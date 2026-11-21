using System.Security.Cryptography;
using Microsoft.AspNetCore.StaticFiles;
using MyERP.Api.Common;

namespace MyERP.Api.Services.Documents;

public sealed record StoredFile(string Path, string FileName, string ContentType, long Size, string Sha256);

/// <summary>Lưu / đọc file tải lên. Hiện lưu trên ổ đĩa máy chủ; đổi sang cloud thì viết lớp khác cùng interface.</summary>
public interface IFileStorage
{
    long MaxBytes { get; }
    IReadOnlyList<string> AllowedExtensions { get; }
    Task<Result<StoredFile>> SaveAsync(IFormFile file, CancellationToken ct);
    Stream? OpenRead(string relativePath);
}

/// <summary>
/// Lưu file vào thư mục Storage:Root (mặc định App_Data/uploads cạnh ứng dụng), chia theo năm/tháng, tên file là GUID
/// để không trùng và không lộ tên gốc. Kiểu file xác định theo phần mở rộng, không tin Content-Type trình duyệt gửi.
/// </summary>
public sealed class LocalFileStorage : IFileStorage
{
    private static readonly string[] Allowed =
        [".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv", ".jpg", ".jpeg", ".png", ".webp", ".gif", ".zip", ".rar"];

    private readonly string _root;
    private readonly FileExtensionContentTypeProvider _types = new();

    public LocalFileStorage(IConfiguration config, IWebHostEnvironment env)
    {
        var configured = config["Storage:Root"];
        _root = Path.GetFullPath(string.IsNullOrWhiteSpace(configured) ? Path.Combine(env.ContentRootPath, "App_Data", "uploads") : configured);
        MaxBytes = config.GetValue("Storage:MaxUploadMb", 20) * 1024L * 1024L;
    }

    public long MaxBytes { get; }
    public IReadOnlyList<string> AllowedExtensions => Allowed;

    public async Task<Result<StoredFile>> SaveAsync(IFormFile file, CancellationToken ct)
    {
        if (file is null || file.Length == 0) return Error.Validation("file.empty", "Chọn file cần tải lên.");
        if (file.Length > MaxBytes) return Error.Validation("file.too_large", $"File tối đa {MaxBytes / 1024 / 1024} MB.");
        var name = Path.GetFileName(file.FileName ?? "").Trim();
        if (name.Length == 0) return Error.Validation("file.name", "Tên file không hợp lệ.");
        if (name.Length > 200) name = name[..(200 - Path.GetExtension(name).Length)] + Path.GetExtension(name);
        var ext = Path.GetExtension(name).ToLowerInvariant();
        if (!Allowed.Contains(ext)) return Error.Validation("file.type", $"Chỉ nhận file: {string.Join(", ", Allowed)}.");

        var now = DateTime.UtcNow;
        var relative = Path.Combine(now.ToString("yyyy"), now.ToString("MM"), $"{Guid.NewGuid():N}{ext}");
        var full = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        string hash;
        await using (var output = new FileStream(full, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, useAsync: true))
        await using (var input = file.OpenReadStream())
        {
            using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            var buffer = new byte[81920];
            int read;
            while ((read = await input.ReadAsync(buffer, ct)) > 0)
            {
                sha.AppendData(buffer, 0, read);
                await output.WriteAsync(buffer.AsMemory(0, read), ct);
            }
            hash = Convert.ToHexString(sha.GetHashAndReset()).ToLowerInvariant();
        }
        var contentType = _types.TryGetContentType(name, out var t) ? t : "application/octet-stream";
        return new StoredFile(relative.Replace('\\', '/'), name, contentType, file.Length, hash);
    }

    public Stream? OpenRead(string relativePath)
    {
        var full = Path.GetFullPath(Path.Combine(_root, relativePath));
        // Chặn đường dẫn kiểu ../../ thoát khỏi thư mục lưu trữ
        if (!full.StartsWith(_root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || !File.Exists(full)) return null;
        return new FileStream(full, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, useAsync: true);
    }
}
