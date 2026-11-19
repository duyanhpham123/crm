using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Validators;

namespace MyERP.Tests.Models;

public class RoleTests
{
    [Fact]
    public void Create_normalizes_code_and_name()
    {
        var role = Role.Create(1, " Ke_Toan_Truong ", "  Kế toán trưởng ", "  ");

        Assert.Equal("ke_toan_truong", role.Code);
        Assert.Equal("Kế toán trưởng", role.Name);
        Assert.Equal("KẾ TOÁN TRƯỞNG", role.NormalizedName);
        Assert.Null(role.Description);
        Assert.False(role.IsGlobal);
    }

    [Fact]
    public void SetPermissions_adds_removes_and_updates_scope()
    {
        var role = Role.CreateForTest(1);
        role.SetPermissions(new Dictionary<int, string> { [1] = "own", [2] = "own", [3] = "own" });

        role.SetPermissions(new Dictionary<int, string> { [1] = "company", [3] = "own", [4] = "department" });

        Assert.Equal([1, 3, 4], role.Permissions.Select(p => p.PermissionId).Order());
        Assert.Equal("company", role.Permissions.Single(p => p.PermissionId == 1).DataScope);
        Assert.Equal("department", role.Permissions.Single(p => p.PermissionId == 4).DataScope);
    }

    [Theory]
    [InlineData("ke_toan", true)]
    [InlineData("KT2", true)]
    [InlineData("k", false)]
    [InlineData("kế toán", false)]
    [InlineData("ke-toan", false)]
    public void Code_format(string code, bool valid)
    {
        var result = new SaveRoleRequestValidator().Validate(new SaveRoleRequest(code, "Tên", null, []));
        Assert.Equal(valid, result.IsValid);
    }

    [Fact]
    public void Rejects_invalid_scope_and_duplicates()
    {
        var result = new SaveRoleRequestValidator().Validate(new SaveRoleRequest("ok", "Tên", null,
            [new RolePermissionDto(1, "own"), new RolePermissionDto(1, "own"), new RolePermissionDto(2, "galaxy")]));

        Assert.Contains(result.Errors, e => e.ErrorMessage.Contains("trùng"));
        Assert.Contains(result.Errors, e => e.ErrorMessage.Contains("Phạm vi"));
    }
}
