using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MyERP.Api.Data;
using MyERP.Api.Models.Entities.Website;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Infrastructure.Authorization;

/// <summary>
/// Xác thực website tự code (Next.js...) bằng khóa API gửi trong header "X-Site-Key".
/// Hợp lệ thì request mang danh tính tài khoản bot của website: có company_id (bộ lọc công ty chạy như bình thường)
/// và site_id, nhưng không có vai trò nào nên không gọi được API quản trị.
/// Chỉ áp cho controller ghi rõ [Authorize(AuthenticationSchemes = SiteKeyDefaults.Scheme)] - các API khác vẫn dùng JWT.
/// </summary>
public static class SiteKeyDefaults
{
    public const string Scheme = "SiteKey";
    public const string Header = "X-Site-Key";
    /// <summary>Website chuyển tiếp IP thật của khách (request đến từ máy chủ Next.js) - dùng giới hạn số lần gửi form.</summary>
    public const string ClientIpHeader = "X-Client-IP";
    public const string SiteIdClaim = "site_id";
}

public sealed class SiteKeyAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder, AppDbContext db)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue(SiteKeyDefaults.Header, out var values) || string.IsNullOrWhiteSpace(values.ToString()))
            return AuthenticateResult.NoResult();
        var raw = values.ToString().Trim();
        if (!raw.StartsWith(Site.KeyPrefix, StringComparison.Ordinal) || raw.Length > 100) return AuthenticateResult.Fail("Khóa website không hợp lệ.");

        var hash = Site.HashKey(raw);
        // Chưa biết công ty nào nên bỏ bộ lọc công ty khi tra khóa
        var site = await db.Sites.IgnoreQueryFilters().AsNoTracking()
            .Where(s => s.ApiKeyHash == hash)
            .Select(s => new { s.Id, s.CompanyId, s.BotUserId, s.IsActive })
            .FirstOrDefaultAsync(Context.RequestAborted);
        if (site is null) return AuthenticateResult.Fail("Khóa website không đúng hoặc đã bị thay.");
        if (!site.IsActive) return AuthenticateResult.Fail("Website đang tắt trong ERP.");
        if (site.BotUserId is null) return AuthenticateResult.Fail("Website chưa có tài khoản ghi đơn.");

        var identity = new ClaimsIdentity(
        [
            new Claim(ErpClaims.UserId, site.BotUserId.Value.ToString()),
            new Claim(ErpClaims.CompanyId, site.CompanyId.ToString()),
            new Claim(SiteKeyDefaults.SiteIdClaim, site.Id.ToString()),
            new Claim(ErpClaims.UserName, $"website-{site.Id}"),
        ], SiteKeyDefaults.Scheme);
        return AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), SiteKeyDefaults.Scheme));
    }

    protected override Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        Response.StatusCode = StatusCodes.Status401Unauthorized;
        Response.ContentType = "application/problem+json";
        return Response.WriteAsync("""{"title":"Thiếu hoặc sai khóa website (header X-Site-Key).","status":401}""");
    }
}
