using FluentValidation;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;

namespace MyERP.Api.Validators;

public sealed class SaveRoleRequestValidator : AbstractValidator<SaveRoleRequest>
{
    public SaveRoleRequestValidator()
    {
        RuleFor(x => x.Code)
            .Matches("^[A-Za-z0-9_]{2,50}$").WithMessage("Mã vai trò 2-50 ký tự, chỉ gồm chữ không dấu, số và dấu gạch dưới.")
            .When(x => x.Code is not null);
        RuleFor(x => x.Name).NotEmpty().WithMessage("Nhập tên vai trò.").MaximumLength(100);
        RuleFor(x => x.Description).MaximumLength(500);
        RuleFor(x => x.Permissions).NotNull();
        RuleForEach(x => x.Permissions).ChildRules(p =>
            p.RuleFor(x => x.DataScope).Must(s => DataScopes.All.Contains(s)).WithMessage("Phạm vi dữ liệu không hợp lệ."));
        RuleFor(x => x.Permissions)
            .Must(list => list.Select(p => p.PermissionId).Distinct().Count() == list.Count)
            .WithMessage("Danh sách quyền bị trùng.")
            .When(x => x.Permissions is not null);
    }
}
