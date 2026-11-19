using FluentValidation;
using MyERP.Api.Models.DTOs;

namespace MyERP.Api.Validators;

// Quy tắc kiểm tra dữ liệu gửi lên. ValidationFilter tự chạy trước khi vào Controller.

public sealed class LoginRequestValidator : AbstractValidator<LoginRequest>
{
    public LoginRequestValidator()
    {
        RuleFor(x => x.UserName).NotEmpty().WithMessage("Nhập tên đăng nhập.").MaximumLength(255);
        RuleFor(x => x.Password).NotEmpty().WithMessage("Nhập mật khẩu.").MaximumLength(200);
    }
}

public sealed class SetupAdminRequestValidator : AbstractValidator<SetupAdminRequest>
{
    public SetupAdminRequestValidator()
    {
        RuleFor(x => x.FullName).NotEmpty().WithMessage("Nhập họ tên.").MaximumLength(150);
        RuleFor(x => x.Email).EmailAddress().WithMessage("Email không hợp lệ.").When(x => !string.IsNullOrWhiteSpace(x.Email));
        RuleFor(x => x.Password).StrongPassword();
    }
}
