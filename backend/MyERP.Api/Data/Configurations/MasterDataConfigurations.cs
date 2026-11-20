using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MyERP.Api.Models.Entities.MasterData;

namespace MyERP.Api.Data.Configurations;

// Map entity vào bảng schema "md" (danh mục dùng chung).

internal sealed class PartnerConfiguration : IEntityTypeConfiguration<Partner>
{
    public void Configure(EntityTypeBuilder<Partner> e)
    {
        e.ToTable("Partners", "md");
        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false);
        e.Property(x => x.PartnerType).HasMaxLength(10).IsUnicode(false);
        e.Property(x => x.Name).HasMaxLength(255);
        e.Property(x => x.TaxCode).HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.Phone).HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.Email).HasMaxLength(255).IsUnicode(false);
        e.Property(x => x.Website).HasMaxLength(255).IsUnicode(false);
        e.HasMany(x => x.Contacts).WithOne().HasForeignKey(x => x.PartnerId);
        e.HasOne(x => x.CustomerGroup).WithMany().HasForeignKey(x => x.CustomerGroupId);
    }
}

internal sealed class PartnerContactConfiguration : IEntityTypeConfiguration<PartnerContact>
{
    public void Configure(EntityTypeBuilder<PartnerContact> e)
    {
        e.ToTable("PartnerContacts", "md");
        e.Property(x => x.Phone).HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.Email).HasMaxLength(255).IsUnicode(false);
    }
}

internal sealed class PartnerGroupConfiguration : IEntityTypeConfiguration<PartnerGroup>
{
    public void Configure(EntityTypeBuilder<PartnerGroup> e) => e.ToTable("PartnerGroups", "md");
}
