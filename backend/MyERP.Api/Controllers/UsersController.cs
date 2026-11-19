using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Users;

namespace MyERP.Api.Controllers;

/// <summary>Quản lý tài khoản nhân viên (ứng dụng "Người dùng").</summary>
[Route("api/users")]
[HasPermission(Permissions.Users.View)]
public sealed class UsersController(IUserService users) : ApiControllerBase
{
    /// <summary>GET /api/users?search=&amp;departmentId=&amp;roleId=&amp;isActive=&amp;page=1&amp;pageSize=20</summary>
    [HttpGet]
    public Task<PagedResult<UserListItem>> List([FromQuery] string? search, [FromQuery] long? departmentId,
        [FromQuery] long? roleId, [FromQuery] bool? isActive, [FromQuery] int page = 1, [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
        => users.ListAsync(new UserQuery(search, departmentId, roleId, isActive, page, pageSize), ct);

    /// <summary>GET /api/users/form-options - danh sách phòng ban + vai trò cho ô chọn.</summary>
    [HttpGet("form-options")]
    public Task<UserFormOptions> FormOptions(CancellationToken ct) => users.GetFormOptionsAsync(ct);

    /// <summary>GET /api/users/5</summary>
    [HttpGet("{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct)
        => FromResult(await users.GetAsync(id, ct), Ok);

    /// <summary>POST /api/users</summary>
    [HttpPost]
    [HasPermission(Permissions.Users.Create)]
    public async Task<IActionResult> Create(CreateUserRequest request, CancellationToken ct)
        => FromResult(await users.CreateAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    /// <summary>PUT /api/users/5 - sửa thông tin, phòng ban, vai trò.</summary>
    [HttpPut("{id:long}")]
    [HasPermission(Permissions.Users.Edit)]
    public async Task<IActionResult> Update(long id, UpdateUserRequest request, CancellationToken ct)
        => FromResult(await users.UpdateAsync(id, request, ct), Ok);

    /// <summary>POST /api/users/5/reset-password - quản trị viên đặt lại mật khẩu.</summary>
    [HttpPost("{id:long}/reset-password")]
    [HasPermission(Permissions.Users.Edit)]
    public async Task<IActionResult> ResetPassword(long id, ResetPasswordRequest request, CancellationToken ct)
        => FromResult(await users.ResetPasswordAsync(id, request, ct), NoContent);

    /// <summary>POST /api/users/5/status  body: { "isActive": false } - khóa / mở khóa tài khoản.</summary>
    [HttpPost("{id:long}/status")]
    [HasPermission(Permissions.Users.Edit)]
    public async Task<IActionResult> SetStatus(long id, SetUserStatusRequest request, CancellationToken ct)
        => FromResult(await users.SetStatusAsync(id, request, ct), Ok);
}
