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

internal sealed class OpportunityConfiguration : IEntityTypeConfiguration<Opportunity>
{
    public void Configure(EntityTypeBuilder<Opportunity> e)
    {
        e.ToTable("Opportunities", "crm");
        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false);
        e.Property(x => x.Name).HasMaxLength(255);
        e.Property(x => x.Status).HasMaxLength(5).IsUnicode(false);
        e.Property(x => x.ExpectedRevenue).HasPrecision(18, 2);
        e.Property(x => x.Probability).HasPrecision(5, 2);
        e.Ignore(x => x.WeightedRevenue);   // cột tính toán trong DB, tính lại ở C#
        e.HasOne(x => x.Stage).WithMany().HasForeignKey(x => x.StageId);
    }
}

internal sealed class PipelineConfiguration : IEntityTypeConfiguration<Pipeline>
{
    public void Configure(EntityTypeBuilder<Pipeline> e)
    {
        e.ToTable("Pipelines", "crm");
        e.HasMany(x => x.Stages).WithOne().HasForeignKey(x => x.PipelineId);
    }
}

internal sealed class StageConfiguration : IEntityTypeConfiguration<Stage>
{
    public void Configure(EntityTypeBuilder<Stage> e)
    {
        e.ToTable("Stages", "crm");
        e.Property(x => x.Probability).HasPrecision(5, 2);
    }
}

internal sealed class LostReasonConfiguration : IEntityTypeConfiguration<LostReason>
{
    public void Configure(EntityTypeBuilder<LostReason> e) => e.ToTable("LostReasons", "crm");
}

internal sealed class OpportunityStageHistoryConfiguration : IEntityTypeConfiguration<OpportunityStageHistory>
{
    public void Configure(EntityTypeBuilder<OpportunityStageHistory> e) => e.ToTable("OpportunityStageHistory", "crm");
}
