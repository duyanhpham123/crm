using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Accounting;
using MyERP.Api.Models.Entities.Hr;
using MyERP.Api.Services.Accounting;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Hr;

public interface IPayrollService
{
    Task<IReadOnlyList<PayrollListItem>> ListAsync(CancellationToken ct);
    Task<Result<PayrollDetail>> GetAsync(long id, CancellationToken ct);
    Task<Result<PayrollDetail>> CreateAsync(CreatePayrollRequest request, CancellationToken ct);
    Task<Result<PayrollDetail>> RecalculateAsync(long id, decimal? standardDays, CancellationToken ct);
    Task<Result<PayrollDetail>> UpdatePayslipAsync(long id, long payslipId, UpdatePayslipRequest request, CancellationToken ct);
    Task<Result<PayrollDetail>> ApproveAsync(long id, CancellationToken ct);
    Task<Result<PayrollDetail>> ReopenAsync(long id, CancellationToken ct);
    Task<Result<PayrollDetail>> PayAsync(long id, PayPayrollRequest request, CancellationToken ct);
}

/// <summary>
/// Bảng lương tháng: lấy ngày công / tăng ca từ chấm công, nghỉ phép có lương từ đơn đã duyệt, lương từ hợp đồng.
/// Duyệt -> chi lương = 1 phiếu chi (Kế toán, loại "Lương nhân viên") bằng tổng thực lĩnh.
/// </summary>
public sealed class PayrollService(AppDbContext db, ICurrentUser currentUser, ICashService cash, TimeProvider clock) : IPayrollService
{
    private static string VoucherReason(int month, int year) => $"Chi lương tháng {month}/{year}";

    public async Task<IReadOnlyList<PayrollListItem>> ListAsync(CancellationToken ct)
        => await db.PayrollPeriods.AsNoTracking().OrderByDescending(p => p.PeriodYear).ThenByDescending(p => p.PeriodMonth)
            .Select(p => new PayrollListItem(p.Id, p.PeriodYear, p.PeriodMonth, p.StandardDays, p.Status, p.Payslips.Count(),
                p.Payslips.Sum(s => s.GrossIncome), p.Payslips.Sum(s => s.NetPay),
                p.Payslips.Sum(s => s.SocialInsurance + s.HealthInsurance + s.UnemploymentInsurance), p.Payslips.Sum(s => s.PersonalIncomeTax),
                p.Payslips.Sum(s => s.EmployerInsurance)))
            .ToListAsync(ct);

    public async Task<Result<PayrollDetail>> GetAsync(long id, CancellationToken ct)
    {
        var p = await db.PayrollPeriods.Include(x => x.Payslips).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return p is null ? Error.NotFound("bảng lương") : await ToDetailAsync(p, ct);
    }

    public async Task<Result<PayrollDetail>> CreateAsync(CreatePayrollRequest r, CancellationToken ct)
    {
        if (await db.PayrollPeriods.AnyAsync(p => p.PeriodYear == r.Year && p.PeriodMonth == r.Month, ct))
            return Error.Conflict("payroll.exists", $"Đã có bảng lương tháng {r.Month}/{r.Year}.");
        var created = PayrollPeriod.Create(currentUser.RequireCompanyId(), r.Year, r.Month, r.StandardDays, clock.GetUtcNow().UtcDateTime);
        if (created.IsFailure) return created.Error!;
        db.PayrollPeriods.Add(created.Value);
        await CalculateAllAsync(created.Value, ct);
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(created.Value, ct);
    }

    public async Task<Result<PayrollDetail>> RecalculateAsync(long id, decimal? standardDays, CancellationToken ct)
    {
        var p = await db.PayrollPeriods.Include(x => x.Payslips).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (p is null) return Error.NotFound("bảng lương");
        if (!p.IsEditable) return Error.Conflict("payroll.locked", "Bảng lương đã duyệt. Mở lại để tính lại.");
        if (standardDays is { } sd) { var s = p.SetStandardDays(sd); if (s.IsFailure) return s.Error!; }
        await CalculateAllAsync(p, ct);
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(p, ct);
    }

    public async Task<Result<PayrollDetail>> UpdatePayslipAsync(long id, long payslipId, UpdatePayslipRequest r, CancellationToken ct)
    {
        if (r.Bonus < 0 || r.Advance < 0 || r.OtherDeductions < 0) return Error.Validation("payslip.amount", "Số tiền không hợp lệ.");
        var p = await db.PayrollPeriods.Include(x => x.Payslips).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (p is null) return Error.NotFound("bảng lương");
        if (!p.IsEditable) return Error.Conflict("payroll.locked", "Bảng lương đã duyệt, không sửa được.");
        var slip = p.Payslips.FirstOrDefault(s => s.Id == payslipId);
        if (slip is null) return Error.NotFound("phiếu lương");
        var input = await BuildInputsAsync(p, [slip.EmployeeId], ct);
        if (input.TryGetValue(slip.EmployeeId, out var inp))
            p.Upsert(slip.EmployeeId, inp.ContractId, inp.Input with { Bonus = r.Bonus, Advance = r.Advance, OtherDeductions = r.OtherDeductions });
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(p, ct);
    }

    public async Task<Result<PayrollDetail>> ApproveAsync(long id, CancellationToken ct) => await ChangeAsync(id, p => p.Approve(currentUser.RequireUserId(), clock.GetUtcNow().UtcDateTime), ct);

    public async Task<Result<PayrollDetail>> ReopenAsync(long id, CancellationToken ct) => await ChangeAsync(id, p => p.Reopen(), ct);

    /// <summary>Chi lương: 1 phiếu chi tổng thực lĩnh (chuyển khoản), phiếu lương chuyển "đã trả".</summary>
    public async Task<Result<PayrollDetail>> PayAsync(long id, PayPayrollRequest r, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            var p = await db.PayrollPeriods.Include(x => x.Payslips).FirstOrDefaultAsync(x => x.Id == id, ct);
            if (p is null) return (Result<PayrollDetail>)Error.NotFound("bảng lương");
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var paid = p.MarkPaid(clock.GetUtcNow().UtcDateTime);
            if (paid.IsFailure) return (Result<PayrollDetail>)paid.Error!;
            var total = p.Payslips.Sum(s => s.NetPay);
            if (total > 0)
            {
                var date = r.Date ?? DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime.AddHours(7));
                var v = await cash.AddVoucherAsync(new VoucherSpec(VoucherTypes.Payment, "salary", "bank_transfer", r.BankAccountId, null, date, total,
                    $"{VoucherReason(p.PeriodMonth, p.PeriodYear)} ({p.Payslips.Count} nhân viên)", "Nhân viên"), ct);
                if (v.IsFailure) return (Result<PayrollDetail>)v.Error!;
            }
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<PayrollDetail>)await ToDetailAsync(p, ct);
        });
    }

    private async Task<Result<PayrollDetail>> ChangeAsync(long id, Func<PayrollPeriod, Result> change, CancellationToken ct)
    {
        var p = await db.PayrollPeriods.Include(x => x.Payslips).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (p is null) return Error.NotFound("bảng lương");
        var r = change(p);
        if (r.IsFailure) return r.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(p, ct);
    }

    private async Task CalculateAllAsync(PayrollPeriod p, CancellationToken ct)
    {
        var first = new DateOnly(p.PeriodYear, p.PeriodMonth, 1);
        var last = first.AddMonths(1).AddDays(-1);
        var empIds = await db.Employees.Where(e => (e.HireDate == null || e.HireDate <= last)
                && (e.EmploymentStatus == "probation" || e.EmploymentStatus == "official" || (e.TerminationDate != null && e.TerminationDate >= first)))
            .Select(e => e.Id).ToListAsync(ct);
        var inputs = await BuildInputsAsync(p, empIds, ct);
        foreach (var (empId, inp) in inputs)
        {
            var existing = p.Payslips.FirstOrDefault(s => s.EmployeeId == empId);
            p.Upsert(empId, inp.ContractId, inp.Input with
            {
                Bonus = existing?.Bonus ?? 0, Advance = existing?.Advance ?? 0, OtherDeductions = existing?.OtherDeductions ?? 0,
            });
        }
        p.MarkCalculated();
    }

    /// <summary>Gom dữ liệu tính lương: hợp đồng còn hiệu lực cuối tháng, ngày công, tăng ca, nghỉ phép có lương.</summary>
    private async Task<Dictionary<long, (long? ContractId, PayslipInput Input)>> BuildInputsAsync(PayrollPeriod p, IReadOnlyList<long> empIds, CancellationToken ct)
    {
        var first = new DateOnly(p.PeriodYear, p.PeriodMonth, 1);
        var last = first.AddMonths(1).AddDays(-1);
        var emps = await db.Employees.Where(e => empIds.Contains(e.Id)).ToDictionaryAsync(e => e.Id, ct);
        var contracts = (await db.Contracts.AsNoTracking().Include(c => c.Allowances).Where(c => empIds.Contains(c.EmployeeId) && c.StartDate <= last).ToListAsync(ct))
            .GroupBy(c => c.EmployeeId).ToDictionary(g => g.Key, g => g.OrderByDescending(c => c.Status == "active").ThenByDescending(c => c.StartDate).First());
        var att = await db.Attendances.AsNoTracking().Where(a => empIds.Contains(a.EmployeeId) && a.WorkDate >= first && a.WorkDate <= last).ToListAsync(ct);
        var paidTypes = await db.LeaveTypes.Where(t => t.IsPaid).Select(t => t.Id).ToListAsync(ct);
        var leaves = await db.LeaveRequests.AsNoTracking().Where(l => empIds.Contains(l.EmployeeId) && l.Status == "approved" && paidTypes.Contains(l.LeaveTypeId)
            && l.FromDate <= last.ToDateTime(new TimeOnly(23, 59)) && l.ToDate >= first.ToDateTime(TimeOnly.MinValue)).ToListAsync(ct);

        var result = new Dictionary<long, (long?, PayslipInput)>();
        foreach (var id in empIds)
        {
            if (!contracts.TryGetValue(id, out var c)) continue;          // chưa có hợp đồng / lương thì bỏ qua
            var mine = att.Where(a => a.EmployeeId == id).ToList();
            var paidLeave = leaves.Where(l => l.EmployeeId == id)
                .Sum(l => l.Days % 1 != 0 ? l.Days : l.WorkingDates().Count(d => d >= first && d <= last));
            result[id] = (c.Id, new PayslipInput(c.BaseSalary, c.InsuranceSalary, c.TotalAllowance, p.StandardDays,
                mine.Where(a => a.Status != "leave").Sum(a => a.WorkDays), paidLeave, mine.Sum(a => a.OvertimeHours), emps[id].Dependents, 0, 0, 0));
        }
        return result;
    }

    private async Task<PayrollDetail> ToDetailAsync(PayrollPeriod p, CancellationToken ct)
    {
        var empIds = p.Payslips.Select(s => s.EmployeeId).ToList();
        var emps = await db.Employees.IgnoreQueryFilters().Where(e => empIds.Contains(e.Id))
            .Select(e => new { e.Id, e.Code, e.FullName, e.BankAccountNo, Dept = db.Departments.Where(d => d.Id == e.DepartmentId).Select(d => d.Name).FirstOrDefault() })
            .ToDictionaryAsync(e => e.Id, ct);
        var contractIds = p.Payslips.Where(s => s.ContractId != null).Select(s => s.ContractId!.Value).ToList();
        var salaries = await db.Contracts.Where(c => contractIds.Contains(c.Id)).ToDictionaryAsync(c => c.Id, c => c.BaseSalary, ct);
        var slips = p.Payslips.OrderBy(s => emps.GetValueOrDefault(s.EmployeeId)?.Code).Select(s => new PayslipDto(s.Id, s.EmployeeId,
            emps.GetValueOrDefault(s.EmployeeId)?.Code ?? "", emps.GetValueOrDefault(s.EmployeeId)?.FullName ?? "", emps.GetValueOrDefault(s.EmployeeId)?.Dept,
            s.ContractId is { } cid ? salaries.GetValueOrDefault(cid) : 0, s.ActualDays, s.PaidLeaveDays, s.OvertimeHours, s.BaseSalary, s.TotalAllowance,
            s.OvertimePay, s.Bonus, s.GrossIncome, s.SocialInsurance + s.HealthInsurance + s.UnemploymentInsurance, s.TaxableIncome, s.PersonalIncomeTax,
            s.Advance, s.OtherDeductions, s.NetPay, s.EmployerInsurance, s.Status, emps.GetValueOrDefault(s.EmployeeId)?.BankAccountNo)).ToList();
        var reason = VoucherReason(p.PeriodMonth, p.PeriodYear);
        var voucher = p.Status == "paid"
            ? await db.CashVouchers.Where(v => v.Category == "salary" && v.Status == "posted" && v.Reason.StartsWith(reason)).OrderByDescending(v => v.Id).Select(v => v.DocNo).FirstOrDefaultAsync(ct)
            : null;
        return new PayrollDetail(p.Id, p.PeriodYear, p.PeriodMonth, p.StandardDays, p.Status, slips, slips.Sum(s => s.GrossIncome), slips.Sum(s => s.NetPay),
            slips.Sum(s => s.Insurance), slips.Sum(s => s.PersonalIncomeTax), slips.Sum(s => s.EmployerInsurance), voucher);
    }
}
