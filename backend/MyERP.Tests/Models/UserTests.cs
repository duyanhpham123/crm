using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Validators;

namespace MyERP.Tests.Models;

public class UserTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 19, 8, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Create_normalizes_username_and_email()
    {
        var user = User.Create("  Sale.An ", " Nguyễn Văn An ", " An@ABC.vn ", " 0912345678 ", 1);

        Assert.Equal("sale.an", user.UserName);
        Assert.Equal("SALE.AN", user.NormalizedUserName);
        Assert.Equal("Nguyễn Văn An", user.FullName);
        Assert.Equal("an@abc.vn", user.Email);
        Assert.Equal("AN@ABC.VN", user.NormalizedEmail);
        Assert.True(user.IsActive);
        Assert.False(user.IsSystemAdmin);
        Assert.Equal(1, user.DefaultCompanyId);
    }

    [Fact]
    public void Reactivating_clears_lockout()
    {
        var user = User.Create("sale01", "Sale", null, null, 1);
        for (var i = 0; i < User.MaxFailedAttempts; i++) user.RecordFailedLogin(Now);
        Assert.True(user.IsLockedOut(Now));

        user.SetActive(false);
        user.SetActive(true);

        Assert.False(user.IsLockedOut(Now));
    }

    [Theory]
    [InlineData("sale01", true)]
    [InlineData("nguyen.van-an_2", true)]
    [InlineData("ab", false)]
    [InlineData("nguyễn", false)]
    [InlineData("có khoảng trắng", false)]
    public void Username_format(string userName, bool valid)
    {
        var result = new CreateUserRequestValidator().Validate(
            new CreateUserRequest(userName, "Tên", null, null, null, [1], "MatKhau12345"));
        Assert.Equal(valid, !result.Errors.Any(e => e.PropertyName == nameof(CreateUserRequest.UserName)));
    }

    [Theory]
    [InlineData("short1", false)]
    [InlineData("chicochucai", false)]
    [InlineData("1234567890", false)]
    [InlineData("MatKhau12345", true)]
    public void Password_policy(string password, bool valid)
        => Assert.Equal(valid, new ResetPasswordRequestValidator().Validate(new ResetPasswordRequest(password)).IsValid);

    [Fact]
    public void New_password_must_differ()
    {
        var result = new ChangePasswordRequestValidator().Validate(new ChangePasswordRequest("MatKhau12345", "MatKhau12345"));
        Assert.Contains(result.Errors, e => e.ErrorMessage.Contains("khác"));
    }
}
