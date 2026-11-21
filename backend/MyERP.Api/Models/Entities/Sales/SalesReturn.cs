using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Sales;

public sealed record ReturnLineInfo(long SalesOrderLineId, long ProductId, decimal Quantity, decimal UnitPrice, string Condition);

/// <summary>
/// Bảng sales.SalesReturns - khách trả hàng (đổi trả). Ghi nhận xong là hàng về kho (hàng tốt)
/// và hoàn tiền cho khách (tiền mặt / chuyển khoản) trong cùng giao dịch.
/// </summary>
public sealed class SalesReturn : AuditableEntity, ICompanyOwned
{
    private SalesReturn() { }

    public long CompanyId { get; private set; }
    public string DocNo { get; private set; } = "";
    public long SalesOrderId { get; private set; }
    public long PartnerId { get; private set; }
    public long WarehouseId { get; private set; }
    public DateTime ReturnDate { get; private set; }
    public string? Reason { get; private set; }
    public string RefundMethod { get; private set; } = "cash";
    public string Status { get; private set; } = "refunded";
    public decimal SubTotal { get; private set; }
    public decimal TotalAmount { get; private set; }
    public long? StockDocumentId { get; private set; }

    private readonly List<SalesReturnLine> _lines = [];
    public IReadOnlyList<SalesReturnLine> Lines => _lines;

    public static Result<SalesReturn> Create(long companyId, string docNo, SalesOrder order, DateTime now, string? reason,
        string refundMethod, IReadOnlyList<ReturnLineInfo> lines)
    {
        if (lines.Count == 0 || lines.Any(l => l.Quantity <= 0)) return Error.Validation("return.lines", "Chọn sản phẩm và số lượng trả.");
        if (refundMethod is not ("cash" or "bank" or "credit_note")) return Error.Validation("return.method", "Hình thức hoàn tiền không hợp lệ.");
        if (lines.Any(l => l.Condition is not ("good" or "damaged"))) return Error.Validation("return.condition", "Tình trạng hàng không hợp lệ.");
        var r = new SalesReturn
        {
            CompanyId = companyId, DocNo = docNo, SalesOrderId = order.Id, PartnerId = order.PartnerId,
            WarehouseId = order.WarehouseId ?? 0, ReturnDate = now, Reason = string.IsNullOrWhiteSpace(reason) ? null : reason.Trim(),
            RefundMethod = refundMethod,
        };
        foreach (var l in lines)
            r._lines.Add(new SalesReturnLine(l.SalesOrderLineId, l.ProductId, l.Quantity, l.UnitPrice, Math.Round(l.Quantity * l.UnitPrice, 0), l.Condition));
        r.SubTotal = r.TotalAmount = r._lines.Sum(x => x.LineTotal);
        return r;
    }

    public void LinkStockDocument(long id) => StockDocumentId = id;

    /// <summary>Làm tròn từng dòng có thể lệch vài đồng so với tiền còn lại của đơn: chặn trên.</summary>
    internal void CapTotal(decimal max) => SubTotal = TotalAmount = max;
}

public sealed class SalesReturnLine
{
    private SalesReturnLine() { }
    internal SalesReturnLine(long orderLineId, long productId, decimal qty, decimal price, decimal total, string condition)
    {
        SalesOrderLineId = orderLineId; ProductId = productId; Quantity = qty; UnitPrice = price; LineTotal = total; Condition = condition;
    }
    public long Id { get; private set; }
    public long SalesReturnId { get; private set; }
    public long SalesOrderLineId { get; private set; }
    public long ProductId { get; private set; }
    public decimal Quantity { get; private set; }
    public decimal UnitPrice { get; private set; }
    public decimal LineTotal { get; private set; }
    public string Condition { get; private set; } = "good";
}
