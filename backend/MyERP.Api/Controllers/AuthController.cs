using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using MyERP.Api.Infrastructure;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Auth;

namespace MyERP.Api.Controllers;

/// <summary>Đăng nhập, làm mới token, đăng xuất, thiết lập lần đầu.</summary>
[Route("api/auth")]
[AllowAnonymous]
public sealed class AuthController(IAuthService auth, IConfiguration config) : ApiControllerBase
{
    /// <summary>GET /api/auth/setup-status - hệ thống đã đặt mật khẩu admin chưa.</summary>
    [HttpGet("setup-status")]
    public Task<SetupStatusResponse> SetupStatus(CancellationToken ct) => auth.GetSetupStatusAsync(ct);

    /// <summary>POST /api/auth/setup - đặt mật khẩu admin lần đầu (chỉ khi Setup:Enabled = true).</summary>
    [HttpPost("setup")]
    [EnableRateLimiting(ServiceRegistration.AuthRateLimitPolicy)]
    public async Task<IActionResult> Setup(SetupAdminRequest request, CancellationToken ct)
    {
        if (!config.GetValue("Setup:Enabled", false))
            return Problem(statusCode: 403, title: "Chức năng thiết lập lần đầu đang tắt (Setup:Enabled).");
        return FromResult(await auth.SetupAdminAsync(request, ct), NoContent);
    }

    /// <summary>POST /api/auth/login - trả access token + refresh token.</summary>
    [HttpPost("login")]
    [EnableRateLimiting(ServiceRegistration.AuthRateLimitPolicy)]
    public async Task<IActionResult> Login(LoginRequest request, CancellationToken ct)
        => FromResult(await auth.LoginAsync(request, Client(), ct), Ok);

    /// <summary>POST /api/auth/refresh - đổi refresh token lấy cặp token mới.</summary>
    [HttpPost("refresh")]
    [EnableRateLimiting(ServiceRegistration.AuthRateLimitPolicy)]
    public async Task<IActionResult> Refresh(RefreshRequest request, CancellationToken ct)
        => FromResult(await auth.RefreshAsync(request, Client(), ct), Ok);

    /// <summary>POST /api/auth/logout - thu hồi refresh token.</summary>
    [HttpPost("logout")]
    public async Task<IActionResult> Logout(RefreshRequest request, CancellationToken ct)
    {
        await auth.LogoutAsync(request, Client(), ct);
        return NoContent();
    }

    private ClientInfo Client() => new(HttpContext.Connection.RemoteIpAddress?.ToString(), Request.Headers.UserAgent.ToString());
}
