using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Crm;
using MyERP.Api.Models.Entities.MasterData;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Crm;

public interface ICustomerService
{
    Task<PagedResult<CustomerListItem>> ListAsync(CustomerQuery query, CancellationToken ct);
    Task<Result<CustomerDetail>> GetAsync(long id, CancellationToken ct);
    Task<Result<CustomerDetail>> CreateAsync(SaveCustomerRequest request, CancellationToken ct);
    Task<Result<CustomerDetail>> UpdateAsync(long id, SaveCustomerRequest request, CancellationToken ct);
    Task<Result> DeleteAsync(long id, CancellationToken ct);
    Task<Result<ContactDto>> AddContactAsync(long customerId, SaveContactRequest request, CancellationToken ct);
    Task<Result<ContactDto>> UpdateContactAsync(long customerId, long contactId, SaveContactRequest request, CancellationToken ct);
    Task<Result> DeleteContactAsync(long customerId, long contactId, CancellationToken ct);
    Task<CrmLookups> GetLookupsAsync(CancellationToken ct);
}

/// <summary>
/// Khách hàng (md.Partners có IsCustomer = 1) + người liên hệ.
/// Phạm vi dữ liệu theo người phụ trách (OwnerUserId), dùng chung quyền crm.*.
/// </summary>
public sealed class CustomerService(
    AppDbContext db,
    ICurrentUser currentUser,
    IDataScopeService dataScope,
    IDocumentNumberService docNumbers,
    TimeProvider clock) : ICustomerService
{
    public async Task<PagedResult<CustomerListItem>> ListAsync(CustomerQuery q, CancellationToken ct)
    {
        var page = Math.Max(1, q.Page);
        var pageSize = Math.Clamp(q.PageSize, 1, 100);
        var query = await ScopedAsync(Permissions.Crm.View, ct);

        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var s = q.Search.Trim();
            var phone = PhoneNumber.Normalize(s);
            query = query.Where(p => p.Name.Contains(s) || p.Code.Contains(s)
                || (p.ShortName != null && p.ShortName.Contains(s))
                || (p.TaxCode != null && p.TaxCode.Contains(s))
                || (p.Email != null && p.Email.Contains(s))
                || (phone != null && phone != "" && p.Phone != null && p.Phone.Contains(phone))
                || p.Contacts.Any(c => !c.IsDeleted && (c.FullName.Contains(s) || (phone != null && phone != "" && c.Phone != null && c.Phone.Contains(phone)))));
        }
        if (q.GroupId is { } g) query = query.Where(p => p.CustomerGroupId == g);
        if (q.OwnerId is { } o) query = query.Where(p => p.OwnerUserId == o);

        var total = await query.CountAsync(ct);
        var items = await query
            .OrderByDescending(p => p.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(p => new CustomerListItem(
                p.Id, p.Code, p.PartnerType, p.Name, p.TaxCode, p.Phone, p.Email,
                p.CustomerGroup != null ? p.CustomerGroup.Name : null,
                p.Contacts.Where(c => c.IsPrimary).Select(c => c.FullName).FirstOrDefault(),
                p.OwnerUserId,
                db.Users.Where(u => u.Id == p.OwnerUserId).Select(u => u.FullName).FirstOrDefault(),
                db.Opportunities.Count(op => op.PartnerId == p.Id && op.Status == OpportunityStatuses.Open),
                db.Opportunities.Where(op => op.PartnerId == p.Id && op.Status == OpportunityStatuses.Open).Sum(op => (decimal?)op.ExpectedRevenue) ?? 0,
                p.CreatedAt))
            .AsNoTracking().ToListAsync(ct);

        return new PagedResult<CustomerListItem>(items, page, pageSize, total);
    }

    public async Task<Result<CustomerDetail>> GetAsync(long id, CancellationToken ct)
    {
        var partner = await (await ScopedAsync(Permissions.Crm.View, ct))
            .Include(p => p.Contacts).Include(p => p.CustomerGroup)
            .AsNoTracking().AsSplitQuery().FirstOrDefaultAsync(p => p.Id == id, ct);
        return partner is null ? Error.NotFound("khách hàng") : await ToDetailAsync(partner, ct);
    }

    public async Task<Result<CustomerDetail>> CreateAsync(SaveCustomerRequest req, CancellationToken ct)
    {
        var check = await ValidateAsync(req, excludeId: null, ct);
        if (check.IsFailure) return check.Error!;

        var info = ToInfo(req, req.OwnerUserId ?? currentUser.RequireUserId());
        var strategy = db.Database.CreateExecutionStrategy();
        var partner = await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var p = Partner.CreateCustomer(currentUser.RequireCompanyId(), await docNumbers.NextAsync("PARTNER", ct: ct), info);
            if (req.PrimaryContact is { } c && !string.IsNullOrWhiteSpace(c.FullName))
                p.AddContact(ToContact(c with { IsPrimary = true }));
            db.Partners.Add(p);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return p;
        });
        return await ToDetailAsync(partner, ct);
    }

    public async Task<Result<CustomerDetail>> UpdateAsync(long id, SaveCustomerRequest req, CancellationToken ct)
    {
        var partner = await (await ScopedAsync(Permissions.Crm.Edit, ct)).Include(p => p.Contacts).FirstOrDefaultAsync(p => p.Id == id, ct);
        if (partner is null) return Error.NotFound("khách hàng");

        var check = await ValidateAsync(req, id, ct);
        if (check.IsFailure) return check.Error!;

        if (!string.IsNullOrEmpty(req.RowVersion))
            db.Entry(partner).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(req.RowVersion);
        partner.Update(ToInfo(req, req.OwnerUserId ?? partner.OwnerUserId));
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(partner, ct);
    }

    public async Task<Result> DeleteAsync(long id, CancellationToken ct)
    {
        var partner = await (await ScopedAsync(Permissions.Crm.Delete, ct)).FirstOrDefaultAsync(p => p.Id == id, ct);
        if (partner is null) return Error.NotFound("khách hàng");

        var open = await db.Opportunities.CountAsync(o => o.PartnerId == id && o.Status == OpportunityStatuses.Open, ct);
        if (open > 0)
            return Error.Conflict("customer.has_opportunities", $"Khách hàng còn {open} cơ hội đang mở. Đóng hoặc xóa các cơ hội trước.");

        db.Partners.Remove(partner);   // xóa mềm: lịch sử giao dịch vẫn còn
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    // ---------- Người liên hệ ----------

    public async Task<Result<ContactDto>> AddContactAsync(long customerId, SaveContactRequest req, CancellationToken ct)
    {
        var partner = await LoadForEditAsync(customerId, ct);
        if (partner is null) return Error.NotFound("khách hàng");

        var contact = partner.AddContact(ToContact(req));
        await db.SaveChangesAsync(ct);
        return ToContactDto(contact);
    }

    public async Task<Result<ContactDto>> UpdateContactAsync(long customerId, long contactId, SaveContactRequest req, CancellationToken ct)
    {
        var partner = await LoadForEditAsync(customerId, ct);
        var contact = partner?.Contacts.FirstOrDefault(c => c.Id == contactId);
        if (partner is null || contact is null) return Error.NotFound("người liên hệ");

        contact.Update(ToContact(req));
        if (req.IsPrimary) partner.SetPrimary(contact);
        await db.SaveChangesAsync(ct);
        return ToContactDto(contact);
    }

    public async Task<Result> DeleteContactAsync(long customerId, long contactId, CancellationToken ct)
    {
        var partner = await LoadForEditAsync(customerId, ct);
        var contact = partner?.Contacts.FirstOrDefault(c => c.Id == contactId);
        if (partner is null || contact is null) return Error.NotFound("người liên hệ");

        contact.IsDeleted = true;
        if (contact.IsPrimary && partner.Contacts.FirstOrDefault(c => !c.IsDeleted) is { } next)
            partner.SetPrimary(next);   // xóa liên hệ chính thì người kế tiếp thành liên hệ chính
        contact.IsPrimary = false;
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    // ---------- Danh mục cho ô chọn ----------

    public async Task<CrmLookups> GetLookupsAsync(CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        var sources = await db.LeadSources.Where(s => s.IsActive).OrderBy(s => s.Name)
            .Select(s => new LeadSourceDto(s.Id, s.Code, s.Name)).AsNoTracking().ToListAsync(ct);
        var groups = await db.PartnerGroups.Where(g => g.GroupType == "customer").OrderBy(g => g.Name)
            .Select(g => new OptionDto(g.Id, g.Name, null)).AsNoTracking().ToListAsync(ct);
        var pipelines = await db.Pipelines.Where(p => p.IsActive).OrderByDescending(p => p.IsDefault)
            .Select(p => new PipelineDto(p.Id, p.Name, p.IsDefault,
                p.Stages.OrderBy(s => s.SortOrder).Select(s => new StageDto(s.Id, s.Name, s.SortOrder, s.Probability, s.StageType, s.Color)).ToList()))
            .AsNoTracking().ToListAsync(ct);
        var reasons = await db.LostReasons.Where(r => r.IsActive).OrderBy(r => r.Id)
            .Select(r => new OptionDto(r.Id, r.Name, null)).AsNoTracking().ToListAsync(ct);
        var owners = await (from uc in db.UserCompanies
                            join u in db.Users on uc.UserId equals u.Id
                            where uc.CompanyId == companyId && u.IsActive
                            orderby u.FullName
                            select new OptionDto(u.Id, u.FullName, null)).AsNoTracking().ToListAsync(ct);
        return new CrmLookups(sources, groups, pipelines, reasons, owners);
    }

    // ---------- Hàm hỗ trợ ----------

    private async Task<IQueryable<Partner>> ScopedAsync(string permission, CancellationToken ct)
    {
        var me = currentUser.RequireUserId();
        var owners = await dataScope.VisibleOwnersAsync(permission, ct);
        var query = db.Partners.Where(p => p.IsCustomer);
        return owners is null
            ? query
            : query.Where(p => (p.OwnerUserId != null && owners.Contains(p.OwnerUserId.Value)) || p.CreatedBy == me);
    }

    private async Task<Partner?> LoadForEditAsync(long id, CancellationToken ct)
        => await (await ScopedAsync(Permissions.Crm.Edit, ct)).Include(p => p.Contacts).FirstOrDefaultAsync(p => p.Id == id, ct);

    /// <summary>Không trùng mã số thuế / số điện thoại với khách hàng khác; nhóm và người phụ trách phải hợp lệ.</summary>
    private async Task<Result> ValidateAsync(SaveCustomerRequest req, long? excludeId, CancellationToken ct)
    {
        var taxCode = req.TaxCode?.Replace(" ", "").Trim();
        if (!string.IsNullOrEmpty(taxCode)
            && await db.Partners.Where(p => p.Id != excludeId && p.TaxCode == taxCode).Select(p => p.Code).FirstOrDefaultAsync(ct) is { } dupTax)
            return Error.Conflict("customer.tax_code_taken", $"Mã số thuế đã thuộc khách hàng {dupTax}.");

        var phone = PhoneNumber.Normalize(req.Phone);
        if (phone is not null
            && await db.Partners.Where(p => p.Id != excludeId && p.IsCustomer && p.Phone == phone).Select(p => p.Code).FirstOrDefaultAsync(ct) is { } dupPhone)
            return Error.Conflict("customer.phone_taken", $"Số điện thoại đã thuộc khách hàng {dupPhone}.");

        if (req.CustomerGroupId is { } g && !await db.PartnerGroups.AnyAsync(x => x.Id == g && x.GroupType == "customer", ct))
            return Error.Validation("customer.group_invalid", "Nhóm khách hàng không hợp lệ.");

        if (req.OwnerUserId is { } owner)
        {
            var companyId = currentUser.RequireCompanyId();
            if (!await db.UserCompanies.AnyAsync(uc => uc.UserId == owner && uc.CompanyId == companyId, ct))
                return Error.Validation("customer.owner_invalid", "Người phụ trách không hợp lệ.");
        }
        return Result.Success();
    }

    private async Task<CustomerDetail> ToDetailAsync(Partner p, CancellationToken ct)
    {
        var now = DateOnly.FromDateTime(clock.GetLocalNow().DateTime);
        var opportunities = await db.Opportunities.Where(o => o.PartnerId == p.Id)
            .OrderBy(o => o.Status == OpportunityStatuses.Open ? 0 : 1).ThenByDescending(o => o.Id)
            .Select(o => new OpportunityCard(o.Id, o.Code, o.Name, o.PartnerId, p.Name, o.StageId, o.Status, o.ExpectedRevenue,
                o.Probability, o.ExpectedCloseDate, o.Priority, o.OwnerUserId,
                db.Users.Where(u => u.Id == o.OwnerUserId).Select(u => u.FullName).FirstOrDefault(),
                o.Status == OpportunityStatuses.Open && o.ExpectedCloseDate != null && o.ExpectedCloseDate < now))
            .AsNoTracking().ToListAsync(ct);
        var groupName = p.CustomerGroup?.Name ?? (p.CustomerGroupId is { } gid
            ? await db.PartnerGroups.Where(g => g.Id == gid).Select(g => g.Name).FirstOrDefaultAsync(ct) : null);
        var ownerName = p.OwnerUserId is { } oid
            ? await db.Users.Where(u => u.Id == oid).Select(u => u.FullName).FirstOrDefaultAsync(ct) : null;

        return new CustomerDetail(p.Id, p.Code, p.PartnerType, p.Name, p.ShortName, p.TaxCode, p.Phone, p.Email, p.Website,
            p.Industry, p.Street, p.CustomerGroupId, groupName, p.OwnerUserId, ownerName, p.Source, p.Note, p.CreatedAt,
            p.Contacts.Where(c => !c.IsDeleted).OrderByDescending(c => c.IsPrimary).ThenBy(c => c.FullName).Select(ToContactDto).ToList(),
            opportunities, Convert.ToBase64String(p.RowVersion));
    }

    private static PartnerInfo ToInfo(SaveCustomerRequest r, long? owner) => new(r.PartnerType, r.Name, r.ShortName, r.TaxCode,
        r.Phone, r.Email, r.Website, r.Industry, r.Street, r.CustomerGroupId, owner, null, r.Note);

    private static ContactInfo ToContact(SaveContactRequest r) => new(r.FullName, r.Position, r.Phone, r.Email, r.Birthday, r.IsPrimary, r.Note);

    private static ContactDto ToContactDto(PartnerContact c) => new(c.Id, c.FullName, c.Position, c.Phone, c.Email, c.Birthday, c.IsPrimary, c.Note);
}
