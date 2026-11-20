using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Crm;

namespace MyERP.Api.Controllers.Crm;

/// <summary>
/// CRM - Lead (khách hàng tiềm năng). Controller chỉ nhận request và trả JSON;
/// toàn bộ nghiệp vụ nằm trong LeadService.
/// </summary>
[Route("api/crm/leads")]
[HasPermission(Permissions.Crm.View)]
public sealed class LeadsController(ILeadService leads) : ApiControllerBase
{
    /// <summary>GET /api/crm/leads?search=&amp;status=&amp;page=1&amp;pageSize=20</summary>
    [HttpGet]
    public Task<PagedResult<LeadListItem>> List([FromQuery] string? search, [FromQuery] string? status,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => leads.ListAsync(new LeadQuery(search, status, page, pageSize), ct);

    /// <summary>GET /api/crm/leads/5</summary>
    [HttpGet("{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct)
        => FromResult(await leads.GetAsync(id, ct), Ok);

    /// <summary>POST /api/crm/leads</summary>
    [HttpPost]
    [HasPermission(Permissions.Crm.Create)]
    public async Task<IActionResult> Create(SaveLeadRequest request, CancellationToken ct)
        => FromResult(await leads.CreateAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    /// <summary>PUT /api/crm/leads/5</summary>
    [HttpPut("{id:long}")]
    [HasPermission(Permissions.Crm.Edit)]
    public async Task<IActionResult> Update(long id, SaveLeadRequest request, CancellationToken ct)
        => FromResult(await leads.UpdateAsync(id, request, ct), Ok);

    /// <summary>POST /api/crm/leads/5/status</summary>
    [HttpPost("{id:long}/status")]
    [HasPermission(Permissions.Crm.Edit)]
    public async Task<IActionResult> ChangeStatus(long id, ChangeLeadStatusRequest request, CancellationToken ct)
        => FromResult(await leads.ChangeStatusAsync(id, request, ct), Ok);

    /// <summary>POST /api/crm/leads/5/convert - chuyển lead thành khách hàng (+ cơ hội).</summary>
    [HttpPost("{id:long}/convert")]
    [HasPermission(Permissions.Crm.Edit)]
    [HasPermission(Permissions.Crm.Create)]
    public async Task<IActionResult> Convert(long id, ConvertLeadRequest request, CancellationToken ct)
        => FromResult(await leads.ConvertAsync(id, request, ct), Ok);

    /// <summary>DELETE /api/crm/leads/5 (xóa mềm)</summary>
    [HttpDelete("{id:long}")]
    [HasPermission(Permissions.Crm.Delete)]
    public async Task<IActionResult> Delete(long id, CancellationToken ct)
        => FromResult(await leads.DeleteAsync(id, ct), NoContent);
}
