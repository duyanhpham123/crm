using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Hr;

public static class EmploymentStatuses
{
    public static readonly string[] All = ["probation", "official", "maternity", "suspended", "resigned", "terminated"];
    public static bool IsWorking(string s) => s is "probation" or "official";
}

/// <summary>hr.Positions - chức danh.</summary>
public sealed class Position : Entity, ICompanyOwned
{
    private Position() { }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public long? DepartmentId { get; private set; }
    public bool IsActive { get; private set; } = true;

    public static Position Create(long companyId, string code, string name) => new() { CompanyId = companyId, Code = code, Name = name.Trim() };
}

public sealed record EmployeeInfo(
    string FullName, string? Gender, DateOnly? DateOfBirth, string? Phone, string? Email, string? Address, long? DepartmentId,
    long? PositionId, long? UserId, DateOnly? HireDate, string Status, string? PersonalTaxCode, byte Dependents,
    string? BankName, string? BankAccountNo, string? IdNumber);

/// <summary>hr.Employees - hồ sơ nhân viên.</summary>
public sealed class Employee : AuditableEntity, ICompanyOwned
{
    private Employee() { }

    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public long? UserId { get; private set; }
    public string FullName { get; private set; } = "";
    public string? Gender { get; private set; }
    public DateOnly? DateOfBirth { get; private set; }
    public string? IdNumber { get; private set; }
    public string? Phone { get; private set; }
    public string? WorkEmail { get; private set; }
    public string? CurrentAddress { get; private set; }
    public long? DepartmentId { get; private set; }
    public long? PositionId { get; private set; }
    public DateOnly? HireDate { get; private set; }
    public DateOnly? TerminationDate { get; private set; }
    public string EmploymentStatus { get; private set; } = "probation";
    public string? PersonalTaxCode { get; private set; }
    public byte Dependents { get; private set; }
    public string? BankName { get; private set; }
    public string? BankAccountNo { get; private set; }

    public bool IsWorking => EmploymentStatuses.IsWorking(EmploymentStatus);

    public static Result<Employee> Create(long companyId, string code, EmployeeInfo info, DateOnly today)
    {
        var e = new Employee { CompanyId = companyId, Code = code };
        var r = e.Update(info, today);
        return r.IsFailure ? r.Error! : e;
    }

    public Result Update(EmployeeInfo i, DateOnly today)
    {
        if (string.IsNullOrWhiteSpace(i.FullName)) return Error.Validation("employee.name", "Nhập họ tên nhân viên.");
        if (!EmploymentStatuses.All.Contains(i.Status)) return Error.Validation("employee.status", "Trạng thái không hợp lệ.");
        if (i.Gender is not (null or "M" or "F" or "O")) return Error.Validation("employee.gender", "Giới tính không hợp lệ.");
        string? phone = null;
        if (!string.IsNullOrWhiteSpace(i.Phone))
        {
            if (!PhoneNumber.IsValid(i.Phone)) return Error.Validation("employee.phone", "Số điện thoại không hợp lệ.");
            phone = PhoneNumber.Normalize(i.Phone);
        }
        var wasWorking = IsWorking;
        FullName = i.FullName.Trim(); Gender = i.Gender; DateOfBirth = i.DateOfBirth; Phone = phone; WorkEmail = Clean(i.Email)?.ToLowerInvariant();
        CurrentAddress = Clean(i.Address); DepartmentId = i.DepartmentId; PositionId = i.PositionId; UserId = i.UserId; HireDate = i.HireDate;
        EmploymentStatus = i.Status; PersonalTaxCode = Clean(i.PersonalTaxCode); Dependents = i.Dependents;
        BankName = Clean(i.BankName); BankAccountNo = Clean(i.BankAccountNo); IdNumber = Clean(i.IdNumber);
        if (wasWorking && !IsWorking) TerminationDate ??= today;
        if (IsWorking) TerminationDate = null;
        return Result.Success();
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

/// <summary>hr.Contracts - hợp đồng lao động (lương cơ bản, lương đóng bảo hiểm, phụ cấp).</summary>
public sealed class Contract
{
    private Contract() { }
    public long Id { get; private set; }
    public long EmployeeId { get; private set; }
    public string ContractNo { get; private set; } = "";
    public string ContractType { get; private set; } = "probation";
    public DateOnly StartDate { get; private set; }
    public DateOnly? EndDate { get; private set; }
    public decimal BaseSalary { get; private set; }
    public decimal InsuranceSalary { get; private set; }
    public string Status { get; private set; } = "active";
    public DateTime CreatedAt { get; private set; }

    private readonly List<ContractAllowance> _allowances = [];
    public IReadOnlyList<ContractAllowance> Allowances => _allowances;
    public decimal TotalAllowance => _allowances.Sum(a => a.Amount);

    public static Result<Contract> Create(long employeeId, string no, string type, DateOnly start, decimal baseSalary, decimal insuranceSalary,
        decimal allowance, DateTime now)
    {
        if (baseSalary < 0 || insuranceSalary < 0 || allowance < 0) return Error.Validation("contract.salary", "Lương không hợp lệ.");
        var c = new Contract
        {
            EmployeeId = employeeId, ContractNo = no, ContractType = type, StartDate = start, BaseSalary = baseSalary,
            InsuranceSalary = insuranceSalary, Status = "active", CreatedAt = now,
        };
        if (allowance > 0) c._allowances.Add(new ContractAllowance("Phụ cấp ăn trưa, xăng xe", allowance));
        return c;
    }

    public void Expire(DateOnly end) { Status = "expired"; EndDate = end; }
}

public sealed class ContractAllowance
{
    private ContractAllowance() { }
    internal ContractAllowance(string name, decimal amount) { Name = name; Amount = amount; IsTaxable = false; }
    public long Id { get; private set; }
    public long ContractId { get; private set; }
    public string Name { get; private set; } = "";
    public decimal Amount { get; private set; }
    public bool IsTaxable { get; private set; }
}

public static class AttendanceStatuses
{
    public static readonly string[] All = ["present", "absent", "leave", "holiday", "business_trip"];
}

/// <summary>hr.Attendances - chấm công 1 ngày của 1 nhân viên (1 ca hành chính).</summary>
public sealed class Attendance
{
    private Attendance() { }
    public long Id { get; private set; }
    public long EmployeeId { get; private set; }
    public DateOnly WorkDate { get; private set; }
    public long? ShiftId { get; private set; }
    public DateTime? CheckIn { get; private set; }
    public DateTime? CheckOut { get; private set; }
    public decimal WorkHours { get; private set; }
    public decimal OvertimeHours { get; private set; }
    public int LateMinutes { get; private set; }
    public int EarlyMinutes { get; private set; }
    public string Source { get; private set; } = "manual";
    public string Status { get; private set; } = "present";
    public string? Note { get; private set; }

    /// <summary>Ngày công: đi làm >= 7 giờ = 1 công, >= 3,5 giờ = 0,5 công; nghỉ phép có lương / lễ / công tác = 1.</summary>
    public decimal WorkDays => Status switch
    {
        "present" => WorkHours >= 7 ? 1 : WorkHours >= 3.5m ? 0.5m : WorkHours > 0 ? 0.5m : 1,
        "business_trip" or "holiday" => 1,
        _ => 0,
    };

    public static Attendance Create(long employeeId, DateOnly date, long? shiftId)
        => new() { EmployeeId = employeeId, WorkDate = date, ShiftId = shiftId };

    public Result Set(string status, decimal workHours, decimal overtimeHours, string? note)
    {
        if (!AttendanceStatuses.All.Contains(status)) return Error.Validation("attendance.status", "Trạng thái chấm công không hợp lệ.");
        if (workHours is < 0 or > 24 || overtimeHours is < 0 or > 16) return Error.Validation("attendance.hours", "Số giờ không hợp lệ.");
        Status = status;
        WorkHours = status == "present" ? workHours : 0;
        OvertimeHours = status == "present" ? overtimeHours : 0;
        Note = string.IsNullOrWhiteSpace(note) ? null : note.Trim();
        Source = "manual";
        if (status != "present") { LateMinutes = 0; EarlyMinutes = 0; }
        return Result.Success();
    }

    /// <summary>Check-in / check-out (giờ địa phương). Ca 8:00 - 17:00, nghỉ trưa 60 phút.</summary>
    public Result Check(bool isIn, DateTime localNow, TimeOnly shiftStart, TimeOnly shiftEnd, int breakMinutes)
    {
        Source = "web"; Status = "present";
        if (isIn)
        {
            if (CheckIn is not null) return Error.Conflict("attendance.checked_in", "Đã check-in hôm nay.");
            CheckIn = localNow;
            LateMinutes = Math.Max(0, (int)(TimeOnly.FromDateTime(localNow) - shiftStart).TotalMinutes);
            if (TimeOnly.FromDateTime(localNow) < shiftStart) LateMinutes = 0;
            return Result.Success();
        }
        if (CheckIn is null) return Error.Conflict("attendance.no_check_in", "Chưa check-in.");
        CheckOut = localNow;
        var end = TimeOnly.FromDateTime(localNow);
        EarlyMinutes = end < shiftEnd ? (int)(shiftEnd - end).TotalMinutes : 0;
        var span = (decimal)(localNow - CheckIn.Value).TotalHours;
        var hours = Math.Round(Math.Max(0, span - (span > 5 ? breakMinutes / 60m : 0)), 2);   // làm trên 5 tiếng thì trừ nghỉ trưa
        WorkHours = Math.Min(hours, 8);
        OvertimeHours = Math.Max(0, Math.Round(hours - 8, 2));
        return Result.Success();
    }
}

/// <summary>hr.WorkShifts</summary>
public sealed class WorkShift : Entity, ICompanyOwned
{
    private WorkShift() { }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public TimeOnly StartTime { get; private set; }
    public TimeOnly EndTime { get; private set; }
    public int BreakMinutes { get; private set; }
}

/// <summary>hr.LeaveTypes</summary>
public sealed class LeaveType : Entity, ICompanyOwned
{
    private LeaveType() { }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public bool IsPaid { get; private set; }
    public decimal DefaultDaysPerYear { get; private set; }
}

/// <summary>hr.LeaveBalances - quỹ phép theo năm.</summary>
public sealed class LeaveBalance
{
    private LeaveBalance() { }
    public long EmployeeId { get; private set; }
    public long LeaveTypeId { get; private set; }
    public short LeaveYear { get; private set; }
    public decimal EntitledDays { get; private set; }
    public decimal CarriedDays { get; private set; }
    public decimal UsedDays { get; private set; }
    public decimal Remaining => EntitledDays + CarriedDays - UsedDays;

    public static LeaveBalance Create(long employeeId, long typeId, short year, decimal entitled)
        => new() { EmployeeId = employeeId, LeaveTypeId = typeId, LeaveYear = year, EntitledDays = entitled };

    public void Use(decimal days) => UsedDays += days;
    public void Restore(decimal days) => UsedDays = Math.Max(0, UsedDays - days);
}

/// <summary>hr.LeaveRequests - đơn xin nghỉ. Tạo là gửi duyệt; duyệt thì chấm công "nghỉ phép" và trừ quỹ phép.</summary>
public sealed class LeaveRequest
{
    private LeaveRequest() { }
    public long Id { get; private set; }
    public long EmployeeId { get; private set; }
    public long LeaveTypeId { get; private set; }
    public DateTime FromDate { get; private set; }
    public DateTime ToDate { get; private set; }
    public decimal Days { get; private set; }
    public string? Reason { get; private set; }
    public string Status { get; private set; } = "submitted";
    public long? ApproverUserId { get; private set; }
    public DateTime? ApprovedAt { get; private set; }
    public string? RejectReason { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public long? CreatedBy { get; private set; }

    /// <summary>Số ngày nghỉ: bỏ Chủ nhật; nghỉ nửa ngày khi from = to và halfDay.</summary>
    public static decimal CountDays(DateOnly from, DateOnly to, bool halfDay)
    {
        if (halfDay && from == to) return from.DayOfWeek == DayOfWeek.Sunday ? 0 : 0.5m;
        var n = 0;
        for (var d = from; d <= to; d = d.AddDays(1)) if (d.DayOfWeek != DayOfWeek.Sunday) n++;
        return n;
    }

    public static Result<LeaveRequest> Create(long employeeId, long typeId, DateOnly from, DateOnly to, bool halfDay, string? reason, long userId, DateTime now)
    {
        if (to < from) return Error.Validation("leave.dates", "Ngày kết thúc phải sau ngày bắt đầu.");
        var days = CountDays(from, to, halfDay);
        if (days <= 0) return Error.Validation("leave.days", "Khoảng nghỉ không có ngày làm việc nào (Chủ nhật).");
        return new LeaveRequest
        {
            EmployeeId = employeeId, LeaveTypeId = typeId, FromDate = from.ToDateTime(TimeOnly.MinValue),
            ToDate = to.ToDateTime(halfDay && from == to ? new TimeOnly(12, 0) : new TimeOnly(23, 59)), Days = days,
            Reason = string.IsNullOrWhiteSpace(reason) ? null : reason.Trim(), Status = "submitted", CreatedAt = now, CreatedBy = userId,
        };
    }

    public IEnumerable<DateOnly> WorkingDates()
    {
        for (var d = DateOnly.FromDateTime(FromDate); d <= DateOnly.FromDateTime(ToDate); d = d.AddDays(1))
            if (d.DayOfWeek != DayOfWeek.Sunday) yield return d;
    }

    public Result Approve(long userId, DateTime now)
    {
        if (Status != "submitted") return Error.Conflict("leave.not_pending", "Đơn đã được xử lý.");
        Status = "approved"; ApproverUserId = userId; ApprovedAt = now;
        return Result.Success();
    }

    public Result Reject(long userId, string reason, DateTime now)
    {
        if (Status != "submitted") return Error.Conflict("leave.not_pending", "Đơn đã được xử lý.");
        if (string.IsNullOrWhiteSpace(reason)) return Error.Validation("leave.reason", "Nhập lý do từ chối.");
        Status = "rejected"; ApproverUserId = userId; ApprovedAt = now; RejectReason = reason.Trim();
        return Result.Success();
    }

    public Result Cancel()
    {
        if (Status is "rejected" or "cancelled") return Error.Conflict("leave.closed", "Đơn đã đóng.");
        Status = "cancelled";
        return Result.Success();
    }
}
