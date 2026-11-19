using FluentValidation;
using MyERP.Api.Common;
using MyERP.Api.Models.DTOs;

namespace MyERP.Api.Validators;

public sealed class SaveLeadRequestValidator : AbstractValidator<SaveLeadRequest>
{
    public SaveLeadRequestValidator()
    {
        RuleFor(x => x.FullName).NotEmpty().WithMessage("Nhập họ tên.").MaximumLength(150);
        RuleFor(x => x.OrganizationName).MaximumLength(255);
        RuleFor(x => x.Position).MaximumLength(100);
        RuleFor(x => x.Street).MaximumLength(255);
        RuleFor(x => x.InterestNote).MaximumLength(1000);
        RuleFor(x => x)
            .Must(x => !string.IsNullOrWhiteSpace(x.Phone) || !string.IsNullOrWhiteSpace(x.Email))
            .WithName("Phone").WithMessage("Cần ít nhất số điện thoại hoặc email.");
        RuleFor(x => x.Phone).Must(PhoneNumber.IsValid).WithMessage("Số điện thoại không hợp lệ.")
            .When(x => !string.IsNullOrWhiteSpace(x.Phone));
        RuleFor(x => x.Email).EmailAddress().WithMessage("Email không hợp lệ.").MaximumLength(255)
            .When(x => !string.IsNullOrWhiteSpace(x.Email));
        RuleFor(x => x.EstimatedValue).GreaterThanOrEqualTo(0).WithMessage("Giá trị dự kiến không được âm.");
    }
}

public sealed class ChangeLeadStatusRequestValidator : AbstractValidator<ChangeLeadStatusRequest>
{
    public ChangeLeadStatusRequestValidator()
    {
        RuleFor(x => x.Status).NotEmpty().WithMessage("Chọn trạng thái.");
        RuleFor(x => x.Reason).MaximumLength(500);
    }
}
