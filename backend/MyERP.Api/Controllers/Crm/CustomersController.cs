using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Crm;

namespace MyERP.Api.Controllers.Crm;

/// <summary>CRM - Khách hàng và người liên hệ.</summary>
[Route("api/crm/customers")]
[HasPermission(Permissions.Crm.View)]
public sealed class CustomersController(ICustomerService customers) : ApiControllerBase
{
    /// <summary>GET /api/crm/customers?search=&amp;groupId=&amp;ownerId=&amp;page=1&amp;pageSize=20</summary>
    [HttpGet]
    public Task<PagedResult<CustomerListItem>> List([FromQuery] string? search, [FromQuery] long? groupId, [FromQuery] long? ownerId,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => customers.ListAsync(new CustomerQuery(search, groupId, ownerId, page, pageSize), ct);

    /// <summary>GET /api/crm/customers/5 - thông tin + người liên hệ + cơ hội.</summary>
    [HttpGet("{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct) => FromResult(await customers.GetAsync(id, ct), Ok);

    /// <summary>POST /api/crm/customers</summary>
    [HttpPost]
    [HasPermission(Permissions.Crm.Create)]
    public async Task<IActionResult> Create(SaveCustomerRequest request, CancellationToken ct)
        => FromResult(await customers.CreateAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    /// <summary>PUT /api/crm/customers/5</summary>
    [HttpPut("{id:long}")]
    [HasPermission(Permissions.Crm.Edit)]
    public async Task<IActionResult> Update(long id, SaveCustomerRequest request, CancellationToken ct)
        => FromResult(await customers.UpdateAsync(id, request, ct), Ok);

    /// <summary>DELETE /api/crm/customers/5 (xóa mềm, chặn nếu còn cơ hội đang mở)</summary>
    [HttpDelete("{id:long}")]
    [HasPermission(Permissions.Crm.Delete)]
    public async Task<IActionResult> Delete(long id, CancellationToken ct) => FromResult(await customers.DeleteAsync(id, ct), NoContent);

    /// <summary>POST /api/crm/customers/5/contacts</summary>
    [HttpPost("{id:long}/contacts")]
    [HasPermission(Permissions.Crm.Edit)]
    public async Task<IActionResult> AddContact(long id, SaveContactRequest request, CancellationToken ct)
        => FromResult(await customers.AddContactAsync(id, request, ct), dto => Created($"/api/crm/customers/{id}/contacts/{dto.Id}", dto));

    /// <summary>PUT /api/crm/customers/5/contacts/9</summary>
    [HttpPut("{id:long}/contacts/{contactId:long}")]
    [HasPermission(Permissions.Crm.Edit)]
    public async Task<IActionResult> UpdateContact(long id, long contactId, SaveContactRequest request, CancellationToken ct)
        => FromResult(await customers.UpdateContactAsync(id, contactId, request, ct), Ok);

    /// <summary>DELETE /api/crm/customers/5/contacts/9</summary>
    [HttpDelete("{id:long}/contacts/{contactId:long}")]
    [HasPermission(Permissions.Crm.Edit)]
    public async Task<IActionResult> DeleteContact(long id, long contactId, CancellationToken ct)
        => FromResult(await customers.DeleteContactAsync(id, contactId, ct), NoContent);
}

/// <summary>Danh mục cho các ô chọn trong CRM: nguồn, nhóm khách, pipeline, lý do thất bại, người phụ trách.</summary>
[Route("api/crm/lookups")]
[HasPermission(Permissions.Crm.View)]
public sealed class CrmLookupsController(ICustomerService customers) : ApiControllerBase
{
    /// <summary>GET /api/crm/lookups</summary>
    [HttpGet]
    public Task<CrmLookups> Get(CancellationToken ct) => customers.GetLookupsAsync(ct);
}
