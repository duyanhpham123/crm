using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Sales;

public static class QuotationStatuses
{
    public const string Draft = "draft";
    public const string Sent = "sent";           // đã gửi khách, chờ phản hồi
    public const string Accepted = "accepted";   // khách đồng ý (đã / sẽ tạo đơn)
    public const string Rejected = "rejected";
    public const string Cancelled = "cancelled";
    public const string Expired = "expired";     // chỉ để hiển thị: đã gửi nhưng quá hạn hiệu lực
}

public sealed record QuotationInfo(
    long PartnerId, DateOnly QuoteDate, DateOnly? ValidUntil, long? SalespersonUserId,
    decimal DiscountAmount, decimal ShippingFee, string? Terms, string? Note, IReadOnlyList<OrderLineInfo> Lines);

/// <summary>
/// Bảng sales.Quotations - báo giá cho khách (thường là khách sỉ / doanh nghiệp).
/// Nháp -> Đã gửi -> Khách đồng ý (tạo đơn hàng) / Từ chối. Sửa được khi Nháp hoặc Đã gửi (tăng số lần sửa).
/// </summary>
public sealed class Quotation : AuditableEntity, ICompanyOwned
{
    private Quotation() { }

    public long CompanyId { get; private set; }
    public string DocNo { get; private set; } = "";
    public int RevisionNo { get; private set; }
    public long PartnerId { get; private set; }
    public DateOnly QuoteDate { get; private set; }
    public DateOnly? ValidUntil { get; private set; }
    public long? SalespersonUserId { get; private set; }
    public string Status { get; private set; } = QuotationStatuses.Draft;
    public decimal SubTotal { get; private set; }
    public decimal DiscountAmount { get; private set; }
    public decimal TaxAmount { get; private set; }
    public decimal ShippingFee { get; private set; }
    public decimal TotalAmount { get; private set; }
    public string? Terms { get; private set; }
    public string? Note { get; private set; }
    public DateTime? SentAt { get; private set; }
    public DateTime? AcceptedAt { get; private set; }
    public string? RejectedReason { get; private set; }

    private readonly List<QuotationLine> _lines = [];
    public IReadOnlyList<QuotationLine> Lines => _lines;

    public bool IsEditable => Status is QuotationStatuses.Draft or QuotationStatuses.Sent;
    public bool IsExpired(DateOnly today) => Status == QuotationStatuses.Sent && ValidUntil is { } v && v < today;

    public static Result<Quotation> Create(long companyId, string docNo, QuotationInfo info)
    {
        var q = new Quotation { CompanyId = companyId, DocNo = docNo };
        var r = q.Apply(info);
        return r.IsFailure ? r.Error! : q;
    }

    public Result Update(QuotationInfo info)
    {
        if (!IsEditable) return Error.Conflict("quotation.locked", "Báo giá đã chốt, không sửa được.");
        if (Status == QuotationStatuses.Sent) RevisionNo++;
        return Apply(info);
    }

    private Result Apply(QuotationInfo i)
    {
        if (i.Lines.Count == 0) return Error.Validation("quotation.no_lines", "Báo giá phải có ít nhất 1 sản phẩm.");
        if (i.ValidUntil is { } v && v < i.QuoteDate) return Error.Validation("quotation.valid_until", "Hạn hiệu lực phải sau ngày báo giá.");
        var lines = i.Lines.Select((l, n) => QuotationLine.Create(n + 1, l)).ToList();
        var sub = lines.Sum(l => l.LineTotal);
        if (i.DiscountAmount < 0 || i.DiscountAmount > sub) return Error.Validation("quotation.discount", "Giảm giá không được lớn hơn tiền hàng.");
        if (i.ShippingFee < 0) return Error.Validation("quotation.shipping", "Phí giao hàng không hợp lệ.");

        PartnerId = i.PartnerId; QuoteDate = i.QuoteDate; ValidUntil = i.ValidUntil; SalespersonUserId = i.SalespersonUserId;
        DiscountAmount = i.DiscountAmount; ShippingFee = i.ShippingFee; Terms = Clean(i.Terms); Note = Clean(i.Note);
        _lines.Clear();
        _lines.AddRange(lines);
        SubTotal = sub;
        TotalAmount = sub - DiscountAmount + ShippingFee;
        return Result.Success();
    }

    public Result MarkSent(DateTime now)
    {
        if (Status != QuotationStatuses.Draft && Status != QuotationStatuses.Sent) return Error.Conflict("quotation.not_draft", "Chỉ gửi được báo giá Nháp.");
        Status = QuotationStatuses.Sent;
        SentAt ??= now;
        return Result.Success();
    }

    public Result Accept(DateTime now)
    {
        if (Status != QuotationStatuses.Sent && Status != QuotationStatuses.Draft) return Error.Conflict("quotation.not_open", "Báo giá đã chốt trước đó.");
        Status = QuotationStatuses.Accepted;
        AcceptedAt = now;
        return Result.Success();
    }

    public Result Reject(string reason)
    {
        if (!IsEditable) return Error.Conflict("quotation.not_open", "Báo giá đã chốt trước đó.");
        if (string.IsNullOrWhiteSpace(reason)) return Error.Validation("quotation.reason", "Nhập lý do khách từ chối.");
        Status = QuotationStatuses.Rejected;
        RejectedReason = reason.Trim();
        return Result.Success();
    }

    public Result Cancel()
    {
        if (!IsEditable) return Error.Conflict("quotation.not_open", "Báo giá đã chốt trước đó.");
        Status = QuotationStatuses.Cancelled;
        return Result.Success();
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

public sealed class QuotationLine
{
    private QuotationLine() { }

    public long Id { get; private set; }
    public long QuotationId { get; private set; }
    public int LineNumber { get; private set; }
    public long? ProductId { get; private set; }
    public string Description { get; private set; } = "";
    public long? UomId { get; private set; }
    public decimal Quantity { get; private set; }
    public decimal UnitPrice { get; private set; }
    public decimal DiscountPercent { get; private set; }
    public decimal DiscountAmount { get; private set; }
    public decimal TaxRate { get; private set; }
    public decimal LineSubTotal { get; private set; }
    public decimal LineTax { get; private set; }
    public decimal LineTotal { get; private set; }

    internal static QuotationLine Create(int n, OrderLineInfo l)
    {
        var gross = l.Quantity * l.UnitPrice;
        var discount = Math.Round(gross * l.DiscountPercent / 100, 0);
        return new QuotationLine
        {
            LineNumber = n, ProductId = l.ProductId, UomId = l.UomId, Description = l.Description,
            Quantity = l.Quantity, UnitPrice = l.UnitPrice, DiscountPercent = l.DiscountPercent, DiscountAmount = discount,
            LineSubTotal = gross - discount, LineTotal = gross - discount,
        };
    }
}
