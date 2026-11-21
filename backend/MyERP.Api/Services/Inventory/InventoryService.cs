using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Inventory;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Inventory;

public interface IInventoryService
{
    Task<StockPage> GetStockAsync(StockQuery query, CancellationToken ct);
    Task<PagedResult<StockDocumentListItem>> ListDocumentsAsync(string? docType, string? search, int page, int pageSize, CancellationToken ct);
    Task<Result<StockDocumentDetail>> GetDocumentAsync(long id, CancellationToken ct);
    Task<Result<StockDocumentDetail>> CreateDocumentAsync(CreateStockDocumentRequest request, CancellationToken ct);
}

/// <summary>Tồn kho và phiếu kho thủ công (nhập ngoài đơn mua, xuất hủy / dùng nội bộ, kiểm kê).</summary>
public sealed class InventoryService(
    AppDbContext db,
    ICurrentUser currentUser,
    IStockService stock,
    IDocumentNumberService docNumbers,
    TimeProvider clock) : IInventoryService
{
    public async Task<StockPage> GetStockAsync(StockQuery q, CancellationToken ct)
    {
        var page = Math.Max(1, q.Page);
        var pageSize = Math.Clamp(q.PageSize, 1, 200);

        var rows = from p in db.Products
                   where p.IsStockTracked && p.IsActive
                   from b in db.StockBalances.Where(b => b.ProductId == p.Id && (q.WarehouseId == null || b.WarehouseId == q.WarehouseId)).DefaultIfEmpty()
                   select new { p, b };

        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            foreach (var word in q.Search.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries).Take(5))
            {
                var w = word;
                rows = rows.Where(x => x.p.Name.Contains(w) || x.p.Code.Contains(w) || x.p.Barcode == w);
            }
        }
        if (q.CategoryId is { } c) rows = rows.Where(x => x.p.CategoryId == c);

        var summaryData = await rows.GroupBy(_ => 1).Select(g => new
        {
            Qty = g.Sum(x => (decimal?)x.b!.QtyOnHand) ?? 0,
            Value = g.Sum(x => (decimal?)(x.b!.QtyOnHand * x.b.AvgCost)) ?? 0,
            Skus = g.Count(),
            Low = g.Count(x => (x.b == null ? 0 : x.b.QtyOnHand) <= x.p.MinStock && (x.b == null ? 0 : x.b.QtyOnHand) > 0),
            Out = g.Count(x => (x.b == null ? 0 : x.b.QtyOnHand) <= 0)
        }).FirstOrDefaultAsync(ct);
        var summary = new StockSummary(summaryData?.Qty ?? 0, Math.Round(summaryData?.Value ?? 0, 0), summaryData?.Skus ?? 0, summaryData?.Low ?? 0, summaryData?.Out ?? 0);

        if (q.LowOnly) rows = rows.Where(x => (x.b == null ? 0 : x.b.QtyOnHand) <= x.p.MinStock);

        var total = await rows.CountAsync(ct);
        var items = await rows
            .OrderBy(x => (x.b == null ? 0 : x.b.QtyOnHand) <= x.p.MinStock ? 0 : 1).ThenBy(x => x.p.Name)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new StockRow(x.p.Id, x.p.Code, x.p.Name, x.p.Color, x.p.Size,
                db.ProductCategories.Where(cat => cat.Id == x.p.CategoryId).Select(cat => cat.Name).FirstOrDefault(),
                x.b == null ? "" : db.Warehouses.Where(w => w.Id == x.b.WarehouseId).Select(w => w.Name).FirstOrDefault() ?? "",
                x.b == null ? 0 : x.b.QtyOnHand, x.p.MinStock,
                x.b == null ? x.p.CostPrice : x.b.AvgCost,
                x.b == null ? 0 : Math.Round(x.b.QtyOnHand * x.b.AvgCost, 0),
                (x.b == null ? 0 : x.b.QtyOnHand) <= x.p.MinStock))
            .AsNoTracking().ToListAsync(ct);

        return new StockPage(new PagedResult<StockRow>(items, page, pageSize, total), summary);
    }

    public async Task<PagedResult<StockDocumentListItem>> ListDocumentsAsync(string? docType, string? search, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var q = db.StockDocuments.Where(d => d.Status == "done");
        if (!string.IsNullOrWhiteSpace(docType)) q = q.Where(d => d.DocType == docType);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            q = q.Where(d => d.DocNo.Contains(s) || (d.SourceDocNo != null && d.SourceDocNo.Contains(s)) || (d.Note != null && d.Note.Contains(s)));
        }
        var total = await q.CountAsync(ct);
        var items = await q.OrderByDescending(d => d.DocDate).ThenByDescending(d => d.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(d => new StockDocumentListItem(d.Id, d.DocNo, d.DocType, d.Reason,
                db.Warehouses.Where(w => w.Id == d.WarehouseId).Select(w => w.Name).FirstOrDefault() ?? "",
                db.Partners.Where(p => p.Id == d.PartnerId).Select(p => p.Name).FirstOrDefault(),
                d.SourceDocNo, d.DocDate, d.TotalQuantity, d.TotalValue, d.Note))
            .AsNoTracking().ToListAsync(ct);
        return new PagedResult<StockDocumentListItem>(items, page, pageSize, total);
    }

    public async Task<Result<StockDocumentDetail>> GetDocumentAsync(long id, CancellationToken ct)
    {
        var d = await db.StockDocuments.Include(x => x.Lines).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return d is null ? Error.NotFound("phiếu kho") : await ToDetailAsync(d, ct);
    }

    public async Task<Result<StockDocumentDetail>> CreateDocumentAsync(CreateStockDocumentRequest req, CancellationToken ct)
    {
        var (sequence, reasons) = req.DocType switch
        {
            StockDocTypes.Receipt => ("STOCK_RECEIPT", new[] { "purchase", "sale_return", "opening", "other" }),
            StockDocTypes.Issue => ("STOCK_ISSUE", new[] { "internal_use", "scrap", "purchase_return", "other" }),
            StockDocTypes.Adjustment => ("STOCK_ADJUST", new[] { "count", "other" }),
            _ => ("", Array.Empty<string>())
        };
        if (sequence == "") return Error.Validation("stock.type_invalid", "Loại phiếu không hợp lệ.");
        if (!reasons.Contains(req.Reason)) return Error.Validation("stock.reason_invalid", "Lý do không phù hợp với loại phiếu.");

        var productIds = req.Lines.Select(l => l.ProductId).Distinct().ToList();
        var uoms = await db.Products.Where(p => productIds.Contains(p.Id)).ToDictionaryAsync(p => p.Id, p => p.UomId, ct);
        if (uoms.Count != productIds.Count) return Error.Validation("stock.product_invalid", "Có sản phẩm không tồn tại.");

        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var now = clock.GetUtcNow().UtcDateTime;
            var doc = StockDocument.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync(sequence, ct: ct),
                req.DocType, req.Reason, req.WarehouseId, now, req.Note);
            foreach (var l in req.Lines)
                doc.AddLine(l.ProductId, uoms[l.ProductId], req.DocType == StockDocTypes.Adjustment ? l.Quantity : Math.Abs(l.Quantity), l.UnitCost ?? 0);

            var posted = await stock.PostAsync(doc, ct);
            if (posted.IsFailure) return (Result<StockDocumentDetail>)posted.Error!;
            await tx.CommitAsync(ct);
            return (Result<StockDocumentDetail>)await ToDetailAsync(doc, ct);
        });
    }

    private async Task<StockDocumentDetail> ToDetailAsync(StockDocument d, CancellationToken ct)
    {
        var ids = d.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.Products.IgnoreQueryFilters().Where(p => ids.Contains(p.Id)).ToDictionaryAsync(p => p.Id, p => new { p.Code, p.Name }, ct);
        var warehouse = await db.Warehouses.IgnoreQueryFilters().Where(w => w.Id == d.WarehouseId).Select(w => w.Name).FirstOrDefaultAsync(ct) ?? "";
        var partner = d.PartnerId is { } pid ? await db.Partners.IgnoreQueryFilters().Where(p => p.Id == pid).Select(p => p.Name).FirstOrDefaultAsync(ct) : null;
        return new StockDocumentDetail(d.Id, d.DocNo, d.DocType, d.Reason, d.WarehouseId, warehouse, partner, d.SourceType, d.SourceId,
            d.SourceDocNo, d.DocDate, d.Note, d.TotalQuantity, d.TotalValue,
            d.Lines.OrderBy(l => l.LineNumber).Select(l => new StockDocumentLineDto(l.ProductId, products[l.ProductId].Code,
                products[l.ProductId].Name, l.Quantity, l.UnitCost, l.LineValue)).ToList());
    }
}
