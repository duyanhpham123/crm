using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MyERP.Api.Models.Entities.Core;

namespace MyERP.Api.Data.Configurations;

// Map entity vào bảng schema "core". Mỗi lớp = 1 bảng.

internal sealed class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> e)
    {
        e.ToTable("Users", "core");
        e.Property(x => x.UserName).HasMaxLength(100);
        e.Property(x => x.NormalizedUserName).HasMaxLength(100);
        e.Property(x => x.FullName).HasMaxLength(150);
        e.Property(x => x.Email).HasMaxLength(255);
        e.Property(x => x.PhoneNumber).HasMaxLength(20).IsUnicode(false);
        e.HasMany(x => x.Memberships).WithOne().HasForeignKey(x => x.UserId);
        e.HasMany(x => x.UserRoles).WithOne().HasForeignKey(x => x.UserId);
    }
}

internal sealed class DepartmentConfiguration : IEntityTypeConfiguration<Department>
{
    public void Configure(EntityTypeBuilder<Department> e) => e.ToTable("Departments", "core");
}

internal sealed class CompanyConfiguration : IEntityTypeConfiguration<Company>
{
    public void Configure(EntityTypeBuilder<Company> e)
    {
        e.ToTable("Companies", "core");
        e.HasQueryFilter(x => x.IsActive);
    }
}

internal sealed class UserCompanyConfiguration : IEntityTypeConfiguration<UserCompany>
{
    public void Configure(EntityTypeBuilder<UserCompany> e)
    {
        e.ToTable("UserCompanies", "core");
        e.HasKey(x => new { x.UserId, x.CompanyId });
    }
}

internal sealed class RoleConfiguration : IEntityTypeConfiguration<Role>
{
    public void Configure(EntityTypeBuilder<Role> e)
    {
        e.ToTable("Roles", "core");
        e.Property(x => x.Code).HasMaxLength(50).IsUnicode(false);
        e.Property(x => x.Name).HasMaxLength(100);
        e.Property(x => x.NormalizedName).HasMaxLength(100);
        e.Property(x => x.Description).HasMaxLength(500);
        e.HasMany(x => x.Permissions).WithOne().HasForeignKey(x => x.RoleId);
        // Lọc xóa mềm được AppDbContext tự thêm vì Role kế thừa AuditableEntity
    }
}

internal sealed class UserRoleConfiguration : IEntityTypeConfiguration<UserRole>
{
    public void Configure(EntityTypeBuilder<UserRole> e)
    {
        e.ToTable("UserRoles", "core");
        e.HasKey(x => new { x.UserId, x.RoleId, x.CompanyId });
    }
}

internal sealed class PermissionConfiguration : IEntityTypeConfiguration<Permission>
{
    public void Configure(EntityTypeBuilder<Permission> e) => e.ToTable("Permissions", "core");
}

internal sealed class RolePermissionConfiguration : IEntityTypeConfiguration<RolePermission>
{
    public void Configure(EntityTypeBuilder<RolePermission> e)
    {
        e.ToTable("RolePermissions", "core");
        e.HasKey(x => new { x.RoleId, x.PermissionId });
    }
}

internal sealed class AppConfiguration : IEntityTypeConfiguration<App>
{
    public void Configure(EntityTypeBuilder<App> e) => e.ToTable("Apps", "core");
}

internal sealed class CompanyAppConfiguration : IEntityTypeConfiguration<CompanyApp>
{
    public void Configure(EntityTypeBuilder<CompanyApp> e)
    {
        e.ToTable("CompanyApps", "core");
        e.HasKey(x => new { x.CompanyId, x.AppId });
    }
}

internal sealed class RefreshTokenConfiguration : IEntityTypeConfiguration<RefreshToken>
{
    public void Configure(EntityTypeBuilder<RefreshToken> e) => e.ToTable("RefreshTokens", "core");
}
