using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Hr;

/// <summary>
/// Quy tắc tính lương Việt Nam. Thay đổi theo luật thì sửa ở đây (một chỗ duy nhất).
/// LƯU Ý: kiểm tra lại mức giảm trừ gia cảnh / biểu thuế theo quy định hiện hành trước khi trả lương thật.
/// </summary>
public static class PayrollRules
{
    public const decimal PersonalDeduction = 15_500_000;   // giảm trừ bản thân / tháng (áp dụng từ kỳ tính thuế 2026)
    public const decimal DependentDeduction = 6_200_000;   // giảm trừ mỗi người phụ thuộc / tháng
    public const decimal SocialRate = 0.08m, HealthRate = 0.015m, UnemploymentRate = 0.01m;   // NLĐ đóng 10,5%
    public const decimal EmployerRate = 0.215m;            // DN đóng 21,5%
    public const decimal OvertimeMultiplier = 1.5m;        // tăng ca ngày thường 150%

    /// <summary>Biểu thuế lũy tiến từng phần theo tháng: (đến mức, thuế suất).</summary>
    public static readonly (decimal UpTo, decimal Rate)[] TaxBrackets =
    [
        (5_000_000, 0.05m), (10_000_000, 0.10m), (18_000_000, 0.15m), (32_000_000, 0.20m),
        (52_000_000, 0.25m), (80_000_000, 0.30m), (decimal.MaxValue, 0.35m),
    ];

    public static decimal PersonalIncomeTax(decimal taxable)
    {
        if (taxable <= 0) return 0;
        decimal tax = 0, lower = 0;
        foreach (var (upTo, rate) in TaxBrackets)
        {
            if (taxable <= lower) break;
            tax += (Math.Min(taxable, upTo) - lower) * rate;
            lower = upTo;
        }
        return Math.Round(tax, 0);
    }
}

public sealed record PayslipInput(decimal BaseSalary, decimal InsuranceSalary, decimal Allowance, decimal StandardDays,
    decimal ActualDays, decimal PaidLeaveDays, decimal OvertimeHours, byte Dependents, decimal Bonus, decimal Advance, decimal OtherDeductions);

/// <summary>hr.PayrollPeriods - kỳ lương tháng. Nháp / Đã tính -> Đã duyệt -> Đã chi (tạo phiếu chi lương).</summary>
public sealed class PayrollPeriod : ICompanyOwned
{
    private PayrollPeriod() { }
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public short PeriodYear { get; private set; }
    public byte PeriodMonth { get; private set; }
    public decimal StandardDays { get; private set; } = 26;
    public string Status { get; private set; } = "draft";
    public long? ApprovedBy { get; private set; }
    public DateTime? ApprovedAt { get; private set; }
    public DateTime CreatedAt { get; private set; }

    private readonly List<Payslip> _payslips = [];
    public IReadOnlyList<Payslip> Payslips => _payslips;

    public bool IsEditable => Status is "draft" or "calculated";

    public static Result<PayrollPeriod> Create(long companyId, int year, int month, decimal standardDays, DateTime now)
    {
        if (month is < 1 or > 12) return Error.Validation("payroll.month", "Tháng không hợp lệ.");
        if (standardDays is <= 0 or > 31) return Error.Validation("payroll.days", "Số công chuẩn không hợp lệ.");
        return new PayrollPeriod { CompanyId = companyId, PeriodYear = (short)year, PeriodMonth = (byte)month, StandardDays = standardDays, CreatedAt = now };
    }

    public Result SetStandardDays(decimal days)
    {
        if (!IsEditable) return Error.Conflict("payroll.locked", "Bảng lương đã duyệt, không sửa được.");
        if (days is <= 0 or > 31) return Error.Validation("payroll.days", "Số công chuẩn không hợp lệ.");
        StandardDays = days;
        return Result.Success();
    }

    public Payslip Upsert(long employeeId, long? contractId, PayslipInput input)
    {
        var p = _payslips.FirstOrDefault(x => x.EmployeeId == employeeId);
        if (p is null) { p = Payslip.Create(employeeId); _payslips.Add(p); }
        p.Calculate(contractId, input);
        return p;
    }

    public void MarkCalculated() { if (Status == "draft") Status = "calculated"; }

    public Result Approve(long userId, DateTime now)
    {
        if (!IsEditable) return Error.Conflict("payroll.approved", "Bảng lương đã duyệt.");
        if (_payslips.Count == 0) return Error.Validation("payroll.empty", "Chưa tính lương cho nhân viên nào.");
        Status = "approved"; ApprovedBy = userId; ApprovedAt = now;
        foreach (var p in _payslips) p.Confirm();
        return Result.Success();
    }

    public Result Reopen()
    {
        if (Status != "approved") return Error.Conflict("payroll.not_approved", "Chỉ mở lại được bảng lương đã duyệt, chưa chi.");
        Status = "calculated";
        foreach (var p in _payslips) p.Unconfirm();
        return Result.Success();
    }

    public Result MarkPaid(DateTime now)
    {
        if (Status != "approved") return Error.Conflict("payroll.not_approved", "Duyệt bảng lương trước khi chi.");
        Status = "paid";
        foreach (var p in _payslips) p.MarkPaid(now);
        return Result.Success();
    }
}

/// <summary>hr.Payslips - phiếu lương 1 nhân viên / 1 tháng.</summary>
public sealed class Payslip
{
    private Payslip() { }
    public long Id { get; private set; }
    public long PayrollPeriodId { get; private set; }
    public long EmployeeId { get; private set; }
    public long? ContractId { get; private set; }
    public decimal ActualDays { get; private set; }
    public decimal PaidLeaveDays { get; private set; }
    public decimal OvertimeHours { get; private set; }
    public decimal BaseSalary { get; private set; }
    public decimal TotalAllowance { get; private set; }
    public decimal OvertimePay { get; private set; }
    public decimal Bonus { get; private set; }
    public decimal GrossIncome { get; private set; }
    public decimal SocialInsurance { get; private set; }
    public decimal HealthInsurance { get; private set; }
    public decimal UnemploymentInsurance { get; private set; }
    public decimal TaxableIncome { get; private set; }
    public decimal PersonalIncomeTax { get; private set; }
    public decimal Advance { get; private set; }
    public decimal OtherDeductions { get; private set; }
    public decimal NetPay { get; private set; }
    public decimal EmployerInsurance { get; private set; }
    public string Status { get; private set; } = "draft";
    public DateTime? PaidAt { get; private set; }

    /// <summary>Lương theo hợp đồng (để hiển thị). BaseSalary trên phiếu là lương thực nhận theo ngày công.</summary>
    public decimal ContractSalary { get; private set; }

    internal static Payslip Create(long employeeId) => new() { EmployeeId = employeeId };

    /// <summary>
    /// Lương = lương HĐ × (công thực tế + nghỉ phép có lương) / công chuẩn; phụ cấp tính tương tự;
    /// tăng ca = giờ × lương giờ × 150%; BH NLĐ 10,5% lương đóng BH; thuế TNCN lũy tiến sau giảm trừ.
    /// </summary>
    internal void Calculate(long? contractId, PayslipInput i)
    {
        ContractId = contractId;
        ContractSalary = i.BaseSalary;
        ActualDays = i.ActualDays; PaidLeaveDays = i.PaidLeaveDays; OvertimeHours = i.OvertimeHours;
        Bonus = i.Bonus; Advance = i.Advance; OtherDeductions = i.OtherDeductions;
        var worked = Math.Min(i.ActualDays + i.PaidLeaveDays, i.StandardDays);
        var ratio = i.StandardDays == 0 ? 0 : worked / i.StandardDays;
        BaseSalary = Math.Round(i.BaseSalary * ratio, 0);
        TotalAllowance = Math.Round(i.Allowance * ratio, 0);
        var hourly = i.StandardDays == 0 ? 0 : i.BaseSalary / i.StandardDays / 8;
        OvertimePay = Math.Round(i.OvertimeHours * hourly * PayrollRules.OvertimeMultiplier, 0);
        GrossIncome = BaseSalary + TotalAllowance + OvertimePay + Bonus;

        var insured = worked > 0 ? i.InsuranceSalary : 0;
        SocialInsurance = Math.Round(insured * PayrollRules.SocialRate, 0);
        HealthInsurance = Math.Round(insured * PayrollRules.HealthRate, 0);
        UnemploymentInsurance = Math.Round(insured * PayrollRules.UnemploymentRate, 0);
        EmployerInsurance = Math.Round(insured * PayrollRules.EmployerRate, 0);
        var insurance = SocialInsurance + HealthInsurance + UnemploymentInsurance;

        // Phụ cấp ăn trưa / xăng xe (không chịu thuế) và phần tăng ca vượt lương thường được miễn thuế
        var overtimeExempt = Math.Round(OvertimePay * (PayrollRules.OvertimeMultiplier - 1) / PayrollRules.OvertimeMultiplier, 0);
        TaxableIncome = Math.Max(0, GrossIncome - TotalAllowance - overtimeExempt - insurance
            - PayrollRules.PersonalDeduction - PayrollRules.DependentDeduction * i.Dependents);
        PersonalIncomeTax = PayrollRules.PersonalIncomeTax(TaxableIncome);
        NetPay = GrossIncome - insurance - PersonalIncomeTax - Advance - OtherDeductions;
    }

    internal void Confirm() => Status = "confirmed";
    internal void Unconfirm() => Status = "draft";
    internal void MarkPaid(DateTime now) { Status = "paid"; PaidAt = now; }
}
