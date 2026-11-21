/* =====================================================================
   MyERP - 45. DỮ LIỆU MẪU NHIỀU WEBSITE (chạy sau 44_demo_phase4.sql). Chạy lại không nhân đôi.
   - Website 1 "MyStyle Fashion": bày các mẫu đang bật trên web, 4 mẫu nổi bật, phí ship 30k / miễn phí từ 500k,
     menu trỏ đúng đường dẫn của website mẫu Next.js (thư mục storefront/)
   - Website 2 "MyStyle Sneaker" (sneaker.mystyle.vn): chỉ bán giày, giá riêng cho 1 mẫu
   Khóa API không tạo sẵn: vào ERP > Website > Kết nối website bấm "Tạo khóa API".
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @C BIGINT = (SELECT TOP 1 Id FROM core.Companies ORDER BY Id);
DECLARE @Site1 BIGINT = (SELECT TOP 1 Id FROM web.Sites WHERE CompanyId = @C ORDER BY Id);
IF @Site1 IS NULL BEGIN PRINT N'Chưa có website - chạy 44_demo_phase4.sql trước.'; RETURN; END

/* Tài khoản bot ghi đơn online (không mật khẩu, không vai trò, đã khóa) */
IF NOT EXISTS (SELECT 1 FROM core.Users WHERE NormalizedUserName = CONCAT('WEBSITE.BOT.', @C))
    INSERT core.Users (UserName, NormalizedUserName, FullName, DefaultCompanyId, IsActive, SecurityStamp, ConcurrencyStamp)
    VALUES (CONCAT('website.bot.', @C), CONCAT('WEBSITE.BOT.', @C), N'Website (bán online)', @C, 0, CONVERT(NVARCHAR(36), NEWID()), CONVERT(NVARCHAR(36), NEWID()));
DECLARE @Bot BIGINT = (SELECT Id FROM core.Users WHERE NormalizedUserName = CONCAT('WEBSITE.BOT.', @C));
UPDATE web.Sites SET BotUserId = @Bot WHERE CompanyId = @C AND BotUserId IS NULL;

/* ---------- Website 1 ---------- */
INSERT web.SiteProducts (SiteId, ModelId)
SELECT @Site1, m.Id FROM md.ProductModels m
WHERE m.CompanyId = @C AND m.IsDeleted = 0
  AND EXISTS (SELECT 1 FROM md.Products p WHERE p.ModelId = m.Id AND p.IsPublishedWeb = 1)
  AND NOT EXISTS (SELECT 1 FROM web.SiteProducts x WHERE x.SiteId = @Site1 AND x.ModelId = m.Id);

IF NOT EXISTS (SELECT 1 FROM web.SiteProducts WHERE SiteId = @Site1 AND IsFeatured = 1)
    UPDATE sp SET IsFeatured = 1, SortOrder = v.SortOrder
    FROM web.SiteProducts sp JOIN md.ProductModels m ON m.Id = sp.ModelId
    JOIN (VALUES ('ATB01', 1), ('GSN14', 2), ('VDM10', 3), ('AKB12', 4)) v(Code, SortOrder) ON v.Code = m.Code
    WHERE sp.SiteId = @Site1;

/* Phí ship + menu khớp website mẫu (chỉ thay khi còn menu demo cũ) */
UPDATE web.Sites SET Settings = JSON_MODIFY(JSON_MODIFY(ISNULL(Settings, N'{}'), '$.shippingFee', 30000), '$.freeShippingFrom', 500000)
WHERE Id = @Site1 AND JSON_VALUE(ISNULL(Settings, N'{}'), '$.shippingFee') IS NULL;

DECLARE @H1 BIGINT = (SELECT Id FROM web.Menus WHERE SiteId = @Site1 AND Code = 'header');
IF @H1 IS NOT NULL AND EXISTS (SELECT 1 FROM web.MenuItems WHERE MenuId = @H1 AND Url = '/collections/nam')
BEGIN
    DELETE web.MenuItems WHERE MenuId = @H1;
    INSERT web.MenuItems (MenuId, Label, Url, SortOrder) VALUES
     (@H1, N'Trang chủ', '/', 10), (@H1, N'Sản phẩm', '/san-pham', 20), (@H1, N'Áo thun', '/san-pham?category=ao-thun', 30),
     (@H1, N'Giày sneaker', '/san-pham?category=giay-sneaker', 40), (@H1, N'Blog', '/blog', 50), (@H1, N'Liên hệ', '/lien-he', 60);
END

/* ---------- Website 2: chỉ bán giày ---------- */
IF NOT EXISTS (SELECT 1 FROM web.Sites WHERE Domain = 'sneaker.mystyle.vn')
BEGIN
    INSERT web.Sites (CompanyId, Name, Domain, WarehouseId, Settings, IsActive, BotUserId)
    VALUES (@C, N'MyStyle Sneaker', 'sneaker.mystyle.vn', (SELECT TOP 1 Id FROM inv.Warehouses WHERE CompanyId = @C ORDER BY Id),
            N'{"slogan":"Giày đẹp cho mọi bước chân","hotline":"0909 123 456","email":"sneaker@mystyle.vn","address":"123 Lê Lợi, Quận 1, TP.HCM","openingHours":"9:00 - 22:00","primaryColor":"#185FA5","shippingFee":25000,"freeShippingFrom":800000}',
            1, @Bot);
    DECLARE @Site2 BIGINT = SCOPE_IDENTITY();

    INSERT web.SiteProducts (SiteId, ModelId, PriceOverride, IsFeatured, SortOrder)
    SELECT @Site2, m.Id, CASE m.Code WHEN 'GSN14' THEN 549000 END, CASE WHEN m.Code IN ('GSN14', 'GCG15') THEN 1 ELSE 0 END, 0
    FROM md.ProductModels m WHERE m.CompanyId = @C AND m.IsDeleted = 0 AND m.Code IN ('GSN14', 'GCG15', 'GTL16', 'DSD17');

    INSERT web.Menus (SiteId, Code) VALUES (@Site2, 'header'), (@Site2, 'footer');
    INSERT web.MenuItems (MenuId, Label, Url, SortOrder)
    SELECT m.Id, i.Label, i.Url, i.SortOrder FROM web.Menus m
    JOIN (VALUES ('header', N'Trang chủ', '/', 10), ('header', N'Tất cả giày', '/san-pham', 20), ('header', N'Liên hệ', '/lien-he', 30),
                 ('footer', N'Chính sách đổi trả', '/pages/chinh-sach-doi-tra', 10)) i(Code, Label, Url, SortOrder) ON i.Code = m.Code
    WHERE m.SiteId = @Site2;

    INSERT web.Pages (SiteId, Slug, Title, Content, IsPublished, PublishedAt, CreatedAt)
    VALUES (@Site2, 'chinh-sach-doi-tra', N'Chính sách đổi trả giày',
            N'Đổi size miễn phí trong 7 ngày nếu giày chưa qua sử dụng, còn hộp và tem. Lỗi keo, lỗi đế: bảo hành 3 tháng.', 1, SYSUTCDATETIME(), SYSUTCDATETIME());
    PRINT N'Đã tạo website mẫu thứ 2: MyStyle Sneaker.';
END
GO
