using System.Globalization;
using System.Text;

namespace MyERP.Api.Models.Entities.MasterData;

public sealed record ProductModelInfo(
    string Name,
    long? CategoryId,
    long? BrandId,
    long UomId,
    decimal SalePrice,
    decimal CostPrice,
    string? Gender,
    string? Material,
    string? Season,
    string? Description);

/// <summary>
/// Bảng md.ProductModels - mẫu sản phẩm (VD "Áo thun basic cổ tròn").
/// Mỗi mẫu sinh ra nhiều SKU (md.Products) theo tổ hợp màu × size.
/// </summary>
public sealed class ProductModel : AuditableEntity, ICompanyOwned
{
    private ProductModel() { }

    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public long? CategoryId { get; private set; }
    public long? BrandId { get; private set; }
    public long UomId { get; private set; }
    public decimal SalePrice { get; private set; }
    public decimal CostPrice { get; private set; }
    public string? Gender { get; private set; }
    public string? Material { get; private set; }
    public string? Season { get; private set; }
    public string? Description { get; private set; }
    public bool IsActive { get; private set; }

    public List<Product> Variants { get; private set; } = [];

    public static ProductModel Create(long companyId, string code, ProductModelInfo info)
    {
        var m = new ProductModel { CompanyId = companyId, Code = code.Trim().ToUpperInvariant(), IsActive = true };
        m.Update(info);
        return m;
    }

    public void Update(ProductModelInfo d)
    {
        Name = d.Name.Trim();
        CategoryId = d.CategoryId;
        BrandId = d.BrandId;
        UomId = d.UomId;
        SalePrice = d.SalePrice;
        CostPrice = d.CostPrice;
        Gender = d.Gender;
        Material = Clean(d.Material);
        Season = Clean(d.Season);
        Description = Clean(d.Description);
        foreach (var v in Variants) v.SyncFromModel(this);
    }

    public void SetActive(bool active)
    {
        IsActive = active;
        foreach (var v in Variants) v.SetActive(active);
    }

    /// <summary>
    /// Sinh các biến thể còn thiếu cho tổ hợp màu × size. Biến thể đã có thì giữ nguyên.
    /// Mã SKU: {MÃ MẪU}-{MÀU}-{SIZE}, VD "ATB01-DEN-M".
    /// </summary>
    public IReadOnlyList<Product> GenerateVariants(IEnumerable<string> colors, IEnumerable<string> sizes)
    {
        var colorList = Normalize(colors);
        var sizeList = Normalize(sizes).Select(s => s.ToUpperInvariant()).ToList();
        if (colorList.Count == 0) colorList = [""];
        if (sizeList.Count == 0) sizeList = [""];

        var created = new List<Product>();
        foreach (var color in colorList)
        foreach (var size in sizeList)
        {
            var c = color == "" ? null : color;
            var s = size == "" ? null : size;
            if (Variants.Any(v => !v.IsDeleted && v.Color == c && v.Size == s)) continue;
            var variant = Product.CreateVariant(this, c, s);
            Variants.Add(variant);
            created.Add(variant);
        }
        return created;
    }

    /// <summary>"Xanh rêu" -> "XANHREU" (bỏ dấu, viết hoa, tối đa 8 ký tự) để ghép mã SKU.</summary>
    public static string CodePart(string text)
    {
        var normalized = text.Replace('Đ', 'D').Replace('đ', 'd').Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder();
        foreach (var ch in normalized)
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark && char.IsLetterOrDigit(ch))
                sb.Append(char.ToUpperInvariant(ch));
        var result = sb.ToString();
        return result.Length > 8 ? result[..8] : result;
    }

    private static List<string> Normalize(IEnumerable<string> values) => values
        .Select(v => v.Trim()).Where(v => v != "").Distinct(StringComparer.OrdinalIgnoreCase).ToList();

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

/// <summary>
/// Bảng md.Products - một SKU bán được, có tồn kho riêng (VD "Áo thun basic - Đen - M").
/// Sản phẩm thuộc mẫu thì tên / nhóm / thương hiệu đồng bộ theo mẫu; giá có thể đặt riêng.
/// </summary>
public sealed class Product : AuditableEntity, ICompanyOwned
{
    private Product() { }

    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string? Barcode { get; private set; }
    public string Name { get; private set; } = "";
    public string ProductType { get; private set; } = "goods";
    public long? CategoryId { get; private set; }
    public long? BrandId { get; private set; }
    public long? ModelId { get; private set; }
    public string? Color { get; private set; }
    public string? Size { get; private set; }
    public long UomId { get; private set; }
    public decimal SalePrice { get; private set; }
    public decimal CostPrice { get; private set; }
    public decimal MinStock { get; private set; }
    public bool IsSellable { get; private set; }
    public bool IsPurchasable { get; private set; }
    public bool IsStockTracked { get; private set; }
    public bool IsActive { get; private set; }

    public ProductModel? Model { get; private set; }

    internal static Product CreateVariant(ProductModel model, string? color, string? size)
    {
        var parts = new[] { model.Code, color is null ? null : ProductModel.CodePart(color), size is null ? null : ProductModel.CodePart(size) }
            .Where(p => !string.IsNullOrEmpty(p));
        var p = new Product
        {
            CompanyId = model.CompanyId,
            Code = string.Join("-", parts),
            Color = color,
            Size = size,
            SalePrice = model.SalePrice,
            CostPrice = model.CostPrice,
            MinStock = 3,
            IsSellable = true,
            IsPurchasable = true,
            IsStockTracked = true,
            IsActive = model.IsActive,
            Model = model
        };
        p.SyncFromModel(model);
        return p;
    }

    internal void SyncFromModel(ProductModel model)
    {
        Name = string.Join(" - ", new[] { model.Name, Color, Size }.Where(x => !string.IsNullOrEmpty(x)));
        CategoryId = model.CategoryId;
        BrandId = model.BrandId;
        UomId = model.UomId;
    }

    /// <summary>Sửa riêng một biến thể: giá bán, mã vạch, tồn tối thiểu.</summary>
    public void UpdateVariant(decimal salePrice, string? barcode, decimal minStock, bool isActive)
    {
        SalePrice = salePrice;
        Barcode = string.IsNullOrWhiteSpace(barcode) ? null : barcode.Trim();
        MinStock = minStock;
        IsActive = isActive;
    }

    public void SetActive(bool active) => IsActive = active;

    /// <summary>Giá vốn bình quân mới nhất (cập nhật khi nhập kho).</summary>
    public void SetCostPrice(decimal cost) => CostPrice = Math.Round(cost, 4);
}

/// <summary>Bảng md.ProductCategories - nhóm hàng (Áo thun, Quần jeans, Giày...).</summary>
public sealed class ProductCategory : ICompanyOwned
{
    private ProductCategory() { }

    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public long? ParentId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public int SortOrder { get; private set; }
    public bool IsActive { get; private set; }

    public static ProductCategory Create(long companyId, string code, string name, int sortOrder) =>
        new() { CompanyId = companyId, Code = code, Name = name.Trim(), SortOrder = sortOrder, IsActive = true };
}

/// <summary>Bảng md.Brands - thương hiệu.</summary>
public sealed class Brand : ICompanyOwned
{
    private Brand() { }

    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public string Name { get; private set; } = "";

    public static Brand Create(long companyId, string name) => new() { CompanyId = companyId, Name = name.Trim() };
}

/// <summary>Bảng md.UnitsOfMeasure - đơn vị tính (Cái, Đôi, Bộ...).</summary>
public sealed class UnitOfMeasure
{
    public long Id { get; private set; }
    public long? CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public bool IsActive { get; private set; }
}
