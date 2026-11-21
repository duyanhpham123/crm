using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Purchasing;

namespace MyERP.Api.Controllers.Purchasing;

/// <summary>Mua hàng: nhà cung cấp, đơn nhập (Nháp -> Đã đặt -> Nhận hàng vào kho).</summary>
[Route("api/purchasing")]
[HasPermission(Permissions.Purchasing.View)]
public sealed class PurchasingController(IPurchaseService purchases) : ApiControllerBase
{
    // ----- Nhà cung cấp -----

    [HttpGet("suppliers")]
    public Task<PagedResult<SupplierListItem>> Suppliers([FromQuery] string? search, [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default)
        => purchases.ListSuppliersAsync(search, page, pageSize, ct);

    [HttpPost("suppliers")]
    [HasPermission(Permissions.Purchasing.Create)]
    public async Task<IActionResult> CreateSupplier(SaveSupplierRequest request, CancellationToken ct)
        => FromResult(await purchases.CreateSupplierAsync(request, ct), dto => Created($"/api/purchasing/suppliers/{dto.Id}", dto));

    [HttpPut("suppliers/{id:long}")]
    [HasPermission(Permissions.Purchasing.Edit)]
    public async Task<IActionResult> UpdateSupplier(long id, SaveSupplierRequest request, CancellationToken ct)
        => FromResult(await purchases.UpdateSupplierAsync(id, request, ct), Ok);

    // ----- Đơn nhập -----

    /// <summary>GET /api/purchasing/orders?search=&amp;status=&amp;supplierId=&amp;page=</summary>
    [HttpGet("orders")]
    public Task<PagedResult<PurchaseListItem>> List([FromQuery] string? search, [FromQuery] string? status, [FromQuery] long? supplierId,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => purchases.ListAsync(new PurchaseQuery(search, status, supplierId, page, pageSize), ct);

    [HttpGet("orders/{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct) => FromResult(await purchases.GetAsync(id, ct), Ok);

    [HttpPost("orders")]
    [HasPermission(Permissions.Purchasing.Create)]
    public async Task<IActionResult> Create(SavePurchaseRequest request, CancellationToken ct)
        => FromResult(await purchases.CreateAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    [HttpPut("orders/{id:long}")]
    [HasPermission(Permissions.Purchasing.Edit)]
    public async Task<IActionResult> Update(long id, SavePurchaseRequest request, CancellationToken ct)
        => FromResult(await purchases.UpdateAsync(id, request, ct), Ok);

    /// <summary>POST /api/purchasing/orders/5/confirm - chốt đặt hàng với nhà cung cấp.</summary>
    [HttpPost("orders/{id:long}/confirm")]
    [HasPermission(Permissions.Purchasing.Edit)]
    public async Task<IActionResult> Confirm(long id, CancellationToken ct) => FromResult(await purchases.ConfirmAsync(id, ct), Ok);

    /// <summary>POST /api/purchasing/orders/5/receive - nhận đủ hàng, nhập kho.</summary>
    [HttpPost("orders/{id:long}/receive")]
    [HasPermission(Permissions.Purchasing.Edit)]
    public async Task<IActionResult> Receive(long id, CancellationToken ct) => FromResult(await purchases.ReceiveAsync(id, ct), Ok);

    [HttpPost("orders/{id:long}/cancel")]
    [HasPermission(Permissions.Purchasing.Edit)]
    public async Task<IActionResult> Cancel(long id, CancellationToken ct) => FromResult(await purchases.CancelAsync(id, ct), Ok);
}
