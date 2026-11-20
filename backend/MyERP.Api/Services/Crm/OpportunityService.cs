using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Crm;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Crm;

public interface IOpportunityService
{
    Task<Result<OpportunityBoard>> GetBoardAsync(long? pipelineId, string? search, long? ownerId, CancellationToken ct);
    Task<Result<OpportunityDetail>> GetAsync(long id, CancellationToken ct);
    Task<Result<OpportunityDetail>> CreateAsync(SaveOpportunityRequest request, CancellationToken ct);
    Task<Result<OpportunityDetail>> UpdateAsync(long id, SaveOpportunityRequest request, CancellationToken ct);
    Task<Result<OpportunityDetail>> MoveStageAsync(long id, MoveStageRequest request, CancellationToken ct);
    Task<Result> DeleteAsync(long id, CancellationToken ct);
}

/// <summary>Cơ hội bán hàng + Kanban theo giai đoạn. Phạm vi dữ liệu theo người phụ trách.</summary>
public sealed class OpportunityService(
    AppDbContext db,
    ICurrentUser currentUser,
    IDataScopeService dataScope,
    IDocumentNumberService docNumbers,
    TimeProvider clock) : IOpportunityService
{
    /// <summary>Kanban: mỗi giai đoạn một cột. Cột Thành công / Thất bại chỉ lấy cơ hội đóng trong 90 ngày gần đây.</summary>
    public async Task<Result<OpportunityBoard>> GetBoardAsync(long? pipelineId, string? search, long? ownerId, CancellationToken ct)
    {
        var pipeline = await db.Pipelines.Include(p => p.Stages).AsNoTracking()
            .Where(p => p.IsActive && (pipelineId == null || p.Id == pipelineId))
            .OrderByDescending(p => p.IsDefault).ThenBy(p => p.Id).FirstOrDefaultAsync(ct);
        if (pipeline is null) return Error.NotFound("quy trình bán hàng");

        var query = (await ScopedAsync(Permissions.Crm.View, ct)).Where(o => o.PipelineId == pipeline.Id);
        var closedSince = clock.GetUtcNow().UtcDateTime.AddDays(-90);
        query = query.Where(o => o.Status == OpportunityStatuses.Open || o.ClosedAt >= closedSince);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            query = query.Where(o => o.Name.Contains(s) || o.Code.Contains(s)
                || db.Partners.Any(p => p.Id == o.PartnerId && p.Name.Contains(s)));
        }
        if (ownerId is { } owner) query = query.Where(o => o.OwnerUserId == owner);

        var cards = await ToCards(query.OrderByDescending(o => o.Priority).ThenBy(o => o.ExpectedCloseDate ?? DateOnly.MaxValue).ThenByDescending(o => o.Id))
            .ToListAsync(ct);

        var columns = pipeline.Stages.OrderBy(s => s.SortOrder).Select(s =>
        {
            var items = cards.Where(c => c.StageId == s.Id).ToList();
            return new BoardColumn(ToStageDto(s), items.Count, items.Sum(i => i.ExpectedRevenue),
                items.Sum(i => Math.Round(i.ExpectedRevenue * i.Probability / 100, 0)), items);
        }).ToList();

        return new OpportunityBoard(pipeline.Id, pipeline.Name, columns);
    }

    public async Task<Result<OpportunityDetail>> GetAsync(long id, CancellationToken ct)
    {
        var o = await (await ScopedAsync(Permissions.Crm.View, ct)).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return o is null ? Error.NotFound("cơ hội") : await ToDetailAsync(o, ct);
    }

    public async Task<Result<OpportunityDetail>> CreateAsync(SaveOpportunityRequest req, CancellationToken ct)
    {
        // Phải thấy được khách hàng mới tạo cơ hội cho khách đó
        var customerOwners = await dataScope.VisibleOwnersAsync(Permissions.Crm.View, ct);
        var me = currentUser.RequireUserId();
        var customerOk = await db.Partners.AnyAsync(p => p.Id == req.CustomerId && p.IsCustomer
            && (customerOwners == null || (p.OwnerUserId != null && customerOwners.Contains(p.OwnerUserId.Value)) || p.CreatedBy == me), ct);
        if (!customerOk) return Error.Validation("opportunity.customer_invalid", "Khách hàng không tồn tại hoặc bạn không có quyền.");

        var check = await ValidateRefsAsync(req.CustomerId, req.ContactId, req.OwnerUserId, ct);
        if (check.IsFailure) return check.Error!;

        Stage? stage = req.StageId is { } sid
            ? await db.Stages.FirstOrDefaultAsync(s => s.Id == sid && db.Pipelines.Any(p => p.Id == s.PipelineId && p.IsActive), ct)
            : await db.Pipelines.Where(p => p.IsActive).OrderByDescending(p => p.IsDefault).ThenBy(p => p.Id)
                .SelectMany(p => p.Stages).Where(s => s.StageType == OpportunityStatuses.Open).OrderBy(s => s.SortOrder).FirstOrDefaultAsync(ct);
        if (stage is null) return Error.Validation("opportunity.stage_invalid", "Giai đoạn không hợp lệ.");

        var info = ToInfo(req, req.OwnerUserId ?? me);
        var now = clock.GetUtcNow().UtcDateTime;
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var created = Opportunity.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync("OPPORTUNITY", ct: ct),
                req.CustomerId, null, stage, info, now);
            if (created.IsFailure) return (Result<OpportunityDetail>)created.Error!;
            db.Opportunities.Add(created.Value);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<OpportunityDetail>)await ToDetailAsync(created.Value, ct);
        });
    }

    public async Task<Result<OpportunityDetail>> UpdateAsync(long id, SaveOpportunityRequest req, CancellationToken ct)
    {
        var o = await (await ScopedAsync(Permissions.Crm.Edit, ct)).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (o is null) return Error.NotFound("cơ hội");

        var check = await ValidateRefsAsync(o.PartnerId, req.ContactId, req.OwnerUserId, ct);
        if (check.IsFailure) return check.Error!;

        if (!string.IsNullOrEmpty(req.RowVersion))
            db.Entry(o).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(req.RowVersion);
        o.Update(ToInfo(req, req.OwnerUserId ?? o.OwnerUserId));
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(o, ct);
    }

    public async Task<Result<OpportunityDetail>> MoveStageAsync(long id, MoveStageRequest req, CancellationToken ct)
    {
        var o = await (await ScopedAsync(Permissions.Crm.Edit, ct)).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (o is null) return Error.NotFound("cơ hội");

        var target = await db.Stages.FirstOrDefaultAsync(s => s.Id == req.StageId, ct);
        if (target is null) return Error.Validation("opportunity.stage_invalid", "Giai đoạn không hợp lệ.");
        if (req.LostReasonId is { } rid && !await db.LostReasons.AnyAsync(r => r.Id == rid && r.IsActive, ct))
            return Error.Validation("opportunity.lost_reason_invalid", "Lý do thất bại không hợp lệ.");

        var moved = o.MoveTo(target, req.LostReasonId, req.LostNote, currentUser.UserId, clock.GetUtcNow().UtcDateTime);
        if (moved.IsFailure) return moved.Error!;
        if (moved.Value is { } history) db.OpportunityStageHistory.Add(history);

        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(o, ct);
    }

    public async Task<Result> DeleteAsync(long id, CancellationToken ct)
    {
        var o = await (await ScopedAsync(Permissions.Crm.Delete, ct)).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (o is null) return Error.NotFound("cơ hội");
        if (o.Status == OpportunityStatuses.Won)
            return Error.Conflict("opportunity.won", "Không xóa cơ hội đã thành công (cần giữ để thống kê doanh số).");

        db.Opportunities.Remove(o);   // xóa mềm
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    // ---------- Hàm hỗ trợ ----------

    private async Task<IQueryable<Opportunity>> ScopedAsync(string permission, CancellationToken ct)
    {
        var me = currentUser.RequireUserId();
        var owners = await dataScope.VisibleOwnersAsync(permission, ct);
        return owners is null
            ? db.Opportunities
            : db.Opportunities.Where(o => (o.OwnerUserId != null && owners.Contains(o.OwnerUserId.Value)) || o.CreatedBy == me);
    }

    private async Task<Result> ValidateRefsAsync(long customerId, long? contactId, long? ownerId, CancellationToken ct)
    {
        if (contactId is { } cid && !await db.PartnerContacts.AnyAsync(c => c.Id == cid && c.PartnerId == customerId, ct))
            return Error.Validation("opportunity.contact_invalid", "Người liên hệ không thuộc khách hàng này.");
        if (ownerId is { } owner)
        {
            var companyId = currentUser.RequireCompanyId();
            if (!await db.UserCompanies.AnyAsync(uc => uc.UserId == owner && uc.CompanyId == companyId, ct))
                return Error.Validation("opportunity.owner_invalid", "Người phụ trách không hợp lệ.");
        }
        return Result.Success();
    }

    private IQueryable<OpportunityCard> ToCards(IQueryable<Opportunity> query)
    {
        var today = DateOnly.FromDateTime(clock.GetLocalNow().DateTime);
        return query.Select(o => new OpportunityCard(o.Id, o.Code, o.Name, o.PartnerId,
            db.Partners.Where(p => p.Id == o.PartnerId).Select(p => p.Name).FirstOrDefault() ?? "",
            o.StageId, o.Status, o.ExpectedRevenue, o.Probability, o.ExpectedCloseDate, o.Priority, o.OwnerUserId,
            db.Users.Where(u => u.Id == o.OwnerUserId).Select(u => u.FullName).FirstOrDefault(),
            o.Status == OpportunityStatuses.Open && o.ExpectedCloseDate != null && o.ExpectedCloseDate < today)).AsNoTracking();
    }

    private async Task<OpportunityDetail> ToDetailAsync(Opportunity o, CancellationToken ct)
    {
        var customerName = await db.Partners.IgnoreQueryFilters().Where(p => p.Id == o.PartnerId).Select(p => p.Name).FirstOrDefaultAsync(ct) ?? "";
        return new OpportunityDetail(o.Id, o.Code, o.Name, o.PartnerId, customerName, o.ContactId, o.LeadId, o.PipelineId, o.StageId,
            o.Status, o.ExpectedRevenue, o.Probability, o.ExpectedCloseDate, o.Priority, o.OwnerUserId, o.LostReasonId, o.LostNote,
            o.ClosedAt, o.Description, o.CreatedAt, Convert.ToBase64String(o.RowVersion));
    }

    private static OpportunityInfo ToInfo(SaveOpportunityRequest r, long? owner)
        => new(r.Name, r.ContactId, r.ExpectedRevenue, r.Probability, r.ExpectedCloseDate, r.Priority, owner, r.Description);

    private static StageDto ToStageDto(Stage s) => new(s.Id, s.Name, s.SortOrder, s.Probability, s.StageType, s.Color);
}
