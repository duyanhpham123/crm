using MyERP.Api.Common;
using Microsoft.EntityFrameworkCore;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Sales;
using MyERP.Api.Services.Sales;

namespace MyERP.Api.Services.Reports;

public interface IReportService
{
    Task<Result<Dashboard>> GetDashboardAsync(int? days, DateOnly? from, DateOnly? to, CancellationToken ct);
}

/// <summary>
/// Báo cáo tổng quan bán hàng. Doanh thu = tiền hàng sau giảm giá (không gồm phí ship),
/// chỉ tính đơn đã xác nhận / hoàn thành; ngày theo giờ Việt Nam.
/// </summary>
public sealed class ReportService(AppDbContext db, TimeProvider clock) : IReportService
{
    private sealed record OrderRow(long Id, DateTime OrderDate, string Channel, string Status, decimal Revenue, decimal Cogs);

    /// <summary>Khoảng dài nhất xem được trong một lần (2 năm).</summary>
    public const int MaxRangeDays = 732;

    /// <summary>
    /// Kỳ báo cáo: from - to (theo ngày Việt Nam, tính cả 2 đầu) hoặc N ngày gần nhất. So sánh với kỳ liền trước cùng số ngày.
    /// Biểu đồ gom theo ngày (tối đa 62 ngày), theo tuần (tối đa 186 ngày), dài hơn thì theo tháng.
    /// </summary>
    public async Task<Result<Dashboard>> GetDashboardAsync(int? days, DateOnly? fromDate, DateOnly? toDate, CancellationToken ct)
    {
        var today = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime.AddHours(7));
        DateOnly from, to;
        if (fromDate is not null || toDate is not null)
        {
            from = fromDate ?? toDate!.Value;
            to = toDate ?? today;
            if (to < from) return Error.Validation("report.range", "Ngày bắt đầu phải trước ngày kết thúc.");
            if (to.DayNumber - from.DayNumber + 1 > MaxRangeDays) return Error.Validation("report.range", "Chỉ xem tối đa 2 năm mỗi lần.");
        }
        else
        {
            var n = Math.Clamp(days ?? 30, 1, MaxRangeDays);
            to = today;
            from = today.AddDays(-n + 1);
        }
        var length = to.DayNumber - from.DayNumber + 1;
        var prevTo = from.AddDays(-1);
        var prevFrom = from.AddDays(-length);
        var fromUtc = OrderService.LocalDayStartUtc(from);
        var prevFromUtc = OrderService.LocalDayStartUtc(prevFrom);
        var toUtc = OrderService.LocalDayStartUtc(to.AddDays(1));

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

        var granularity = length <= 62 ? "day" : length <= 186 ? "week" : "month";
        DateOnly Bucket(DateOnly d) => granularity switch
        {
            "day" => d,
            "week" => Max(from, d.AddDays(-(((int)d.DayOfWeek + 6) % 7))),   // tuần bắt đầu thứ Hai
            _ => Max(from, new DateOnly(d.Year, d.Month, 1)),
        };
        static DateOnly Max(DateOnly a, DateOnly b) => a > b ? a : b;
        var buckets = Enumerable.Range(0, length).Select(i => Bucket(from.AddDays(i))).Distinct().ToList();
        var soldByBucket = currentSold.GroupBy(o => Bucket(DateOnly.FromDateTime(o.OrderDate.AddHours(7)))).ToDictionary(g => g.Key, g => g.ToList());
        var byDay = buckets.Select(b =>
        {
            var list = soldByBucket.GetValueOrDefault(b) ?? [];
            return new DailyRevenue(b, Rev(list), Gp(list), list.Count);
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

        return new Dashboard(length, from, to, prevFrom, prevTo, granularity,
            new KpiValue(Rev(currentSold), Rev(prevSold)),
            new KpiValue(Math.Round(Gp(currentSold), 0), Math.Round(Gp(prevSold), 0)),
            new KpiValue(currentSold.Count, prevSold.Count),
            new KpiValue(Aov(currentSold), Aov(prevSold)),
            receivable, Math.Round(stockValue, 0), byDay, byChannel, byCategory, topProducts, lowStock, byStatus);
    }
}
