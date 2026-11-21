using System.Globalization;
using System.Text;
using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Website;

public static class Slug
{
    /// <summary>"Áo thun Basic - Đen!" → "ao-thun-basic-den".</summary>
    public static string From(string text)
    {
        var folded = (text ?? "").Replace('đ', 'd').Replace('Đ', 'D').Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder();
        var dash = false;
        foreach (var ch in folded)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark) continue;
            if (char.IsAsciiLetterOrDigit(ch)) { sb.Append(char.ToLowerInvariant(ch)); dash = false; }
            else if (!dash && sb.Length > 0) { sb.Append('-'); dash = true; }
        }
        var s = sb.ToString().Trim('-');
        return s.Length > 200 ? s[..200].Trim('-') : s;
    }

    public static Result<string> Clean(string? slug, string fallbackText)
    {
        var s = From(string.IsNullOrWhiteSpace(slug) ? fallbackText : slug);
        return s.Length == 0 ? Error.Validation("web.slug", "Đường dẫn không hợp lệ.") : s;
    }
}

public sealed record SiteInfo(string Name, string Domain, string? LogoUrl, string? Settings, bool IsActive);

/// <summary>web.Sites - website bán hàng của cửa hàng. Settings: JSON (hotline, địa chỉ, màu chủ đạo, mạng xã hội).</summary>
public sealed class Site : ICompanyOwned
{
    private Site() { }
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public string Name { get; private set; } = "";
    public string Domain { get; private set; } = "";
    public string DefaultLanguage { get; private set; } = "vi";
    public string? LogoUrl { get; private set; }
    public string? FaviconUrl { get; private set; }
    public long? PriceListId { get; private set; }
    public long? WarehouseId { get; private set; }
    public string? Settings { get; private set; }
    public bool IsActive { get; private set; } = true;

    public static Result<Site> Create(long companyId, SiteInfo info)
    {
        var s = new Site { CompanyId = companyId };
        var r = s.Update(info);
        return r.IsFailure ? r.Error! : s;
    }

    public Result Update(SiteInfo i)
    {
        if (string.IsNullOrWhiteSpace(i.Name)) return Error.Validation("site.name", "Nhập tên website.");
        var domain = (i.Domain ?? "").Trim().ToLowerInvariant().Replace("https://", "").Replace("http://", "").TrimEnd('/');
        if (domain.Length is < 3 or > 255 || domain.Any(ch => !(char.IsAsciiLetterOrDigit(ch) || ch is '.' or '-' or ':')))
            return Error.Validation("site.domain", "Tên miền không hợp lệ (VD: mystyle.vn).");
        Name = i.Name.Trim(); Domain = domain; LogoUrl = string.IsNullOrWhiteSpace(i.LogoUrl) ? null : i.LogoUrl.Trim();
        Settings = string.IsNullOrWhiteSpace(i.Settings) ? null : i.Settings; IsActive = i.IsActive;
        return Result.Success();
    }

    public void SetWarehouse(long? warehouseId) => WarehouseId = warehouseId;

    // ----- Kết nối website tự code (Next.js...) -----

    public string? ApiKeyHash { get; private set; }
    public string? ApiKeyPrefix { get; private set; }
    public DateTime? ApiKeyCreatedAt { get; private set; }
    public string? RevalidateUrl { get; private set; }
    public string? RevalidateSecret { get; private set; }
    public DateTime? LastSyncAt { get; private set; }
    public string? LastSyncStatus { get; private set; }
    /// <summary>Tài khoản (không đăng nhập được, không có quyền) ghi làm người tạo cho đơn đặt từ website này.</summary>
    public long? BotUserId { get; private set; }

    public const string KeyPrefix = "mys_";

    /// <summary>Tạo khóa API mới (khóa cũ hết hiệu lực ngay). Trả về khóa gốc - chỉ hiện 1 lần, ERP chỉ lưu bản băm.</summary>
    public string IssueApiKey(DateTime nowUtc)
    {
        var raw = KeyPrefix + RandomToken(40);
        ApiKeyHash = HashKey(raw);
        ApiKeyPrefix = raw[..10];
        ApiKeyCreatedAt = nowUtc;
        return raw;
    }

    public void RevokeApiKey() { ApiKeyHash = null; ApiKeyPrefix = null; ApiKeyCreatedAt = null; }

    public static string HashKey(string raw)
        => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(raw))).ToLowerInvariant();

    /// <summary>Địa chỉ website nhận lệnh làm mới (Next.js: /api/revalidate). Bỏ trống = không gửi. Chưa có mật khẩu thì tự tạo.</summary>
    public Result SetWebhook(string? url, bool newSecret)
    {
        if (string.IsNullOrWhiteSpace(url)) { RevalidateUrl = null; return Result.Success(); }
        var u = url.Trim();
        if (u.Length > 500 || !Uri.TryCreate(u, UriKind.Absolute, out var uri) || (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp))
            return Error.Validation("site.webhook", "Địa chỉ webhook phải là http(s)://..., VD https://mystyle.vn/api/revalidate");
        RevalidateUrl = u;
        if (newSecret || string.IsNullOrEmpty(RevalidateSecret)) RevalidateSecret = RandomToken(32);
        return Result.Success();
    }

    public void RecordSync(DateTime nowUtc, string status) { LastSyncAt = nowUtc; LastSyncStatus = status.Length > 300 ? status[..300] : status; }

    public void SetBot(long userId) => BotUserId = userId;

    private static string RandomToken(int length)
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
        var bytes = System.Security.Cryptography.RandomNumberGenerator.GetBytes(length);
        var sb = new StringBuilder(length);
        foreach (var b in bytes) sb.Append(chars[b % chars.Length]);
        return sb.ToString();
    }
}

/// <summary>web.SiteProducts - mẫu sản phẩm bày bán trên một website. Giá riêng (nếu có) áp cho mọi màu - size của mẫu.</summary>
public sealed class SiteProduct
{
    private SiteProduct() { }
    public long SiteId { get; private set; }
    public long ModelId { get; private set; }
    public decimal? PriceOverride { get; private set; }
    public bool IsFeatured { get; private set; }
    public int SortOrder { get; private set; }
    public DateTime AddedAt { get; private set; }

    public static SiteProduct Create(long siteId, long modelId, DateTime nowUtc) => new() { SiteId = siteId, ModelId = modelId, AddedAt = nowUtc };

    public Result Update(decimal? priceOverride, bool isFeatured)
    {
        if (priceOverride is < 0) return Error.Validation("web.price", "Giá không hợp lệ.");
        PriceOverride = priceOverride; IsFeatured = isFeatured;
        return Result.Success();
    }
}

/// <summary>web.Carts - ở đây dùng để ghi "đơn này đặt từ website nào" (giỏ hàng nằm ở trình duyệt khách).</summary>
public sealed class WebCart
{
    private WebCart() { }
    public long Id { get; private set; }
    public long SiteId { get; private set; }
    public long? CustomerAccountId { get; private set; }
    public string SessionKey { get; private set; } = "";
    public string? PromotionCode { get; private set; }
    public long? SalesOrderId { get; private set; }
    public string Status { get; private set; } = "ordered";
    public DateTime CreatedAt { get; private set; }
    public DateTime? UpdatedAt { get; private set; }

    public static WebCart ForOrder(long siteId, long orderId, string? promotionCode, DateTime nowUtc)
        => new() { SiteId = siteId, SalesOrderId = orderId, SessionKey = $"order-{orderId}", PromotionCode = promotionCode, Status = "ordered", CreatedAt = nowUtc };
}

public sealed record ContentInfo(string Title, string? Slug, string? Summary, string? Content, string? ThumbnailUrl, long? CategoryId,
    string? MetaTitle, string? MetaDescription, bool IsPublished);

/// <summary>web.Pages - trang tĩnh (Giới thiệu, Chính sách đổi trả, Hướng dẫn chọn size...).</summary>
public sealed class WebPage : IAuditable, ISoftDelete
{
    private WebPage() { }
    public long Id { get; private set; }
    public long SiteId { get; private set; }
    public string Slug { get; private set; } = "";
    public string Title { get; private set; } = "";
    public string? Content { get; private set; }
    public string? MetaTitle { get; private set; }
    public string? MetaDescription { get; private set; }
    public bool IsPublished { get; private set; }
    public DateTime? PublishedAt { get; private set; }
    public DateTime CreatedAt { get; set; }
    public long? CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public long? UpdatedBy { get; set; }
    public bool IsDeleted { get; set; }

    public static Result<WebPage> Create(long siteId, ContentInfo info, DateTime nowUtc)
    {
        var p = new WebPage { SiteId = siteId };
        var r = p.Update(info, nowUtc);
        return r.IsFailure ? r.Error! : p;
    }

    public Result Update(ContentInfo i, DateTime nowUtc)
    {
        if (string.IsNullOrWhiteSpace(i.Title)) return Error.Validation("page.title", "Nhập tiêu đề.");
        var slug = Website.Slug.Clean(i.Slug, i.Title);
        if (slug.IsFailure) return slug.Error!;
        Title = i.Title.Trim(); Slug = slug.Value; Content = i.Content; MetaTitle = Clean(i.MetaTitle); MetaDescription = Clean(i.MetaDescription);
        if (i.IsPublished && !IsPublished) PublishedAt = nowUtc;
        IsPublished = i.IsPublished;
        return Result.Success();
    }

    /// <summary>Gọi trước khi xóa: đổi đường dẫn để trang mới dùng lại được (ràng buộc UNIQUE vẫn tính dòng đã xóa mềm).</summary>
    public void ReleaseSlug() => Slug = $"{Slug}~{Id}";

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

/// <summary>web.PostCategories - chuyên mục blog (Phối đồ, Xu hướng, Tin cửa hàng).</summary>
public sealed class PostCategory
{
    private PostCategory() { }
    public long Id { get; private set; }
    public long SiteId { get; private set; }
    public long? ParentId { get; private set; }
    public string Slug { get; private set; } = "";
    public string Name { get; private set; } = "";

    public static Result<PostCategory> Create(long siteId, string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return Error.Validation("category.name", "Nhập tên chuyên mục.");
        var slug = Website.Slug.Clean(null, name);
        return slug.IsFailure ? slug.Error! : new PostCategory { SiteId = siteId, Name = name.Trim(), Slug = slug.Value };
    }
}

/// <summary>web.Posts - bài viết blog / tin tức.</summary>
public sealed class Post : IAuditable, ISoftDelete
{
    private Post() { }
    public long Id { get; private set; }
    public long SiteId { get; private set; }
    public long? CategoryId { get; private set; }
    public string Slug { get; private set; } = "";
    public string Title { get; private set; } = "";
    public string? Summary { get; private set; }
    public string? Content { get; private set; }
    public string? ThumbnailUrl { get; private set; }
    public long? AuthorUserId { get; private set; }
    public string? MetaTitle { get; private set; }
    public string? MetaDescription { get; private set; }
    public bool IsPublished { get; private set; }
    public DateTime? PublishedAt { get; private set; }
    public long ViewCount { get; private set; }
    public DateTime CreatedAt { get; set; }
    public long? CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public long? UpdatedBy { get; set; }
    public bool IsDeleted { get; set; }

    public static Result<Post> Create(long siteId, long authorId, ContentInfo info, DateTime nowUtc)
    {
        var p = new Post { SiteId = siteId, AuthorUserId = authorId };
        var r = p.Update(info, nowUtc);
        return r.IsFailure ? r.Error! : p;
    }

    public Result Update(ContentInfo i, DateTime nowUtc)
    {
        if (string.IsNullOrWhiteSpace(i.Title)) return Error.Validation("post.title", "Nhập tiêu đề.");
        if (i.Summary?.Length > 1000) return Error.Validation("post.summary", "Tóm tắt tối đa 1000 ký tự.");
        var slug = Website.Slug.Clean(i.Slug, i.Title);
        if (slug.IsFailure) return slug.Error!;
        Title = i.Title.Trim(); Slug = slug.Value; Summary = Clean(i.Summary); Content = i.Content; ThumbnailUrl = Clean(i.ThumbnailUrl);
        CategoryId = i.CategoryId; MetaTitle = Clean(i.MetaTitle); MetaDescription = Clean(i.MetaDescription);
        if (i.IsPublished && !IsPublished) PublishedAt = nowUtc;
        IsPublished = i.IsPublished;
        return Result.Success();
    }


    /// <summary>Gọi trước khi xóa: đổi đường dẫn để bài mới dùng lại được.</summary>
    public void ReleaseSlug() => Slug = $"{Slug}~{Id}";

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

/// <summary>web.Menus - menu đầu trang ('header') / chân trang ('footer').</summary>
public sealed class Menu
{
    private Menu() { }
    public long Id { get; private set; }
    public long SiteId { get; private set; }
    public string Code { get; private set; } = "header";

    private readonly List<MenuItem> _items = [];
    public IReadOnlyList<MenuItem> Items => _items;

    public static Menu Create(long siteId, string code) => new() { SiteId = siteId, Code = code };

    /// <summary>Thay toàn bộ mục menu (1 cấp) theo thứ tự gửi lên.</summary>
    public Result ReplaceItems(IReadOnlyList<(string Label, string Url, bool NewTab)> items)
    {
        if (items.Count > 30) return Error.Validation("menu.limit", "Menu tối đa 30 mục.");
        foreach (var (label, url, _) in items)
        {
            if (string.IsNullOrWhiteSpace(label) || label.Trim().Length > 100) return Error.Validation("menu.label", "Tên mục menu 1-100 ký tự.");
            var u = (url ?? "").Trim();
            if (u.Length is 0 or > 500 || !(u.StartsWith('/') || u.StartsWith("https://") || u.StartsWith("http://") || u.StartsWith('#')))
                return Error.Validation("menu.url", $"Đường dẫn của \"{label}\" phải bắt đầu bằng / hoặc https://");
        }
        _items.Clear();
        var order = 0;
        foreach (var (label, url, newTab) in items) _items.Add(new MenuItem(label.Trim(), url.Trim(), order += 10, newTab));
        return Result.Success();
    }
}

public sealed class MenuItem
{
    private MenuItem() { }
    internal MenuItem(string label, string url, int sortOrder, bool newTab) { Label = label; Url = url; SortOrder = sortOrder; OpenNewTab = newTab; }
    public long Id { get; private set; }
    public long MenuId { get; private set; }
    public long? ParentId { get; private set; }
    public string Label { get; private set; } = "";
    public string Url { get; private set; } = "";
    public int SortOrder { get; private set; }
    public bool OpenNewTab { get; private set; }
}

/// <summary>web.ContactSubmissions - khách gửi form liên hệ trên website; nhân viên chuyển thành Lead trong CRM.</summary>
public sealed class ContactSubmission
{
    private ContactSubmission() { }
    public long Id { get; private set; }
    public long SiteId { get; private set; }
    public string FormCode { get; private set; } = "contact";
    public string FullName { get; private set; } = "";
    public string? Phone { get; private set; }
    public string? Email { get; private set; }
    public string? Message { get; private set; }
    public string? PageUrl { get; private set; }
    public string? UtmSource { get; private set; }
    public string? UtmMedium { get; private set; }
    public string? UtmCampaign { get; private set; }
    public string? IpAddress { get; private set; }
    public bool ConsentGiven { get; private set; }
    public long? LeadId { get; private set; }
    public DateTime CreatedAt { get; private set; }

    public static Result<ContactSubmission> Create(long siteId, string fullName, string? phone, string? email, string? message, string? pageUrl,
        string? utmSource, string? utmMedium, string? utmCampaign, string? ip, bool consent, DateTime nowUtc)
    {
        if (string.IsNullOrWhiteSpace(fullName) || fullName.Trim().Length > 150) return Error.Validation("contact.name", "Nhập họ tên (tối đa 150 ký tự).");
        var p = PhoneNumber.Normalize(phone);
        var e = string.IsNullOrWhiteSpace(email) ? null : email.Trim().ToLowerInvariant();
        if (p is null && e is null) return Error.Validation("contact.reach", "Nhập số điện thoại hoặc email.");
        if (p is not null && !PhoneNumber.IsValid(p)) return Error.Validation("contact.phone", "Số điện thoại không hợp lệ.");
        if (e is not null && (e.Length > 255 || !e.Contains('@') || e.StartsWith('@') || e.EndsWith('@'))) return Error.Validation("contact.email", "Email không hợp lệ.");
        if (message?.Length > 2000) return Error.Validation("contact.message", "Nội dung tối đa 2000 ký tự.");
        return new ContactSubmission
        {
            SiteId = siteId, FullName = fullName.Trim(), Phone = p, Email = e, Message = string.IsNullOrWhiteSpace(message) ? null : message.Trim(),
            PageUrl = Trunc(pageUrl, 1000), UtmSource = Trunc(utmSource, 100), UtmMedium = Trunc(utmMedium, 100), UtmCampaign = Trunc(utmCampaign, 100),
            IpAddress = Trunc(ip, 45), ConsentGiven = consent, CreatedAt = nowUtc
        };
    }

    public Result LinkLead(long leadId)
    {
        if (LeadId is not null) return Error.Conflict("contact.converted", "Liên hệ này đã chuyển thành khách tiềm năng.");
        LeadId = leadId;
        return Result.Success();
    }

    private static string? Trunc(string? s, int max) => string.IsNullOrWhiteSpace(s) ? null : s.Trim() is var t && t.Length > max ? t[..max] : s.Trim();
}
