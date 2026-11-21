using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Marketing;
using MyERP.Api.Models.Entities.Sales;
using MyERP.Api.Services.Common;
using MyERP.Api.Services.Sales;

namespace MyERP.Api.Services.Marketing;

public interface IMarketingService
{
    Task<MarketingLookups> GetLookupsAsync(CancellationToken ct);
    Task<CampaignPage> ListCampaignsAsync(string? search, string? status, int page, int pageSize, CancellationToken ct);
    Task<Result<CampaignDetail>> GetCampaignAsync(long id, CancellationToken ct);
    Task<Result<CampaignDetail>> CreateCampaignAsync(SaveCampaignRequest request, CancellationToken ct);
    Task<Result<CampaignDetail>> UpdateCampaignAsync(long id, SaveCampaignRequest request, CancellationToken ct);
    Task<Result<CampaignDetail>> SetDailyStatAsync(long id, DailyStatRequest request, CancellationToken ct);
    Task<IReadOnlyList<PromotionListItem>> ListPromotionsAsync(string? search, string? state, CancellationToken ct);
    Task<Result<PromotionListItem>> CreatePromotionAsync(SavePromotionRequest request, CancellationToken ct);
    Task<Result<PromotionListItem>> UpdatePromotionAsync(long id, SavePromotionRequest request, CancellationToken ct);
    Task<SegmentPage> SegmentsAsync(string? segment, string? search, int page, int pageSize, CancellationToken ct);
}

/// <summary>
/// Marketing: chiến dịch quảng cáo (chi phí, hiển thị, click, lead theo ngày; doanh thu qua mã giảm giá của chiến dịch),
/// mã giảm giá dùng ở Đơn hàng, phân nhóm khách hàng theo hành vi mua.
/// </summary>
public sealed class MarketingService(AppDbContext db, ICurrentUser currentUser, IDocumentNumberService docNumbers, TimeProvider clock) : IMarketingService
{
    public static readonly IReadOnlyList<CodeOption> Channels =
    [
        new("facebook", "Facebook Ads"), new("tiktok", "TikTok Ads"), new("google", "Google Ads"), new("zalo", "Zalo"),
        new("email", "Email"), new("sms", "SMS"), new("seo", "SEO / Website"), new("event", "Sự kiện"), new("offline", "Offline / tại cửa hàng"), new("other", "Khác")
    ];

    public const decimal VipSpend = 8_000_000;
    public const int AtRiskDays = 15;

    private DateTime LocalNow => clock.GetUtcNow().UtcDateTime.AddHours(7);

    public async Task<MarketingLookups> GetLookupsAsync(CancellationToken ct)
        => new(Channels, await db.Campaigns.Where(c => c.Status != "cancelled").OrderByDescending(c => c.StartDate).Select(c => new OptionDto(c.Id, c.Name, c.Code)).ToListAsync(ct),
            OrderService.Channels);

    // ---------- Chiến dịch ----------

    private sealed record Perf(long CampaignId, int Orders, decimal Revenue);

    private async Task<Dictionary<long, Perf>> PerformanceAsync(IReadOnlyList<long> campaignIds, CancellationToken ct)
    {
        var rows = await (from op in db.OrderPromotions
                          join p in db.Promotions on op.PromotionId equals p.Id
                          join o in db.SalesOrders on op.SalesOrderId equals o.Id
                          where p.CampaignId != null && campaignIds.Contains(p.CampaignId.Value)
                                && (o.Status == OrderStatuses.Confirmed || o.Status == OrderStatuses.Completed)
                          group o by p.CampaignId into g
                          select new { Id = g.Key!.Value, Orders = g.Count(), Revenue = g.Sum(x => x.SubTotal - x.DiscountAmount - x.ReturnedAmount) }).ToListAsync(ct);
        return rows.ToDictionary(r => r.Id, r => new Perf(r.Id, r.Orders, r.Revenue));
    }

    public async Task<CampaignPage> ListCampaignsAsync(string? search, string? status, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var q = db.Campaigns.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(search)) { var s = search.Trim(); q = q.Where(c => c.Name.Contains(s) || c.Code.Contains(s)); }
        if (!string.IsNullOrEmpty(status)) q = q.Where(c => c.Status == status);
        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(c => c.Status == "running").ThenByDescending(c => c.StartDate).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(c => new { c.Id, c.Code, c.Name, c.Channel, c.StartDate, c.EndDate, c.Budget, c.ActualCost, c.Status, Leads = c.Stats.Sum(s => s.Leads) })
            .ToListAsync(ct);
        var allIds = await db.Campaigns.Select(c => c.Id).ToListAsync(ct);
        var perf = await PerformanceAsync(allIds, ct);
        var items = rows.Select(c =>
        {
            var p = perf.GetValueOrDefault(c.Id);
            return new CampaignListItem(c.Id, c.Code, c.Name, c.Channel, c.StartDate, c.EndDate, c.Budget, c.ActualCost, c.Status, c.Leads,
                p?.Orders ?? 0, p?.Revenue ?? 0, Ratio(p?.Revenue ?? 0, c.ActualCost), c.Leads == 0 ? null : Math.Round(c.ActualCost / c.Leads, 0));
        }).ToList();
        var spend = await db.Campaigns.SumAsync(c => (decimal?)c.ActualCost, ct) ?? 0;
        var revenue = perf.Values.Sum(p => p.Revenue);
        var summary = new CampaignSummary(await db.Campaigns.CountAsync(c => c.Status == "running", ct), spend, revenue,
            await db.Campaigns.SelectMany(c => c.Stats).SumAsync(s => (int?)s.Leads, ct) ?? 0, Ratio(revenue, spend));
        return new CampaignPage(new PagedResult<CampaignListItem>(items, page, pageSize, total), summary);
    }

    private static decimal? Ratio(decimal revenue, decimal cost) => cost == 0 ? null : Math.Round(revenue / cost, 2);

    public async Task<Result<CampaignDetail>> GetCampaignAsync(long id, CancellationToken ct)
    {
        var c = await db.Campaigns.Include(x => x.Stats).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return c is null ? Error.NotFound("chiến dịch") : await ToDetailAsync(c, ct);
    }

    public async Task<Result<CampaignDetail>> CreateCampaignAsync(SaveCampaignRequest r, CancellationToken ct)
    {
        var created = Campaign.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync("CAMPAIGN", r.StartDate, ct), currentUser.RequireUserId(), ToInfo(r));
        if (created.IsFailure) return created.Error!;
        db.Campaigns.Add(created.Value);
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(created.Value, ct);
    }

    public async Task<Result<CampaignDetail>> UpdateCampaignAsync(long id, SaveCampaignRequest r, CancellationToken ct)
    {
        var c = await db.Campaigns.Include(x => x.Stats).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (c is null) return Error.NotFound("chiến dịch");
        if (!string.IsNullOrEmpty(r.RowVersion)) db.Entry(c).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(r.RowVersion);
        var u = c.Update(ToInfo(r));
        if (u.IsFailure) return u.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(c, ct);
    }

    public async Task<Result<CampaignDetail>> SetDailyStatAsync(long id, DailyStatRequest r, CancellationToken ct)
    {
        var c = await db.Campaigns.Include(x => x.Stats).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (c is null) return Error.NotFound("chiến dịch");
        if (r.Date > DateOnly.FromDateTime(LocalNow)) return Error.Validation("campaign.stat_future", "Không nhập số liệu cho ngày chưa tới.");
        var s = c.SetDailyStat(r.Date, r.Impressions, r.Clicks, r.Spend, r.Leads);
        if (s.IsFailure) return s.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(c, ct);
    }

    private static CampaignInfo ToInfo(SaveCampaignRequest r) => new(r.Name, r.Channel, r.StartDate, r.EndDate, r.Budget, r.TargetLeads, r.UtmCampaign, r.Status, r.Description);

    private async Task<CampaignDetail> ToDetailAsync(Campaign c, CancellationToken ct)
    {
        var perf = (await PerformanceAsync([c.Id], ct)).GetValueOrDefault(c.Id);
        var impressions = c.Stats.Sum(s => s.Impressions);
        var clicks = c.Stats.Sum(s => s.Clicks);
        var leads = c.Stats.Sum(s => s.Leads);
        var promos = await ListPromotionsCoreAsync(db.Promotions.Where(p => p.CampaignId == c.Id), ct);
        return new CampaignDetail(c.Id, c.Code, c.Name, c.Channel, c.StartDate, c.EndDate, c.Budget, c.ActualCost, c.TargetLeads, c.UtmCampaign, c.Status,
            c.Description, impressions, clicks, leads, perf?.Orders ?? 0, perf?.Revenue ?? 0, Ratio(perf?.Revenue ?? 0, c.ActualCost),
            leads == 0 ? null : Math.Round(c.ActualCost / leads, 0), impressions == 0 ? null : Math.Round(clicks * 100m / impressions, 2),
            c.Stats.OrderByDescending(s => s.StatDate).Select(s => new DailyStatDto(s.StatDate, s.Impressions, s.Clicks, s.Spend, s.Leads)).ToList(),
            promos, Convert.ToBase64String(c.RowVersion));
    }

    // ---------- Mã giảm giá ----------

    public async Task<IReadOnlyList<PromotionListItem>> ListPromotionsAsync(string? search, string? state, CancellationToken ct)
    {
        var q = db.Promotions.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(search)) { var s = search.Trim(); q = q.Where(p => p.Code.Contains(s) || p.Name.Contains(s)); }
        var list = await ListPromotionsCoreAsync(q, ct);
        return string.IsNullOrEmpty(state) ? list : list.Where(p => p.State == state).ToList();
    }

    private async Task<List<PromotionListItem>> ListPromotionsCoreAsync(IQueryable<Promotion> q, CancellationToken ct)
    {
        var list = await q.OrderByDescending(p => p.IsActive).ThenByDescending(p => p.EndAt).ToListAsync(ct);
        var ids = list.Select(p => p.Id).ToList();
        var usage = await (from op in db.OrderPromotions
                           join o in db.SalesOrders on op.SalesOrderId equals o.Id
                           where ids.Contains(op.PromotionId) && (o.Status == OrderStatuses.Confirmed || o.Status == OrderStatuses.Completed)
                           group new { op, o } by op.PromotionId into g
                           select new { Id = g.Key, Revenue = g.Sum(x => x.o.SubTotal - x.o.DiscountAmount - x.o.ReturnedAmount), Discount = g.Sum(x => x.op.DiscountAmount) })
            .ToDictionaryAsync(x => x.Id, ct);
        var campaignIds = list.Where(p => p.CampaignId != null).Select(p => p.CampaignId!.Value).Distinct().ToList();
        var campaigns = await db.Campaigns.Where(c => campaignIds.Contains(c.Id)).ToDictionaryAsync(c => c.Id, c => c.Name, ct);
        var now = LocalNow;
        return list.Select(p => new PromotionListItem(p.Id, p.Code, p.Name, p.PromotionType, p.Value, p.MaxDiscount, p.MinOrderAmount, p.StartAt, p.EndAt,
            p.UsageLimit, p.UsedCount, p.Channels, p.CampaignId, p.CampaignId is { } cid ? campaigns.GetValueOrDefault(cid) : null, p.IsActive,
            !p.IsActive ? "inactive" : now < p.StartAt ? "scheduled" : now > p.EndAt ? "expired" : p.UsageLimit is { } l && p.UsedCount >= l ? "used_up" : "active",
            usage.GetValueOrDefault(p.Id)?.Revenue ?? 0, usage.GetValueOrDefault(p.Id)?.Discount ?? 0)).ToList();
    }

    public async Task<Result<PromotionListItem>> CreatePromotionAsync(SavePromotionRequest r, CancellationToken ct)
    {
        if (r.CampaignId is { } cid && !await db.Campaigns.AnyAsync(c => c.Id == cid, ct)) return Error.Validation("promotion.campaign", "Chiến dịch không hợp lệ.");
        var created = Promotion.Create(currentUser.RequireCompanyId(), r.Code, ToInfo(r), clock.GetUtcNow().UtcDateTime);
        if (created.IsFailure) return created.Error!;
        if (await db.Promotions.AnyAsync(p => p.Code == created.Value.Code, ct)) return Error.Conflict("promotion.code_taken", "Mã giảm giá đã tồn tại.");
        db.Promotions.Add(created.Value);
        await db.SaveChangesAsync(ct);
        return (await ListPromotionsCoreAsync(db.Promotions.Where(p => p.Id == created.Value.Id), ct))[0];
    }

    public async Task<Result<PromotionListItem>> UpdatePromotionAsync(long id, SavePromotionRequest r, CancellationToken ct)
    {
        var p = await db.Promotions.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (p is null) return Error.NotFound("mã giảm giá");
        if (r.CampaignId is { } cid && !await db.Campaigns.AnyAsync(c => c.Id == cid, ct)) return Error.Validation("promotion.campaign", "Chiến dịch không hợp lệ.");
        var u = p.Update(ToInfo(r));
        if (u.IsFailure) return u.Error!;
        await db.SaveChangesAsync(ct);
        return (await ListPromotionsCoreAsync(db.Promotions.Where(x => x.Id == id), ct))[0];
    }

    private static PromotionInfo ToInfo(SavePromotionRequest r) => new(r.Name, r.Type, r.Value, r.MaxDiscount, r.MinOrderAmount, r.StartAt, r.EndAt,
        r.UsageLimit, r.Channels, r.CampaignId, r.IsActive);

    // ---------- Phân nhóm khách ----------

    /// <summary>
    /// Nhóm theo hành vi mua (đơn đã xác nhận / hoàn thành, bỏ khách lẻ):
    /// at_risk = đã mua từ 2 lần nhưng hơn 15 ngày chưa quay lại (xét trước, kể cả khách VIP - cần gọi chăm sóc lại);
    /// vip = tổng mua từ 8 triệu; loyal = từ 2 đơn; new = 1 đơn trong 30 ngày; one_time = 1 đơn đã lâu.
    /// </summary>
    public async Task<SegmentPage> SegmentsAsync(string? segment, string? search, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var stats = await db.SalesOrders.AsNoTracking()
            .Where(o => (o.Status == OrderStatuses.Confirmed || o.Status == OrderStatuses.Completed) && db.Partners.Any(p => p.Id == o.PartnerId && p.Code != OrderService.WalkInCode))
            .GroupBy(o => o.PartnerId)
            .Select(g => new { PartnerId = g.Key, Orders = g.Count(), Spent = g.Sum(o => o.TotalAmount), Last = g.Max(o => o.OrderDate) })
            .ToListAsync(ct);
        var ids = stats.Select(s => s.PartnerId).ToList();
        var partners = await db.Partners.AsNoTracking().Where(p => ids.Contains(p.Id)).Select(p => new { p.Id, p.Code, p.Name, p.Phone }).ToDictionaryAsync(p => p.Id, ct);
        var today = DateOnly.FromDateTime(LocalNow);
        var rows = stats.Where(s => partners.ContainsKey(s.PartnerId)).Select(s =>
        {
            var last = DateOnly.FromDateTime(s.Last.AddHours(7));
            var days = today.DayNumber - last.DayNumber;
            var seg = s.Orders >= 2 && days > AtRiskDays ? "at_risk" : s.Spent >= VipSpend ? "vip" : s.Orders >= 2 ? "loyal" : days <= 30 ? "new" : "one_time";
            var p = partners[s.PartnerId];
            return new CustomerSegmentRow(p.Id, p.Code, p.Name, p.Phone, s.Orders, s.Spent, last, days, seg);
        }).ToList();
        var counts = rows.GroupBy(r => r.Segment).ToDictionary(g => g.Key, g => g.Count());
        IEnumerable<CustomerSegmentRow> filtered = rows;
        if (!string.IsNullOrEmpty(segment)) filtered = filtered.Where(r => r.Segment == segment);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = TextSearch.Fold(search);
            filtered = filtered.Where(r => TextSearch.Fold(r.Name).Contains(s) || (r.Phone ?? "").Contains(search.Trim()) || r.Code.Contains(search.Trim(), StringComparison.OrdinalIgnoreCase));
        }
        var ordered = filtered.OrderByDescending(r => r.TotalSpent).ToList();
        return new SegmentPage(new PagedResult<CustomerSegmentRow>(ordered.Skip((page - 1) * pageSize).Take(pageSize).ToList(), page, pageSize, ordered.Count), counts);
    }
}
