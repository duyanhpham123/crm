using Microsoft.EntityFrameworkCore;
using MyERP.Api.Data;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Auth;

public interface IAccountService
{
    Task<MeResponse?> GetMeAsync(CancellationToken ct);
    Task<IReadOnlyList<AppDto>> GetMyAppsAsync(CancellationToken ct);
}

public sealed class AccountService(AppDbContext db, ICurrentUser currentUser, IPermissionService permissions) : IAccountService
{
    public async Task<MeResponse?> GetMeAsync(CancellationToken ct)
    {
        var userId = currentUser.RequireUserId();
        var companyId = currentUser.RequireCompanyId();

        var info = await (from u in db.Users
                          from c in db.Companies.Where(c => c.Id == companyId)
                          where u.Id == userId
                          select new { u.UserName, u.FullName, CompanyName = c.Name })
                         .AsNoTracking().FirstOrDefaultAsync(ct);
        if (info is null) return null;

        var granted = await permissions.GetPermissionsAsync(userId, companyId, ct);
        return new MeResponse(userId, info.UserName, info.FullName, companyId, info.CompanyName, granted.Keys.Order().ToList());
    }

    /// <summary>Ứng dụng hiện trên màn hình lưới: công ty đã bật + người dùng có quyền xem.</summary>
    public async Task<IReadOnlyList<AppDto>> GetMyAppsAsync(CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        var granted = await permissions.GetPermissionsAsync(currentUser.RequireUserId(), companyId, ct);

        var apps = await (from a in db.Apps
                          join ca in db.CompanyApps on a.Id equals ca.AppId
                          where ca.CompanyId == companyId && ca.IsEnabled && a.IsEnabled
                          orderby a.SortOrder
                          select new AppDto(a.Code, a.Name, a.Icon, a.Color, a.Route))
                         .AsNoTracking().ToListAsync(ct);

        return apps.Where(a => granted.ContainsKey(Permissions.AppView(a.Code))).ToList();
    }
}
