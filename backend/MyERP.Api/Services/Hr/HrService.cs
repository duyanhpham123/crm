using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Hr;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Hr;

public interface IHrService
{
    Task<HrLookups> GetLookupsAsync(CancellationToken ct);
    Task<EmployeePage> ListEmployeesAsync(string? search, long? departmentId, string? status, int page, int pageSize, CancellationToken ct);
    Task<Result<EmployeeDetail>> GetEmployeeAsync(long id, CancellationToken ct);
    Task<Result<EmployeeDetail>> CreateEmployeeAsync(SaveEmployeeRequest request, CancellationToken ct);
    Task<Result<EmployeeDetail>> UpdateEmployeeAsync(long id, SaveEmployeeRequest request, CancellationToken ct);
    Task<Result<OptionDto>> CreatePositionAsync(string name, CancellationToken ct);
    Task<AttendanceMonth> AttendanceAsync(int year, int month, long? departmentId, CancellationToken ct);
    Task<Result> SetAttendanceAsync(SetAttendanceRequest request, CancellationToken ct);
    Task<Result<int>> FillAttendanceAsync(FillAttendanceRequest request, CancellationToken ct);
    Task<Result<AttendanceCell>> CheckAsync(CheckRequest request, CancellationToken ct);
    Task<LeavePage> ListLeavesAsync(string? status, long? employeeId, int page, int pageSize, CancellationToken ct);
    Task<Result<LeaveRequestDto>> CreateLeaveAsync(CreateLeaveRequest request, CancellationToken ct);
    Task<Result<LeaveRequestDto>> ApproveLeaveAsync(long id, CancellationToken ct);
    Task<Result<LeaveRequestDto>> RejectLeaveAsync(long id, string reason, CancellationToken ct);
    Task<Result<LeaveRequestDto>> CancelLeaveAsync(long id, CancellationToken ct);
}

/// <summary>
/// Nhân sự: hồ sơ nhân viên (kèm hợp đồng / lương), chấm công tháng, check-in, đơn nghỉ phép có duyệt.
/// Duyệt nghỉ phép -> tự chấm công "nghỉ phép" các ngày đó và trừ quỹ phép năm.
/// </summary>
public sealed class HrService(AppDbContext db, ICurrentUser currentUser, IDocumentNumberService docNumbers, TimeProvider clock) : IHrService
{
    private DateTime LocalNow => clock.GetUtcNow().UtcDateTime.AddHours(7);
    private DateOnly Today => DateOnly.FromDateTime(LocalNow);

    public async Task<HrLookups> GetLookupsAsync(CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        return new HrLookups(
            await db.Departments.Where(d => d.IsActive).OrderBy(d => d.SortOrder).ThenBy(d => d.Name).Select(d => new OptionDto(d.Id, d.Name, d.Code)).ToListAsync(ct),
            await db.Positions.Where(p => p.IsActive).OrderBy(p => p.Name).Select(p => new OptionDto(p.Id, p.Name, p.Code)).ToListAsync(ct),
            await db.Users.Where(u => u.IsActive && db.UserCompanies.Any(c => c.UserId == u.Id && c.CompanyId == companyId))
                .OrderBy(u => u.FullName).Select(u => new OptionDto(u.Id, u.FullName, u.UserName)).ToListAsync(ct),
            await db.LeaveTypes.OrderBy(t => t.Id).Select(t => new LeaveTypeDto(t.Id, t.Name, t.IsPaid, t.DefaultDaysPerYear)).ToListAsync(ct),
            await db.Employees.Where(e => e.EmploymentStatus == "probation" || e.EmploymentStatus == "official")
                .OrderBy(e => e.FullName).Select(e => new OptionDto(e.Id, e.FullName, e.Code)).ToListAsync(ct));
    }

    // ---------- Nhân viên ----------

    public async Task<EmployeePage> ListEmployeesAsync(string? search, long? departmentId, string? status, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var today = Today;
        var q = db.Employees.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            q = q.Where(e => e.FullName.Contains(s) || e.Code.Contains(s) || (e.Phone != null && e.Phone.Contains(s)));
        }
        if (departmentId is { } d) q = q.Where(e => e.DepartmentId == d);
        q = status switch
        {
            null or "" or "working" => q.Where(e => e.EmploymentStatus == "probation" || e.EmploymentStatus == "official"),
            "all" => q,
            var st => q.Where(e => e.EmploymentStatus == st),
        };

        var working = db.Employees.Where(e => e.EmploymentStatus == "probation" || e.EmploymentStatus == "official");
        var todayStart = today.ToDateTime(TimeOnly.MinValue);
        var summary = new HrSummary(
            await working.CountAsync(ct),
            await working.CountAsync(e => e.EmploymentStatus == "probation", ct),
            await db.Attendances.CountAsync(a => a.WorkDate == today && a.Status == "present" && working.Any(e => e.Id == a.EmployeeId), ct),
            await db.LeaveRequests.CountAsync(l => l.Status == "approved" && l.FromDate <= todayStart.AddDays(1) && l.ToDate >= todayStart && working.Any(e => e.Id == l.EmployeeId), ct),
            await db.LeaveRequests.CountAsync(l => l.Status == "submitted" && db.Employees.Any(e => e.Id == l.EmployeeId), ct),
            await db.Contracts.Where(c => c.Status == "active" && working.Any(e => e.Id == c.EmployeeId))
                .SumAsync(c => (decimal?)(c.BaseSalary + c.Allowances.Sum(a => a.Amount)), ct) ?? 0);

        var total = await q.CountAsync(ct);
        var rows = await q.OrderBy(e => e.Code).Skip((page - 1) * pageSize).Take(pageSize).Select(e => new
        {
            e.Id, e.Code, e.FullName, e.Phone, e.HireDate, e.EmploymentStatus,
            Dept = db.Departments.Where(x => x.Id == e.DepartmentId).Select(x => x.Name).FirstOrDefault(),
            Pos = db.Positions.Where(x => x.Id == e.PositionId).Select(x => x.Name).FirstOrDefault(),
            User = db.Users.Where(u => u.Id == e.UserId).Select(u => u.UserName).FirstOrDefault(),
            Salary = db.Contracts.Where(c => c.EmployeeId == e.Id && c.Status == "active").Select(c => (decimal?)c.BaseSalary).FirstOrDefault(),
            Today = db.Attendances.Where(a => a.EmployeeId == e.Id && a.WorkDate == today).Select(a => a.Status).FirstOrDefault(),
        }).ToListAsync(ct);
        var items = rows.Select(r => new EmployeeListItem(r.Id, r.Code, r.FullName, r.Phone, r.Dept, r.Pos, r.HireDate, r.EmploymentStatus,
            r.Salary ?? 0, r.User, r.Today)).ToList();
        return new EmployeePage(new PagedResult<EmployeeListItem>(items, page, pageSize, total), summary);
    }

    public async Task<Result<EmployeeDetail>> GetEmployeeAsync(long id, CancellationToken ct)
    {
        var e = await db.Employees.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return e is null ? Error.NotFound("nhân viên") : await ToDetailAsync(e, ct);
    }

    public async Task<Result<EmployeeDetail>> CreateEmployeeAsync(SaveEmployeeRequest r, CancellationToken ct)
    {
        var check = await ValidateRefsAsync(r, null, ct);
        if (check.IsFailure) return check.Error!;
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var created = Employee.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync("EMPLOYEE", ct: ct), ToInfo(r), Today);
            if (created.IsFailure) return (Result<EmployeeDetail>)created.Error!;
            db.Employees.Add(created.Value);
            await db.SaveChangesAsync(ct);
            var contract = await NewContractAsync(created.Value, r, ct);
            if (contract.IsFailure) return (Result<EmployeeDetail>)contract.Error!;
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<EmployeeDetail>)await ToDetailAsync(created.Value, ct);
        });
    }

    public async Task<Result<EmployeeDetail>> UpdateEmployeeAsync(long id, SaveEmployeeRequest r, CancellationToken ct)
    {
        var e = await db.Employees.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (e is null) return Error.NotFound("nhân viên");
        if (!string.IsNullOrEmpty(r.RowVersion)) db.Entry(e).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(r.RowVersion);
        var check = await ValidateRefsAsync(r, id, ct);
        if (check.IsFailure) return check.Error!;
        var u = e.Update(ToInfo(r), Today);
        if (u.IsFailure) return u.Error!;

        // Đổi lương / loại hợp đồng -> kết thúc hợp đồng cũ, lập hợp đồng mới từ hôm nay
        var current = await db.Contracts.Include(c => c.Allowances).Where(c => c.EmployeeId == id && c.Status == "active").OrderByDescending(c => c.Id).FirstOrDefaultAsync(ct);
        if (current is null || current.BaseSalary != r.BaseSalary || current.InsuranceSalary != r.InsuranceSalary
            || current.TotalAllowance != r.Allowance || current.ContractType != r.ContractType)
        {
            current?.Expire(Today.AddDays(-1) < current.StartDate ? current.StartDate : Today.AddDays(-1));
            var c = await NewContractAsync(e, r, ct);
            if (c.IsFailure) return c.Error!;
        }
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(e, ct);
    }

    public async Task<Result<OptionDto>> CreatePositionAsync(string name, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(name)) return Error.Validation("position.name", "Nhập tên chức danh.");
        if (await db.Positions.AnyAsync(p => p.Name == name.Trim(), ct)) return Error.Conflict("position.duplicate", "Chức danh đã có.");
        var code = "CD" + (await db.Positions.CountAsync(ct) + 1).ToString("000");
        var p = Position.Create(currentUser.RequireCompanyId(), code, name);
        db.Positions.Add(p);
        await db.SaveChangesAsync(ct);
        return new OptionDto(p.Id, p.Name, p.Code);
    }

    private async Task<Result<Contract>> NewContractAsync(Employee e, SaveEmployeeRequest r, CancellationToken ct)
    {
        if (r.ContractType is not ("probation" or "fixed_term" or "indefinite" or "seasonal" or "service"))
            return Error.Validation("contract.type", "Loại hợp đồng không hợp lệ.");
        var n = await db.Contracts.CountAsync(c => c.EmployeeId == e.Id, ct) + 1;
        var start = await db.Contracts.AnyAsync(c => c.EmployeeId == e.Id, ct) ? Today : e.HireDate ?? Today;
        var c = Contract.Create(e.Id, $"HD-{e.Code}-{n:00}", r.ContractType, start, r.BaseSalary,
            r.InsuranceSalary > 0 ? r.InsuranceSalary : r.BaseSalary, r.Allowance, clock.GetUtcNow().UtcDateTime);
        if (c.IsFailure) return c.Error!;
        db.Contracts.Add(c.Value);
        return c.Value;
    }

    private async Task<Result> ValidateRefsAsync(SaveEmployeeRequest r, long? selfId, CancellationToken ct)
    {
        if (r.DepartmentId is { } d && !await db.Departments.AnyAsync(x => x.Id == d, ct)) return Error.Validation("employee.department", "Phòng ban không hợp lệ.");
        if (r.PositionId is { } p && !await db.Positions.AnyAsync(x => x.Id == p, ct)) return Error.Validation("employee.position", "Chức danh không hợp lệ.");
        if (r.UserId is { } u)
        {
            if (!await db.Users.AnyAsync(x => x.Id == u, ct)) return Error.Validation("employee.user", "Tài khoản không tồn tại.");
            if (await db.Employees.AnyAsync(x => x.UserId == u && x.Id != selfId, ct)) return Error.Conflict("employee.user_taken", "Tài khoản đã gắn với nhân viên khác.");
        }
        if (r.BaseSalary < 0 || r.Allowance < 0 || r.InsuranceSalary < 0) return Error.Validation("employee.salary", "Lương không hợp lệ.");
        if (!string.IsNullOrWhiteSpace(r.Phone) && await db.Employees.AnyAsync(x => x.Phone == PhoneNumber.Normalize(r.Phone) && x.Id != selfId, ct))
            return Error.Conflict("employee.phone_taken", "Số điện thoại đã dùng cho nhân viên khác.");
        return Result.Success();
    }

    private static EmployeeInfo ToInfo(SaveEmployeeRequest r) => new(r.FullName, string.IsNullOrEmpty(r.Gender) ? null : r.Gender, r.DateOfBirth,
        r.Phone, r.Email, r.Address, r.DepartmentId, r.PositionId, r.UserId, r.HireDate, r.Status, r.PersonalTaxCode, r.Dependents,
        r.BankName, r.BankAccountNo, r.IdNumber);

    private async Task<EmployeeDetail> ToDetailAsync(Employee e, CancellationToken ct)
    {
        var c = await db.Contracts.AsNoTracking().Include(x => x.Allowances).Where(x => x.EmployeeId == e.Id && x.Status == "active")
            .OrderByDescending(x => x.Id).FirstOrDefaultAsync(ct);
        var dept = e.DepartmentId is { } d ? await db.Departments.Where(x => x.Id == d).Select(x => x.Name).FirstOrDefaultAsync(ct) : null;
        var pos = e.PositionId is { } p ? await db.Positions.Where(x => x.Id == p).Select(x => x.Name).FirstOrDefaultAsync(ct) : null;
        var user = e.UserId is { } u ? await db.Users.Where(x => x.Id == u).Select(x => x.UserName).FirstOrDefaultAsync(ct) : null;
        var remaining = (await AnnualBalancesAsync([e.Id], ct)).FirstOrDefault()?.Remaining ?? 0;
        return new EmployeeDetail(e.Id, e.Code, e.FullName, e.Gender, e.DateOfBirth, e.IdNumber, e.Phone, e.WorkEmail, e.CurrentAddress,
            e.DepartmentId, dept, e.PositionId, pos, e.UserId, user, e.HireDate, e.TerminationDate, e.EmploymentStatus, e.PersonalTaxCode,
            e.Dependents, e.BankName, e.BankAccountNo, c?.BaseSalary ?? 0, c?.InsuranceSalary ?? 0, c?.TotalAllowance ?? 0, c?.ContractNo,
            c?.ContractType, c?.StartDate, remaining, Convert.ToBase64String(e.RowVersion));
    }

    // ---------- Chấm công ----------

    public async Task<AttendanceMonth> AttendanceAsync(int year, int month, long? departmentId, CancellationToken ct)
    {
        var first = new DateOnly(year, Math.Clamp(month, 1, 12), 1);
        var last = first.AddMonths(1).AddDays(-1);
        var emps = db.Employees.AsNoTracking().Where(e => (e.EmploymentStatus == "probation" || e.EmploymentStatus == "official"
            || (e.TerminationDate != null && e.TerminationDate >= first)) && (e.HireDate == null || e.HireDate <= last));
        if (departmentId is { } d) emps = emps.Where(e => e.DepartmentId == d);
        var list = await emps.OrderBy(e => e.Code).Select(e => new { e.Id, e.Code, e.FullName }).ToListAsync(ct);
        var ids = list.Select(e => e.Id).ToList();
        var rows = await db.Attendances.AsNoTracking().Where(a => ids.Contains(a.EmployeeId) && a.WorkDate >= first && a.WorkDate <= last).ToListAsync(ct);
        var sundays = Enumerable.Range(1, last.Day).Where(dd => new DateOnly(year, month, dd).DayOfWeek == DayOfWeek.Sunday).ToList();
        return new AttendanceMonth(year, month, last.Day, sundays, list.Select(e =>
        {
            var mine = rows.Where(a => a.EmployeeId == e.Id).ToList();
            return new AttendanceRow(e.Id, e.Code, e.FullName,
                mine.ToDictionary(a => a.WorkDate.Day, a => new AttendanceCell(a.Status, a.WorkHours, a.OvertimeHours, a.LateMinutes, a.CheckIn, a.CheckOut, a.Note, a.WorkDays)),
                mine.Sum(a => a.WorkDays), mine.Count(a => a.Status == "leave"), mine.Sum(a => a.OvertimeHours), mine.Count(a => a.LateMinutes > 0));
        }).ToList());
    }

    public async Task<Result> SetAttendanceAsync(SetAttendanceRequest r, CancellationToken ct)
    {
        if (!await db.Employees.AnyAsync(e => e.Id == r.EmployeeId, ct)) return Error.NotFound("nhân viên");
        if (r.Date > Today) return Error.Validation("attendance.future", "Không chấm công cho ngày chưa tới.");
        var a = await GetOrCreateAttendanceAsync(r.EmployeeId, r.Date, ct);
        var set = a.Set(r.Status, r.WorkHours, r.OvertimeHours, r.Note);
        if (set.IsFailure) return set;
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result<int>> FillAttendanceAsync(FillAttendanceRequest r, CancellationToken ct)
    {
        var first = new DateOnly(r.Year, Math.Clamp(r.Month, 1, 12), 1);
        var last = first.AddMonths(1).AddDays(-1);
        if (last > Today) last = Today;
        if (first > Today) return Error.Validation("attendance.future", "Tháng này chưa tới.");
        var emps = await db.Employees.Where(e => (e.EmploymentStatus == "probation" || e.EmploymentStatus == "official")
                && (r.EmployeeIds == null || r.EmployeeIds.Contains(e.Id)))
            .Select(e => new { e.Id, e.HireDate }).ToListAsync(ct);
        var ids = emps.Select(e => e.Id).ToList();
        var existing = (await db.Attendances.Where(a => ids.Contains(a.EmployeeId) && a.WorkDate >= first && a.WorkDate <= last)
            .Select(a => new { a.EmployeeId, a.WorkDate }).ToListAsync(ct)).Select(x => (x.EmployeeId, x.WorkDate)).ToHashSet();
        var shift = await ShiftIdAsync(ct);
        var n = 0;
        foreach (var e in emps)
            for (var d = first; d <= last; d = d.AddDays(1))
            {
                if (d.DayOfWeek == DayOfWeek.Sunday || (e.HireDate is { } h && d < h) || existing.Contains((e.Id, d))) continue;
                var a = Attendance.Create(e.Id, d, shift);
                a.Set("present", 8, 0, null);
                db.Attendances.Add(a);
                n++;
            }
        await db.SaveChangesAsync(ct);
        return n;
    }

    public async Task<Result<AttendanceCell>> CheckAsync(CheckRequest r, CancellationToken ct)
    {
        if (r.Action is not ("in" or "out")) return Error.Validation("attendance.action", "Thao tác không hợp lệ.");
        var e = await db.Employees.FirstOrDefaultAsync(x => x.Id == r.EmployeeId, ct);
        if (e is null) return Error.NotFound("nhân viên");
        if (!e.IsWorking) return Error.Conflict("attendance.not_working", "Nhân viên đã nghỉ việc.");
        var shift = await db.WorkShifts.OrderBy(s => s.Id).FirstAsync(ct);
        var a = await GetOrCreateAttendanceAsync(e.Id, Today, ct);
        var res = a.Check(r.Action == "in", LocalNow, shift.StartTime, shift.EndTime, shift.BreakMinutes);
        if (res.IsFailure) return res.Error!;
        await db.SaveChangesAsync(ct);
        return new AttendanceCell(a.Status, a.WorkHours, a.OvertimeHours, a.LateMinutes, a.CheckIn, a.CheckOut, a.Note, a.WorkDays);
    }

    private async Task<long?> ShiftIdAsync(CancellationToken ct) => await db.WorkShifts.OrderBy(s => s.Id).Select(s => (long?)s.Id).FirstOrDefaultAsync(ct);

    private async Task<Attendance> GetOrCreateAttendanceAsync(long employeeId, DateOnly date, CancellationToken ct)
    {
        var a = await db.Attendances.FirstOrDefaultAsync(x => x.EmployeeId == employeeId && x.WorkDate == date, ct);
        if (a is not null) return a;
        a = Attendance.Create(employeeId, date, await ShiftIdAsync(ct));
        db.Attendances.Add(a);
        return a;
    }

    // ---------- Nghỉ phép ----------

    public async Task<LeavePage> ListLeavesAsync(string? status, long? employeeId, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var q = db.LeaveRequests.AsNoTracking().Where(l => db.Employees.Any(e => e.Id == l.EmployeeId));
        if (!string.IsNullOrEmpty(status)) q = q.Where(l => l.Status == status);
        if (employeeId is { } eid) q = q.Where(l => l.EmployeeId == eid);
        var total = await q.CountAsync(ct);
        var list = await q.OrderBy(l => l.Status == "submitted" ? 0 : 1).ThenByDescending(l => l.FromDate)
            .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var working = await db.Employees.Where(e => e.EmploymentStatus == "probation" || e.EmploymentStatus == "official").Select(e => e.Id).ToListAsync(ct);
        return new LeavePage(new PagedResult<LeaveRequestDto>(await ToLeaveDtosAsync(list, ct), page, pageSize, total), await AnnualBalancesAsync(working, ct));
    }

    public async Task<Result<LeaveRequestDto>> CreateLeaveAsync(CreateLeaveRequest r, CancellationToken ct)
    {
        var e = await db.Employees.FirstOrDefaultAsync(x => x.Id == r.EmployeeId, ct);
        if (e is null) return Error.NotFound("nhân viên");
        if (!e.IsWorking) return Error.Conflict("leave.not_working", "Nhân viên đã nghỉ việc.");
        var type = await db.LeaveTypes.FirstOrDefaultAsync(t => t.Id == r.LeaveTypeId, ct);
        if (type is null) return Error.Validation("leave.type", "Loại nghỉ không hợp lệ.");
        var from = r.FromDate.ToDateTime(TimeOnly.MinValue);
        var to = r.ToDate.ToDateTime(new TimeOnly(23, 59));
        if (await db.LeaveRequests.AnyAsync(l => l.EmployeeId == e.Id && (l.Status == "submitted" || l.Status == "approved") && l.FromDate <= to && l.ToDate >= from, ct))
            return Error.Conflict("leave.overlap", "Đã có đơn nghỉ trùng thời gian này.");
        var created = LeaveRequest.Create(e.Id, type.Id, r.FromDate, r.ToDate, r.HalfDay, r.Reason, currentUser.RequireUserId(), clock.GetUtcNow().UtcDateTime);
        if (created.IsFailure) return created.Error!;
        if (type.DefaultDaysPerYear > 0)
        {
            var bal = await GetBalanceAsync(e.Id, type, (short)r.FromDate.Year, ct);
            if (created.Value.Days > bal.Remaining) return Error.Validation("leave.balance", $"Không đủ ngày phép (còn {bal.Remaining:0.#} ngày).");
        }
        db.LeaveRequests.Add(created.Value);
        await db.SaveChangesAsync(ct);
        return (await ToLeaveDtosAsync([created.Value], ct))[0];
    }

    public async Task<Result<LeaveRequestDto>> ApproveLeaveAsync(long id, CancellationToken ct)
    {
        var l = await db.LeaveRequests.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (l is null) return Error.NotFound("đơn nghỉ");
        var type = await db.LeaveTypes.FirstAsync(t => t.Id == l.LeaveTypeId, ct);
        if (type.DefaultDaysPerYear > 0)
        {
            var bal = await GetBalanceAsync(l.EmployeeId, type, (short)l.FromDate.Year, ct);
            if (l.Days > bal.Remaining) return Error.Validation("leave.balance", $"Không đủ ngày phép (còn {bal.Remaining:0.#} ngày).");
            bal.Use(l.Days);
        }
        var r = l.Approve(currentUser.RequireUserId(), clock.GetUtcNow().UtcDateTime);
        if (r.IsFailure) return r.Error!;
        var half = l.Days % 1 != 0;
        foreach (var d in l.WorkingDates())
        {
            var a = await GetOrCreateAttendanceAsync(l.EmployeeId, d, ct);
            if (half) a.Set("present", 4, 0, $"Nghỉ nửa ngày ({type.Name})");
            else a.Set("leave", 0, 0, type.Name);
        }
        await db.SaveChangesAsync(ct);
        return (await ToLeaveDtosAsync([l], ct))[0];
    }

    public async Task<Result<LeaveRequestDto>> RejectLeaveAsync(long id, string reason, CancellationToken ct)
    {
        var l = await db.LeaveRequests.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (l is null) return Error.NotFound("đơn nghỉ");
        var r = l.Reject(currentUser.RequireUserId(), reason, clock.GetUtcNow().UtcDateTime);
        if (r.IsFailure) return r.Error!;
        await db.SaveChangesAsync(ct);
        return (await ToLeaveDtosAsync([l], ct))[0];
    }

    /// <summary>Hủy đơn: đơn đã duyệt thì trả lại ngày phép và xóa chấm công "nghỉ phép" của các ngày chưa qua.</summary>
    public async Task<Result<LeaveRequestDto>> CancelLeaveAsync(long id, CancellationToken ct)
    {
        var l = await db.LeaveRequests.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (l is null) return Error.NotFound("đơn nghỉ");
        var wasApproved = l.Status == "approved";
        var r = l.Cancel();
        if (r.IsFailure) return r.Error!;
        if (wasApproved)
        {
            var type = await db.LeaveTypes.FirstAsync(t => t.Id == l.LeaveTypeId, ct);
            if (type.DefaultDaysPerYear > 0) (await GetBalanceAsync(l.EmployeeId, type, (short)l.FromDate.Year, ct)).Restore(l.Days);
            var dates = l.WorkingDates().ToList();
            var rows = await db.Attendances.Where(a => a.EmployeeId == l.EmployeeId && dates.Contains(a.WorkDate) && (a.Status == "leave" || a.Note != null)).ToListAsync(ct);
            db.Attendances.RemoveRange(rows.Where(a => a.Status == "leave" || (a.Note ?? "").StartsWith("Nghỉ nửa ngày")));
        }
        await db.SaveChangesAsync(ct);
        return (await ToLeaveDtosAsync([l], ct))[0];
    }

    private async Task<LeaveBalance> GetBalanceAsync(long employeeId, LeaveType type, short year, CancellationToken ct)
    {
        var b = await db.LeaveBalances.FirstOrDefaultAsync(x => x.EmployeeId == employeeId && x.LeaveTypeId == type.Id && x.LeaveYear == year, ct);
        if (b is not null) return b;
        b = LeaveBalance.Create(employeeId, type.Id, year, type.DefaultDaysPerYear);
        db.LeaveBalances.Add(b);
        return b;
    }

    /// <summary>Quỹ phép năm (loại có số ngày mặc định / năm, VD phép năm 12 ngày) của năm hiện tại.</summary>
    private async Task<List<LeaveBalanceDto>> AnnualBalancesAsync(IReadOnlyList<long> employeeIds, CancellationToken ct)
    {
        var type = await db.LeaveTypes.Where(t => t.DefaultDaysPerYear > 0).OrderByDescending(t => t.DefaultDaysPerYear).FirstOrDefaultAsync(ct);
        if (type is null) return [];
        var year = (short)Today.Year;
        var emps = await db.Employees.AsNoTracking().Where(e => employeeIds.Contains(e.Id)).OrderBy(e => e.Code).Select(e => new { e.Id, e.Code, e.FullName }).ToListAsync(ct);
        var bals = await db.LeaveBalances.AsNoTracking().Where(b => employeeIds.Contains(b.EmployeeId) && b.LeaveTypeId == type.Id && b.LeaveYear == year)
            .ToDictionaryAsync(b => b.EmployeeId, ct);
        return emps.Select(e =>
        {
            var b = bals.GetValueOrDefault(e.Id);
            var entitled = b is null ? type.DefaultDaysPerYear : b.EntitledDays + b.CarriedDays;
            var used = b?.UsedDays ?? 0;
            return new LeaveBalanceDto(e.Id, e.Code, e.FullName, entitled, used, entitled - used);
        }).ToList();
    }

    private async Task<List<LeaveRequestDto>> ToLeaveDtosAsync(IReadOnlyList<LeaveRequest> list, CancellationToken ct)
    {
        var empIds = list.Select(l => l.EmployeeId).Distinct().ToList();
        var userIds = list.Where(l => l.ApproverUserId != null).Select(l => l.ApproverUserId!.Value).Distinct().ToList();
        var emps = await db.Employees.IgnoreQueryFilters().Where(e => empIds.Contains(e.Id)).ToDictionaryAsync(e => e.Id, e => e.FullName, ct);
        var users = await db.Users.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName, ct);
        var types = await db.LeaveTypes.ToDictionaryAsync(t => t.Id, t => t.Name, ct);
        return list.Select(l => new LeaveRequestDto(l.Id, l.EmployeeId, emps.GetValueOrDefault(l.EmployeeId, ""), l.LeaveTypeId,
            types.GetValueOrDefault(l.LeaveTypeId, ""), DateOnly.FromDateTime(l.FromDate), DateOnly.FromDateTime(l.ToDate), l.Days, l.Reason, l.Status,
            l.ApproverUserId is { } u ? users.GetValueOrDefault(u) : null, l.RejectReason, l.CreatedAt)).ToList();
    }
}
