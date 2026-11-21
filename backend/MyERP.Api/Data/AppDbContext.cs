using System.Reflection;
using Microsoft.EntityFrameworkCore;
using MyERP.Api.Models.Entities;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Models.Entities.Crm;
using MyERP.Api.Models.Entities.Inventory;
using MyERP.Api.Models.Entities.MasterData;
using MyERP.Api.Models.Entities.Purchasing;
using MyERP.Api.Models.Entities.Accounting;
using MyERP.Api.Models.Entities.Logistics;
using MyERP.Api.Models.Entities.Support;
using MyERP.Api.Models.Entities.Hr;
using MyERP.Api.Models.Entities.Marketing;
using MyERP.Api.Models.Entities.Sales;
using MyERP.Api.Models.Entities.Projects;
using MyERP.Api.Models.Entities.Documents;
using MyERP.Api.Models.Entities.Chat;
using MyERP.Api.Models.Entities.Website;
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

    // ----- md (danh mục dùng chung) -----
    public DbSet<Partner> Partners => Set<Partner>();
    public DbSet<PartnerContact> PartnerContacts => Set<PartnerContact>();
    public DbSet<PartnerGroup> PartnerGroups => Set<PartnerGroup>();

    public DbSet<ProductModel> ProductModels => Set<ProductModel>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<ProductCategory> ProductCategories => Set<ProductCategory>();
    public DbSet<Brand> Brands => Set<Brand>();
    public DbSet<UnitOfMeasure> UnitsOfMeasure => Set<UnitOfMeasure>();

    // ----- inv (kho) -----
    public DbSet<Warehouse> Warehouses => Set<Warehouse>();
    public DbSet<StockDocument> StockDocuments => Set<StockDocument>();
    public DbSet<StockLedgerEntry> StockLedger => Set<StockLedgerEntry>();
    public DbSet<StockBalance> StockBalances => Set<StockBalance>();

    // ----- sales, pur -----
    public DbSet<SalesOrder> SalesOrders => Set<SalesOrder>();
    public DbSet<SalesOrderLine> SalesOrderLines => Set<SalesOrderLine>();
    public DbSet<PurchaseOrder> PurchaseOrders => Set<PurchaseOrder>();

    // Báo giá, trả hàng, vận chuyển, kế toán, CSKH
    public DbSet<Quotation> Quotations => Set<Quotation>();
    public DbSet<SalesReturn> SalesReturns => Set<SalesReturn>();
    public DbSet<SalesReturnLine> SalesReturnLines => Set<SalesReturnLine>();
    public DbSet<Carrier> Carriers => Set<Carrier>();
    public DbSet<Shipment> Shipments => Set<Shipment>();
    public DbSet<CashVoucher> CashVouchers => Set<CashVoucher>();
    public DbSet<BankAccount> BankAccounts => Set<BankAccount>();
    public DbSet<LedgerAccount> LedgerAccounts => Set<LedgerAccount>();
    public DbSet<Ticket> Tickets => Set<Ticket>();
    public DbSet<TicketMessage> TicketMessages => Set<TicketMessage>();
    public DbSet<TicketCategory> TicketCategories => Set<TicketCategory>();
    public DbSet<SlaPolicy> SlaPolicies => Set<SlaPolicy>();

    // Nhân sự, marketing, cài đặt
    public DbSet<Position> Positions => Set<Position>();
    public DbSet<Employee> Employees => Set<Employee>();
    public DbSet<Contract> Contracts => Set<Contract>();
    public DbSet<Attendance> Attendances => Set<Attendance>();
    public DbSet<WorkShift> WorkShifts => Set<WorkShift>();
    public DbSet<LeaveType> LeaveTypes => Set<LeaveType>();
    public DbSet<LeaveBalance> LeaveBalances => Set<LeaveBalance>();
    public DbSet<LeaveRequest> LeaveRequests => Set<LeaveRequest>();
    public DbSet<PayrollPeriod> PayrollPeriods => Set<PayrollPeriod>();
    public DbSet<Payslip> Payslips => Set<Payslip>();
    public DbSet<Campaign> Campaigns => Set<Campaign>();
    public DbSet<Promotion> Promotions => Set<Promotion>();
    public DbSet<OrderPromotion> OrderPromotions => Set<OrderPromotion>();
    public DbSet<Sequence> Sequences => Set<Sequence>();
    public DbSet<Setting> Settings => Set<Setting>();

    // Dự án & công việc, tài liệu, chat nội bộ, website
    public DbSet<Project> Projects => Set<Project>();
    public DbSet<ProjectMember> ProjectMembers => Set<ProjectMember>();
    public DbSet<TaskStage> TaskStages => Set<TaskStage>();
    public DbSet<ProjectTask> ProjectTasks => Set<ProjectTask>();
    public DbSet<TaskChecklistItem> TaskChecklistItems => Set<TaskChecklistItem>();
    public DbSet<Timesheet> Timesheets => Set<Timesheet>();
    public DbSet<Attachment> Attachments => Set<Attachment>();
    public DbSet<Folder> Folders => Set<Folder>();
    public DbSet<Document> Documents => Set<Document>();
    public DbSet<DocumentVersion> DocumentVersions => Set<DocumentVersion>();
    public DbSet<Channel> Channels => Set<Channel>();
    public DbSet<ChannelMember> ChannelMembers => Set<ChannelMember>();
    public DbSet<Message> Messages => Set<Message>();
    public DbSet<Site> Sites => Set<Site>();
    public DbSet<WebPage> WebPages => Set<WebPage>();
    public DbSet<PostCategory> PostCategories => Set<PostCategory>();
    public DbSet<Post> Posts => Set<Post>();
    public DbSet<Menu> Menus => Set<Menu>();
    public DbSet<ContactSubmission> ContactSubmissions => Set<ContactSubmission>();
    public DbSet<SiteProduct> SiteProducts => Set<SiteProduct>();
    public DbSet<WebCart> WebCarts => Set<WebCart>();

    // ----- crm -----
    public DbSet<Lead> Leads => Set<Lead>();
    public DbSet<LeadSource> LeadSources => Set<LeadSource>();
    public DbSet<Opportunity> Opportunities => Set<Opportunity>();
    public DbSet<Pipeline> Pipelines => Set<Pipeline>();
    public DbSet<Stage> Stages => Set<Stage>();
    public DbSet<LostReason> LostReasons => Set<LostReason>();
    public DbSet<OpportunityStageHistory> OpportunityStageHistory => Set<OpportunityStageHistory>();

    // EF tham số hóa thuộc tính của context nên giá trị được đọc lại ở mỗi truy vấn.
    private long CurrentCompanyId => currentUser.CompanyId ?? 0;

    /// <summary>Mọi cột tiền / số lượng mặc định DECIMAL(18,4) - khớp DB, tránh EF cảnh báo làm tròn.</summary>
    protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder)
        => configurationBuilder.Properties<decimal>().HavePrecision(18, 4);

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
