using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Crm;

/// <summary>
/// Bảng crm.Leads - khách hàng tiềm năng. Quy tắc nghiệp vụ nằm ngay trong model:
/// lead đã chuyển đổi thì khóa, loại bỏ lead phải có lý do.
/// </summary>
public sealed class Lead : AuditableEntity, ICompanyOwned
{
    private Lead() { }

    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string FullName { get; private set; } = "";
    public string? OrganizationName { get; private set; }
    public string? Position { get; private set; }
    public string? Phone { get; private set; }
    public string? Email { get; private set; }
    public string? Street { get; private set; }
    public string? ProvinceCode { get; private set; }
    public long? SourceId { get; private set; }
    public long? CampaignId { get; private set; }
    public string? InterestNote { get; private set; }
    public decimal? EstimatedValue { get; private set; }
    public int Score { get; private set; }
    public string Status { get; private set; } = LeadStatuses.New;
    public long? OwnerUserId { get; private set; }
    public string? DisqualifyReason { get; private set; }
    public long? ConvertedPartnerId { get; private set; }
    public long? ConvertedOpportunityId { get; private set; }
    public DateTime? ConvertedAt { get; private set; }

    public LeadSource? Source { get; private set; }

    public bool IsConverted => Status == LeadStatuses.Converted;

    public static Lead Create(long companyId, string code, long ownerUserId, LeadInfo info)
    {
        var lead = new Lead { CompanyId = companyId, Code = code, OwnerUserId = ownerUserId };
        lead.Apply(info);
        return lead;
    }

    public Result Update(LeadInfo info)
    {
        if (IsConverted)
            return Error.Conflict("lead.converted", "Lead đã chuyển đổi thành khách hàng, không sửa được nữa.");
        Apply(info);
        return Result.Success();
    }

    public Result ChangeStatus(string status, string? reason)
    {
        if (IsConverted)
            return Error.Conflict("lead.converted", "Lead đã chuyển đổi, không đổi trạng thái được.");
        if (status == LeadStatuses.Converted)
            return Error.Validation("lead.convert_via_flow", "Dùng chức năng Chuyển đổi để biến lead thành khách hàng.");
        if (!LeadStatuses.All.Contains(status))
            return Error.Validation("lead.status_invalid", "Trạng thái không hợp lệ.");
        if (status == LeadStatuses.Unqualified && string.IsNullOrWhiteSpace(reason))
            return Error.Validation("lead.reason_required", "Nhập lý do khi đánh dấu lead không phù hợp.");

        Status = status;
        DisqualifyReason = status == LeadStatuses.Unqualified ? reason!.Trim() : null;
        return Result.Success();
    }

    /// <summary>Chuyển đổi lead thành khách hàng (và cơ hội nếu có). Sau đó lead bị khóa.</summary>
    public Result CanConvert() => Status switch
    {
        LeadStatuses.Converted => Error.Conflict("lead.converted", "Lead này đã được chuyển đổi."),
        LeadStatuses.Unqualified => Error.Validation("lead.unqualified", "Lead đã đánh dấu không phù hợp. Đổi trạng thái trước khi chuyển đổi."),
        _ => Result.Success()
    };

    public void MarkConverted(long partnerId, long? opportunityId, DateTime now)
    {
        Status = LeadStatuses.Converted;
        ConvertedPartnerId = partnerId;
        ConvertedOpportunityId = opportunityId;
        ConvertedAt = now;
    }

    private void Apply(LeadInfo d)
    {
        FullName = d.FullName.Trim();
        OrganizationName = Clean(d.OrganizationName);
        Position = Clean(d.Position);
        Phone = PhoneNumber.Normalize(d.Phone);
        Email = Clean(d.Email)?.ToLowerInvariant();
        Street = Clean(d.Street);
        SourceId = d.SourceId;
        InterestNote = Clean(d.InterestNote);
        EstimatedValue = d.EstimatedValue;
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

/// <summary>Thông tin nhập của lead (dùng khi tạo / sửa).</summary>
public sealed record LeadInfo(
    string FullName,
    string? OrganizationName,
    string? Position,
    string? Phone,
    string? Email,
    string? Street,
    long? SourceId,
    string? InterestNote,
    decimal? EstimatedValue);

/// <summary>Bảng crm.LeadSources - nguồn lead (Facebook, Zalo, Website...).</summary>
public sealed class LeadSource : ICompanyOwned
{
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public bool IsActive { get; private set; }
}
