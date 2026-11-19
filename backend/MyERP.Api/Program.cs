using MyERP.Api.Infrastructure;
using MyERP.Api.Infrastructure.Filters;
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

// ---------- Đăng ký service (chi tiết trong Infrastructure/ServiceRegistration.cs) ----------
builder.Services.AddControllers(o => o.Filters.Add<ValidationFilter>());
builder.Services.AddAppServices(builder.Configuration);
builder.Services.AddJwtAuth(builder.Configuration);
builder.Services.AddWebSecurity(builder.Configuration);
builder.Services.AddOpenApi();

var app = builder.Build();

// ---------- Pipeline xử lý request ----------
app.UseExceptionHandler();
app.UseStatusCodePages();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference("/docs");   // tài liệu + thử API: http://localhost:5121/docs
}
else
{
    app.UseHsts();
    app.UseHttpsRedirection();
}

// Phục vụ bản build React (frontend: npm run build xuất vào wwwroot).
// File trong /assets có hash trong tên nên cache lâu; index.html không cache để deploy là thấy bản mới ngay.
app.UseStaticFiles(new StaticFileOptions
{
    OnPrepareResponse = ctx => ctx.Context.Response.Headers.CacheControl =
        ctx.Context.Request.Path.StartsWithSegments("/assets")
            ? "public, max-age=31536000, immutable"
            : "no-cache"
});

app.UseCors(ServiceRegistration.CorsPolicy);
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
app.MapGet("/api/health", () => Results.Ok(new { status = "ok" })).AllowAnonymous().ExcludeFromDescription();

// API không tồn tại: trả 404 JSON (không trả về trang React)
app.Map("/api/{**path}", () => Results.Problem(statusCode: 404, title: "Không tìm thấy API.")).ExcludeFromDescription();

// Đường dẫn còn lại (VD /crm/leads) trả index.html để React Router xử lý
app.MapFallbackToFile("index.html", new StaticFileOptions
{
    OnPrepareResponse = ctx => ctx.Context.Response.Headers.CacheControl = "no-cache, no-store, must-revalidate"
});

app.Run();

public partial class Program;
