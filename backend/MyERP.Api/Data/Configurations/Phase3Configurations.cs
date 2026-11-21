using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Models.Entities.Hr;
using MyERP.Api.Models.Entities.Marketing;

namespace MyERP.Api.Data.Configurations;

// Map entity Nhân sự / Marketing / Cài đặt vào các bảng hr, mkt, sales.Promotions, core.

internal sealed class PositionConfiguration : IEntityTypeConfiguration<Position>
{
    public void Configure(EntityTypeBuilder<Position> e) => e.ToTable("Positions", "hr");
}

internal sealed class EmployeeConfiguration : IEntityTypeConfiguration<Employee>
{
    public void Configure(EntityTypeBuilder<Employee> e)
    {
        e.ToTable("Employees", "hr");
        e.Property(x => x.Code).HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.Gender).HasColumnType("char(1)");
        e.Ignore(x => x.IsWorking);
    }
}

internal sealed class ContractConfiguration : IEntityTypeConfiguration<Contract>
{
    public void Configure(EntityTypeBuilder<Contract> e)
    {
        e.ToTable("Contracts", "hr");
        e.Ignore(x => x.TotalAllowance);
        e.HasMany(x => x.Allowances).WithOne().HasForeignKey(x => x.ContractId);
    }
}

internal sealed class ContractAllowanceConfiguration : IEntityTypeConfiguration<ContractAllowance>
{
    public void Configure(EntityTypeBuilder<ContractAllowance> e) => e.ToTable("ContractAllowances", "hr");
}

internal sealed class AttendanceConfiguration : IEntityTypeConfiguration<Attendance>
{
    public void Configure(EntityTypeBuilder<Attendance> e)
    {
        e.ToTable("Attendances", "hr");
        e.Ignore(x => x.WorkDays);
    }
}

internal sealed class WorkShiftConfiguration : IEntityTypeConfiguration<WorkShift>
{
    public void Configure(EntityTypeBuilder<WorkShift> e) => e.ToTable("WorkShifts", "hr");
}

internal sealed class LeaveTypeConfiguration : IEntityTypeConfiguration<LeaveType>
{
    public void Configure(EntityTypeBuilder<LeaveType> e) => e.ToTable("LeaveTypes", "hr");
}

internal sealed class LeaveBalanceConfiguration : IEntityTypeConfiguration<LeaveBalance>
{
    public void Configure(EntityTypeBuilder<LeaveBalance> e)
    {
        e.ToTable("LeaveBalances", "hr");
        e.HasKey(x => new { x.EmployeeId, x.LeaveTypeId, x.LeaveYear });
        e.Ignore(x => x.Remaining);
    }
}

internal sealed class LeaveRequestConfiguration : IEntityTypeConfiguration<LeaveRequest>
{
    public void Configure(EntityTypeBuilder<LeaveRequest> e) => e.ToTable("LeaveRequests", "hr");
}

internal sealed class PayrollPeriodConfiguration : IEntityTypeConfiguration<PayrollPeriod>
{
    public void Configure(EntityTypeBuilder<PayrollPeriod> e)
    {
        e.ToTable("PayrollPeriods", "hr");
        e.Ignore(x => x.IsEditable);
        e.HasMany(x => x.Payslips).WithOne().HasForeignKey(x => x.PayrollPeriodId);
    }
}

internal sealed class PayslipConfiguration : IEntityTypeConfiguration<Payslip>
{
    public void Configure(EntityTypeBuilder<Payslip> e)
    {
        e.ToTable("Payslips", "hr");
        e.Ignore(x => x.ContractSalary);
    }
}

internal sealed class CampaignConfiguration : IEntityTypeConfiguration<Campaign>
{
    public void Configure(EntityTypeBuilder<Campaign> e)
    {
        e.ToTable("Campaigns", "mkt");
        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false);
        e.HasMany(x => x.Stats).WithOne().HasForeignKey(x => x.CampaignId);
    }
}

internal sealed class CampaignDailyStatConfiguration : IEntityTypeConfiguration<CampaignDailyStat>
{
    public void Configure(EntityTypeBuilder<CampaignDailyStat> e)
    {
        e.ToTable("CampaignDailyStats", "mkt");
        e.HasKey(x => new { x.CampaignId, x.StatDate });
    }
}

internal sealed class PromotionConfiguration : IEntityTypeConfiguration<Promotion>
{
    public void Configure(EntityTypeBuilder<Promotion> e)
    {
        e.ToTable("Promotions", "sales");
        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false);
    }
}

internal sealed class OrderPromotionConfiguration : IEntityTypeConfiguration<OrderPromotion>
{
    public void Configure(EntityTypeBuilder<OrderPromotion> e)
    {
        e.ToTable("OrderPromotions", "sales");
        e.HasKey(x => new { x.SalesOrderId, x.PromotionId });
    }
}

internal sealed class SequenceConfiguration : IEntityTypeConfiguration<Sequence>
{
    public void Configure(EntityTypeBuilder<Sequence> e) => e.ToTable("Sequences", "core");
}

internal sealed class SettingConfiguration : IEntityTypeConfiguration<Setting>
{
    public void Configure(EntityTypeBuilder<Setting> e) => e.ToTable("Settings", "core");
}
