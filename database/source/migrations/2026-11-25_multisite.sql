/* =====================================================================
   Nâng cấp: nhiều website tự code (Next.js...) đọc dữ liệu từ ERP.
   - web.Sites: khóa API (lưu dạng băm SHA-256), webhook báo web làm mới, tài khoản bot ghi đơn online
   - web.SiteProducts: mẫu sản phẩm bày bán trên từng website (giá riêng, nổi bật)
   DB mới tạo bằng run_all.ps1 đã có sẵn. Chạy lại nhiều lần không sao.
   Chạy:  sqlcmd -S localhost -E -d MyERP -I -f 65001 -i migrations\2026-11-25_multisite.sql
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF COL_LENGTH('web.Sites', 'ApiKeyHash') IS NULL
    ALTER TABLE web.Sites ADD
        ApiKeyHash       CHAR(64)      NULL,     -- SHA-256 của khóa API (khóa gốc chỉ hiện 1 lần lúc tạo)
        ApiKeyPrefix     VARCHAR(16)   NULL,     -- vài ký tự đầu để nhận ra khóa nào đang dùng
        ApiKeyCreatedAt  DATETIME2(3)  NULL,
        RevalidateUrl    VARCHAR(500)  NULL,     -- VD https://mystyle.vn/api/revalidate
        RevalidateSecret VARCHAR(100)  NULL,
        LastSyncAt       DATETIME2(3)  NULL,
        LastSyncStatus   NVARCHAR(300) NULL,
        BotUserId        BIGINT        NULL CONSTRAINT FK_Sites_BotUser REFERENCES core.Users(Id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Sites_ApiKeyHash')
    CREATE UNIQUE INDEX UX_Sites_ApiKeyHash ON web.Sites(ApiKeyHash) WHERE ApiKeyHash IS NOT NULL;
GO

IF OBJECT_ID('web.SiteProducts') IS NULL
CREATE TABLE web.SiteProducts (
    SiteId        BIGINT        NOT NULL,
    ModelId       BIGINT        NOT NULL,
    PriceOverride DECIMAL(18,2) NULL,        -- NULL = giá bán của từng biến thể
    IsFeatured    BIT           NOT NULL DEFAULT 0,
    SortOrder     INT           NOT NULL DEFAULT 0,
    AddedAt       DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_SiteProducts PRIMARY KEY (SiteId, ModelId),
    CONSTRAINT FK_SiteProducts_Sites FOREIGN KEY (SiteId) REFERENCES web.Sites(Id) ON DELETE CASCADE,
    CONSTRAINT FK_SiteProducts_Models FOREIGN KEY (ModelId) REFERENCES md.ProductModels(Id),
    CONSTRAINT CK_SiteProducts_Price CHECK (PriceOverride IS NULL OR PriceOverride >= 0)
);
GO

/* Mẫu đang bật "hiện trên web" (cách cũ) -> bày bán trên website đầu tiên của công ty */
INSERT web.SiteProducts (SiteId, ModelId)
SELECT s.Id, m.Id
FROM md.ProductModels m
CROSS APPLY (SELECT TOP 1 Id FROM web.Sites WHERE CompanyId = m.CompanyId ORDER BY Id) s
WHERE m.IsDeleted = 0
  AND EXISTS (SELECT 1 FROM md.Products p WHERE p.ModelId = m.Id AND p.IsPublishedWeb = 1)
  AND NOT EXISTS (SELECT 1 FROM web.SiteProducts x WHERE x.SiteId = s.Id AND x.ModelId = m.Id);
GO

/* Tài khoản bot ghi đơn online: mỗi công ty 1 tài khoản, không có mật khẩu, không có vai trò -> không đăng nhập, không có quyền */
INSERT core.Users (UserName, NormalizedUserName, FullName, DefaultCompanyId, IsActive, SecurityStamp, ConcurrencyStamp)
SELECT CONCAT('website.bot.', c.Id), CONCAT('WEBSITE.BOT.', c.Id), N'Website (bán online)', c.Id, 0, CONVERT(NVARCHAR(36), NEWID()), CONVERT(NVARCHAR(36), NEWID())
FROM core.Companies c
WHERE EXISTS (SELECT 1 FROM web.Sites s WHERE s.CompanyId = c.Id)
  AND NOT EXISTS (SELECT 1 FROM core.Users u WHERE u.NormalizedUserName = CONCAT('WEBSITE.BOT.', c.Id));

UPDATE s SET BotUserId = u.Id
FROM web.Sites s JOIN core.Users u ON u.NormalizedUserName = CONCAT('WEBSITE.BOT.', s.CompanyId)
WHERE s.BotUserId IS NULL;
GO
PRINT N'Đã nâng cấp database cho nhiều website.';
