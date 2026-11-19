using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Auth;

/// <summary>Cấu hình JWT - đọc từ mục "Jwt" trong appsettings.json.</summary>
public sealed class JwtOptions
{
    public const string Section = "Jwt";
    public string Issuer { get; set; } = "MyERP";
    public string Audience { get; set; } = "MyERP";
    public string SigningKey { get; set; } = "";
    public int AccessTokenMinutes { get; set; } = 30;
    public int RefreshTokenDays { get; set; } = 14;

    public SymmetricSecurityKey GetSigningKey()
    {
        var bytes = Encoding.UTF8.GetBytes(SigningKey);
        if (bytes.Length < 32)
            throw new InvalidOperationException("Jwt:SigningKey phải dài ít nhất 32 byte. Đặt qua user-secrets hoặc biến môi trường.");
        return new SymmetricSecurityKey(bytes);
    }
}

public sealed class TokenService(IOptions<JwtOptions> options, TimeProvider clock)
{
    private readonly JwtOptions _options = options.Value;

    public (string Token, DateTime ExpiresAt) CreateAccessToken(User user, UserCompany membership)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        var expires = now.AddMinutes(_options.AccessTokenMinutes);

        var claims = new List<Claim>
        {
            new(ErpClaims.UserId, user.Id.ToString()),
            new(ErpClaims.UserName, user.UserName),
            new(ErpClaims.FullName, user.FullName),
            new(ErpClaims.CompanyId, membership.CompanyId.ToString()),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString("N"))
        };
        if (membership.BranchId is { } branch) claims.Add(new(ErpClaims.BranchId, branch.ToString()));
        if (membership.DepartmentId is { } dept) claims.Add(new(ErpClaims.DepartmentId, dept.ToString()));

        var credentials = new SigningCredentials(_options.GetSigningKey(), SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(_options.Issuer, _options.Audience, claims, now, expires, credentials);
        return (new JwtSecurityTokenHandler().WriteToken(token), expires);
    }

    /// <summary>Refresh token ngẫu nhiên 512 bit; DB chỉ lưu SHA-256 của nó.</summary>
    public static (string Token, string Hash) CreateRefreshToken()
    {
        var token = Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(64));
        return (token, Hash(token));
    }

    public static string Hash(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
}
