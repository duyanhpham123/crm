using System.Diagnostics;
using System.Net.Http.Json;
using System.Threading.Channels;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using MyERP.Api.Data;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Models.Entities.Inventory;
using MyERP.Api.Models.Entities.MasterData;
using MyERP.Api.Models.Entities.Website;

namespace MyERP.Api.Services.Website;

/// <summary>
/// Nhóm dữ liệu website đang hiển thị. Next.js gắn tag khi fetch (next: { tags: ['products'] }) và gọi revalidateTag khi ERP báo.
/// </summary>
public static class WebTags
{
    public const string Products = "products";
    public const string Posts = "posts";
    public const string Pages = "pages";
    public const string Site = "site";
    public static readonly string[] All = [Site, Products, Posts, Pages];
}

/// <summary>Có thay đổi: SiteId = null nghĩa là mọi website của công ty.</summary>
public sealed record RevalidateSignal(long CompanyId, long? SiteId, IReadOnlyCollection<string> Tags);

public interface IRevalidationQueue
{
    void Enqueue(RevalidateSignal signal);
    /// <summary>Gửi ngay (nút "Làm mới website" / "Gửi thử") và trả về kết quả để hiện cho người dùng.</summary>
    Task<string> SendNowAsync(long siteId, IReadOnlyCollection<string> tags, CancellationToken ct);
}

/// <summary>
/// Chạy trước / sau SaveChanges: thấy sản phẩm, giá, tồn kho, bài viết, trang, menu, thông tin website / công ty thay đổi
/// thì báo các website liên quan làm mới. Lưu thất bại thì không báo.
/// </summary>
public sealed class WebChangeInterceptor(IRevalidationQueue queue) : SaveChangesInterceptor
{
    private static readonly HashSet<string> SiteContentFields = [nameof(Site.Name), nameof(Site.Domain), nameof(Site.LogoUrl), nameof(Site.Settings), nameof(Site.IsActive)];
    private readonly List<RevalidateSignal> _pending = [];

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData e, InterceptionResult<int> result, CancellationToken ct = default)
    {
        if (e.Context is not null) Collect(e.Context);
        return base.SavingChangesAsync(e, result, ct);
    }

    public override InterceptionResult<int> SavingChanges(DbContextEventData e, InterceptionResult<int> result)
    {
        if (e.Context is not null) Collect(e.Context);
        return base.SavingChanges(e, result);
    }

    public override ValueTask<int> SavedChangesAsync(SaveChangesCompletedEventData e, int result, CancellationToken ct = default)
    {
        Flush();
        return base.SavedChangesAsync(e, result, ct);
    }

    public override int SavedChanges(SaveChangesCompletedEventData e, int result)
    {
        Flush();
        return base.SavedChanges(e, result);
    }

    public override void SaveChangesFailed(DbContextErrorEventData e) => _pending.Clear();
    public override Task SaveChangesFailedAsync(DbContextErrorEventData e, CancellationToken ct = default) { _pending.Clear(); return Task.CompletedTask; }

    private void Collect(DbContext context)
    {
        foreach (var entry in context.ChangeTracker.Entries())
        {
            if (entry.State is not (EntityState.Added or EntityState.Modified or EntityState.Deleted)) continue;
            var signal = entry.Entity switch
            {
                Product p => new RevalidateSignal(p.CompanyId, null, [WebTags.Products]),
                ProductModel m => new RevalidateSignal(m.CompanyId, null, [WebTags.Products]),
                StockBalance b => new RevalidateSignal(b.CompanyId, null, [WebTags.Products]),
                ProductCategory c => new RevalidateSignal(c.CompanyId, null, [WebTags.Products]),
                SiteProduct sp => new RevalidateSignal(0, sp.SiteId, [WebTags.Products]),
                Post post => new RevalidateSignal(0, post.SiteId, [WebTags.Posts]),
                PostCategory pc => new RevalidateSignal(0, pc.SiteId, [WebTags.Posts]),
                WebPage page => new RevalidateSignal(0, page.SiteId, [WebTags.Pages]),
                Menu menu => new RevalidateSignal(0, menu.SiteId, [WebTags.Site]),
                MenuItem item => context.ChangeTracker.Entries<Menu>().Select(x => x.Entity).FirstOrDefault(m => m.Id == item.MenuId) is { } owner
                    ? new RevalidateSignal(0, owner.SiteId, [WebTags.Site]) : null,
                // Chỉ khi đổi nội dung hiển thị - bỏ qua cột ghi kết quả đồng bộ / khóa API (tránh tự gọi lại vòng lặp)
                Site site when entry.State == EntityState.Modified && entry.Properties.Any(p => p.IsModified && SiteContentFields.Contains(p.Metadata.Name))
                    => new RevalidateSignal(site.CompanyId, site.Id, WebTags.All),
                Company company => new RevalidateSignal(company.Id, null, [WebTags.Site]),
                _ => null,
            };
            if (signal is not null) _pending.Add(signal);
        }
    }

    private void Flush()
    {
        foreach (var s in _pending) queue.Enqueue(s);
        _pending.Clear();
    }
}

/// <summary>
/// Gom các thay đổi trong ~1,5 giây rồi gửi 1 lệnh làm mới cho mỗi website: POST {RevalidateUrl}
/// header "x-revalidate-secret", body { "tags": [...] }. Ghi kết quả vào LastSyncAt / LastSyncStatus.
/// Gửi lỗi thì website vẫn tự làm mới sau vài phút (revalidate theo thời gian ở phía Next.js).
/// </summary>
public sealed class RevalidationDispatcher(IServiceScopeFactory scopes, IHttpClientFactory http, ILogger<RevalidationDispatcher> log, TimeProvider clock)
    : BackgroundService, IRevalidationQueue
{
    public const string HttpClientName = "revalidate";
    public const string SecretHeader = "x-revalidate-secret";
    private static readonly TimeSpan Debounce = TimeSpan.FromMilliseconds(1500);
    private readonly Channel<RevalidateSignal> _channel = Channel.CreateBounded<RevalidateSignal>(
        new BoundedChannelOptions(10_000) { FullMode = BoundedChannelFullMode.DropOldest });

    public void Enqueue(RevalidateSignal signal) => _channel.Writer.TryWrite(signal);

    protected override async Task ExecuteAsync(CancellationToken stop)
    {
        while (await _channel.Reader.WaitToReadAsync(stop))
        {
            await Task.Delay(Debounce, stop);
            var batch = new List<RevalidateSignal>();
            while (_channel.Reader.TryRead(out var s)) batch.Add(s);
            try { await DispatchAsync(batch, stop); }
            catch (Exception ex) when (ex is not OperationCanceledException) { log.LogError(ex, "Không gửi được lệnh làm mới website"); }
        }
    }

    private async Task DispatchAsync(List<RevalidateSignal> batch, CancellationToken ct)
    {
        using var scope = scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        // Chạy nền, không có người đăng nhập -> bỏ bộ lọc công ty, tự lọc theo CompanyId / SiteId
        var sites = await db.Sites.IgnoreQueryFilters().Where(s => s.IsActive && s.RevalidateUrl != null).ToListAsync(ct);
        var tagsBySite = new Dictionary<long, HashSet<string>>();
        foreach (var s in batch)
            foreach (var site in sites.Where(x => s.SiteId is { } id ? x.Id == id : x.CompanyId == s.CompanyId))
            {
                if (!tagsBySite.TryGetValue(site.Id, out var set)) tagsBySite[site.Id] = set = [];
                set.UnionWith(s.Tags);
            }
        foreach (var (siteId, tags) in tagsBySite)
        {
            var site = sites.First(x => x.Id == siteId);
            site.RecordSync(clock.GetUtcNow().UtcDateTime, await PostAsync(site, tags, ct));
        }
        if (tagsBySite.Count > 0) await db.SaveChangesAsync(ct);
    }

    public async Task<string> SendNowAsync(long siteId, IReadOnlyCollection<string> tags, CancellationToken ct)
    {
        using var scope = scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var site = await db.Sites.IgnoreQueryFilters().FirstAsync(s => s.Id == siteId, ct);
        if (site.RevalidateUrl is null) return "Chưa nhập địa chỉ webhook.";
        var status = await PostAsync(site, tags, ct);
        site.RecordSync(clock.GetUtcNow().UtcDateTime, status);
        await db.SaveChangesAsync(ct);
        return status;
    }

    private async Task<string> PostAsync(Site site, IReadOnlyCollection<string> tags, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Post, site.RevalidateUrl) { Content = JsonContent.Create(new { tags }) };
            req.Headers.Add(SecretHeader, site.RevalidateSecret);
            using var res = await http.CreateClient(HttpClientName).SendAsync(req, ct);
            var tagText = string.Join(", ", tags.Order());
            return res.IsSuccessStatusCode
                ? $"OK ({(int)res.StatusCode}, {sw.ElapsedMilliseconds} ms): {tagText}"
                : $"Lỗi {(int)res.StatusCode} {res.ReasonPhrase} - kiểm tra mật khẩu webhook ở website: {tagText}";
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            log.LogWarning("Không gọi được webhook {Url}: {Message}", site.RevalidateUrl, ex.Message);
            return $"Không kết nối được website ({ex.GetType().Name}): {ex.Message}";
        }
    }
}
