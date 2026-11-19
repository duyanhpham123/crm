using System.Security.Claims;
using MyERP.Api.Models;
using MyERP.Api.Services.Auth;

namespace MyERP.Api.Services.Common;

/// <summary>Tên claim trong JWT.</summary>
public static class ErpClaims
{
    public const string UserId = "sub";
    public const string UserName = "name";
    public const string FullName = "full_name";
    public const string CompanyId = "company_id";
    public const string BranchId = "branch_id";
    public const string DepartmentId = "department_id";
}

/// <summary>Người dùng đang gọi API (đọc từ JWT). Inject vào Service khi cần biết "ai đang làm".</summary>
public interface ICurrentUser
{
    bool IsAuthenticated { get; }
    long? UserId { get; }
    long? CompanyId { get; }
    long? BranchId { get; }
    long? DepartmentId { get; }

    long RequireUserId();
    long RequireCompanyId();

    Task<bool> HasPermissionAsync(string permission, CancellationToken ct = default);

    /// <summary>Phạm vi dữ liệu của quyền; null nếu không có quyền.</summary>
    Task<DataScope?> GetScopeAsync(string permission, CancellationToken ct = default);
}

/// <remarks>
/// IPermissionService được lấy lúc cần (không inject qua constructor) để tránh vòng phụ thuộc:
/// CurrentUser -> PermissionService -> AppDbContext -> CurrentUser.
/// </remarks>
public sealed class CurrentUser(IHttpContextAccessor accessor, IServiceProvider services) : ICurrentUser
{
    private ClaimsPrincipal? Principal => accessor.HttpContext?.User;

    public bool IsAuthenticated => Principal?.Identity?.IsAuthenticated == true;
    public long? UserId => ReadLong(ErpClaims.UserId);
    public long? CompanyId => ReadLong(ErpClaims.CompanyId);
    public long? BranchId => ReadLong(ErpClaims.BranchId);
    public long? DepartmentId => ReadLong(ErpClaims.DepartmentId);

    public long RequireUserId() => UserId ?? throw new UnauthorizedAccessException("Chưa đăng nhập.");
    public long RequireCompanyId() => CompanyId ?? throw new UnauthorizedAccessException("Chưa chọn công ty.");

    public async Task<bool> HasPermissionAsync(string permission, CancellationToken ct = default)
        => await GetScopeAsync(permission, ct) is not null;

    public async Task<DataScope?> GetScopeAsync(string permission, CancellationToken ct = default)
    {
        if (UserId is not { } userId || CompanyId is not { } companyId) return null;
        var granted = await services.GetRequiredService<IPermissionService>().GetPermissionsAsync(userId, companyId, ct);
        return granted.TryGetValue(permission, out var scope) ? scope : null;
    }

    private long? ReadLong(string claim)
        => long.TryParse(Principal?.FindFirst(claim)?.Value, out var v) ? v : null;
}
