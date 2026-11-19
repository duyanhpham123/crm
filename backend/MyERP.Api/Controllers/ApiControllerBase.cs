using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyERP.Api.Common;

namespace MyERP.Api.Controllers;

/// <summary>
/// Lớp cha của mọi API controller:
///  - [ApiController]: tự đọc JSON body, tự trả 400 khi sai kiểu dữ liệu
///  - [Authorize]: mặc định phải đăng nhập (action công khai thì gắn [AllowAnonymous])
///  - Hàm tiện ích đổi Result của Service thành HTTP response JSON
/// </summary>
[ApiController]
[Authorize]
[Produces("application/json")]
public abstract class ApiControllerBase : ControllerBase
{
    /// <summary>Thành công: gọi onSuccess. Thất bại: trả ProblemDetails với status phù hợp.</summary>
    protected IActionResult FromResult<T>(Result<T> result, Func<T, IActionResult> onSuccess)
        => result.IsSuccess ? onSuccess(result.Value) : ErrorResult(result.Error!);

    protected IActionResult FromResult(Result result, Func<IActionResult> onSuccess)
        => result.IsSuccess ? onSuccess() : ErrorResult(result.Error!);

    /// <summary>
    /// Lỗi nghiệp vụ thành JSON chuẩn RFC 9457, VD:
    /// { "status": 409, "title": "Đã có lead LD2611-00001...", "code": "lead.duplicate" }
    /// </summary>
    protected IActionResult ErrorResult(Error error)
    {
        var status = error.Type switch
        {
            ErrorType.NotFound => StatusCodes.Status404NotFound,
            ErrorType.Conflict => StatusCodes.Status409Conflict,
            ErrorType.Forbidden => StatusCodes.Status403Forbidden,
            ErrorType.Unauthorized => StatusCodes.Status401Unauthorized,
            _ => StatusCodes.Status400BadRequest
        };
        var problem = ProblemDetailsFactory.CreateProblemDetails(HttpContext, status, error.Message);
        problem.Extensions["code"] = error.Code;
        return new ObjectResult(problem) { StatusCode = status };
    }
}
