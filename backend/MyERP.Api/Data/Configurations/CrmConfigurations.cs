using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MyERP.Api.Models.Entities.Crm;

namespace MyERP.Api.Data.Configurations;

// Map entity vào bảng schema "crm".

internal sealed class LeadConfiguration : IEntityTypeConfiguration<Lead>
{
    public void Configure(EntityTypeBuilder<Lead> e)
    {
        e.ToTable("Leads", "crm");
        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false);
        e.Property(x => x.FullName).HasMaxLength(150);
        e.Property(x => x.Phone).HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.Email).HasMaxLength(255).IsUnicode(false);
        e.Property(x => x.Status).HasMaxLength(12).IsUnicode(false);
        e.Property(x => x.EstimatedValue).HasPrecision(18, 2);
        e.HasOne(x => x.Source).WithMany().HasForeignKey(x => x.SourceId);
    }
}

internal sealed class LeadSourceConfiguration : IEntityTypeConfiguration<LeadSource>
{
    public void Configure(EntityTypeBuilder<LeadSource> e) => e.ToTable("LeadSources", "crm");
}
