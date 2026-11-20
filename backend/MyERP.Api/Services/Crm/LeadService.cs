using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Crm;
using MyERP.Api.Models.Entities.MasterData;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Crm;

public interface ILeadService
{
    Task<PagedResult<LeadListItem>> ListAsync(LeadQuery query, CancellationToken ct);
    Task<Result<LeadDto>> GetAsync(long id, CancellationToken ct);
    Task<Result<LeadDto>> CreateAsync(SaveLeadRequest request, CancellationToken ct);
    Task<Result<LeadDto>> UpdateAsync(long id, SaveLeadRequest request, CancellationToken ct);
    Task<Result<LeadDto>> ChangeStatusAsync(long id, ChangeLeadStatusRequest request, CancellationToken ct);
    Task<Result> DeleteAsync(long id, CancellationToken ct);
    Task<List<LeadSourceDto>> ListSourcesAsync(CancellationToken ct);
    Task<Result<ConvertLeadResponse>> ConvertAsync(long id, ConvertLeadRequest request, CancellationToken ct);
}

public sealed class LeadService(
    AppDbContext db,
    ICurrentUser currentUser,
    IDocumentNumberService docNumbers,
    IDataScopeService dataScope,
    TimeProvider clock) : ILeadService
{
    public async Task<PagedResult<LeadListItem>> ListAsync(LeadQuery q, CancellationToken ct)
    {
        var page = Math.Max(1, q.Page);
        var pageSize = Math.Clamp(q.PageSize, 1, 100);

        var query = await ScopedAsync(Permissions.Crm.View, ct);
        if (!string.IsNullOrWhiteSpace(q.Status))
            query = query.Where(x => x.Status == q.Status);
        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var s = q.Search.Trim();
            var phone = PhoneNumber.Normalize(s);
            query = query.Where(x => x.FullName.Contains(s) || x.Code.Contains(s)
                || (x.OrganizationName != null && x.OrganizationName.Contains(s))
                || (x.Email != null && x.Email.Contains(s))
                || (phone != null && phone != "" && x.Phone != null && x.Phone.Contains(phone)));
        }

        var total = await query.CountAsync(ct);
        var items = await query
            .OrderByDescending(x => x.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new LeadListItem(x.Id, x.Code, x.FullName, x.OrganizationName, x.Phone, x.Email,
                x.Source != null ? x.Source.Name : null, x.Status, x.EstimatedValue, x.OwnerUserId, x.CreatedAt))
            .AsNoTracking().ToListAsync(ct);

        return new PagedResult<LeadListItem>(items, page, pageSize, total);
    }

    public async Task<Result<LeadDto>> GetAsync(long id, CancellationToken ct)
    {
        var lead = await (await ScopedAsync(Permissions.Crm.View, ct)).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return lead is null ? Error.NotFound("lead") : ToDto(lead);
    }

    public async Task<Result<LeadDto>> CreateAsync(SaveLeadRequest req, CancellationToken ct)
    {
        var info = ToInfo(req);
        if (await SourceInvalidAsync(info.SourceId, ct))
            return Error.Validation("lead.source_invalid", "Nguồn lead không hợp lệ.");
        if (await FindDuplicateAsync(info, excludeId: null, ct) is { } dup)
            return Error.Conflict("lead.duplicate", $"Đã có lead {dup} với cùng số điện thoại hoặc email.");

        // Lấy số chứng từ và lưu trong cùng transaction: lỗi thì số không bị "nhảy".
        // Bật retry khi mất kết nối nên phải bọc trong execution strategy.
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var code = await docNumbers.NextAsync("LEAD", ct: ct);
            var lead = Lead.Create(currentUser.RequireCompanyId(), code, currentUser.RequireUserId(), info);
            db.Leads.Add(lead);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<LeadDto>)ToDto(lead);
        });
    }

    public async Task<Result<LeadDto>> UpdateAsync(long id, SaveLeadRequest req, CancellationToken ct)
    {
        var lead = await (await ScopedAsync(Permissions.Crm.Edit, ct)).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (lead is null) return Error.NotFound("lead");

        var info = ToInfo(req);
        if (await SourceInvalidAsync(info.SourceId, ct))
            return Error.Validation("lead.source_invalid", "Nguồn lead không hợp lệ.");
        if (await FindDuplicateAsync(info, id, ct) is { } dup)
            return Error.Conflict("lead.duplicate", $"Đã có lead {dup} với cùng số điện thoại hoặc email.");

        if (!string.IsNullOrEmpty(req.RowVersion))
            db.Entry(lead).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(req.RowVersion);

        var result = lead.Update(info);
        if (result.IsFailure) return result.Error!;

        await db.SaveChangesAsync(ct);   // RowVersion lệch thì ném DbUpdateConcurrencyException, trả 409
        return ToDto(lead);
    }

    public async Task<Result<LeadDto>> ChangeStatusAsync(long id, ChangeLeadStatusRequest req, CancellationToken ct)
    {
        var lead = await (await ScopedAsync(Permissions.Crm.Edit, ct)).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (lead is null) return Error.NotFound("lead");

        var result = lead.ChangeStatus(req.Status, req.Reason);
        if (result.IsFailure) return result.Error!;
        await db.SaveChangesAsync(ct);
        return ToDto(lead);
    }

    public async Task<Result> DeleteAsync(long id, CancellationToken ct)
    {
        var lead = await (await ScopedAsync(Permissions.Crm.Delete, ct)).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (lead is null) return Error.NotFound("lead");
        if (lead.IsConverted)
            return Error.Conflict("lead.converted", "Không xóa lead đã chuyển đổi thành khách hàng.");

        db.Leads.Remove(lead);   // AuditInterceptor đổi thành xóa mềm
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    /// <summary>
    /// Chuyển đổi lead: tạo khách hàng mới (hoặc gắn vào khách hàng có sẵn) + người liên hệ
    /// + cơ hội ở giai đoạn đầu của pipeline. Tất cả trong 1 transaction.
    /// </summary>
    public async Task<Result<ConvertLeadResponse>> ConvertAsync(long id, ConvertLeadRequest req, CancellationToken ct)
    {
        var lead = await (await ScopedAsync(Permissions.Crm.Edit, ct)).Include(l => l.Source).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (lead is null) return Error.NotFound("lead");
        var can = lead.CanConvert();
        if (can.IsFailure) return can.Error!;

        Partner? existing = null;
        if (req.ExistingCustomerId is { } customerId)
        {
            existing = await db.Partners.Include(p => p.Contacts).FirstOrDefaultAsync(p => p.Id == customerId && p.IsCustomer, ct);
            if (existing is null) return Error.Validation("lead.customer_invalid", "Khách hàng được chọn không tồn tại.");
        }

        Stage? firstStage = null;
        if (req.CreateOpportunity)
        {
            if (string.IsNullOrWhiteSpace(req.OpportunityName))
                return Error.Validation("lead.opportunity_name_required", "Nhập tên cơ hội.");
            firstStage = await db.Pipelines.Where(p => p.IsActive).OrderByDescending(p => p.IsDefault).ThenBy(p => p.Id)
                .SelectMany(p => p.Stages).Where(s => s.StageType == OpportunityStatuses.Open).OrderBy(s => s.SortOrder)
                .FirstOrDefaultAsync(ct);
            if (firstStage is null) return Error.Validation("crm.no_pipeline", "Chưa cấu hình quy trình bán hàng.");
        }

        var companyId = currentUser.RequireCompanyId();
        var now = clock.GetUtcNow().UtcDateTime;
        var owner = lead.OwnerUserId ?? currentUser.RequireUserId();

        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);

            // 1. Khách hàng: doanh nghiệp nếu lead có tên công ty, ngược lại là cá nhân
            var partner = existing;
            if (partner is null)
            {
                var isCompany = !string.IsNullOrWhiteSpace(lead.OrganizationName);
                partner = Partner.CreateCustomer(companyId, await docNumbers.NextAsync("PARTNER", ct: ct), new PartnerInfo(
                    isCompany ? Partner.Company : Partner.Individual,
                    isCompany ? lead.OrganizationName! : lead.FullName,
                    null, null,
                    isCompany ? null : lead.Phone,
                    isCompany ? null : lead.Email,
                    null, null, lead.Street, null, owner, lead.Source?.Name, lead.InterestNote));
                db.Partners.Add(partner);
            }

            // 2. Người liên hệ: người trong lead (nếu khách là doanh nghiệp)
            PartnerContact? contact = null;
            if (partner.PartnerType == Partner.Company)
            {
                contact = partner.Contacts.FirstOrDefault(c => !c.IsDeleted && c.Phone != null && c.Phone == lead.Phone)
                    ?? partner.AddContact(new ContactInfo(lead.FullName, lead.Position, lead.Phone, lead.Email, null, false, null));
            }
            await db.SaveChangesAsync(ct);

            // 3. Cơ hội
            Opportunity? opportunity = null;
            if (firstStage is not null)
            {
                var created = Opportunity.Create(companyId, await docNumbers.NextAsync("OPPORTUNITY", ct: ct), partner.Id, lead.Id, firstStage,
                    new OpportunityInfo(req.OpportunityName!, contact?.Id, req.ExpectedRevenue ?? lead.EstimatedValue ?? 0, null,
                        req.ExpectedCloseDate, 1, owner, lead.InterestNote), now);
                if (created.IsFailure) return (Result<ConvertLeadResponse>)created.Error!;
                opportunity = created.Value;
                db.Opportunities.Add(opportunity);
                await db.SaveChangesAsync(ct);
            }

            lead.MarkConverted(partner.Id, opportunity?.Id, now);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<ConvertLeadResponse>)new ConvertLeadResponse(partner.Id, partner.Code, opportunity?.Id, opportunity?.Code);
        });
    }

    public Task<List<LeadSourceDto>> ListSourcesAsync(CancellationToken ct)
        => db.LeadSources.Where(s => s.IsActive).OrderBy(s => s.Name)
            .Select(s => new LeadSourceDto(s.Id, s.Code, s.Name)).AsNoTracking().ToListAsync(ct);

    /// <summary>Lọc theo phạm vi dữ liệu của quyền (xem DataScopeService).</summary>
    private async Task<IQueryable<Lead>> ScopedAsync(string permission, CancellationToken ct)
    {
        var me = currentUser.RequireUserId();
        var visibleOwners = await dataScope.VisibleOwnersAsync(permission, ct);
        return visibleOwners is null
            ? db.Leads
            : db.Leads.Where(x => (x.OwnerUserId != null && visibleOwners.Contains(x.OwnerUserId.Value)) || x.CreatedBy == me);
    }

    private async Task<string?> FindDuplicateAsync(LeadInfo info, long? excludeId, CancellationToken ct)
    {
        var phone = PhoneNumber.Normalize(info.Phone);
        var email = info.Email?.Trim().ToLowerInvariant();
        if (phone is null && string.IsNullOrEmpty(email)) return null;

        return await db.Leads
            .Where(x => x.Id != excludeId && x.Status != LeadStatuses.Converted && x.Status != LeadStatuses.Unqualified)
            .Where(x => (phone != null && x.Phone == phone) || (email != null && email != "" && x.Email == email))
            .Select(x => x.Code).FirstOrDefaultAsync(ct);
    }

    private async Task<bool> SourceInvalidAsync(long? sourceId, CancellationToken ct)
        => sourceId is { } id && !await db.LeadSources.AnyAsync(s => s.Id == id && s.IsActive, ct);

    private static LeadInfo ToInfo(SaveLeadRequest r) => new(r.FullName, r.OrganizationName, r.Position,
        r.Phone, r.Email, r.Street, r.SourceId, r.InterestNote, r.EstimatedValue);

    private static LeadDto ToDto(Lead x) => new(x.Id, x.Code, x.FullName, x.OrganizationName, x.Position,
        x.Phone, x.Email, x.Street, x.SourceId, x.InterestNote, x.EstimatedValue, x.Score, x.Status,
        x.DisqualifyReason, x.OwnerUserId, x.ConvertedPartnerId, x.ConvertedOpportunityId, x.CreatedAt, Convert.ToBase64String(x.RowVersion));
}
