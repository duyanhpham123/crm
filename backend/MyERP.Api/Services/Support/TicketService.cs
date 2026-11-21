using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Support;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Support;

public interface ITicketService
{
    Task<SupportLookups> GetLookupsAsync(CancellationToken ct);
    Task<TicketPage> ListAsync(TicketQuery query, CancellationToken ct);
    Task<Result<TicketDetail>> GetAsync(long id, CancellationToken ct);
    Task<Result<TicketDetail>> CreateAsync(SaveTicketRequest request, CancellationToken ct);
    Task<Result<TicketDetail>> UpdateAsync(long id, SaveTicketRequest request, CancellationToken ct);
    Task<Result<TicketDetail>> AddMessageAsync(long id, TicketMessageRequest request, CancellationToken ct);
    Task<Result<TicketDetail>> ChangeStatusAsync(long id, TicketStatusRequest request, CancellationToken ct);
    Task<Result<TicketDetail>> AssignAsync(long id, long? userId, CancellationToken ct);
    Task<Result<TicketDetail>> RateAsync(long id, RateRequest request, CancellationToken ct);
}

/// <summary>
/// CSKH: tiếp nhận khiếu nại / hỗ trợ / đổi trả từ mọi kênh, giao người xử lý, trao đổi (công khai + ghi chú nội bộ),
/// theo dõi hạn xử lý (SLA) và đánh giá hài lòng.
/// </summary>
public sealed class TicketService(AppDbContext db, ICurrentUser currentUser, IDocumentNumberService docNumbers, TimeProvider clock) : ITicketService
{
    public static readonly IReadOnlyList<CodeOption> Channels =
    [
        new("phone", "Điện thoại"), new("zalo", "Zalo"), new("facebook", "Facebook"), new("email", "Email"),
        new("web", "Website"), new("walk_in", "Tại cửa hàng"), new("other", "Khác")
    ];

    public static readonly IReadOnlyList<CodeOption> Priorities =
        [new("low", "Thấp"), new("normal", "Bình thường"), new("high", "Cao"), new("urgent", "Khẩn cấp")];

    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    public async Task<SupportLookups> GetLookupsAsync(CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        var agents = await db.Users.Where(u => u.IsActive && db.UserCompanies.Any(c => c.UserId == u.Id && c.CompanyId == companyId))
            .OrderBy(u => u.FullName).Select(u => new OptionDto(u.Id, u.FullName, null)).ToListAsync(ct);
        return new SupportLookups(
            await db.TicketCategories.Where(c => c.IsActive).OrderBy(c => c.Id).Select(c => new OptionDto(c.Id, c.Name, null)).ToListAsync(ct),
            agents, Channels, Priorities);
    }

    public async Task<TicketPage> ListAsync(TicketQuery q, CancellationToken ct)
    {
        var page = Math.Max(1, q.Page);
        var size = Math.Clamp(q.PageSize, 1, 100);
        var now = Now;
        var me = currentUser.RequireUserId();
        var query = db.Tickets.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var s = q.Search.Trim();
            query = query.Where(t => t.Code.Contains(s) || t.Subject.Contains(s) || (t.ReporterName != null && t.ReporterName.Contains(s))
                || (t.ReporterPhone != null && t.ReporterPhone.Contains(s))
                || db.Partners.Any(p => p.Id == t.PartnerId && (p.Name.Contains(s) || (p.Phone != null && p.Phone.Contains(s)))));
        }
        query = q.Status switch
        {
            "active" or null or "" => query.Where(t => t.Status == TicketStatuses.New || t.Status == TicketStatuses.Open || t.Status == TicketStatuses.Pending),
            "all" => query,
            var st => query.Where(t => t.Status == st),
        };
        if (!string.IsNullOrEmpty(q.Priority)) query = query.Where(t => t.Priority == q.Priority);
        if (q.Mine) query = query.Where(t => t.AssignedUserId == me);
        else if (q.AssigneeId is { } a) query = query.Where(t => t.AssignedUserId == a);
        if (q.OverdueOnly) query = query.Where(t => (t.Status == TicketStatuses.New || t.Status == TicketStatuses.Open || t.Status == TicketStatuses.Pending) && t.ResolutionDueAt < now);

        var all = db.Tickets.AsNoTracking();
        var monthStart = new DateTime(now.AddHours(7).Year, now.AddHours(7).Month, 1).AddHours(-7);
        var summary = new TicketSummary(
            await all.CountAsync(t => t.Status == TicketStatuses.New, ct),
            await all.CountAsync(t => t.Status == TicketStatuses.Open, ct),
            await all.CountAsync(t => t.Status == TicketStatuses.Pending, ct),
            await all.CountAsync(t => (t.Status == TicketStatuses.New || t.Status == TicketStatuses.Open || t.Status == TicketStatuses.Pending) && t.ResolutionDueAt < now, ct),
            await all.CountAsync(t => t.ResolvedAt >= monthStart, ct),
            await all.Where(t => t.SatisfactionScore != null).AverageAsync(t => (decimal?)t.SatisfactionScore, ct) is { } avg ? Math.Round(avg, 1) : null);

        var total = await query.CountAsync(ct);
        var rows = await query
            .OrderBy(t => t.Status == TicketStatuses.Resolved || t.Status == TicketStatuses.Closed || t.Status == TicketStatuses.Cancelled)
            .ThenByDescending(t => t.Priority == "urgent").ThenByDescending(t => t.Priority == "high")
            .ThenByDescending(t => t.CreatedAt)
            .Skip((page - 1) * size).Take(size)
            .Select(t => new
            {
                t.Id, t.Code, t.Subject, t.PartnerId, t.ReporterName, t.ReporterPhone, t.Channel, t.Priority, t.Status, t.CreatedAt, t.ResolutionDueAt,
                Customer = db.Partners.Where(p => p.Id == t.PartnerId).Select(p => p.Name).FirstOrDefault(),
                Category = db.TicketCategories.Where(c => c.Id == t.CategoryId).Select(c => c.Name).FirstOrDefault(),
                Assignee = db.Users.Where(u => u.Id == t.AssignedUserId).Select(u => u.FullName).FirstOrDefault(),
            }).ToListAsync(ct);
        var items = rows.Select(t => new TicketListItem(t.Id, t.Code, t.Subject, t.PartnerId, t.Customer ?? t.ReporterName, t.ReporterPhone,
            t.Category, t.Channel, t.Priority, t.Status, t.Assignee, t.CreatedAt, t.ResolutionDueAt,
            TicketStatuses.IsActive(t.Status) && t.ResolutionDueAt < now)).ToList();
        return new TicketPage(new PagedResult<TicketListItem>(items, page, size, total), summary);
    }

    public async Task<Result<TicketDetail>> GetAsync(long id, CancellationToken ct)
    {
        var t = await db.Tickets.Include(x => x.Messages).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return t is null ? Error.NotFound("phiếu hỗ trợ") : await ToDetailAsync(t, ct);
    }

    public async Task<Result<TicketDetail>> CreateAsync(SaveTicketRequest r, CancellationToken ct)
    {
        var info = await BuildInfoAsync(r, ct);
        if (info.IsFailure) return info.Error!;
        var sla = await db.SlaPolicies.FirstOrDefaultAsync(s => s.Priority == r.Priority, ct);
        var created = Ticket.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync("TICKET", ct: ct), info.Value, sla, Now);
        if (created.IsFailure) return created.Error!;
        db.Tickets.Add(created.Value);
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(created.Value, ct);
    }

    public async Task<Result<TicketDetail>> UpdateAsync(long id, SaveTicketRequest r, CancellationToken ct)
    {
        var t = await db.Tickets.Include(x => x.Messages).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (t is null) return Error.NotFound("phiếu hỗ trợ");
        if (!string.IsNullOrEmpty(r.RowVersion)) db.Entry(t).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(r.RowVersion);
        var info = await BuildInfoAsync(r, ct);
        if (info.IsFailure) return info.Error!;
        var sla = await db.SlaPolicies.FirstOrDefaultAsync(s => s.Priority == r.Priority, ct);
        var u = t.Update(info.Value, sla);
        if (u.IsFailure) return u.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(t, ct);
    }

    public Task<Result<TicketDetail>> AddMessageAsync(long id, TicketMessageRequest r, CancellationToken ct)
        => ChangeAsync(id, t => t.AddMessage(currentUser.RequireUserId(), r.Body, r.IsInternal, Now), ct);

    public Task<Result<TicketDetail>> ChangeStatusAsync(long id, TicketStatusRequest r, CancellationToken ct)
        => ChangeAsync(id, t => t.ChangeStatus(r.Status, r.Resolution, Now), ct);

    public async Task<Result<TicketDetail>> AssignAsync(long id, long? userId, CancellationToken ct)
    {
        if (userId is { } u && !await db.Users.AnyAsync(x => x.Id == u && x.IsActive, ct)) return Error.Validation("ticket.assignee", "Người xử lý không hợp lệ.");
        return await ChangeAsync(id, t => t.Assign(userId), ct);
    }

    public Task<Result<TicketDetail>> RateAsync(long id, RateRequest r, CancellationToken ct) => ChangeAsync(id, t => t.Rate(r.Score, r.Note), ct);

    private async Task<Result<TicketDetail>> ChangeAsync(long id, Func<Ticket, Result> change, CancellationToken ct)
    {
        var t = await db.Tickets.Include(x => x.Messages).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (t is null) return Error.NotFound("phiếu hỗ trợ");
        var r = change(t);
        if (r.IsFailure) return r.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(t, ct);
    }

    private async Task<Result<TicketInfo>> BuildInfoAsync(SaveTicketRequest r, CancellationToken ct)
    {
        if (r.CustomerId is { } cid && !await db.Partners.AnyAsync(p => p.Id == cid, ct)) return Error.Validation("ticket.customer", "Khách hàng không tồn tại.");
        if (r.SalesOrderId is { } oid)
        {
            var order = await db.SalesOrders.Where(o => o.Id == oid).Select(o => new { o.PartnerId }).FirstOrDefaultAsync(ct);
            if (order is null) return Error.Validation("ticket.order", "Đơn hàng không tồn tại.");
            if (r.CustomerId is { } c && order.PartnerId != c) return Error.Validation("ticket.order_customer", "Đơn hàng không thuộc khách hàng đã chọn.");
        }
        if (r.CategoryId is { } cat && !await db.TicketCategories.AnyAsync(c => c.Id == cat, ct)) return Error.Validation("ticket.category", "Loại phiếu không hợp lệ.");
        if (r.AssignedUserId is { } a && !await db.Users.AnyAsync(u => u.Id == a && u.IsActive, ct)) return Error.Validation("ticket.assignee", "Người xử lý không hợp lệ.");
        // Có đơn mà chưa chọn khách thì lấy khách của đơn
        var customerId = r.CustomerId ?? (r.SalesOrderId is { } o2 ? await db.SalesOrders.Where(o => o.Id == o2).Select(o => (long?)o.PartnerId).FirstOrDefaultAsync(ct) : null);
        return new TicketInfo(r.Subject, r.Description, customerId, r.ReporterName, r.ReporterPhone, r.SalesOrderId, r.CategoryId, r.Channel, r.Priority, r.AssignedUserId);
    }

    private async Task<TicketDetail> ToDetailAsync(Ticket t, CancellationToken ct)
    {
        var customer = t.PartnerId is { } pid ? await db.Partners.IgnoreQueryFilters().Where(p => p.Id == pid).Select(p => new { p.Name, p.Phone }).FirstOrDefaultAsync(ct) : null;
        var order = t.SalesOrderId is { } oid ? await db.SalesOrders.IgnoreQueryFilters().Where(o => o.Id == oid).Select(o => o.DocNo).FirstOrDefaultAsync(ct) : null;
        var category = t.CategoryId is { } c ? await db.TicketCategories.Where(x => x.Id == c).Select(x => x.Name).FirstOrDefaultAsync(ct) : null;
        var userIds = t.Messages.Select(m => m.AuthorUserId).Append(t.AssignedUserId).Where(x => x != null).Select(x => x!.Value).Distinct().ToList();
        var users = await db.Users.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName, ct);
        var messages = t.Messages.OrderBy(m => m.CreatedAt).ThenBy(m => m.Id).Select(m => new TicketMessageDto(m.Id,
            m.AuthorUserId is { } a ? users.GetValueOrDefault(a, "Nhân viên") : m.AuthorName ?? "Khách hàng", m.Body, m.IsInternal, m.CreatedAt)).ToList();
        return new TicketDetail(t.Id, t.Code, t.Subject, t.Description, t.PartnerId, customer?.Name, customer?.Phone, t.ReporterName, t.ReporterPhone,
            t.SalesOrderId, order, t.CategoryId, category, t.Channel, t.Priority, t.Status, t.AssignedUserId,
            t.AssignedUserId is { } au ? users.GetValueOrDefault(au) : null, t.FirstResponseDueAt, t.ResolutionDueAt, t.FirstRespondedAt,
            t.ResolvedAt, t.ClosedAt, t.Resolution, t.SatisfactionScore, t.SatisfactionNote, t.IsOverdue(Now), t.CreatedAt, messages,
            Convert.ToBase64String(t.RowVersion));
    }
}
