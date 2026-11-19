using MyERP.Api.Models;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Services.Auth;

namespace MyERP.Tests.Services;

public class AuthTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 19, 8, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Locks_out_after_max_failed_attempts()
    {
        var user = User.CreateForTest("sale01");

        for (var i = 0; i < User.MaxFailedAttempts - 1; i++) user.RecordFailedLogin(Now);
        Assert.False(user.IsLockedOut(Now));

        user.RecordFailedLogin(Now);

        Assert.True(user.IsLockedOut(Now));
        Assert.False(user.IsLockedOut(Now + User.LockoutDuration + TimeSpan.FromSeconds(1)));
    }

    [Fact]
    public void Successful_login_resets_failures()
    {
        var user = User.CreateForTest("sale01");
        user.RecordFailedLogin(Now);
        user.RecordFailedLogin(Now);

        user.RecordSuccessfulLogin(Now);
        for (var i = 0; i < User.MaxFailedAttempts - 1; i++) user.RecordFailedLogin(Now);

        Assert.False(user.IsLockedOut(Now));
    }

    [Fact]
    public void Multiple_roles_take_widest_scope()
    {
        var merged = PermissionService.MergeScopes([
            ("crm.view", "own"),
            ("crm.view", "department"),
            ("crm.edit", "own"),
            ("order.view", "company"),
            ("order.view", "own")
        ]);

        Assert.Equal(DataScope.Department, merged["crm.view"]);
        Assert.Equal(DataScope.Own, merged["crm.edit"]);
        Assert.Equal(DataScope.Company, merged["order.view"]);
    }

    [Fact]
    public void Refresh_token_is_random_and_stored_hashed()
    {
        var (t1, h1) = TokenService.CreateRefreshToken();
        var (t2, _) = TokenService.CreateRefreshToken();

        Assert.NotEqual(t1, t2);
        Assert.NotEqual(t1, h1);
        Assert.Equal(64, h1.Length);
        Assert.Equal(h1, TokenService.Hash(t1));
    }
}
