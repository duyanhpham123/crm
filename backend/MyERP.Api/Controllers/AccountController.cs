using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using MyERP.Api.Infrastructure;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Auth;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Controllers;

/// <summary>Thông tin và thao tác của chính người dùng đang đăng nhập.</summary>
[Route("api")]
public sealed class AccountController(IAccountService account, IAuthService auth, ICurrentUser currentUser) : ApiControllerBase
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

    /// <summary>POST /api/me/change-password - tự đổi mật khẩu, trả cặp token mới.</summary>
    [HttpPost("me/change-password")]
    [EnableRateLimiting(ServiceRegistration.AuthRateLimitPolicy)]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest request, CancellationToken ct)
        => FromResult(await auth.ChangePasswordAsync(currentUser.RequireUserId(), request,
            new ClientInfo(HttpContext.Connection.RemoteIpAddress?.ToString(), Request.Headers.UserAgent.ToString()), ct), Ok);
}
