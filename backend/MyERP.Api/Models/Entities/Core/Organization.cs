namespace MyERP.Api.Models.Entities.Core;

// Các bảng tổ chức & phân quyền của schema core.

/// <summary>core.Companies</summary>
public sealed class Company
{
    public long Id { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public string? ShortName { get; private set; }
    public string? TaxCode { get; private set; }
    public string? Address { get; private set; }
    public string? Phone { get; private set; }
    public string? Email { get; private set; }
    public string? Website { get; private set; }
    public string? LegalRepresentative { get; private set; }
    public bool IsActive { get; private set; }

    public Common.Result Update(string name, string? shortName, string? taxCode, string? address, string? phone, string? email, string? website, string? legalRep)
    {
        if (string.IsNullOrWhiteSpace(name)) return Common.Error.Validation("company.name", "Nhập tên công ty / cửa hàng.");
        static string? C(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
        Name = name.Trim(); ShortName = C(shortName); TaxCode = C(taxCode); Address = C(address); Phone = C(phone);
        Email = C(email); Website = C(website); LegalRepresentative = C(legalRep);
        return Common.Result.Success();
    }
}

/// <summary>core.Departments - phòng ban.</summary>
public sealed class Department : ICompanyOwned, ISoftDelete
{
    public static Department Create(long companyId, long? branchId, string code, string name, int sortOrder)
        => new() { CompanyId = companyId, BranchId = branchId, Code = code.Trim().ToUpperInvariant(), Name = name.Trim(), SortOrder = sortOrder, IsActive = true };

    public void Update(string name, long? parentId, int sortOrder, bool isActive)
    {
        Name = name.Trim(); ParentId = parentId; SortOrder = sortOrder; IsActive = isActive;
    }

    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public long? BranchId { get; private set; }
    public long? ParentId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public int SortOrder { get; private set; }
    public bool IsActive { get; private set; }
    public bool IsDeleted { get; set; }
}

/// <summary>core.UserCompanies - người dùng thuộc công ty / chi nhánh / phòng ban nào.</summary>
public sealed class UserCompany
{
    private UserCompany() { }

    public long UserId { get; private set; }
    public long CompanyId { get; private set; }
    public long? BranchId { get; private set; }
    public long? DepartmentId { get; private set; }
    public bool IsDefault { get; private set; }

    public static UserCompany Create(long companyId, long? branchId, long? departmentId) => new()
    {
        CompanyId = companyId,
        BranchId = branchId,
        DepartmentId = departmentId,
        IsDefault = true
    };

    public void MoveTo(long? branchId, long? departmentId)
    {
        BranchId = branchId;
        DepartmentId = departmentId;
    }
}

/// <summary>core.Roles - vai trò (Kế toán, Thủ kho, Sale...).</summary>
public sealed class Role : AuditableEntity
{
    private Role() { }

    public long? CompanyId { get; private set; }   // NULL = vai trò hệ thống (admin), không sửa được
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public string NormalizedName { get; private set; } = "";
    public string? Description { get; private set; }
    public bool IsSystem { get; private set; }

    /// <summary>Quyền của vai trò (core.RolePermissions).</summary>
    public List<RolePermission> Permissions { get; private set; } = [];

    public bool IsGlobal => CompanyId is null;

    public static Role Create(long companyId, string code, string name, string? description)
    {
        var role = new Role { CompanyId = companyId, Code = code.Trim().ToLowerInvariant() };
        role.Update(name, description);
        return role;
    }

    public void Update(string name, string? description)
    {
        Name = name.Trim();
        NormalizedName = Name.ToUpperInvariant();
        Description = string.IsNullOrWhiteSpace(description) ? null : description.Trim();
    }

    /// <summary>Thay toàn bộ danh sách quyền: thêm quyền mới, bỏ quyền không còn, cập nhật phạm vi.</summary>
    public void SetPermissions(IReadOnlyDictionary<int, string> grants)
    {
        Permissions.RemoveAll(p => !grants.ContainsKey(p.PermissionId));
        foreach (var (permissionId, scope) in grants)
        {
            var existing = Permissions.FirstOrDefault(p => p.PermissionId == permissionId);
            if (existing is null) Permissions.Add(RolePermission.Create(permissionId, scope));
            else existing.SetScope(scope);
        }
    }

    /// <summary>Chỉ dùng cho unit test.</summary>
    internal static Role CreateForTest(long companyId) => Create(companyId, "test", "Test", null);
}

/// <summary>core.UserRoles</summary>
public sealed class UserRole
{
    private UserRole() { }

    public long UserId { get; private set; }
    public long RoleId { get; private set; }
    public long CompanyId { get; private set; }

    public static UserRole Create(long roleId, long companyId) => new() { RoleId = roleId, CompanyId = companyId };
}

/// <summary>core.Permissions - mã quyền như 'crm.view'.</summary>
public sealed class Permission
{
    public int Id { get; private set; }
    public int AppId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
}

/// <summary>core.RolePermissions - vai trò có quyền gì, phạm vi dữ liệu nào.</summary>
public sealed class RolePermission
{
    private RolePermission() { }

    public long RoleId { get; private set; }
    public int PermissionId { get; private set; }
    public string DataScope { get; private set; } = "own";

    public static RolePermission Create(int permissionId, string dataScope) => new() { PermissionId = permissionId, DataScope = dataScope };

    public void SetScope(string dataScope) => DataScope = dataScope;
}

/// <summary>core.Apps - ứng dụng trên màn hình lưới.</summary>
public sealed class App
{
    public int Id { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public string? Icon { get; private set; }
    public string? Color { get; private set; }
    public string? Route { get; private set; }
    public int SortOrder { get; private set; }
    public bool IsEnabled { get; private set; }
}

/// <summary>core.CompanyApps - công ty nào bật ứng dụng nào.</summary>
public sealed class CompanyApp
{
    public long CompanyId { get; private set; }
    public int AppId { get; private set; }
    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled) => IsEnabled = enabled;
}

/// <summary>core.Sequences - quy tắc đánh số chứng từ (tiền tố, mẫu ngày, số chữ số).</summary>
public sealed class Sequence : ICompanyOwned
{
    private Sequence() { }
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Prefix { get; private set; } = "";
    public string? DatePattern { get; private set; }
    public byte Padding { get; private set; }
    public string ResetPolicy { get; private set; } = "monthly";

    public Common.Result Update(string prefix, string? datePattern, byte padding)
    {
        var p = (prefix ?? "").Trim().ToUpperInvariant();
        if (p.Length is < 1 or > 10 || !p.All(char.IsAsciiLetterOrDigit)) return Common.Error.Validation("sequence.prefix", "Tiền tố 1-10 ký tự chữ / số không dấu.");
        if (datePattern is not (null or "" or "yyMM" or "yyyyMM" or "yyyy" or "yy")) return Common.Error.Validation("sequence.pattern", "Mẫu ngày không hợp lệ.");
        if (padding is < 3 or > 8) return Common.Error.Validation("sequence.padding", "Số chữ số từ 3 đến 8.");
        Prefix = p; DatePattern = string.IsNullOrEmpty(datePattern) ? null : datePattern; Padding = padding;
        ResetPolicy = DatePattern switch { null => "never", "yyyy" or "yy" => "yearly", _ => "monthly" };
        return Common.Result.Success();
    }
}

/// <summary>core.Settings - cấu hình dạng khóa / giá trị theo công ty.</summary>
public sealed class Setting
{
    private Setting() { }
    public Setting(long companyId, string key) { CompanyId = companyId; SettingKey = key; }
    public long Id { get; private set; }
    public long? CompanyId { get; private set; }
    public string SettingKey { get; private set; } = "";
    public string? SettingValue { get; private set; }
    public DateTime? UpdatedAt { get; private set; }
    public long? UpdatedBy { get; private set; }

    public void Set(string? value, long userId, DateTime now) { SettingValue = value; UpdatedAt = now; UpdatedBy = userId; }
}
