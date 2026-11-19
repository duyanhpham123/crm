using System.Reflection;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;
using MyERP.Api.Controllers;
using MyERP.Api.Infrastructure.Authorization;

namespace MyERP.Tests;

/// <summary>
/// Kiểm tra quy ước của dự án để code mới không vô tình phá vỡ.
/// Thêm controller mới mà quên kế thừa ApiControllerBase hoặc quên phân quyền thì test báo lỗi ngay.
/// </summary>
public class ConventionTests
{
    private static readonly Type[] Controllers = typeof(ApiControllerBase).Assembly.GetTypes()
        .Where(t => typeof(ControllerBase).IsAssignableFrom(t) && !t.IsAbstract)
        .ToArray();

    private static readonly string[] PublicRoutes = ["api/auth"];

    [Fact]
    public void All_controllers_inherit_ApiControllerBase()
    {
        var bad = Controllers.Where(c => !c.IsSubclassOf(typeof(ApiControllerBase))).Select(c => c.Name).ToList();
        Assert.True(bad.Count == 0, $"Controller phải kế thừa ApiControllerBase: {string.Join(", ", bad)}");
    }

    [Fact]
    public void Only_auth_controller_allows_anonymous()
    {
        var bad = new List<string>();
        foreach (var controller in Controllers)
        {
            var route = controller.GetCustomAttribute<RouteAttribute>()?.Template ?? "";
            var publicController = controller.GetCustomAttribute<AllowAnonymousAttribute>() is not null;
            if (publicController && !PublicRoutes.Contains(route)) bad.Add(controller.Name);

            bad.AddRange(controller.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                .Where(m => m.GetCustomAttribute<AllowAnonymousAttribute>() is not null && !PublicRoutes.Contains(route))
                .Select(m => $"{controller.Name}.{m.Name}"));
        }
        Assert.True(bad.Count == 0, $"[AllowAnonymous] ngoài API đăng nhập: {string.Join(", ", bad)}");
    }

    [Fact]
    public void Business_controllers_require_a_permission()
    {
        // Controller nghiệp vụ (api/crm, api/sales...) bắt buộc có [HasPermission] ở cấp controller
        var bad = Controllers
            .Where(c => (c.GetCustomAttribute<RouteAttribute>()?.Template ?? "") is var r
                        && r.StartsWith("api/") && r.Count(ch => ch == '/') >= 2 && !PublicRoutes.Contains(r))
            .Where(c => c.GetCustomAttribute<HasPermissionAttribute>() is null)
            .Select(c => c.Name).ToList();
        Assert.True(bad.Count == 0, $"Thiếu [HasPermission] trên controller: {string.Join(", ", bad)}");
    }

    [Fact]
    public void Write_actions_require_specific_permission()
    {
        // POST/PUT/DELETE trong controller nghiệp vụ phải có [HasPermission] riêng (create/edit/delete)
        var bad = Controllers
            .Where(c => c.GetCustomAttribute<HasPermissionAttribute>() is not null)
            .SelectMany(c => c.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                .Where(m => m.GetCustomAttributes<HttpMethodAttribute>().Any(h => h.HttpMethods.Any(v => v is "POST" or "PUT" or "DELETE" or "PATCH")))
                .Where(m => m.GetCustomAttribute<HasPermissionAttribute>() is null)
                .Select(m => $"{c.Name}.{m.Name}"))
            .ToList();
        Assert.True(bad.Count == 0, $"Action ghi dữ liệu thiếu [HasPermission]: {string.Join(", ", bad)}");
    }
}
