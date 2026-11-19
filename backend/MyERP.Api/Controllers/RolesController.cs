using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Users;

namespace MyERP.Api.Controllers;

/// <summary>Vai trò & quyền (nằm trong ứng dụng "Người dùng", dùng chung mã quyền users.*).</summary>
[Route("api/roles")]
[HasPermission(Permissions.Users.View)]
public sealed class RolesController(IRoleService roles) : ApiControllerBase
{
    /// <summary>GET /api/roles - danh sách vai trò kèm số người dùng, số quyền.</summary>
    [HttpGet]
    public Task<IReadOnlyList<RoleListItem>> List(CancellationToken ct) => roles.ListAsync(ct);

    /// <summary>GET /api/roles/permission-catalog - toàn bộ quyền, nhóm theo ứng dụng (để vẽ ma trận).</summary>
    [HttpGet("permission-catalog")]
    public Task<PermissionCatalog> Catalog(CancellationToken ct) => roles.GetCatalogAsync(ct);

    /// <summary>GET /api/roles/5 - chi tiết vai trò + quyền đang có.</summary>
    [HttpGet("{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct)
        => FromResult(await roles.GetAsync(id, ct), Ok);

    /// <summary>POST /api/roles</summary>
    [HttpPost]
    [HasPermission(Permissions.Users.Create)]
    public async Task<IActionResult> Create(SaveRoleRequest request, CancellationToken ct)
        => FromResult(await roles.CreateAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    /// <summary>PUT /api/roles/5 - sửa tên, mô tả, quyền (gửi kèm rowVersion).</summary>
    [HttpPut("{id:long}")]
    [HasPermission(Permissions.Users.Edit)]
    public async Task<IActionResult> Update(long id, SaveRoleRequest request, CancellationToken ct)
        => FromResult(await roles.UpdateAsync(id, request, ct), Ok);

    /// <summary>DELETE /api/roles/5 - chỉ xóa được khi không còn ai giữ vai trò.</summary>
    [HttpDelete("{id:long}")]
    [HasPermission(Permissions.Users.Delete)]
    public async Task<IActionResult> Delete(long id, CancellationToken ct)
        => FromResult(await roles.DeleteAsync(id, ct), NoContent);
}
