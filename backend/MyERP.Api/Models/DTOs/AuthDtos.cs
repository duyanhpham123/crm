namespace MyERP.Api.Models.DTOs;

// DTO = dữ liệu JSON gửi lên / trả về cho frontend. Không trả thẳng Entity ra ngoài.

public sealed record SetupStatusResponse(bool NeedsSetup);

public sealed record SetupAdminRequest(string Password, string FullName, string? Email);

public sealed record LoginRequest(string UserName, string Password);

public sealed record RefreshRequest(string RefreshToken);

public sealed record TokenResponse(string AccessToken, DateTime AccessTokenExpiresAt, string RefreshToken);

public sealed record MeResponse(
    long UserId,
    string UserName,
    string FullName,
    long CompanyId,
    string CompanyName,
    IReadOnlyList<string> Permissions);

public sealed record AppDto(string Code, string Name, string? Icon, string? Color, string? Route);
