using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Sales;
using MyERP.Api.Models.Entities.Website;
using MyERP.Api.Services.Common;
using MyERP.Api.Services.Crm;
using MyERP.Api.Services.Sales;

namespace MyERP.Api.Services.Website;

public interface IWebsiteService
{
    Task<WebsiteOverview> OverviewAsync(long? siteId, CancellationToken ct);
    Task<SiteDto> GetSiteAsync(long? siteId, CancellationToken ct);
    Task<Result<SiteDto>> SaveSiteAsync(long? siteId, SaveSiteRequest request, CancellationToken ct);
    Task<IReadOnlyList<WebPageDto>> PagesAsync(long? siteId, CancellationToken ct);
    Task<Result<WebPageDto>> SavePageAsync(long? siteId, long? id, SaveContentRequest request, CancellationToken ct);
    Task<Result> DeletePageAsync(long? siteId, long id, CancellationToken ct);
    Task<PagedResult<PostListItem>> PostsAsync(long? siteId, string? search, long? categoryId, string? state, int page, int pageSize, CancellationToken ct);
    Task<Result<PostDetail>> GetPostAsync(long? siteId, long id, CancellationToken ct);
    Task<Result<PostDetail>> SavePostAsync(long? siteId, long? id, SaveContentRequest request, CancellationToken ct);
    Task<Result> DeletePostAsync(long? siteId, long id, CancellationToken ct);
    Task<IReadOnlyList<OptionDto>> CategoriesAsync(long? siteId, CancellationToken ct);
    Task<Result<OptionDto>> CreateCategoryAsync(long? siteId, string name, CancellationToken ct);
    Task<PagedResult<WebProductRow>> ProductsAsync(long? siteId, string? search, string? state, int page, int pageSize, CancellationToken ct);
    Task<Result<WebProductRow>> PublishModelAsync(long? siteId, long modelId, WebProductUpdate update, CancellationToken ct);
    Task<IReadOnlyList<SiteListItem>> SitesAsync(CancellationToken ct);
    Task<Result<SiteDto>> CreateSiteAsync(SaveSiteRequest request, CancellationToken ct);
    Task<Result<ApiKeyResult>> IssueApiKeyAsync(long siteId, CancellationToken ct);
    Task<Result> RevokeApiKeyAsync(long siteId, CancellationToken ct);
    Task<Result<WebhookResult>> GetWebhookAsync(long siteId, CancellationToken ct);
    Task<Result<WebhookResult>> SaveWebhookAsync(long siteId, WebhookRequest request, CancellationToken ct);
    Task<Result<SyncResult>> RevalidateNowAsync(long siteId, CancellationToken ct);
    Task<MenuDto> MenuAsync(long? siteId, string code, CancellationToken ct);
    Task<Result<MenuDto>> SaveMenuAsync(long? siteId, string code, SaveMenuRequest request, CancellationToken ct);
    Task<PagedResult<WebContactDto>> ContactsAsync(long? siteId, string? state, string? search, int page, int pageSize, CancellationToken ct);
    Task<Result<WebContactDto>> ConvertContactAsync(long? siteId, long id, CancellationToken ct);
}

/// <summary>
/// Quản trị website bán hàng: thông tin site, trang tĩnh, bài viết, menu, bật / tắt sản phẩm hiện trên web,
/// liên hệ khách gửi từ form (chuyển thành Lead CRM). Đơn online nằm ở app Đơn hàng với kênh "website".
/// </summary>
public sealed class WebsiteService(AppDbContext db, ICurrentUser currentUser, ILeadService leads, IRevalidationQueue revalidation, TimeProvider clock) : IWebsiteService
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private DateTime NowUtc => clock.GetUtcNow().UtcDateTime;

    /// <summary>Website đang thao tác: theo siteId, không truyền thì website đầu tiên. Công ty chưa có website nào thì tạo theo tên công ty.</summary>
    private async Task<Site> SiteAsync(long? siteId, CancellationToken ct)
    {
        if (siteId is { } id)
            return await db.Sites.FirstOrDefaultAsync(s => s.Id == id, ct) ?? throw new KeyNotFoundException("Không tìm thấy website.");
        var site = await db.Sites.OrderBy(s => s.Id).FirstOrDefaultAsync(ct);
        if (site is not null) return site;
        var company = await db.Companies.FirstAsync(c => c.Id == currentUser.RequireCompanyId(), ct);
        var baseDomain = Slug.From(company.ShortName ?? company.Name).Replace("-", "");
        var domain = $"{(baseDomain.Length == 0 ? "shop" : baseDomain)}.vn";
        if (await db.Sites.IgnoreQueryFilters().AnyAsync(s => s.Domain == domain, ct)) domain = $"{company.Id}-{domain}";
        site = Site.Create(company.Id, new SiteInfo(company.ShortName ?? company.Name, domain, null, null, true)).Value;
        site.SetBot(await BotUserIdAsync(company.Id, ct));
        db.Sites.Add(site);
        await db.SaveChangesAsync(ct);
        return site;
    }

    internal static SiteSettings ReadSettings(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new SiteSettings(null, null, null, null, null, null, null, null, null, null);
        try { return JsonSerializer.Deserialize<SiteSettings>(json, Json) ?? ReadSettings(null); }
        catch (JsonException) { return ReadSettings(null); }
    }

    private static SiteDto ToDto(Site s) => new(s.Id, s.Name, s.Domain, s.LogoUrl, s.IsActive, ReadSettings(s.Settings));

    public async Task<WebsiteOverview> OverviewAsync(long? siteId, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        var now = NowUtc;
        var local = now.AddHours(7);
        var monthStartUtc = new DateTime(local.Year, local.Month, 1).AddHours(-7);
        var since = now.AddDays(-30);
        var models = db.ProductModels.Where(m => m.IsActive);
        // Đơn của website này: đặt qua API (có web.Carts ghi website), không tính đơn hủy
        var online = db.SalesOrders.Where(o => o.Channel == "website" && o.OrderDate >= since && o.Status != OrderStatuses.Cancelled
            && db.WebCarts.Any(c => c.SiteId == site.Id && c.SalesOrderId == o.Id));
        var recent = await ContactsQuery(site.Id, db.ContactSubmissions.Where(c => c.SiteId == site.Id).OrderByDescending(c => c.Id).Take(5)).ToListAsync(ct);
        var top = await db.Posts.Where(p => p.SiteId == site.Id && p.IsPublished).OrderByDescending(p => p.ViewCount).Take(5)
            .Select(p => new WebPostRow(p.Id, p.Title, p.ViewCount, p.PublishedAt)).ToListAsync(ct);
        return new WebsiteOverview(ToDto(site),
            await db.SiteProducts.CountAsync(sp => sp.SiteId == site.Id && models.Any(m => m.Id == sp.ModelId), ct),
            await models.CountAsync(ct),
            await db.Posts.CountAsync(p => p.SiteId == site.Id && p.IsPublished, ct),
            await db.Posts.CountAsync(p => p.SiteId == site.Id && !p.IsPublished, ct),
            await db.WebPages.CountAsync(p => p.SiteId == site.Id, ct),
            await db.ContactSubmissions.CountAsync(c => c.SiteId == site.Id && c.LeadId == null, ct),
            await db.ContactSubmissions.CountAsync(c => c.SiteId == site.Id && c.CreatedAt >= monthStartUtc, ct),
            await online.CountAsync(ct),
            await online.SumAsync(o => (decimal?)(o.TotalAmount - o.ReturnedAmount), ct) ?? 0,
            recent, top);
    }

    public async Task<SiteDto> GetSiteAsync(long? siteId, CancellationToken ct) => ToDto(await SiteAsync(siteId, ct));

    public async Task<Result<SiteDto>> SaveSiteAsync(long? siteId, SaveSiteRequest r, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        var settings = r.Settings is null ? site.Settings : JsonSerializer.Serialize(r.Settings, Json);
        if (r.Settings is { } st && (st.ShippingFee < 0 || st.FreeShippingFrom < 0)) return Error.Validation("site.shipping", "Phí giao hàng không hợp lệ.");
        if (r.Settings?.PrimaryColor is { Length: > 0 } color && !(color.Length == 7 && color[0] == '#' && color[1..].All(char.IsAsciiHexDigit)))
            return Error.Validation("site.color", "Màu chủ đạo dạng #RRGGBB.");
        var u = site.Update(new SiteInfo(r.Name, r.Domain, r.LogoUrl, settings, r.IsActive));
        if (u.IsFailure) return u.Error!;
        if (await db.Sites.IgnoreQueryFilters().AnyAsync(s => s.Id != site.Id && s.Domain == site.Domain, ct))
            return Error.Conflict("site.domain_taken", "Tên miền đã được dùng.");
        await db.SaveChangesAsync(ct);
        return ToDto(site);
    }

    // ---------- Trang tĩnh ----------

    public async Task<IReadOnlyList<WebPageDto>> PagesAsync(long? siteId, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        return await db.WebPages.AsNoTracking().Where(p => p.SiteId == site.Id).OrderBy(p => p.Title)
            .Select(p => new WebPageDto(p.Id, p.Title, p.Slug, p.Content, p.MetaTitle, p.MetaDescription, p.IsPublished, p.PublishedAt, p.UpdatedAt ?? p.CreatedAt))
            .ToListAsync(ct);
    }

    public async Task<Result<WebPageDto>> SavePageAsync(long? siteId, long? id, SaveContentRequest r, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        var info = ToInfo(r);
        WebPage page;
        if (id is { } pid)
        {
            var existing = await db.WebPages.FirstOrDefaultAsync(p => p.Id == pid && p.SiteId == site.Id, ct);
            if (existing is null) return Error.NotFound("trang");
            var u = existing.Update(info, NowUtc);
            if (u.IsFailure) return u.Error!;
            page = existing;
        }
        else
        {
            var created = WebPage.Create(site.Id, info, NowUtc);
            if (created.IsFailure) return created.Error!;
            page = created.Value;
            db.WebPages.Add(page);
        }
        if (await db.WebPages.IgnoreQueryFilters([AppDbContext.SoftDeleteFilter]).AnyAsync(p => p.SiteId == site.Id && p.Slug == page.Slug && p.Id != page.Id, ct))
            return Error.Conflict("page.slug_taken", $"Đường dẫn /{page.Slug} đã có trang khác dùng.");
        await db.SaveChangesAsync(ct);
        return new WebPageDto(page.Id, page.Title, page.Slug, page.Content, page.MetaTitle, page.MetaDescription, page.IsPublished, page.PublishedAt,
            page.UpdatedAt ?? page.CreatedAt);
    }

    public async Task<Result> DeletePageAsync(long? siteId, long id, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        var p = await db.WebPages.FirstOrDefaultAsync(x => x.Id == id && x.SiteId == site.Id, ct);
        if (p is null) return Error.NotFound("trang");
        p.ReleaseSlug();
        db.WebPages.Remove(p);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    private static ContentInfo ToInfo(SaveContentRequest r) => new(r.Title, r.Slug, r.Summary, r.Content, r.ThumbnailUrl, r.CategoryId,
        r.MetaTitle, r.MetaDescription, r.IsPublished);

    // ---------- Bài viết ----------

    public async Task<PagedResult<PostListItem>> PostsAsync(long? siteId, string? search, long? categoryId, string? state, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var site = await SiteAsync(siteId, ct);
        var q = db.Posts.AsNoTracking().Where(p => p.SiteId == site.Id);
        if (!string.IsNullOrWhiteSpace(search)) { var s = search.Trim(); q = q.Where(p => p.Title.Contains(s)); }
        if (categoryId is { } cid) q = q.Where(p => p.CategoryId == cid);
        if (state == "published") q = q.Where(p => p.IsPublished);
        else if (state == "draft") q = q.Where(p => !p.IsPublished);
        var total = await q.CountAsync(ct);
        var items = await q.OrderByDescending(p => p.PublishedAt ?? p.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(p => new PostListItem(p.Id, p.Title, p.Slug, p.CategoryId, db.PostCategories.Where(c => c.Id == p.CategoryId).Select(c => c.Name).FirstOrDefault(),
                p.Summary, p.ThumbnailUrl, db.Users.Where(u => u.Id == p.AuthorUserId).Select(u => u.FullName).FirstOrDefault(), p.IsPublished, p.PublishedAt,
                p.ViewCount, p.CreatedAt)).ToListAsync(ct);
        return new PagedResult<PostListItem>(items, page, pageSize, total);
    }

    public async Task<Result<PostDetail>> GetPostAsync(long? siteId, long id, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        var p = await db.Posts.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.SiteId == site.Id, ct);
        return p is null ? Error.NotFound("bài viết") : ToDetail(p);
    }

    private static PostDetail ToDetail(Post p) => new(p.Id, p.Title, p.Slug, p.CategoryId, p.Summary, p.Content, p.ThumbnailUrl, p.MetaTitle,
        p.MetaDescription, p.IsPublished, p.PublishedAt, p.ViewCount);

    public async Task<Result<PostDetail>> SavePostAsync(long? siteId, long? id, SaveContentRequest r, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        if (r.CategoryId is { } cid && !await db.PostCategories.AnyAsync(c => c.Id == cid && c.SiteId == site.Id, ct))
            return Error.Validation("post.category", "Chuyên mục không hợp lệ.");
        var info = ToInfo(r);
        Post post;
        if (id is { } pid)
        {
            var existing = await db.Posts.FirstOrDefaultAsync(p => p.Id == pid && p.SiteId == site.Id, ct);
            if (existing is null) return Error.NotFound("bài viết");
            var u = existing.Update(info, NowUtc);
            if (u.IsFailure) return u.Error!;
            post = existing;
        }
        else
        {
            var created = Post.Create(site.Id, currentUser.RequireUserId(), info, NowUtc);
            if (created.IsFailure) return created.Error!;
            post = created.Value;
            db.Posts.Add(post);
        }
        if (await db.Posts.IgnoreQueryFilters([AppDbContext.SoftDeleteFilter]).AnyAsync(p => p.SiteId == site.Id && p.Slug == post.Slug && p.Id != post.Id, ct))
            return Error.Conflict("post.slug_taken", $"Đường dẫn {post.Slug} đã có bài khác dùng, đổi tiêu đề hoặc đường dẫn.");
        await db.SaveChangesAsync(ct);
        return ToDetail(post);
    }

    public async Task<Result> DeletePostAsync(long? siteId, long id, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        var p = await db.Posts.FirstOrDefaultAsync(x => x.Id == id && x.SiteId == site.Id, ct);
        if (p is null) return Error.NotFound("bài viết");
        p.ReleaseSlug();
        db.Posts.Remove(p);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<IReadOnlyList<OptionDto>> CategoriesAsync(long? siteId, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        return await db.PostCategories.Where(c => c.SiteId == site.Id).OrderBy(c => c.Name)
            .Select(c => new OptionDto(c.Id, c.Name, c.Slug)).ToListAsync(ct);
    }

    public async Task<Result<OptionDto>> CreateCategoryAsync(long? siteId, string name, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        var created = PostCategory.Create(site.Id, name);
        if (created.IsFailure) return created.Error!;
        if (await db.PostCategories.AnyAsync(c => c.SiteId == site.Id && c.Slug == created.Value.Slug, ct))
            return Error.Conflict("category.taken", "Chuyên mục đã có.");
        db.PostCategories.Add(created.Value);
        await db.SaveChangesAsync(ct);
        return new OptionDto(created.Value.Id, created.Value.Name, created.Value.Slug);
    }

    // ---------- Sản phẩm trên web ----------

    public static string ModelSlug(string name, string code) => Slug.From($"{name} {code}");

    public async Task<PagedResult<WebProductRow>> ProductsAsync(long? siteId, string? search, string? state, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var site = await SiteAsync(siteId, ct);
        var q = db.ProductModels.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(search)) { var s = search.Trim(); q = q.Where(m => m.Name.Contains(s) || m.Code.Contains(s)); }
        var listed = db.SiteProducts.Where(sp => sp.SiteId == site.Id);
        if (state == "published") q = q.Where(m => listed.Any(sp => sp.ModelId == m.Id));
        else if (state == "hidden") q = q.Where(m => !listed.Any(sp => sp.ModelId == m.Id));
        else if (state == "featured") q = q.Where(m => listed.Any(sp => sp.ModelId == m.Id && sp.IsFeatured));
        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(m => m.IsActive).ThenBy(m => m.Name).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(m => new
            {
                m.Id, m.Code, m.Name, m.SalePrice, m.IsActive, m.ImageUrl,
                Category = db.ProductCategories.Where(c => c.Id == m.CategoryId).Select(c => c.Name).FirstOrDefault(),
                Variants = m.Variants.Count, Active = m.Variants.Count(v => v.IsActive),
                Stock = db.StockBalances.Where(b => m.Variants.Select(v => v.Id).Contains(b.ProductId)).Sum(b => (decimal?)b.QtyOnHand) ?? 0,
                Listing = listed.Where(sp => sp.ModelId == m.Id).Select(sp => new { sp.PriceOverride, sp.IsFeatured }).FirstOrDefault(),
            }).ToListAsync(ct);
        var items = rows.Select(m => new WebProductRow(m.Id, m.Code, m.Name, m.Category, m.SalePrice, m.Variants, m.Active, m.Stock, m.ImageUrl,
            ModelSlug(m.Name, m.Code), m.Listing is not null, m.IsActive, m.Listing?.PriceOverride, m.Listing?.IsFeatured ?? false)).ToList();
        return new PagedResult<WebProductRow>(items, page, pageSize, total);
    }

    /// <summary>Bày / ẩn mẫu (mọi màu - size đang bán) trên 1 website, đặt giá riêng / nổi bật. Mẫu ngừng kinh doanh thì không bày được.</summary>
    public async Task<Result<WebProductRow>> PublishModelAsync(long? siteId, long modelId, WebProductUpdate u, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        var m = await db.ProductModels.Include(x => x.Variants).FirstOrDefaultAsync(x => x.Id == modelId, ct);
        if (m is null) return Error.NotFound("mẫu sản phẩm");
        var listing = await db.SiteProducts.FirstOrDefaultAsync(x => x.SiteId == site.Id && x.ModelId == modelId, ct);
        if (u.IsPublished)
        {
            if (!m.IsActive) return Error.Validation("web.inactive", "Mẫu đã ngừng kinh doanh, bật lại ở app Kho trước.");
            if (listing is null) { listing = SiteProduct.Create(site.Id, modelId, NowUtc); db.SiteProducts.Add(listing); }
            var r = listing.Update(u.PriceOverride, u.IsFeatured);
            if (r.IsFailure) return r.Error!;
        }
        else if (listing is not null) db.SiteProducts.Remove(listing);
        await db.SaveChangesAsync(ct);
        // Cờ cũ "hiện trên web" trên từng SKU = đang bày ở ít nhất 1 website
        var anySite = await db.SiteProducts.AnyAsync(x => x.ModelId == modelId, ct);
        foreach (var v in m.Variants) v.SetWebPublish(anySite && v.IsActive, Slug.From($"{m.Name} {v.Code}"));
        await db.SaveChangesAsync(ct);
        var page = await ProductsAsync(site.Id, m.Code, null, 1, 50, ct);
        return page.Items.First(x => x.ModelId == modelId);
    }

    // ---------- Quản lý nhiều website ----------

    public async Task<IReadOnlyList<SiteListItem>> SitesAsync(CancellationToken ct)
    {
        await SiteAsync(null, ct); // công ty chưa có website thì tạo website đầu tiên
        return await db.Sites.AsNoTracking().OrderBy(s => s.Id)
            .Select(s => new SiteListItem(s.Id, s.Name, s.Domain, s.IsActive, s.ApiKeyHash != null, s.ApiKeyPrefix, s.ApiKeyCreatedAt, s.RevalidateUrl,
                s.LastSyncAt, s.LastSyncStatus, db.SiteProducts.Count(sp => sp.SiteId == s.Id)))
            .ToListAsync(ct);
    }

    public async Task<Result<SiteDto>> CreateSiteAsync(SaveSiteRequest r, CancellationToken ct)
    {
        var company = currentUser.RequireCompanyId();
        var settings = r.Settings is null ? null : JsonSerializer.Serialize(r.Settings, Json);
        var created = Site.Create(company, new SiteInfo(r.Name, r.Domain, r.LogoUrl, settings, r.IsActive));
        if (created.IsFailure) return created.Error!;
        if (await db.Sites.IgnoreQueryFilters().AnyAsync(s => s.Domain == created.Value.Domain, ct))
            return Error.Conflict("site.domain_taken", "Tên miền đã được dùng.");
        created.Value.SetBot(await BotUserIdAsync(company, ct));
        created.Value.SetWarehouse(await db.Warehouses.OrderBy(w => w.Id).Select(w => (long?)w.Id).FirstOrDefaultAsync(ct));
        db.Sites.Add(created.Value);
        await db.SaveChangesAsync(ct);
        return ToDto(created.Value);
    }

    /// <summary>Tài khoản bot ghi đơn online của công ty (tạo lần đầu): không mật khẩu, không vai trò, đã khóa -> không đăng nhập được.</summary>
    private async Task<long> BotUserIdAsync(long companyId, CancellationToken ct)
    {
        var name = $"WEBSITE.BOT.{companyId}";
        var id = await db.Users.IgnoreQueryFilters().Where(u => u.NormalizedUserName == name).Select(u => (long?)u.Id).FirstOrDefaultAsync(ct);
        if (id is { } existing) return existing;
        await db.Database.ExecuteSqlInterpolatedAsync($@"INSERT core.Users (UserName, NormalizedUserName, FullName, DefaultCompanyId, IsActive, SecurityStamp, ConcurrencyStamp)
            VALUES ({name.ToLowerInvariant()}, {name}, {"Website (bán online)"}, {companyId}, 0, {Guid.NewGuid().ToString()}, {Guid.NewGuid().ToString()})", ct);
        return await db.Users.IgnoreQueryFilters().Where(u => u.NormalizedUserName == name).Select(u => u.Id).FirstAsync(ct);
    }

    /// <summary>Tạo khóa API mới cho website (khóa cũ hết hiệu lực ngay). Khóa gốc chỉ trả về 1 lần này.</summary>
    public async Task<Result<ApiKeyResult>> IssueApiKeyAsync(long siteId, CancellationToken ct)
    {
        var site = await db.Sites.FirstOrDefaultAsync(s => s.Id == siteId, ct);
        if (site is null) return Error.NotFound("website");
        if (site.BotUserId is null) site.SetBot(await BotUserIdAsync(site.CompanyId, ct));
        var key = site.IssueApiKey(NowUtc);
        await db.SaveChangesAsync(ct);
        return new ApiKeyResult(key, site.ApiKeyPrefix!);
    }

    public async Task<Result> RevokeApiKeyAsync(long siteId, CancellationToken ct)
    {
        var site = await db.Sites.FirstOrDefaultAsync(s => s.Id == siteId, ct);
        if (site is null) return Error.NotFound("website");
        site.RevokeApiKey();
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    /// <summary>Địa chỉ website nhận lệnh làm mới + mật khẩu (trả về để dán vào biến môi trường REVALIDATE_SECRET của website).</summary>
    public async Task<Result<WebhookResult>> SaveWebhookAsync(long siteId, WebhookRequest r, CancellationToken ct)
    {
        var site = await db.Sites.FirstOrDefaultAsync(s => s.Id == siteId, ct);
        if (site is null) return Error.NotFound("website");
        var u = site.SetWebhook(r.Url, r.NewSecret);
        if (u.IsFailure) return u.Error!;
        await db.SaveChangesAsync(ct);
        return new WebhookResult(site.RevalidateUrl, site.RevalidateSecret);
    }

    public async Task<Result<WebhookResult>> GetWebhookAsync(long siteId, CancellationToken ct)
    {
        var site = await db.Sites.AsNoTracking().FirstOrDefaultAsync(s => s.Id == siteId, ct);
        return site is null ? Error.NotFound("website") : new WebhookResult(site.RevalidateUrl, site.RevalidateSecret);
    }

    public async Task<Result<SyncResult>> RevalidateNowAsync(long siteId, CancellationToken ct)
    {
        if (!await db.Sites.AnyAsync(s => s.Id == siteId, ct)) return Error.NotFound("website");
        return new SyncResult(await revalidation.SendNowAsync(siteId, WebTags.All, ct));
    }

    // ---------- Menu ----------

    public async Task<MenuDto> MenuAsync(long? siteId, string code, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        var menu = await db.Menus.Include(x => x.Items).AsNoTracking().FirstOrDefaultAsync(x => x.SiteId == site.Id && x.Code == code, ct);
        return new MenuDto(code, menu?.Items.OrderBy(i => i.SortOrder).Select(i => new MenuItemDto(i.Label, i.Url, i.OpenNewTab)).ToList() ?? []);
    }

    public async Task<Result<MenuDto>> SaveMenuAsync(long? siteId, string code, SaveMenuRequest r, CancellationToken ct)
    {
        if (code is not ("header" or "footer")) return Error.Validation("menu.code", "Chỉ có menu header / footer.");
        var site = await SiteAsync(siteId, ct);
        var menu = await db.Menus.Include(x => x.Items).FirstOrDefaultAsync(x => x.SiteId == site.Id && x.Code == code, ct);
        if (menu is null) { menu = Menu.Create(site.Id, code); db.Menus.Add(menu); }
        var res = menu.ReplaceItems((r.Items ?? []).Select(i => (i.Label, i.Url, i.OpenNewTab)).ToList());
        if (res.IsFailure) return res.Error!;
        await db.SaveChangesAsync(ct);
        return await MenuAsync(site.Id, code, ct);
    }

    // ---------- Liên hệ ----------

    private IQueryable<WebContactDto> ContactsQuery(long siteId, IQueryable<ContactSubmission>? source = null)
        => (source ?? db.ContactSubmissions.Where(c => c.SiteId == siteId)).AsNoTracking()
            .Select(c => new WebContactDto(c.Id, c.FullName, c.Phone, c.Email, c.Message, c.PageUrl, c.UtmSource, c.UtmCampaign, c.CreatedAt, c.LeadId,
                db.Leads.Where(l => l.Id == c.LeadId).Select(l => l.Code).FirstOrDefault()));

    public async Task<PagedResult<WebContactDto>> ContactsAsync(long? siteId, string? state, string? search, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var site = await SiteAsync(siteId, ct);
        var q = db.ContactSubmissions.Where(c => c.SiteId == site.Id);
        if (state == "new") q = q.Where(c => c.LeadId == null);
        else if (state == "converted") q = q.Where(c => c.LeadId != null);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            var phone = PhoneNumber.Normalize(s);
            q = q.Where(c => c.FullName.Contains(s) || (c.Email != null && c.Email.Contains(s)) || (phone != null && phone != "" && c.Phone != null && c.Phone.Contains(phone)));
        }
        var total = await q.CountAsync(ct);
        var items = await ContactsQuery(site.Id, q.OrderByDescending(c => c.Id).Skip((page - 1) * pageSize).Take(pageSize)).ToListAsync(ct);
        return new PagedResult<WebContactDto>(items, page, pageSize, total);
    }

    /// <summary>Chuyển liên hệ thành khách tiềm năng (Lead) nguồn Website. Trùng SĐT / email với lead có sẵn thì gắn vào lead đó.</summary>
    public async Task<Result<WebContactDto>> ConvertContactAsync(long? siteId, long id, CancellationToken ct)
    {
        var site = await SiteAsync(siteId, ct);
        var c = await db.ContactSubmissions.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.SiteId == site.Id, ct);
        if (c is null) return Error.NotFound("liên hệ");
        if (c.LeadId is not null) return Error.Conflict("contact.converted", "Liên hệ này đã chuyển thành khách tiềm năng.");
        var leadId = await db.Leads.Where(l => (c.Phone != null && l.Phone == c.Phone) || (c.Email != null && l.Email == c.Email))
            .Select(l => (long?)l.Id).FirstOrDefaultAsync(ct);
        if (leadId is null)
        {
            var source = await db.LeadSources.Where(s => s.Code == "WEBSITE").Select(s => (long?)s.Id).FirstOrDefaultAsync(ct);
            var note = string.Join(" · ", new[] { c.Message, c.UtmCampaign is null ? null : $"Chiến dịch: {c.UtmCampaign}", c.PageUrl is null ? null : $"Trang: {c.PageUrl}" }
                .Where(x => !string.IsNullOrWhiteSpace(x)));
            var created = await leads.CreateAsync(new SaveLeadRequest(c.FullName, null, null, c.Phone, c.Email, null, source,
                note.Length > 1000 ? note[..1000] : note.Length == 0 ? null : note, null), ct);
            if (created.IsFailure) return created.Error!;
            leadId = created.Value.Id;
        }
        db.ChangeTracker.Clear();
        var tracked = await db.ContactSubmissions.FirstAsync(x => x.Id == id, ct);
        var link = tracked.LinkLead(leadId.Value);
        if (link.IsFailure) return link.Error!;
        await db.SaveChangesAsync(ct);
        return await ContactsQuery(site.Id, db.ContactSubmissions.Where(x => x.Id == id)).FirstAsync(ct);
    }
}
