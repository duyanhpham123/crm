namespace MyERP.Api.Models.DTOs;

/// <summary>Lọc danh sách: GET /api/users?search=&amp;departmentId=&amp;roleId=&amp;isActive=&amp;page=</summary>
public sealed record UserQuery(string? Search, long? DepartmentId, long? RoleId, bool? IsActive, int Page = 1, int PageSize = 20);

public sealed record UserListItem(
    long Id,
    string UserName,
    string FullName,
    string? Email,
    string? PhoneNumber,
    long? DepartmentId,
    string? DepartmentName,
    IReadOnlyList<string> Roles,
    bool IsActive,
    bool IsLockedOut,
    bool IsSystemAdmin,
    DateTime? LastLoginAt);

public sealed record UserDetail(
    long Id,
    string UserName,
    string FullName,
    string? Email,
    string? PhoneNumber,
    long? DepartmentId,
    IReadOnlyList<long> RoleIds,
    bool IsActive,
    bool IsLockedOut,
    bool IsSystemAdmin,
    DateTime? LastLoginAt,
    DateTime CreatedAt);

/// <summary>POST /api/users - quản trị viên đặt mật khẩu ban đầu, nhân viên tự đổi sau khi đăng nhập.</summary>
public sealed record CreateUserRequest(
    string UserName,
    string FullName,
    string? Email,
    string? PhoneNumber,
    long? DepartmentId,
    IReadOnlyList<long> RoleIds,
    string Password);

/// <summary>PUT /api/users/{id}</summary>
public sealed record UpdateUserRequest(
    string FullName,
    string? Email,
    string? PhoneNumber,
    long? DepartmentId,
    IReadOnlyList<long> RoleIds);

public sealed record ResetPasswordRequest(string NewPassword);

public sealed record SetUserStatusRequest(bool IsActive);

/// <summary>POST /api/me/change-password - người dùng tự đổi mật khẩu.</summary>
public sealed record ChangePasswordRequest(string CurrentPassword, string NewPassword);

public sealed record OptionDto(long Id, string Name, string? Description = null);

/// <summary>Dữ liệu cho các ô chọn trong form người dùng.</summary>
public sealed record UserFormOptions(IReadOnlyList<OptionDto> Departments, IReadOnlyList<OptionDto> Roles);
