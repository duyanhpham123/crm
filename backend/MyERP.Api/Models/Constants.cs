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

    public static class Inventory
    {
        public const string View = "inventory.view";
        public const string Create = "inventory.create";
        public const string Edit = "inventory.edit";
        public const string Delete = "inventory.delete";
    }

    public static class Orders
    {
        public const string View = "order.view";
        public const string Create = "order.create";
        public const string Edit = "order.edit";
        public const string Approve = "order.approve";
    }

    public static class Purchasing
    {
        public const string View = "purchasing.view";
        public const string Create = "purchasing.create";
        public const string Edit = "purchasing.edit";
        public const string Approve = "purchasing.approve";
    }

    public static class Reports
    {
        public const string View = "report.view";
    }

    public static class Quotations
    {
        public const string View = "quotation.view";
        public const string Create = "quotation.create";
        public const string Edit = "quotation.edit";
    }

    public static class Logistics
    {
        public const string View = "logistics.view";
        public const string Create = "logistics.create";
        public const string Edit = "logistics.edit";
    }

    public static class Accounting
    {
        public const string View = "accounting.view";
        public const string Create = "accounting.create";
        public const string Edit = "accounting.edit";
    }

    public static class Hr
    {
        public const string View = "hr.view";
        public const string Create = "hr.create";
        public const string Edit = "hr.edit";
        public const string Approve = "hr.approve";
    }

    public static class Marketing
    {
        public const string View = "marketing.view";
        public const string Create = "marketing.create";
        public const string Edit = "marketing.edit";
    }

    public static class Settings
    {
        public const string View = "settings.view";
        public const string Edit = "settings.edit";
    }

    public static class Support
    {
        public const string View = "support.view";
        public const string Create = "support.create";
        public const string Edit = "support.edit";
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
