using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.Entities.Inventory;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Inventory;

/// <summary>
/// Nơi DUY NHẤT thay đổi tồn kho. Đơn hàng, đơn nhập, phiếu kho thủ công đều đi qua đây.
/// Ghi sổ một phiếu kho:
///  1. Kiểm tra đủ hàng cho các dòng xuất (trừ khi kho cho phép âm)
///  2. Cập nhật tồn (StockBalances) + giá vốn bình quân gia quyền
///  3. Ghi sổ kho (StockLedger) - không bao giờ sửa / xóa
/// Phải gọi bên trong transaction của bên gọi để chứng từ gốc và kho cùng thành công hoặc cùng thất bại.
/// </summary>
public interface IStockService
{
    Task<Result> PostAsync(StockDocument doc, CancellationToken ct);
}

public sealed class StockService(AppDbContext db, ICurrentUser currentUser, TimeProvider clock) : IStockService
{
    public async Task<Result> PostAsync(StockDocument doc, CancellationToken ct)
    {
        if (doc.Lines.Count == 0) return Error.Validation("stock.no_lines", "Phiếu kho phải có ít nhất một dòng.");

        var warehouse = await db.Warehouses.FirstOrDefaultAsync(w => w.Id == doc.WarehouseId, ct);
        if (warehouse is null) return Error.Validation("stock.warehouse_invalid", "Kho không hợp lệ.");

        var productIds = doc.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.Products.Where(p => productIds.Contains(p.Id)).ToDictionaryAsync(p => p.Id, ct);
        if (products.Count != productIds.Count) return Error.Validation("stock.product_invalid", "Có sản phẩm không tồn tại.");

        var balances = await db.StockBalances
            .Where(b => b.WarehouseId == doc.WarehouseId && productIds.Contains(b.ProductId))
            .ToDictionaryAsync(b => b.ProductId, ct);

        // 1. Kiểm tra đủ hàng (gộp các dòng cùng SKU)
        if (!warehouse.AllowNegativeStock)
        {
            var shortages = doc.Lines.Where(l => IsOutgoing(doc, l))
                .GroupBy(l => l.ProductId)
                .Select(g => (Product: products[g.Key], Need: g.Sum(l => Math.Abs(l.Quantity)), Have: balances.GetValueOrDefault(g.Key)?.QtyOnHand ?? 0))
                .Where(x => x.Have < x.Need)
                .Select(x => $"{x.Product.Code} (còn {x.Have:0.##}, cần {x.Need:0.##})")
                .ToList();
            if (shortages.Count > 0)
                return Error.Conflict("stock.insufficient", $"Không đủ hàng trong kho {warehouse.Name}: {string.Join("; ", shortages)}.");
        }

        // Lưu phiếu trước để có Id cho sổ kho
        if (db.Entry(doc).State == EntityState.Detached) db.StockDocuments.Add(doc);
        await db.SaveChangesAsync(ct);

        // 2 + 3. Cập nhật tồn và ghi sổ
        var now = clock.GetUtcNow().UtcDateTime;
        foreach (var line in doc.Lines)
        {
            var product = products[line.ProductId];
            if (!balances.TryGetValue(line.ProductId, out var balance))
            {
                balance = StockBalance.Create(doc.CompanyId, doc.WarehouseId, line.ProductId);
                db.StockBalances.Add(balance);
                balances[line.ProductId] = balance;
            }

            var qty = Math.Abs(line.Quantity);
            if (IsOutgoing(doc, line))
            {
                var cost = balance.AvgCost > 0 ? balance.AvgCost : product.CostPrice;
                line.SetCost(cost);
                balance.Issue(qty, now);
                db.StockLedger.Add(StockLedgerEntry.Create(doc, line, 0, qty, cost));
            }
            else
            {
                var cost = line.UnitCost > 0 ? line.UnitCost : (balance.AvgCost > 0 ? balance.AvgCost : product.CostPrice);
                line.SetCost(cost);
                balance.Receive(qty, cost, now);
                db.StockLedger.Add(StockLedgerEntry.Create(doc, line, qty, 0, cost));
                product.SetCostPrice(balance.AvgCost);
            }
        }

        doc.MarkDone(currentUser.UserId, now);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    private static bool IsOutgoing(StockDocument doc, StockDocumentLine line) =>
        doc.DocType == StockDocTypes.Issue || (doc.DocType == StockDocTypes.Adjustment && line.Quantity < 0);
}
