using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Accounting;
using MyERP.Api.Services.Logistics;
using MyERP.Api.Services.Sales;
using MyERP.Api.Services.Support;

namespace MyERP.Api.Controllers;

/// <summary>Báo giá: Nháp -> Gửi khách -> Khách đồng ý (tạo đơn hàng) / Từ chối.</summary>
[Route("api/quotations")]
[HasPermission(Permissions.Quotations.View)]
public sealed class QuotationsController(IQuotationService quotations) : ApiControllerBase
{
    /// <summary>GET /api/quotations?search=&amp;status=draft|sent|expired|accepted|rejected|cancelled</summary>
    [HttpGet]
    public Task<QuotationPage> List([FromQuery] string? search, [FromQuery] string? status, [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => quotations.ListAsync(new QuotationQuery(search, status, page, pageSize), ct);

    [HttpGet("{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct) => FromResult(await quotations.GetAsync(id, ct), Ok);

    [HttpPost]
    [HasPermission(Permissions.Quotations.Create)]
    public async Task<IActionResult> Create(SaveQuotationRequest request, CancellationToken ct)
        => FromResult(await quotations.CreateAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    [HttpPut("{id:long}")]
    [HasPermission(Permissions.Quotations.Edit)]
    public async Task<IActionResult> Update(long id, SaveQuotationRequest request, CancellationToken ct)
        => FromResult(await quotations.UpdateAsync(id, request, ct), Ok);

    [HttpPost("{id:long}/send")]
    [HasPermission(Permissions.Quotations.Edit)]
    public async Task<IActionResult> Send(long id, CancellationToken ct) => FromResult(await quotations.SendAsync(id, ct), Ok);

    /// <summary>POST /api/quotations/5/accept - khách đồng ý, tạo đơn hàng nháp.</summary>
    [HttpPost("{id:long}/accept")]
    [HasPermission(Permissions.Quotations.Edit)]
    [HasPermission(Permissions.Orders.Create)]
    public async Task<IActionResult> Accept(long id, CancellationToken ct) => FromResult(await quotations.AcceptAsync(id, ct), Ok);

    [HttpPost("{id:long}/reject")]
    [HasPermission(Permissions.Quotations.Edit)]
    public async Task<IActionResult> Reject(long id, ReasonRequest request, CancellationToken ct)
        => FromResult(await quotations.RejectAsync(id, request.Reason, ct), Ok);

    [HttpPost("{id:long}/cancel")]
    [HasPermission(Permissions.Quotations.Edit)]
    public async Task<IActionResult> Cancel(long id, CancellationToken ct) => FromResult(await quotations.CancelAsync(id, ct), Ok);
}

/// <summary>Vận chuyển: vận đơn, hành trình, đối soát COD.</summary>
[Route("api/logistics")]
[HasPermission(Permissions.Logistics.View)]
public sealed class LogisticsController(IShipmentService shipments) : ApiControllerBase
{
    [HttpGet("lookups")]
    public Task<LogisticsLookups> Lookups(CancellationToken ct) => shipments.GetLookupsAsync(ct);

    /// <summary>GET /api/logistics/shipments?status=ready|in_transit|delivered|failed...&amp;carrierId=&amp;codStatus=collected</summary>
    [HttpGet("shipments")]
    public Task<ShipmentPage> List([FromQuery] string? search, [FromQuery] string? status, [FromQuery] long? carrierId,
        [FromQuery] string? codStatus, [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => shipments.ListAsync(new ShipmentQuery(search, status, carrierId, codStatus, page, pageSize), ct);

    /// <summary>GET /api/logistics/ready-orders - đơn đã xác nhận chưa có vận đơn.</summary>
    [HttpGet("ready-orders")]
    public Task<IReadOnlyList<ReadyToShipOrder>> ReadyOrders([FromQuery] string? search, CancellationToken ct) => shipments.ReadyOrdersAsync(search, ct);

    [HttpGet("shipments/{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct) => FromResult(await shipments.GetAsync(id, ct), Ok);

    [HttpPost("shipments")]
    [HasPermission(Permissions.Logistics.Create)]
    public async Task<IActionResult> Create(SaveShipmentRequest request, CancellationToken ct)
        => FromResult(await shipments.CreateAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    [HttpPut("shipments/{id:long}")]
    [HasPermission(Permissions.Logistics.Edit)]
    public async Task<IActionResult> Update(long id, SaveShipmentRequest request, CancellationToken ct)
        => FromResult(await shipments.UpdateAsync(id, request, ct), Ok);

    /// <summary>POST /api/logistics/shipments/5/status  body: { status: "delivered", note, location }</summary>
    [HttpPost("shipments/{id:long}/status")]
    [HasPermission(Permissions.Logistics.Edit)]
    public async Task<IActionResult> Status(long id, ShipmentStatusRequest request, CancellationToken ct)
        => FromResult(await shipments.ChangeStatusAsync(id, request, ct), Ok);

    /// <summary>POST /api/logistics/cod/reconcile - hãng chuyển tiền COD.</summary>
    [HttpPost("cod/reconcile")]
    [HasPermission(Permissions.Logistics.Edit)]
    [HasPermission(Permissions.Accounting.Create)]
    public async Task<IActionResult> Reconcile(CodReconcileRequest request, CancellationToken ct)
        => FromResult(await shipments.ReconcileCodAsync(request, ct), Ok);
}

/// <summary>Kế toán: phiếu thu chi, sổ quỹ, công nợ, lãi lỗ, tài khoản ngân hàng.</summary>
[Route("api/accounting")]
[HasPermission(Permissions.Accounting.View)]
public sealed class AccountingController(ICashService cash) : ApiControllerBase
{
    [HttpGet("lookups")]
    public Task<AccountingLookups> Lookups(CancellationToken ct) => cash.GetLookupsAsync(ct);

    /// <summary>GET /api/accounting/overview?from=2026-11-01&amp;to=2026-11-30 - lãi lỗ, dòng tiền, số dư quỹ, công nợ.</summary>
    [HttpGet("overview")]
    public Task<AccountingOverview> Overview([FromQuery] DateOnly? from, [FromQuery] DateOnly? to, CancellationToken ct)
        => cash.OverviewAsync(from, to, ct);

    /// <summary>GET /api/accounting/vouchers?type=receipt|payment&amp;category=&amp;fund=cash|{bankId}&amp;from=&amp;to=&amp;search=</summary>
    [HttpGet("vouchers")]
    public Task<VoucherPage> Vouchers([FromQuery] string? type, [FromQuery] string? category, [FromQuery] string? fund,
        [FromQuery] DateOnly? from, [FromQuery] DateOnly? to, [FromQuery] string? search, [FromQuery] int page = 1,
        [FromQuery] int pageSize = 30, CancellationToken ct = default)
        => cash.ListAsync(new VoucherQuery(type, category, fund, from, to, search, page, pageSize), ct);

    [HttpPost("vouchers")]
    [HasPermission(Permissions.Accounting.Create)]
    public async Task<IActionResult> CreateVoucher(CreateVoucherRequest request, CancellationToken ct)
        => FromResult(await cash.CreateAsync(request, ct), Ok);

    [HttpPost("vouchers/{id:long}/cancel")]
    [HasPermission(Permissions.Accounting.Edit)]
    public async Task<IActionResult> CancelVoucher(long id, CancellationToken ct) => FromResult(await cash.CancelAsync(id, ct), Ok);

    /// <summary>GET /api/accounting/cashbook?fund=cash|{bankId}&amp;from=&amp;to=</summary>
    [HttpGet("cashbook")]
    public async Task<IActionResult> CashBook([FromQuery] string fund = "cash", [FromQuery] DateOnly? from = null, [FromQuery] DateOnly? to = null,
        CancellationToken ct = default)
        => FromResult(await cash.CashBookAsync(fund, from, to, ct), Ok);

    [HttpGet("receivables")]
    public Task<DebtPage> Receivables([FromQuery] string? search, [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => cash.ReceivablesAsync(search, page, pageSize, ct);

    [HttpGet("receivables/{partnerId:long}")]
    public Task<IReadOnlyList<DebtDocument>> CustomerDocuments(long partnerId, CancellationToken ct) => cash.CustomerDocumentsAsync(partnerId, ct);

    [HttpGet("payables")]
    public Task<DebtPage> Payables([FromQuery] string? search, [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => cash.PayablesAsync(search, page, pageSize, ct);

    [HttpGet("payables/{partnerId:long}")]
    public Task<IReadOnlyList<DebtDocument>> SupplierDocuments(long partnerId, CancellationToken ct) => cash.SupplierDocumentsAsync(partnerId, ct);

    /// <summary>GET /api/accounting/partners?kind=customer|supplier&amp;search= - chọn đối tượng thu / chi (kèm số nợ).</summary>
    [HttpGet("partners")]
    public Task<IReadOnlyList<PartnerOption>> Partners([FromQuery] string kind = "customer", [FromQuery] string? search = null, CancellationToken ct = default)
        => cash.PartnersAsync(kind, search, ct);

    [HttpPost("bank-accounts")]
    [HasPermission(Permissions.Accounting.Edit)]
    public async Task<IActionResult> CreateBank(SaveBankAccountRequest request, CancellationToken ct)
        => FromResult(await cash.SaveBankAccountAsync(null, request, ct), Ok);

    [HttpPut("bank-accounts/{id:long}")]
    [HasPermission(Permissions.Accounting.Edit)]
    public async Task<IActionResult> UpdateBank(long id, SaveBankAccountRequest request, CancellationToken ct)
        => FromResult(await cash.SaveBankAccountAsync(id, request, ct), Ok);
}

/// <summary>CSKH: phiếu hỗ trợ / khiếu nại / đổi trả.</summary>
[Route("api/support")]
[HasPermission(Permissions.Support.View)]
public sealed class SupportController(ITicketService tickets) : ApiControllerBase
{
    [HttpGet("lookups")]
    public Task<SupportLookups> Lookups(CancellationToken ct) => tickets.GetLookupsAsync(ct);

    /// <summary>GET /api/support/tickets?status=active|all|new|open|pending|resolved|closed&amp;priority=&amp;mine=true&amp;overdueOnly=true</summary>
    [HttpGet("tickets")]
    public Task<TicketPage> List([FromQuery] string? search, [FromQuery] string? status, [FromQuery] string? priority,
        [FromQuery] long? assigneeId, [FromQuery] bool mine = false, [FromQuery] bool overdueOnly = false,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => tickets.ListAsync(new TicketQuery(search, status, priority, assigneeId, mine, overdueOnly, page, pageSize), ct);

    [HttpGet("tickets/{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct) => FromResult(await tickets.GetAsync(id, ct), Ok);

    [HttpPost("tickets")]
    [HasPermission(Permissions.Support.Create)]
    public async Task<IActionResult> Create(SaveTicketRequest request, CancellationToken ct)
        => FromResult(await tickets.CreateAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    [HttpPut("tickets/{id:long}")]
    [HasPermission(Permissions.Support.Edit)]
    public async Task<IActionResult> Update(long id, SaveTicketRequest request, CancellationToken ct)
        => FromResult(await tickets.UpdateAsync(id, request, ct), Ok);

    [HttpPost("tickets/{id:long}/messages")]
    [HasPermission(Permissions.Support.Edit)]
    public async Task<IActionResult> Message(long id, TicketMessageRequest request, CancellationToken ct)
        => FromResult(await tickets.AddMessageAsync(id, request, ct), Ok);

    [HttpPost("tickets/{id:long}/status")]
    [HasPermission(Permissions.Support.Edit)]
    public async Task<IActionResult> Status(long id, TicketStatusRequest request, CancellationToken ct)
        => FromResult(await tickets.ChangeStatusAsync(id, request, ct), Ok);

    [HttpPost("tickets/{id:long}/assign")]
    [HasPermission(Permissions.Support.Edit)]
    public async Task<IActionResult> Assign(long id, AssignRequest request, CancellationToken ct)
        => FromResult(await tickets.AssignAsync(id, request.UserId, ct), Ok);

    [HttpPost("tickets/{id:long}/rate")]
    [HasPermission(Permissions.Support.Edit)]
    public async Task<IActionResult> Rate(long id, RateRequest request, CancellationToken ct)
        => FromResult(await tickets.RateAsync(id, request, ct), Ok);
}
