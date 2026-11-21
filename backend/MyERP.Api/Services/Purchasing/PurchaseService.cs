using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Inventory;
using MyERP.Api.Models.Entities.MasterData;
using MyERP.Api.Models.Entities.Purchasing;
using MyERP.Api.Services.Common;
using MyERP.Api.Services.Inventory;

namespace MyERP.Api.Services.Purchasing;

public interface IPurchaseService
{
    Task<PagedResult<SupplierListItem>> ListSuppliersAsync(string? search, int page, int pageSize, CancellationToken ct);
    Task<Result<SupplierListItem>> CreateSupplierAsync(SaveSupplierRequest request, CancellationToken ct);
    Task<Result<SupplierListItem>> UpdateSupplierAsync(long id, SaveSupplierRequest request, CancellationToken ct);
    Task<PagedResult<PurchaseListItem>> ListAsync(PurchaseQuery query, CancellationToken ct);
    Task<Result<PurchaseDetail>> GetAsync(long id, CancellationToken ct);
    Task<Result<PurchaseDetail>> CreateAsync(SavePurchaseRequest request, CancellationToken ct);
    Task<Result<PurchaseDetail>> UpdateAsync(long id, SavePurchaseRequest request, CancellationToken ct);
    Task<Result<PurchaseDetail>> ConfirmAsync(long id, CancellationToken ct);
    Task<Result<PurchaseDetail>> ReceiveAsync(long id, CancellationToken ct);
    Task<Result<PurchaseDetail>> CancelAsync(long id, CancellationToken ct);
}

/// <summary>Nhà cung cấp và đơn nhập hàng. Nhận hàng = nhập kho với giá vốn đã phân bổ chi phí khác.</summary>
public sealed class PurchaseService(
    AppDbContext db,
    ICurrentUser currentUser,
    IDocumentNumberService docNumbers,
    IStockService stock,
    TimeProvider clock) : IPurchaseService
{
    // ---------- Nhà cung cấp ----------

    public async Task<PagedResult<SupplierListItem>> ListSuppliersAsync(string? search, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var q = db.Partners.Where(p => p.IsSupplier);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            q = q.Where(p => p.Name.Contains(s) || p.Code.Contains(s) || (p.TaxCode != null && p.TaxCode.Contains(s)) || (p.Phone != null && p.Phone.Contains(s)));
        }
        var total = await q.CountAsync(ct);
        var items = await ProjectSuppliers(q.OrderBy(p => p.Name).Skip((page - 1) * pageSize).Take(pageSize)).ToListAsync(ct);
        return new PagedResult<SupplierListItem>(items, page, pageSize, total);
    }

    public async Task<Result<SupplierListItem>> CreateSupplierAsync(SaveSupplierRequest req, CancellationToken ct)
    {
        var check = await ValidateSupplierAsync(req, null, ct);
        if (check.IsFailure) return check.Error!;

        var strategy = db.Database.CreateExecutionStrategy();
        var id = await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var p = Partner.CreateSupplier(currentUser.RequireCompanyId(), await docNumbers.NextAsync("SUPPLIER", ct: ct), ToInfo(req));
            if (!string.IsNullOrWhiteSpace(req.ContactName))
                p.AddContact(new ContactInfo(req.ContactName, null, req.ContactPhone, null, null, true, null));
            db.Partners.Add(p);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return p.Id;
        });
        return (await ListSuppliersByIdAsync(id, ct))!;
    }

    public async Task<Result<SupplierListItem>> UpdateSupplierAsync(long id, SaveSupplierRequest req, CancellationToken ct)
    {
        var p = await db.Partners.Include(x => x.Contacts).FirstOrDefaultAsync(x => x.Id == id && x.IsSupplier, ct);
        if (p is null) return Error.NotFound("nhà cung cấp");
        var check = await ValidateSupplierAsync(req, id, ct);
        if (check.IsFailure) return check.Error!;

        p.Update(ToInfo(req));
        var primary = p.Contacts.FirstOrDefault(c => c.IsPrimary);
        if (!string.IsNullOrWhiteSpace(req.ContactName))
        {
            if (primary is null) p.AddContact(new ContactInfo(req.ContactName, null, req.ContactPhone, null, null, true, null));
            else primary.Update(new ContactInfo(req.ContactName, primary.Position, req.ContactPhone, primary.Email, primary.Birthday, true, primary.Note));
        }
        await db.SaveChangesAsync(ct);
        return (await ListSuppliersByIdAsync(id, ct))!;
    }

    private Task<SupplierListItem?> ListSuppliersByIdAsync(long id, CancellationToken ct)
        => ProjectSuppliers(db.Partners.Where(p => p.Id == id)).FirstOrDefaultAsync(ct);

    private IQueryable<SupplierListItem> ProjectSuppliers(IQueryable<Partner> q)
        => q.Select(p => new SupplierListItem(p.Id, p.Code, p.Name, p.TaxCode, p.Phone, p.Email,
                p.Contacts.Where(c => c.IsPrimary).Select(c => c.FullName).FirstOrDefault(),
                db.PurchaseOrders.Count(o => o.PartnerId == p.Id && o.Status != PurchaseStatuses.Cancelled),
                db.PurchaseOrders.Where(o => o.PartnerId == p.Id && o.Status == PurchaseStatuses.Completed).Sum(o => (decimal?)o.TotalAmount) ?? 0,
                p.IsActive, p.Street,
                p.Contacts.Where(c => c.IsPrimary).Select(c => c.Phone).FirstOrDefault(),
                p.Note)).AsNoTracking();

    private async Task<Result> ValidateSupplierAsync(SaveSupplierRequest req, long? excludeId, CancellationToken ct)
    {
        var tax = req.TaxCode?.Replace(" ", "").Trim();
        if (!string.IsNullOrEmpty(tax) && await db.Partners.AnyAsync(p => p.TaxCode == tax && p.Id != excludeId && p.IsSupplier, ct))
            return Error.Conflict("supplier.tax_code_taken", "Mã số thuế đã thuộc nhà cung cấp khác.");
        return Result.Success();
    }

    private static PartnerInfo ToInfo(SaveSupplierRequest r) => new(Partner.Company, r.Name, null, r.TaxCode, r.Phone, r.Email,
        null, null, r.Street, null, null, null, r.Note);

    // ---------- Đơn nhập ----------

    public async Task<PagedResult<PurchaseListItem>> ListAsync(PurchaseQuery q, CancellationToken ct)
    {
        var page = Math.Max(1, q.Page);
        var pageSize = Math.Clamp(q.PageSize, 1, 100);
        var query = db.PurchaseOrders.AsQueryable();
        if (!string.IsNullOrWhiteSpace(q.Status)) query = query.Where(o => o.Status == q.Status);
        if (q.SupplierId is { } sid) query = query.Where(o => o.PartnerId == sid);
        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var s = q.Search.Trim();
            query = query.Where(o => o.DocNo.Contains(s) || db.Partners.Any(p => p.Id == o.PartnerId && p.Name.Contains(s)));
        }
        var total = await query.CountAsync(ct);
        var items = await query.OrderByDescending(o => o.OrderDate).ThenByDescending(o => o.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(o => new PurchaseListItem(o.Id, o.DocNo, o.OrderDate, o.ExpectedDate, o.PartnerId,
                db.Partners.Where(p => p.Id == o.PartnerId).Select(p => p.Name).FirstOrDefault() ?? "",
                o.Lines.Count, o.Lines.Sum(l => l.Quantity), o.TotalAmount, o.Status, o.ReceiptStatus))
            .AsNoTracking().ToListAsync(ct);
        return new PagedResult<PurchaseListItem>(items, page, pageSize, total);
    }

    public async Task<Result<PurchaseDetail>> GetAsync(long id, CancellationToken ct)
    {
        var o = await db.PurchaseOrders.Include(x => x.Lines).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return o is null ? Error.NotFound("đơn nhập") : await ToDetailAsync(o, ct);
    }

    public async Task<Result<PurchaseDetail>> CreateAsync(SavePurchaseRequest req, CancellationToken ct)
    {
        var info = await BuildInfoAsync(req, ct);
        if (info.IsFailure) return info.Error!;
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var created = PurchaseOrder.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync("PURCHASE_ORDER", req.OrderDate, ct),
                currentUser.UserId, info.Value);
            if (created.IsFailure) return (Result<PurchaseDetail>)created.Error!;
            db.PurchaseOrders.Add(created.Value);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<PurchaseDetail>)await ToDetailAsync(created.Value, ct);
        });
    }

    public async Task<Result<PurchaseDetail>> UpdateAsync(long id, SavePurchaseRequest req, CancellationToken ct)
    {
        var o = await db.PurchaseOrders.Include(x => x.Lines).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (o is null) return Error.NotFound("đơn nhập");
        var info = await BuildInfoAsync(req, ct);
        if (info.IsFailure) return info.Error!;
        if (!string.IsNullOrEmpty(req.RowVersion))
            db.Entry(o).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(req.RowVersion);
        if (o.Status == PurchaseStatuses.Draft) db.RemoveRange(o.Lines);
        var r = o.Update(info.Value);
        if (r.IsFailure) return r.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(o, ct);
    }

    public async Task<Result<PurchaseDetail>> ConfirmAsync(long id, CancellationToken ct)
    {
        var o = await db.PurchaseOrders.Include(x => x.Lines).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (o is null) return Error.NotFound("đơn nhập");
        var r = o.Confirm(clock.GetUtcNow().UtcDateTime);
        if (r.IsFailure) return r.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(o, ct);
    }

    /// <summary>Nhận đủ hàng: tạo phiếu nhập kho, giá vốn = giá nhập sau chiết khấu + phân bổ chi phí khác.</summary>
    public async Task<Result<PurchaseDetail>> ReceiveAsync(long id, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            var o = await db.PurchaseOrders.Include(x => x.Lines).FirstOrDefaultAsync(x => x.Id == id, ct);
            if (o is null) return (Result<PurchaseDetail>)Error.NotFound("đơn nhập");
            var can = o.CanReceive();
            if (can.IsFailure) return (Result<PurchaseDetail>)can.Error!;

            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var now = clock.GetUtcNow().UtcDateTime;
            var costs = o.LandedUnitCosts();
            var doc = StockDocument.Create(o.CompanyId, await docNumbers.NextAsync("STOCK_RECEIPT", ct: ct), StockDocTypes.Receipt, "purchase",
                o.WarehouseId, now, $"Nhập hàng theo đơn {o.DocNo}", o.PartnerId, "pur.PurchaseOrders", o.Id, o.DocNo);
            foreach (var l in o.Lines) doc.AddLine(l.ProductId, l.UomId, l.Quantity, costs[l.Id], l.Id);

            var posted = await stock.PostAsync(doc, ct);
            if (posted.IsFailure) return (Result<PurchaseDetail>)posted.Error!;
            o.MarkReceived();
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<PurchaseDetail>)await ToDetailAsync(o, ct);
        });
    }

    public async Task<Result<PurchaseDetail>> CancelAsync(long id, CancellationToken ct)
    {
        var o = await db.PurchaseOrders.Include(x => x.Lines).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (o is null) return Error.NotFound("đơn nhập");
        var r = o.Cancel();
        if (r.IsFailure) return r.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(o, ct);
    }

    private async Task<Result<PurchaseInfo>> BuildInfoAsync(SavePurchaseRequest r, CancellationToken ct)
    {
        if (!await db.Partners.AnyAsync(p => p.Id == r.SupplierId && p.IsSupplier, ct))
            return Error.Validation("purchase.supplier_invalid", "Nhà cung cấp không hợp lệ.");
        var warehouseId = r.WarehouseId ?? await db.Warehouses.OrderBy(w => w.Id).Select(w => w.Id).FirstOrDefaultAsync(ct);
        if (!await db.Warehouses.AnyAsync(w => w.Id == warehouseId, ct)) return Error.Validation("purchase.warehouse_invalid", "Kho không hợp lệ.");

        var ids = r.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.Products.Where(p => ids.Contains(p.Id) && p.IsPurchasable).ToDictionaryAsync(p => p.Id, ct);
        if (products.Count != ids.Count) return Error.Validation("purchase.product_invalid", "Có sản phẩm không tồn tại hoặc không cho phép nhập.");

        return new PurchaseInfo(r.SupplierId, r.OrderDate, r.ExpectedDate, warehouseId, r.OtherCost, r.Note,
            r.Lines.Select(l => new PurchaseLineInfo(l.ProductId, products[l.ProductId].UomId, products[l.ProductId].Name,
                l.Quantity, l.UnitPrice, l.DiscountPercent)).ToList());
    }

    private async Task<PurchaseDetail> ToDetailAsync(PurchaseOrder o, CancellationToken ct)
    {
        var ids = o.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.Products.IgnoreQueryFilters().Where(p => ids.Contains(p.Id)).ToDictionaryAsync(p => p.Id, p => new { p.Code, p.Name }, ct);
        var supplier = await db.Partners.IgnoreQueryFilters().Where(p => p.Id == o.PartnerId).Select(p => p.Name).FirstAsync(ct);
        var receipt = await db.StockDocuments.Where(d => d.SourceType == "pur.PurchaseOrders" && d.SourceId == o.Id)
            .Select(d => new { d.Id, d.DocNo }).FirstOrDefaultAsync(ct);
        return new PurchaseDetail(o.Id, o.DocNo, o.OrderDate, o.ExpectedDate, o.PartnerId, supplier, o.WarehouseId, o.Status, o.ReceiptStatus,
            o.SubTotal, o.OtherCost, o.TotalAmount, o.Note, receipt?.Id, receipt?.DocNo,
            o.Lines.OrderBy(l => l.LineNumber).Select(l => new PurchaseLineDto(l.Id, l.ProductId, products[l.ProductId].Code,
                products[l.ProductId].Name, l.Quantity, l.UnitPrice, l.DiscountPercent, l.LineTotal, l.QtyReceived)).ToList(),
            Convert.ToBase64String(o.RowVersion));
    }
}
