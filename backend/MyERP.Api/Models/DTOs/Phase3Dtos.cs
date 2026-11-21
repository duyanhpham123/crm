namespace MyERP.Api.Models.DTOs;

// ===================== NHÂN SỰ =====================

public sealed record LeaveTypeDto(long Id, string Name, bool IsPaid, decimal DefaultDaysPerYear);

public sealed record HrLookups(IReadOnlyList<OptionDto> Departments, IReadOnlyList<OptionDto> Positions, IReadOnlyList<OptionDto> Users,
    IReadOnlyList<LeaveTypeDto> LeaveTypes, IReadOnlyList<OptionDto> Employees);

public sealed record EmployeeListItem(long Id, string Code, string FullName, string? Phone, string? DepartmentName, string? PositionName,
    DateOnly? HireDate, string Status, decimal BaseSalary, string? UserName, string? TodayStatus);

public sealed record HrSummary(int Working, int Probation, int PresentToday, int OnLeaveToday, int PendingLeaves, decimal MonthlySalaryFund);

public sealed record EmployeePage(PagedResult<EmployeeListItem> Rows, HrSummary Summary);

public sealed record EmployeeDetail(long Id, string Code, string FullName, string? Gender, DateOnly? DateOfBirth, string? IdNumber, string? Phone,
    string? Email, string? Address, long? DepartmentId, string? DepartmentName, long? PositionId, string? PositionName, long? UserId, string? UserName,
    DateOnly? HireDate, DateOnly? TerminationDate, string Status, string? PersonalTaxCode, byte Dependents, string? BankName, string? BankAccountNo,
    decimal BaseSalary, decimal InsuranceSalary, decimal Allowance, string? ContractNo, string? ContractType, DateOnly? ContractStart,
    decimal AnnualLeaveRemaining, string RowVersion);

public sealed record SaveEmployeeRequest(string FullName, string? Gender, DateOnly? DateOfBirth, string? IdNumber, string? Phone, string? Email,
    string? Address, long? DepartmentId, long? PositionId, long? UserId, DateOnly? HireDate, string Status, string? PersonalTaxCode,
    byte Dependents, string? BankName, string? BankAccountNo, decimal BaseSalary, decimal InsuranceSalary, decimal Allowance,
    string ContractType = "probation", string? RowVersion = null);

public sealed record AttendanceCell(string Status, decimal WorkHours, decimal OvertimeHours, int LateMinutes, DateTime? CheckIn, DateTime? CheckOut,
    string? Note, decimal WorkDays);

public sealed record AttendanceRow(long EmployeeId, string Code, string FullName, IReadOnlyDictionary<int, AttendanceCell> Cells,
    decimal WorkDays, decimal LeaveDays, decimal OvertimeHours, int LateCount);

public sealed record AttendanceMonth(int Year, int Month, int DaysInMonth, IReadOnlyList<int> Sundays, IReadOnlyList<AttendanceRow> Rows);

public sealed record SetAttendanceRequest(long EmployeeId, DateOnly Date, string Status, decimal WorkHours, decimal OvertimeHours, string? Note);

/// <summary>Chấm đủ công (8 giờ) cho các ngày làm việc còn trống từ đầu tháng tới hôm nay.</summary>
public sealed record FillAttendanceRequest(int Year, int Month, IReadOnlyList<long>? EmployeeIds);

public sealed record CheckRequest(long EmployeeId, string Action);

public sealed record LeaveRequestDto(long Id, long EmployeeId, string EmployeeName, long LeaveTypeId, string TypeName, DateOnly FromDate, DateOnly ToDate,
    decimal Days, string? Reason, string Status, string? ApproverName, string? RejectReason, DateTime CreatedAt);

public sealed record CreateLeaveRequest(long EmployeeId, long LeaveTypeId, DateOnly FromDate, DateOnly ToDate, bool HalfDay, string? Reason);

public sealed record LeaveBalanceDto(long EmployeeId, string Code, string FullName, decimal Entitled, decimal Used, decimal Remaining);

public sealed record LeavePage(PagedResult<LeaveRequestDto> Rows, IReadOnlyList<LeaveBalanceDto> Balances);

public sealed record PayrollListItem(long Id, int Year, int Month, decimal StandardDays, string Status, int EmployeeCount, decimal TotalGross,
    decimal TotalNet, decimal TotalInsurance, decimal TotalTax, decimal TotalEmployerInsurance);

public sealed record PayslipDto(long Id, long EmployeeId, string Code, string FullName, string? DepartmentName, decimal ContractSalary,
    decimal ActualDays, decimal PaidLeaveDays, decimal OvertimeHours, decimal BaseSalary, decimal TotalAllowance, decimal OvertimePay, decimal Bonus,
    decimal GrossIncome, decimal Insurance, decimal TaxableIncome, decimal PersonalIncomeTax, decimal Advance, decimal OtherDeductions, decimal NetPay,
    decimal EmployerInsurance, string Status, string? BankAccountNo);

public sealed record PayrollDetail(long Id, int Year, int Month, decimal StandardDays, string Status, IReadOnlyList<PayslipDto> Payslips,
    decimal TotalGross, decimal TotalNet, decimal TotalInsurance, decimal TotalTax, decimal TotalEmployerInsurance, string? VoucherDocNo);

public sealed record CreatePayrollRequest(int Year, int Month, decimal StandardDays = 26);

public sealed record UpdatePayslipRequest(decimal Bonus, decimal Advance, decimal OtherDeductions);

public sealed record PayPayrollRequest(long? BankAccountId, DateOnly? Date);

// ===================== MARKETING =====================

public sealed record MarketingLookups(IReadOnlyList<CodeOption> Channels, IReadOnlyList<OptionDto> Campaigns, IReadOnlyList<CodeOption> SalesChannels);

public sealed record CampaignListItem(long Id, string Code, string Name, string Channel, DateOnly StartDate, DateOnly? EndDate, decimal Budget,
    decimal ActualCost, string Status, int Leads, int Orders, decimal Revenue, decimal? Roas, decimal? CostPerLead);

public sealed record CampaignSummary(int Running, decimal TotalSpend, decimal TotalRevenue, int TotalLeads, decimal? Roas);

public sealed record CampaignPage(PagedResult<CampaignListItem> Rows, CampaignSummary Summary);

public sealed record DailyStatDto(DateOnly Date, long Impressions, long Clicks, decimal Spend, int Leads);

public sealed record CampaignDetail(long Id, string Code, string Name, string Channel, DateOnly StartDate, DateOnly? EndDate, decimal Budget,
    decimal ActualCost, int? TargetLeads, string? UtmCampaign, string Status, string? Description, long Impressions, long Clicks,
    int Leads, int Orders, decimal Revenue, decimal? Roas, decimal? CostPerLead, decimal? Ctr, IReadOnlyList<DailyStatDto> Stats,
    IReadOnlyList<PromotionListItem> Promotions, string RowVersion);

public sealed record SaveCampaignRequest(string Name, string Channel, DateOnly StartDate, DateOnly? EndDate, decimal Budget, int? TargetLeads,
    string? UtmCampaign, string Status, string? Description, string? RowVersion = null);

public sealed record DailyStatRequest(DateOnly Date, long Impressions, long Clicks, decimal Spend, int Leads);

public sealed record PromotionListItem(long Id, string Code, string Name, string Type, decimal Value, decimal? MaxDiscount, decimal MinOrderAmount,
    DateTime StartAt, DateTime EndAt, int? UsageLimit, int UsedCount, string? Channels, long? CampaignId, string? CampaignName, bool IsActive,
    string State, decimal Revenue, decimal DiscountGiven);

public sealed record SavePromotionRequest(string Code, string Name, string Type, decimal Value, decimal? MaxDiscount, decimal MinOrderAmount,
    DateTime StartAt, DateTime EndAt, int? UsageLimit, string? Channels, long? CampaignId, bool IsActive = true);

public sealed record PromotionCheckResult(long Id, string Code, string Name, decimal Discount);

public sealed record CustomerSegmentRow(long PartnerId, string Code, string Name, string? Phone, int Orders, decimal TotalSpent,
    DateOnly LastOrderDate, int DaysSinceLast, string Segment);

public sealed record SegmentPage(PagedResult<CustomerSegmentRow> Rows, IReadOnlyDictionary<string, int> Counts);

// ===================== CÀI ĐẶT =====================

public sealed record CompanyInfoDto(string Name, string? ShortName, string? TaxCode, string? Address, string? Phone, string? Email, string? Website,
    string? LegalRepresentative, string? PrintFooter, string? ReturnPolicy);

public sealed record DepartmentDto(long Id, string Code, string Name, long? ParentId, int SortOrder, bool IsActive, int EmployeeCount, int UserCount);

public sealed record SaveDepartmentRequest(string Code, string Name, long? ParentId, int SortOrder, bool IsActive = true);

public sealed record WarehouseDto(long Id, string Code, string Name, string? Street, bool AllowNegativeStock, bool IsActive, int SkuCount, decimal StockValue);

public sealed record SaveWarehouseRequest(string Code, string Name, string? Street, bool AllowNegativeStock = false, bool IsActive = true);

public sealed record AppToggleDto(int Id, string Code, string Name, string? Icon, string? Color, bool IsEnabled, bool Locked);

public sealed record ToggleRequest(bool IsEnabled);

public sealed record SequenceDto(long Id, string Code, string Label, string Prefix, string? DatePattern, byte Padding, string Example);

public sealed record SaveSequenceRequest(string Prefix, string? DatePattern, byte Padding);
