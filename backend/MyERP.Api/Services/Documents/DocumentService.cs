using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Documents;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Documents;

public interface IDocumentService
{
    Task<DocumentLookups> GetLookupsAsync(CancellationToken ct);
    Task<DocumentPage> ListAsync(long? folderId, string? type, string? status, string? search, long? partnerId, int page, int pageSize, CancellationToken ct);
    Task<Result<DocumentDetail>> GetAsync(long id, CancellationToken ct);
    Task<Result<DocumentDetail>> CreateAsync(SaveDocumentRequest request, CancellationToken ct);
    Task<Result<DocumentDetail>> UpdateAsync(long id, SaveDocumentRequest request, CancellationToken ct);
    Task<Result<DocumentDetail>> UploadVersionAsync(long id, IFormFile file, string? note, CancellationToken ct);
    Task<Result> DeleteAsync(long id, CancellationToken ct);
    Task<Result<FileDownload>> DownloadAsync(long attachmentId, CancellationToken ct);
    Task<Result<FolderDto>> CreateFolderAsync(SaveFolderRequest request, CancellationToken ct);
    Task<Result<FolderDto>> UpdateFolderAsync(long id, SaveFolderRequest request, CancellationToken ct);
    Task<Result> DeleteFolderAsync(long id, CancellationToken ct);
}

/// <summary>
/// Kho tài liệu: thư mục chung / theo phòng ban, hợp đồng có ngày hiệu lực - hết hạn (cảnh báo trước 30 ngày), nhiều phiên bản file.
/// Phạm vi xem theo quyền document.view: own = tài liệu của mình + thư mục chung + thư mục phòng mình; company = tất cả.
/// </summary>
public sealed class DocumentService(AppDbContext db, ICurrentUser currentUser, IFileStorage storage, TimeProvider clock) : IDocumentService
{
    public static readonly IReadOnlyList<CodeOption> Types =
    [
        new("contract", "Hợp đồng"), new("policy", "Chính sách / quy định"), new("process", "Quy trình"), new("form", "Biểu mẫu"),
        new("report", "Báo cáo"), new("other", "Khác")
    ];

    public static readonly IReadOnlyList<CodeOption> Statuses =
    [
        new("draft", "Nháp"), new("pending_signature", "Chờ ký"), new("signed", "Đã ký"), new("active", "Đang hiệu lực"),
        new("expired", "Hết hạn"), new("archived", "Lưu trữ")
    ];

    private DateTime NowUtc => clock.GetUtcNow().UtcDateTime;
    private DateOnly Today => DateOnly.FromDateTime(NowUtc.AddHours(7));

    private sealed record Scope(DataScope Level, long UserId, long? DepartmentId);

    private async Task<Scope> ScopeAsync(CancellationToken ct)
        => new(await currentUser.GetScopeAsync(Permissions.Documents.View, ct) ?? DataScope.Own, currentUser.RequireUserId(), currentUser.DepartmentId);

    private IQueryable<Folder> VisibleFolders(Scope s)
    {
        if (s.Level >= DataScope.Company) return db.Folders;
        var me = s.UserId;
        var dept = s.DepartmentId;
        return db.Folders.Where(f => f.DepartmentId == null || f.DepartmentId == dept || f.OwnerUserId == me);
    }

    /// <summary>Tài liệu trong thư mục mình xem được, hoặc do mình phụ trách / tạo.</summary>
    private IQueryable<Document> VisibleDocuments(Scope s)
    {
        if (s.Level >= DataScope.Company) return db.Documents;
        var me = s.UserId;
        var folders = VisibleFolders(s).Select(f => f.Id);
        return db.Documents.Where(d => d.OwnerUserId == me || d.CreatedBy == me || (d.FolderId != null && folders.Contains(d.FolderId.Value)));
    }

    private static bool CanModify(Document d, Scope s) => s.Level >= DataScope.Department || d.OwnerUserId == s.UserId || d.CreatedBy == s.UserId;

    public async Task<DocumentLookups> GetLookupsAsync(CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var docs = VisibleDocuments(scope);
        var folders = await VisibleFolders(scope).AsNoTracking().OrderBy(f => f.DepartmentId != null).ThenBy(f => f.Name)
            .Select(f => new FolderDto(f.Id, f.Name, f.ParentId, f.DepartmentId,
                db.Departments.Where(d => d.Id == f.DepartmentId).Select(d => d.Name).FirstOrDefault(),
                docs.Count(d => d.FolderId == f.Id))).ToListAsync(ct);
        var departments = await db.Departments.Where(d => d.IsActive).OrderBy(d => d.SortOrder).Select(d => new OptionDto(d.Id, d.Name, d.Code)).ToListAsync(ct);
        return new DocumentLookups(folders, departments, Types, Statuses, storage.MaxBytes, storage.AllowedExtensions);
    }

    public async Task<DocumentPage> ListAsync(long? folderId, string? type, string? status, string? search, long? partnerId, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var scope = await ScopeAsync(ct);
        var today = Today;
        var soon = today.AddDays(Document.ExpiringDays);
        var all = VisibleDocuments(scope).AsNoTracking();
        var q = all;
        if (folderId is { } fid) q = q.Where(d => d.FolderId == fid);
        if (!string.IsNullOrEmpty(type)) q = q.Where(d => d.DocumentType == type);
        if (partnerId is { } pid) q = q.Where(d => d.PartnerId == pid);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            q = q.Where(d => d.Title.Contains(s) || (d.Code != null && d.Code.Contains(s)) || db.Partners.Any(p => p.Id == d.PartnerId && p.Name.Contains(s)));
        }
        q = status switch
        {
            null or "" => q,
            "expired" => q.Where(d => d.Status != "archived" && (d.Status == "expired" || d.ExpiryDate < today)),
            "expiring" => q.Where(d => d.Status != "archived" && d.Status != "expired" && d.ExpiryDate >= today && d.ExpiryDate <= soon),
            "archived" => q.Where(d => d.Status == "archived"),
            _ => q.Where(d => d.Status == status && !(d.ExpiryDate < today)),
        };
        var total = await q.CountAsync(ct);
        var rows = await q.OrderBy(d => d.Status == "archived").ThenByDescending(d => d.UpdatedAt ?? d.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(d => new
            {
                d.Id, d.Code, d.Title, d.DocumentType, d.FolderId, d.Status, d.EffectiveDate, d.ExpiryDate, d.ContractValue, d.CurrentVersionNo,
                Updated = d.UpdatedAt ?? d.CreatedAt,
                Folder = db.Folders.Where(f => f.Id == d.FolderId).Select(f => f.Name).FirstOrDefault(),
                Partner = db.Partners.Where(p => p.Id == d.PartnerId).Select(p => p.Name).FirstOrDefault(),
                Owner = db.Users.Where(u => u.Id == d.OwnerUserId).Select(u => u.FullName).FirstOrDefault(),
                File = d.Versions.OrderByDescending(v => v.VersionNo)
                    .Select(v => db.Attachments.Where(a => a.Id == v.AttachmentId).Select(a => new { a.FileName, a.SizeBytes }).FirstOrDefault()).FirstOrDefault(),
            }).ToListAsync(ct);
        var items = rows.Select(d => new DocumentListItem(d.Id, d.Code, d.Title, d.DocumentType, d.FolderId, d.Folder, d.Partner,
            Document.EffectiveStatus(d.Status, d.ExpiryDate, today), d.EffectiveDate, d.ExpiryDate,
            d.ExpiryDate is { } x ? x.DayNumber - today.DayNumber : null, Document.IsExpiring(d.Status, d.ExpiryDate, today), d.ContractValue,
            d.CurrentVersionNo, d.File?.FileName, d.File?.SizeBytes, d.Owner, d.Updated)).ToList();

        var summary = new DocumentSummary(
            await all.CountAsync(ct),
            await all.CountAsync(d => d.DocumentType == "contract", ct),
            await all.CountAsync(d => d.Status != "archived" && d.Status != "expired" && d.ExpiryDate >= today && d.ExpiryDate <= soon, ct),
            await all.CountAsync(d => d.Status != "archived" && (d.Status == "expired" || d.ExpiryDate < today), ct),
            await all.CountAsync(d => d.Status == "pending_signature", ct),
            await all.Where(d => d.DocumentType == "contract" && (d.Status == "signed" || d.Status == "active") && !(d.ExpiryDate < today))
                .SumAsync(d => d.ContractValue ?? 0, ct));
        return new DocumentPage(new PagedResult<DocumentListItem>(items, page, pageSize, total), summary);
    }

    public async Task<Result<DocumentDetail>> GetAsync(long id, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var d = await VisibleDocuments(scope).Include(x => x.Versions).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return d is null ? Error.NotFound("tài liệu") : await ToDetailAsync(d, scope, ct);
    }

    public async Task<Result<DocumentDetail>> CreateAsync(SaveDocumentRequest r, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var refs = await ValidateRefsAsync(r, scope, ct);
        if (refs.IsFailure) return refs.Error!;
        var created = Document.Create(currentUser.RequireCompanyId(), scope.UserId, ToInfo(r));
        if (created.IsFailure) return created.Error!;
        db.Documents.Add(created.Value);
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(created.Value, scope, ct);
    }

    public async Task<Result<DocumentDetail>> UpdateAsync(long id, SaveDocumentRequest r, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var d = await VisibleDocuments(scope).Include(x => x.Versions).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (d is null) return Error.NotFound("tài liệu");
        if (!CanModify(d, scope)) return Error.Forbidden("Chỉ người phụ trách tài liệu được sửa.");
        var refs = await ValidateRefsAsync(r, scope, ct);
        if (refs.IsFailure) return refs.Error!;
        if (!string.IsNullOrEmpty(r.RowVersion)) db.Entry(d).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(r.RowVersion);
        var u = d.Update(ToInfo(r));
        if (u.IsFailure) return u.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(d, scope, ct);
    }

    private async Task<Result> ValidateRefsAsync(SaveDocumentRequest r, Scope scope, CancellationToken ct)
    {
        if (r.FolderId is { } fid && !await VisibleFolders(scope).AnyAsync(f => f.Id == fid, ct)) return Error.Validation("document.folder", "Thư mục không hợp lệ.");
        if (r.PartnerId is { } pid && !await db.Partners.AnyAsync(p => p.Id == pid, ct)) return Error.Validation("document.partner", "Đối tác không hợp lệ.");
        return Result.Success();
    }

    private static DocumentInfo ToInfo(SaveDocumentRequest r) => new(r.Title, r.Type, r.FolderId, r.PartnerId, r.Status, r.EffectiveDate, r.ExpiryDate,
        r.ContractValue, r.Code);

    public async Task<Result<DocumentDetail>> UploadVersionAsync(long id, IFormFile file, string? note, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var d = await VisibleDocuments(scope).Include(x => x.Versions).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (d is null) return Error.NotFound("tài liệu");
        if (!CanModify(d, scope)) return Error.Forbidden("Chỉ người phụ trách tài liệu được tải phiên bản mới.");
        if (note?.Length > 500) return Error.Validation("document.note", "Ghi chú tối đa 500 ký tự.");
        var stored = await storage.SaveAsync(file, ct);
        if (stored.IsFailure) return stored.Error!;
        var f = stored.Value;
        var att = Attachment.Create(d.CompanyId, "document", d.Id, f.FileName, f.ContentType, f.Size, f.Path, f.Sha256, scope.UserId, NowUtc);
        db.Attachments.Add(att);
        await db.SaveChangesAsync(ct);
        d.AddVersion(att.Id, note, scope.UserId, NowUtc);
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(d, scope, ct);
    }

    public async Task<Result> DeleteAsync(long id, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var d = await VisibleDocuments(scope).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (d is null) return Error.NotFound("tài liệu");
        if (!CanModify(d, scope)) return Error.Forbidden("Chỉ người phụ trách tài liệu được xóa.");
        db.Documents.Remove(d); // xóa mềm - file vẫn giữ để khôi phục khi cần
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result<FileDownload>> DownloadAsync(long attachmentId, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var docs = VisibleDocuments(scope);
        var att = await db.Attachments.AsNoTracking().FirstOrDefaultAsync(a => a.Id == attachmentId
            && db.DocumentVersions.Any(v => v.AttachmentId == a.Id && docs.Any(d => d.Id == v.DocumentId)), ct);
        if (att is null) return Error.NotFound("file");
        var stream = storage.OpenRead(att.StoragePath);
        return stream is null ? Error.NotFound("file trên máy chủ") : new FileDownload(stream, att.FileName, att.ContentType);
    }

    private async Task<DocumentDetail> ToDetailAsync(Document d, Scope scope, CancellationToken ct)
    {
        var today = Today;
        var attIds = d.Versions.Select(v => v.AttachmentId).ToList();
        var atts = await db.Attachments.AsNoTracking().Where(a => attIds.Contains(a.Id)).ToDictionaryAsync(a => a.Id, ct);
        var userIds = d.Versions.Select(v => v.CreatedBy).Append(d.OwnerUserId).Where(x => x != null).Select(x => x!.Value).Distinct().ToList();
        var names = await db.Users.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName, ct);
        var folder = d.FolderId is { } fid ? await db.Folders.Where(f => f.Id == fid).Select(f => f.Name).FirstOrDefaultAsync(ct) : null;
        var partner = d.PartnerId is { } pid ? await db.Partners.Where(p => p.Id == pid).Select(p => p.Name).FirstOrDefaultAsync(ct) : null;
        var versions = d.Versions.OrderByDescending(v => v.VersionNo).Select(v =>
        {
            var a = atts.GetValueOrDefault(v.AttachmentId);
            return new DocumentVersionDto(v.Id, v.VersionNo, v.AttachmentId, a?.FileName ?? "(đã xóa)", a?.ContentType ?? "", a?.SizeBytes ?? 0, v.ChangeNote,
                v.CreatedBy is { } cb ? names.GetValueOrDefault(cb) : null, v.CreatedAt);
        }).ToList();
        var canEdit = CanModify(d, scope) && await currentUser.HasPermissionAsync(Permissions.Documents.Edit, ct);
        return new DocumentDetail(d.Id, d.Code, d.Title, d.DocumentType, d.FolderId, folder, d.PartnerId, partner,
            Document.EffectiveStatus(d.Status, d.ExpiryDate, today), d.Status, d.EffectiveDate, d.ExpiryDate,
            d.ExpiryDate is { } x ? x.DayNumber - today.DayNumber : null, Document.IsExpiring(d.Status, d.ExpiryDate, today), d.ContractValue,
            d.OwnerUserId is { } o ? names.GetValueOrDefault(o) : null, versions, d.CreatedAt, canEdit, Convert.ToBase64String(d.RowVersion));
    }

    // ---------- Thư mục ----------

    public async Task<Result<FolderDto>> CreateFolderAsync(SaveFolderRequest r, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var check = await ValidateFolderAsync(null, r, scope, ct);
        if (check.IsFailure) return check.Error!;
        var created = Folder.Create(currentUser.RequireCompanyId(), r.Name, r.ParentId, r.DepartmentId, scope.UserId);
        if (created.IsFailure) return created.Error!;
        db.Folders.Add(created.Value);
        await db.SaveChangesAsync(ct);
        return await FolderDtoAsync(created.Value.Id, ct);
    }

    public async Task<Result<FolderDto>> UpdateFolderAsync(long id, SaveFolderRequest r, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var f = await VisibleFolders(scope).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (f is null) return Error.NotFound("thư mục");
        if (scope.Level < DataScope.Department && f.OwnerUserId != scope.UserId) return Error.Forbidden("Chỉ người tạo thư mục được sửa.");
        var check = await ValidateFolderAsync(id, r, scope, ct);
        if (check.IsFailure) return check.Error!;
        var u = f.Update(r.Name, r.ParentId, r.DepartmentId);
        if (u.IsFailure) return u.Error!;
        await db.SaveChangesAsync(ct);
        return await FolderDtoAsync(id, ct);
    }

    private async Task<Result> ValidateFolderAsync(long? id, SaveFolderRequest r, Scope scope, CancellationToken ct)
    {
        if (r.ParentId is { } pid)
        {
            if (pid == id) return Error.Validation("folder.parent", "Thư mục cha không hợp lệ.");
            if (!await VisibleFolders(scope).AnyAsync(f => f.Id == pid, ct)) return Error.Validation("folder.parent", "Thư mục cha không hợp lệ.");
        }
        if (r.DepartmentId is { } did)
        {
            if (!await db.Departments.AnyAsync(d => d.Id == did, ct)) return Error.Validation("folder.department", "Phòng ban không hợp lệ.");
            if (scope.Level < DataScope.Company && did != scope.DepartmentId) return Error.Forbidden("Chỉ tạo thư mục cho phòng ban của mình.");
        }
        var name = (r.Name ?? "").Trim();
        if (await db.Folders.AnyAsync(f => f.Id != id && f.ParentId == r.ParentId && f.Name == name, ct))
            return Error.Conflict("folder.name_taken", "Đã có thư mục cùng tên ở đây.");
        return Result.Success();
    }

    public async Task<Result> DeleteFolderAsync(long id, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var f = await VisibleFolders(scope).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (f is null) return Error.NotFound("thư mục");
        if (scope.Level < DataScope.Department && f.OwnerUserId != scope.UserId) return Error.Forbidden("Chỉ người tạo thư mục được xóa.");
        if (await db.Documents.AnyAsync(d => d.FolderId == id, ct) || await db.Folders.AnyAsync(x => x.ParentId == id, ct))
            return Error.Conflict("folder.not_empty", "Thư mục còn tài liệu hoặc thư mục con, chuyển đi trước khi xóa.");
        db.Folders.Remove(f);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    private async Task<FolderDto> FolderDtoAsync(long id, CancellationToken ct)
        => await db.Folders.AsNoTracking().Where(f => f.Id == id)
            .Select(f => new FolderDto(f.Id, f.Name, f.ParentId, f.DepartmentId, db.Departments.Where(d => d.Id == f.DepartmentId).Select(d => d.Name).FirstOrDefault(),
                db.Documents.Count(d => d.FolderId == f.Id))).FirstAsync(ct);
}
