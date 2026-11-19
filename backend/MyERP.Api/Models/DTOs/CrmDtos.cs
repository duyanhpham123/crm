namespace MyERP.Api.Models.DTOs;

public sealed record PagedResult<T>(IReadOnlyList<T> Items, int Page, int PageSize, int TotalCount)
{
    public int TotalPages => PageSize == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);
}

/// <summary>Tham số lọc danh sách lead: GET /api/crm/leads?search=&amp;status=&amp;page=&amp;pageSize=</summary>
public sealed record LeadQuery(string? Search, string? Status, int Page = 1, int PageSize = 20);

public sealed record LeadListItem(
    long Id,
    string Code,
    string FullName,
    string? OrganizationName,
    string? Phone,
    string? Email,
    string? SourceName,
    string Status,
    decimal? EstimatedValue,
    long? OwnerUserId,
    DateTime CreatedAt);

public sealed record LeadDto(
    long Id,
    string Code,
    string FullName,
    string? OrganizationName,
    string? Position,
    string? Phone,
    string? Email,
    string? Street,
    long? SourceId,
    string? InterestNote,
    decimal? EstimatedValue,
    int Score,
    string Status,
    string? DisqualifyReason,
    long? OwnerUserId,
    DateTime CreatedAt,
    string RowVersion);

/// <summary>Body của POST / PUT lead. RowVersion gửi kèm khi sửa để phát hiện 2 người sửa cùng lúc.</summary>
public sealed record SaveLeadRequest(
    string FullName,
    string? OrganizationName,
    string? Position,
    string? Phone,
    string? Email,
    string? Street,
    long? SourceId,
    string? InterestNote,
    decimal? EstimatedValue,
    string? RowVersion = null);

public sealed record ChangeLeadStatusRequest(string Status, string? Reason);

public sealed record LeadSourceDto(long Id, string Code, string Name);
