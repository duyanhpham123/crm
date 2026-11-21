using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MyERP.Api.Models.Entities.Inventory;
using MyERP.Api.Models.Entities.MasterData;
using MyERP.Api.Models.Entities.Purchasing;
using MyERP.Api.Models.Entities.Sales;

namespace MyERP.Api.Data.Configurations;

// Map entity Kho / Bán hàng / Mua hàng vào các bảng md, inv, sales, pur.
// Cột có trong DB nhưng không map ở đây sẽ dùng giá trị DEFAULT của DB khi thêm mới.

internal sealed class ProductModelConfiguration : IEntityTypeConfiguration<ProductModel>
{
    public void Configure(EntityTypeBuilder<ProductModel> e)
    {
        e.ToTable("ProductModels", "md");
        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false);
        e.Property(x => x.Name).HasMaxLength(255);
        e.HasMany(x => x.Variants).WithOne(x => x.Model).HasForeignKey(x => x.ModelId);
    }
}

internal sealed class ProductConfiguration : IEntityTypeConfiguration<Product>
{
    public void Configure(EntityTypeBuilder<Product> e)
    {
        e.ToTable("Products", "md");
        e.Property(x => x.Code).HasMaxLength(50).IsUnicode(false);
        e.Property(x => x.Barcode).HasMaxLength(50).IsUnicode(false);
        e.Property(x => x.Name).HasMaxLength(255);
        e.Property(x => x.Size).HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.WebSlug).HasMaxLength(255).IsUnicode(false);
    }
}

internal sealed class ProductCategoryConfiguration : IEntityTypeConfiguration<ProductCategory>
{
    public void Configure(EntityTypeBuilder<ProductCategory> e) => e.ToTable("ProductCategories", "md");
}

internal sealed class BrandConfiguration : IEntityTypeConfiguration<Brand>
{
    public void Configure(EntityTypeBuilder<Brand> e) => e.ToTable("Brands", "md");
}

internal sealed class UnitOfMeasureConfiguration : IEntityTypeConfiguration<UnitOfMeasure>
{
    public void Configure(EntityTypeBuilder<UnitOfMeasure> e) => e.ToTable("UnitsOfMeasure", "md");
}

internal sealed class WarehouseConfiguration : IEntityTypeConfiguration<Warehouse>
{
    public void Configure(EntityTypeBuilder<Warehouse> e)
    {
        e.ToTable("Warehouses", "inv");
        // Bộ lọc có tên: không được trộn bộ lọc vô danh với bộ lọc "Company" tự thêm ở AppDbContext
        e.HasQueryFilter("Active", x => x.IsActive);
    }
}

internal sealed class StockDocumentConfiguration : IEntityTypeConfiguration<StockDocument>
{
    public void Configure(EntityTypeBuilder<StockDocument> e)
    {
        e.ToTable("StockDocuments", "inv");
        e.Property(x => x.DocNo).HasMaxLength(30).IsUnicode(false);
        e.HasMany(x => x.Lines).WithOne().HasForeignKey(x => x.DocumentId);
    }
}

internal sealed class StockDocumentLineConfiguration : IEntityTypeConfiguration<StockDocumentLine>
{
    public void Configure(EntityTypeBuilder<StockDocumentLine> e) => e.ToTable("StockDocumentLines", "inv");
}

internal sealed class StockLedgerConfiguration : IEntityTypeConfiguration<StockLedgerEntry>
{
    public void Configure(EntityTypeBuilder<StockLedgerEntry> e) => e.ToTable("StockLedger", "inv");
}

internal sealed class StockBalanceConfiguration : IEntityTypeConfiguration<StockBalance>
{
    public void Configure(EntityTypeBuilder<StockBalance> e)
    {
        e.ToTable("StockBalances", "inv");
        e.Property(x => x.RowVersion).IsRowVersion();   // 2 đơn cùng trừ 1 SKU một lúc: người sau nhận 409, không âm kho
    }
}

internal sealed class SalesOrderConfiguration : IEntityTypeConfiguration<SalesOrder>
{
    public void Configure(EntityTypeBuilder<SalesOrder> e)
    {
        e.ToTable("SalesOrders", "sales");
        e.Property(x => x.DocNo).HasMaxLength(30).IsUnicode(false);
        e.Ignore(x => x.AmountDue);
        e.Ignore(x => x.IsEditable);
        e.Ignore(x => x.StockWasIssued);
        e.HasMany(x => x.Lines).WithOne().HasForeignKey(x => x.SalesOrderId);
    }
}

internal sealed class SalesOrderLineConfiguration : IEntityTypeConfiguration<SalesOrderLine>
{
    public void Configure(EntityTypeBuilder<SalesOrderLine> e) => e.ToTable("SalesOrderLines", "sales");
}

internal sealed class PurchaseOrderConfiguration : IEntityTypeConfiguration<PurchaseOrder>
{
    public void Configure(EntityTypeBuilder<PurchaseOrder> e)
    {
        e.ToTable("PurchaseOrders", "pur");
        e.Property(x => x.DocNo).HasMaxLength(30).IsUnicode(false);
        e.Ignore(x => x.AmountDue);
        e.HasMany(x => x.Lines).WithOne().HasForeignKey(x => x.PurchaseOrderId);
    }
}

internal sealed class PurchaseOrderLineConfiguration : IEntityTypeConfiguration<PurchaseOrderLine>
{
    public void Configure(EntityTypeBuilder<PurchaseOrderLine> e) => e.ToTable("PurchaseOrderLines", "pur");
}
