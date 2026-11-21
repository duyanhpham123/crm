using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Documents;

/// <summary>core.Attachments - file đã tải lên (lưu trên ổ đĩa máy chủ, đường dẫn tương đối trong StoragePath).</summary>
public sealed class Attachment : ICompanyOwned, ISoftDelete
{
    private Attachment() { }
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public string? EntityName { get; private set; }
    public long? EntityId { get; private set; }
    public string FileName { get; private set; } = "";
    public string ContentType { get; private set; } = "application/octet-stream";
    public long SizeBytes { get; private set; }
    public string StorageProvider { get; private set; } = "local";
    public string StoragePath { get; private set; } = "";
    public string? Checksum { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public long? CreatedBy { get; private set; }
    public bool IsDeleted { get; set; }

    public static Attachment Create(long companyId, string entityName, long? entityId, string fileName, string contentType, long size,
        string storagePath, string checksum, long userId, DateTime nowUtc) => new()
    {
        CompanyId = companyId, EntityName = entityName, EntityId = entityId, FileName = fileName, ContentType = contentType,
        SizeBytes = size, StoragePath = storagePath, Checksum = checksum, CreatedBy = userId, CreatedAt = nowUtc
    };

    public void LinkTo(long entityId) => EntityId = entityId;
}

/// <summary>doc.Folders - thư mục tài liệu. DepartmentId có giá trị = thư mục của phòng ban.</summary>
public sealed class Folder : ICompanyOwned, ISoftDelete, IAuditable
{
    private Folder() { }
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public long? ParentId { get; private set; }
    public string Name { get; private set; } = "";
    public long? OwnerUserId { get; private set; }
    public long? DepartmentId { get; private set; }
    public string? Path { get; private set; }
    public DateTime CreatedAt { get; set; }
    public long? CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public long? UpdatedBy { get; set; }
    public bool IsDeleted { get; set; }

    public static Result<Folder> Create(long companyId, string name, long? parentId, long? departmentId, long ownerId)
    {
        var f = new Folder { CompanyId = companyId, OwnerUserId = ownerId };
        var r = f.Update(name, parentId, departmentId);
        return r.IsFailure ? r.Error! : f;
    }

    public Result Update(string name, long? parentId, long? departmentId)
    {
        if (string.IsNullOrWhiteSpace(name)) return Error.Validation("folder.name", "Nhập tên thư mục.");
        if (parentId is { } p && p == Id && Id != 0) return Error.Validation("folder.parent", "Thư mục cha không hợp lệ.");
        Name = name.Trim(); ParentId = parentId; DepartmentId = departmentId;
        return Result.Success();
    }
}

public sealed record DocumentInfo(string Title, string DocumentType, long? FolderId, long? PartnerId, string Status, DateOnly? EffectiveDate,
    DateOnly? ExpiryDate, decimal? ContractValue, string? Code);

/// <summary>doc.Documents - hợp đồng, quy trình, chính sách, biểu mẫu... mỗi lần tải file mới là một phiên bản.</summary>
public sealed class Document : AuditableEntity, ICompanyOwned
{
    public static readonly string[] Types = ["contract", "policy", "process", "form", "report", "other"];
    public static readonly string[] Statuses = ["draft", "pending_signature", "signed", "active", "expired", "archived"];
    public const int ExpiringDays = 30;

    private Document() { }
    public long CompanyId { get; private set; }
    public long? FolderId { get; private set; }
    public string? Code { get; private set; }
    public string Title { get; private set; } = "";
    public string DocumentType { get; private set; } = "other";
    public long? PartnerId { get; private set; }
    public string? EntityName { get; private set; }
    public long? EntityId { get; private set; }
    public int CurrentVersionNo { get; private set; }
    public long? OwnerUserId { get; private set; }
    public string Status { get; private set; } = "draft";
    public DateOnly? EffectiveDate { get; private set; }
    public DateOnly? ExpiryDate { get; private set; }
    public decimal? ContractValue { get; private set; }

    private readonly List<DocumentVersion> _versions = [];
    public IReadOnlyList<DocumentVersion> Versions => _versions;

    public static Result<Document> Create(long companyId, long ownerId, DocumentInfo info)
    {
        var d = new Document { CompanyId = companyId, OwnerUserId = ownerId };
        var r = d.Update(info);
        return r.IsFailure ? r.Error! : d;
    }

    public Result Update(DocumentInfo i)
    {
        if (string.IsNullOrWhiteSpace(i.Title)) return Error.Validation("document.title", "Nhập tên tài liệu.");
        if (!Types.Contains(i.DocumentType)) return Error.Validation("document.type", "Loại tài liệu không hợp lệ.");
        if (!Statuses.Contains(i.Status)) return Error.Validation("document.status", "Trạng thái không hợp lệ.");
        if (i.EffectiveDate is { } e && i.ExpiryDate is { } x && x < e) return Error.Validation("document.dates", "Ngày hết hạn phải sau ngày hiệu lực.");
        if (i.ContractValue < 0) return Error.Validation("document.value", "Giá trị hợp đồng không hợp lệ.");
        Title = i.Title.Trim(); DocumentType = i.DocumentType; FolderId = i.FolderId; PartnerId = i.PartnerId; Status = i.Status;
        EffectiveDate = i.EffectiveDate; ExpiryDate = i.ExpiryDate; ContractValue = i.ContractValue;
        Code = string.IsNullOrWhiteSpace(i.Code) ? null : i.Code.Trim().ToUpperInvariant();
        return Result.Success();
    }

    /// <summary>Thêm phiên bản file mới (bản đầu tiên là 1).</summary>
    public DocumentVersion AddVersion(long attachmentId, string? note, long userId, DateTime nowUtc)
    {
        CurrentVersionNo = _versions.Count == 0 ? 1 : _versions.Max(v => v.VersionNo) + 1;
        var v = new DocumentVersion(CurrentVersionNo, attachmentId, note, userId, nowUtc);
        _versions.Add(v);
        return v;
    }

    /// <summary>Trạng thái hiển thị: tài liệu có hạn đã qua ngày hết hạn coi như hết hạn.</summary>
    public static string EffectiveStatus(string status, DateOnly? expiry, DateOnly today)
        => status is "archived" ? status : expiry is { } x && x < today ? "expired" : status;

    public static bool IsExpiring(string status, DateOnly? expiry, DateOnly today)
        => status is not ("archived" or "expired") && expiry is { } x && x >= today && x.DayNumber - today.DayNumber <= ExpiringDays;
}

public sealed class DocumentVersion
{
    private DocumentVersion() { }
    internal DocumentVersion(int no, long attachmentId, string? note, long userId, DateTime nowUtc)
    {
        VersionNo = no; AttachmentId = attachmentId; ChangeNote = string.IsNullOrWhiteSpace(note) ? null : note.Trim(); CreatedBy = userId; CreatedAt = nowUtc;
    }
    public long Id { get; private set; }
    public long DocumentId { get; private set; }
    public int VersionNo { get; private set; }
    public long AttachmentId { get; private set; }
    public string? ChangeNote { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public long? CreatedBy { get; private set; }
}
