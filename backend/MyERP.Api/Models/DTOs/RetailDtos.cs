namespace MyERP.Api.Models.DTOs;

// ===================== KHO: sản phẩm =====================

public sealed record InventoryLookups(
    IReadOnlyList<OptionDto> Categories,
    IReadOnlyList<OptionDto> Brands,
    IReadOnlyList<OptionDto> Units,
    IReadOnlyList<OptionDto> Warehouses,
    IReadOnlyList<string> SuggestedColors,
    IReadOnlyList<string> SuggestedSizes);

public sealed record ProductModelListItem(
    long Id, string Code, string Name, string? CategoryName, string? BrandName, string? Gender,
    decimal SalePrice, decimal MinPrice, decimal MaxPrice, int VariantCount, decimal TotalStock, int LowStockVariants, bool IsActive);

public sealed record VariantDto(
    long Id, string Code, string? Barcode, string? Color, string? Size,
    decimal SalePrice, decimal CostPrice, decimal MinStock, decimal OnHand, bool IsActive);

public sealed record ProductModelDetail(
    long Id, string Code, string Name, long? CategoryId, string? CategoryName, long? BrandId, string? BrandName,
    long UomId, decimal SalePrice, decimal CostPrice, string? Gender, string? Material, string? Season, string? Description,
    bool IsActive, IReadOnlyList<VariantDto> Variants, string RowVersion);

/// <summary>POST /api/inventory/models. Code để trống thì tự sinh. Colors × Sizes sinh ra các SKU.</summary>
public sealed record SaveProductModelRequest(
    string? Code,
    string Name,
    long? CategoryId,
    long? BrandId,
    long UomId,
    decimal SalePrice,
    decimal CostPrice,
    string? Gender,
    string? Material,
    string? Season,
    string? Description,
    IReadOnlyList<string> Colors,
    IReadOnlyList<string> Sizes,
    bool IsActive = true,
    string? RowVersion = null);

public sealed record UpdateVariantRequest(decimal SalePrice, string? Barcode, decimal MinStock, bool IsActive);

/// <summary>Kết quả tìm SKU cho ô chọn sản phẩm ở đơn hàng / đơn nhập / phiếu kho.</summary>
public sealed record SkuOption(long Id, string Code, string Name, string? Color, string? Size, long UomId, string UomName,
    decimal SalePrice, decimal CostPrice, decimal Available);

// ===================== KHO: tồn & phiếu kho =====================

public sealed record StockQuery(string? Search, long? CategoryId, long? WarehouseId, bool LowOnly, int Page = 1, int PageSize = 50);

public sealed record StockRow(long ProductId, string Code, string Name, string? Color, string? Size, string? CategoryName,
    string WarehouseName, decimal OnHand, decimal MinStock, decimal AvgCost, decimal StockValue, bool IsLow);

public sealed record StockSummary(decimal TotalQuantity, decimal TotalValue, int SkuCount, int LowStockCount, int OutOfStockCount);

public sealed record StockPage(PagedResult<StockRow> Rows, StockSummary Summary);

public sealed record StockDocumentListItem(long Id, string DocNo, string DocType, string Reason, string WarehouseName,
    string? PartnerName, string? SourceDocNo, DateTime DocDate, decimal TotalQuantity, decimal TotalValue, string? Note);

public sealed record StockDocumentLineDto(long ProductId, string Code, string Name, decimal Quantity, decimal UnitCost, decimal LineValue);

public sealed record StockDocumentDetail(long Id, string DocNo, string DocType, string Reason, long WarehouseId, string WarehouseName,
    string? PartnerName, string? SourceType, long? SourceId, string? SourceDocNo, DateTime DocDate, string? Note,
    decimal TotalQuantity, decimal TotalValue, IReadOnlyList<StockDocumentLineDto> Lines);

public sealed record StockLineRequest(long ProductId, decimal Quantity, decimal? UnitCost);

/// <summary>Phiếu kho thủ công. DocType: receipt | issue | adjustment (adjustment: Quantity âm = giảm, dương = tăng).</summary>
public sealed record CreateStockDocumentRequest(string DocType, string Reason, long WarehouseId, string? Note, IReadOnlyList<StockLineRequest> Lines);

// ===================== ĐƠN HÀNG =====================

public sealed record OrderQuery(string? Search, string? Status, string? Channel, DateOnly? From, DateOnly? To, int Page = 1, int PageSize = 20);

public sealed record OrderListItem(long Id, string DocNo, DateTime OrderDate, string Channel, long CustomerId, string CustomerName,
    string? CustomerPhone, int ItemCount, decimal TotalAmount, decimal AmountPaid, string Status, string PaymentStatus,
    string DeliveryStatus, string? SalespersonName);

public sealed record OrderSummary(int Count, decimal TotalAmount, decimal AmountPaid, decimal AmountDue);

public sealed record OrderPage(PagedResult<OrderListItem> Rows, OrderSummary Summary);

public sealed record OrderLineDto(long Id, long ProductId, string Code, string Name, string? Color, string? Size,
    decimal Quantity, decimal UnitPrice, decimal DiscountPercent, decimal LineTotal, decimal UnitCost, decimal QtyReturned = 0);

public sealed record OrderDetail(long Id, string DocNo, DateTime OrderDate, string Channel, long CustomerId, string CustomerName,
    bool IsWalkIn, long? WarehouseId, long? SalespersonUserId, string? ReceiverName, string? ReceiverPhone, string? ShippingAddress,
    string Status, string PaymentStatus, string DeliveryStatus, string? PaymentMethodCode,
    decimal SubTotal, decimal DiscountAmount, decimal ShippingFee, decimal TotalAmount, decimal AmountPaid, decimal AmountDue,
    decimal GrossProfit, string? Note, string? CancelReason, DateTime? ConfirmedAt, DateTime CreatedAt,
    IReadOnlyList<OrderLineDto> Lines, string RowVersion, decimal ReturnedAmount = 0,
    IReadOnlyList<SalesReturnDto>? Returns = null, OrderLinks? Links = null, string? PromotionCode = null, decimal PromotionDiscount = 0);

public sealed record OrderLineRequest(long ProductId, decimal Quantity, decimal UnitPrice, decimal DiscountPercent);

/// <summary>CustomerId = null thì dùng khách "Khách lẻ".</summary>
public sealed record SaveOrderRequest(
    long? CustomerId,
    string Channel,
    long? WarehouseId,
    string? ReceiverName,
    string? ReceiverPhone,
    string? ShippingAddress,
    decimal ShippingFee,
    decimal DiscountAmount,
    string? PaymentMethodCode,
    string? Note,
    IReadOnlyList<OrderLineRequest> Lines,
    string? RowVersion = null,
    string? PromotionCode = null);

public sealed record CancelOrderRequest(string Reason);

public sealed record RecordPaymentRequest(decimal Amount, string Method);

public sealed record SalesLookups(IReadOnlyList<OptionDto> Warehouses, IReadOnlyList<OptionDto> Salespeople,
    IReadOnlyList<CodeOption> Channels, IReadOnlyList<CodeOption> PaymentMethods);

public sealed record CodeOption(string Code, string Name);

// ===================== MUA HÀNG =====================

public sealed record SupplierListItem(long Id, string Code, string Name, string? TaxCode, string? Phone, string? Email,
    string? ContactName, int OrderCount, decimal TotalPurchased, bool IsActive,
    string? Street = null, string? ContactPhone = null, string? Note = null);

public sealed record SaveSupplierRequest(string Name, string? TaxCode, string? Phone, string? Email, string? Street, string? Note,
    string? ContactName, string? ContactPhone);

public sealed record PurchaseQuery(string? Search, string? Status, long? SupplierId, int Page = 1, int PageSize = 20);

public sealed record PurchaseListItem(long Id, string DocNo, DateOnly OrderDate, DateOnly? ExpectedDate, long SupplierId,
    string SupplierName, int ItemCount, decimal TotalQuantity, decimal TotalAmount, string Status, string ReceiptStatus);

public sealed record PurchaseLineDto(long Id, long ProductId, string Code, string Name, decimal Quantity, decimal UnitPrice,
    decimal DiscountPercent, decimal LineTotal, decimal QtyReceived);

public sealed record PurchaseDetail(long Id, string DocNo, DateOnly OrderDate, DateOnly? ExpectedDate, long SupplierId, string SupplierName,
    long WarehouseId, string Status, string ReceiptStatus, decimal SubTotal, decimal OtherCost, decimal TotalAmount, string? Note,
    long? ReceiptDocumentId, string? ReceiptDocNo, IReadOnlyList<PurchaseLineDto> Lines, string RowVersion);

public sealed record PurchaseLineRequest(long ProductId, decimal Quantity, decimal UnitPrice, decimal DiscountPercent);

public sealed record SavePurchaseRequest(long SupplierId, DateOnly OrderDate, DateOnly? ExpectedDate, long? WarehouseId,
    decimal OtherCost, string? Note, IReadOnlyList<PurchaseLineRequest> Lines, string? RowVersion = null);

// ===================== BÁO CÁO =====================

public sealed record KpiValue(decimal Value, decimal PreviousValue)
{
    /// <summary>% thay đổi so với kỳ trước (null nếu kỳ trước = 0).</summary>
    public decimal? ChangePercent => PreviousValue == 0 ? null : Math.Round((Value - PreviousValue) / PreviousValue * 100, 1);
}

public sealed record DailyRevenue(DateOnly Date, decimal Revenue, decimal GrossProfit, int Orders);

public sealed record NamedValue(string Name, decimal Value, decimal Quantity);

public sealed record TopProduct(long ModelId, string Code, string Name, decimal Quantity, decimal Revenue, decimal GrossProfit);

public sealed record LowStockItem(long ProductId, string Code, string Name, decimal OnHand, decimal MinStock);

public sealed record Dashboard(
    int Days,
    KpiValue Revenue,
    KpiValue GrossProfit,
    KpiValue Orders,
    KpiValue AverageOrderValue,
    decimal ReceivableOutstanding,
    decimal StockValue,
    IReadOnlyList<DailyRevenue> RevenueByDay,
    IReadOnlyList<NamedValue> RevenueByChannel,
    IReadOnlyList<NamedValue> RevenueByCategory,
    IReadOnlyList<TopProduct> TopProducts,
    IReadOnlyList<LowStockItem> LowStock,
    IReadOnlyList<NamedValue> OrdersByStatus);
