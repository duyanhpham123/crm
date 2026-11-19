namespace MyERP.Api.Models;

/// <summary>Mã quyền, khớp bảng core.Permissions. Dùng trong [HasPermission(...)] trên controller.</summary>
public static class Permissions
{
    public static class Crm
    {
        public const string View = "crm.view";
        public const string Create = "crm.create";
        public const string Edit = "crm.edit";
        public const string Delete = "crm.delete";
        public const string Export = "crm.export";
    }

    /// <summary>Ứng dụng "Người dùng" - gồm cả quản lý vai trò & quyền.</summary>
    public static class Users
    {
        public const string View = "users.view";
        public const string Create = "users.create";
        public const string Edit = "users.edit";
        public const string Delete = "users.delete";
    }

    /// <summary>Các hành động chuẩn của mọi ứng dụng (cột trong ma trận phân quyền).</summary>
    public static readonly IReadOnlyList<string> StandardActions = ["view", "create", "edit", "delete", "approve", "export"];

    public static string AppView(string appCode) => $"{appCode}.view";
}

/// <summary>Phạm vi dữ liệu được thấy, khớp cột core.RolePermissions.DataScope.</summary>
public enum DataScope
{
    Own = 1,
    Department = 2,
    Branch = 3,
    Company = 4,
    All = 5
}

public static class DataScopes
{
    public static readonly IReadOnlyList<string> All = ["own", "department", "branch", "company", "all"];

    public static DataScope Parse(string value) => value switch
    {
        "own" => DataScope.Own,
        "department" => DataScope.Department,
        "branch" => DataScope.Branch,
        "company" => DataScope.Company,
        "all" => DataScope.All,
        _ => throw new ArgumentOutOfRangeException(nameof(value), value, "DataScope không hợp lệ")
    };

    /// <summary>Có nhiều vai trò cùng cấp một quyền thì lấy phạm vi rộng nhất.</summary>
    public static DataScope Widest(DataScope a, DataScope b) => a >= b ? a : b;
}

public static class LeadStatuses
{
    public const string New = "new";
    public const string Contacted = "contacted";
    public const string Qualified = "qualified";
    public const string Unqualified = "unqualified";
    public const string Converted = "converted";

    public static readonly IReadOnlyList<string> All = [New, Contacted, Qualified, Unqualified, Converted];
}
