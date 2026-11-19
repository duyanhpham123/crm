using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Services.Auth;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Users;

public interface IUserService
{
    Task<PagedResult<UserListItem>> ListAsync(UserQuery query, CancellationToken ct);
    Task<Result<UserDetail>> GetAsync(long id, CancellationToken ct);
    Task<UserFormOptions> GetFormOptionsAsync(CancellationToken ct);
    Task<Result<UserDetail>> CreateAsync(CreateUserRequest request, CancellationToken ct);
    Task<Result<UserDetail>> UpdateAsync(long id, UpdateUserRequest request, CancellationToken ct);
    Task<Result> ResetPasswordAsync(long id, ResetPasswordRequest request, CancellationToken ct);
    Task<Result<UserDetail>> SetStatusAsync(long id, SetUserStatusRequest request, CancellationToken ct);
}

/// <summary>
/// Quản lý tài khoản nhân viên trong công ty đang đăng nhập.
/// Quy tắc an toàn:
///  - Không tự khóa / tự đổi vai trò của chính mình (tránh tự mất quyền quản trị).
///  - Chỉ quản trị hệ thống mới được sửa tài khoản quản trị hệ thống và gán vai trò hệ thống.
///  - Khóa tài khoản / đặt lại mật khẩu thì thu hồi mọi phiên đăng nhập của người đó.
/// </summary>
public sealed class UserService(
    AppDbContext db,
    ICurrentUser currentUser,
    IPermissionService permissions,
    IPasswordHasher<User> hasher,
    TimeProvider clock) : IUserService
{
    public async Task<PagedResult<UserListItem>> ListAsync(UserQuery q, CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        var page = Math.Max(1, q.Page);
        var pageSize = Math.Clamp(q.PageSize, 1, 100);
        var now = clock.GetUtcNow();

        var query = from uc in db.UserCompanies
                    join u in db.Users on uc.UserId equals u.Id
                    where uc.CompanyId == companyId
                    select new { u, uc.DepartmentId };

        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var s = q.Search.Trim();
            query = query.Where(x => x.u.FullName.Contains(s) || x.u.UserName.Contains(s)
                || (x.u.Email != null && x.u.Email.Contains(s)) || (x.u.PhoneNumber != null && x.u.PhoneNumber.Contains(s)));
        }
        if (q.DepartmentId is { } dept) query = query.Where(x => x.DepartmentId == dept);
        if (q.IsActive is { } active) query = query.Where(x => x.u.IsActive == active);
        if (q.RoleId is { } roleId)
            query = query.Where(x => db.UserRoles.Any(r => r.UserId == x.u.Id && r.CompanyId == companyId && r.RoleId == roleId));

        var total = await query.CountAsync(ct);
        var rows = await query
            .OrderBy(x => x.u.FullName)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new
            {
                x.u.Id, x.u.UserName, x.u.FullName, x.u.Email, x.u.PhoneNumber, x.DepartmentId,
                DepartmentName = db.Departments.Where(d => d.Id == x.DepartmentId).Select(d => d.Name).FirstOrDefault(),
                Roles = (from ur in db.UserRoles
                         join r in db.Roles on ur.RoleId equals r.Id
                         where ur.UserId == x.u.Id && ur.CompanyId == companyId
                         orderby r.Name
                         select r.Name).ToList(),
                x.u.IsActive, x.u.LockoutEnabled, x.u.LockoutEnd, x.u.IsSystemAdmin, x.u.LastLoginAt
            })
            .AsNoTracking().ToListAsync(ct);

        var items = rows.Select(r => new UserListItem(r.Id, r.UserName, r.FullName, r.Email, r.PhoneNumber,
            r.DepartmentId, r.DepartmentName, r.Roles, r.IsActive, r.LockoutEnabled && r.LockoutEnd > now,
            r.IsSystemAdmin, r.LastLoginAt)).ToList();

        return new PagedResult<UserListItem>(items, page, pageSize, total);
    }

    public async Task<Result<UserDetail>> GetAsync(long id, CancellationToken ct)
    {
        var user = await LoadAsync(id, ct);
        return user is null ? Error.NotFound("người dùng") : ToDetail(user);
    }

    public async Task<UserFormOptions> GetFormOptionsAsync(CancellationToken ct)
    {
        var departments = await db.Departments.Where(d => d.IsActive).OrderBy(d => d.SortOrder).ThenBy(d => d.Name)
            .Select(d => new OptionDto(d.Id, d.Name, null)).AsNoTracking().ToListAsync(ct);
        var roles = await AssignableRoles(await IsCurrentSystemAdminAsync(ct)).OrderBy(r => r.CompanyId == null ? 0 : 1).ThenBy(r => r.Name)
            .Select(r => new OptionDto(r.Id, r.Name, r.Description)).AsNoTracking().ToListAsync(ct);
        return new UserFormOptions(departments, roles);
    }

    public async Task<Result<UserDetail>> CreateAsync(CreateUserRequest req, CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        var normalizedName = req.UserName.Trim().ToUpperInvariant();
        if (await db.Users.IgnoreQueryFilters().AnyAsync(u => u.NormalizedUserName == normalizedName, ct))
            return Error.Conflict("user.username_taken", $"Tên đăng nhập \"{req.UserName.Trim().ToLowerInvariant()}\" đã được dùng.");
        if (await EmailTakenAsync(req.Email, excludeId: null, ct))
            return Error.Conflict("user.email_taken", "Email này đã được dùng cho tài khoản khác.");

        var check = await ValidateAssignmentAsync(req.DepartmentId, req.RoleIds, ct);
        if (check.IsFailure) return check.Error!;

        var user = User.Create(req.UserName, req.FullName, req.Email, req.PhoneNumber, companyId);
        user.SetPassword(hasher.HashPassword(user, req.Password));
        user.Memberships.Add(UserCompany.Create(companyId, DepartmentBranch(check), req.DepartmentId));
        foreach (var roleId in req.RoleIds.Distinct()) user.UserRoles.Add(UserRole.Create(roleId, companyId));

        db.Users.Add(user);
        await db.SaveChangesAsync(ct);
        return ToDetail(user);
    }

    public async Task<Result<UserDetail>> UpdateAsync(long id, UpdateUserRequest req, CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        var user = await LoadAsync(id, ct);
        if (user is null) return Error.NotFound("người dùng");

        var guard = await GuardTargetAsync(user, ct);
        if (guard.IsFailure) return guard.Error!;
        if (await EmailTakenAsync(req.Email, id, ct))
            return Error.Conflict("user.email_taken", "Email này đã được dùng cho tài khoản khác.");

        var check = await ValidateAssignmentAsync(req.DepartmentId, req.RoleIds, ct);
        if (check.IsFailure) return check.Error!;

        var newRoles = req.RoleIds.Distinct().ToHashSet();
        var currentRoles = user.UserRoles.Where(r => r.CompanyId == companyId).Select(r => r.RoleId).ToHashSet();
        if (id == currentUser.RequireUserId() && !newRoles.SetEquals(currentRoles))
            return Error.Forbidden("Bạn không thể tự đổi vai trò của chính mình. Nhờ quản trị viên khác thực hiện.");

        // Không kiểm tra RowVersion ở đây: mỗi lần nhân viên đăng nhập, dòng Users được ghi LastLoginAt
        // làm RowVersion đổi, nên admin sẽ liên tục bị báo "người khác đã sửa". EF chỉ ghi các cột thay đổi
        // nên dữ liệu đăng nhập và dữ liệu admin sửa không đè lên nhau.
        user.UpdateProfile(req.FullName, req.Email, req.PhoneNumber);
        user.Memberships.Single(m => m.CompanyId == companyId).MoveTo(DepartmentBranch(check), req.DepartmentId);
        user.UserRoles.RemoveAll(r => r.CompanyId == companyId && !newRoles.Contains(r.RoleId));
        foreach (var roleId in newRoles.Except(currentRoles)) user.UserRoles.Add(UserRole.Create(roleId, companyId));

        await db.SaveChangesAsync(ct);
        permissions.Invalidate(user.Id, companyId);        // quyền mới có hiệu lực ngay
        return ToDetail(user);
    }

    public async Task<Result> ResetPasswordAsync(long id, ResetPasswordRequest req, CancellationToken ct)
    {
        var user = await LoadAsync(id, ct);
        if (user is null) return Error.NotFound("người dùng");
        var guard = await GuardTargetAsync(user, ct);
        if (guard.IsFailure) return guard.Error!;

        user.SetPassword(hasher.HashPassword(user, req.NewPassword));
        await RevokeSessionsAsync(user.Id, ct);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result<UserDetail>> SetStatusAsync(long id, SetUserStatusRequest req, CancellationToken ct)
    {
        var user = await LoadAsync(id, ct);
        if (user is null) return Error.NotFound("người dùng");
        if (id == currentUser.RequireUserId())
            return Error.Forbidden("Bạn không thể tự khóa tài khoản của chính mình.");
        var guard = await GuardTargetAsync(user, ct);
        if (guard.IsFailure) return guard.Error!;

        user.SetActive(req.IsActive);
        if (!req.IsActive) await RevokeSessionsAsync(user.Id, ct);
        await db.SaveChangesAsync(ct);
        permissions.Invalidate(user.Id, currentUser.RequireCompanyId());   // khóa thì mất quyền ngay, không đợi cache
        return ToDetail(user);
    }

    // ---------- Hàm hỗ trợ ----------

    /// <summary>Chỉ tải người dùng thuộc công ty hiện tại.</summary>
    private Task<User?> LoadAsync(long id, CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        return db.Users
            .Include(u => u.Memberships)
            .Include(u => u.UserRoles)
            .Where(u => u.Id == id && u.Memberships.Any(m => m.CompanyId == companyId))
            .AsSplitQuery()
            .FirstOrDefaultAsync(ct);
    }

    private async Task<Result> GuardTargetAsync(User target, CancellationToken ct)
        => target.IsSystemAdmin && !await IsCurrentSystemAdminAsync(ct)
            ? Error.Forbidden("Chỉ quản trị hệ thống mới được thay đổi tài khoản quản trị hệ thống.")
            : Result.Success();

    private Task<bool> IsCurrentSystemAdminAsync(CancellationToken ct)
    {
        var me = currentUser.RequireUserId();
        return db.Users.AnyAsync(u => u.Id == me && u.IsSystemAdmin, ct);
    }

    /// <summary>Vai trò được phép gán: của công ty hiện tại; vai trò hệ thống chỉ quản trị hệ thống mới gán được.</summary>
    private IQueryable<Role> AssignableRoles(bool isSystemAdmin)
    {
        var companyId = currentUser.RequireCompanyId();
        return db.Roles.Where(r => r.CompanyId == companyId || (isSystemAdmin && r.CompanyId == null));
    }

    private sealed record Assignment(long? BranchId) { }

    private async Task<Result<Assignment>> ValidateAssignmentAsync(long? departmentId, IReadOnlyList<long> roleIds, CancellationToken ct)
    {
        long? branchId = null;
        if (departmentId is { } deptId)
        {
            var dept = await db.Departments.Where(d => d.Id == deptId && d.IsActive).Select(d => new { d.BranchId }).FirstOrDefaultAsync(ct);
            if (dept is null) return Error.Validation("user.department_invalid", "Phòng ban không hợp lệ.");
            branchId = dept.BranchId;
        }

        var ids = roleIds.Distinct().ToList();
        var allowed = await AssignableRoles(await IsCurrentSystemAdminAsync(ct)).CountAsync(r => ids.Contains(r.Id), ct);
        if (allowed != ids.Count) return Error.Validation("user.role_invalid", "Có vai trò không hợp lệ hoặc bạn không được phép gán.");

        return new Assignment(branchId);
    }

    private static long? DepartmentBranch(Result<Assignment> check) => check.Value.BranchId;

    private async Task<bool> EmailTakenAsync(string? email, long? excludeId, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(email)) return false;
        var normalized = email.Trim().ToUpperInvariant();
        return await db.Users.AnyAsync(u => u.NormalizedEmail == normalized && u.Id != excludeId, ct);
    }

    private async Task RevokeSessionsAsync(long userId, CancellationToken ct)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        var tokens = await db.RefreshTokens.Where(t => t.UserId == userId && t.RevokedAt == null).ToListAsync(ct);
        tokens.ForEach(t => t.Revoke(now, null));
    }

    private UserDetail ToDetail(User u)
    {
        var companyId = currentUser.RequireCompanyId();
        return new UserDetail(u.Id, u.UserName, u.FullName, u.Email, u.PhoneNumber,
            u.Memberships.FirstOrDefault(m => m.CompanyId == companyId)?.DepartmentId,
            u.UserRoles.Where(r => r.CompanyId == companyId).Select(r => r.RoleId).Order().ToList(),
            u.IsActive, u.IsLockedOut(clock.GetUtcNow()), u.IsSystemAdmin, u.LastLoginAt, u.CreatedAt);
    }
}
