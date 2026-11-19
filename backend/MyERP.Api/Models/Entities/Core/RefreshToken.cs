namespace MyERP.Api.Models.Entities.Core;

/// <summary>Bảng core.RefreshTokens - chỉ lưu SHA-256 của token, không lưu token gốc.</summary>
public sealed class RefreshToken
{
    private RefreshToken() { }

    public long Id { get; private set; }
    public long UserId { get; private set; }
    public string TokenHash { get; private set; } = "";
    public DateTime ExpiresAt { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public string? CreatedByIp { get; private set; }
    public string? UserAgent { get; private set; }
    public DateTime? RevokedAt { get; private set; }
    public string? RevokedByIp { get; private set; }
    public string? ReplacedByTokenHash { get; private set; }

    public bool IsActive(DateTime nowUtc) => RevokedAt is null && ExpiresAt > nowUtc;

    public static RefreshToken Issue(long userId, string tokenHash, DateTime nowUtc, TimeSpan lifetime, string? ip, string? userAgent) => new()
    {
        UserId = userId,
        TokenHash = tokenHash,
        CreatedAt = nowUtc,
        ExpiresAt = nowUtc.Add(lifetime),
        CreatedByIp = ip,
        UserAgent = userAgent?.Length > 500 ? userAgent[..500] : userAgent
    };

    public void Revoke(DateTime nowUtc, string? ip, string? replacedByHash = null)
    {
        RevokedAt ??= nowUtc;
        RevokedByIp ??= ip;
        ReplacedByTokenHash ??= replacedByHash;
    }
}
