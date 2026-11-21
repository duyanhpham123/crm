/* =====================================================================
   MyERP - 42. DỮ LIỆU MẪU ĐỢT 2: Vận chuyển, Kế toán, Báo giá, Trả hàng, CSKH
   Chạy SAU 41_demo_fashion.sql, gắn với các đơn bán / đơn nhập đã có:
   - Vận đơn cho đơn online (GHN, GHTK, SPX, J&T...), COD đã đối soát theo tuần + COD hãng đang giữ
   - Phiếu thu cho đơn đã thanh toán, trả tiền nhà cung cấp, góp vốn, chi phí (thuê nhà, lương, quảng cáo, điện nước)
   - Báo giá đồng phục cho khách doanh nghiệp, phiếu trả hàng, phiếu CSKH
   Chỉ nạp khi đã có đơn bán và chưa có phiếu thu chi / vận đơn.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF NOT EXISTS (SELECT 1 FROM sales.SalesOrders) OR EXISTS (SELECT 1 FROM acc.Payments) OR EXISTS (SELECT 1 FROM lgs.Shipments)
BEGIN
    PRINT N'Bỏ qua dữ liệu mẫu đợt 2 (chưa có đơn bán hoặc đã có phiếu thu chi / vận đơn).';
    RETURN;
END

DECLARE @C BIGINT = (SELECT Id FROM core.Companies WHERE Code = 'ABC');
DECLARE @U BIGINT = (SELECT MIN(Id) FROM core.Users WHERE IsSystemAdmin = 1);
DECLARE @WH BIGINT = (SELECT MIN(Id) FROM inv.Warehouses WHERE CompanyId = @C);
DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
DECLARE @Today DATE = CAST(DATEADD(HOUR, 7, @Now) AS DATE);
DECLARE @Cash BIGINT = (SELECT Id FROM acc.Accounts WHERE CompanyId = @C AND Code = '1111');
DECLARE @Bank BIGINT = (SELECT MIN(Id) FROM acc.BankAccounts WHERE CompanyId = @C);
DECLARE @i INT, @n INT, @Doc VARCHAR(30), @Seq VARCHAR(30), @D DATE, @Id BIGINT;

BEGIN TRAN;

/* =================== 1. VẬN ĐƠN cho đơn online đã xác nhận / hoàn thành =================== */
DECLARE @Carrier TABLE (Code VARCHAR(10) PRIMARY KEY, Id BIGINT);
INSERT @Carrier SELECT Code, Id FROM lgs.Carriers WHERE CompanyId = @C;

CREATE TABLE #S (Seq INT IDENTITY, OrderId BIGINT, OrderDate DATETIME2(0), Carrier BIGINT, CarrierCode VARCHAR(10), Status VARCHAR(12),
    Cod DECIMAL(18,2), Fee DECIMAL(18,2), CodStatus VARCHAR(12), DeliveredAt DATETIME2(0), PickedAt DATETIME2(0), Failed NVARCHAR(200),
    Receiver NVARCHAR(150), Phone VARCHAR(20), Street NVARCHAR(255), Id BIGINT NULL, DocNo VARCHAR(30) NULL);

INSERT #S (OrderId, OrderDate, Carrier, CarrierCode, Status, Cod, Fee, CodStatus, DeliveredAt, PickedAt, Failed, Receiver, Phone, Street)
SELECT o.Id, o.OrderDate, c.Id, c.Code,
       x.Status,
       CASE WHEN o.PaymentMethodCode = 'cod' THEN o.TotalAmount ELSE 0 END,
       CASE c.Code WHEN 'SPX' THEN 18000 WHEN 'JT' THEN 22000 WHEN 'GHN' THEN 28000 ELSE 25000 END,
       CASE WHEN o.PaymentMethodCode <> 'cod' THEN 'none'
            WHEN x.Status <> 'delivered' THEN 'pending'
            WHEN DATEADD(DAY, 2, o.OrderDate) < DATEADD(DAY, -4, @Now) THEN 'reconciled' ELSE 'collected' END,
       CASE WHEN x.Status = 'delivered' THEN CASE WHEN DATEADD(DAY, 2, o.OrderDate) > @Now THEN DATEADD(HOUR, -1, @Now) ELSE DATEADD(DAY, 2, o.OrderDate) END END,
       CASE WHEN x.Status <> 'ready' THEN DATEADD(HOUR, 5, o.OrderDate) END,
       CASE WHEN x.Status = 'failed' THEN N'Khách không nghe máy, hẹn giao lại' END,
       ISNULL(o.ReceiverName, p.Name), ISNULL(o.ReceiverPhone, ISNULL(p.Phone, '0900000000')), ISNULL(o.ShippingStreet, ISNULL(p.Street, N'TP.HCM'))
FROM sales.SalesOrders o
JOIN md.Partners p ON p.Id = o.PartnerId
CROSS APPLY (SELECT CASE o.Channel WHEN 'shopee' THEN 'SPX' WHEN 'tiktok' THEN 'JT'
                     ELSE CASE WHEN o.Id % 2 = 0 THEN 'GHN' ELSE 'GHTK' END END AS Code) cc
JOIN @Carrier c ON c.Code = cc.Code
CROSS APPLY (SELECT CASE WHEN o.Status = 'completed' THEN 'delivered'
                         WHEN o.Id % 5 = 0 THEN 'ready' WHEN o.Id % 5 = 1 THEN 'picked_up' WHEN o.Id % 7 = 3 THEN 'failed'
                         ELSE 'in_transit' END AS Status) x
WHERE o.CompanyId = @C AND o.Channel <> 'direct' AND o.Status IN ('confirmed', 'completed')
ORDER BY o.OrderDate, o.Id;

-- Đơn đã giao nhưng hãng chưa chuyển tiền COD: đơn chưa thu tiền
UPDATE o SET AmountPaid = 0, PaymentStatus = 'unpaid'
FROM sales.SalesOrders o JOIN #S s ON s.OrderId = o.Id WHERE s.CodStatus = 'collected';
UPDATE o SET DeliveryStatus = CASE WHEN s.Status = 'delivered' THEN 'delivered' ELSE 'shipping' END
FROM sales.SalesOrders o JOIN #S s ON s.OrderId = o.Id;

SET @i = 1; SET @n = (SELECT COUNT(*) FROM #S);
WHILE @i <= @n
BEGIN
    SELECT @D = CAST(DATEADD(HOUR, 7, OrderDate) AS DATE) FROM #S WHERE Seq = @i;
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'SHIPMENT', @DocDate = @D, @DocNo = @Doc OUTPUT;
    INSERT lgs.Shipments (CompanyId, DocNo, SalesOrderId, CarrierId, TrackingNo, ServiceType, FromWarehouseId, ReceiverName, ReceiverPhone,
        Street, PackageCount, WeightGram, CodAmount, ShippingFee, FeePayer, Status, CodStatus, PickedUpAt, DeliveredAt, FailedReason, CreatedAt, CreatedBy)
    SELECT @C, @Doc, OrderId, Carrier, CASE WHEN Status = 'ready' THEN NULL ELSE CarrierCode + RIGHT('000000000' + CAST(OrderId * 7919 % 1000000000 AS VARCHAR), 9) END,
        N'Tiêu chuẩn', @WH, Receiver, Phone, Street, 1, 500, Cod, Fee, 'sender', Status, CodStatus, PickedAt, DeliveredAt, Failed,
        DATEADD(MINUTE, 30, OrderDate), @U
    FROM #S WHERE Seq = @i;
    SET @Id = SCOPE_IDENTITY();
    UPDATE #S SET Id = @Id, DocNo = @Doc WHERE Seq = @i;
    SET @i += 1;
END

-- Hành trình
INSERT lgs.ShipmentTrackingEvents (ShipmentId, EventAt, StatusCode, Description)
SELECT s.Id, DATEADD(MINUTE, 30, s.OrderDate), 'ready', N'Tạo vận đơn, chờ hãng lấy hàng' FROM #S s
UNION ALL SELECT s.Id, s.PickedAt, 'picked_up', N'Hãng đã lấy hàng' FROM #S s WHERE s.PickedAt IS NOT NULL
UNION ALL SELECT s.Id, DATEADD(HOUR, 12, s.PickedAt), 'in_transit', N'Đang giao đến người nhận' FROM #S s WHERE s.Status IN ('in_transit', 'delivered', 'failed') AND DATEADD(HOUR, 12, s.PickedAt) < @Now
UNION ALL SELECT s.Id, s.DeliveredAt, 'delivered', N'Giao hàng thành công' FROM #S s WHERE s.Status = 'delivered'
UNION ALL SELECT s.Id, DATEADD(HOUR, -1, @Now), 'failed', s.Failed FROM #S s WHERE s.Status = 'failed';

/* =================== 2. PHIẾU THU CHI =================== */
CREATE TABLE #V (Seq INT IDENTITY, PType VARCHAR(8), Category VARCHAR(30), Method VARCHAR(20), IsBank BIT, PartnerId BIGINT NULL,
    PDate DATE, Amount DECIMAL(18,2), Reason NVARCHAR(500), Person NVARCHAR(150) NULL, OrderId BIGINT NULL, PoId BIGINT NULL);

-- 2a. Góp vốn ban đầu
INSERT #V (PType, Category, Method, IsBank, PDate, Amount, Reason, Person) VALUES
 ('receipt', 'other_income', 'bank_transfer', 1, DATEADD(DAY, -64, @Today), 400000000, N'Chủ shop góp vốn kinh doanh', N'Chủ cửa hàng'),
 ('receipt', 'other_income', 'cash', 0, DATEADD(DAY, -64, @Today), 30000000, N'Nạp quỹ tiền mặt đầu kỳ', N'Chủ cửa hàng');

-- 2b. Thu tiền đơn bán tại quầy (tiền mặt / chuyển khoản) và đơn sàn (sàn chuyển tiền sau khi giao)
INSERT #V (PType, Category, Method, IsBank, PartnerId, PDate, Amount, Reason, OrderId)
SELECT 'receipt', 'customer', o.PaymentMethodCode, CASE WHEN o.PaymentMethodCode = 'cash' THEN 0 ELSE 1 END, o.PartnerId,
       CASE WHEN o.PaymentMethodCode = 'ewallet'
            THEN CASE WHEN DATEADD(DAY, 5, CAST(DATEADD(HOUR, 7, o.OrderDate) AS DATE)) > @Today THEN @Today ELSE DATEADD(DAY, 5, CAST(DATEADD(HOUR, 7, o.OrderDate) AS DATE)) END
            ELSE CAST(DATEADD(HOUR, 7, o.OrderDate) AS DATE) END,
       o.AmountPaid,
       CASE WHEN o.PaymentMethodCode = 'ewallet' THEN CASE o.Channel WHEN 'shopee' THEN N'Shopee thanh toán đơn ' ELSE N'TikTok Shop thanh toán đơn ' END
            ELSE N'Thu tiền đơn ' END + o.DocNo, o.Id
FROM sales.SalesOrders o
WHERE o.CompanyId = @C AND o.AmountPaid > 0 AND o.PaymentMethodCode IN ('cash', 'bank_transfer', 'card', 'ewallet');

-- 2c. Đối soát COD theo tuần, mỗi hãng: 1 phiếu báo có tiền COD + 1 phiếu chi phí ship
INSERT #V (PType, Category, Method, IsBank, PDate, Amount, Reason, Person)
SELECT 'receipt', 'cod', 'bank_transfer', 1, w.PayDate, SUM(s.Cod),
       c.Name + N' chuyển tiền COD tuần ' + CONVERT(VARCHAR(5), w.WeekStart, 103) + N' (' + CAST(COUNT(*) AS NVARCHAR) + N' vận đơn)', c.Name
FROM #S s JOIN lgs.Carriers c ON c.Id = s.Carrier
CROSS APPLY (SELECT DATEADD(DAY, -((DATEPART(WEEKDAY, CAST(DATEADD(HOUR, 7, s.DeliveredAt) AS DATE)) + 5) % 7), CAST(DATEADD(HOUR, 7, s.DeliveredAt) AS DATE)) AS WeekStart) ws
CROSS APPLY (SELECT ws.WeekStart, CASE WHEN DATEADD(DAY, 9, ws.WeekStart) > @Today THEN @Today ELSE DATEADD(DAY, 9, ws.WeekStart) END AS PayDate) w
WHERE s.CodStatus = 'reconciled'
GROUP BY c.Name, w.WeekStart, w.PayDate;

INSERT #V (PType, Category, Method, IsBank, PDate, Amount, Reason, Person)
SELECT 'payment', 'shipping', 'bank_transfer', 1, w.PayDate, SUM(s.Fee),
       N'Phí vận chuyển ' + c.Name + N' tuần ' + CONVERT(VARCHAR(5), w.WeekStart, 103), c.Name
FROM #S s JOIN lgs.Carriers c ON c.Id = s.Carrier
CROSS APPLY (SELECT DATEADD(DAY, -((DATEPART(WEEKDAY, CAST(DATEADD(HOUR, 7, ISNULL(s.DeliveredAt, s.PickedAt)) AS DATE)) + 5) % 7), CAST(DATEADD(HOUR, 7, ISNULL(s.DeliveredAt, s.PickedAt)) AS DATE)) AS WeekStart) ws
CROSS APPLY (SELECT ws.WeekStart, CASE WHEN DATEADD(DAY, 9, ws.WeekStart) > @Today THEN @Today ELSE DATEADD(DAY, 9, ws.WeekStart) END AS PayDate) w
WHERE s.Status = 'delivered' AND DATEADD(DAY, 9, ws.WeekStart) <= @Today
GROUP BY c.Name, w.WeekStart, w.PayDate;

-- 2d. Trả tiền nhà cung cấp: đơn đợt 1 trả đủ, đợt 2 trả 50%, đơn đang chờ hàng đặt cọc 30%
INSERT #V (PType, Category, Method, IsBank, PartnerId, PDate, Amount, Reason, PoId)
SELECT 'payment', 'supplier', 'bank_transfer', 1, po.PartnerId,
       CASE WHEN DATEADD(DAY, 7, po.OrderDate) > @Today THEN @Today ELSE DATEADD(DAY, 7, po.OrderDate) END,
       CASE WHEN po.Status = 'confirmed' THEN ROUND(po.TotalAmount * 0.3, -3)
            WHEN po.OrderDate < DATEADD(DAY, -40, @Today) THEN po.TotalAmount ELSE ROUND(po.TotalAmount * 0.5, -3) END,
       CASE WHEN po.Status = 'confirmed' THEN N'Đặt cọc đơn nhập ' ELSE N'Thanh toán đơn nhập ' END + po.DocNo, po.Id
FROM pur.PurchaseOrders po WHERE po.CompanyId = @C AND po.Status IN ('completed', 'confirmed');

-- 2e. Chi phí hoạt động 2 tháng
INSERT #V (PType, Category, Method, IsBank, PDate, Amount, Reason, Person)
SELECT v.PType, v.Category, v.Method, v.IsBank, DATEADD(DAY, -v.DaysAgo, @Today), v.Amount, v.Reason, v.Person
FROM (VALUES
 ('payment', 'rent', 'bank_transfer', 1, 60, 15000000, N'Tiền thuê mặt bằng cửa hàng tháng 10', N'Chủ nhà - Ông Tuấn'),
 ('payment', 'rent', 'bank_transfer', 1, 30, 15000000, N'Tiền thuê mặt bằng cửa hàng tháng 11', N'Chủ nhà - Ông Tuấn'),
 ('payment', 'salary', 'bank_transfer', 1, 35, 24000000, N'Lương tháng 10 (3 nhân viên bán hàng)', NULL),
 ('payment', 'salary', 'bank_transfer', 1, 5, 24500000, N'Lương tháng 11 (3 nhân viên bán hàng)', NULL),
 ('payment', 'utilities', 'cash', 0, 40, 2350000, N'Tiền điện, nước, internet tháng 10', N'EVN, VNPT'),
 ('payment', 'utilities', 'cash', 0, 10, 2480000, N'Tiền điện, nước, internet tháng 11', N'EVN, VNPT'),
 ('payment', 'other_expense', 'cash', 0, 55, 3200000, N'Mua móc treo, túi giấy, tem nhãn', N'Cửa hàng bao bì Minh Phát'),
 ('payment', 'other_expense', 'cash', 0, 18, 1500000, N'Mua băng keo, hộp carton đóng hàng', N'Cửa hàng bao bì Minh Phát')
) v(PType, Category, Method, IsBank, DaysAgo, Amount, Reason, Person);
-- Quảng cáo Facebook / TikTok mỗi tuần
INSERT #V (PType, Category, Method, IsBank, PDate, Amount, Reason, Person)
SELECT 'payment', 'marketing', 'card', 1, DATEADD(DAY, -w * 7, @Today), 1800000 + (w % 3) * 400000,
       CASE WHEN w % 2 = 0 THEN N'Chạy quảng cáo Facebook' ELSE N'Chạy quảng cáo TikTok' END + N' tuần ' + CAST(9 - w AS NVARCHAR), N'Meta / TikTok'
FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8)) x(w);

-- Gán số phiếu theo đúng loại quỹ + ngày rồi ghi sổ
ALTER TABLE #V ADD DocNo VARCHAR(30) NULL;
DECLARE vc CURSOR LOCAL FAST_FORWARD FOR SELECT Seq FROM #V ORDER BY PDate, Seq;
OPEN vc; FETCH NEXT FROM vc INTO @i;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @D = PDate, @Seq = CASE WHEN PType = 'receipt' AND IsBank = 0 THEN 'CASH_RECEIPT' WHEN PType = 'receipt' THEN 'BANK_RECEIPT'
                                   WHEN IsBank = 0 THEN 'CASH_PAYMENT' ELSE 'BANK_PAYMENT' END FROM #V WHERE Seq = @i;
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = @Seq, @DocDate = @D, @DocNo = @Doc OUTPUT;
    UPDATE #V SET DocNo = @Doc WHERE Seq = @i;
    FETCH NEXT FROM vc INTO @i;
END
CLOSE vc; DEALLOCATE vc;

INSERT acc.Payments (CompanyId, DocNo, PaymentType, PaymentMethodCode, PartnerId, PaymentDate, Amount, BankAccountId, CashAccountId,
    Reason, PersonName, Status, Category, SalesOrderId, PurchaseOrderId, CreatedAt, CreatedBy)
SELECT @C, DocNo, PType, Method, PartnerId, PDate, Amount, CASE WHEN IsBank = 1 THEN @Bank END, CASE WHEN IsBank = 0 THEN @Cash END,
       Reason, Person, 'posted', Category, OrderId, PoId, DATEADD(HOUR, 3, CAST(PDate AS DATETIME2)), @U
FROM #V;

UPDATE po SET AmountPaid = v.Amount
FROM pur.PurchaseOrders po JOIN #V v ON v.PoId = po.Id;

/* =================== 3. BÁO GIÁ đồng phục cho khách doanh nghiệp =================== */
DECLARE @Q TABLE (Seq INT IDENTITY, PartnerCode VARCHAR(20), DaysAgo INT, Valid INT, Status VARCHAR(12), Sku1 VARCHAR(50), Qty1 INT,
    Sku2 VARCHAR(50) NULL, Qty2 INT NULL, Disc DECIMAL(9,2), Reason NVARCHAR(200) NULL, Id BIGINT NULL, DocNo VARCHAR(30) NULL);
INSERT @Q (PartnerCode, DaysAgo, Valid, Status, Sku1, Qty1, Sku2, Qty2, Disc, Reason) VALUES
 ('KH-000001', 40, 15, 'accepted', 'ATP02-TRANG-L',   40, 'ATP02-XANHNAVY-M', 30, 15, NULL),
 ('KH-000002', 28, 15, 'rejected', 'ASM04-TRANG-M',   25, 'ASM04-TRANG-L',    25, 10, N'Khách chọn đơn vị khác giá rẻ hơn'),
 ('KH-000003', 20, 10, 'sent',     'ATP02-TRANG-M',   60, NULL, NULL, 12, NULL),          -- quá hạn
 ('KH-000005', 9,  15, 'sent',     'AKG13-HONG-FREESIZE', 30, 'MLT19-DEN-FREESIZE', 30, 10, NULL),
 ('KH-000006', 6,  15, 'sent',     'ATB01-DEN-L',     50, 'ATB01-TRANG-L',    50, 15, NULL),
 ('KH-000008', 4,  15, 'accepted', 'ATP02-DEN-L',     20, 'QKK08-DEN-31',     20, 10, NULL),
 ('KH-000004', 2,  15, 'draft',    'ASM04-XANHDUON-L', 35, 'QKK08-BE-32',     35, 12, NULL),
 ('KH-000001', 1,  20, 'draft',    'AKB12-DEN-L',     30, NULL, NULL, 10, NULL);

CREATE TABLE #QL (QSeq INT, Ln INT, ProductId BIGINT, UomId BIGINT, Name NVARCHAR(255), Qty DECIMAL(18,4), Price DECIMAL(18,4), Disc DECIMAL(9,4));
INSERT #QL SELECT q.Seq, 1, p.Id, p.UomId, p.Name, q.Qty1, p.SalePrice, q.Disc FROM @Q q JOIN md.Products p ON p.Code = q.Sku1
UNION ALL SELECT q.Seq, 2, p.Id, p.UomId, p.Name, q.Qty2, p.SalePrice, q.Disc FROM @Q q JOIN md.Products p ON p.Code = q.Sku2;

DECLARE @QDate DATE, @QId BIGINT, @Partner BIGINT, @QStatus VARCHAR(12), @OrderDoc VARCHAR(30), @OrderId BIGINT;
SET @i = 1; SET @n = (SELECT COUNT(*) FROM @Q);
WHILE @i <= @n
BEGIN
    SELECT @QDate = DATEADD(DAY, -DaysAgo, @Today), @QStatus = Status, @Partner = (SELECT Id FROM md.Partners WHERE CompanyId = @C AND Code = q.PartnerCode)
    FROM @Q q WHERE Seq = @i;
    IF @Partner IS NOT NULL AND EXISTS (SELECT 1 FROM #QL WHERE QSeq = @i)
    BEGIN
        EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'QUOTATION', @DocDate = @QDate, @DocNo = @Doc OUTPUT;
        INSERT sales.Quotations (CompanyId, DocNo, PartnerId, QuoteDate, ValidUntil, SalespersonUserId, Status, SubTotal, DiscountAmount, TaxAmount,
            ShippingFee, TotalAmount, Terms, Note, SentAt, AcceptedAt, RejectedReason, CreatedAt, CreatedBy)
        SELECT @C, @Doc, @Partner, @QDate, DATEADD(DAY, q.Valid, @QDate), @U, q.Status, t.Sub, 0, 0, 0, t.Sub,
               N'Giá đã bao gồm VAT. In logo công ty miễn phí từ 30 áo.' + CHAR(10) + N'Thanh toán: chuyển khoản 50% khi đặt, 50% khi nhận hàng.' + CHAR(10) + N'Giao hàng trong 7 ngày làm việc.',
               N'Đồng phục nhân viên', CASE WHEN q.Status <> 'draft' THEN DATEADD(HOUR, 2, CAST(@QDate AS DATETIME2)) END,
               CASE WHEN q.Status = 'accepted' THEN DATEADD(DAY, 2, CAST(@QDate AS DATETIME2)) END, q.Reason,
               CAST(@QDate AS DATETIME2), @U
        FROM @Q q CROSS APPLY (SELECT SUM(ROUND(Qty * Price * (1 - Disc / 100), 0)) AS Sub FROM #QL WHERE QSeq = q.Seq) t
        WHERE q.Seq = @i;
        SET @QId = SCOPE_IDENTITY();
        UPDATE @Q SET Id = @QId, DocNo = @Doc WHERE Seq = @i;
        INSERT sales.QuotationLines (QuotationId, LineNumber, ProductId, Description, UomId, Quantity, UnitPrice, DiscountPercent, DiscountAmount,
            TaxRate, LineSubTotal, LineTax, LineTotal)
        SELECT @QId, Ln, ProductId, Name, UomId, Qty, Price, Disc, ROUND(Qty * Price * Disc / 100, 0), 0,
               ROUND(Qty * Price * (1 - Disc / 100), 0), 0, ROUND(Qty * Price * (1 - Disc / 100), 0)
        FROM #QL WHERE QSeq = @i;

        -- Báo giá khách đồng ý -> đơn hàng nháp (chờ khách chuyển cọc để xác nhận)
        IF @QStatus = 'accepted'
        BEGIN
            SET @D = DATEADD(DAY, 2, @QDate);
            EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'SALES_ORDER', @DocDate = @D, @DocNo = @OrderDoc OUTPUT;
            INSERT sales.SalesOrders (CompanyId, DocNo, QuotationId, PartnerId, OrderDate, Channel, WarehouseId, SalespersonUserId, PaymentMethodCode,
                ReceiverName, ReceiverPhone, ShippingStreet, Status, SubTotal, DiscountAmount, TaxAmount, ShippingFee, TotalAmount, Note, CreatedAt, CreatedBy)
            SELECT @C, @OrderDoc, q.Id, @Partner, DATEADD(HOUR, 2, CAST(@D AS DATETIME2(0))), 'other', @WH, @U, 'bank_transfer',
                   p.Name, p.Phone, p.Street, 'draft', qq.SubTotal, 0, 0, 0, qq.TotalAmount, N'Tạo từ báo giá ' + q.DocNo, DATEADD(HOUR, 2, CAST(@D AS DATETIME2)), @U
            FROM @Q q JOIN sales.Quotations qq ON qq.Id = q.Id JOIN md.Partners p ON p.Id = @Partner WHERE q.Seq = @i;
            SET @OrderId = SCOPE_IDENTITY();
            INSERT sales.SalesOrderLines (SalesOrderId, LineNumber, ProductId, Description, UomId, Quantity, UnitPrice, DiscountPercent, DiscountAmount,
                TaxRate, LineSubTotal, LineTax, LineTotal, UnitCost, QtyDelivered)
            SELECT @OrderId, LineNumber, ProductId, Description, UomId, Quantity, UnitPrice, DiscountPercent, DiscountAmount, 0, LineSubTotal, 0, LineTotal, 0, 0
            FROM sales.QuotationLines WHERE QuotationId = @QId;
        END
    END
    SET @i += 1;
END

/* =================== 4. TRẢ HÀNG: 3 đơn hoàn thành tại cửa hàng, khách đổi ý / không vừa size =================== */
DECLARE @R TABLE (Seq INT IDENTITY, OrderId BIGINT, LineId BIGINT, ProductId BIGINT, UomId BIGINT, UnitCost DECIMAL(18,4), Price DECIMAL(18,4),
    Cond VARCHAR(10), Reason NVARCHAR(200), RetDate DATETIME2(0));
INSERT @R (OrderId, LineId, ProductId, UomId, UnitCost, Price, Cond, Reason, RetDate)
SELECT TOP 3 o.Id, l.Id, l.ProductId, l.UomId, l.UnitCost, l.LineTotal / l.Quantity,
       CASE WHEN ROW_NUMBER() OVER (ORDER BY o.OrderDate DESC) = 2 THEN 'damaged' ELSE 'good' END,
       CASE ROW_NUMBER() OVER (ORDER BY o.OrderDate DESC) WHEN 1 THEN N'Không vừa size, khách lấy tiền lại' WHEN 2 THEN N'Lỗi đường may ở tay áo' ELSE N'Khách đổi ý' END,
       DATEADD(DAY, 1, o.OrderDate)
FROM sales.SalesOrders o
CROSS APPLY (SELECT TOP 1 * FROM sales.SalesOrderLines x WHERE x.SalesOrderId = o.Id ORDER BY x.LineNumber) l
WHERE o.CompanyId = @C AND o.Channel = 'direct' AND o.PaymentMethodCode = 'cash' AND o.Status = 'completed' AND o.QuotationId IS NULL
  AND o.OrderDate BETWEEN DATEADD(DAY, -30, @Now) AND DATEADD(DAY, -3, @Now) AND l.Quantity = 1 AND o.DiscountAmount = 0
ORDER BY o.OrderDate DESC;

DECLARE @RetId BIGINT, @RetDoc VARCHAR(30), @StockDoc BIGINT, @RetDate DATETIME2(0), @ROrder BIGINT, @RPartner BIGINT, @RValue DECIMAL(18,2), @ODoc VARCHAR(30);
SET @i = 1; SET @n = (SELECT COUNT(*) FROM @R);
WHILE @i <= @n
BEGIN
    SELECT @RetDate = r.RetDate, @ROrder = r.OrderId, @RPartner = o.PartnerId, @RValue = ROUND(r.Price, 0), @ODoc = o.DocNo, @D = CAST(DATEADD(HOUR, 7, r.RetDate) AS DATE)
    FROM @R r JOIN sales.SalesOrders o ON o.Id = r.OrderId WHERE r.Seq = @i;
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'SALES_RETURN', @DocDate = @D, @DocNo = @RetDoc OUTPUT;
    INSERT sales.SalesReturns (CompanyId, DocNo, SalesOrderId, PartnerId, WarehouseId, ReturnDate, Reason, RefundMethod, Status, SubTotal, TaxAmount, TotalAmount, CreatedAt, CreatedBy)
    SELECT @C, @RetDoc, @ROrder, @RPartner, @WH, @RetDate, Reason, 'cash', 'refunded', @RValue, 0, @RValue, @RetDate, @U FROM @R WHERE Seq = @i;
    SET @RetId = SCOPE_IDENTITY();
    INSERT sales.SalesReturnLines (SalesReturnId, SalesOrderLineId, ProductId, Quantity, UnitPrice, TaxRate, LineTotal, Condition)
    SELECT @RetId, LineId, ProductId, 1, Price, 0, @RValue, Cond FROM @R WHERE Seq = @i;

    IF EXISTS (SELECT 1 FROM @R WHERE Seq = @i AND Cond = 'good')
    BEGIN
        EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'STOCK_RECEIPT', @DocDate = @D, @DocNo = @Doc OUTPUT;
        INSERT inv.StockDocuments (CompanyId, DocNo, DocType, Reason, WarehouseId, PartnerId, SourceType, SourceId, SourceDocNo, DocDate, Status, Note,
            TotalQuantity, TotalValue, DoneAt, DoneBy, CreatedAt, CreatedBy)
        SELECT @C, @Doc, 'receipt', 'sale_return', @WH, @RPartner, 'sales.SalesReturns', @RetId, @RetDoc, @RetDate, 'done',
               N'Khách trả hàng ' + @RetDoc + N' - đơn ' + @ODoc, 1, UnitCost, @RetDate, @U, @RetDate, @U FROM @R WHERE Seq = @i;
        SET @StockDoc = SCOPE_IDENTITY();
        UPDATE sales.SalesReturns SET StockDocumentId = @StockDoc WHERE Id = @RetId;
        INSERT inv.StockDocumentLines (DocumentId, LineNumber, ProductId, UomId, Quantity, BaseQuantity, UnitCost, LineValue, SourceLineId)
        SELECT @StockDoc, 1, ProductId, UomId, 1, 1, UnitCost, UnitCost, LineId FROM @R WHERE Seq = @i;
        INSERT inv.StockLedger (CompanyId, ProductId, WarehouseId, MoveDate, QtyIn, QtyOut, UnitCost, ValueIn, ValueOut, StockDocumentId, StockDocumentLineId)
        SELECT @C, l.ProductId, @WH, @RetDate, 1, 0, l.UnitCost, l.LineValue, 0, @StockDoc, l.Id FROM inv.StockDocumentLines l WHERE l.DocumentId = @StockDoc;
        UPDATE b SET AvgCost = CASE WHEN b.QtyOnHand <= 0 THEN r.UnitCost ELSE ROUND((b.QtyOnHand * b.AvgCost + r.UnitCost) / (b.QtyOnHand + 1), 4) END,
                     QtyOnHand = b.QtyOnHand + 1, UpdatedAt = @Now
        FROM inv.StockBalances b JOIN @R r ON r.ProductId = b.ProductId AND r.Seq = @i WHERE b.WarehouseId = @WH;
    END

    UPDATE sales.SalesOrders SET ReturnedAmount = ReturnedAmount + @RValue, TotalAmount = TotalAmount - @RValue, AmountPaid = AmountPaid - @RValue WHERE Id = @ROrder;
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'CASH_PAYMENT', @DocDate = @D, @DocNo = @Doc OUTPUT;
    INSERT acc.Payments (CompanyId, DocNo, PaymentType, PaymentMethodCode, PartnerId, PaymentDate, Amount, CashAccountId, Reason, Status, Category, SalesOrderId, CreatedAt, CreatedBy)
    VALUES (@C, @Doc, 'payment', 'cash', @RPartner, @D, @RValue, @Cash, N'Hoàn tiền trả hàng ' + @RetDoc + N' - đơn ' + @ODoc, 'posted', 'refund', @ROrder, @RetDate, @U);
    SET @i += 1;
END

/* =================== 5. CSKH: phiếu hỗ trợ =================== */
DECLARE @T TABLE (Seq INT IDENTITY, Subject NVARCHAR(255), Descr NVARCHAR(1000), Cat NVARCHAR(100), Channel VARCHAR(10), Priority VARCHAR(8),
    Status VARCHAR(10), HoursAgo INT, Reply NVARCHAR(500) NULL, Note NVARCHAR(500) NULL, Resolution NVARCHAR(500) NULL, Score TINYINT NULL, OrderPick INT);
INSERT @T VALUES
 (N'Áo bị lỗi đường may ở tay', N'Khách nhận hàng thấy đường may tay áo bị bung, muốn đổi cái mới.', N'Đổi trả', 'zalo', 'high', 'resolved', 240,
  N'Shop xin lỗi chị, shop gửi áo mới và nhận lại áo lỗi, chị không mất phí ship ạ.', N'Đã báo xưởng kiểm tra lô áo này', N'Đổi áo mới, shop chịu phí ship 2 chiều', 5, 1),
 (N'Giao thiếu 1 mũ trong đơn', N'Đơn có 2 sản phẩm nhưng khách chỉ nhận được áo, thiếu mũ.', N'Khiếu nại', 'facebook', 'high', 'resolved', 180,
  N'Shop kiểm tra camera đóng gói, đúng là thiếu. Shop gửi bù mũ trong hôm nay ạ.', NULL, N'Gửi bù mũ qua GHN, tặng voucher 50k', 4, 2),
 (N'Hỏi bảng size quần jeans', N'Khách cao 1m70 nặng 65kg hỏi nên mặc size nào.', N'Hỗ trợ sử dụng', 'zalo', 'low', 'closed', 300,
  N'Với chiều cao cân nặng này anh mặc size 30 vừa đẹp ạ.', NULL, N'Tư vấn size 30', 5, 0),
 (N'Giày sneaker bị ố vàng sau 2 tuần', N'Khách phản ánh đế giày bị ố vàng, muốn bảo hành.', N'Bảo hành', 'phone', 'normal', 'open', 30,
  N'Shop đã nhận thông tin, chị gửi giúp shop vài ảnh đế giày ạ.', N'Chờ ảnh để gửi NCC Bình Tiên xem', NULL, NULL, 3),
 (N'Muốn đổi sang size L', N'Khách mua áo polo size M nhưng mặc chật, muốn đổi L.', N'Đổi trả', 'walk_in', 'normal', 'pending', 20,
  N'Size L màu trắng shop còn hàng, anh mang áo qua cửa hàng đổi giúp shop nhé.', NULL, NULL, NULL, 4),
 (N'Đơn chưa nhận được sau 5 ngày', N'Khách đặt trên website 5 ngày chưa nhận được hàng.', N'Khiếu nại', 'web', 'urgent', 'open', 26,
  NULL, N'Đã gọi GHTK, hàng đang ở kho trung chuyển', NULL, NULL, 5),
 (N'Hỏi chính sách mua sỉ', N'Chủ shop ở Đà Nẵng muốn lấy sỉ 100 áo thun.', N'Hỗ trợ sử dụng', 'phone', 'normal', 'new', 3, NULL, NULL, NULL, NULL, 0),
 (N'Váy bị phai màu sau lần giặt đầu', N'Khách giặt máy lần đầu thì váy bị phai màu.', N'Khiếu nại', 'facebook', 'high', 'new', 9, NULL, NULL, NULL, NULL, 6),
 (N'Góp ý: nên có thêm size XXL áo khoác', N'Khách to người muốn mua áo khoác bomber size XXL.', N'Góp ý', 'facebook', 'low', 'closed', 500,
  N'Cảm ơn anh đã góp ý, đợt hàng tới shop sẽ nhập thêm size XXL ạ.', NULL, N'Ghi nhận, đề xuất nhập thêm size XXL', 4, 0),
 (N'Hoàn tiền đơn hủy trên Shopee', N'Khách hủy đơn trên Shopee nhưng chưa thấy tiền hoàn.', N'Khiếu nại', 'other', 'normal', 'resolved', 120,
  N'Đơn hủy trên Shopee sẽ được Shopee hoàn về ví trong 3-5 ngày ạ.', NULL, N'Hướng dẫn khách kiểm tra ví ShopeePay', 3, 0);

DECLARE @Cat BIGINT, @TOrder BIGINT, @TPartner BIGINT, @Created DATETIME2(3), @Pri VARCHAR(8), @Sla BIGINT, @Fr INT, @Rs INT, @TId BIGINT, @Pick INT;
SET @i = 1; SET @n = (SELECT COUNT(*) FROM @T);
WHILE @i <= @n
BEGIN
    SELECT @Created = DATEADD(HOUR, -HoursAgo, @Now), @Pri = Priority, @Pick = OrderPick,
           @Cat = (SELECT Id FROM cs.TicketCategories c WHERE c.CompanyId = @C AND c.Name = t.Cat) FROM @T t WHERE Seq = @i;
    SELECT @Sla = Id, @Fr = FirstResponseMinutes, @Rs = ResolutionMinutes FROM cs.SlaPolicies WHERE CompanyId = @C AND Priority = @Pri;
    SET @TOrder = NULL; SET @TPartner = NULL;
    IF @Pick > 0
        SELECT @TOrder = Id, @TPartner = PartnerId FROM (
            SELECT Id, PartnerId, ROW_NUMBER() OVER (ORDER BY OrderDate DESC) rn FROM sales.SalesOrders
            WHERE CompanyId = @C AND Channel <> 'direct' AND Status IN ('confirmed', 'completed') AND OrderDate < @Created) x WHERE rn = @Pick * 3;
    IF @TPartner IS NULL SELECT @TPartner = MIN(Id) + (@i % 10) FROM md.Partners WHERE CompanyId = @C AND Code LIKE 'KH-%' AND PartnerType = 'individual';
    SET @D = CAST(DATEADD(HOUR, 7, @Created) AS DATE);
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'TICKET', @DocDate = @D, @DocNo = @Doc OUTPUT;
    INSERT cs.Tickets (CompanyId, Code, Subject, Description, PartnerId, SalesOrderId, CategoryId, Channel, Priority, Status, AssignedUserId, SlaPolicyId,
        FirstResponseDueAt, ResolutionDueAt, FirstRespondedAt, ResolvedAt, ClosedAt, Resolution, SatisfactionScore, CreatedAt, CreatedBy)
    SELECT @C, @Doc, Subject, Descr, @TPartner, @TOrder, @Cat, Channel, Priority, Status, CASE WHEN Status = 'new' THEN NULL ELSE @U END, @Sla,
           DATEADD(MINUTE, @Fr, @Created), DATEADD(MINUTE, @Rs, @Created),
           CASE WHEN Reply IS NOT NULL THEN DATEADD(MINUTE, 25, @Created) END,
           CASE WHEN Status IN ('resolved', 'closed') THEN DATEADD(HOUR, 6, @Created) END,
           CASE WHEN Status = 'closed' THEN DATEADD(HOUR, 30, @Created) END, Resolution, Score, @Created, @U
    FROM @T WHERE Seq = @i;
    SET @TId = SCOPE_IDENTITY();
    INSERT cs.TicketMessages (TicketId, AuthorUserId, Body, IsInternal, CreatedAt)
    SELECT @TId, @U, Note, 1, DATEADD(MINUTE, 10, @Created) FROM @T WHERE Seq = @i AND Note IS NOT NULL
    UNION ALL SELECT @TId, @U, Reply, 0, DATEADD(MINUTE, 25, @Created) FROM @T WHERE Seq = @i AND Reply IS NOT NULL;
    SET @i += 1;
END

COMMIT;
DROP TABLE #S; DROP TABLE #V; DROP TABLE #QL;

DECLARE @Ships INT = (SELECT COUNT(*) FROM lgs.Shipments), @Vouchers INT = (SELECT COUNT(*) FROM acc.Payments),
        @Quotes INT = (SELECT COUNT(*) FROM sales.Quotations), @Tickets INT = (SELECT COUNT(*) FROM cs.Tickets);
PRINT N'Đã thêm ' + CAST(@Ships AS NVARCHAR) + N' vận đơn, ' + CAST(@Vouchers AS NVARCHAR) + N' phiếu thu chi, '
    + CAST(@Quotes AS NVARCHAR) + N' báo giá, ' + CAST(@Tickets AS NVARCHAR) + N' phiếu CSKH.';
GO
