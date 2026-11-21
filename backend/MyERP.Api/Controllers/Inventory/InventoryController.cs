using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Common;
using MyERP.Api.Services.Inventory;

namespace MyERP.Api.Controllers.Inventory;

/// <summary>Kho: sản phẩm (mẫu + biến thể màu/size), tồn kho, phiếu nhập / xuất / điều chỉnh.</summary>
[Route("api/inventory")]
[HasPermission(Permissions.Inventory.View)]
public sealed class InventoryController(IProductService products, IInventoryService inventory) : ApiControllerBase
{
    /// <summary>GET /api/inventory/lookups - nhóm hàng, thương hiệu, đơn vị tính, kho, màu & size gợi ý.</summary>
    [HttpGet("lookups")]
    public Task<InventoryLookups> Lookups(CancellationToken ct) => products.GetLookupsAsync(ct);

    // ----- Sản phẩm -----

    /// <summary>GET /api/inventory/models?search=&amp;categoryId=&amp;page=</summary>
    [HttpGet("models")]
    public Task<PagedResult<ProductModelListItem>> Models([FromQuery] string? search, [FromQuery] long? categoryId,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 24, CancellationToken ct = default)
        => products.ListModelsAsync(search, categoryId, page, pageSize, ct);

    /// <summary>GET /api/inventory/models/5 - mẫu + toàn bộ biến thể kèm tồn.</summary>
    [HttpGet("models/{id:long}")]
    public async Task<IActionResult> Model(long id, CancellationToken ct) => FromResult(await products.GetModelAsync(id, ct), Ok);

    /// <summary>POST /api/inventory/models - tạo mẫu và sinh SKU theo màu × size.</summary>
    [HttpPost("models")]
    [HasPermission(Permissions.Inventory.Create)]
    public async Task<IActionResult> CreateModel(SaveProductModelRequest request, CancellationToken ct)
        => FromResult(await products.CreateModelAsync(request, ct), dto => CreatedAtAction(nameof(Model), new { id = dto.Id }, dto));

    /// <summary>PUT /api/inventory/models/5 - sửa mẫu, thêm màu / size mới.</summary>
    [HttpPut("models/{id:long}")]
    [HasPermission(Permissions.Inventory.Edit)]
    public async Task<IActionResult> UpdateModel(long id, SaveProductModelRequest request, CancellationToken ct)
        => FromResult(await products.UpdateModelAsync(id, request, ct), Ok);

    /// <summary>PUT /api/inventory/products/9 - sửa riêng 1 biến thể (giá, mã vạch, tồn tối thiểu).</summary>
    [HttpPut("products/{id:long}")]
    [HasPermission(Permissions.Inventory.Edit)]
    public async Task<IActionResult> UpdateVariant(long id, UpdateVariantRequest request, CancellationToken ct)
        => FromResult(await products.UpdateVariantAsync(id, request, ct), Ok);

    /// <summary>POST /api/inventory/categories  body: { "name": "Áo khoác" }</summary>
    [HttpPost("categories")]
    [HasPermission(Permissions.Inventory.Create)]
    public async Task<IActionResult> CreateCategory(NameRequest request, CancellationToken ct)
        => FromResult(await products.CreateCategoryAsync(request.Name, ct), Ok);

    /// <summary>POST /api/inventory/brands</summary>
    [HttpPost("brands")]
    [HasPermission(Permissions.Inventory.Create)]
    public async Task<IActionResult> CreateBrand(NameRequest request, CancellationToken ct)
        => FromResult(await products.CreateBrandAsync(request.Name, ct), Ok);

    // ----- Tồn kho & phiếu kho -----

    /// <summary>GET /api/inventory/stock?search=&amp;categoryId=&amp;warehouseId=&amp;lowOnly=true</summary>
    [HttpGet("stock")]
    public Task<StockPage> Stock([FromQuery] string? search, [FromQuery] long? categoryId, [FromQuery] long? warehouseId,
        [FromQuery] bool lowOnly = false, [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default)
        => inventory.GetStockAsync(new StockQuery(search, categoryId, warehouseId, lowOnly, page, pageSize), ct);

    /// <summary>GET /api/inventory/documents?docType=receipt|issue|adjustment&amp;search=</summary>
    [HttpGet("documents")]
    public Task<PagedResult<StockDocumentListItem>> Documents([FromQuery] string? docType, [FromQuery] string? search,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => inventory.ListDocumentsAsync(docType, search, page, pageSize, ct);

    [HttpGet("documents/{id:long}")]
    public async Task<IActionResult> Document(long id, CancellationToken ct) => FromResult(await inventory.GetDocumentAsync(id, ct), Ok);

    /// <summary>POST /api/inventory/documents - phiếu nhập / xuất / điều chỉnh thủ công, ghi sổ ngay.</summary>
    [HttpPost("documents")]
    [HasPermission(Permissions.Inventory.Create)]
    public async Task<IActionResult> CreateDocument(CreateStockDocumentRequest request, CancellationToken ct)
        => FromResult(await inventory.CreateDocumentAsync(request, ct), dto => CreatedAtAction(nameof(Document), new { id = dto.Id }, dto));
}

public sealed record NameRequest(string Name);

/// <summary>
/// Tìm SKU cho ô chọn sản phẩm. Dùng chung cho Đơn hàng, Mua hàng, Kho nên chỉ cần 1 trong 3 quyền xem.
/// </summary>
[Route("api/catalog")]
public sealed class CatalogController(IProductService products, ICurrentUser currentUser) : ApiControllerBase
{
    /// <summary>GET /api/catalog/skus?search=thun den m&amp;warehouseId=&amp;forPurchase=false</summary>
    [HttpGet("skus")]
    public async Task<IActionResult> Skus([FromQuery] string? search, [FromQuery] long? warehouseId, [FromQuery] bool forPurchase = false, CancellationToken ct = default)
    {
        var allowed = await currentUser.HasPermissionAsync(Permissions.Orders.View, ct)
            || await currentUser.HasPermissionAsync(Permissions.Purchasing.View, ct)
            || await currentUser.HasPermissionAsync(Permissions.Inventory.View, ct);
        if (!allowed) return ErrorResult(Common.Error.Forbidden());
        return Ok(await products.SearchSkusAsync(search, warehouseId, forPurchase, ct));
    }
}
