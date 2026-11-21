namespace MyERP.Api.Models.Entities.Inventory;

public static class StockDocTypes
{
    public const string Receipt = "receipt";       // nhập kho
    public const string Issue = "issue";           // xuất kho
    public const string Adjustment = "adjustment"; // kiểm kê / điều chỉnh (số lượng có thể âm)
}

/// <summary>Bảng inv.Warehouses - kho hàng / cửa hàng.</summary>
public sealed class Warehouse : ICompanyOwned
{
    public static Warehouse Create(long companyId, long? branchId, string code, string name)
        => new() { CompanyId = companyId, BranchId = branchId, Code = code.Trim().ToUpperInvariant(), Name = name.Trim(), IsActive = true };

    public void Update(string name, string? address, bool allowNegative, bool isActive)
    {
        Name = name.Trim(); Street = string.IsNullOrWhiteSpace(address) ? null : address.Trim(); AllowNegativeStock = allowNegative; IsActive = isActive;
    }

    public long? BranchId { get; private set; }
    public string? Street { get; private set; }
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public bool AllowNegativeStock { get; private set; }
    public bool IsActive { get; private set; }
}

/// <summary>
/// Bảng inv.StockDocuments - phiếu nhập / xuất / điều chỉnh kho.
/// Phiếu được ghi sổ ngay khi tạo (Status = done) bởi StockService.
/// </summary>
public sealed class StockDocument : AuditableEntity, ICompanyOwned
{
    private StockDocument() { }

    public long CompanyId { get; private set; }
    public string DocNo { get; private set; } = "";
    public string DocType { get; private set; } = StockDocTypes.Receipt;
    public string Reason { get; private set; } = "other";
    public long WarehouseId { get; private set; }
    public long? PartnerId { get; private set; }
    public string? SourceType { get; private set; }
    public long? SourceId { get; private set; }
    public string? SourceDocNo { get; private set; }
    public DateTime DocDate { get; private set; }
    public string Status { get; private set; } = "draft";
    public string? Note { get; private set; }
    public decimal TotalQuantity { get; private set; }
    public decimal TotalValue { get; private set; }
    public DateTime? DoneAt { get; private set; }
    public long? DoneBy { get; private set; }

    public List<StockDocumentLine> Lines { get; private set; } = [];

    public static StockDocument Create(long companyId, string docNo, string docType, string reason, long warehouseId,
        DateTime docDate, string? note, long? partnerId = null, string? sourceType = null, long? sourceId = null, string? sourceDocNo = null)
        => new()
        {
            CompanyId = companyId, DocNo = docNo, DocType = docType, Reason = reason, WarehouseId = warehouseId,
            DocDate = docDate, Note = string.IsNullOrWhiteSpace(note) ? null : note.Trim(),
            PartnerId = partnerId, SourceType = sourceType, SourceId = sourceId, SourceDocNo = sourceDocNo
        };

    /// <param name="quantity">Số lượng (luôn dương với nhập / xuất; âm hoặc dương với điều chỉnh).</param>
    public StockDocumentLine AddLine(long productId, long uomId, decimal quantity, decimal unitCost, long? sourceLineId = null)
    {
        var line = StockDocumentLine.Create(Lines.Count + 1, productId, uomId, quantity, unitCost, sourceLineId);
        Lines.Add(line);
        return line;
    }

    internal void MarkDone(long? userId, DateTime now)
    {
        Status = "done";
        DoneAt = now;
        DoneBy = userId;
        TotalQuantity = Lines.Sum(l => Math.Abs(l.Quantity));
        TotalValue = Lines.Sum(l => Math.Abs(l.LineValue));
    }
}

public sealed class StockDocumentLine
{
    private StockDocumentLine() { }

    public long Id { get; private set; }
    public long DocumentId { get; private set; }
    public int LineNumber { get; private set; }
    public long ProductId { get; private set; }
    public long UomId { get; private set; }
    public decimal Quantity { get; private set; }
    public decimal BaseQuantity { get; private set; }
    public decimal UnitCost { get; private set; }
    public decimal LineValue { get; private set; }
    public long? SourceLineId { get; private set; }

    internal static StockDocumentLine Create(int lineNumber, long productId, long uomId, decimal qty, decimal unitCost, long? sourceLineId) => new()
    {
        LineNumber = lineNumber, ProductId = productId, UomId = uomId, Quantity = qty, BaseQuantity = qty,
        UnitCost = unitCost, LineValue = Math.Round(qty * unitCost, 0), SourceLineId = sourceLineId
    };

    /// <summary>Xuất kho: giá vốn lấy theo bình quân tại thời điểm xuất.</summary>
    internal void SetCost(decimal unitCost)
    {
        UnitCost = Math.Round(unitCost, 4);
        LineValue = Math.Round(Quantity * UnitCost, 0);
    }
}

/// <summary>Bảng inv.StockLedger - sổ kho, mỗi dòng 1 biến động, chỉ thêm không sửa.</summary>
public sealed class StockLedgerEntry
{
    private StockLedgerEntry() { }

    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public long ProductId { get; private set; }
    public long WarehouseId { get; private set; }
    public DateTime MoveDate { get; private set; }
    public decimal QtyIn { get; private set; }
    public decimal QtyOut { get; private set; }
    public decimal UnitCost { get; private set; }
    public decimal ValueIn { get; private set; }
    public decimal ValueOut { get; private set; }
    public long StockDocumentId { get; private set; }
    public long StockDocumentLineId { get; private set; }

    internal static StockLedgerEntry Create(StockDocument doc, StockDocumentLine line, decimal qtyIn, decimal qtyOut, decimal unitCost) => new()
    {
        CompanyId = doc.CompanyId, ProductId = line.ProductId, WarehouseId = doc.WarehouseId, MoveDate = doc.DocDate,
        QtyIn = qtyIn, QtyOut = qtyOut, UnitCost = unitCost,
        ValueIn = Math.Round(qtyIn * unitCost, 0), ValueOut = Math.Round(qtyOut * unitCost, 0),
        StockDocumentId = doc.Id, StockDocumentLineId = line.Id
    };
}

/// <summary>Bảng inv.StockBalances - tồn hiện tại theo kho + SKU (đọc nhanh, tính lại được từ sổ kho).</summary>
public sealed class StockBalance : ICompanyOwned
{
    private StockBalance() { }

    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public long WarehouseId { get; private set; }
    public long ProductId { get; private set; }
    public decimal QtyOnHand { get; private set; }
    public decimal QtyReserved { get; private set; }
    public decimal AvgCost { get; private set; }
    public DateTime UpdatedAt { get; private set; }
    public byte[] RowVersion { get; private set; } = [];

    public static StockBalance Create(long companyId, long warehouseId, long productId)
        => new() { CompanyId = companyId, WarehouseId = warehouseId, ProductId = productId };

    /// <summary>Nhập: giá vốn bình quân gia quyền = (tồn × giá cũ + nhập × giá nhập) / tổng.</summary>
    public void Receive(decimal qty, decimal unitCost, DateTime now)
    {
        var newQty = QtyOnHand + qty;
        AvgCost = QtyOnHand <= 0 || newQty <= 0 ? unitCost : Math.Round((QtyOnHand * AvgCost + qty * unitCost) / newQty, 4);
        QtyOnHand = newQty;
        UpdatedAt = now;
    }

    public void Issue(decimal qty, DateTime now)
    {
        QtyOnHand -= qty;
        UpdatedAt = now;
    }

    /// <summary>Chỉ dùng cho unit test.</summary>
    internal static StockBalance ForTest(decimal qty, decimal avg) => new() { QtyOnHand = qty, AvgCost = avg };
}
