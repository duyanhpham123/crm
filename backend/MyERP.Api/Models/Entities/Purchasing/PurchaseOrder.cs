using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Purchasing;

public static class PurchaseStatuses
{
    public const string Draft = "draft";
    public const string Confirmed = "confirmed";   // đã chốt với nhà cung cấp, chờ hàng về
    public const string Completed = "completed";   // đã nhận đủ hàng vào kho
    public const string Cancelled = "cancelled";
}

public sealed record PurchaseLineInfo(long ProductId, long UomId, string? Description, decimal Quantity, decimal UnitPrice, decimal DiscountPercent);

public sealed record PurchaseInfo(
    long SupplierId,
    DateOnly OrderDate,
    DateOnly? ExpectedDate,
    long WarehouseId,
    decimal OtherCost,
    string? Note,
    IReadOnlyList<PurchaseLineInfo> Lines);

/// <summary>
/// Bảng pur.PurchaseOrders - đơn nhập hàng từ nhà cung cấp.
/// Luồng: Nháp -> Đã đặt -> Nhận hàng (kho tăng, tính lại giá vốn) -> Hoàn thành.
/// </summary>
public sealed class PurchaseOrder : AuditableEntity, ICompanyOwned
{
    private PurchaseOrder() { }

    public long CompanyId { get; private set; }
    public string DocNo { get; private set; } = "";
    public long PartnerId { get; private set; }
    public DateOnly OrderDate { get; private set; }
    public DateOnly? ExpectedDate { get; private set; }
    public long WarehouseId { get; private set; }
    public long? BuyerUserId { get; private set; }
    public string Status { get; private set; } = PurchaseStatuses.Draft;
    public string ReceiptStatus { get; private set; } = "pending";
    public decimal SubTotal { get; private set; }
    public decimal DiscountAmount { get; private set; }
    public decimal TaxAmount { get; private set; }
    public decimal OtherCost { get; private set; }
    public decimal TotalAmount { get; private set; }
    public decimal AmountPaid { get; private set; }
    public decimal AmountDue => Status == PurchaseStatuses.Cancelled ? 0 : TotalAmount - AmountPaid;

    /// <summary>Trả tiền nhà cung cấp cho đơn này (phiếu chi).</summary>
    public Result RecordPayment(decimal amount)
    {
        if (Status is PurchaseStatuses.Draft or PurchaseStatuses.Cancelled) return Error.Conflict("purchase.not_payable", "Chỉ trả tiền được cho đơn đã đặt / đã nhận.");
        if (amount <= 0 || amount > AmountDue) return Error.Validation("purchase.payment_too_large", $"Số tiền vượt quá số còn phải trả ({AmountDue:N0} đ).");
        AmountPaid += amount;
        return Result.Success();
    }

    public Result ReversePayment(decimal amount)
    {
        if (amount <= 0 || amount > AmountPaid) return Error.Validation("purchase.reverse_invalid", "Số tiền hủy vượt quá số đã trả.");
        AmountPaid -= amount;
        return Result.Success();
    }
    public string? Note { get; private set; }
    public DateTime? ConfirmedAt { get; private set; }

    public List<PurchaseOrderLine> Lines { get; private set; } = [];

    public static Result<PurchaseOrder> Create(long companyId, string docNo, long? buyerId, PurchaseInfo info)
    {
        var p = new PurchaseOrder { CompanyId = companyId, DocNo = docNo, BuyerUserId = buyerId };
        var r = p.Apply(info);
        return r.IsFailure ? r.Error! : p;
    }

    public Result Update(PurchaseInfo info)
        => Status == PurchaseStatuses.Draft ? Apply(info) : Error.Conflict("purchase.locked", "Chỉ sửa được đơn nhập ở trạng thái Nháp.");

    private Result Apply(PurchaseInfo d)
    {
        if (d.Lines.Count == 0) return Error.Validation("purchase.no_lines", "Đơn nhập phải có ít nhất một sản phẩm.");
        PartnerId = d.SupplierId;
        OrderDate = d.OrderDate;
        ExpectedDate = d.ExpectedDate;
        WarehouseId = d.WarehouseId;
        OtherCost = d.OtherCost;
        Note = string.IsNullOrWhiteSpace(d.Note) ? null : d.Note.Trim();
        Lines.Clear();
        var n = 1;
        foreach (var l in d.Lines) Lines.Add(PurchaseOrderLine.Create(n++, l));
        SubTotal = Lines.Sum(l => l.LineSubTotal);
        TotalAmount = SubTotal + OtherCost;
        return Result.Success();
    }

    public Result Confirm(DateTime now)
    {
        if (Status != PurchaseStatuses.Draft) return Error.Conflict("purchase.not_draft", "Đơn nhập đã được đặt trước đó.");
        Status = PurchaseStatuses.Confirmed;
        ConfirmedAt = now;
        return Result.Success();
    }

    public Result CanReceive() => Status == PurchaseStatuses.Confirmed
        ? Result.Success()
        : Error.Conflict("purchase.not_confirmed", "Chỉ nhận hàng cho đơn đã đặt (chưa nhận).");

    /// <summary>
    /// Giá vốn nhập kho từng dòng = giá sau chiết khấu + phần chi phí khác (vận chuyển...)
    /// phân bổ theo tỷ lệ giá trị dòng.
    /// </summary>
    public IReadOnlyDictionary<long, decimal> LandedUnitCosts()
        => Lines.ToDictionary(l => l.Id, l =>
        {
            var share = SubTotal == 0 ? 0 : OtherCost * l.LineSubTotal / SubTotal;
            return l.Quantity == 0 ? 0 : Math.Round((l.LineSubTotal + share) / l.Quantity, 4);
        });

    public void MarkReceived()
    {
        foreach (var l in Lines) l.MarkReceived();
        ReceiptStatus = "received";
        Status = PurchaseStatuses.Completed;
    }

    public Result Cancel() => AmountPaid > 0
        ? Error.Conflict("purchase.paid", "Đơn đã trả tiền nhà cung cấp, hãy hủy phiếu chi trước.")
        : Status is PurchaseStatuses.Draft or PurchaseStatuses.Confirmed
        ? SetCancelled()
        : Error.Conflict("purchase.cannot_cancel", "Đơn đã nhận hàng không hủy được.");

    private Result SetCancelled()
    {
        Status = PurchaseStatuses.Cancelled;
        return Result.Success();
    }
}

public sealed class PurchaseOrderLine
{
    private PurchaseOrderLine() { }

    public long Id { get; private set; }
    public long PurchaseOrderId { get; private set; }
    public int LineNumber { get; private set; }
    public long ProductId { get; private set; }
    public string? Description { get; private set; }
    public long UomId { get; private set; }
    public decimal Quantity { get; private set; }
    public decimal UnitPrice { get; private set; }
    public decimal DiscountPercent { get; private set; }
    public decimal TaxRate { get; private set; }
    public decimal LineSubTotal { get; private set; }
    public decimal LineTax { get; private set; }
    public decimal LineTotal { get; private set; }
    public decimal QtyReceived { get; private set; }

    internal static PurchaseOrderLine Create(int n, PurchaseLineInfo l)
    {
        var sub = Math.Round(l.Quantity * l.UnitPrice * (1 - l.DiscountPercent / 100), 0);
        return new PurchaseOrderLine
        {
            LineNumber = n, ProductId = l.ProductId, UomId = l.UomId, Description = l.Description,
            Quantity = l.Quantity, UnitPrice = l.UnitPrice, DiscountPercent = l.DiscountPercent,
            LineSubTotal = sub, LineTotal = sub
        };
    }

    internal void MarkReceived() => QtyReceived = Quantity;
}
