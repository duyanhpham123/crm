using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Hr;
using MyERP.Api.Services.Marketing;
using MyERP.Api.Services.Settings;

namespace MyERP.Api.Controllers;

/// <summary>Nhân sự: nhân viên, chấm công, nghỉ phép, bảng lương.</summary>
[Route("api/hr")]
[HasPermission(Permissions.Hr.View)]
public sealed class HrController(IHrService hr, IPayrollService payroll) : ApiControllerBase
{
    [HttpGet("lookups")]
    public Task<HrLookups> Lookups(CancellationToken ct) => hr.GetLookupsAsync(ct);

    /// <summary>GET /api/hr/employees?search=&amp;departmentId=&amp;status=working|all|probation|official|resigned...</summary>
    [HttpGet("employees")]
    public Task<EmployeePage> Employees([FromQuery] string? search, [FromQuery] long? departmentId, [FromQuery] string? status,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => hr.ListEmployeesAsync(search, departmentId, status, page, pageSize, ct);

    [HttpGet("employees/{id:long}")]
    public async Task<IActionResult> Employee(long id, CancellationToken ct) => FromResult(await hr.GetEmployeeAsync(id, ct), Ok);

    [HttpPost("employees")]
    [HasPermission(Permissions.Hr.Create)]
    public async Task<IActionResult> CreateEmployee(SaveEmployeeRequest request, CancellationToken ct)
        => FromResult(await hr.CreateEmployeeAsync(request, ct), dto => CreatedAtAction(nameof(Employee), new { id = dto.Id }, dto));

    [HttpPut("employees/{id:long}")]
    [HasPermission(Permissions.Hr.Edit)]
    public async Task<IActionResult> UpdateEmployee(long id, SaveEmployeeRequest request, CancellationToken ct)
        => FromResult(await hr.UpdateEmployeeAsync(id, request, ct), Ok);

    [HttpPost("positions")]
    [HasPermission(Permissions.Hr.Create)]
    public async Task<IActionResult> CreatePosition(Inventory.NameRequest request, CancellationToken ct)
        => FromResult(await hr.CreatePositionAsync(request.Name, ct), Ok);

    // ----- Chấm công -----

    /// <summary>GET /api/hr/attendance?year=2026&amp;month=11&amp;departmentId=</summary>
    [HttpGet("attendance")]
    public Task<AttendanceMonth> Attendance([FromQuery] int year, [FromQuery] int month, [FromQuery] long? departmentId, CancellationToken ct)
        => hr.AttendanceAsync(year, month, departmentId, ct);

    [HttpPut("attendance")]
    [HasPermission(Permissions.Hr.Edit)]
    public async Task<IActionResult> SetAttendance(SetAttendanceRequest request, CancellationToken ct)
        => FromResult(await hr.SetAttendanceAsync(request, ct), NoContent);

    /// <summary>POST /api/hr/attendance/fill - chấm đủ công các ngày còn trống đến hôm nay.</summary>
    [HttpPost("attendance/fill")]
    [HasPermission(Permissions.Hr.Edit)]
    public async Task<IActionResult> Fill(FillAttendanceRequest request, CancellationToken ct)
        => FromResult(await hr.FillAttendanceAsync(request, ct), n => Ok(new { filled = n }));

    /// <summary>POST /api/hr/attendance/check  body: { employeeId, action: "in" | "out" }</summary>
    [HttpPost("attendance/check")]
    [HasPermission(Permissions.Hr.Edit)]
    public async Task<IActionResult> Check(CheckRequest request, CancellationToken ct) => FromResult(await hr.CheckAsync(request, ct), Ok);

    // ----- Nghỉ phép -----

    [HttpGet("leaves")]
    public Task<LeavePage> Leaves([FromQuery] string? status, [FromQuery] long? employeeId, [FromQuery] int page = 1, [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
        => hr.ListLeavesAsync(status, employeeId, page, pageSize, ct);

    [HttpPost("leaves")]
    [HasPermission(Permissions.Hr.Create)]
    public async Task<IActionResult> CreateLeave(CreateLeaveRequest request, CancellationToken ct) => FromResult(await hr.CreateLeaveAsync(request, ct), Ok);

    [HttpPost("leaves/{id:long}/approve")]
    [HasPermission(Permissions.Hr.Approve)]
    public async Task<IActionResult> ApproveLeave(long id, CancellationToken ct) => FromResult(await hr.ApproveLeaveAsync(id, ct), Ok);

    [HttpPost("leaves/{id:long}/reject")]
    [HasPermission(Permissions.Hr.Approve)]
    public async Task<IActionResult> RejectLeave(long id, ReasonRequest request, CancellationToken ct) => FromResult(await hr.RejectLeaveAsync(id, request.Reason, ct), Ok);

    [HttpPost("leaves/{id:long}/cancel")]
    [HasPermission(Permissions.Hr.Edit)]
    public async Task<IActionResult> CancelLeave(long id, CancellationToken ct) => FromResult(await hr.CancelLeaveAsync(id, ct), Ok);

    // ----- Bảng lương -----

    [HttpGet("payroll")]
    public Task<IReadOnlyList<PayrollListItem>> Payrolls(CancellationToken ct) => payroll.ListAsync(ct);

    [HttpGet("payroll/{id:long}")]
    public async Task<IActionResult> Payroll(long id, CancellationToken ct) => FromResult(await payroll.GetAsync(id, ct), Ok);

    [HttpPost("payroll")]
    [HasPermission(Permissions.Hr.Create)]
    public async Task<IActionResult> CreatePayroll(CreatePayrollRequest request, CancellationToken ct) => FromResult(await payroll.CreateAsync(request, ct), Ok);

    /// <summary>POST /api/hr/payroll/5/recalculate?standardDays=26 - tính lại theo chấm công mới nhất.</summary>
    [HttpPost("payroll/{id:long}/recalculate")]
    [HasPermission(Permissions.Hr.Edit)]
    public async Task<IActionResult> Recalculate(long id, [FromQuery] decimal? standardDays, CancellationToken ct)
        => FromResult(await payroll.RecalculateAsync(id, standardDays, ct), Ok);

    [HttpPut("payroll/{id:long}/payslips/{payslipId:long}")]
    [HasPermission(Permissions.Hr.Edit)]
    public async Task<IActionResult> UpdatePayslip(long id, long payslipId, UpdatePayslipRequest request, CancellationToken ct)
        => FromResult(await payroll.UpdatePayslipAsync(id, payslipId, request, ct), Ok);

    [HttpPost("payroll/{id:long}/approve")]
    [HasPermission(Permissions.Hr.Approve)]
    public async Task<IActionResult> ApprovePayroll(long id, CancellationToken ct) => FromResult(await payroll.ApproveAsync(id, ct), Ok);

    [HttpPost("payroll/{id:long}/reopen")]
    [HasPermission(Permissions.Hr.Approve)]
    public async Task<IActionResult> ReopenPayroll(long id, CancellationToken ct) => FromResult(await payroll.ReopenAsync(id, ct), Ok);

    /// <summary>POST /api/hr/payroll/5/pay - chi lương, tạo phiếu chi bên Kế toán.</summary>
    [HttpPost("payroll/{id:long}/pay")]
    [HasPermission(Permissions.Hr.Approve)]
    [HasPermission(Permissions.Accounting.Create)]
    public async Task<IActionResult> PayPayroll(long id, PayPayrollRequest request, CancellationToken ct) => FromResult(await payroll.PayAsync(id, request, ct), Ok);
}

/// <summary>Marketing: chiến dịch, mã giảm giá, phân nhóm khách.</summary>
[Route("api/marketing")]
[HasPermission(Permissions.Marketing.View)]
public sealed class MarketingController(IMarketingService marketing) : ApiControllerBase
{
    [HttpGet("lookups")]
    public Task<MarketingLookups> Lookups(CancellationToken ct) => marketing.GetLookupsAsync(ct);

    [HttpGet("campaigns")]
    public Task<CampaignPage> Campaigns([FromQuery] string? search, [FromQuery] string? status, [FromQuery] int page = 1, [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
        => marketing.ListCampaignsAsync(search, status, page, pageSize, ct);

    [HttpGet("campaigns/{id:long}")]
    public async Task<IActionResult> Campaign(long id, CancellationToken ct) => FromResult(await marketing.GetCampaignAsync(id, ct), Ok);

    [HttpPost("campaigns")]
    [HasPermission(Permissions.Marketing.Create)]
    public async Task<IActionResult> CreateCampaign(SaveCampaignRequest request, CancellationToken ct)
        => FromResult(await marketing.CreateCampaignAsync(request, ct), dto => CreatedAtAction(nameof(Campaign), new { id = dto.Id }, dto));

    [HttpPut("campaigns/{id:long}")]
    [HasPermission(Permissions.Marketing.Edit)]
    public async Task<IActionResult> UpdateCampaign(long id, SaveCampaignRequest request, CancellationToken ct)
        => FromResult(await marketing.UpdateCampaignAsync(id, request, ct), Ok);

    /// <summary>PUT /api/marketing/campaigns/5/stats - nhập chi phí / hiển thị / click / lead của 1 ngày.</summary>
    [HttpPut("campaigns/{id:long}/stats")]
    [HasPermission(Permissions.Marketing.Edit)]
    public async Task<IActionResult> SetStat(long id, DailyStatRequest request, CancellationToken ct)
        => FromResult(await marketing.SetDailyStatAsync(id, request, ct), Ok);

    /// <summary>GET /api/marketing/promotions?state=active|scheduled|expired|inactive|used_up</summary>
    [HttpGet("promotions")]
    public Task<IReadOnlyList<PromotionListItem>> Promotions([FromQuery] string? search, [FromQuery] string? state, CancellationToken ct)
        => marketing.ListPromotionsAsync(search, state, ct);

    [HttpPost("promotions")]
    [HasPermission(Permissions.Marketing.Create)]
    public async Task<IActionResult> CreatePromotion(SavePromotionRequest request, CancellationToken ct) => FromResult(await marketing.CreatePromotionAsync(request, ct), Ok);

    [HttpPut("promotions/{id:long}")]
    [HasPermission(Permissions.Marketing.Edit)]
    public async Task<IActionResult> UpdatePromotion(long id, SavePromotionRequest request, CancellationToken ct)
        => FromResult(await marketing.UpdatePromotionAsync(id, request, ct), Ok);

    /// <summary>GET /api/marketing/segments?segment=vip|loyal|new|at_risk|one_time&amp;search=</summary>
    [HttpGet("segments")]
    public Task<SegmentPage> Segments([FromQuery] string? segment, [FromQuery] string? search, [FromQuery] int page = 1, [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
        => marketing.SegmentsAsync(segment, search, page, pageSize, ct);
}

/// <summary>Cài đặt hệ thống của công ty.</summary>
[Route("api/settings")]
[HasPermission(Permissions.Settings.View)]
public sealed class SettingsController(ISettingsService settings) : ApiControllerBase
{
    [HttpGet("company")]
    public Task<CompanyInfoDto> Company(CancellationToken ct) => settings.GetCompanyAsync(ct);

    [HttpPut("company")]
    [HasPermission(Permissions.Settings.Edit)]
    public async Task<IActionResult> UpdateCompany(CompanyInfoDto request, CancellationToken ct) => FromResult(await settings.UpdateCompanyAsync(request, ct), Ok);

    [HttpGet("departments")]
    public Task<IReadOnlyList<DepartmentDto>> Departments(CancellationToken ct) => settings.DepartmentsAsync(ct);

    [HttpPost("departments")]
    [HasPermission(Permissions.Settings.Edit)]
    public async Task<IActionResult> CreateDepartment(SaveDepartmentRequest request, CancellationToken ct) => FromResult(await settings.SaveDepartmentAsync(null, request, ct), Ok);

    [HttpPut("departments/{id:long}")]
    [HasPermission(Permissions.Settings.Edit)]
    public async Task<IActionResult> UpdateDepartment(long id, SaveDepartmentRequest request, CancellationToken ct)
        => FromResult(await settings.SaveDepartmentAsync(id, request, ct), Ok);

    [HttpGet("warehouses")]
    public Task<IReadOnlyList<WarehouseDto>> Warehouses(CancellationToken ct) => settings.WarehousesAsync(ct);

    [HttpPost("warehouses")]
    [HasPermission(Permissions.Settings.Edit)]
    public async Task<IActionResult> CreateWarehouse(SaveWarehouseRequest request, CancellationToken ct) => FromResult(await settings.SaveWarehouseAsync(null, request, ct), Ok);

    [HttpPut("warehouses/{id:long}")]
    [HasPermission(Permissions.Settings.Edit)]
    public async Task<IActionResult> UpdateWarehouse(long id, SaveWarehouseRequest request, CancellationToken ct)
        => FromResult(await settings.SaveWarehouseAsync(id, request, ct), Ok);

    [HttpGet("apps")]
    public Task<IReadOnlyList<AppToggleDto>> Apps(CancellationToken ct) => settings.AppsAsync(ct);

    [HttpPut("apps/{id:int}")]
    [HasPermission(Permissions.Settings.Edit)]
    public async Task<IActionResult> ToggleApp(int id, ToggleRequest request, CancellationToken ct) => FromResult(await settings.ToggleAppAsync(id, request.IsEnabled, ct), Ok);

    [HttpGet("sequences")]
    public Task<IReadOnlyList<SequenceDto>> Sequences(CancellationToken ct) => settings.SequencesAsync(ct);

    [HttpPut("sequences/{id:long}")]
    [HasPermission(Permissions.Settings.Edit)]
    public async Task<IActionResult> UpdateSequence(long id, SaveSequenceRequest request, CancellationToken ct)
        => FromResult(await settings.SaveSequenceAsync(id, request, ct), Ok);
}

/// <summary>Thông tin công ty để in lên báo giá / chứng từ - mọi người đã đăng nhập đều xem được.</summary>
[Route("api/company-info")]
public sealed class CompanyInfoController(ISettingsService settings) : ApiControllerBase
{
    [HttpGet]
    public Task<CompanyInfoDto> Get(CancellationToken ct) => settings.GetCompanyAsync(ct);
}
