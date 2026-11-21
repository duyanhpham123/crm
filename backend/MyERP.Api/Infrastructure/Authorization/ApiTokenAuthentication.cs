using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MyERP.Api.Data;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Infrastructure.Authorization;

/// <summary>
/// Khóa truy cập cá nhân: header "Authorization: Bearer erp_...". Request mang danh tính và quyền của chủ khóa
/// (giống đăng nhập), dùng cho trợ lý AI qua MCP. Khóa không được dùng để quản lý người dùng / vai trò / khóa khác
/// (xem ApiTokenRestrictionMiddleware).
/// </summary>
public static class ApiTokenDefaults
{
    public const string Scheme = "ApiToken";
    /// <summary>Scheme mặc định: khóa "erp_..." đi tới ApiToken, còn lại là JWT đăng nhập.</summary>
    public const string Selector = "Bearer-or-ApiToken";
    public const string TokenIdClaim = "api_token_id";

    public static bool IsApiTokenHeader(string? authorization)
        => authorization is not null && authorization.StartsWith("Bearer " + ApiToken.TokenPrefix, StringComparison.Ordinal);

    public static bool IsApiTokenUser(ClaimsPrincipal? user) => user?.Identity?.AuthenticationType == Scheme;

    public static string SelectScheme(HttpContext ctx)
        => IsApiTokenHeader(ctx.Request.Headers.Authorization.ToString()) ? Scheme : JwtBearerDefaults.AuthenticationScheme;
}

public sealed class ApiTokenAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder, AppDbContext db, TimeProvider clock)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    private static readonly TimeSpan TouchEvery = TimeSpan.FromMinutes(5);

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (!ApiTokenDefaults.IsApiTokenHeader(header)) return AuthenticateResult.NoResult();
        var raw = header["Bearer ".Length..].Trim();
        if (raw.Length > 100) return AuthenticateResult.Fail("Khóa truy cập không hợp lệ.");
        var now = clock.GetUtcNow().UtcDateTime;
        var hash = ApiToken.Hash(raw);

        // Chưa biết công ty nào nên bỏ bộ lọc công ty khi tra khóa
        var row = await (from t in db.ApiTokens.IgnoreQueryFilters()
                         join u in db.Users.IgnoreQueryFilters() on t.UserId equals u.Id
                         where t.TokenHash == hash
                         select new { Token = t, u.UserName, u.FullName, u.IsActive, u.IsDeleted, u.LockoutEnd })
                        .FirstOrDefaultAsync(Context.RequestAborted);
        if (row is null || !row.Token.IsActive(now)) return AuthenticateResult.Fail("Khóa truy cập sai, đã thu hồi hoặc hết hạn.");
        if (!row.IsActive || row.IsDeleted || row.LockoutEnd > clock.GetUtcNow()) return AuthenticateResult.Fail("Tài khoản chủ khóa đang bị khóa.");
        var membership = await db.UserCompanies.IgnoreQueryFilters().AsNoTracking()
            .FirstOrDefaultAsync(m => m.UserId == row.Token.UserId && m.CompanyId == row.Token.CompanyId, Context.RequestAborted);
        if (membership is null) return AuthenticateResult.Fail("Chủ khóa không còn thuộc công ty này.");

        if (row.Token.LastUsedAt is null || now - row.Token.LastUsedAt > TouchEvery)
        {
            var ip = Context.Connection.RemoteIpAddress?.ToString();
            await db.ApiTokens.IgnoreQueryFilters().Where(t => t.Id == row.Token.Id)
                .ExecuteUpdateAsync(s => s.SetProperty(t => t.LastUsedAt, now).SetProperty(t => t.LastUsedIp, ip), Context.RequestAborted);
        }

        var claims = new List<Claim>
        {
            new(ErpClaims.UserId, row.Token.UserId.ToString()),
            new(ErpClaims.UserName, row.UserName),
            new(ErpClaims.FullName, row.FullName),
            new(ErpClaims.CompanyId, membership.CompanyId.ToString()),
            new(ApiTokenDefaults.TokenIdClaim, row.Token.Id.ToString()),
        };
        if (membership.BranchId is { } branch) claims.Add(new(ErpClaims.BranchId, branch.ToString()));
        if (membership.DepartmentId is { } dept) claims.Add(new(ErpClaims.DepartmentId, dept.ToString()));
        var identity = new ClaimsIdentity(claims, ApiTokenDefaults.Scheme, ErpClaims.UserName, null);
        return AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), ApiTokenDefaults.Scheme));
    }
}

/// <summary>
/// Khóa truy cập (AI) KHÔNG được: quản lý người dùng, vai trò & quyền, khóa truy cập, đổi mật khẩu.
/// Những việc này phải đăng nhập bằng mật khẩu trên giao diện ERP.
/// </summary>
public sealed class ApiTokenRestrictionMiddleware(RequestDelegate next)
{
    private static readonly string[] Blocked = ["/api/users", "/api/roles", "/api/me/api-tokens", "/api/me/change-password", "/api/auth"];

    public async Task InvokeAsync(HttpContext ctx)
    {
        if (ApiTokenDefaults.IsApiTokenUser(ctx.User) && Blocked.Any(b => ctx.Request.Path.StartsWithSegments(b, StringComparison.OrdinalIgnoreCase)))
        {
            ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
            ctx.Response.ContentType = "application/problem+json";
            await ctx.Response.WriteAsync("""{"title":"Khóa truy cập (AI) không được dùng cho tài khoản, vai trò và khóa truy cập. Hãy đăng nhập ERP để làm việc này.","status":403}""");
            return;
        }
        await next(ctx);
    }
}
