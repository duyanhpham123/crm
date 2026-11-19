using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace MyERP.Api.Infrastructure.Middleware;

/// <summary>Bắt mọi exception chưa xử lý, trả JSON ProblemDetails, không lộ stack trace ra ngoài.</summary>
public sealed class GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger, IProblemDetailsService problemDetails)
    : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken ct)
    {
        var (status, title) = exception switch
        {
            DbUpdateConcurrencyException => (StatusCodes.Status409Conflict, "Dữ liệu đã bị người khác thay đổi. Hãy tải lại rồi thử lại."),
            UnauthorizedAccessException => (StatusCodes.Status403Forbidden, "Bạn không có quyền thực hiện thao tác này."),
            _ => (StatusCodes.Status500InternalServerError, "Hệ thống gặp lỗi. Vui lòng thử lại sau.")
        };

        if (status == StatusCodes.Status500InternalServerError)
            logger.LogError(exception, "Unhandled exception on {Method} {Path}", httpContext.Request.Method, httpContext.Request.Path);

        httpContext.Response.StatusCode = status;
        return await problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails = new ProblemDetails { Status = status, Title = title },
            Exception = exception
        });
    }
}
