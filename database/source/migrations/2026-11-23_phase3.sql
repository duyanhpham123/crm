/* =====================================================================
   Nâng cấp database ĐÃ TẠO trước đợt 3 (Nhân sự, Marketing, Cài đặt).
   DB mới tạo bằng run_all.ps1 đã có sẵn. Chạy lại nhiều lần không sao.
   Chạy:  sqlcmd -S localhost -E -d MyERP -I -f 65001 -i migrations\2026-11-23_phase3.sql
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF COL_LENGTH('sales.Promotions', 'CampaignId') IS NULL
    ALTER TABLE sales.Promotions ADD CampaignId BIGINT NULL CONSTRAINT FK_Promotions_Campaigns REFERENCES mkt.Campaigns(Id);
GO

INSERT hr.Positions (CompanyId, Code, Name)
SELECT c.Id, v.Code, v.Name FROM core.Companies c
CROSS JOIN (VALUES ('CHT',N'Cửa hàng trưởng'),('NVBH',N'Nhân viên bán hàng'),('NVOL',N'Nhân viên bán online'),
                   ('NVK',N'Nhân viên kho'),('KT',N'Kế toán'),('MKT',N'Nhân viên marketing')) v(Code, Name)
WHERE NOT EXISTS (SELECT 1 FROM hr.Positions p WHERE p.CompanyId = c.Id AND p.Code = v.Code);
GO
PRINT N'Đã nâng cấp database cho đợt 3.';
