using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Crm;

namespace MyERP.Api.Controllers.Crm;

/// <summary>Danh mục nguồn lead (Facebook, Zalo, Website...).</summary>
[Route("api/crm/lead-sources")]
[HasPermission(Permissions.Crm.View)]
public sealed class LeadSourcesController(ILeadService leads) : ApiControllerBase
{
    /// <summary>GET /api/crm/lead-sources</summary>
    [HttpGet]
    public Task<List<LeadSourceDto>> List(CancellationToken ct) => leads.ListSourcesAsync(ct);
}
