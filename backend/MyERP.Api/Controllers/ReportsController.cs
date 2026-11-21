using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Reports;

namespace MyERP.Api.Controllers;

/// <summary>Báo cáo tổng quan kinh doanh.</summary>
[Route("api/reports")]
[HasPermission(Permissions.Reports.View)]
public sealed class ReportsController(IReportService reports) : ApiControllerBase
{
    /// <summary>
    /// GET /api/reports/dashboard?from=2026-11-01&amp;to=2026-11-21 (khoảng tự chọn) hoặc ?days=30 (N ngày gần nhất)
    /// - doanh thu, lãi gộp, kênh bán, sản phẩm bán chạy, tồn kho; so với kỳ liền trước cùng độ dài.
    /// </summary>
    [HttpGet("dashboard")]
    public async Task<IActionResult> Dashboard([FromQuery] int? days, [FromQuery] DateOnly? from, [FromQuery] DateOnly? to, CancellationToken ct = default)
        => FromResult(await reports.GetDashboardAsync(days, from, to, ct), Ok);
}
