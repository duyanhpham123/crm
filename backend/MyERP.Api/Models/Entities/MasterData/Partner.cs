using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.MasterData;

/// <summary>Thông tin nhập của khách hàng (dùng khi tạo / sửa).</summary>
public sealed record PartnerInfo(
    string PartnerType,          // company | individual
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
    string? Source,
    string? Note);

/// <summary>
/// Bảng md.Partners - đối tác dùng chung cho mọi phòng ban.
/// CRM dùng với vai trò khách hàng (IsCustomer = 1); Mua hàng dùng với vai trò nhà cung cấp.
/// </summary>
public sealed class Partner : AuditableEntity, ICompanyOwned
{
    public const string Company = "company";
    public const string Individual = "individual";

    private Partner() { }

    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string PartnerType { get; private set; } = Company;
    public string Name { get; private set; } = "";
    public string? ShortName { get; private set; }
    public string? TaxCode { get; private set; }
    public string? Phone { get; private set; }
    public string? Email { get; private set; }
    public string? Website { get; private set; }
    public string? Industry { get; private set; }
    public string? Street { get; private set; }
    public bool IsCustomer { get; private set; }
    public bool IsSupplier { get; private set; }
    public long? CustomerGroupId { get; private set; }
    public long? OwnerUserId { get; private set; }
    public string? Source { get; private set; }
    public string? Note { get; private set; }
    public bool IsActive { get; private set; }

    public List<PartnerContact> Contacts { get; private set; } = [];
    public PartnerGroup? CustomerGroup { get; private set; }

    public static Partner CreateCustomer(long companyId, string code, PartnerInfo info)
    {
        var partner = new Partner { CompanyId = companyId, Code = code, IsCustomer = true, IsActive = true };
        partner.Update(info);
        return partner;
    }

    public void Update(PartnerInfo d)
    {
        PartnerType = d.PartnerType == Individual ? Individual : Company;
        Name = d.Name.Trim();
        ShortName = Clean(d.ShortName);
        TaxCode = Clean(d.TaxCode)?.Replace(" ", "");
        Phone = PhoneNumber.Normalize(d.Phone);
        Email = Clean(d.Email)?.ToLowerInvariant();
        Website = Clean(d.Website);
        Industry = Clean(d.Industry);
        Street = Clean(d.Street);
        CustomerGroupId = d.CustomerGroupId;
        OwnerUserId = d.OwnerUserId;
        Source = Clean(d.Source);
        Note = Clean(d.Note);
    }

    /// <summary>Thêm người liên hệ. Người liên hệ đầu tiên tự thành liên hệ chính.</summary>
    public PartnerContact AddContact(ContactInfo info)
    {
        var contact = PartnerContact.Create(info);
        Contacts.Add(contact);
        if (contact.IsPrimary || Contacts.Count(c => !c.IsDeleted) == 1) SetPrimary(contact);
        return contact;
    }

    /// <summary>Mỗi khách hàng chỉ có tối đa 1 liên hệ chính.</summary>
    public void SetPrimary(PartnerContact primary)
    {
        foreach (var c in Contacts) c.IsPrimary = ReferenceEquals(c, primary);
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

public sealed record ContactInfo(string FullName, string? Position, string? Phone, string? Email, DateOnly? Birthday, bool IsPrimary, string? Note);

/// <summary>Bảng md.PartnerContacts - người liên hệ của khách hàng (giám đốc, kế toán...).</summary>
public sealed class PartnerContact : IAuditable, ISoftDelete
{
    private PartnerContact() { }

    public long Id { get; private set; }
    public long PartnerId { get; private set; }
    public string FullName { get; private set; } = "";
    public string? Position { get; private set; }
    public string? Phone { get; private set; }
    public string? Email { get; private set; }
    public DateOnly? Birthday { get; private set; }
    public bool IsPrimary { get; internal set; }
    public string? Note { get; private set; }
    public DateTime CreatedAt { get; set; }
    public long? CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public long? UpdatedBy { get; set; }
    public bool IsDeleted { get; set; }

    internal static PartnerContact Create(ContactInfo info)
    {
        var c = new PartnerContact();
        c.Update(info);
        return c;
    }

    public void Update(ContactInfo d)
    {
        FullName = d.FullName.Trim();
        Position = string.IsNullOrWhiteSpace(d.Position) ? null : d.Position.Trim();
        Phone = PhoneNumber.Normalize(d.Phone);
        Email = string.IsNullOrWhiteSpace(d.Email) ? null : d.Email.Trim().ToLowerInvariant();
        Birthday = d.Birthday;
        IsPrimary = d.IsPrimary;
        Note = string.IsNullOrWhiteSpace(d.Note) ? null : d.Note.Trim();
    }
}

/// <summary>Bảng md.PartnerGroups - nhóm khách hàng (Khách lẻ, Đại lý, VIP...).</summary>
public sealed class PartnerGroup : ICompanyOwned
{
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public string GroupType { get; private set; } = "customer";
}
