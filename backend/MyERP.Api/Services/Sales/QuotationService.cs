using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Sales;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Sales;

public interface IQuotationService
{
    Task<QuotationPage> ListAsync(QuotationQuery query, CancellationToken ct);
    Task<Result<QuotationDetail>> GetAsync(long id, CancellationToken ct);
    Task<Result<QuotationDetail>> CreateAsync(SaveQuotationRequest request, CancellationToken ct);
    Task<Result<QuotationDetail>> UpdateAsync(long id, SaveQuotationRequest request, CancellationToken ct);
    Task<Result<QuotationDetail>> SendAsync(long id, CancellationToken ct);
    Task<Result<QuotationDetail>> AcceptAsync(long id, CancellationToken ct);
    Task<Result<QuotationDetail>> RejectAsync(long id, string reason, CancellationToken ct);
    Task<Result<QuotationDetail>> CancelAsync(long id, CancellationToken ct);
}

/// <summary>
/// Báo giá: lập cho khách (sỉ / doanh nghiệp), gửi khách, khách đồng ý thì tự tạo đơn hàng nháp đúng giá đã báo.
/// </summary>
public sealed class QuotationService(AppDbContext db, ICurrentUser currentUser, IDocumentNumberService docNumbers,
    IOrderService orders, TimeProvider clock) : IQuotationService
{
    private DateOnly Today => DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime.AddHours(7));

    public async Task<QuotationPage> ListAsync(QuotationQuery q, CancellationToken ct)
    {
        var page = Math.Max(1, q.Page);
        var size = Math.Clamp(q.PageSize, 1, 100);
        var today = Today;
        var query = db.Quotations.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var s = q.Search.Trim();
            query = query.Where(x => x.DocNo.Contains(s) || db.Partners.Any(p => p.Id == x.PartnerId && (p.Name.Contains(s) || (p.Phone != null && p.Phone.Contains(s)))));
        }
        query = q.Status switch
        {
            QuotationStatuses.Expired => query.Where(x => x.Status == QuotationStatuses.Sent && x.ValidUntil < today),
            QuotationStatuses.Sent => query.Where(x => x.Status == QuotationStatuses.Sent && (x.ValidUntil == null || x.ValidUntil >= today)),
            { Length: > 0 } st => query.Where(x => x.Status == st),
            _ => query,
        };

        var all = db.Quotations.AsNoTracking();
        var open = all.Where(x => x.Status == QuotationStatuses.Draft || (x.Status == QuotationStatuses.Sent && (x.ValidUntil == null || x.ValidUntil >= today)));
        var accepted = all.Where(x => x.Status == QuotationStatuses.Accepted);
        var decided = await all.CountAsync(x => x.Status == QuotationStatuses.Accepted || x.Status == QuotationStatuses.Rejected
            || (x.Status == QuotationStatuses.Sent && x.ValidUntil < today), ct);
        var acceptedCount = await accepted.CountAsync(ct);
        var summary = new QuotationSummary(await open.CountAsync(ct), await open.SumAsync(x => (decimal?)x.TotalAmount, ct) ?? 0,
            acceptedCount, await accepted.SumAsync(x => (decimal?)x.TotalAmount, ct) ?? 0,
            decided == 0 ? 0 : Math.Round(acceptedCount * 100m / decided, 1));

        var total = await query.CountAsync(ct);
        var rows = await query.OrderByDescending(x => x.QuoteDate).ThenByDescending(x => x.Id).Skip((page - 1) * size).Take(size)
            .Select(x => new
            {
                x.Id, x.DocNo, x.QuoteDate, x.ValidUntil, x.PartnerId, x.TotalAmount, x.Status, x.SalespersonUserId,
                Customer = db.Partners.Where(p => p.Id == x.PartnerId).Select(p => p.Name).FirstOrDefault(),
                Items = x.Lines.Count(),
                Order = db.SalesOrders.Where(o => o.QuotationId == x.Id).Select(o => new { o.Id, o.DocNo }).FirstOrDefault(),
                Sales = db.Users.Where(u => u.Id == x.SalespersonUserId).Select(u => u.FullName).FirstOrDefault(),
            }).ToListAsync(ct);
        var items = rows.Select(x => new QuotationListItem(x.Id, x.DocNo, x.QuoteDate, x.ValidUntil, x.PartnerId, x.Customer ?? "", x.Items,
            x.TotalAmount, DisplayStatus(x.Status, x.ValidUntil, today), x.Sales, x.Order?.Id, x.Order?.DocNo)).ToList();
        return new QuotationPage(new PagedResult<QuotationListItem>(items, page, size, total), summary);
    }

    public async Task<Result<QuotationDetail>> GetAsync(long id, CancellationToken ct)
    {
        var q = await db.Quotations.Include(x => x.Lines).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return q is null ? Error.NotFound("báo giá") : await ToDetailAsync(q, ct);
    }

    public async Task<Result<QuotationDetail>> CreateAsync(SaveQuotationRequest r, CancellationToken ct)
    {
        var info = await BuildInfoAsync(r, null, ct);
        if (info.IsFailure) return info.Error!;
        var created = Quotation.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync("QUOTATION", r.QuoteDate, ct), info.Value);
        if (created.IsFailure) return created.Error!;
        db.Quotations.Add(created.Value);
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(created.Value, ct);
    }

    public async Task<Result<QuotationDetail>> UpdateAsync(long id, SaveQuotationRequest r, CancellationToken ct)
    {
        var q = await db.Quotations.Include(x => x.Lines).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (q is null) return Error.NotFound("báo giá");
        if (!string.IsNullOrEmpty(r.RowVersion)) db.Entry(q).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(r.RowVersion);
        var info = await BuildInfoAsync(r, q.SalespersonUserId, ct);
        if (info.IsFailure) return info.Error!;
        var oldLines = q.Lines.ToList();
        var updated = q.Update(info.Value);
        if (updated.IsFailure) return updated.Error!;
        db.RemoveRange(oldLines);
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(q, ct);
    }

    public Task<Result<QuotationDetail>> SendAsync(long id, CancellationToken ct)
        => ChangeAsync(id, q => q.MarkSent(clock.GetUtcNow().UtcDateTime), ct);

    public Task<Result<QuotationDetail>> RejectAsync(long id, string reason, CancellationToken ct) => ChangeAsync(id, q => q.Reject(reason), ct);

    public Task<Result<QuotationDetail>> CancelAsync(long id, CancellationToken ct) => ChangeAsync(id, q => q.Cancel(), ct);

    /// <summary>Khách đồng ý: chốt báo giá và tạo đơn hàng nháp đúng giá đã báo (kho trừ khi xác nhận đơn).</summary>
    public async Task<Result<QuotationDetail>> AcceptAsync(long id, CancellationToken ct)
    {
        var q = await db.Quotations.Include(x => x.Lines).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (q is null) return Error.NotFound("báo giá");
        if (q.IsExpired(Today)) return Error.Conflict("quotation.expired", "Báo giá đã hết hạn. Sửa ngày hiệu lực rồi gửi lại khách.");
        var accepted = q.Accept(clock.GetUtcNow().UtcDateTime);
        if (accepted.IsFailure) return accepted.Error!;

        var customer = await db.Partners.Where(p => p.Id == q.PartnerId).Select(p => new { p.Name, p.Phone, p.Street }).FirstAsync(ct);
        var request = new SaveOrderRequest(q.PartnerId, "other", null, customer.Name, customer.Phone, customer.Street, q.ShippingFee,
            q.DiscountAmount, "bank_transfer", $"Tạo từ báo giá {q.DocNo}",
            q.Lines.Where(l => l.ProductId != null).OrderBy(l => l.LineNumber)
                .Select(l => new OrderLineRequest(l.ProductId!.Value, l.Quantity, l.UnitPrice, l.DiscountPercent)).ToList());
        var order = await orders.CreateAsync(request, ct);
        if (order.IsFailure) return order.Error!;

        db.ChangeTracker.Clear();
        var so = await db.SalesOrders.FirstAsync(o => o.Id == order.Value.Id, ct);
        so.LinkQuotation(q.Id);
        var fresh = await db.Quotations.FirstAsync(x => x.Id == id, ct);
        fresh.Accept(clock.GetUtcNow().UtcDateTime);
        await db.SaveChangesAsync(ct);
        return await GetAsync(id, ct);
    }

    private async Task<Result<QuotationDetail>> ChangeAsync(long id, Func<Quotation, Result> change, CancellationToken ct)
    {
        var q = await db.Quotations.Include(x => x.Lines).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (q is null) return Error.NotFound("báo giá");
        var r = change(q);
        if (r.IsFailure) return r.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(q, ct);
    }

    private async Task<Result<QuotationInfo>> BuildInfoAsync(SaveQuotationRequest r, long? salesperson, CancellationToken ct)
    {
        if (!await db.Partners.AnyAsync(p => p.Id == r.CustomerId && p.IsCustomer, ct))
            return Error.Validation("quotation.customer", "Chọn khách hàng.");
        if (r.Lines.Any(l => l.Quantity <= 0 || l.UnitPrice < 0 || l.DiscountPercent is < 0 or > 100))
            return Error.Validation("quotation.lines", "Số lượng, đơn giá hoặc chiết khấu không hợp lệ.");
        var ids = r.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.Products.Where(p => ids.Contains(p.Id)).ToDictionaryAsync(p => p.Id, ct);
        if (products.Count != ids.Count) return Error.Validation("quotation.product", "Có sản phẩm không tồn tại.");
        return new QuotationInfo(r.CustomerId, r.QuoteDate, r.ValidUntil, salesperson ?? currentUser.RequireUserId(),
            r.DiscountAmount, r.ShippingFee, r.Terms, r.Note,
            r.Lines.Select(l => new OrderLineInfo(l.ProductId, products[l.ProductId].UomId, products[l.ProductId].Name, l.Quantity, l.UnitPrice, l.DiscountPercent)).ToList());
    }

    private static string DisplayStatus(string status, DateOnly? validUntil, DateOnly today)
        => status == QuotationStatuses.Sent && validUntil is { } v && v < today ? QuotationStatuses.Expired : status;

    private async Task<QuotationDetail> ToDetailAsync(Quotation q, CancellationToken ct)
    {
        var ids = q.Lines.Where(l => l.ProductId != null).Select(l => l.ProductId!.Value).Distinct().ToList();
        var products = await db.Products.IgnoreQueryFilters().Where(p => ids.Contains(p.Id)).ToDictionaryAsync(p => p.Id, p => new { p.Code, p.Name }, ct);
        var c = await db.Partners.IgnoreQueryFilters().Where(p => p.Id == q.PartnerId).Select(p => new { p.Name, p.Phone, p.Email, p.Street }).FirstAsync(ct);
        var order = await db.SalesOrders.Where(o => o.QuotationId == q.Id).Select(o => new { o.Id, o.DocNo }).FirstOrDefaultAsync(ct);
        var sales = q.SalespersonUserId is { } u ? await db.Users.Where(x => x.Id == u).Select(x => x.FullName).FirstOrDefaultAsync(ct) : null;
        var lines = q.Lines.OrderBy(l => l.LineNumber).Select(l => new QuotationLineDto(l.Id, l.ProductId ?? 0,
            l.ProductId is { } p ? products.GetValueOrDefault(p)?.Code ?? "" : "", l.ProductId is { } p2 ? products.GetValueOrDefault(p2)?.Name ?? l.Description : l.Description,
            l.Quantity, l.UnitPrice, l.DiscountPercent, l.LineTotal)).ToList();
        return new QuotationDetail(q.Id, q.DocNo, q.RevisionNo, q.QuoteDate, q.ValidUntil, q.PartnerId, c.Name, c.Phone, c.Email, c.Street,
            DisplayStatus(q.Status, q.ValidUntil, Today), q.SubTotal, q.DiscountAmount, q.ShippingFee, q.TotalAmount, q.Terms, q.Note,
            q.SentAt, q.AcceptedAt, q.RejectedReason, sales, order?.Id, order?.DocNo, lines, Convert.ToBase64String(q.RowVersion));
    }
}
