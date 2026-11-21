using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using MyERP.Api.Infrastructure;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Auth;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Controllers;

/// <summary>Thông tin và thao tác của chính người dùng đang đăng nhập.</summary>
[Route("api")]
public sealed class AccountController(IAccountService account, IAuthService auth, ICurrentUser currentUser, IApiTokenService apiTokens) : ApiControllerBase
{
    /// <summary>GET /api/me - tên, công ty, danh sách quyền (frontend dùng để ẩn/hiện nút).</summary>
    [HttpGet("me")]
    public async Task<ActionResult<MeResponse>> Me(CancellationToken ct)
    {
        var me = await account.GetMeAsync(ct);
        if (me is null) return Unauthorized();
        return me;
    }

    /// <summary>GET /api/apps - ứng dụng hiện trên màn hình lưới.</summary>
    [HttpGet("apps")]
    public Task<IReadOnlyList<AppDto>> Apps(CancellationToken ct) => account.GetMyAppsAsync(ct);

    // ----- Khóa truy cập cá nhân (cho trợ lý AI qua MCP) - phải đăng nhập bằng mật khẩu, không dùng khóa để tạo khóa -----

    /// <summary>GET /api/me/api-tokens - các khóa của chính mình.</summary>
    [HttpGet("me/api-tokens")]
    public Task<IReadOnlyList<ApiTokenDto>> ApiTokens(CancellationToken ct) => apiTokens.ListMineAsync(ct);

    /// <summary>POST /api/me/api-tokens  body: { name, expiresInDays: 7|30|90|365|null } - khóa gốc chỉ trả về 1 lần.</summary>
    [HttpPost("me/api-tokens")]
    public async Task<IActionResult> CreateApiToken(CreateApiTokenRequest request, CancellationToken ct) => FromResult(await apiTokens.CreateAsync(request, ct), Ok);

    /// <summary>GET /api/me/ai-setup - đường dẫn MCP server trên máy chạy ERP (để trang Kết nối AI ghi sẵn lệnh cài).</summary>
    [HttpGet("me/ai-setup")]
    public IActionResult AiSetup([FromServices] IWebHostEnvironment env)
    {
        // Thư mục dự án có mcp/server.js: dò ngược từ thư mục chạy backend (backend/MyERP.Api -> ... -> mcp/)
        string? mcpDir = null;
        for (var dir = new DirectoryInfo(env.ContentRootPath); dir is not null && mcpDir is null; dir = dir.Parent)
            if (System.IO.File.Exists(Path.Combine(dir.FullName, "mcp", "server.js"))) mcpDir = Path.Combine(dir.FullName, "mcp");
        return Ok(new { mcpDir });
    }

    [HttpDelete("me/api-tokens/{id:long}")]
    public async Task<IActionResult> RevokeApiToken(long id, CancellationToken ct) => FromResult(await apiTokens.RevokeAsync(id, ct), NoContent);

    /// <summary>POST /api/me/change-password - tự đổi mật khẩu, trả cặp token mới.</summary>
    [HttpPost("me/change-password")]
    [EnableRateLimiting(ServiceRegistration.AuthRateLimitPolicy)]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest request, CancellationToken ct)
        => FromResult(await auth.ChangePasswordAsync(currentUser.RequireUserId(), request,
            new ClientInfo(HttpContext.Connection.RemoteIpAddress?.ToString(), Request.Headers.UserAgent.ToString()), ct), Ok);
}
