using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Marketing;

public sealed record CampaignInfo(string Name, string Channel, DateOnly StartDate, DateOnly? EndDate, decimal Budget, int? TargetLeads,
    string? UtmCampaign, string Status, string? Description);

/// <summary>mkt.Campaigns - chiến dịch quảng cáo / khuyến mãi. Chi phí thực tế = tổng chi phí ngày đã nhập.</summary>
public sealed class Campaign : AuditableEntity, ICompanyOwned
{
    public static readonly string[] Channels = ["facebook", "google", "tiktok", "zalo", "email", "sms", "seo", "event", "offline", "other"];
    public static readonly string[] Statuses = ["draft", "running", "paused", "completed", "cancelled"];

    private Campaign() { }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public string Channel { get; private set; } = "facebook";
    public DateOnly StartDate { get; private set; }
    public DateOnly? EndDate { get; private set; }
    public decimal Budget { get; private set; }
    public decimal ActualCost { get; private set; }
    public int? TargetLeads { get; private set; }
    public string? UtmCampaign { get; private set; }
    public string Status { get; private set; } = "draft";
    public long? OwnerUserId { get; private set; }
    public string? Description { get; private set; }

    private readonly List<CampaignDailyStat> _stats = [];
    public IReadOnlyList<CampaignDailyStat> Stats => _stats;

    public static Result<Campaign> Create(long companyId, string code, long ownerId, CampaignInfo info)
    {
        var c = new Campaign { CompanyId = companyId, Code = code, OwnerUserId = ownerId };
        var r = c.Update(info);
        return r.IsFailure ? r.Error! : c;
    }

    public Result Update(CampaignInfo i)
    {
        if (string.IsNullOrWhiteSpace(i.Name)) return Error.Validation("campaign.name", "Nhập tên chiến dịch.");
        if (!Channels.Contains(i.Channel)) return Error.Validation("campaign.channel", "Kênh không hợp lệ.");
        if (!Statuses.Contains(i.Status)) return Error.Validation("campaign.status", "Trạng thái không hợp lệ.");
        if (i.EndDate is { } e && e < i.StartDate) return Error.Validation("campaign.dates", "Ngày kết thúc phải sau ngày bắt đầu.");
        if (i.Budget < 0) return Error.Validation("campaign.budget", "Ngân sách không hợp lệ.");
        Name = i.Name.Trim(); Channel = i.Channel; StartDate = i.StartDate; EndDate = i.EndDate; Budget = i.Budget;
        TargetLeads = i.TargetLeads; UtmCampaign = string.IsNullOrWhiteSpace(i.UtmCampaign) ? null : i.UtmCampaign.Trim();
        Status = i.Status; Description = string.IsNullOrWhiteSpace(i.Description) ? null : i.Description.Trim();
        return Result.Success();
    }

    /// <summary>Nhập / sửa số liệu 1 ngày (chi phí, hiển thị, click, khách để lại thông tin).</summary>
    public Result SetDailyStat(DateOnly date, long impressions, long clicks, decimal spend, int leads)
    {
        if (impressions < 0 || clicks < 0 || spend < 0 || leads < 0) return Error.Validation("campaign.stat", "Số liệu không hợp lệ.");
        if (date < StartDate) return Error.Validation("campaign.stat_date", "Ngày phải trong thời gian chạy chiến dịch.");
        var s = _stats.FirstOrDefault(x => x.StatDate == date);
        if (s is null) { s = new CampaignDailyStat(date); _stats.Add(s); }
        s.Set(impressions, clicks, spend, leads);
        ActualCost = _stats.Sum(x => x.Spend);
        return Result.Success();
    }
}

public sealed class CampaignDailyStat
{
    private CampaignDailyStat() { }
    internal CampaignDailyStat(DateOnly date) { StatDate = date; }
    public long CampaignId { get; private set; }
    public DateOnly StatDate { get; private set; }
    public long Impressions { get; private set; }
    public long Clicks { get; private set; }
    public decimal Spend { get; private set; }
    public int Leads { get; private set; }
    internal void Set(long i, long c, decimal s, int l) { Impressions = i; Clicks = c; Spend = s; Leads = l; }
}

public sealed record PromotionInfo(string Name, string Type, decimal Value, decimal? MaxDiscount, decimal MinOrderAmount, DateTime StartAt,
    DateTime EndAt, int? UsageLimit, string? Channels, long? CampaignId, bool IsActive);

/// <summary>sales.Promotions - mã giảm giá áp dụng khi tạo đơn hàng.</summary>
public sealed class Promotion : ICompanyOwned
{
    public static readonly string[] Types = ["percent", "fixed", "free_ship"];

    private Promotion() { }
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public string PromotionType { get; private set; } = "percent";
    public decimal Value { get; private set; }
    public decimal? MaxDiscount { get; private set; }
    public decimal MinOrderAmount { get; private set; }
    public DateTime StartAt { get; private set; }
    public DateTime EndAt { get; private set; }
    public int? UsageLimit { get; private set; }
    public int UsedCount { get; private set; }
    public string? Channels { get; private set; }
    public long? CampaignId { get; private set; }
    public bool IsActive { get; private set; } = true;
    public DateTime CreatedAt { get; private set; }

    public static Result<Promotion> Create(long companyId, string code, PromotionInfo info, DateTime now)
    {
        var c = (code ?? "").Trim().ToUpperInvariant();
        if (c.Length is < 3 or > 30 || !c.All(ch => char.IsAsciiLetterOrDigit(ch) || ch is '-' or '_'))
            return Error.Validation("promotion.code", "Mã 3-30 ký tự, chỉ gồm chữ không dấu, số, - hoặc _.");
        var p = new Promotion { CompanyId = companyId, Code = c, CreatedAt = now };
        var r = p.Update(info);
        return r.IsFailure ? r.Error! : p;
    }

    public Result Update(PromotionInfo i)
    {
        if (string.IsNullOrWhiteSpace(i.Name)) return Error.Validation("promotion.name", "Nhập tên chương trình.");
        if (!Types.Contains(i.Type)) return Error.Validation("promotion.type", "Loại giảm giá không hợp lệ.");
        if (i.Type == "percent" && i.Value is <= 0 or > 100) return Error.Validation("promotion.value", "Phần trăm giảm từ 1 đến 100.");
        if (i.Type == "fixed" && i.Value <= 0) return Error.Validation("promotion.value", "Nhập số tiền giảm.");
        if (i.EndAt <= i.StartAt) return Error.Validation("promotion.dates", "Thời gian kết thúc phải sau thời gian bắt đầu.");
        if (i.MinOrderAmount < 0 || i.MaxDiscount < 0 || i.UsageLimit < 1) return Error.Validation("promotion.limits", "Điều kiện không hợp lệ.");
        Name = i.Name.Trim(); PromotionType = i.Type; Value = i.Type == "free_ship" ? 0 : i.Value; MaxDiscount = i.MaxDiscount;
        MinOrderAmount = i.MinOrderAmount; StartAt = i.StartAt; EndAt = i.EndAt; UsageLimit = i.UsageLimit;
        Channels = string.IsNullOrWhiteSpace(i.Channels) ? null : i.Channels.Replace(" ", ""); CampaignId = i.CampaignId; IsActive = i.IsActive;
        return Result.Success();
    }

    /// <summary>Tính tiền giảm cho 1 đơn. Lỗi nếu mã hết hạn, hết lượt, sai kênh hoặc chưa đủ giá trị tối thiểu.</summary>
    public Result<decimal> DiscountFor(decimal subTotal, decimal shippingFee, string channel, DateTime now)
    {
        if (!IsActive) return Error.Validation("promotion.inactive", $"Mã {Code} đang tạm dừng.");
        if (now < StartAt) return Error.Validation("promotion.not_started", $"Mã {Code} chưa đến thời gian áp dụng.");
        if (now > EndAt) return Error.Validation("promotion.expired", $"Mã {Code} đã hết hạn.");
        if (UsageLimit is { } limit && UsedCount >= limit) return Error.Validation("promotion.used_up", $"Mã {Code} đã hết lượt sử dụng.");
        if (Channels is { } chs && !chs.Split(',').Contains(channel)) return Error.Validation("promotion.channel", $"Mã {Code} không áp dụng cho kênh bán này.");
        if (subTotal < MinOrderAmount) return Error.Validation("promotion.min_order", $"Mã {Code} áp dụng cho đơn từ {MinOrderAmount:N0} đ.");
        var d = PromotionType switch
        {
            "percent" => Math.Round(subTotal * Value / 100, 0),
            "fixed" => Value,
            _ => shippingFee,
        };
        if (MaxDiscount is { } max && d > max) d = max;
        return Math.Min(d, PromotionType == "free_ship" ? shippingFee : subTotal);
    }

    public void Use() => UsedCount++;
    public void Release() => UsedCount = Math.Max(0, UsedCount - 1);
}

/// <summary>sales.OrderPromotions - đơn dùng mã nào, giảm bao nhiêu.</summary>
public sealed class OrderPromotion
{
    private OrderPromotion() { }
    public OrderPromotion(long orderId, long promotionId, decimal amount) { SalesOrderId = orderId; PromotionId = promotionId; DiscountAmount = amount; }
    public long SalesOrderId { get; private set; }
    public long PromotionId { get; private set; }
    public decimal DiscountAmount { get; private set; }
}
