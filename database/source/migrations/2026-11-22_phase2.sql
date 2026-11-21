/* =====================================================================
   Nâng cấp database ĐÃ TẠO trước đợt 2 (Báo giá, Vận chuyển, Kế toán, CSKH).
   DB mới tạo bằng run_all.ps1 đã có sẵn, không cần chạy. Chạy lại nhiều lần không sao.
   Chạy:  sqlcmd -S localhost -E -d MyERP -I -f 65001 -i migrations\2026-11-22_phase2.sql
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF COL_LENGTH('acc.Payments', 'Category') IS NULL
    ALTER TABLE acc.Payments ADD
        Category        VARCHAR(30) NULL,
        SalesOrderId    BIGINT NULL CONSTRAINT FK_Payments_SalesOrders REFERENCES sales.SalesOrders(Id),
        PurchaseOrderId BIGINT NULL CONSTRAINT FK_Payments_PurchaseOrders REFERENCES pur.PurchaseOrders(Id);
GO
IF COL_LENGTH('sales.SalesOrders', 'ReturnedAmount') IS NULL
    ALTER TABLE sales.SalesOrders ADD ReturnedAmount DECIMAL(18,2) NOT NULL CONSTRAINT DF_SalesOrders_ReturnedAmount DEFAULT 0;
GO
IF COL_LENGTH('pur.PurchaseOrders', 'AmountPaid') IS NULL
    ALTER TABLE pur.PurchaseOrders ADD AmountPaid DECIMAL(18,2) NOT NULL CONSTRAINT DF_PurchaseOrders_AmountPaid DEFAULT 0;
GO

-- Trạng thái giao hàng của đơn: thêm "đang giao" và "đang hoàn" (do Vận chuyển cập nhật)
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SalesOrders_Delivery' AND definition LIKE '%shipping%')
BEGIN
    ALTER TABLE sales.SalesOrders DROP CONSTRAINT CK_SalesOrders_Delivery;
    ALTER TABLE sales.SalesOrders ADD CONSTRAINT CK_SalesOrders_Delivery
        CHECK (DeliveryStatus IN ('pending','partial','shipping','delivered','returning','returned'));
END
GO

INSERT lgs.Carriers (CompanyId, Code, Name, CarrierType, ApiProvider)
SELECT c.Id, v.Code, v.Name, v.CType, v.Api
FROM core.Companies c
CROSS JOIN (VALUES ('GHN',N'Giao Hàng Nhanh','third_party','ghn'),('GHTK',N'Giao Hàng Tiết Kiệm','third_party','ghtk'),
                   ('VTP',N'Viettel Post','third_party','viettelpost'),('JT',N'J&T Express','third_party','jt'),
                   ('SPX',N'SPX Express (Shopee)','third_party',NULL),('NOIBO',N'Shop tự giao','internal',NULL)) v(Code, Name, CType, Api)
WHERE NOT EXISTS (SELECT 1 FROM lgs.Carriers x WHERE x.CompanyId = c.Id AND x.Code = v.Code);

INSERT acc.BankAccounts (CompanyId, AccountId, BankName, BankBranch, AccountNo, AccountName)
SELECT a.CompanyId, a.Id, N'Vietcombank', N'Chi nhánh Hà Nội', '0011000000001', N'CONG TY ABC'
FROM acc.Accounts a
WHERE a.Code = '1121' AND NOT EXISTS (SELECT 1 FROM acc.BankAccounts b WHERE b.CompanyId = a.CompanyId);
GO
PRINT N'Đã nâng cấp database cho đợt 2.';
