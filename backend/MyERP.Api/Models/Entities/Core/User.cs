namespace MyERP.Api.Models.Entities.Core;

/// <summary>Bảng core.Users - tài khoản đăng nhập.</summary>
public sealed class User : AuditableEntity
{
    public const int MaxFailedAttempts = 5;
    public static readonly TimeSpan LockoutDuration = TimeSpan.FromMinutes(15);

    private User() { }

    public string UserName { get; private set; } = "";
    public string NormalizedUserName { get; private set; } = "";
    public string? Email { get; private set; }
    public string? NormalizedEmail { get; private set; }
    public string? PhoneNumber { get; private set; }
    public string? PasswordHash { get; private set; }
    public string? SecurityStamp { get; private set; }
    public string FullName { get; private set; } = "";
    public long? DefaultCompanyId { get; private set; }
    public bool IsSystemAdmin { get; private set; }
    public bool IsActive { get; private set; }
    public bool LockoutEnabled { get; private set; }
    public DateTimeOffset? LockoutEnd { get; private set; }
    public int AccessFailedCount { get; private set; }
    public DateTime? LastLoginAt { get; private set; }

    /// <summary>Công ty / phòng ban người dùng thuộc về (core.UserCompanies).</summary>
    public List<UserCompany> Memberships { get; private set; } = [];

    /// <summary>Vai trò của người dùng (core.UserRoles).</summary>
    public List<UserRole> UserRoles { get; private set; } = [];

    public bool HasPassword => !string.IsNullOrEmpty(PasswordHash);

    public bool IsLockedOut(DateTimeOffset now) => LockoutEnabled && LockoutEnd > now;

    /// <summary>Tạo tài khoản mới thuộc một công ty. Mật khẩu đặt riêng bằng SetPassword.</summary>
    public static User Create(string userName, string fullName, string? email, string? phone, long companyId)
    {
        var user = new User
        {
            UserName = userName.Trim().ToLowerInvariant(),
            DefaultCompanyId = companyId,
            IsActive = true,
            LockoutEnabled = true,
            SecurityStamp = Guid.NewGuid().ToString("N")
        };
        user.NormalizedUserName = user.UserName.ToUpperInvariant();
        user.UpdateProfile(fullName, email, phone);
        return user;
    }

    public void SetPassword(string passwordHash)
    {
        PasswordHash = passwordHash;
        SecurityStamp = Guid.NewGuid().ToString("N");   // đổi mật khẩu thì phiên cũ hết hiệu lực
        AccessFailedCount = 0;
        LockoutEnd = null;
    }

    public void UpdateProfile(string fullName, string? email, string? phone = null)
    {
        FullName = fullName.Trim();
        Email = string.IsNullOrWhiteSpace(email) ? null : email.Trim().ToLowerInvariant();
        NormalizedEmail = Email?.ToUpperInvariant();
        PhoneNumber = string.IsNullOrWhiteSpace(phone) ? null : phone.Trim();
    }

    /// <summary>Khóa / mở khóa tài khoản. Mở khóa thì xóa luôn trạng thái tạm khóa do sai mật khẩu.</summary>
    public void SetActive(bool active)
    {
        IsActive = active;
        if (active) Unlock();
    }

    public void Unlock()
    {
        AccessFailedCount = 0;
        LockoutEnd = null;
    }

    /// <summary>Sai mật khẩu quá 5 lần thì khóa 15 phút - chống dò mật khẩu.</summary>
    public void RecordFailedLogin(DateTimeOffset now)
    {
        AccessFailedCount++;
        if (LockoutEnabled && AccessFailedCount >= MaxFailedAttempts)
        {
            LockoutEnd = now.Add(LockoutDuration);
            AccessFailedCount = 0;
        }
    }

    public void RecordSuccessfulLogin(DateTimeOffset now)
    {
        AccessFailedCount = 0;
        LockoutEnd = null;
        LastLoginAt = now.UtcDateTime;
    }

    /// <summary>Chỉ dùng cho unit test.</summary>
    internal static User CreateForTest(string userName, bool lockoutEnabled = true) => new()
    {
        UserName = userName,
        NormalizedUserName = userName.ToUpperInvariant(),
        FullName = userName,
        IsActive = true,
        LockoutEnabled = lockoutEnabled
    };
}
