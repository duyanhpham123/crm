using FluentValidation;
using MyERP.Api.Common;
using MyERP.Api.Models.DTOs;

namespace MyERP.Api.Validators;

/// <summary>Quy tắc mật khẩu dùng chung cho mọi nơi đặt mật khẩu.</summary>
public static class PasswordRules
{
    public const int MinLength = 10;

    public static IRuleBuilderOptions<T, string> StrongPassword<T>(this IRuleBuilder<T, string> rule) => rule
        .NotEmpty().WithMessage("Nhập mật khẩu.")
        .MinimumLength(MinLength).WithMessage($"Mật khẩu tối thiểu {MinLength} ký tự.")
        .Matches("[A-Za-z]").WithMessage("Mật khẩu phải có chữ cái.")
        .Matches("[0-9]").WithMessage("Mật khẩu phải có chữ số.")
        .MaximumLength(200);
}

public sealed class CreateUserRequestValidator : AbstractValidator<CreateUserRequest>
{
    public CreateUserRequestValidator()
    {
        RuleFor(x => x.UserName)
            .NotEmpty().WithMessage("Nhập tên đăng nhập.")
            .Matches("^[A-Za-z0-9._-]{3,50}$").WithMessage("Tên đăng nhập 3-50 ký tự, chỉ gồm chữ không dấu, số, dấu chấm, gạch dưới, gạch ngang.");
        RuleFor(x => x.Password).StrongPassword();
        RuleFor(x => x.FullName).NotEmpty().WithMessage("Nhập họ tên.").MaximumLength(150);
        RuleFor(x => x.Email).EmailAddress().WithMessage("Email không hợp lệ.").MaximumLength(255)
            .When(x => !string.IsNullOrWhiteSpace(x.Email));
        RuleFor(x => x.PhoneNumber).Must(PhoneNumber.IsValid).WithMessage("Số điện thoại không hợp lệ.")
            .When(x => !string.IsNullOrWhiteSpace(x.PhoneNumber));
        RuleFor(x => x.RoleIds).NotNull().Must(r => r.Count > 0).WithMessage("Chọn ít nhất một vai trò.");
    }
}

public sealed class UpdateUserRequestValidator : AbstractValidator<UpdateUserRequest>
{
    public UpdateUserRequestValidator()
    {
        RuleFor(x => x.FullName).NotEmpty().WithMessage("Nhập họ tên.").MaximumLength(150);
        RuleFor(x => x.Email).EmailAddress().WithMessage("Email không hợp lệ.").MaximumLength(255)
            .When(x => !string.IsNullOrWhiteSpace(x.Email));
        RuleFor(x => x.PhoneNumber).Must(PhoneNumber.IsValid).WithMessage("Số điện thoại không hợp lệ.")
            .When(x => !string.IsNullOrWhiteSpace(x.PhoneNumber));
        RuleFor(x => x.RoleIds).NotNull().Must(r => r.Count > 0).WithMessage("Chọn ít nhất một vai trò.");
    }
}

public sealed class ResetPasswordRequestValidator : AbstractValidator<ResetPasswordRequest>
{
    public ResetPasswordRequestValidator() => RuleFor(x => x.NewPassword).StrongPassword();
}

public sealed class ChangePasswordRequestValidator : AbstractValidator<ChangePasswordRequest>
{
    public ChangePasswordRequestValidator()
    {
        RuleFor(x => x.CurrentPassword).NotEmpty().WithMessage("Nhập mật khẩu hiện tại.");
        RuleFor(x => x.NewPassword).StrongPassword()
            .NotEqual(x => x.CurrentPassword).WithMessage("Mật khẩu mới phải khác mật khẩu hiện tại.");
    }
}
