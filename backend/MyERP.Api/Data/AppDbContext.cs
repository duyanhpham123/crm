using System.Reflection;
using Microsoft.EntityFrameworkCore;
using MyERP.Api.Models.Entities;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Models.Entities.Crm;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Data;

/// <summary>
/// DbContext duy nhất của ứng dụng. Map vào các bảng đã tạo bằng script database/*.sql.
/// Cấu hình từng bảng nằm trong Data/Configurations/.
///
/// Tự áp dụng 2 bộ lọc cho mọi truy vấn:
///  - SoftDelete: ẩn bản ghi IsDeleted = 1
///  - Company   : chỉ thấy dữ liệu của công ty đang đăng nhập
/// </summary>
public sealed class AppDbContext(DbContextOptions<AppDbContext> options, ICurrentUser currentUser) : DbContext(options)
{
    public const string SoftDeleteFilter = "SoftDelete";
    public const string CompanyFilter = "Company";

    // ----- core -----
    public DbSet<User> Users => Set<User>();
    public DbSet<Company> Companies => Set<Company>();
    public DbSet<Department> Departments => Set<Department>();
    public DbSet<UserCompany> UserCompanies => Set<UserCompany>();
    public DbSet<Role> Roles => Set<Role>();
    public DbSet<UserRole> UserRoles => Set<UserRole>();
    public DbSet<Permission> Permissions => Set<Permission>();
    public DbSet<RolePermission> RolePermissions => Set<RolePermission>();
    public DbSet<App> Apps => Set<App>();
    public DbSet<CompanyApp> CompanyApps => Set<CompanyApp>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();

    // ----- crm -----
    public DbSet<Lead> Leads => Set<Lead>();
    public DbSet<LeadSource> LeadSources => Set<LeadSource>();

    // EF tham số hóa thuộc tính của context nên giá trị được đọc lại ở mỗi truy vấn.
    private long CurrentCompanyId => currentUser.CompanyId ?? 0;

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Nạp mọi lớp IEntityTypeConfiguration trong Data/Configurations
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);

        foreach (var entity in modelBuilder.Model.GetEntityTypes().Where(e => e.BaseType is null))
        {
            var clr = entity.ClrType;
            if (typeof(ISoftDelete).IsAssignableFrom(clr))
                CallGeneric(nameof(ApplySoftDeleteFilter), clr, modelBuilder);
            if (typeof(ICompanyOwned).IsAssignableFrom(clr))
                CallGeneric(nameof(ApplyCompanyFilter), clr, modelBuilder);
            if (typeof(AuditableEntity).IsAssignableFrom(clr))
                modelBuilder.Entity(clr).Property(nameof(AuditableEntity.RowVersion)).IsRowVersion();
        }
    }

    private void CallGeneric(string method, Type clr, ModelBuilder mb) =>
        typeof(AppDbContext).GetMethod(method, BindingFlags.NonPublic | BindingFlags.Instance)!
            .MakeGenericMethod(clr).Invoke(this, [mb]);

    private void ApplySoftDeleteFilter<T>(ModelBuilder mb) where T : class, ISoftDelete
        => mb.Entity<T>().HasQueryFilter(SoftDeleteFilter, e => !e.IsDeleted);

    private void ApplyCompanyFilter<T>(ModelBuilder mb) where T : class, ICompanyOwned
        => mb.Entity<T>().HasQueryFilter(CompanyFilter, e => e.CompanyId == CurrentCompanyId);
}
