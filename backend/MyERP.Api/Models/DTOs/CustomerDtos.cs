namespace MyERP.Api.Models.DTOs;

/// <summary>GET /api/crm/customers?search=&amp;groupId=&amp;ownerId=&amp;page=</summary>
public sealed record CustomerQuery(string? Search, long? GroupId, long? OwnerId, int Page = 1, int PageSize = 20);

public sealed record CustomerListItem(
    long Id,
    string Code,
    string PartnerType,
    string Name,
    string? TaxCode,
    string? Phone,
    string? Email,
    string? GroupName,
    string? PrimaryContact,
    long? OwnerUserId,
    string? OwnerName,
    int OpenOpportunities,
    decimal OpenPipelineValue,
    DateTime CreatedAt);

public sealed record ContactDto(long Id, string FullName, string? Position, string? Phone, string? Email, DateOnly? Birthday, bool IsPrimary, string? Note);

public sealed record CustomerDetail(
    long Id,
    string Code,
    string PartnerType,
    string Name,
    string? ShortName,
    string? TaxCode,
    string? Phone,
    string? Email,
    string? Website,
    string? Industry,
    string? Street,
    long? CustomerGroupId,
    string? GroupName,
    long? OwnerUserId,
    string? OwnerName,
    string? Source,
    string? Note,
    DateTime CreatedAt,
    IReadOnlyList<ContactDto> Contacts,
    IReadOnlyList<OpportunityCard> Opportunities,
    string RowVersion);

public sealed record SaveCustomerRequest(
    string PartnerType,
    string Name,
    string? ShortName,
    string? TaxCode,
    string? Phone,
    string? Email,
    string? Website,
    string? Industry,
    string? Street,
    long? CustomerGroupId,
    long? OwnerUserId,
    string? Note,
    SaveContactRequest? PrimaryContact = null,   // chỉ dùng khi tạo mới
    string? RowVersion = null);

public sealed record SaveContactRequest(string FullName, string? Position, string? Phone, string? Email, DateOnly? Birthday, bool IsPrimary, string? Note);
