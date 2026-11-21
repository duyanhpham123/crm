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
    /// <summary>GET /api/reports/dashboard?days=30 - doanh thu, lãi gộp, kênh bán, sản phẩm bán chạy, tồn kho.</summary>
    [HttpGet("dashboard")]
    public Task<Dashboard> Dashboard([FromQuery] int days = 30, CancellationToken ct = default) => reports.GetDashboardAsync(days, ct);
}
