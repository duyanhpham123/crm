/* =====================================================================
   MyERP - 41. DỮ LIỆU MẪU SHOP THỜI TRANG (chỉ để dùng thử, KHÔNG chạy trên production)
   - 13 nhóm hàng, 5 thương hiệu, 20 mẫu sản phẩm (168 SKU theo màu × size)
   - 4 nhà cung cấp, đơn nhập hàng (đã nhận / chờ hàng / nháp)
   - ~170 đơn bán trong 60 ngày qua nhiều kênh (cửa hàng, Shopee, TikTok, Facebook...)
   Tồn kho được sinh ĐÚNG như vận hành thật: phiếu nhập theo đơn mua, phiếu xuất theo đơn bán,
   sổ kho đầy đủ, tồn = nhập - xuất. Chỉ nạp khi chưa có sản phẩm nào.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS (SELECT 1 FROM md.ProductModels)
BEGIN
    PRINT N'Đã có sản phẩm, bỏ qua dữ liệu mẫu thời trang.';
    RETURN;
END

DECLARE @C BIGINT = (SELECT Id FROM core.Companies WHERE Code = 'ABC');
DECLARE @U BIGINT = (SELECT MIN(Id) FROM core.Users WHERE IsSystemAdmin = 1);
DECLARE @WH BIGINT = (SELECT MIN(Id) FROM inv.Warehouses WHERE CompanyId = @C);
DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
DECLARE @Today DATE = CAST(DATEADD(HOUR, 7, @Now) AS DATE);
DECLARE @UomCai BIGINT = (SELECT Id FROM md.UnitsOfMeasure WHERE CompanyId IS NULL AND Code = 'CAI');
DECLARE @UomDoi BIGINT = (SELECT Id FROM md.UnitsOfMeasure WHERE CompanyId IS NULL AND Code = 'DOI');
DECLARE @UomBo  BIGINT = (SELECT Id FROM md.UnitsOfMeasure WHERE CompanyId IS NULL AND Code = 'BO');
DECLARE @Code VARCHAR(50), @i INT, @n INT, @Id BIGINT, @Date DATE;

BEGIN TRAN;

/* ---------- 1. Nhóm hàng, thương hiệu ---------- */
INSERT md.ProductCategories (CompanyId, Code, Name, SortOrder)
SELECT @C, v.Code, v.Name, v.SortOrder FROM (VALUES
 ('AOTHUN', N'Áo thun', 10), ('SOMI', N'Áo sơ mi', 20), ('JEANS', N'Quần jeans', 30), ('KAKI', N'Quần kaki', 40),
 ('SHORT', N'Quần short', 50), ('VAY', N'Váy đầm', 60), ('KHOAC', N'Áo khoác', 70), ('SNEAKER', N'Giày sneaker', 80),
 ('GIAYNU', N'Giày nữ', 90), ('GIAYNAM', N'Giày nam', 100), ('DEP', N'Dép sandal', 110), ('TUI', N'Túi xách', 120),
 ('PHUKIEN', N'Phụ kiện', 130)) v(Code, Name, SortOrder)
WHERE NOT EXISTS (SELECT 1 FROM md.ProductCategories c WHERE c.CompanyId = @C AND c.Code = v.Code);

INSERT md.Brands (CompanyId, Name)
SELECT @C, v.Name FROM (VALUES (N'MyStyle'), (N'Urban'), (N'Elegant'), (N'Denim Co'), (N'Stepup')) v(Name)
WHERE NOT EXISTS (SELECT 1 FROM md.Brands b WHERE b.CompanyId = @C AND b.Name = v.Name);

/* ---------- 2. Mẫu sản phẩm + biến thể ---------- */
DECLARE @Color TABLE (Name NVARCHAR(50) PRIMARY KEY, Part VARCHAR(8));   -- khớp ProductModel.CodePart() ở backend
INSERT @Color VALUES (N'Đen','DEN'), (N'Trắng','TRANG'), (N'Xám','XAM'), (N'Be','BE'), (N'Nâu','NAU'), (N'Xanh navy','XANHNAVY'),
 (N'Xanh dương','XANHDUON'), (N'Xanh rêu','XANHREU'), (N'Hồng','HONG'), (N'Kem','KEM'), (N'Xanh jean','XANHJEAN'), (N'Xanh nhạt','XANHNHAT');

DECLARE @M TABLE (Seq INT IDENTITY, Code VARCHAR(30), Name NVARCHAR(255), Cat VARCHAR(20), Brand NVARCHAR(50), Uom BIGINT,
    Price DECIMAL(18,0), Cost DECIMAL(18,0), Gender VARCHAR(10), Material NVARCHAR(100), Colors NVARCHAR(200), Sizes VARCHAR(100),
    Pop INT, Supplier INT, Id BIGINT NULL);
INSERT @M (Code, Name, Cat, Brand, Uom, Price, Cost, Gender, Material, Colors, Sizes, Pop, Supplier) VALUES
 ('ATB01', N'Áo thun basic cổ tròn',     'AOTHUN',  N'MyStyle',  @UomCai, 159000,  65000, 'unisex', N'Cotton 100%',      N'Đen,Trắng,Xám,Xanh navy', 'S,M,L,XL',        3, 1),
 ('ATP02', N'Áo polo pique',             'AOTHUN',  N'MyStyle',  @UomCai, 249000, 105000, 'men',    N'Cotton pique',     N'Trắng,Đen,Xanh navy',     'M,L,XL,XXL',      2, 1),
 ('ATO03', N'Áo thun oversize in chữ',   'AOTHUN',  N'Urban',    @UomCai, 199000,  80000, 'unisex', N'Cotton 2 chiều',   N'Đen,Trắng,Be',            'M,L,XL',          3, 1),
 ('ASM04', N'Áo sơ mi trắng công sở',    'SOMI',    N'Elegant',  @UomCai, 329000, 140000, 'men',    N'Kate lụa',         N'Trắng,Xanh dương',        'S,M,L,XL',        2, 2),
 ('ASN05', N'Áo sơ mi nữ lụa',           'SOMI',    N'Elegant',  @UomCai, 359000, 150000, 'women',  N'Lụa tơ tằm',       N'Trắng,Hồng,Be',           'S,M,L',           2, 2),
 ('QJS06', N'Quần jeans slim fit',       'JEANS',   N'Denim Co', @UomCai, 459000, 200000, 'men',    N'Denim co giãn',    N'Xanh jean,Đen',           '29,30,31,32,34',  3, 3),
 ('QJN07', N'Quần jeans nữ ống rộng',    'JEANS',   N'Denim Co', @UomCai, 429000, 185000, 'women',  N'Denim',            N'Xanh nhạt,Đen',           'S,M,L',           2, 3),
 ('QKK08', N'Quần kaki chinos',          'KAKI',    N'MyStyle',  @UomCai, 389000, 165000, 'men',    N'Kaki co giãn',     N'Be,Đen,Xanh navy',        '29,30,31,32',     2, 2),
 ('QSO09', N'Quần short thể thao',       'SHORT',   N'Urban',    @UomCai, 179000,  70000, 'unisex', N'Thun lạnh',        N'Đen,Xám',                 'M,L,XL',          2, 1),
 ('VDM10', N'Váy đầm hoa nhí',           'VAY',     N'Elegant',  @UomCai, 399000, 160000, 'women',  N'Voan 2 lớp',       N'Hồng,Kem,Xanh dương',     'S,M,L',           2, 2),
 ('VCS11', N'Chân váy chữ A',            'VAY',     N'Elegant',  @UomCai, 279000, 110000, 'women',  N'Tuyết mưa',        N'Đen,Be',                  'S,M,L',           1, 2),
 ('AKB12', N'Áo khoác bomber',           'KHOAC',   N'Urban',    @UomCai, 599000, 260000, 'unisex', N'Dù 2 lớp',         N'Đen,Xanh rêu',            'M,L,XL',          1, 1),
 ('AKG13', N'Áo khoác gió chống nắng',   'KHOAC',   N'MyStyle',  @UomCai, 299000, 120000, 'women',  N'Vải dù chống UV',  N'Hồng,Trắng,Xanh dương',   'FREESIZE',        2, 1),
 ('GSN14', N'Giày sneaker trắng',        'SNEAKER', N'Stepup',   @UomDoi, 690000, 310000, 'unisex', N'Da tổng hợp',      N'Trắng,Đen',               '36,37,38,39,40,41,42,43', 3, 4),
 ('GCG15', N'Giày cao gót mũi nhọn',     'GIAYNU',  N'Stepup',   @UomDoi, 520000, 220000, 'women',  N'Da PU',            N'Đen,Be',                  '35,36,37,38,39',  1, 4),
 ('GTL16', N'Giày tây da bò',            'GIAYNAM', N'Stepup',   @UomDoi, 990000, 450000, 'men',    N'Da bò thật',       N'Đen,Nâu',                 '39,40,41,42,43',  1, 4),
 ('DSD17', N'Dép sandal quai ngang',     'DEP',     N'Stepup',   @UomDoi, 249000,  95000, 'unisex', N'Cao su EVA',       N'Đen,Be',                  '37,38,39,40,41,42', 2, 4),
 ('TXK18', N'Túi xách nữ đeo chéo',      'TUI',     N'Elegant',  @UomCai, 459000, 190000, 'women',  N'Da PU cao cấp',    N'Đen,Kem,Nâu',             '',                2, 2),
 ('MLT19', N'Mũ lưỡi trai',              'PHUKIEN', N'Urban',    @UomCai, 129000,  45000, 'unisex', N'Kaki',             N'Đen,Be,Xanh navy',        'FREESIZE',        2, 1),
 ('TAT20', N'Tất cổ ngắn (combo 3 đôi)', 'PHUKIEN', N'MyStyle',  @UomBo,   79000,  28000, 'unisex', N'Cotton',           N'Đen,Trắng',               'FREESIZE',        3, 1);

INSERT md.ProductModels (CompanyId, Code, Name, CategoryId, BrandId, UomId, SalePrice, CostPrice, Gender, Material, Season, Description, CreatedAt, CreatedBy)
SELECT @C, m.Code, m.Name,
       (SELECT Id FROM md.ProductCategories WHERE CompanyId = @C AND Code = m.Cat),
       (SELECT Id FROM md.Brands WHERE CompanyId = @C AND Name = m.Brand),
       m.Uom, m.Price, m.Cost, m.Gender, m.Material, N'Thu đông 2026', NULL, DATEADD(DAY, -62, @Now), @U
FROM @M m ORDER BY m.Seq;
UPDATE m SET Id = pm.Id FROM @M m JOIN md.ProductModels pm ON pm.CompanyId = @C AND pm.Code = m.Code;

-- Biến thể = màu × size (size 'FREESIZE' hiển thị "Free size", mẫu không size thì chỉ theo màu)
INSERT md.Products (CompanyId, Code, Name, ProductType, CategoryId, BrandId, ModelId, Color, Size, UomId, SalePrice, CostPrice,
                    MinStock, IsSellable, IsPurchasable, IsStockTracked, CreatedAt, CreatedBy)
SELECT @C,
       m.Code + '-' + col.Part + CASE WHEN sz.Size IS NULL THEN '' WHEN sz.Size = 'FREESIZE' THEN '-FREESIZE' ELSE '-' + sz.Size END,
       m.Name + N' - ' + c.value + CASE WHEN sz.Size IS NULL THEN N'' WHEN sz.Size = 'FREESIZE' THEN N' - Free size' ELSE N' - ' + sz.Size END,
       'goods', pm.CategoryId, pm.BrandId, m.Id, c.value,
       CASE WHEN sz.Size = 'FREESIZE' THEN 'Free size' ELSE sz.Size END,
       m.Uom, m.Price, m.Cost, 3, 1, 1, 1, DATEADD(DAY, -62, @Now), @U
FROM @M m
JOIN md.ProductModels pm ON pm.Id = m.Id
CROSS APPLY STRING_SPLIT(m.Colors, ',') c
JOIN @Color col ON col.Name = c.value
CROSS APPLY (SELECT NULLIF(s.value, '') AS Size FROM STRING_SPLIT(m.Sizes, ',') s) sz;   -- Sizes '' => 1 dòng Size NULL

/* ---------- 3. Nhà cung cấp ---------- */
DECLARE @S TABLE (Seq INT, Name NVARCHAR(255), TaxCode VARCHAR(20), Phone VARCHAR(20), Email VARCHAR(255), Street NVARCHAR(255),
    Contact NVARCHAR(150), ContactPhone VARCHAR(20), Id BIGINT NULL);
INSERT @S (Seq, Name, TaxCode, Phone, Email, Street, Contact, ContactPhone) VALUES
 (1, N'Xưởng may Thành Công',              '0312223334', '02838110001', 'order@maythanhcong.vn', N'KCN Tân Bình, TP.HCM',     N'Lê Thị Thu',   '0908111222'),
 (2, N'Công ty TNHH Dệt may Phương Nam',   '0313334445', '02838220002', 'sales@detmaypn.vn',     N'Q.12, TP.HCM',             N'Trần Văn Hậu', '0909222333'),
 (3, N'Denim Việt',                        '0314445556', '02838330003', 'b2b@denimviet.vn',      N'Thủ Đức, TP.HCM',          N'Phạm Quốc Vũ', '0918333444'),
 (4, N'Giày da Bình Tiên Supply',          '0315556667', '02838440004', 'wholesale@btsupply.vn', N'Q.6, TP.HCM',              N'Ngô Mỹ Dung',  '0937444555');

SET @i = 1;
WHILE @i <= 4
BEGIN
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'SUPPLIER', @DocDate = @Today, @DocNo = @Code OUTPUT;
    INSERT md.Partners (CompanyId, Code, PartnerType, Name, TaxCode, Phone, Email, Street, IsSupplier, Source, CreatedAt, CreatedBy)
    SELECT @C, @Code, 'company', Name, TaxCode, Phone, Email, Street, 1, N'Dữ liệu mẫu', DATEADD(DAY, -65, @Now), @U FROM @S WHERE Seq = @i;
    SET @Id = SCOPE_IDENTITY();
    UPDATE @S SET Id = @Id WHERE Seq = @i;
    INSERT md.PartnerContacts (PartnerId, FullName, Phone, IsPrimary, CreatedAt, CreatedBy)
    SELECT @Id, Contact, ContactPhone, 1, DATEADD(DAY, -65, @Now), @U FROM @S WHERE Seq = @i;
    SET @i += 1;
END

/* ---------- 5. Khách mua online (cá nhân) ---------- */
DECLARE @K TABLE (Seq INT, Name NVARCHAR(150), Phone VARCHAR(20), Street NVARCHAR(255), Id BIGINT NULL);
INSERT @K (Seq, Name, Phone, Street) VALUES
 (1, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội'),      (2, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM'),
 (3, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng'),        (4, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội'),
 (5, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM'),       (6, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ'),
 (7, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng'),      (8, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM'),
 (9, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội'),     (10, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM'),
 (11, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An'),    (12, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai');

DECLARE @WalkIn BIGINT = (SELECT Id FROM md.Partners WHERE CompanyId = @C AND Code = 'KHACHLE');
IF @WalkIn IS NULL
BEGIN
    INSERT md.Partners (CompanyId, Code, PartnerType, Name, IsCustomer, Note, CreatedAt, CreatedBy)
    VALUES (@C, 'KHACHLE', 'individual', N'Khách lẻ', 1, N'Khách mua tại quầy không để lại thông tin', DATEADD(DAY, -65, @Now), @U);
    SET @WalkIn = SCOPE_IDENTITY();
END

SET @i = 1;
WHILE @i <= 12
BEGIN
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'PARTNER', @DocDate = @Today, @DocNo = @Code OUTPUT;
    INSERT md.Partners (CompanyId, Code, PartnerType, Name, Phone, Street, IsCustomer, CustomerGroupId, OwnerUserId, Source, CreatedAt, CreatedBy)
    SELECT @C, @Code, 'individual', Name, Phone, Street, 1, (SELECT Id FROM md.PartnerGroups WHERE CompanyId = @C AND Code = 'RETAIL'),
           @U, N'Dữ liệu mẫu', DATEADD(DAY, -60 + @i * 2, @Now), @U FROM @K WHERE Seq = @i;
    UPDATE @K SET Id = SCOPE_IDENTITY() WHERE Seq = @i;
    SET @i += 1;
END

/* ---------- 6. Đơn bán hàng (~170 đơn / 60 ngày) ---------- */
-- Danh sách SKU có trọng số: mẫu bán chạy xuất hiện nhiều lần hơn
CREATE TABLE #Pick (Idx INT IDENTITY(0,1), ProductId BIGINT);
INSERT #Pick (ProductId)
SELECT p.Id FROM md.Products p JOIN @M m ON m.Id = p.ModelId CROSS JOIN (VALUES (1), (2), (3)) w(k) WHERE w.k <= m.Pop ORDER BY p.Id, w.k;
DECLARE @PickCount INT = (SELECT COUNT(*) FROM #Pick);

CREATE TABLE #O (N INT PRIMARY KEY, DaysAgo INT, Hour INT, Channel VARCHAR(12), CustomerId BIGINT, Status VARCHAR(12),
    PayMethod VARCHAR(20), Lines INT, OrderDiscount DECIMAL(18,0), Ship DECIMAL(18,0), Id BIGINT NULL);

;WITH nums AS (SELECT TOP 170 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS N FROM sys.all_objects),
r AS (
    SELECT N,
           ABS(CHECKSUM(N * 7919)) % 1000 AS R1, ABS(CHECKSUM(N * 104729)) % 20 AS R2, ABS(CHECKSUM(N * 1299709)) % 100 AS R3,
           ABS(CHECKSUM(N * 15485863)) % 10 AS R4, ABS(CHECKSUM(N * 32452843)) % 12 AS R5, ABS(CHECKSUM(N * 49979687)) % 13 AS R6
    FROM nums)
INSERT #O (N, DaysAgo, Hour, Channel, CustomerId, Status, PayMethod, Lines, OrderDiscount, Ship)
SELECT N,
       FLOOR(59 * (R1 / 1000.0) * (R1 / 1000.0)),                         -- dồn về gần đây: shop đang tăng trưởng
       9 + (R3 % 12),
       CASE WHEN R2 < 7 THEN 'direct' WHEN R2 < 11 THEN 'shopee' WHEN R2 < 14 THEN 'tiktok'
            WHEN R2 < 17 THEN 'facebook' WHEN R2 < 19 THEN 'website' ELSE 'zalo' END,
       NULL, NULL, NULL,
       CASE WHEN R4 < 5 THEN 1 WHEN R4 < 8 THEN 2 ELSE 3 END,
       CASE WHEN R6 = 0 THEN 20000 ELSE 0 END, 0
FROM r;

UPDATE o SET
    CustomerId = CASE WHEN o.Channel = 'direct' AND ABS(CHECKSUM(o.N * 3)) % 10 < 7 THEN @WalkIn
                      ELSE (SELECT Id FROM @K WHERE Seq = 1 + ABS(CHECKSUM(o.N * 11)) % 12) END,
    Ship = CASE WHEN o.Channel IN ('direct') THEN 0 ELSE 30000 END,
    Status = CASE WHEN o.DaysAgo >= 3 THEN CASE WHEN ABS(CHECKSUM(o.N * 17)) % 100 < 6 THEN 'cancelled' ELSE 'completed' END
                  ELSE CASE ABS(CHECKSUM(o.N * 19)) % 10 WHEN 0 THEN 'draft' WHEN 1 THEN 'draft' WHEN 2 THEN 'completed' WHEN 3 THEN 'cancelled' ELSE 'confirmed' END END
FROM #O o;
UPDATE #O SET PayMethod = CASE WHEN Channel = 'direct' THEN CASE WHEN N % 3 = 0 THEN 'bank_transfer' ELSE 'cash' END
                               WHEN Channel IN ('shopee', 'tiktok') THEN 'ewallet' ELSE 'cod' END;

CREATE TABLE #OL (N INT, Ln INT, ProductId BIGINT, Qty DECIMAL(18,4), Price DECIMAL(18,4), Disc DECIMAL(9,4), Cost DECIMAL(18,4), UomId BIGINT, Name NVARCHAR(255));
INSERT #OL (N, Ln, ProductId, Qty, Price, Disc, Cost, UomId, Name)
SELECT o.N, k.k, p.Id, CASE WHEN ABS(CHECKSUM(o.N * 31 + k.k)) % 6 = 0 THEN 2 ELSE 1 END, p.SalePrice,
       CASE WHEN ABS(CHECKSUM(o.N * 37 + k.k)) % 9 = 0 THEN 10 ELSE 0 END, p.CostPrice, p.UomId, p.Name
FROM #O o
CROSS JOIN (VALUES (1), (2), (3)) k(k)
JOIN #Pick pk ON pk.Idx = ABS(CHECKSUM(o.N * 7 + k.k * 131)) % @PickCount
JOIN md.Products p ON p.Id = pk.ProductId
WHERE k.k <= o.Lines;
-- Cùng 1 SKU xuất hiện 2 lần trong 1 đơn thì gộp (giữ dòng đầu, cộng số lượng)
;WITH d AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY N, ProductId ORDER BY Ln) AS rn, SUM(Qty) OVER (PARTITION BY N, ProductId) AS TotalQty FROM #OL)
UPDATE d SET Qty = TotalQty WHERE rn = 1;
;WITH d AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY N, ProductId ORDER BY Ln) AS rn FROM #OL)
DELETE FROM d WHERE rn > 1;

/* ---------- 4. Đơn nhập hàng + phiếu nhập kho ---------- */
-- Đợt 1 (60 ngày trước): hàng mở bán. Đợt 2 (25 ngày trước): nhập bổ sung mẫu bán chạy.
DECLARE @PO TABLE (Seq INT IDENTITY, Supplier INT, OrderDays INT, ReceiveDays INT NULL, Status VARCHAR(20), Wave INT, Id BIGINT NULL, DocNo VARCHAR(30) NULL);
INSERT @PO (Supplier, OrderDays, ReceiveDays, Status, Wave) VALUES
 (1, 60, 57, 'completed', 1), (2, 60, 56, 'completed', 1), (3, 59, 56, 'completed', 1), (4, 59, 55, 'completed', 1),
 (1, 26, 23, 'completed', 2), (3, 25, 22, 'completed', 2), (4, 25, 21, 'completed', 2),
 (2, 3, NULL, 'confirmed', 3),   -- đã đặt, đang chờ hàng về
 (3, 1, NULL, 'draft', 3);       -- đơn nháp chưa gửi

-- Số lượng nhập = nhu cầu bán thực tế + tồn dư cuối kỳ (vài mã chỉ còn 0-2 => hiện cảnh báo sắp hết hàng)
CREATE TABLE #D (ProductId BIGINT PRIMARY KEY, D1 DECIMAL(18,4), D2 DECIMAL(18,4), F DECIMAL(18,4), InW2 BIT);
INSERT #D (ProductId, D1, D2, F, InW2)
SELECT p.Id,
       ISNULL((SELECT SUM(l.Qty) FROM #OL l JOIN #O o ON o.N = l.N WHERE l.ProductId = p.Id AND o.Status IN ('confirmed','completed') AND o.DaysAgo >= 20), 0),
       ISNULL((SELECT SUM(l.Qty) FROM #OL l JOIN #O o ON o.N = l.N WHERE l.ProductId = p.Id AND o.Status IN ('confirmed','completed') AND o.DaysAgo < 20), 0),
       CASE WHEN ABS(CHECKSUM(p.Id * 7)) % 10 < 2 THEN ABS(CHECKSUM(p.Id * 7)) % 10 + 1      -- 1-2: sắp hết
            ELSE 4 + ABS(CHECKSUM(p.Id * 13)) % (4 + 3 * m.Pop) END,
       CASE WHEN m.Pop >= 2 AND m.Supplier IN (SELECT Supplier FROM @PO WHERE Wave = 2) THEN 1 ELSE 0 END
FROM md.Products p JOIN @M m ON m.Id = p.ModelId;

CREATE TABLE #POLine (PoSeq INT, Ln INT, ProductId BIGINT, UomId BIGINT, Qty DECIMAL(18,4), Price DECIMAL(18,4));
INSERT #POLine (PoSeq, Ln, ProductId, UomId, Qty, Price)
SELECT po.Seq, ROW_NUMBER() OVER (PARTITION BY po.Seq ORDER BY p.Id), p.Id, p.UomId,
       CASE po.Wave WHEN 1 THEN CASE WHEN d.InW2 = 1 THEN d.D1 + 3 ELSE d.D1 + d.D2 + d.F END
                    WHEN 2 THEN GREATEST(d.D2 + d.F - 3, 2)
                    ELSE CASE m.Pop WHEN 3 THEN 12 ELSE 6 END END,
       m.Cost
FROM @PO po
JOIN @M m ON m.Supplier = po.Supplier AND (po.Wave = 1 OR (po.Wave = 2 AND m.Pop >= 2) OR (po.Wave = 3 AND m.Pop >= 2))
JOIN md.Products p ON p.ModelId = m.Id
JOIN #D d ON d.ProductId = p.Id;

SET @i = 1; SET @n = (SELECT COUNT(*) FROM @PO);
DECLARE @StockDoc BIGINT, @Status VARCHAR(20), @RecvDays INT, @OrderDays INT, @Supplier BIGINT, @PoId BIGINT, @PoNo VARCHAR(30);
WHILE @i <= @n
BEGIN
    SELECT @Status = Status, @RecvDays = ReceiveDays, @OrderDays = OrderDays, @Supplier = s.Id
    FROM @PO po JOIN @S s ON s.Seq = po.Supplier WHERE po.Seq = @i;
    SET @Date = DATEADD(DAY, -@OrderDays, @Today);
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'PURCHASE_ORDER', @DocDate = @Date, @DocNo = @PoNo OUTPUT;

    INSERT pur.PurchaseOrders (CompanyId, DocNo, PartnerId, OrderDate, ExpectedDate, WarehouseId, BuyerUserId, Status, ReceiptStatus,
                               SubTotal, DiscountAmount, TaxAmount, OtherCost, TotalAmount, Note, ConfirmedAt, CreatedAt, CreatedBy)
    SELECT @C, @PoNo, @Supplier, @Date, DATEADD(DAY, 4, @Date), @WH, @U, @Status,
           CASE WHEN @Status = 'completed' THEN 'received' ELSE 'pending' END,
           SUM(Qty * Price), 0, 0, 0, SUM(Qty * Price),
           CASE WHEN @Status = 'draft' THEN N'Chờ chốt số lượng với nhà cung cấp' END,
           CASE WHEN @Status <> 'draft' THEN DATEADD(DAY, -@OrderDays, @Now) END,
           DATEADD(DAY, -@OrderDays, @Now), @U
    FROM #POLine WHERE PoSeq = @i;
    SET @PoId = SCOPE_IDENTITY();
    UPDATE @PO SET Id = @PoId, DocNo = @PoNo WHERE Seq = @i;

    INSERT pur.PurchaseOrderLines (PurchaseOrderId, LineNumber, ProductId, Description, UomId, Quantity, UnitPrice, DiscountPercent,
                                   TaxRate, LineSubTotal, LineTax, LineTotal, QtyReceived)
    SELECT @PoId, l.Ln, l.ProductId, p.Name, l.UomId, l.Qty, l.Price, 0, 0, l.Qty * l.Price, 0, l.Qty * l.Price,
           CASE WHEN @Status = 'completed' THEN l.Qty ELSE 0 END
    FROM #POLine l JOIN md.Products p ON p.Id = l.ProductId WHERE l.PoSeq = @i;

    IF @Status = 'completed'
    BEGIN
        SET @Date = DATEADD(DAY, -@RecvDays, @Today);
        EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'STOCK_RECEIPT', @DocDate = @Date, @DocNo = @Code OUTPUT;
        INSERT inv.StockDocuments (CompanyId, DocNo, DocType, Reason, WarehouseId, PartnerId, SourceType, SourceId, SourceDocNo, DocDate,
                                   Status, Note, TotalQuantity, TotalValue, DoneAt, DoneBy, CreatedAt, CreatedBy)
        SELECT @C, @Code, 'receipt', 'purchase', @WH, @Supplier, 'pur.PurchaseOrders', @PoId, @PoNo, DATEADD(HOUR, 3, DATEADD(DAY, -@RecvDays, @Now)),
               'done', N'Nhập hàng theo đơn ' + @PoNo, SUM(Qty), SUM(Qty * Price), DATEADD(DAY, -@RecvDays, @Now), @U, DATEADD(DAY, -@RecvDays, @Now), @U
        FROM #POLine WHERE PoSeq = @i;
        SET @StockDoc = SCOPE_IDENTITY();
        INSERT inv.StockDocumentLines (DocumentId, LineNumber, ProductId, UomId, Quantity, BaseQuantity, UnitCost, LineValue, SourceLineId)
        SELECT @StockDoc, l.Ln, l.ProductId, l.UomId, l.Qty, l.Qty, l.Price, l.Qty * l.Price, pl.Id
        FROM #POLine l JOIN pur.PurchaseOrderLines pl ON pl.PurchaseOrderId = @PoId AND pl.LineNumber = l.Ln WHERE l.PoSeq = @i;
        INSERT inv.StockLedger (CompanyId, ProductId, WarehouseId, MoveDate, QtyIn, QtyOut, UnitCost, ValueIn, ValueOut, StockDocumentId, StockDocumentLineId)
        SELECT @C, sl.ProductId, @WH, d.DocDate, sl.Quantity, 0, sl.UnitCost, sl.LineValue, 0, @StockDoc, sl.Id
        FROM inv.StockDocumentLines sl JOIN inv.StockDocuments d ON d.Id = sl.DocumentId WHERE sl.DocumentId = @StockDoc;
    END
    SET @i += 1;
END

/* ---------- 6b. Ghi đơn bán + phiếu xuất ---------- */
DECLARE @OrderNo VARCHAR(30), @OrderId BIGINT, @OrderDate DATETIME2(0), @OStatus VARCHAR(12), @Customer BIGINT, @Channel VARCHAR(12);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT N FROM #O ORDER BY DaysAgo DESC, Hour, N;
OPEN cur; FETCH NEXT FROM cur INTO @i;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @OrderDate = DATEADD(HOUR, Hour - 7, CAST(DATEADD(DAY, -DaysAgo, @Today) AS DATETIME2(0))),
           @OStatus = Status, @Customer = CustomerId, @Channel = Channel, @Date = DATEADD(DAY, -DaysAgo, @Today)
    FROM #O WHERE N = @i;
    -- Đơn hôm nay không được có giờ ở tương lai (+10 phút xác nhận cũng phải trước bây giờ)
    IF DATEADD(MINUTE, 10, @OrderDate) > @Now
        SET @OrderDate = DATEADD(MINUTE, -(15 + (@i * 37) % 240), CAST(@Now AS DATETIME2(0)));
    SET @Date = CAST(DATEADD(HOUR, 7, @OrderDate) AS DATE);
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'SALES_ORDER', @DocDate = @Date, @DocNo = @OrderNo OUTPUT;

    INSERT sales.SalesOrders (CompanyId, DocNo, PartnerId, OrderDate, Channel, WarehouseId, SalespersonUserId, PaymentMethodCode,
        ReceiverName, ReceiverPhone, ShippingStreet, Status, DeliveryStatus, PaymentStatus, SubTotal, DiscountAmount, TaxAmount,
        ShippingFee, TotalAmount, AmountPaid, Note, ConfirmedAt, ConfirmedBy, CancelledAt, CancelReason, CreatedAt, CreatedBy)
    SELECT @C, @OrderNo, o.CustomerId, @OrderDate, o.Channel, @WH, @U, o.PayMethod,
           CASE WHEN o.Channel <> 'direct' THEN p.Name END, CASE WHEN o.Channel <> 'direct' THEN p.Phone END,
           CASE WHEN o.Channel <> 'direct' THEN p.Street END,
           o.Status,
           CASE WHEN o.Status = 'completed' THEN 'delivered' ELSE 'pending' END,
           CASE WHEN o.Status = 'completed' OR (o.Status = 'confirmed' AND o.Channel = 'direct') THEN 'paid' ELSE 'unpaid' END,
           t.Sub, CASE WHEN o.OrderDiscount > t.Sub THEN 0 ELSE o.OrderDiscount END, 0, o.Ship,
           t.Sub - CASE WHEN o.OrderDiscount > t.Sub THEN 0 ELSE o.OrderDiscount END + o.Ship,
           CASE WHEN o.Status = 'completed' OR (o.Status = 'confirmed' AND o.Channel = 'direct')
                THEN t.Sub - CASE WHEN o.OrderDiscount > t.Sub THEN 0 ELSE o.OrderDiscount END + o.Ship ELSE 0 END,
           NULL,
           CASE WHEN o.Status IN ('confirmed', 'completed') THEN DATEADD(MINUTE, 10, @OrderDate) END,
           CASE WHEN o.Status IN ('confirmed', 'completed') THEN @U END,
           CASE WHEN o.Status = 'cancelled' THEN DATEADD(HOUR, 2, @OrderDate) END,
           CASE WHEN o.Status = 'cancelled' THEN N'Khách đổi ý, không mua nữa' END,
           @OrderDate, @U
    FROM #O o
    JOIN md.Partners p ON p.Id = o.CustomerId
    CROSS APPLY (SELECT SUM(ROUND(l.Qty * l.Price * (1 - l.Disc / 100), 0)) AS Sub FROM #OL l WHERE l.N = o.N) t
    WHERE o.N = @i;
    SET @OrderId = SCOPE_IDENTITY();
    UPDATE #O SET Id = @OrderId WHERE N = @i;

    INSERT sales.SalesOrderLines (SalesOrderId, LineNumber, ProductId, Description, UomId, Quantity, UnitPrice, DiscountPercent,
        DiscountAmount, TaxRate, LineSubTotal, LineTax, LineTotal, UnitCost, QtyDelivered)
    SELECT @OrderId, ROW_NUMBER() OVER (ORDER BY l.Ln), l.ProductId, l.Name, l.UomId, l.Qty, l.Price, l.Disc,
           ROUND(l.Qty * l.Price * l.Disc / 100, 0), 0,
           ROUND(l.Qty * l.Price * (1 - l.Disc / 100), 0), 0, ROUND(l.Qty * l.Price * (1 - l.Disc / 100), 0),
           CASE WHEN @OStatus IN ('confirmed', 'completed') THEN l.Cost ELSE 0 END,
           CASE WHEN @OStatus IN ('confirmed', 'completed') THEN l.Qty ELSE 0 END
    FROM #OL l WHERE l.N = @i;

    -- Đơn đã xác nhận / hoàn thành: phiếu xuất kho + sổ kho
    IF @OStatus IN ('confirmed', 'completed')
    BEGIN
        EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'STOCK_ISSUE', @DocDate = @Date, @DocNo = @Code OUTPUT;
        INSERT inv.StockDocuments (CompanyId, DocNo, DocType, Reason, WarehouseId, PartnerId, SourceType, SourceId, SourceDocNo, DocDate,
                                   Status, Note, TotalQuantity, TotalValue, DoneAt, DoneBy, CreatedAt, CreatedBy)
        SELECT @C, @Code, 'issue', 'sale', @WH, @Customer, 'sales.SalesOrders', @OrderId, @OrderNo, DATEADD(MINUTE, 10, @OrderDate),
               'done', N'Xuất bán đơn ' + @OrderNo, SUM(Quantity), SUM(Quantity * UnitCost), DATEADD(MINUTE, 10, @OrderDate), @U, DATEADD(MINUTE, 10, @OrderDate), @U
        FROM sales.SalesOrderLines WHERE SalesOrderId = @OrderId;
        SET @StockDoc = SCOPE_IDENTITY();
        INSERT inv.StockDocumentLines (DocumentId, LineNumber, ProductId, UomId, Quantity, BaseQuantity, UnitCost, LineValue, SourceLineId)
        SELECT @StockDoc, LineNumber, ProductId, UomId, Quantity, Quantity, UnitCost, ROUND(Quantity * UnitCost, 0), Id
        FROM sales.SalesOrderLines WHERE SalesOrderId = @OrderId;
        INSERT inv.StockLedger (CompanyId, ProductId, WarehouseId, MoveDate, QtyIn, QtyOut, UnitCost, ValueIn, ValueOut, StockDocumentId, StockDocumentLineId)
        SELECT @C, sl.ProductId, @WH, DATEADD(MINUTE, 10, @OrderDate), 0, sl.Quantity, sl.UnitCost, 0, sl.LineValue, @StockDoc, sl.Id
        FROM inv.StockDocumentLines sl WHERE sl.DocumentId = @StockDoc;
    END
    FETCH NEXT FROM cur INTO @i;
END
CLOSE cur; DEALLOCATE cur;

/* ---------- 7. Tồn kho = tổng hợp từ sổ kho ---------- */
INSERT inv.StockBalances (CompanyId, WarehouseId, ProductId, QtyOnHand, QtyReserved, QtyIncoming, AvgCost, UpdatedAt)
SELECT @C, l.WarehouseId, l.ProductId, SUM(l.QtyIn) - SUM(l.QtyOut), 0, 0,
       CASE WHEN SUM(l.QtyIn) = 0 THEN 0 ELSE ROUND(SUM(l.ValueIn) / SUM(l.QtyIn), 4) END, @Now
FROM inv.StockLedger l
WHERE l.CompanyId = @C AND NOT EXISTS (SELECT 1 FROM inv.StockBalances b WHERE b.WarehouseId = l.WarehouseId AND b.ProductId = l.ProductId)
GROUP BY l.WarehouseId, l.ProductId;

IF EXISTS (SELECT 1 FROM inv.StockBalances WHERE QtyOnHand < 0)
    THROW 50010, N'Dữ liệu mẫu sinh ra tồn âm - kiểm tra lại số lượng nhập.', 1;

COMMIT;

DROP TABLE #POLine; DROP TABLE #D; DROP TABLE #Pick; DROP TABLE #O; DROP TABLE #OL;

DECLARE @Models INT = (SELECT COUNT(*) FROM md.ProductModels), @Skus INT = (SELECT COUNT(*) FROM md.Products WHERE ModelId IS NOT NULL),
        @Orders INT = (SELECT COUNT(*) FROM sales.SalesOrders), @Pos INT = (SELECT COUNT(*) FROM pur.PurchaseOrders);
PRINT N'Đã thêm ' + CAST(@Models AS NVARCHAR) + N' mẫu / ' + CAST(@Skus AS NVARCHAR) + N' SKU, '
    + CAST(@Pos AS NVARCHAR) + N' đơn nhập, ' + CAST(@Orders AS NVARCHAR) + N' đơn bán.';
GO
