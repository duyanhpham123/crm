using FluentValidation;
using MyERP.Api.Common;
using MyERP.Api.Models.DTOs;

namespace MyERP.Api.Validators;

public sealed class SaveCustomerRequestValidator : AbstractValidator<SaveCustomerRequest>
{
    public SaveCustomerRequestValidator()
    {
        RuleFor(x => x.PartnerType).Must(t => t is "company" or "individual").WithMessage("Loại khách hàng không hợp lệ.");
        RuleFor(x => x.Name).NotEmpty().WithMessage("Nhập tên khách hàng.").MaximumLength(255);
        RuleFor(x => x.ShortName).MaximumLength(100);
        RuleFor(x => x.TaxCode)
            .Matches(@"^\s*[0-9]{10}(-?[0-9]{3})?\s*$").WithMessage("Mã số thuế gồm 10 số hoặc 13 số (10 số + 3 số chi nhánh).")
            .When(x => !string.IsNullOrWhiteSpace(x.TaxCode));
        RuleFor(x => x.Phone).Must(PhoneNumber.IsValid).WithMessage("Số điện thoại không hợp lệ.")
            .When(x => !string.IsNullOrWhiteSpace(x.Phone));
        RuleFor(x => x.Email).EmailAddress().WithMessage("Email không hợp lệ.").MaximumLength(255)
            .When(x => !string.IsNullOrWhiteSpace(x.Email));
        RuleFor(x => x.Website).MaximumLength(255);
        RuleFor(x => x.Industry).MaximumLength(100);
        RuleFor(x => x.Street).MaximumLength(255);
        RuleFor(x => x.PrimaryContact!).SetValidator(new SaveContactRequestValidator())
            .When(x => x.PrimaryContact is not null && !string.IsNullOrWhiteSpace(x.PrimaryContact.FullName));
    }
}

public sealed class SaveContactRequestValidator : AbstractValidator<SaveContactRequest>
{
    public SaveContactRequestValidator()
    {
        RuleFor(x => x.FullName).NotEmpty().WithMessage("Nhập họ tên người liên hệ.").MaximumLength(150);
        RuleFor(x => x.Position).MaximumLength(100);
        RuleFor(x => x.Phone).Must(PhoneNumber.IsValid).WithMessage("Số điện thoại người liên hệ không hợp lệ.")
            .When(x => !string.IsNullOrWhiteSpace(x.Phone));
        RuleFor(x => x.Email).EmailAddress().WithMessage("Email người liên hệ không hợp lệ.")
            .When(x => !string.IsNullOrWhiteSpace(x.Email));
        RuleFor(x => x.Note).MaximumLength(1000);
    }
}

public sealed class SaveOpportunityRequestValidator : AbstractValidator<SaveOpportunityRequest>
{
    public SaveOpportunityRequestValidator()
    {
        RuleFor(x => x.Name).NotEmpty().WithMessage("Nhập tên cơ hội.").MaximumLength(255);
        RuleFor(x => x.CustomerId).GreaterThan(0).WithMessage("Chọn khách hàng.");
        RuleFor(x => x.ExpectedRevenue).GreaterThanOrEqualTo(0).WithMessage("Giá trị dự kiến không được âm.");
        RuleFor(x => x.Probability).InclusiveBetween(0, 100).WithMessage("Xác suất từ 0 đến 100%.").When(x => x.Probability is not null);
        RuleFor(x => x.Priority).InclusiveBetween((byte)0, (byte)3).WithMessage("Độ ưu tiên từ 0 đến 3 sao.");
    }
}

public sealed class ConvertLeadRequestValidator : AbstractValidator<ConvertLeadRequest>
{
    public ConvertLeadRequestValidator()
    {
        RuleFor(x => x.OpportunityName).NotEmpty().WithMessage("Nhập tên cơ hội.").MaximumLength(255).When(x => x.CreateOpportunity);
        RuleFor(x => x.ExpectedRevenue).GreaterThanOrEqualTo(0).WithMessage("Giá trị dự kiến không được âm.").When(x => x.ExpectedRevenue is not null);
    }
}
