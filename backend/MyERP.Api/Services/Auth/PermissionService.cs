using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using MyERP.Api.Data;
using MyERP.Api.Models;

namespace MyERP.Api.Services.Auth;

public interface IPermissionService
{
    /// <summary>Mã quyền -> phạm vi dữ liệu của người dùng trong một công ty.</summary>
    Task<IReadOnlyDictionary<string, DataScope>> GetPermissionsAsync(long userId, long companyId, CancellationToken ct = default);

    /// <summary>Gọi sau khi đổi vai trò / quyền của người dùng để cập nhật ngay.</summary>
    void Invalidate(long userId, long companyId);
}

/// <summary>
/// Quyền = hợp các vai trò của người dùng; cùng một quyền thì lấy phạm vi rộng nhất.
/// Cache 5 phút để không truy vấn DB ở mỗi request.
/// </summary>
public sealed class PermissionService(AppDbContext db, IMemoryCache cache) : IPermissionService
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(5);

    public async Task<IReadOnlyDictionary<string, DataScope>> GetPermissionsAsync(long userId, long companyId, CancellationToken ct = default)
    {
        var key = CacheKey(userId, companyId);
        if (cache.TryGetValue(key, out IReadOnlyDictionary<string, DataScope>? cached) && cached is not null)
            return cached;

        var isSystemAdmin = await db.Users.AsNoTracking()
            .Where(u => u.Id == userId && u.IsActive)
            .Select(u => (bool?)u.IsSystemAdmin)
            .FirstOrDefaultAsync(ct);

        Dictionary<string, DataScope> result;
        if (isSystemAdmin is null)
        {
            result = [];   // user không tồn tại hoặc đã khóa
        }
        else if (isSystemAdmin.Value)
        {
            result = await db.Permissions.AsNoTracking().ToDictionaryAsync(p => p.Code, _ => DataScope.All, ct);
        }
        else
        {
            var rows = await (
                from ur in db.UserRoles
                join rp in db.RolePermissions on ur.RoleId equals rp.RoleId
                join p in db.Permissions on rp.PermissionId equals p.Id
                join r in db.Roles on ur.RoleId equals r.Id
                where ur.UserId == userId && ur.CompanyId == companyId
                select new { p.Code, rp.DataScope }
            ).AsNoTracking().ToListAsync(ct);

            result = MergeScopes(rows.Select(r => (r.Code, r.DataScope)));
        }

        cache.Set(key, (IReadOnlyDictionary<string, DataScope>)result, CacheDuration);
        return result;
    }

    public void Invalidate(long userId, long companyId) => cache.Remove(CacheKey(userId, companyId));

    public static Dictionary<string, DataScope> MergeScopes(IEnumerable<(string Code, string Scope)> grants)
    {
        var result = new Dictionary<string, DataScope>(StringComparer.Ordinal);
        foreach (var (code, scope) in grants)
        {
            var parsed = DataScopes.Parse(scope);
            result[code] = result.TryGetValue(code, out var existing) ? DataScopes.Widest(existing, parsed) : parsed;
        }
        return result;
    }

    private static string CacheKey(long userId, long companyId) => $"perm:{userId}:{companyId}";
}
