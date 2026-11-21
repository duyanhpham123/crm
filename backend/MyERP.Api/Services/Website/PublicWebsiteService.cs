using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.MasterData;
using MyERP.Api.Models.Entities.Website;
using MyERP.Api.Services.Common;
using MyERP.Api.Services.Sales;

namespace MyERP.Api.Services.Website;

public interface IPublicWebsiteService
{
    Task<PublicSite> SiteAsync(CancellationToken ct);
    Task<IReadOnlyList<PublicProduct>> ProductsAsync(string? category, string? search, bool featuredOnly, string? sort, CancellationToken ct);
    Task<Result<PublicProductDetail>> ProductAsync(string slug, CancellationToken ct);
    Task<IReadOnlyList<PublicPost>> PostsAsync(string? category, CancellationToken ct);
    Task<Result<PublicPost>> PostAsync(string slug, CancellationToken ct);
    Task<Result<WebPageDto>> PageAsync(string slug, CancellationToken ct);
    Task<Result> SubmitContactAsync(PublicContactRequest request, string? ip, CancellationToken ct);
    Task<Result<PublicPromotion>> CheckPromotionAsync(string code, decimal subTotal, CancellationToken ct);
    Task<Result<PublicOrderResult>> PlaceOrderAsync(PublicOrderRequest request, CancellationToken ct);
}

/// <summary>
/// API cho website tự code (Next.js...). Request đã được xác thực bằng khóa website (SiteKeyAuthenticationHandler) nên biết
/// website nào, công ty nào: bộ lọc công ty chạy như bình thường, dữ liệu chỉ lấy của website đó.
/// Sản phẩm = các mẫu website bày bán (web.SiteProducts), giá / tồn kho đọc trực tiếp từ Kho -> sửa ở ERP là web đổi theo.
/// </summary>
public sealed class PublicWebsiteService(AppDbContext db, IHttpContextAccessor http, ICurrentUser currentUser, IOrderService orders,
    IDocumentNumberService docNumbers, TimeProvider clock) : IPublicWebsiteService
{
    public const int MaxProducts = 500;
    public const int MaxQuantityPerItem = 20;
    public const int MaxItems = 30;
    /// <summary>Số lượng còn bán hiển thị tối đa - không lộ tồn kho thật cho đối thủ.</summary>
    public const int AvailableCap = 99;
    public const decimal DefaultShippingFee = 30_000;

    private long SiteId => long.TryParse(http.HttpContext?.User.FindFirst(SiteKeyDefaults.SiteIdClaim)?.Value, out var id)
        ? id : throw new UnauthorizedAccessException("Thiếu khóa website.");

    private async Task<Site> LoadSiteAsync(CancellationToken ct) => await db.Sites.AsNoTracking().FirstAsync(s => s.Id == SiteId, ct);

    public async Task<PublicSite> SiteAsync(CancellationToken ct)
    {
        var site = await LoadSiteAsync(ct);
        var menus = await db.Menus.AsNoTracking().Where(m => m.SiteId == site.Id).Include(m => m.Items).ToListAsync(ct);
        List<MenuItemDto> Items(string code) => menus.FirstOrDefault(m => m.Code == code)?.Items.OrderBy(i => i.SortOrder)
            .Select(i => new MenuItemDto(i.Label, i.Url, i.OpenNewTab)).ToList() ?? [];
        var company = await db.Companies.AsNoTracking().Where(c => c.Id == site.CompanyId).Select(c => new { c.Name, c.TaxCode }).FirstOrDefaultAsync(ct);
        var categories = (await ProductsAsync(null, null, false, null, ct))
            .Where(p => p.CategorySlug != null).GroupBy(p => (p.CategorySlug!, p.Category!))
            .Select(g => new PublicCategory(g.Key.Item1, g.Key.Item2, g.Count())).OrderByDescending(c => c.Count).ToList();
        return new PublicSite(site.Name, site.Domain, site.LogoUrl, WebsiteService.ReadSettings(site.Settings), Items("header"), Items("footer"),
            categories, company?.Name, company?.TaxCode);
    }

    // ---------- Sản phẩm ----------

    private sealed record VariantRow(long Id, string Code, string? Color, string? Size, decimal Price, decimal Available);
    private sealed record ModelRow(long Id, string Code, string Name, string? Category, string? ImageUrl, string? Description, string? Material,
        string? Gender, decimal ModelPrice, decimal? PriceOverride, bool IsFeatured, int SortOrder, DateTime AddedAt, List<VariantRow> Variants);

    /// <summary>Mẫu đang bày trên website này, còn kinh doanh, kèm các biến thể đang bán và số lượng còn bán được.</summary>
    private async Task<List<ModelRow>> ListedAsync(IQueryable<ProductModel>? filter, CancellationToken ct)
    {
        var siteId = SiteId;
        var site = await LoadSiteAsync(ct);
        var q = (filter ?? db.ProductModels).Where(m => m.IsActive && db.SiteProducts.Any(sp => sp.SiteId == siteId && sp.ModelId == m.Id));
        var rows = await q.AsNoTracking().Take(MaxProducts).Select(m => new
        {
            m.Id, m.Code, m.Name, m.ImageUrl, m.Description, m.Material, m.Gender, m.SalePrice,
            Category = db.ProductCategories.Where(c => c.Id == m.CategoryId).Select(c => c.Name).FirstOrDefault(),
            Listing = db.SiteProducts.Where(sp => sp.SiteId == siteId && sp.ModelId == m.Id).Select(sp => new { sp.PriceOverride, sp.IsFeatured, sp.SortOrder, sp.AddedAt }).First(),
            Variants = m.Variants.Where(v => v.IsActive && v.IsSellable).OrderBy(v => v.Id).Select(v => new
            {
                v.Id, v.Code, v.Color, v.Size, v.SalePrice,
                Available = db.StockBalances.Where(b => b.ProductId == v.Id && (site.WarehouseId == null || b.WarehouseId == site.WarehouseId))
                    .Sum(b => (decimal?)(b.QtyOnHand - b.QtyReserved)) ?? 0,
            }).ToList(),
        }).ToListAsync(ct);
        return rows.Select(m => new ModelRow(m.Id, m.Code, m.Name, m.Category, m.ImageUrl, m.Description, m.Material, m.Gender, m.SalePrice,
            m.Listing.PriceOverride, m.Listing.IsFeatured, m.Listing.SortOrder, m.Listing.AddedAt,
            m.Variants.Select(v => new VariantRow(v.Id, v.Code, v.Color, v.Size, m.Listing.PriceOverride ?? v.SalePrice, Math.Max(0, v.Available))).ToList()))
            .Where(m => m.Variants.Count > 0).ToList();
    }

    private static PublicProduct ToSummary(ModelRow m)
    {
        var prices = m.Variants.Select(v => v.Price).ToList();
        var min = prices.Min();
        var max = prices.Max();
        return new PublicProduct(WebsiteService.ModelSlug(m.Name, m.Code), m.Code, m.Name, m.Category, m.Category is null ? null : Slug.From(m.Category),
            min, max > min ? max : null, m.ImageUrl, m.Description,
            m.Variants.Select(v => v.Color).Where(c => c != null).Distinct().ToList()!,
            SortSizes(m.Variants.Select(v => v.Size).Where(s => s != null).Distinct()!),
            m.Variants.Any(v => v.Available > 0), m.IsFeatured);
    }

    /// <summary>Size chữ theo thứ tự S &lt; M &lt; L..., size số theo số.</summary>
    private static List<string> SortSizes(IEnumerable<string> sizes)
    {
        string[] order = ["XXS", "XS", "S", "M", "L", "XL", "XXL", "2XL", "3XL", "FREESIZE"];
        return sizes.OrderBy(s => Array.IndexOf(order, s.ToUpperInvariant()) is var i && i >= 0 ? i : 100)
            .ThenBy(s => decimal.TryParse(s, out var n) ? n : decimal.MaxValue).ThenBy(s => s).ToList();
    }

    public async Task<IReadOnlyList<PublicProduct>> ProductsAsync(string? category, string? search, bool featuredOnly, string? sort, CancellationToken ct)
    {
        IQueryable<ProductModel>? filter = null;
        if (!string.IsNullOrWhiteSpace(search)) { var s = search.Trim(); filter = db.ProductModels.Where(m => m.Name.Contains(s) || m.Code.Contains(s)); }
        var list = (await ListedAsync(filter, ct)).AsEnumerable();
        if (featuredOnly) list = list.Where(m => m.IsFeatured);
        var items = list.Select(m => (Row: m, Dto: ToSummary(m)));
        if (!string.IsNullOrWhiteSpace(category)) items = items.Where(x => x.Dto.CategorySlug == category.Trim().ToLowerInvariant());
        items = sort switch
        {
            "price_asc" => items.OrderBy(x => x.Dto.Price),
            "price_desc" => items.OrderByDescending(x => x.Dto.Price),
            "newest" => items.OrderByDescending(x => x.Row.AddedAt),
            _ => items.OrderByDescending(x => x.Row.IsFeatured).ThenBy(x => x.Row.SortOrder).ThenByDescending(x => x.Dto.InStock).ThenBy(x => x.Dto.Name),
        };
        return items.Select(x => x.Dto).ToList();
    }

    public async Task<Result<PublicProductDetail>> ProductAsync(string slug, CancellationToken ct)
    {
        var key = (slug ?? "").Trim().ToLowerInvariant();
        // Slug = tên + mã mẫu, mã nằm cuối: lọc theo mã trước cho nhanh rồi so khớp chính xác
        var code = key.Split('-').LastOrDefault() ?? "";
        var all = await ListedAsync(db.ProductModels.Where(m => m.Code == code), ct);
        var m = all.FirstOrDefault(x => WebsiteService.ModelSlug(x.Name, x.Code) == key);
        if (m is null) return Error.NotFound("sản phẩm");
        var s = ToSummary(m);
        var related = (await ProductsAsync(s.CategorySlug, null, false, null, ct)).Where(p => p.Slug != s.Slug).Take(8).ToList();
        return new PublicProductDetail(s.Slug, s.Code, s.Name, s.Category, s.CategorySlug, s.Price, s.MaxPrice, s.ImageUrl, s.Description, m.Material,
            m.Gender, s.Colors, s.Sizes, s.InStock,
            m.Variants.Select(v => new PublicVariant(v.Code, v.Color, v.Size, v.Price, v.Available > 0, (int)Math.Min(AvailableCap, Math.Floor(v.Available)))).ToList(),
            related);
    }

    // ---------- Bài viết, trang ----------

    private IQueryable<Post> PublishedPosts() { var siteId = SiteId; return db.Posts.Where(p => p.SiteId == siteId && p.IsPublished); }

    public async Task<IReadOnlyList<PublicPost>> PostsAsync(string? category, CancellationToken ct)
    {
        var q = PublishedPosts().AsNoTracking();
        if (!string.IsNullOrWhiteSpace(category)) q = q.Where(p => db.PostCategories.Any(c => c.Id == p.CategoryId && c.Slug == category));
        return await q.OrderByDescending(p => p.PublishedAt).Take(100)
            .Select(p => new PublicPost(p.Slug, p.Title, p.Summary, null, p.ThumbnailUrl,
                db.PostCategories.Where(c => c.Id == p.CategoryId).Select(c => c.Name).FirstOrDefault(), p.PublishedAt)).ToListAsync(ct);
    }

    public async Task<Result<PublicPost>> PostAsync(string slug, CancellationToken ct)
    {
        var p = await PublishedPosts().AsNoTracking().FirstOrDefaultAsync(x => x.Slug == slug, ct);
        if (p is null) return Error.NotFound("bài viết");
        // Tăng lượt xem trực tiếp trong DB: không đụng UpdatedAt và không báo website làm mới
        await db.Posts.Where(x => x.Id == p.Id).ExecuteUpdateAsync(s => s.SetProperty(x => x.ViewCount, x => x.ViewCount + 1), ct);
        var category = await db.PostCategories.Where(c => c.Id == p.CategoryId).Select(c => c.Name).FirstOrDefaultAsync(ct);
        return new PublicPost(p.Slug, p.Title, p.Summary, p.Content, p.ThumbnailUrl, category, p.PublishedAt);
    }

    public async Task<Result<WebPageDto>> PageAsync(string slug, CancellationToken ct)
    {
        var siteId = SiteId;
        var p = await db.WebPages.AsNoTracking().FirstOrDefaultAsync(x => x.SiteId == siteId && x.IsPublished && x.Slug == slug, ct);
        return p is null ? Error.NotFound("trang") : new WebPageDto(p.Id, p.Title, p.Slug, p.Content, p.MetaTitle, p.MetaDescription, true, p.PublishedAt, p.UpdatedAt);
    }

    // ---------- Liên hệ ----------

    public async Task<Result> SubmitContactAsync(PublicContactRequest r, string? ip, CancellationToken ct)
    {
        // Ô "Website" bị ẩn trên form: người thật để trống; bot tự điền thì bỏ qua (vẫn báo thành công)
        if (!string.IsNullOrEmpty(r.Website)) return Result.Success();
        var now = clock.GetUtcNow().UtcDateTime;
        var siteId = SiteId;
        if (ip is not null && await db.ContactSubmissions.CountAsync(c => c.SiteId == siteId && c.IpAddress == ip && c.CreatedAt > now.AddMinutes(-10), ct) >= 5)
            return Error.Validation("contact.too_many", "Bạn gửi quá nhiều lần, vui lòng thử lại sau ít phút.");
        var created = ContactSubmission.Create(siteId, r.FullName, r.Phone, r.Email, r.Message, r.PageUrl, r.UtmSource, r.UtmMedium, r.UtmCampaign, ip, r.Consent, now);
        if (created.IsFailure) return created.Error!;
        db.ContactSubmissions.Add(created.Value);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    // ---------- Đặt hàng ----------

    private static decimal ShippingFeeFor(SiteSettings s, decimal subTotal)
        => s.FreeShippingFrom is { } free && subTotal >= free ? 0 : s.ShippingFee ?? DefaultShippingFee;

    public async Task<Result<PublicPromotion>> CheckPromotionAsync(string code, decimal subTotal, CancellationToken ct)
    {
        var settings = WebsiteService.ReadSettings((await LoadSiteAsync(ct)).Settings);
        var r = await orders.CheckPromotionAsync(code, subTotal, ShippingFeeFor(settings, subTotal), "website", ct);
        return r.IsFailure ? r.Error! : new PublicPromotion(r.Value.Code, r.Value.Name, r.Value.Discount);
    }

    /// <summary>
    /// Tạo đơn Nháp kênh "website" (shop gọi xác nhận rồi bấm Xác nhận như đơn thường). Giá, phí ship, mã giảm giá tính lại ở đây;
    /// khách tìm theo số điện thoại, chưa có thì tạo khách hàng mới. Ghi web.Carts để biết đơn đến từ website nào.
    /// </summary>
    public async Task<Result<PublicOrderResult>> PlaceOrderAsync(PublicOrderRequest r, CancellationToken ct)
    {
        var name = r.CustomerName?.Trim() ?? "";
        if (name.Length is < 2 or > 150) return Error.Validation("order.name", "Nhập họ tên người nhận.");
        if (!PhoneNumber.IsValid(r.Phone)) return Error.Validation("order.phone", "Số điện thoại không hợp lệ.");
        var phone = PhoneNumber.Normalize(r.Phone)!;
        var address = r.Address?.Trim() ?? "";
        if (address.Length is < 10 or > 500) return Error.Validation("order.address", "Nhập địa chỉ giao hàng đầy đủ (số nhà, đường, phường, quận, tỉnh).");
        if (r.PaymentMethod is not ("cod" or "bank_transfer")) return Error.Validation("order.payment", "Chọn thanh toán khi nhận hàng hoặc chuyển khoản.");
        var email = string.IsNullOrWhiteSpace(r.Email) ? null : r.Email.Trim();
        if (email is not null && (email.Length > 200 || !email.Contains('@'))) return Error.Validation("order.email", "Email không hợp lệ.");
        if (r.Note?.Length > 500) return Error.Validation("order.note", "Ghi chú tối đa 500 ký tự.");
        var items = (r.Items ?? []).GroupBy(i => (i.Sku ?? "").Trim().ToUpperInvariant())
            .Select(g => new PublicOrderItem(g.Key, g.Sum(x => x.Quantity))).ToList();
        if (items.Count == 0) return Error.Validation("order.empty", "Giỏ hàng đang trống.");
        if (items.Count > MaxItems) return Error.Validation("order.too_many", $"Mỗi đơn tối đa {MaxItems} sản phẩm khác nhau.");
        if (items.Any(i => i.Quantity is < 1 or > MaxQuantityPerItem)) return Error.Validation("order.quantity", $"Số lượng mỗi sản phẩm từ 1 đến {MaxQuantityPerItem}.");

        // Giá & tồn: chỉ SKU thuộc mẫu đang bày trên website này
        var skus = items.Select(i => i.Sku).ToList();
        var listed = await ListedAsync(db.ProductModels.Where(m => m.Variants.Any(v => skus.Contains(v.Code))), ct);
        var variants = listed.SelectMany(m => m.Variants.Select(v => (Model: m, Variant: v))).ToDictionary(x => x.Variant.Code.ToUpperInvariant());
        var lines = new List<(VariantRow V, string Name, int Qty)>();
        foreach (var i in items)
        {
            if (!variants.TryGetValue(i.Sku, out var x)) return Error.Validation("order.sku", $"Sản phẩm {i.Sku} không còn bán trên website.");
            if (x.Variant.Available < i.Quantity)
                return Error.Validation("order.stock", x.Variant.Available <= 0
                    ? $"{x.Model.Name} ({x.Variant.Color} {x.Variant.Size}) đã hết hàng."
                    : $"{x.Model.Name} ({x.Variant.Color} {x.Variant.Size}) chỉ còn {Math.Floor(x.Variant.Available)}.");
            lines.Add((x.Variant, string.Join(" - ", new[] { x.Model.Name, x.Variant.Color, x.Variant.Size }.Where(s => !string.IsNullOrEmpty(s))), i.Quantity));
        }
        var subTotal = lines.Sum(l => l.V.Price * l.Qty);
        var site = await LoadSiteAsync(ct);
        var shippingFee = ShippingFeeFor(WebsiteService.ReadSettings(site.Settings), subTotal);

        var customerId = await FindOrCreateCustomerAsync(name, phone, email, address, ct);
        if (customerId.IsFailure) return customerId.Error!;
        var note = string.Join(" | ", new[] { $"Đặt từ website {site.Domain}", email is null ? null : $"Email: {email}", r.Note?.Trim() }
            .Where(x => !string.IsNullOrEmpty(x)));
        var created = await orders.CreateAsync(new SaveOrderRequest(customerId.Value, "website", site.WarehouseId, name, phone, address, shippingFee, 0,
            r.PaymentMethod, note, lines.Select(l => new OrderLineRequest(l.V.Id, l.Qty, l.V.Price, 0)).ToList(), null,
            string.IsNullOrWhiteSpace(r.PromotionCode) ? null : r.PromotionCode.Trim()), ct);
        if (created.IsFailure) return created.Error!;
        var o = created.Value;
        db.ChangeTracker.Clear();
        db.WebCarts.Add(WebCart.ForOrder(site.Id, o.Id, o.PromotionCode, clock.GetUtcNow().UtcDateTime));
        await db.SaveChangesAsync(ct);
        return new PublicOrderResult(o.DocNo, lines.Select(l => new PublicOrderLine(l.V.Code, l.Name, l.Qty, l.V.Price, l.V.Price * l.Qty)).ToList(),
            o.SubTotal, o.DiscountAmount, o.ShippingFee, o.TotalAmount, r.PaymentMethod,
            r.PaymentMethod == "bank_transfer"
                ? $"Đặt hàng thành công! Vui lòng chuyển khoản với nội dung \"{o.DocNo}\". Cửa hàng sẽ gọi xác nhận sớm."
                : "Đặt hàng thành công! Cửa hàng sẽ gọi xác nhận và giao hàng sớm.");
    }

    /// <summary>Khách cũ (trùng số điện thoại) thì dùng lại, chưa có thì tạo khách hàng cá nhân mới.</summary>
    private async Task<Result<long>> FindOrCreateCustomerAsync(string name, string phone, string? email, string address, CancellationToken ct)
    {
        var existing = await db.Partners.Where(p => p.IsCustomer && p.Phone == phone).Select(p => (long?)p.Id).FirstOrDefaultAsync(ct);
        if (existing is { } id) return id;
        var info = new PartnerInfo(PartnerType: Partner.Individual, Name: name, ShortName: null, TaxCode: null, Phone: phone, Email: email, Website: null,
            Industry: null, Street: address, CustomerGroupId: null, OwnerUserId: null, Source: "website", Note: "Khách đặt hàng từ website");
        var partner = Partner.CreateCustomer(currentUser.RequireCompanyId(), await docNumbers.NextAsync("PARTNER", ct: ct), info);
        db.Partners.Add(partner);
        await db.SaveChangesAsync(ct);
        return partner.Id;
    }
}
