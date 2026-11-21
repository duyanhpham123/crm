using Microsoft.EntityFrameworkCore;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Sales;
using MyERP.Api.Services.Sales;

namespace MyERP.Api.Services.Reports;

public interface IReportService
{
    Task<Dashboard> GetDashboardAsync(int days, CancellationToken ct);
}

/// <summary>
/// Báo cáo tổng quan bán hàng. Doanh thu = tiền hàng sau giảm giá (không gồm phí ship),
/// chỉ tính đơn đã xác nhận / hoàn thành; ngày theo giờ Việt Nam.
/// </summary>
public sealed class ReportService(AppDbContext db, TimeProvider clock) : IReportService
{
    private sealed record OrderRow(long Id, DateTime OrderDate, string Channel, string Status, decimal Revenue, decimal Cogs);

    public async Task<Dashboard> GetDashboardAsync(int days, CancellationToken ct)
    {
        days = Math.Clamp(days, 7, 365);
        var today = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime.AddHours(7));
        var from = today.AddDays(-days + 1);
        var prevFrom = from.AddDays(-days);
        var fromUtc = OrderService.LocalDayStartUtc(from);
        var prevFromUtc = OrderService.LocalDayStartUtc(prevFrom);
        var toUtc = OrderService.LocalDayStartUtc(today.AddDays(1));

        var sold = new[] { OrderStatuses.Confirmed, OrderStatuses.Completed };
        var orders = await db.SalesOrders.Where(o => o.OrderDate >= prevFromUtc && o.OrderDate < toUtc)
            .Select(o => new OrderRow(o.Id, o.OrderDate, o.Channel, o.Status,
                o.SubTotal - o.DiscountAmount - o.ReturnedAmount,   // doanh thu thuần (trừ hàng bị trả)
                o.Lines.Sum(l => l.Quantity * l.UnitCost)))
            .AsNoTracking().ToListAsync(ct);

        var current = orders.Where(o => o.OrderDate >= fromUtc).ToList();
        var currentSold = current.Where(o => sold.Contains(o.Status)).ToList();
        var prevSold = orders.Where(o => o.OrderDate < fromUtc && sold.Contains(o.Status)).ToList();

        static decimal Rev(IEnumerable<OrderRow> r) => r.Sum(o => o.Revenue);
        static decimal Gp(IEnumerable<OrderRow> r) => r.Sum(o => o.Revenue - o.Cogs);
        static decimal Aov(List<OrderRow> r) => r.Count == 0 ? 0 : Math.Round(Rev(r) / r.Count, 0);

        var byDay = Enumerable.Range(0, days).Select(i => from.AddDays(i)).Select(d =>
        {
            var dayOrders = currentSold.Where(o => DateOnly.FromDateTime(o.OrderDate.AddHours(7)) == d).ToList();
            return new DailyRevenue(d, Rev(dayOrders), Gp(dayOrders), dayOrders.Count);
        }).ToList();

        var channelNames = OrderService.Channels.ToDictionary(c => c.Code, c => c.Name);
        var byChannel = currentSold.GroupBy(o => o.Channel)
            .Select(g => new NamedValue(channelNames.GetValueOrDefault(g.Key, g.Key), Rev(g), g.Count()))
            .OrderByDescending(x => x.Value).ToList();

        var statusNames = new Dictionary<string, string>
        {
            [OrderStatuses.Draft] = "Nháp", [OrderStatuses.Confirmed] = "Đã xác nhận",
            [OrderStatuses.Completed] = "Hoàn thành", [OrderStatuses.Cancelled] = "Đã hủy"
        };
        var byStatus = current.GroupBy(o => o.Status)
            .Select(g => new NamedValue(statusNames.GetValueOrDefault(g.Key, g.Key), g.Sum(o => o.Revenue), g.Count())).ToList();

        // Theo sản phẩm / nhóm hàng: tính trên dòng đơn trong kỳ
        var soldIds = currentSold.Select(o => o.Id).ToList();
        var lines = await (from l in db.SalesOrderLines
                           join p in db.Products.IgnoreQueryFilters() on l.ProductId equals p.Id
                           where soldIds.Contains(l.SalesOrderId)
                           select new { p.ModelId, ProductId = p.Id, p.Code, p.Name, p.CategoryId, l.Quantity, l.LineSubTotal, l.UnitCost })
                          .AsNoTracking().ToListAsync(ct);

        var models = await db.ProductModels.IgnoreQueryFilters().Select(m => new { m.Id, m.Code, m.Name }).ToDictionaryAsync(m => m.Id, ct);
        var topProducts = lines.GroupBy(l => l.ModelId ?? -l.ProductId)
            .Select(g =>
            {
                var first = g.First();
                var (code, name) = first.ModelId is { } mid && models.TryGetValue(mid, out var m) ? (m.Code, m.Name) : (first.Code, first.Name);
                return new TopProduct(first.ModelId ?? first.ProductId, code, name, g.Sum(x => x.Quantity), g.Sum(x => x.LineSubTotal),
                    g.Sum(x => x.LineSubTotal - x.Quantity * x.UnitCost));
            })
            .OrderByDescending(x => x.Revenue).Take(10).ToList();

        var categories = await db.ProductCategories.Select(c => new { c.Id, c.Name }).ToDictionaryAsync(c => c.Id, c => c.Name, ct);
        var byCategory = lines.GroupBy(l => l.CategoryId)
            .Select(g => new NamedValue(g.Key is { } cid ? categories.GetValueOrDefault(cid, "Khác") : "Khác", g.Sum(x => x.LineSubTotal), g.Sum(x => x.Quantity)))
            .OrderByDescending(x => x.Value).ToList();

        var lowStock = await (from p in db.Products
                              where p.IsActive && p.IsStockTracked
                              let onHand = db.StockBalances.Where(b => b.ProductId == p.Id).Sum(b => (decimal?)b.QtyOnHand) ?? 0
                              where onHand <= p.MinStock
                              orderby onHand, p.Name
                              select new LowStockItem(p.Id, p.Code, p.Name, onHand, p.MinStock)).Take(10).AsNoTracking().ToListAsync(ct);

        var stockValue = await db.StockBalances.SumAsync(b => (decimal?)(b.QtyOnHand * b.AvgCost), ct) ?? 0;
        var receivable = await db.SalesOrders.Where(o => sold.Contains(o.Status)).SumAsync(o => (decimal?)(o.TotalAmount - o.AmountPaid), ct) ?? 0;

        return new Dashboard(days,
            new KpiValue(Rev(currentSold), Rev(prevSold)),
            new KpiValue(Math.Round(Gp(currentSold), 0), Math.Round(Gp(prevSold), 0)),
            new KpiValue(currentSold.Count, prevSold.Count),
            new KpiValue(Aov(currentSold), Aov(prevSold)),
            receivable, Math.Round(stockValue, 0), byDay, byChannel, byCategory, topProducts, lowStock, byStatus);
    }
}
