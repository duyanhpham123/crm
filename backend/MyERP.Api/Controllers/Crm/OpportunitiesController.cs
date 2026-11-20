using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Crm;

namespace MyERP.Api.Controllers.Crm;

/// <summary>CRM - Cơ hội bán hàng (Kanban theo giai đoạn).</summary>
[Route("api/crm/opportunities")]
[HasPermission(Permissions.Crm.View)]
public sealed class OpportunitiesController(IOpportunityService opportunities) : ApiControllerBase
{
    /// <summary>GET /api/crm/opportunities/board?pipelineId=&amp;search=&amp;ownerId= - dữ liệu Kanban.</summary>
    [HttpGet("board")]
    public async Task<IActionResult> Board([FromQuery] long? pipelineId, [FromQuery] string? search, [FromQuery] long? ownerId, CancellationToken ct)
        => FromResult(await opportunities.GetBoardAsync(pipelineId, search, ownerId, ct), Ok);

    /// <summary>GET /api/crm/opportunities/5</summary>
    [HttpGet("{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct) => FromResult(await opportunities.GetAsync(id, ct), Ok);

    /// <summary>POST /api/crm/opportunities</summary>
    [HttpPost]
    [HasPermission(Permissions.Crm.Create)]
    public async Task<IActionResult> Create(SaveOpportunityRequest request, CancellationToken ct)
        => FromResult(await opportunities.CreateAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    /// <summary>PUT /api/crm/opportunities/5</summary>
    [HttpPut("{id:long}")]
    [HasPermission(Permissions.Crm.Edit)]
    public async Task<IActionResult> Update(long id, SaveOpportunityRequest request, CancellationToken ct)
        => FromResult(await opportunities.UpdateAsync(id, request, ct), Ok);

    /// <summary>POST /api/crm/opportunities/5/stage  body: { stageId, lostReasonId, lostNote }</summary>
    [HttpPost("{id:long}/stage")]
    [HasPermission(Permissions.Crm.Edit)]
    public async Task<IActionResult> MoveStage(long id, MoveStageRequest request, CancellationToken ct)
        => FromResult(await opportunities.MoveStageAsync(id, request, ct), Ok);

    /// <summary>DELETE /api/crm/opportunities/5 (xóa mềm; không xóa cơ hội đã thành công)</summary>
    [HttpDelete("{id:long}")]
    [HasPermission(Permissions.Crm.Delete)]
    public async Task<IActionResult> Delete(long id, CancellationToken ct) => FromResult(await opportunities.DeleteAsync(id, ct), NoContent);
}
