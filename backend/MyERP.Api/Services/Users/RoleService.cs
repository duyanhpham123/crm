using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Services.Auth;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Users;

public interface IRoleService
{
    Task<IReadOnlyList<RoleListItem>> ListAsync(CancellationToken ct);
    Task<Result<RoleDetail>> GetAsync(long id, CancellationToken ct);
    Task<PermissionCatalog> GetCatalogAsync(CancellationToken ct);
    Task<Result<RoleDetail>> CreateAsync(SaveRoleRequest request, CancellationToken ct);
    Task<Result<RoleDetail>> UpdateAsync(long id, SaveRoleRequest request, CancellationToken ct);
    Task<Result> DeleteAsync(long id, CancellationToken ct);
}

/// <summary>
/// Quản lý vai trò và quyền của vai trò.
/// Chốt chặn leo thang đặc quyền (với người không phải quản trị hệ thống):
///  - Không được sửa vai trò mình đang giữ (nếu không, tự cấp thêm quyền cho mình được).
///  - Chỉ được cấp những quyền mình đang có, với phạm vi không rộng hơn của mình.
/// Vai trò hệ thống (admin) chỉ xem, không sửa / xóa.
/// </summary>
public sealed class RoleService(
    AppDbContext db,
    ICurrentUser currentUser,
    IPermissionService permissions,
    TimeProvider clock) : IRoleService
{
    public async Task<IReadOnlyList<RoleListItem>> ListAsync(CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        return await VisibleRoles()
            .OrderBy(r => r.CompanyId == null ? 0 : 1).ThenBy(r => r.Name)
            .Select(r => new RoleListItem(r.Id, r.Code, r.Name, r.Description, r.CompanyId == null,
                db.UserRoles.Count(ur => ur.RoleId == r.Id && ur.CompanyId == companyId),
                r.Permissions.Count))
            .AsNoTracking().ToListAsync(ct);
    }

    public async Task<Result<RoleDetail>> GetAsync(long id, CancellationToken ct)
    {
        var role = await VisibleRoles().Include(r => r.Permissions).AsNoTracking().FirstOrDefaultAsync(r => r.Id == id, ct);
        return role is null ? Error.NotFound("vai trò") : await ToDetailAsync(role, ct);
    }

    public async Task<PermissionCatalog> GetCatalogAsync(CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        var rows = await (from p in db.Permissions
                          join a in db.Apps on p.AppId equals a.Id
                          join ca in db.CompanyApps on a.Id equals ca.AppId
                          where ca.CompanyId == companyId && ca.IsEnabled && a.IsEnabled
                          orderby a.SortOrder, p.Id
                          select new { a.Code, a.Name, a.Icon, a.Color, PermissionId = p.Id, PermissionCode = p.Code, PermissionName = p.Name })
                         .AsNoTracking().ToListAsync(ct);

        var groups = rows.GroupBy(r => new { r.Code, r.Name, r.Icon, r.Color })
            .Select(g => new PermissionGroup(g.Key.Code, g.Key.Name, g.Key.Icon, g.Key.Color,
                g.Select(p =>
                {
                    var action = p.PermissionCode[(g.Key.Code.Length + 1)..];
                    return new PermissionItem(p.PermissionId, p.PermissionCode, action, p.PermissionName,
                        Permissions.StandardActions.Contains(action));
                }).ToList()))
            .ToList();

        return new PermissionCatalog(groups, await IsSystemAdminAsync(ct));
    }

    public async Task<Result<RoleDetail>> CreateAsync(SaveRoleRequest req, CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        if (string.IsNullOrWhiteSpace(req.Code))
            return Error.Validation("role.code_required", "Nhập mã vai trò.");

        var code = req.Code.Trim().ToLowerInvariant();
        if (await db.Roles.IgnoreQueryFilters().AnyAsync(r => (r.CompanyId == companyId || r.CompanyId == null) && r.Code == code, ct))
            return Error.Conflict("role.code_taken", $"Mã vai trò \"{code}\" đã tồn tại.");
        if (await NameTakenAsync(req.Name, null, ct))
            return Error.Conflict("role.name_taken", "Đã có vai trò cùng tên.");

        var grants = await ValidateGrantsAsync(req.Permissions, ct);
        if (grants.IsFailure) return grants.Error!;

        var role = Role.Create(companyId, code, req.Name, req.Description);
        role.SetPermissions(grants.Value);
        db.Roles.Add(role);
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(role, ct);
    }

    public async Task<Result<RoleDetail>> UpdateAsync(long id, SaveRoleRequest req, CancellationToken ct)
    {
        var role = await VisibleRoles().Include(r => r.Permissions).FirstOrDefaultAsync(r => r.Id == id, ct);
        if (role is null) return Error.NotFound("vai trò");

        var guard = await GuardEditableAsync(role, ct);
        if (guard.IsFailure) return guard.Error!;
        if (await NameTakenAsync(req.Name, id, ct))
            return Error.Conflict("role.name_taken", "Đã có vai trò cùng tên.");

        var grants = await ValidateGrantsAsync(req.Permissions, ct);
        if (grants.IsFailure) return grants.Error!;

        if (!string.IsNullOrEmpty(req.RowVersion))
            db.Entry(role).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(req.RowVersion);

        role.Update(req.Name, req.Description);
        role.SetPermissions(grants.Value);
        role.UpdatedAt = clock.GetUtcNow().UtcDateTime;   // luôn ghi dòng Roles để RowVersion được kiểm tra (2 người cùng sửa)

        await db.SaveChangesAsync(ct);
        await InvalidateHoldersAsync(role.Id, ct);         // người giữ vai trò nhận quyền mới ngay
        return await ToDetailAsync(role, ct);
    }

    public async Task<Result> DeleteAsync(long id, CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        var role = await VisibleRoles().FirstOrDefaultAsync(r => r.Id == id, ct);
        if (role is null) return Error.NotFound("vai trò");

        var guard = await GuardEditableAsync(role, ct);
        if (guard.IsFailure) return guard.Error!;

        var holders = await db.UserRoles.CountAsync(ur => ur.RoleId == id && ur.CompanyId == companyId, ct);
        if (holders > 0)
            return Error.Conflict("role.in_use", $"Vai trò đang được gán cho {holders} người dùng. Gỡ vai trò khỏi họ trước khi xóa.");

        db.Roles.Remove(role);   // xóa mềm
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    // ---------- Hàm hỗ trợ ----------

    /// <summary>Vai trò của công ty hiện tại + vai trò hệ thống dùng chung.</summary>
    private IQueryable<Role> VisibleRoles()
    {
        var companyId = currentUser.RequireCompanyId();
        return db.Roles.Where(r => r.CompanyId == companyId || r.CompanyId == null);
    }

    private Task<bool> IsSystemAdminAsync(CancellationToken ct)
    {
        var me = currentUser.RequireUserId();
        return db.Users.AnyAsync(u => u.Id == me && u.IsSystemAdmin, ct);
    }

    private async Task<string?> ReadOnlyReasonAsync(Role role, CancellationToken ct)
    {
        if (role.IsGlobal)
            return "Vai trò hệ thống luôn có toàn quyền, không chỉnh sửa được.";
        if (await IsSystemAdminAsync(ct))
            return null;
        var me = currentUser.RequireUserId();
        if (await db.UserRoles.AnyAsync(ur => ur.UserId == me && ur.RoleId == role.Id, ct))
            return "Bạn đang giữ vai trò này nên không thể tự sửa. Nhờ quản trị viên khác thực hiện.";
        return null;
    }

    private async Task<Result> GuardEditableAsync(Role role, CancellationToken ct)
        => await ReadOnlyReasonAsync(role, ct) is { } reason ? Error.Forbidden(reason) : Result.Success();

    private async Task<bool> NameTakenAsync(string name, long? excludeId, CancellationToken ct)
    {
        var normalized = name.Trim().ToUpperInvariant();
        return await VisibleRoles().AnyAsync(r => r.NormalizedName == normalized && r.Id != excludeId, ct);
    }

    /// <summary>
    /// Kiểm tra danh sách quyền định cấp:
    ///  - Quyền phải tồn tại và thuộc ứng dụng công ty đã bật
    ///  - Có quyền gì của một ứng dụng thì bắt buộc có quyền "Xem" của ứng dụng đó
    ///  - Phạm vi "all" (mọi công ty) chỉ quản trị hệ thống được cấp
    ///  - Người không phải quản trị hệ thống chỉ cấp được quyền mình có, phạm vi không rộng hơn
    /// </summary>
    private async Task<Result<Dictionary<int, string>>> ValidateGrantsAsync(IReadOnlyList<RolePermissionDto> requested, CancellationToken ct)
    {
        var catalog = (await GetCatalogAsync(ct)).Groups;
        var byId = catalog.SelectMany(g => g.Permissions.Select(p => (Group: g, Permission: p))).ToDictionary(x => x.Permission.Id);

        var unknown = requested.Where(r => !byId.ContainsKey(r.PermissionId)).ToList();
        if (unknown.Count > 0)
            return Error.Validation("role.permission_invalid", "Có quyền không tồn tại hoặc thuộc ứng dụng chưa bật.");

        var requestedIds = requested.Select(r => r.PermissionId).ToHashSet();
        var missingView = requested.Select(r => byId[r.PermissionId].Group).Distinct()
            .Where(g => g.Permissions.FirstOrDefault(p => p.Action == "view") is { } view && !requestedIds.Contains(view.Id))
            .Select(g => g.AppName).ToList();
        if (missingView.Count > 0)
            return Error.Validation("role.view_required", $"Phải cấp quyền \"Xem\" cho ứng dụng: {string.Join(", ", missingView)}.");

        var isSystemAdmin = await IsSystemAdminAsync(ct);
        if (!isSystemAdmin && requested.Any(r => r.DataScope == "all"))
            return Error.Forbidden("Chỉ quản trị hệ thống mới cấp được phạm vi \"Tất cả công ty\".");

        if (!isSystemAdmin)
        {
            var mine = await permissions.GetPermissionsAsync(currentUser.RequireUserId(), currentUser.RequireCompanyId(), ct);
            var exceeding = requested
                .Where(r => !mine.TryGetValue(byId[r.PermissionId].Permission.Code, out var myScope) || myScope < DataScopes.Parse(r.DataScope))
                .Select(r => byId[r.PermissionId].Permission.Name)
                .ToList();
            if (exceeding.Count > 0)
                return Error.Forbidden($"Bạn không thể cấp quyền vượt quá quyền của chính mình: {string.Join(", ", exceeding.Take(5))}{(exceeding.Count > 5 ? "..." : "")}.");
        }

        return requested.ToDictionary(r => r.PermissionId, r => r.DataScope);
    }

    private async Task InvalidateHoldersAsync(long roleId, CancellationToken ct)
    {
        var holders = await db.UserRoles.Where(ur => ur.RoleId == roleId).Select(ur => new { ur.UserId, ur.CompanyId }).ToListAsync(ct);
        foreach (var h in holders) permissions.Invalidate(h.UserId, h.CompanyId);
    }

    private async Task<RoleDetail> ToDetailAsync(Role role, CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        var reason = await ReadOnlyReasonAsync(role, ct);
        var userCount = await db.UserRoles.CountAsync(ur => ur.RoleId == role.Id && ur.CompanyId == companyId, ct);
        return new RoleDetail(role.Id, role.Code, role.Name, role.Description, role.IsGlobal, reason is not null, reason, userCount,
            role.Permissions.OrderBy(p => p.PermissionId).Select(p => new RolePermissionDto(p.PermissionId, p.DataScope)).ToList(),
            Convert.ToBase64String(role.RowVersion));
    }
}
