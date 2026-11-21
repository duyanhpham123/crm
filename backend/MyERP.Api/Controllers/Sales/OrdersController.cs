using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Sales;

namespace MyERP.Api.Controllers.Sales;

/// <summary>Đơn hàng bán: Nháp -> Xác nhận (trừ kho) -> Hoàn thành; thu tiền; hủy (hoàn kho).</summary>
[Route("api/sales")]
[HasPermission(Permissions.Orders.View)]
public sealed class OrdersController(IOrderService orders) : ApiControllerBase
{
    /// <summary>GET /api/sales/lookups - kho, nhân viên, kênh bán, hình thức thanh toán.</summary>
    [HttpGet("lookups")]
    public Task<SalesLookups> Lookups(CancellationToken ct) => orders.GetLookupsAsync(ct);

    /// <summary>GET /api/sales/orders?search=&amp;status=&amp;channel=&amp;from=2026-11-01&amp;to=2026-11-30&amp;page=</summary>
    [HttpGet("orders")]
    public Task<OrderPage> List([FromQuery] string? search, [FromQuery] string? status, [FromQuery] string? channel,
        [FromQuery] DateOnly? from, [FromQuery] DateOnly? to, [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => orders.ListAsync(new OrderQuery(search, status, channel, from, to, page, pageSize), ct);

    [HttpGet("orders/{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct) => FromResult(await orders.GetAsync(id, ct), Ok);

    /// <summary>POST /api/sales/orders - tạo đơn nháp.</summary>
    [HttpPost("orders")]
    [HasPermission(Permissions.Orders.Create)]
    public async Task<IActionResult> Create(SaveOrderRequest request, CancellationToken ct)
        => FromResult(await orders.CreateAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    /// <summary>PUT /api/sales/orders/5 - sửa đơn (chỉ khi Nháp).</summary>
    [HttpPut("orders/{id:long}")]
    [HasPermission(Permissions.Orders.Edit)]
    public async Task<IActionResult> Update(long id, SaveOrderRequest request, CancellationToken ct)
        => FromResult(await orders.UpdateAsync(id, request, ct), Ok);

    /// <summary>POST /api/sales/orders/5/confirm - xác nhận, xuất kho.</summary>
    [HttpPost("orders/{id:long}/confirm")]
    [HasPermission(Permissions.Orders.Edit)]
    public async Task<IActionResult> Confirm(long id, CancellationToken ct) => FromResult(await orders.ConfirmAsync(id, ct), Ok);

    /// <summary>POST /api/sales/orders/5/complete - đã giao xong.</summary>
    [HttpPost("orders/{id:long}/complete")]
    [HasPermission(Permissions.Orders.Edit)]
    public async Task<IActionResult> Complete(long id, CancellationToken ct) => FromResult(await orders.CompleteAsync(id, ct), Ok);

    /// <summary>POST /api/sales/orders/5/cancel  body: { reason } - hủy, hàng đã xuất được nhập lại kho.</summary>
    [HttpPost("orders/{id:long}/cancel")]
    [HasPermission(Permissions.Orders.Edit)]
    public async Task<IActionResult> Cancel(long id, CancelOrderRequest request, CancellationToken ct)
        => FromResult(await orders.CancelAsync(id, request.Reason, ct), Ok);

    /// <summary>POST /api/sales/orders/5/payments  body: { amount, method }</summary>
    [HttpPost("orders/{id:long}/payments")]
    [HasPermission(Permissions.Orders.Edit)]
    public async Task<IActionResult> Pay(long id, RecordPaymentRequest request, CancellationToken ct)
        => FromResult(await orders.RecordPaymentAsync(id, request, ct), Ok);

    /// <summary>GET /api/sales/promotions/check?code=SALE10&amp;subTotal=500000&amp;shippingFee=30000&amp;channel=shopee</summary>
    [HttpGet("promotions/check")]
    public async Task<IActionResult> CheckPromotion([FromQuery] string code, [FromQuery] decimal subTotal, [FromQuery] decimal shippingFee,
        [FromQuery] string channel = "direct", CancellationToken ct = default)
        => FromResult(await orders.CheckPromotionAsync(code, subTotal, shippingFee, channel, ct), Ok);

    /// <summary>POST /api/sales/orders/5/returns - khách trả hàng: nhập lại kho + hoàn tiền.</summary>
    [HttpPost("orders/{id:long}/returns")]
    [HasPermission(Permissions.Orders.Edit)]
    public async Task<IActionResult> Return(long id, CreateReturnRequest request, CancellationToken ct)
        => FromResult(await orders.CreateReturnAsync(id, request, ct), Ok);
}
