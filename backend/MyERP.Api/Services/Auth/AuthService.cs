using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Core;

namespace MyERP.Api.Services.Auth;

public sealed record ClientInfo(string? IpAddress, string? UserAgent);

public interface IAuthService
{
    Task<SetupStatusResponse> GetSetupStatusAsync(CancellationToken ct);
    Task<Result> SetupAdminAsync(SetupAdminRequest request, CancellationToken ct);
    Task<Result<TokenResponse>> LoginAsync(LoginRequest request, ClientInfo client, CancellationToken ct);
    Task<Result<TokenResponse>> RefreshAsync(RefreshRequest request, ClientInfo client, CancellationToken ct);
    Task LogoutAsync(RefreshRequest request, ClientInfo client, CancellationToken ct);
    Task<Result<TokenResponse>> ChangePasswordAsync(long userId, ChangePasswordRequest request, ClientInfo client, CancellationToken ct);
}

public sealed class AuthService(
    AppDbContext db,
    TokenService tokens,
    IPasswordHasher<User> hasher,
    IOptions<JwtOptions> jwt,
    TimeProvider clock) : IAuthService
{
    private static readonly Error InvalidCredentials = Error.Unauthorized("Tên đăng nhập hoặc mật khẩu không đúng.");

    /// <summary>Lần chạy đầu: tài khoản quản trị chưa có mật khẩu.</summary>
    public async Task<SetupStatusResponse> GetSetupStatusAsync(CancellationToken ct)
        => new(await FindAdminWithoutPassword(ct) is not null);

    public async Task<Result> SetupAdminAsync(SetupAdminRequest request, CancellationToken ct)
    {
        var admin = await FindAdminWithoutPassword(ct);
        if (admin is null)
            return Error.Conflict("setup.done", "Hệ thống đã được thiết lập.");

        admin.SetPassword(hasher.HashPassword(admin, request.Password));
        admin.UpdateProfile(request.FullName, request.Email);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result<TokenResponse>> LoginAsync(LoginRequest request, ClientInfo client, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        var normalized = request.UserName.Trim().ToUpperInvariant();
        var user = await db.Users.FirstOrDefaultAsync(u => u.NormalizedUserName == normalized || u.NormalizedEmail == normalized, ct);

        // Cùng một thông báo cho mọi trường hợp sai: không để lộ tài khoản nào tồn tại.
        if (user is null || !user.IsActive || !user.HasPassword)
            return InvalidCredentials;

        if (user.IsLockedOut(now))
            return Error.Unauthorized($"Tài khoản tạm khóa do đăng nhập sai nhiều lần. Thử lại sau {user.LockoutEnd!.Value.ToLocalTime():HH:mm}.");

        var verify = hasher.VerifyHashedPassword(user, user.PasswordHash!, request.Password);
        if (verify == PasswordVerificationResult.Failed)
        {
            user.RecordFailedLogin(now);
            await db.SaveChangesAsync(ct);
            return InvalidCredentials;
        }
        if (verify == PasswordVerificationResult.SuccessRehashNeeded)
            user.SetPassword(hasher.HashPassword(user, request.Password));

        var membership = await FindMembershipAsync(user, ct);
        if (membership is null)
            return Error.Forbidden("Tài khoản chưa được gán vào công ty nào.");

        user.RecordSuccessfulLogin(now);
        var response = IssueTokens(user, membership, client);
        await db.SaveChangesAsync(ct);
        return response;
    }

    /// <summary>
    /// Xoay vòng refresh token: mỗi token chỉ dùng 1 lần. Nếu token đã thu hồi bị dùng lại
    /// (dấu hiệu bị đánh cắp) thì thu hồi toàn bộ phiên của người dùng đó.
    /// </summary>
    public async Task<Result<TokenResponse>> RefreshAsync(RefreshRequest request, ClientInfo client, CancellationToken ct)
    {
        var nowUtc = clock.GetUtcNow().UtcDateTime;
        var hash = TokenService.Hash(request.RefreshToken);
        var stored = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (stored is null)
            return Error.Unauthorized("Phiên đăng nhập không hợp lệ.");

        if (!stored.IsActive(nowUtc))
        {
            // Chỉ coi là bị đánh cắp khi token ĐÃ ĐƯỢC XOAY VÒNG (có token thay thế) mà vẫn bị dùng lại.
            // Token bị thu hồi do đăng xuất / đổi mật khẩu / admin khóa thì chỉ từ chối, không thu hồi
            // các phiên khác - nếu không, máy cũ tự refresh sẽ đá văng luôn phiên mới hợp lệ.
            if (stored.ReplacedByTokenHash is not null)
            {
                var all = await db.RefreshTokens.Where(t => t.UserId == stored.UserId && t.RevokedAt == null).ToListAsync(ct);
                all.ForEach(t => t.Revoke(nowUtc, client.IpAddress));
                await db.SaveChangesAsync(ct);
            }
            return Error.Unauthorized("Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.");
        }

        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == stored.UserId && u.IsActive, ct);
        var membership = user is null ? null : await FindMembershipAsync(user, ct);
        if (user is null || membership is null)
            return Error.Unauthorized("Tài khoản không còn hoạt động.");

        var response = IssueTokens(user, membership, client);
        stored.Revoke(nowUtc, client.IpAddress, TokenService.Hash(response.RefreshToken));
        await db.SaveChangesAsync(ct);
        return response;
    }

    public async Task LogoutAsync(RefreshRequest request, ClientInfo client, CancellationToken ct)
    {
        var hash = TokenService.Hash(request.RefreshToken);
        var stored = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (stored is null) return;
        stored.Revoke(clock.GetUtcNow().UtcDateTime, client.IpAddress);
        await db.SaveChangesAsync(ct);
    }

    /// <summary>
    /// Người dùng tự đổi mật khẩu: thu hồi mọi phiên đăng nhập cũ (kể cả trên máy khác)
    /// rồi cấp cặp token mới cho phiên hiện tại để không bị đăng xuất.
    /// </summary>
    public async Task<Result<TokenResponse>> ChangePasswordAsync(long userId, ChangePasswordRequest request, ClientInfo client, CancellationToken ct)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId && u.IsActive, ct);
        if (user is null || !user.HasPassword)
            return Error.Unauthorized("Tài khoản không còn hoạt động.");

        if (hasher.VerifyHashedPassword(user, user.PasswordHash!, request.CurrentPassword) == PasswordVerificationResult.Failed)
            return Error.Validation("auth.wrong_password", "Mật khẩu hiện tại không đúng.");

        var membership = await FindMembershipAsync(user, ct);
        if (membership is null)
            return Error.Forbidden("Tài khoản chưa được gán vào công ty nào.");

        user.SetPassword(hasher.HashPassword(user, request.NewPassword));
        var nowUtc = clock.GetUtcNow().UtcDateTime;
        var sessions = await db.RefreshTokens.Where(t => t.UserId == userId && t.RevokedAt == null).ToListAsync(ct);
        sessions.ForEach(t => t.Revoke(nowUtc, client.IpAddress));

        var response = IssueTokens(user, membership, client);
        await db.SaveChangesAsync(ct);
        return response;
    }

    private TokenResponse IssueTokens(User user, UserCompany membership, ClientInfo client)
    {
        var (access, expires) = tokens.CreateAccessToken(user, membership);
        var (refresh, refreshHash) = TokenService.CreateRefreshToken();
        db.RefreshTokens.Add(RefreshToken.Issue(user.Id, refreshHash, clock.GetUtcNow().UtcDateTime,
            TimeSpan.FromDays(jwt.Value.RefreshTokenDays), client.IpAddress, client.UserAgent));
        return new TokenResponse(access, expires, refresh);
    }

    private Task<UserCompany?> FindMembershipAsync(User user, CancellationToken ct)
        => (from uc in db.UserCompanies
            join c in db.Companies on uc.CompanyId equals c.Id
            where uc.UserId == user.Id
            orderby uc.CompanyId == user.DefaultCompanyId descending, uc.IsDefault descending, uc.CompanyId
            select uc).FirstOrDefaultAsync(ct);

    private Task<User?> FindAdminWithoutPassword(CancellationToken ct)
        => db.Users.Where(u => u.IsSystemAdmin && u.IsActive && (u.PasswordHash == null || u.PasswordHash == ""))
            .OrderBy(u => u.Id).FirstOrDefaultAsync(ct);
}
