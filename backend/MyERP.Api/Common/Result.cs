namespace MyERP.Api.Common;

public enum ErrorType { Validation, NotFound, Conflict, Forbidden, Unauthorized }

/// <summary>Lỗi nghiệp vụ. Controller tự đổi thành HTTP status phù hợp (400/401/403/404/409).</summary>
public sealed record Error(string Code, string Message, ErrorType Type = ErrorType.Validation)
{
    public static Error NotFound(string what) => new($"{what}.not_found", $"Không tìm thấy {what}.", ErrorType.NotFound);
    public static Error Forbidden(string message = "Bạn không có quyền thực hiện thao tác này.") => new("forbidden", message, ErrorType.Forbidden);
    public static Error Conflict(string code, string message) => new(code, message, ErrorType.Conflict);
    public static Error Validation(string code, string message) => new(code, message, ErrorType.Validation);
    public static Error Unauthorized(string message) => new("unauthorized", message, ErrorType.Unauthorized);
}

/// <summary>
/// Kết quả trả về từ Service. Lỗi nghiệp vụ dự đoán được thì trả Result.Failure,
/// không ném exception (exception chỉ dành cho lỗi bất thường).
/// </summary>
public class Result
{
    protected Result(Error? error) => Error = error;

    public Error? Error { get; }
    public bool IsSuccess => Error is null;
    public bool IsFailure => !IsSuccess;

    public static Result Success() => new(null);
    public static Result Failure(Error error) => new(error);

    public static implicit operator Result(Error error) => Failure(error);
}

public sealed class Result<T> : Result
{
    private readonly T? _value;

    private Result(T? value, Error? error) : base(error) => _value = value;

    public T Value => IsSuccess ? _value! : throw new InvalidOperationException("Kết quả thất bại không có Value.");

    public static implicit operator Result<T>(T value) => new(value, null);
    public static implicit operator Result<T>(Error error) => new(default, error);
}
