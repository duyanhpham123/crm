using System.Security.Cryptography;
using System.Text;
using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Core;

/// <summary>
/// core.ApiTokens - khóa truy cập cá nhân: phần mềm khác (VD trợ lý AI qua MCP) gọi API thay mặt người dùng,
/// với đúng quyền của người đó. Chỉ lưu SHA-256; khóa gốc trả về 1 lần lúc tạo.
/// </summary>
public sealed class ApiToken
{
    public const string TokenPrefix = "erp_";
    public const int MaxActivePerUser = 10;
    public static readonly int[] AllowedDays = [7, 30, 90, 365];

    private ApiToken() { }
    public long Id { get; private set; }
    public long UserId { get; private set; }
    public long CompanyId { get; private set; }
    public string Name { get; private set; } = "";
    public string TokenHash { get; private set; } = "";
    public string Prefix { get; private set; } = "";
    public DateTime CreatedAt { get; private set; }
    public DateTime? ExpiresAt { get; private set; }
    public DateTime? LastUsedAt { get; private set; }
    public string? LastUsedIp { get; private set; }
    public DateTime? RevokedAt { get; private set; }

    public bool IsActive(DateTime nowUtc) => RevokedAt is null && (ExpiresAt is null || ExpiresAt > nowUtc);

    /// <summary>Tạo khóa mới; trả về (bản ghi, khóa gốc). expiresInDays null = không hết hạn.</summary>
    public static Result<(ApiToken Token, string Raw)> Issue(long userId, long companyId, string name, int? expiresInDays, DateTime nowUtc)
    {
        var n = (name ?? "").Trim();
        if (n.Length is < 2 or > 100) return Error.Validation("token.name", "Đặt tên khóa (2-100 ký tự), VD \"Claude Desktop - máy văn phòng\".");
        if (expiresInDays is { } d && !AllowedDays.Contains(d)) return Error.Validation("token.expiry", "Thời hạn chỉ chọn 7, 30, 90 hoặc 365 ngày.");
        var raw = TokenPrefix + RandomToken(40);
        return (new ApiToken
        {
            UserId = userId, CompanyId = companyId, Name = n, TokenHash = Hash(raw), Prefix = raw[..10], CreatedAt = nowUtc,
            ExpiresAt = expiresInDays is { } days ? nowUtc.AddDays(days) : null,
        }, raw);
    }

    public void Revoke(DateTime nowUtc) => RevokedAt ??= nowUtc;

    public void Touch(DateTime nowUtc, string? ip) { LastUsedAt = nowUtc; LastUsedIp = ip?.Length > 45 ? ip[..45] : ip; }

    public static string Hash(string raw) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(raw))).ToLowerInvariant();

    private static string RandomToken(int length)
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
        var bytes = RandomNumberGenerator.GetBytes(length);
        var sb = new StringBuilder(length);
        foreach (var b in bytes) sb.Append(chars[b % chars.Length]);
        return sb.ToString();
    }
}
