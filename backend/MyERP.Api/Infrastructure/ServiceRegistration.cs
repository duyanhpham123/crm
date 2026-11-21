using System.Threading.RateLimiting;
using FluentValidation;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using MyERP.Api.Data;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Infrastructure.Middleware;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Services.Auth;
using MyERP.Api.Services.Common;
using MyERP.Api.Services.Crm;
using MyERP.Api.Services.Users;
using MyERP.Api.Services.Inventory;
using MyERP.Api.Services.Purchasing;
using MyERP.Api.Services.Reports;
using MyERP.Api.Services.Sales;
using MyERP.Api.Services.Accounting;
using MyERP.Api.Services.Logistics;
using MyERP.Api.Services.Support;
using MyERP.Api.Services.Hr;
using MyERP.Api.Services.Marketing;
using MyERP.Api.Services.Settings;

namespace MyERP.Api.Infrastructure;

/// <summary>
/// Đăng ký mọi service vào DI. Thêm Service mới (VD IOrderService) thì đăng ký ở AddAppServices.
/// </summary>
public static class ServiceRegistration
{
    public const string AuthRateLimitPolicy = "auth";
    public const string CorsPolicy = "frontend";

    /// <summary>Database + các Service nghiệp vụ.</summary>
    public static IServiceCollection AddAppServices(this IServiceCollection services, IConfiguration config)
    {
        services.AddHttpContextAccessor();
        services.AddMemoryCache();
        services.AddSingleton(TimeProvider.System);

        services.AddScoped<AuditInterceptor>();
        services.AddDbContext<AppDbContext>((sp, options) => options
            .UseSqlServer(config.GetConnectionString("MyERP") ?? throw new InvalidOperationException("Thiếu ConnectionStrings:MyERP"),
                sql => sql.EnableRetryOnFailure(3))
            .AddInterceptors(sp.GetRequiredService<AuditInterceptor>()));

        // Common
        services.AddScoped<ICurrentUser, CurrentUser>();
        services.AddScoped<IDocumentNumberService, DocumentNumberService>();
        services.AddScoped<IDataScopeService, DataScopeService>();

        // Auth
        services.AddScoped<IPasswordHasher<User>, PasswordHasher<User>>();
        services.AddScoped<TokenService>();
        services.AddScoped<IPermissionService, PermissionService>();
        services.AddScoped<IAuthService, AuthService>();
        services.AddScoped<IAccountService, AccountService>();

        // Người dùng
        services.AddScoped<IUserService, UserService>();
        services.AddScoped<IRoleService, RoleService>();

        // CRM
        services.AddScoped<ILeadService, LeadService>();
        services.AddScoped<ICustomerService, CustomerService>();
        services.AddScoped<IOpportunityService, OpportunityService>();

        // Kho, bán hàng, mua hàng, báo cáo
        services.AddScoped<IStockService, StockService>();
        services.AddScoped<IProductService, ProductService>();
        services.AddScoped<IInventoryService, InventoryService>();
        services.AddScoped<IOrderService, OrderService>();
        services.AddScoped<IPurchaseService, PurchaseService>();
        services.AddScoped<IReportService, ReportService>();
        services.AddScoped<ICashService, CashService>();
        services.AddScoped<IQuotationService, QuotationService>();
        services.AddScoped<IShipmentService, ShipmentService>();
        services.AddScoped<ITicketService, TicketService>();
        services.AddScoped<IHrService, HrService>();
        services.AddScoped<IPayrollService, PayrollService>();
        services.AddScoped<IMarketingService, MarketingService>();
        services.AddScoped<ISettingsService, SettingsService>();

        // Validators: tự nạp mọi lớp AbstractValidator trong thư mục Validators/
        services.AddValidatorsFromAssemblyContaining<Program>(includeInternalTypes: true);

        services.AddExceptionHandler<GlobalExceptionHandler>();
        services.AddProblemDetails();
        return services;
    }

    /// <summary>Xác thực JWT + phân quyền theo [HasPermission].</summary>
    public static IServiceCollection AddJwtAuth(this IServiceCollection services, IConfiguration config)
    {
        var section = config.GetSection(JwtOptions.Section);
        services.Configure<JwtOptions>(section);
        var jwt = section.Get<JwtOptions>() ?? new JwtOptions();

        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(o =>
            {
                o.MapInboundClaims = false;   // giữ nguyên tên claim "sub", "company_id"
                o.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidIssuer = jwt.Issuer,
                    ValidAudience = jwt.Audience,
                    IssuerSigningKey = jwt.GetSigningKey(),
                    NameClaimType = ErpClaims.UserName,
                    ClockSkew = TimeSpan.FromSeconds(30)
                };
            });

        services.AddAuthorization();
        services.AddSingleton<IAuthorizationPolicyProvider, PermissionPolicyProvider>();
        services.AddScoped<IAuthorizationHandler, PermissionHandler>();
        return services;
    }

    /// <summary>CORS cho frontend chạy khác địa chỉ + chống dò mật khẩu.</summary>
    public static IServiceCollection AddWebSecurity(this IServiceCollection services, IConfiguration config)
    {
        var origins = config.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
        services.AddCors(o => o.AddPolicy(CorsPolicy, p => p.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod()));

        // Chống dò mật khẩu: tối đa N lần gọi API đăng nhập / đổi mật khẩu mỗi phút cho mỗi IP.
        // Production mặc định 10 (appsettings.json), Development nới rộng để dev đăng nhập lại thoải mái.
        var permitLimit = config.GetValue("RateLimit:AuthPermitLimit", 10);
        services.AddRateLimiter(o =>
        {
            o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            o.AddPolicy(AuthRateLimitPolicy, http => RateLimitPartition.GetFixedWindowLimiter(
                http.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                _ => new FixedWindowRateLimiterOptions { PermitLimit = permitLimit, Window = TimeSpan.FromMinutes(1) }));
        });
        return services;
    }
}
