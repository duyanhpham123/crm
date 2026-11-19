namespace MyERP.Api.Models.DTOs;

public sealed record RoleListItem(
    long Id,
    string Code,
    string Name,
    string? Description,
    bool IsSystem,          // vai trò hệ thống (admin): chỉ xem, không sửa / xóa
    int UserCount,
    int PermissionCount);

/// <summary>Một quyền được cấp + phạm vi dữ liệu: own | department | branch | company | all</summary>
public sealed record RolePermissionDto(int PermissionId, string DataScope);

public sealed record RoleDetail(
    long Id,
    string Code,
    string Name,
    string? Description,
    bool IsSystem,
    bool IsReadOnly,        // true nếu bạn không được sửa vai trò này (vai trò hệ thống / vai trò bạn đang giữ)
    string? ReadOnlyReason,
    int UserCount,
    IReadOnlyList<RolePermissionDto> Permissions,
    string RowVersion);

/// <summary>POST /api/roles (có Code) hoặc PUT /api/roles/{id} (bỏ qua Code).</summary>
public sealed record SaveRoleRequest(
    string? Code,
    string Name,
    string? Description,
    IReadOnlyList<RolePermissionDto> Permissions,
    string? RowVersion = null);

// ----- Danh mục quyền để vẽ ma trận phân quyền -----

/// <summary>Action: "view", "create"... với quyền chuẩn; mã đầy đủ (VD "entry.post") với quyền đặc thù.</summary>
public sealed record PermissionItem(int Id, string Code, string Action, string Name, bool IsStandard);

public sealed record PermissionGroup(string AppCode, string AppName, string? Icon, string? Color, IReadOnlyList<PermissionItem> Permissions);

/// <param name="CanGrantAllCompanies">Chỉ quản trị hệ thống mới cấp được phạm vi "all" (mọi công ty).</param>
public sealed record PermissionCatalog(IReadOnlyList<PermissionGroup> Groups, bool CanGrantAllCompanies);
