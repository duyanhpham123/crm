using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MyERP.Api.Models.Entities.Accounting;
using MyERP.Api.Models.Entities.Logistics;
using MyERP.Api.Models.Entities.Sales;
using MyERP.Api.Models.Entities.Support;

namespace MyERP.Api.Data.Configurations;

// Map entity Báo giá / Trả hàng / Vận chuyển / Kế toán / CSKH vào các bảng sales, lgs, acc, cs.

internal sealed class QuotationConfiguration : IEntityTypeConfiguration<Quotation>
{
    public void Configure(EntityTypeBuilder<Quotation> e)
    {
        e.ToTable("Quotations", "sales");
        e.Property(x => x.DocNo).HasMaxLength(30).IsUnicode(false);
        e.Ignore(x => x.IsEditable);
        e.HasMany(x => x.Lines).WithOne().HasForeignKey(x => x.QuotationId);
    }
}

internal sealed class QuotationLineConfiguration : IEntityTypeConfiguration<QuotationLine>
{
    public void Configure(EntityTypeBuilder<QuotationLine> e) => e.ToTable("QuotationLines", "sales");
}

internal sealed class SalesReturnConfiguration : IEntityTypeConfiguration<SalesReturn>
{
    public void Configure(EntityTypeBuilder<SalesReturn> e)
    {
        e.ToTable("SalesReturns", "sales");
        e.Property(x => x.DocNo).HasMaxLength(30).IsUnicode(false);
        e.HasMany(x => x.Lines).WithOne().HasForeignKey(x => x.SalesReturnId);
    }
}

internal sealed class SalesReturnLineConfiguration : IEntityTypeConfiguration<SalesReturnLine>
{
    public void Configure(EntityTypeBuilder<SalesReturnLine> e) => e.ToTable("SalesReturnLines", "sales");
}

internal sealed class CarrierConfiguration : IEntityTypeConfiguration<Carrier>
{
    public void Configure(EntityTypeBuilder<Carrier> e) => e.ToTable("Carriers", "lgs");
}

internal sealed class ShipmentConfiguration : IEntityTypeConfiguration<Shipment>
{
    public void Configure(EntityTypeBuilder<Shipment> e)
    {
        e.ToTable("Shipments", "lgs");
        e.Property(x => x.DocNo).HasMaxLength(30).IsUnicode(false);
        e.Property(x => x.TrackingNo).HasMaxLength(50).IsUnicode(false);
        e.HasMany(x => x.Events).WithOne().HasForeignKey(x => x.ShipmentId);
    }
}

internal sealed class ShipmentEventConfiguration : IEntityTypeConfiguration<ShipmentEvent>
{
    public void Configure(EntityTypeBuilder<ShipmentEvent> e) => e.ToTable("ShipmentTrackingEvents", "lgs");
}

internal sealed class CashVoucherConfiguration : IEntityTypeConfiguration<CashVoucher>
{
    public void Configure(EntityTypeBuilder<CashVoucher> e)
    {
        e.ToTable("Payments", "acc");
        e.Property(x => x.DocNo).HasMaxLength(30).IsUnicode(false);
        e.Ignore(x => x.IsCash);
        e.Ignore(x => x.SignedAmount);
    }
}

internal sealed class BankAccountConfiguration : IEntityTypeConfiguration<BankAccount>
{
    public void Configure(EntityTypeBuilder<BankAccount> e) => e.ToTable("BankAccounts", "acc");
}

internal sealed class LedgerAccountConfiguration : IEntityTypeConfiguration<LedgerAccount>
{
    public void Configure(EntityTypeBuilder<LedgerAccount> e) => e.ToTable("Accounts", "acc");
}

internal sealed class TicketConfiguration : IEntityTypeConfiguration<Ticket>
{
    public void Configure(EntityTypeBuilder<Ticket> e)
    {
        e.ToTable("Tickets", "cs");
        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false);
        e.HasMany(x => x.Messages).WithOne().HasForeignKey(x => x.TicketId);
    }
}

internal sealed class TicketMessageConfiguration : IEntityTypeConfiguration<TicketMessage>
{
    public void Configure(EntityTypeBuilder<TicketMessage> e) => e.ToTable("TicketMessages", "cs");
}

internal sealed class TicketCategoryConfiguration : IEntityTypeConfiguration<TicketCategory>
{
    public void Configure(EntityTypeBuilder<TicketCategory> e) => e.ToTable("TicketCategories", "cs");
}

internal sealed class SlaPolicyConfiguration : IEntityTypeConfiguration<SlaPolicy>
{
    public void Configure(EntityTypeBuilder<SlaPolicy> e) => e.ToTable("SlaPolicies", "cs");
}
