using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Auth;

public sealed record ApiTokenDto(long Id, string Name, string Prefix, DateTime CreatedAt, DateTime? ExpiresAt, DateTime? LastUsedAt,
    string? LastUsedIp, bool IsActive);

public sealed record CreateApiTokenRequest(string Name, int? ExpiresInDays);

/// <summary>Khóa gốc chỉ trả về đúng 1 lần này.</summary>
public sealed record CreatedApiToken(ApiTokenDto Info, string Token);

public interface IApiTokenService
{
    Task<IReadOnlyList<ApiTokenDto>> ListMineAsync(CancellationToken ct);
    Task<Result<CreatedApiToken>> CreateAsync(CreateApiTokenRequest request, CancellationToken ct);
    Task<Result> RevokeAsync(long id, CancellationToken ct);
}

/// <summary>Người dùng tự quản lý khóa truy cập của mình (cho trợ lý AI). Khóa có quyền đúng bằng chủ khóa.</summary>
public sealed class ApiTokenService(AppDbContext db, ICurrentUser currentUser, TimeProvider clock) : IApiTokenService
{
    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    private static ApiTokenDto ToDto(ApiToken t, DateTime now) => new(t.Id, t.Name, t.Prefix, t.CreatedAt, t.ExpiresAt, t.LastUsedAt, t.LastUsedIp, t.IsActive(now));

    public async Task<IReadOnlyList<ApiTokenDto>> ListMineAsync(CancellationToken ct)
    {
        var me = currentUser.RequireUserId();
        var now = Now;
        var list = await db.ApiTokens.AsNoTracking().Where(t => t.UserId == me).OrderByDescending(t => t.Id).Take(50).ToListAsync(ct);
        return list.Select(t => ToDto(t, now)).ToList();
    }

    public async Task<Result<CreatedApiToken>> CreateAsync(CreateApiTokenRequest r, CancellationToken ct)
    {
        var me = currentUser.RequireUserId();
        var now = Now;
        var active = await db.ApiTokens.CountAsync(t => t.UserId == me && t.RevokedAt == null && (t.ExpiresAt == null || t.ExpiresAt > now), ct);
        if (active >= ApiToken.MaxActivePerUser) return Error.Validation("token.limit", $"Tối đa {ApiToken.MaxActivePerUser} khóa đang dùng - thu hồi khóa cũ trước.");
        var issued = ApiToken.Issue(me, currentUser.RequireCompanyId(), r.Name, r.ExpiresInDays, now);
        if (issued.IsFailure) return issued.Error!;
        db.ApiTokens.Add(issued.Value.Token);
        await db.SaveChangesAsync(ct);
        return new CreatedApiToken(ToDto(issued.Value.Token, now), issued.Value.Raw);
    }

    public async Task<Result> RevokeAsync(long id, CancellationToken ct)
    {
        var me = currentUser.RequireUserId();
        var t = await db.ApiTokens.FirstOrDefaultAsync(x => x.Id == id && x.UserId == me, ct);
        if (t is null) return Error.NotFound("khóa truy cập");
        t.Revoke(Now);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }
}
