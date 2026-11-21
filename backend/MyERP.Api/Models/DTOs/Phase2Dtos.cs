namespace MyERP.Api.Models.DTOs;

// ===================== BÁO GIÁ =====================

public sealed record QuotationQuery(string? Search, string? Status, int Page = 1, int PageSize = 20);

public sealed record QuotationListItem(long Id, string DocNo, DateOnly QuoteDate, DateOnly? ValidUntil, long CustomerId,
    string CustomerName, int ItemCount, decimal TotalAmount, string Status, string? SalespersonName, long? OrderId, string? OrderDocNo);

public sealed record QuotationSummary(int OpenCount, decimal OpenValue, int AcceptedCount, decimal AcceptedValue, decimal ConversionRate);

public sealed record QuotationPage(PagedResult<QuotationListItem> Rows, QuotationSummary Summary);

public sealed record QuotationLineDto(long Id, long ProductId, string Code, string Name, decimal Quantity, decimal UnitPrice,
    decimal DiscountPercent, decimal LineTotal);

public sealed record QuotationDetail(long Id, string DocNo, int RevisionNo, DateOnly QuoteDate, DateOnly? ValidUntil,
    long CustomerId, string CustomerName, string? CustomerPhone, string? CustomerEmail, string? CustomerAddress, string Status,
    decimal SubTotal, decimal DiscountAmount, decimal ShippingFee, decimal TotalAmount, string? Terms, string? Note,
    DateTime? SentAt, DateTime? AcceptedAt, string? RejectedReason, string? SalespersonName, long? OrderId, string? OrderDocNo,
    IReadOnlyList<QuotationLineDto> Lines, string RowVersion);

public sealed record SaveQuotationRequest(long CustomerId, DateOnly QuoteDate, DateOnly? ValidUntil, decimal DiscountAmount,
    decimal ShippingFee, string? Terms, string? Note, IReadOnlyList<OrderLineRequest> Lines, string? RowVersion = null);

public sealed record ReasonRequest(string Reason);

// ===================== TRẢ HÀNG =====================

public sealed record ReturnLineRequest(long SalesOrderLineId, decimal Quantity, string Condition = "good");

/// <summary>Khách trả hàng. RefundMethod: cash | bank | credit_note (không hoàn tiền, trừ vào công nợ).</summary>
public sealed record CreateReturnRequest(IReadOnlyList<ReturnLineRequest> Lines, string? Reason, string RefundMethod,
    decimal RefundAmount, long? BankAccountId = null);

public sealed record ReturnLineDto(long ProductId, string Code, string Name, decimal Quantity, decimal UnitPrice, decimal LineTotal, string Condition);

public sealed record SalesReturnDto(long Id, string DocNo, DateTime ReturnDate, string? Reason, string RefundMethod,
    decimal TotalAmount, IReadOnlyList<ReturnLineDto> Lines);

/// <summary>Chứng từ liên quan tới đơn hàng: báo giá gốc, vận đơn, phiếu CSKH.</summary>
public sealed record OrderLinks(long? QuotationId, string? QuotationDocNo, long? ShipmentId, string? ShipmentDocNo,
    string? ShipmentStatus, int TicketCount);

// ===================== VẬN CHUYỂN =====================

public sealed record LogisticsLookups(IReadOnlyList<OptionDto> Carriers, IReadOnlyList<CodeOption> Statuses,
    IReadOnlyList<OptionDto> BankAccounts);

public sealed record ShipmentQuery(string? Search, string? Status, long? CarrierId, string? CodStatus, int Page = 1, int PageSize = 20);

public sealed record ShipmentListItem(long Id, string DocNo, DateTime CreatedAt, long? OrderId, string? OrderDocNo, string CarrierName,
    string? TrackingNo, string ReceiverName, string ReceiverPhone, string Street, decimal CodAmount, decimal ShippingFee,
    string Status, string CodStatus, string? FailedReason);

public sealed record ShipmentSummary(int Ready, int InTransit, int Failed, int Returning, decimal CodHolding, decimal CodPending);

public sealed record ShipmentPage(PagedResult<ShipmentListItem> Rows, ShipmentSummary Summary);

public sealed record ShipmentEventDto(DateTime EventAt, string Status, string? Description, string? Location);

public sealed record ShipmentDetail(long Id, string DocNo, DateTime CreatedAt, long? OrderId, string? OrderDocNo, string? OrderStatus,
    decimal OrderAmountDue, long CarrierId, string CarrierName, string? TrackingNo, string? ServiceType, string ReceiverName,
    string ReceiverPhone, string Street, int PackageCount, decimal? WeightGram, decimal CodAmount, decimal ShippingFee,
    string FeePayer, string Status, string CodStatus, DateTime? PickedUpAt, DateTime? DeliveredAt, string? FailedReason,
    string? Note, IReadOnlyList<string> NextStatuses, IReadOnlyList<ShipmentEventDto> Events, string RowVersion);

public sealed record SaveShipmentRequest(long? SalesOrderId, long CarrierId, string? TrackingNo, string? ServiceType,
    string ReceiverName, string ReceiverPhone, string Street, int PackageCount, decimal? WeightGram, decimal CodAmount,
    decimal ShippingFee, string FeePayer, string? Note, string? RowVersion = null);

public sealed record ShipmentStatusRequest(string Status, string? Note, string? Location);

/// <summary>Đơn đã xác nhận nhưng chưa có vận đơn (chờ đóng gói giao).</summary>
public sealed record ReadyToShipOrder(long Id, string DocNo, DateTime OrderDate, string Channel, string CustomerName,
    string? ReceiverName, string? ReceiverPhone, string? ShippingAddress, decimal TotalAmount, decimal AmountDue, string? PaymentMethodCode);

public sealed record CodReconcileRequest(long CarrierId, IReadOnlyList<long> ShipmentIds, long? BankAccountId, string? Reference);

public sealed record CodReconcileResult(int ShipmentCount, decimal TotalCod, decimal TotalFee, decimal NetAmount,
    string ReceiptDocNo, string? FeeDocNo);

// ===================== KẾ TOÁN =====================

public sealed record BankAccountDto(long Id, string BankName, string? BankBranch, string AccountNo, string AccountName, bool IsActive, decimal Balance);

public sealed record VoucherCategoryDto(string Code, string Type, string Name);

public sealed record AccountingLookups(IReadOnlyList<BankAccountDto> BankAccounts, IReadOnlyList<VoucherCategoryDto> Categories,
    IReadOnlyList<CodeOption> PaymentMethods);

public sealed record VoucherQuery(string? Type, string? Category, string? Fund, DateOnly? From, DateOnly? To, string? Search,
    int Page = 1, int PageSize = 30);

public sealed record VoucherListItem(long Id, string DocNo, string Type, string? Category, string CategoryName, DateOnly Date,
    decimal Amount, string FundName, long? PartnerId, string? PartnerName, string? PersonName, string Reason,
    string? SourceType, long? SourceId, string? SourceDocNo, string Status);

public sealed record VoucherSummary(decimal TotalReceipt, decimal TotalPayment, decimal Net);

public sealed record VoucherPage(PagedResult<VoucherListItem> Rows, VoucherSummary Summary);

/// <summary>
/// Phiếu thu / chi. BankAccountId = null là tiền mặt.
/// Thu tiền khách (customer) / trả NCC (supplier) không chọn đơn cụ thể thì tự trừ vào các đơn còn nợ cũ nhất trước.
/// </summary>
public sealed record CreateVoucherRequest(string Type, string Category, long? BankAccountId, string? Method, long? PartnerId,
    long? SalesOrderId, long? PurchaseOrderId, decimal Amount, DateOnly Date, string Reason, string? PersonName, string? Reference);

public sealed record CreateVoucherResult(IReadOnlyList<VoucherListItem> Vouchers);

public sealed record FundBalance(string Key, string Name, decimal Balance);

public sealed record CashBookRow(long Id, DateOnly Date, string DocNo, string Reason, string? PartnerName, decimal In, decimal Out, decimal Balance);

public sealed record CashBook(string Fund, string FundName, DateOnly From, DateOnly To, decimal Opening, decimal TotalIn,
    decimal TotalOut, decimal Closing, IReadOnlyList<CashBookRow> Rows, IReadOnlyList<FundBalance> Funds);

public sealed record DebtRow(long PartnerId, string Code, string Name, string? Phone, int DocCount, decimal Total, decimal Paid,
    decimal Due, DateOnly? OldestDate);

public sealed record DebtPage(PagedResult<DebtRow> Rows, decimal TotalDue, int PartnerCount);

public sealed record DebtDocument(long Id, string DocNo, DateOnly Date, decimal Total, decimal Paid, decimal Due);

public sealed record PartnerOption(long Id, string Code, string Name, string? Phone, decimal Due);

public sealed record AccountingOverview(DateOnly From, DateOnly To, decimal Revenue, decimal Returns, decimal NetRevenue,
    decimal Cogs, decimal GrossProfit, IReadOnlyList<NamedValue> Expenses, decimal TotalExpense, decimal NetProfit,
    decimal CashIn, decimal CashOut, IReadOnlyList<FundBalance> Funds, decimal Receivable, decimal Payable);

public sealed record SaveBankAccountRequest(string BankName, string? BankBranch, string AccountNo, string AccountName, bool IsActive = true);

// ===================== CSKH =====================

public sealed record SupportLookups(IReadOnlyList<OptionDto> Categories, IReadOnlyList<OptionDto> Agents,
    IReadOnlyList<CodeOption> Channels, IReadOnlyList<CodeOption> Priorities);

public sealed record TicketQuery(string? Search, string? Status, string? Priority, long? AssigneeId, bool Mine = false,
    bool OverdueOnly = false, int Page = 1, int PageSize = 20);

public sealed record TicketListItem(long Id, string Code, string Subject, long? CustomerId, string? CustomerName, string? ReporterPhone,
    string? CategoryName, string Channel, string Priority, string Status, string? AssigneeName, DateTime CreatedAt,
    DateTime? ResolutionDueAt, bool IsOverdue);

public sealed record TicketSummary(int New, int Open, int Pending, int Overdue, int ResolvedThisMonth, decimal? AvgSatisfaction);

public sealed record TicketPage(PagedResult<TicketListItem> Rows, TicketSummary Summary);

public sealed record TicketMessageDto(long Id, string AuthorName, string Body, bool IsInternal, DateTime CreatedAt);

public sealed record TicketDetail(long Id, string Code, string Subject, string? Description, long? CustomerId, string? CustomerName,
    string? CustomerPhone, string? ReporterName, string? ReporterPhone, long? SalesOrderId, string? OrderDocNo, long? CategoryId,
    string? CategoryName, string Channel, string Priority, string Status, long? AssignedUserId, string? AssigneeName,
    DateTime? FirstResponseDueAt, DateTime? ResolutionDueAt, DateTime? FirstRespondedAt, DateTime? ResolvedAt, DateTime? ClosedAt,
    string? Resolution, byte? SatisfactionScore, string? SatisfactionNote, bool IsOverdue, DateTime CreatedAt,
    IReadOnlyList<TicketMessageDto> Messages, string RowVersion);

public sealed record SaveTicketRequest(string Subject, string? Description, long? CustomerId, string? ReporterName, string? ReporterPhone,
    long? SalesOrderId, long? CategoryId, string Channel, string Priority, long? AssignedUserId, string? RowVersion = null);

public sealed record TicketMessageRequest(string Body, bool IsInternal);

public sealed record TicketStatusRequest(string Status, string? Resolution);

public sealed record AssignRequest(long? UserId);

public sealed record RateRequest(byte Score, string? Note);
