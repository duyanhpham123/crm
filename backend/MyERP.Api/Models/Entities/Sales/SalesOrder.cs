using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Sales;

public static class OrderStatuses
{
    public const string Draft = "draft";
    public const string Confirmed = "confirmed";   // đã xác nhận, đã xuất kho
    public const string Completed = "completed";   // đã giao xong
    public const string Cancelled = "cancelled";
}

public sealed record OrderLineInfo(long ProductId, long UomId, string Description, decimal Quantity, decimal UnitPrice, decimal DiscountPercent);

public sealed record OrderInfo(
    long PartnerId,
    DateTime OrderDate,
    string Channel,
    long WarehouseId,
    long? SalespersonUserId,
    string? ReceiverName,
    string? ReceiverPhone,
    string? ShippingAddress,
    decimal ShippingFee,
    decimal DiscountAmount,
    string? PaymentMethodCode,
    string? Note,
    IReadOnlyList<OrderLineInfo> Lines);

/// <summary>
/// Bảng sales.SalesOrders - đơn bán hàng.
/// Luồng: Nháp -> Xác nhận (trừ kho) -> Hoàn thành. Hủy đơn đã xác nhận thì hàng trả về kho.
/// Giá bán đã gồm VAT (bán lẻ), nên thuế dòng = 0.
/// </summary>
public sealed class SalesOrder : AuditableEntity, ICompanyOwned
{
    private SalesOrder() { }

    public long CompanyId { get; private set; }
    public string DocNo { get; private set; } = "";
    public long PartnerId { get; private set; }
    public DateTime OrderDate { get; private set; }
    public string Channel { get; private set; } = "direct";
    public long? WarehouseId { get; private set; }
    public long? SalespersonUserId { get; private set; }
    public string? PaymentMethodCode { get; private set; }
    public string? ReceiverName { get; private set; }
    public string? ReceiverPhone { get; private set; }
    public string? ShippingStreet { get; private set; }
    public string Status { get; private set; } = OrderStatuses.Draft;
    public string DeliveryStatus { get; private set; } = "pending";
    public string PaymentStatus { get; private set; } = "unpaid";
    public decimal SubTotal { get; private set; }
    public decimal DiscountAmount { get; private set; }
    public decimal TaxAmount { get; private set; }
    public decimal ShippingFee { get; private set; }
    public decimal TotalAmount { get; private set; }
    public decimal AmountPaid { get; private set; }
    public string? Note { get; private set; }
    public DateTime? ConfirmedAt { get; private set; }
    public long? ConfirmedBy { get; private set; }
    public DateTime? CancelledAt { get; private set; }
    public long? QuotationId { get; private set; }
    /// <summary>Tổng tiền hàng khách đã trả lại (phiếu trả hàng). Doanh thu thuần = SubTotal - Discount - ReturnedAmount.</summary>
    public decimal ReturnedAmount { get; private set; }
    public string? CancelReason { get; private set; }

    public List<SalesOrderLine> Lines { get; private set; } = [];

    public decimal AmountDue => TotalAmount - AmountPaid;
    public bool IsEditable => Status == OrderStatuses.Draft;

    public static Result<SalesOrder> Create(long companyId, string docNo, OrderInfo info)
    {
        var o = new SalesOrder { CompanyId = companyId, DocNo = docNo };
        var r = o.Apply(info);
        return r.IsFailure ? r.Error! : o;
    }

    public Result Update(OrderInfo info)
        => IsEditable ? Apply(info) : Error.Conflict("order.locked", "Chỉ sửa được đơn ở trạng thái Nháp.");

    private Result Apply(OrderInfo d)
    {
        if (d.Lines.Count == 0) return Error.Validation("order.no_lines", "Đơn hàng phải có ít nhất một sản phẩm.");

        PartnerId = d.PartnerId;
        OrderDate = d.OrderDate;
        Channel = d.Channel;
        WarehouseId = d.WarehouseId;
        SalespersonUserId = d.SalespersonUserId;
        ReceiverName = Clean(d.ReceiverName);
        ReceiverPhone = PhoneNumber.Normalize(d.ReceiverPhone);
        ShippingStreet = Clean(d.ShippingAddress);
        ShippingFee = d.ShippingFee;
        PaymentMethodCode = d.PaymentMethodCode;
        Note = Clean(d.Note);

        Lines.Clear();
        var n = 1;
        foreach (var l in d.Lines) Lines.Add(SalesOrderLine.Create(n++, l));

        SubTotal = Lines.Sum(l => l.LineSubTotal);
        if (d.DiscountAmount > SubTotal) return Error.Validation("order.discount_too_large", "Giảm giá không được lớn hơn tiền hàng.");
        DiscountAmount = d.DiscountAmount;
        TaxAmount = 0;
        TotalAmount = SubTotal - DiscountAmount + ShippingFee;
        return Result.Success();
    }

    /// <summary>Xác nhận đơn: StockService đã xuất kho thành công thì gọi hàm này, kèm giá vốn từng dòng.</summary>
    public Result Confirm(IReadOnlyDictionary<long, decimal> unitCostByLineId, long? userId, DateTime now)
    {
        if (Status != OrderStatuses.Draft) return Error.Conflict("order.not_draft", "Đơn hàng đã được xác nhận trước đó.");
        foreach (var line in Lines) line.MarkDelivered(unitCostByLineId.GetValueOrDefault(line.Id));
        Status = OrderStatuses.Confirmed;
        ConfirmedAt = now;
        ConfirmedBy = userId;
        return Result.Success();
    }

    public Result Complete()
    {
        if (Status != OrderStatuses.Confirmed) return Error.Conflict("order.not_confirmed", "Chỉ hoàn thành được đơn đã xác nhận.");
        Status = OrderStatuses.Completed;
        DeliveryStatus = "delivered";
        return Result.Success();
    }

    public Result CanCancel() => Status switch
    {
        OrderStatuses.Cancelled => Error.Conflict("order.cancelled", "Đơn hàng đã hủy."),
        OrderStatuses.Completed => Error.Conflict("order.completed", "Đơn đã hoàn thành không hủy được. Hãy tạo phiếu trả hàng."),
        _ => Result.Success()
    };

    public bool StockWasIssued => Status == OrderStatuses.Confirmed;

    public void Cancel(string reason, DateTime now)
    {
        Status = OrderStatuses.Cancelled;
        CancelReason = reason.Trim();
        CancelledAt = now;
    }

    public void LinkQuotation(long quotationId) => QuotationId = quotationId;

    /// <summary>pending | shipping | delivered | returned - do Vận chuyển cập nhật.</summary>
    public void SetDeliveryStatus(string status) => DeliveryStatus = status;

    /// <summary>Hủy 1 khoản đã thu (phiếu thu bị hủy).</summary>
    public Result ReversePayment(decimal amount)
    {
        if (amount <= 0 || amount > AmountPaid) return Error.Validation("order.reverse_invalid", "Số tiền hủy vượt quá số đã thu.");
        AmountPaid -= amount;
        PaymentStatus = AmountPaid <= 0 ? "unpaid" : AmountPaid >= TotalAmount ? "paid" : "partial";
        return Result.Success();
    }

    /// <summary>Ghi nhận khách trả hàng (giá trị hàng trả) và số tiền đã hoàn lại cho khách.</summary>
    public Result RegisterReturn(decimal returnedValue, decimal refunded)
    {
        if (Status is not (OrderStatuses.Confirmed or OrderStatuses.Completed)) return Error.Conflict("order.not_delivered", "Chỉ trả hàng được với đơn đã xác nhận / hoàn thành.");
        if (refunded < 0 || refunded > AmountPaid) return Error.Validation("order.refund_too_large", $"Tiền hoàn không được lớn hơn số khách đã trả ({AmountPaid:N0} đ).");
        ReturnedAmount += returnedValue;
        AmountPaid -= refunded;
        TotalAmount = Math.Max(0, TotalAmount - returnedValue);
        PaymentStatus = AmountPaid <= 0 ? (TotalAmount == 0 ? "paid" : "unpaid") : AmountPaid >= TotalAmount ? "paid" : "partial";
        return Result.Success();
    }

    public Result RecordPayment(decimal amount, string method)
    {
        if (Status == OrderStatuses.Cancelled) return Error.Conflict("order.cancelled", "Đơn hàng đã hủy.");
        if (amount <= 0) return Error.Validation("order.payment_invalid", "Số tiền phải lớn hơn 0.");
        if (amount > AmountDue) return Error.Validation("order.payment_too_large", $"Số tiền vượt quá số còn phải thu ({AmountDue:N0} đ).");
        AmountPaid += amount;
        PaymentMethodCode = method;
        PaymentStatus = AmountPaid >= TotalAmount ? "paid" : "partial";
        return Result.Success();
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

public sealed class SalesOrderLine
{
    private SalesOrderLine() { }

    public long Id { get; private set; }
    public long SalesOrderId { get; private set; }
    public int LineNumber { get; private set; }
    public long ProductId { get; private set; }
    public string? Description { get; private set; }
    public long UomId { get; private set; }
    public decimal Quantity { get; private set; }
    public decimal UnitPrice { get; private set; }
    public decimal DiscountPercent { get; private set; }
    public decimal DiscountAmount { get; private set; }
    public decimal TaxRate { get; private set; }
    public decimal LineSubTotal { get; private set; }
    public decimal LineTax { get; private set; }
    public decimal LineTotal { get; private set; }
    public decimal UnitCost { get; private set; }
    public decimal QtyDelivered { get; private set; }

    internal static SalesOrderLine Create(int n, OrderLineInfo l)
    {
        var gross = l.Quantity * l.UnitPrice;
        var discount = Math.Round(gross * l.DiscountPercent / 100, 0);
        return new SalesOrderLine
        {
            LineNumber = n, ProductId = l.ProductId, UomId = l.UomId, Description = l.Description,
            Quantity = l.Quantity, UnitPrice = l.UnitPrice, DiscountPercent = l.DiscountPercent, DiscountAmount = discount,
            LineSubTotal = gross - discount, LineTotal = gross - discount
        };
    }

    internal void MarkDelivered(decimal unitCost)
    {
        UnitCost = unitCost;
        QtyDelivered = Quantity;
    }
}
