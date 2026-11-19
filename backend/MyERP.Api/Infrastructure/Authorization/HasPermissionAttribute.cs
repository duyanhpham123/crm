using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Infrastructure.Authorization;

/// <summary>
/// Gắn lên Controller hoặc Action để yêu cầu quyền:
/// <code>[HasPermission(Permissions.Crm.Edit)]</code>
/// Gắn ở cả Controller và Action thì phải có đủ cả hai quyền.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = true)]
public sealed class HasPermissionAttribute(string permission)
    : AuthorizeAttribute(PermissionPolicyProvider.Prefix + permission)
{
    public string Permission { get; } = permission;
}

public sealed class PermissionRequirement(string permission) : IAuthorizationRequirement
{
    public string Permission { get; } = permission;
}

/// <summary>Kiểm tra người dùng có quyền (tra bảng core.RolePermissions qua PermissionService).</summary>
public sealed class PermissionHandler(ICurrentUser currentUser) : AuthorizationHandler<PermissionRequirement>
{
    protected override async Task HandleRequirementAsync(AuthorizationHandlerContext context, PermissionRequirement requirement)
    {
        if (await currentUser.HasPermissionAsync(requirement.Permission))
            context.Succeed(requirement);
    }
}

/// <summary>Tạo policy "perm:xxx" động - không phải đăng ký từng policy cho từng quyền.</summary>
public sealed class PermissionPolicyProvider(IOptions<AuthorizationOptions> options) : IAuthorizationPolicyProvider
{
    public const string Prefix = "perm:";
    private readonly DefaultAuthorizationPolicyProvider _fallback = new(options);

    public Task<AuthorizationPolicy?> GetPolicyAsync(string policyName)
    {
        if (!policyName.StartsWith(Prefix, StringComparison.Ordinal))
            return _fallback.GetPolicyAsync(policyName);

        var policy = new AuthorizationPolicyBuilder()
            .RequireAuthenticatedUser()
            .AddRequirements(new PermissionRequirement(policyName[Prefix.Length..]))
            .Build();
        return Task.FromResult<AuthorizationPolicy?>(policy);
    }

    public Task<AuthorizationPolicy> GetDefaultPolicyAsync() => _fallback.GetDefaultPolicyAsync();
    public Task<AuthorizationPolicy?> GetFallbackPolicyAsync() => _fallback.GetFallbackPolicyAsync();
}
