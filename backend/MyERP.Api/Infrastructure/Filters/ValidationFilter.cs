using FluentValidation;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Mvc.Infrastructure;

namespace MyERP.Api.Infrastructure.Filters;

/// <summary>
/// Chạy trước mọi action: tìm Validator (thư mục Validators/) cho từng tham số
/// và trả 400 kèm danh sách lỗi nếu dữ liệu không hợp lệ. Controller không phải tự kiểm tra.
/// </summary>
public sealed class ValidationFilter(IServiceProvider services, ProblemDetailsFactory problems) : IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        foreach (var argument in context.ActionArguments.Values)
        {
            if (argument is null) continue;
            var validatorType = typeof(IValidator<>).MakeGenericType(argument.GetType());
            if (services.GetService(validatorType) is not IValidator validator) continue;

            var result = await validator.ValidateAsync(new ValidationContext<object>(argument), context.HttpContext.RequestAborted);
            if (result.IsValid) continue;

            foreach (var error in result.Errors)
                context.ModelState.AddModelError(error.PropertyName, error.ErrorMessage);
        }

        if (!context.ModelState.IsValid)
        {
            var details = problems.CreateValidationProblemDetails(context.HttpContext, context.ModelState,
                StatusCodes.Status400BadRequest, "Dữ liệu không hợp lệ.");
            context.Result = new BadRequestObjectResult(details);
            return;
        }

        await next();
    }
}
