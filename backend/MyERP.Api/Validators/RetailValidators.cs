using FluentValidation;
using MyERP.Api.Common;
using MyERP.Api.Models.DTOs;

namespace MyERP.Api.Validators;

public sealed class SaveProductModelRequestValidator : AbstractValidator<SaveProductModelRequest>
{
    public SaveProductModelRequestValidator()
    {
        RuleFor(x => x.Code).Matches("^[A-Za-z0-9_-]{2,20}$").WithMessage("Mã sản phẩm 2-20 ký tự: chữ không dấu, số, gạch ngang.")
            .When(x => !string.IsNullOrWhiteSpace(x.Code));
        RuleFor(x => x.Name).NotEmpty().WithMessage("Nhập tên sản phẩm.").MaximumLength(200);
        RuleFor(x => x.SalePrice).GreaterThanOrEqualTo(0).WithMessage("Giá bán không được âm.");
        RuleFor(x => x.CostPrice).GreaterThanOrEqualTo(0).WithMessage("Giá vốn không được âm.");
        RuleFor(x => x.Gender).Must(g => g is null or "" or "men" or "women" or "unisex" or "kids").WithMessage("Giới tính không hợp lệ.");
        RuleFor(x => x.Colors).Must(c => c.Count <= 20).WithMessage("Tối đa 20 màu.");
        RuleFor(x => x.Sizes).Must(s => s.Count <= 20).WithMessage("Tối đa 20 size.");
        RuleForEach(x => x.Colors).MaximumLength(50);
        RuleForEach(x => x.Sizes).MaximumLength(20);
    }
}

public sealed class UpdateVariantRequestValidator : AbstractValidator<UpdateVariantRequest>
{
    public UpdateVariantRequestValidator()
    {
        RuleFor(x => x.SalePrice).GreaterThanOrEqualTo(0).WithMessage("Giá bán không được âm.");
        RuleFor(x => x.MinStock).GreaterThanOrEqualTo(0).WithMessage("Tồn tối thiểu không được âm.");
        RuleFor(x => x.Barcode).MaximumLength(50);
    }
}

public sealed class CreateStockDocumentRequestValidator : AbstractValidator<CreateStockDocumentRequest>
{
    public CreateStockDocumentRequestValidator()
    {
        RuleFor(x => x.Lines).NotEmpty().WithMessage("Thêm ít nhất một sản phẩm.");
        RuleForEach(x => x.Lines).ChildRules(l =>
        {
            l.RuleFor(x => x.Quantity).NotEqual(0).WithMessage("Số lượng phải khác 0.");
            l.RuleFor(x => x.UnitCost).GreaterThanOrEqualTo(0).WithMessage("Đơn giá không được âm.").When(x => x.UnitCost is not null);
        });
        RuleFor(x => x.Note).MaximumLength(1000);
    }
}

public sealed class SaveOrderRequestValidator : AbstractValidator<SaveOrderRequest>
{
    public SaveOrderRequestValidator()
    {
        RuleFor(x => x.Lines).NotEmpty().WithMessage("Thêm ít nhất một sản phẩm vào đơn.");
        RuleForEach(x => x.Lines).ChildRules(l =>
        {
            l.RuleFor(x => x.Quantity).GreaterThan(0).WithMessage("Số lượng phải lớn hơn 0.");
            l.RuleFor(x => x.UnitPrice).GreaterThanOrEqualTo(0).WithMessage("Đơn giá không được âm.");
            l.RuleFor(x => x.DiscountPercent).InclusiveBetween(0, 100).WithMessage("Chiết khấu từ 0 đến 100%.");
        });
        RuleFor(x => x.ShippingFee).GreaterThanOrEqualTo(0).WithMessage("Phí ship không được âm.");
        RuleFor(x => x.DiscountAmount).GreaterThanOrEqualTo(0).WithMessage("Giảm giá không được âm.");
        RuleFor(x => x.ReceiverPhone).Must(PhoneNumber.IsValid).WithMessage("Số điện thoại người nhận không hợp lệ.")
            .When(x => !string.IsNullOrWhiteSpace(x.ReceiverPhone));
        RuleFor(x => x.Note).MaximumLength(1000);
    }
}

public sealed class CancelOrderRequestValidator : AbstractValidator<CancelOrderRequest>
{
    public CancelOrderRequestValidator() => RuleFor(x => x.Reason).NotEmpty().WithMessage("Nhập lý do hủy.").MaximumLength(500);
}

public sealed class RecordPaymentRequestValidator : AbstractValidator<RecordPaymentRequest>
{
    public RecordPaymentRequestValidator() => RuleFor(x => x.Amount).GreaterThan(0).WithMessage("Số tiền phải lớn hơn 0.");
}

public sealed class SaveSupplierRequestValidator : AbstractValidator<SaveSupplierRequest>
{
    public SaveSupplierRequestValidator()
    {
        RuleFor(x => x.Name).NotEmpty().WithMessage("Nhập tên nhà cung cấp.").MaximumLength(255);
        RuleFor(x => x.TaxCode).Matches(@"^\s*[0-9]{10}(-?[0-9]{3})?\s*$").WithMessage("Mã số thuế gồm 10 hoặc 13 số.")
            .When(x => !string.IsNullOrWhiteSpace(x.TaxCode));
        RuleFor(x => x.Phone).Must(PhoneNumber.IsValid).WithMessage("Số điện thoại không hợp lệ.").When(x => !string.IsNullOrWhiteSpace(x.Phone));
        RuleFor(x => x.Email).EmailAddress().WithMessage("Email không hợp lệ.").When(x => !string.IsNullOrWhiteSpace(x.Email));
        RuleFor(x => x.ContactPhone).Must(PhoneNumber.IsValid).WithMessage("SĐT người liên hệ không hợp lệ.").When(x => !string.IsNullOrWhiteSpace(x.ContactPhone));
    }
}

public sealed class SavePurchaseRequestValidator : AbstractValidator<SavePurchaseRequest>
{
    public SavePurchaseRequestValidator()
    {
        RuleFor(x => x.SupplierId).GreaterThan(0).WithMessage("Chọn nhà cung cấp.");
        RuleFor(x => x.Lines).NotEmpty().WithMessage("Thêm ít nhất một sản phẩm.");
        RuleForEach(x => x.Lines).ChildRules(l =>
        {
            l.RuleFor(x => x.Quantity).GreaterThan(0).WithMessage("Số lượng phải lớn hơn 0.");
            l.RuleFor(x => x.UnitPrice).GreaterThanOrEqualTo(0).WithMessage("Đơn giá không được âm.");
            l.RuleFor(x => x.DiscountPercent).InclusiveBetween(0, 100).WithMessage("Chiết khấu từ 0 đến 100%.");
        });
        RuleFor(x => x.OtherCost).GreaterThanOrEqualTo(0).WithMessage("Chi phí khác không được âm.");
        RuleFor(x => x.ExpectedDate).GreaterThanOrEqualTo(x => x.OrderDate).WithMessage("Ngày dự kiến về không được trước ngày đặt.")
            .When(x => x.ExpectedDate is not null);
    }
}
