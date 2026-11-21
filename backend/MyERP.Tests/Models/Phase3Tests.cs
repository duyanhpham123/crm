using MyERP.Api.Models.Entities.Hr;
using MyERP.Api.Models.Entities.Marketing;

namespace MyERP.Tests.Models;

public class PayrollTests
{
    [Theory]
    [InlineData(0, 0)]
    [InlineData(5_000_000, 250_000)]                 // 5tr x 5%
    [InlineData(10_000_000, 750_000)]                // 250k + 5tr x 10%
    [InlineData(20_000_000, 2_350_000)]              // 750k + 8tr x 15% + 2tr x 20%
    public void Progressive_income_tax(decimal taxable, decimal expected) => Assert.Equal(expected, PayrollRules.PersonalIncomeTax(taxable));

    private static PayrollPeriod Period() => PayrollPeriod.Create(1, 2026, 11, 26, DateTime.UtcNow).Value;

    [Fact]
    public void Full_month_low_salary_no_tax()
    {
        var p = Period();
        var s = p.Upsert(5, 9, new PayslipInput(8_000_000, 8_000_000, 1_000_000, 26, 26, 0, 0, 0, 0, 0, 0));
        Assert.Equal(8_000_000, s.BaseSalary);
        Assert.Equal(9_000_000, s.GrossIncome);
        Assert.Equal(840_000, s.SocialInsurance + s.HealthInsurance + s.UnemploymentInsurance);   // 10,5%
        Assert.Equal(0, s.PersonalIncomeTax);
        Assert.Equal(8_160_000, s.NetPay);
        Assert.Equal(1_720_000, s.EmployerInsurance);                                             // 21,5%
    }

    [Fact]
    public void Prorated_by_work_days_with_overtime_bonus_and_advance()
    {
        var p = Period();
        var s = p.Upsert(5, 9, new PayslipInput(26_000_000, 10_000_000, 0, 26, 20, 2, 8, 0, 500_000, 1_000_000, 0));
        Assert.Equal(22_000_000, s.BaseSalary);                    // 26tr x 22/26
        Assert.Equal(1_500_000, s.OvertimePay);                    // 8h x 125.000 x 1,5
        Assert.Equal(24_000_000, s.GrossIncome);
        // Chịu thuế = 24tr - 500k (phần tăng ca được miễn) - 1,05tr BH - 15,5tr = 6,95tr -> 250k + 1,95tr x 10%
        Assert.Equal(6_950_000, s.TaxableIncome);
        Assert.Equal(445_000, s.PersonalIncomeTax);
        Assert.Equal(24_000_000 - 1_050_000 - 445_000 - 1_000_000, s.NetPay);
    }

    [Fact]
    public void Dependents_reduce_tax_and_period_flow()
    {
        var p = Period();
        var s = p.Upsert(5, 9, new PayslipInput(30_000_000, 30_000_000, 0, 26, 26, 0, 0, 2, 0, 0, 0));
        // 30tr - 3,15tr BH - 15,5tr bản thân - 2 x 6,2tr người phụ thuộc < 0 -> không chịu thuế
        Assert.Equal(0, s.TaxableIncome);
        Assert.Equal(0, s.PersonalIncomeTax);
        Assert.Equal(30_000_000 - 3_150_000, s.NetPay);
        Assert.True(p.MarkPaid(DateTime.UtcNow).IsFailure);       // chưa duyệt
        Assert.True(p.Approve(1, DateTime.UtcNow).IsSuccess);
        Assert.False(p.IsEditable);
        Assert.True(p.MarkPaid(DateTime.UtcNow).IsSuccess);
        Assert.True(p.Reopen().IsFailure);                         // đã chi thì không mở lại
    }
}

public class LeaveAndAttendanceTests
{
    [Fact]
    public void Leave_days_skip_sunday_and_half_day()
    {
        // 20/11/2026 thứ Sáu -> 23/11 thứ Hai: Sáu, Bảy, Hai = 3 ngày (bỏ CN 22/11)
        Assert.Equal(3, LeaveRequest.CountDays(new DateOnly(2026, 11, 20), new DateOnly(2026, 11, 23), false));
        Assert.Equal(0.5m, LeaveRequest.CountDays(new DateOnly(2026, 11, 20), new DateOnly(2026, 11, 20), true));
        Assert.True(LeaveRequest.Create(1, 1, new DateOnly(2026, 11, 22), new DateOnly(2026, 11, 22), false, null, 1, DateTime.UtcNow).IsFailure);
    }

    [Fact]
    public void Leave_approve_once()
    {
        var l = LeaveRequest.Create(1, 1, new DateOnly(2026, 11, 20), new DateOnly(2026, 11, 21), false, "Về quê", 1, DateTime.UtcNow).Value;
        Assert.Equal(2, l.WorkingDates().Count());
        Assert.True(l.Approve(2, DateTime.UtcNow).IsSuccess);
        Assert.True(l.Reject(2, "x", DateTime.UtcNow).IsFailure);
    }

    [Fact]
    public void Check_in_late_and_check_out_with_overtime()
    {
        var a = Attendance.Create(1, new DateOnly(2026, 11, 20), 1);
        Assert.True(a.Check(false, new DateTime(2026, 11, 20, 17, 0, 0), new TimeOnly(8, 0), new TimeOnly(17, 0), 60).IsFailure);
        Assert.True(a.Check(true, new DateTime(2026, 11, 20, 8, 15, 0), new TimeOnly(8, 0), new TimeOnly(17, 0), 60).IsSuccess);
        Assert.Equal(15, a.LateMinutes);
        Assert.True(a.Check(true, new DateTime(2026, 11, 20, 8, 20, 0), new TimeOnly(8, 0), new TimeOnly(17, 0), 60).IsFailure);
        Assert.True(a.Check(false, new DateTime(2026, 11, 20, 19, 15, 0), new TimeOnly(8, 0), new TimeOnly(17, 0), 60).IsSuccess);
        Assert.Equal(8, a.WorkHours);                              // 11h - 1h nghỉ trưa = 10h -> 8h + 2h tăng ca
        Assert.Equal(2, a.OvertimeHours);
        Assert.Equal(1, a.WorkDays);
    }

    [Fact]
    public void Half_day_counts_half()
    {
        var a = Attendance.Create(1, new DateOnly(2026, 11, 20), 1);
        a.Set("present", 4, 0, null);
        Assert.Equal(0.5m, a.WorkDays);
        a.Set("absent", 8, 0, null);
        Assert.Equal(0, a.WorkDays);
        Assert.Equal(0, a.WorkHours);
    }
}

public class PromotionTests
{
    private static readonly DateTime Now = new(2026, 11, 20, 10, 0, 0);

    private static Promotion Promo(string type, decimal value, decimal? max = null, decimal min = 0, int? limit = null, string? channels = null)
        => Promotion.Create(1, "sale-10", new PromotionInfo("Giảm giá", type, value, max, min, Now.AddDays(-1), Now.AddDays(5), limit, channels, null, true), Now).Value;

    [Fact]
    public void Percent_with_cap_and_code_upper()
    {
        var p = Promo("percent", 10, max: 50_000);
        Assert.Equal("SALE-10", p.Code);
        Assert.Equal(30_000, p.DiscountFor(300_000, 0, "direct", Now).Value);
        Assert.Equal(50_000, p.DiscountFor(900_000, 0, "direct", Now).Value);
    }

    [Fact]
    public void Free_ship_fixed_and_conditions()
    {
        Assert.Equal(30_000, Promo("free_ship", 0).DiscountFor(200_000, 30_000, "shopee", Now).Value);
        Assert.Equal(100_000, Promo("fixed", 150_000).DiscountFor(100_000, 0, "direct", Now).Value);   // không giảm quá tiền hàng
        Assert.Equal("promotion.min_order", Promo("fixed", 50_000, min: 500_000).DiscountFor(300_000, 0, "direct", Now).Error!.Code);
        Assert.Equal("promotion.channel", Promo("fixed", 50_000, channels: "website,facebook").DiscountFor(300_000, 0, "direct", Now).Error!.Code);
        Assert.Equal("promotion.expired", Promo("fixed", 50_000).DiscountFor(300_000, 0, "direct", Now.AddDays(10)).Error!.Code);
        var limited = Promo("fixed", 50_000, limit: 1);
        limited.Use();
        Assert.Equal("promotion.used_up", limited.DiscountFor(300_000, 0, "direct", Now).Error!.Code);
    }

    [Fact]
    public void Invalid_code_rejected()
        => Assert.True(Promotion.Create(1, "giảm giá", new PromotionInfo("x", "fixed", 1000, null, 0, Now, Now.AddDays(1), null, null, null, true), Now).IsFailure);
}

public class CampaignTests
{
    [Fact]
    public void Daily_stats_sum_actual_cost()
    {
        var c = Campaign.Create(1, "CD2026-001", 1, new CampaignInfo("Sale 11.11", "facebook", new DateOnly(2026, 11, 1), null, 10_000_000, 100, null, "running", null)).Value;
        Assert.True(c.SetDailyStat(new DateOnly(2026, 11, 2), 10_000, 300, 500_000, 12).IsSuccess);
        Assert.True(c.SetDailyStat(new DateOnly(2026, 11, 3), 8_000, 200, 400_000, 8).IsSuccess);
        Assert.True(c.SetDailyStat(new DateOnly(2026, 11, 2), 12_000, 350, 600_000, 15).IsSuccess);   // sửa lại ngày 2
        Assert.Equal(1_000_000, c.ActualCost);
        Assert.True(c.SetDailyStat(new DateOnly(2026, 10, 30), 1, 1, 1, 1).IsFailure);              // trước ngày bắt đầu
    }
}
