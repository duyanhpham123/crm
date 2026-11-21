using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.MasterData;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Inventory;

public interface IProductService
{
    Task<InventoryLookups> GetLookupsAsync(CancellationToken ct);
    Task<PagedResult<ProductModelListItem>> ListModelsAsync(string? search, long? categoryId, int page, int pageSize, CancellationToken ct);
    Task<Result<ProductModelDetail>> GetModelAsync(long id, CancellationToken ct);
    Task<Result<ProductModelDetail>> CreateModelAsync(SaveProductModelRequest request, CancellationToken ct);
    Task<Result<ProductModelDetail>> UpdateModelAsync(long id, SaveProductModelRequest request, CancellationToken ct);
    Task<Result<VariantDto>> UpdateVariantAsync(long productId, UpdateVariantRequest request, CancellationToken ct);
    Task<IReadOnlyList<SkuOption>> SearchSkusAsync(string? search, long? warehouseId, bool forPurchase, CancellationToken ct);
    Task<Result<OptionDto>> CreateCategoryAsync(string name, CancellationToken ct);
    Task<Result<OptionDto>> CreateBrandAsync(string name, CancellationToken ct);
}

/// <summary>Danh mục sản phẩm: mẫu + biến thể màu/size, nhóm hàng, thương hiệu.</summary>
public sealed class ProductService(AppDbContext db, ICurrentUser currentUser, IDocumentNumberService docNumbers) : IProductService
{
    private static readonly string[] Colors = ["Đen", "Trắng", "Xám", "Be", "Nâu", "Xanh navy", "Xanh dương", "Xanh rêu", "Đỏ", "Hồng", "Vàng", "Kem"];
    private static readonly string[] Sizes = ["XS", "S", "M", "L", "XL", "XXL", "28", "29", "30", "31", "32", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "Free size"];

    public async Task<InventoryLookups> GetLookupsAsync(CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        return new InventoryLookups(
            await db.ProductCategories.Where(c => c.IsActive).OrderBy(c => c.SortOrder).ThenBy(c => c.Name).Select(c => new OptionDto(c.Id, c.Name, null)).ToListAsync(ct),
            await db.Brands.OrderBy(b => b.Name).Select(b => new OptionDto(b.Id, b.Name, null)).ToListAsync(ct),
            await db.UnitsOfMeasure.Where(u => u.IsActive && (u.CompanyId == null || u.CompanyId == companyId)).OrderBy(u => u.Id).Select(u => new OptionDto(u.Id, u.Name, u.Code)).ToListAsync(ct),
            await db.Warehouses.OrderBy(w => w.Id).Select(w => new OptionDto(w.Id, w.Name, w.Code)).ToListAsync(ct),
            Colors, Sizes);
    }

    public async Task<PagedResult<ProductModelListItem>> ListModelsAsync(string? search, long? categoryId, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var q = db.ProductModels.AsQueryable();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            q = q.Where(m => m.Name.Contains(s) || m.Code.Contains(s) || m.Variants.Any(v => v.Code.Contains(s) || v.Barcode == s));
        }
        if (categoryId is { } c) q = q.Where(m => m.CategoryId == c);

        var total = await q.CountAsync(ct);
        var items = await q.OrderBy(m => m.IsActive ? 0 : 1).ThenByDescending(m => m.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(m => new ProductModelListItem(
                m.Id, m.Code, m.Name,
                db.ProductCategories.Where(x => x.Id == m.CategoryId).Select(x => x.Name).FirstOrDefault(),
                db.Brands.Where(x => x.Id == m.BrandId).Select(x => x.Name).FirstOrDefault(),
                m.Gender, m.SalePrice,
                m.Variants.Where(v => !v.IsDeleted).Min(v => (decimal?)v.SalePrice) ?? m.SalePrice,
                m.Variants.Where(v => !v.IsDeleted).Max(v => (decimal?)v.SalePrice) ?? m.SalePrice,
                m.Variants.Count(v => !v.IsDeleted),
                db.StockBalances.Where(b => m.Variants.Select(v => v.Id).Contains(b.ProductId)).Sum(b => (decimal?)b.QtyOnHand) ?? 0,
                m.Variants.Count(v => !v.IsDeleted && v.IsActive
                    && (db.StockBalances.Where(b => b.ProductId == v.Id).Sum(b => (decimal?)b.QtyOnHand) ?? 0) <= v.MinStock),
                m.IsActive))
            .AsNoTracking().ToListAsync(ct);
        return new PagedResult<ProductModelListItem>(items, page, pageSize, total);
    }

    public async Task<Result<ProductModelDetail>> GetModelAsync(long id, CancellationToken ct)
    {
        var m = await db.ProductModels.Include(x => x.Variants).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return m is null ? Error.NotFound("sản phẩm") : await ToDetailAsync(m, ct);
    }

    public async Task<Result<ProductModelDetail>> CreateModelAsync(SaveProductModelRequest req, CancellationToken ct)
    {
        var check = await ValidateRefsAsync(req, ct);
        if (check.IsFailure) return check.Error!;

        var code = string.IsNullOrWhiteSpace(req.Code) ? null : req.Code.Trim().ToUpperInvariant();
        if (code is not null && await db.ProductModels.IgnoreQueryFilters().AnyAsync(m => m.Code == code, ct))
            return Error.Conflict("product.code_taken", $"Mã sản phẩm \"{code}\" đã tồn tại.");

        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var model = ProductModel.Create(currentUser.RequireCompanyId(), code ?? await docNumbers.NextAsync("PRODUCT", ct: ct), ToInfo(req));
            var variants = model.GenerateVariants(req.Colors, req.Sizes);

            var dup = await DuplicateSkuAsync(variants.Select(v => v.Code), ct);
            if (dup is not null) return (Result<ProductModelDetail>)Error.Conflict("product.sku_taken", $"Mã SKU \"{dup}\" đã tồn tại. Đổi mã sản phẩm.");

            db.ProductModels.Add(model);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<ProductModelDetail>)await ToDetailAsync(model, ct);
        });
    }

    /// <summary>Sửa thông tin mẫu; màu/size mới được thêm thành biến thể mới (biến thể cũ không bị xóa).</summary>
    public async Task<Result<ProductModelDetail>> UpdateModelAsync(long id, SaveProductModelRequest req, CancellationToken ct)
    {
        var model = await db.ProductModels.Include(x => x.Variants).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (model is null) return Error.NotFound("sản phẩm");
        var check = await ValidateRefsAsync(req, ct);
        if (check.IsFailure) return check.Error!;

        if (!string.IsNullOrEmpty(req.RowVersion))
            db.Entry(model).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(req.RowVersion);

        var oldPrice = model.SalePrice;
        model.Update(ToInfo(req));
        // Biến thể đang theo giá mẫu cũ thì cập nhật theo giá mẫu mới; biến thể đặt giá riêng thì giữ
        foreach (var v in model.Variants.Where(v => v.SalePrice == oldPrice))
            v.UpdateVariant(req.SalePrice, v.Barcode, v.MinStock, v.IsActive);
        model.SetActive(req.IsActive);

        var created = model.GenerateVariants(
            req.Colors.Count > 0 ? req.Colors : model.Variants.Select(v => v.Color ?? "").Distinct(),
            req.Sizes.Count > 0 ? req.Sizes : model.Variants.Select(v => v.Size ?? "").Distinct());
        var dup = await DuplicateSkuAsync(created.Select(v => v.Code), ct);
        if (dup is not null) return Error.Conflict("product.sku_taken", $"Mã SKU \"{dup}\" đã tồn tại.");

        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(model, ct);
    }

    public async Task<Result<VariantDto>> UpdateVariantAsync(long productId, UpdateVariantRequest req, CancellationToken ct)
    {
        var p = await db.Products.FirstOrDefaultAsync(x => x.Id == productId, ct);
        if (p is null) return Error.NotFound("biến thể");
        var barcode = req.Barcode?.Trim();
        if (!string.IsNullOrEmpty(barcode) && await db.Products.AnyAsync(x => x.Barcode == barcode && x.Id != productId, ct))
            return Error.Conflict("product.barcode_taken", "Mã vạch đã dùng cho sản phẩm khác.");

        p.UpdateVariant(req.SalePrice, barcode, req.MinStock, req.IsActive);
        await db.SaveChangesAsync(ct);
        var onHand = await db.StockBalances.Where(b => b.ProductId == p.Id).SumAsync(b => (decimal?)b.QtyOnHand, ct) ?? 0;
        return new VariantDto(p.Id, p.Code, p.Barcode, p.Color, p.Size, p.SalePrice, p.CostPrice, p.MinStock, onHand, p.IsActive);
    }

    /// <summary>Tìm SKU cho ô chọn: theo mã, mã vạch, tên, màu, size. Kèm tồn khả dụng tại kho.</summary>
    public async Task<IReadOnlyList<SkuOption>> SearchSkusAsync(string? search, long? warehouseId, bool forPurchase, CancellationToken ct)
    {
        var q = db.Products.Where(p => p.IsActive && (forPurchase ? p.IsPurchasable : p.IsSellable));
        if (!string.IsNullOrWhiteSpace(search))
        {
            // Gõ nhiều từ: "thun den m" -> mọi từ đều phải khớp tên / mã
            foreach (var word in search.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries).Take(5))
            {
                var w = word;
                q = q.Where(p => p.Name.Contains(w) || p.Code.Contains(w) || p.Barcode == w);
            }
        }
        var wh = warehouseId ?? await db.Warehouses.OrderBy(w => w.Id).Select(w => w.Id).FirstOrDefaultAsync(ct);
        return await q.OrderBy(p => p.Name).Take(20)
            .Select(p => new SkuOption(p.Id, p.Code, p.Name, p.Color, p.Size, p.UomId,
                db.UnitsOfMeasure.Where(u => u.Id == p.UomId).Select(u => u.Name).FirstOrDefault() ?? "",
                p.SalePrice, p.CostPrice,
                db.StockBalances.Where(b => b.ProductId == p.Id && b.WarehouseId == wh).Sum(b => (decimal?)(b.QtyOnHand - b.QtyReserved)) ?? 0))
            .AsNoTracking().ToListAsync(ct);
    }

    public async Task<Result<OptionDto>> CreateCategoryAsync(string name, CancellationToken ct)
    {
        name = name.Trim();
        if (name.Length is 0 or > 150) return Error.Validation("category.name_invalid", "Tên nhóm hàng 1-150 ký tự.");
        if (await db.ProductCategories.AnyAsync(c => c.Name == name, ct)) return Error.Conflict("category.exists", "Nhóm hàng đã tồn tại.");
        var code = ProductModel.CodePart(name);
        if (code.Length == 0 || await db.ProductCategories.AnyAsync(c => c.Code == code, ct)) code = $"CAT{DateTime.UtcNow:HHmmssfff}";
        var c = ProductCategory.Create(currentUser.RequireCompanyId(), code, name, 100);
        db.ProductCategories.Add(c);
        await db.SaveChangesAsync(ct);
        return new OptionDto(c.Id, c.Name, null);
    }

    public async Task<Result<OptionDto>> CreateBrandAsync(string name, CancellationToken ct)
    {
        name = name.Trim();
        if (name.Length is 0 or > 150) return Error.Validation("brand.name_invalid", "Tên thương hiệu 1-150 ký tự.");
        if (await db.Brands.AnyAsync(b => b.Name == name, ct)) return Error.Conflict("brand.exists", "Thương hiệu đã tồn tại.");
        var b = Brand.Create(currentUser.RequireCompanyId(), name);
        db.Brands.Add(b);
        await db.SaveChangesAsync(ct);
        return new OptionDto(b.Id, b.Name, null);
    }

    // ---------- Hàm hỗ trợ ----------

    private async Task<Result> ValidateRefsAsync(SaveProductModelRequest req, CancellationToken ct)
    {
        if (req.CategoryId is { } c && !await db.ProductCategories.AnyAsync(x => x.Id == c, ct))
            return Error.Validation("product.category_invalid", "Nhóm hàng không hợp lệ.");
        if (req.BrandId is { } b && !await db.Brands.AnyAsync(x => x.Id == b, ct))
            return Error.Validation("product.brand_invalid", "Thương hiệu không hợp lệ.");
        if (!await db.UnitsOfMeasure.AnyAsync(u => u.Id == req.UomId, ct))
            return Error.Validation("product.uom_invalid", "Đơn vị tính không hợp lệ.");
        return Result.Success();
    }

    private async Task<string?> DuplicateSkuAsync(IEnumerable<string> codes, CancellationToken ct)
    {
        var list = codes.ToList();
        if (list.Count == 0) return null;
        return await db.Products.IgnoreQueryFilters().Where(p => list.Contains(p.Code)).Select(p => p.Code).FirstOrDefaultAsync(ct);
    }

    private async Task<ProductModelDetail> ToDetailAsync(ProductModel m, CancellationToken ct)
    {
        var ids = m.Variants.Select(v => v.Id).ToList();
        var stock = await db.StockBalances.Where(b => ids.Contains(b.ProductId))
            .GroupBy(b => b.ProductId).Select(g => new { g.Key, Qty = g.Sum(b => b.QtyOnHand) })
            .ToDictionaryAsync(x => x.Key, x => x.Qty, ct);
        var category = m.CategoryId is { } c ? await db.ProductCategories.Where(x => x.Id == c).Select(x => x.Name).FirstOrDefaultAsync(ct) : null;
        var brand = m.BrandId is { } b ? await db.Brands.Where(x => x.Id == b).Select(x => x.Name).FirstOrDefaultAsync(ct) : null;

        var sizeOrder = Sizes.Select((s, i) => (s, i)).ToDictionary(x => x.s, x => x.i, StringComparer.OrdinalIgnoreCase);
        var variants = m.Variants.Where(v => !v.IsDeleted)
            .OrderBy(v => v.Color).ThenBy(v => v.Size is null ? -1 : sizeOrder.GetValueOrDefault(v.Size, 999)).ThenBy(v => v.Size)
            .Select(v => new VariantDto(v.Id, v.Code, v.Barcode, v.Color, v.Size, v.SalePrice, v.CostPrice, v.MinStock,
                stock.GetValueOrDefault(v.Id), v.IsActive))
            .ToList();

        return new ProductModelDetail(m.Id, m.Code, m.Name, m.CategoryId, category, m.BrandId, brand, m.UomId, m.SalePrice, m.CostPrice,
            m.Gender, m.Material, m.Season, m.Description, m.IsActive, variants, Convert.ToBase64String(m.RowVersion));
    }

    private static ProductModelInfo ToInfo(SaveProductModelRequest r) => new(r.Name, r.CategoryId, r.BrandId, r.UomId,
        r.SalePrice, r.CostPrice, string.IsNullOrWhiteSpace(r.Gender) ? null : r.Gender, r.Material, r.Season, r.Description);
}
