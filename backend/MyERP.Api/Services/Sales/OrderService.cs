using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Inventory;
using MyERP.Api.Models.Entities.MasterData;
using MyERP.Api.Models.Entities.Sales;
using MyERP.Api.Services.Common;
using MyERP.Api.Models.Entities.Accounting;
using MyERP.Api.Models.Entities.Marketing;
using MyERP.Api.Services.Accounting;
using MyERP.Api.Services.Inventory;

namespace MyERP.Api.Services.Sales;

public interface IOrderService
{
    Task<SalesLookups> GetLookupsAsync(CancellationToken ct);
    Task<OrderPage> ListAsync(OrderQuery query, CancellationToken ct);
    Task<Result<OrderDetail>> GetAsync(long id, CancellationToken ct);
    Task<Result<OrderDetail>> CreateAsync(SaveOrderRequest request, CancellationToken ct);
    Task<Result<OrderDetail>> UpdateAsync(long id, SaveOrderRequest request, CancellationToken ct);
    Task<Result<OrderDetail>> ConfirmAsync(long id, CancellationToken ct);
    Task<Result<OrderDetail>> CompleteAsync(long id, CancellationToken ct);
    Task<Result<OrderDetail>> CancelAsync(long id, string reason, CancellationToken ct);
    Task<Result<OrderDetail>> RecordPaymentAsync(long id, RecordPaymentRequest request, CancellationToken ct);
    Task<Result<OrderDetail>> CreateReturnAsync(long id, CreateReturnRequest request, CancellationToken ct);
    Task<Result<PromotionCheckResult>> CheckPromotionAsync(string code, decimal subTotal, decimal shippingFee, string channel, CancellationToken ct);
}

/// <summary>
/// Đơn bán hàng. Xác nhận đơn = xuất kho (qua StockService) trong cùng transaction;
/// hủy đơn đã xác nhận = nhập lại kho đúng giá vốn đã xuất.
/// Phạm vi dữ liệu theo nhân viên bán hàng (SalespersonUserId).
/// </summary>
public sealed class OrderService(
    AppDbContext db,
    ICurrentUser currentUser,
    IDataScopeService dataScope,
    IDocumentNumberService docNumbers,
    IStockService stock,
    ICashService cash,
    TimeProvider clock) : IOrderService
{
    public const string WalkInCode = "KHACHLE";

    public static readonly IReadOnlyList<CodeOption> Channels =
    [
        new("direct", "Tại cửa hàng"), new("facebook", "Facebook"), new("shopee", "Shopee"), new("tiktok", "TikTok Shop"),
        new("lazada", "Lazada"), new("website", "Website"), new("zalo", "Zalo"), new("phone", "Điện thoại"), new("other", "Khác")
    ];

    public static readonly IReadOnlyList<CodeOption> PaymentMethods =
    [
        new("cash", "Tiền mặt"), new("bank_transfer", "Chuyển khoản"), new("card", "Quẹt thẻ"), new("ewallet", "Ví điện tử"), new("cod", "Thu hộ (COD)")
    ];

    public async Task<SalesLookups> GetLookupsAsync(CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        return new SalesLookups(
            await db.Warehouses.OrderBy(w => w.Id).Select(w => new OptionDto(w.Id, w.Name, w.Code)).ToListAsync(ct),
            await (from uc in db.UserCompanies join u in db.Users on uc.UserId equals u.Id
                   where uc.CompanyId == companyId && u.IsActive orderby u.FullName
                   select new OptionDto(u.Id, u.FullName, null)).ToListAsync(ct),
            Channels, PaymentMethods);
    }

    public async Task<OrderPage> ListAsync(OrderQuery q, CancellationToken ct)
    {
        var page = Math.Max(1, q.Page);
        var pageSize = Math.Clamp(q.PageSize, 1, 100);
        var query = await ScopedAsync(Permissions.Orders.View, ct);

        if (!string.IsNullOrWhiteSpace(q.Status)) query = query.Where(o => o.Status == q.Status);
        if (!string.IsNullOrWhiteSpace(q.Channel)) query = query.Where(o => o.Channel == q.Channel);
        if (q.From is { } from) { var f = LocalDayStartUtc(from); query = query.Where(o => o.OrderDate >= f); }
        if (q.To is { } to) { var t = LocalDayStartUtc(to.AddDays(1)); query = query.Where(o => o.OrderDate < t); }
        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var s = q.Search.Trim();
            var phone = PhoneNumber.Normalize(s);
            query = query.Where(o => o.DocNo.Contains(s)
                || (o.ReceiverName != null && o.ReceiverName.Contains(s))
                || (phone != null && phone != "" && o.ReceiverPhone != null && o.ReceiverPhone.Contains(phone))
                || db.Partners.Any(p => p.Id == o.PartnerId && (p.Name.Contains(s) || (phone != null && phone != "" && p.Phone == phone))));
        }

        var sum = await query.Where(o => o.Status != OrderStatuses.Cancelled).GroupBy(_ => 1)
            .Select(g => new { Count = g.Count(), Total = g.Sum(o => o.TotalAmount), Paid = g.Sum(o => o.AmountPaid) })
            .FirstOrDefaultAsync(ct);

        var total = await query.CountAsync(ct);
        var items = await query.OrderByDescending(o => o.OrderDate).ThenByDescending(o => o.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(o => new OrderListItem(o.Id, o.DocNo, o.OrderDate, o.Channel, o.PartnerId,
                db.Partners.Where(p => p.Id == o.PartnerId).Select(p => p.Name).FirstOrDefault() ?? "",
                o.ReceiverPhone ?? db.Partners.Where(p => p.Id == o.PartnerId).Select(p => p.Phone).FirstOrDefault(),
                o.Lines.Count, o.TotalAmount, o.AmountPaid, o.Status, o.PaymentStatus, o.DeliveryStatus,
                db.Users.Where(u => u.Id == o.SalespersonUserId).Select(u => u.FullName).FirstOrDefault()))
            .AsNoTracking().ToListAsync(ct);

        var summary = new OrderSummary(sum?.Count ?? 0, sum?.Total ?? 0, sum?.Paid ?? 0, (sum?.Total ?? 0) - (sum?.Paid ?? 0));
        return new OrderPage(new PagedResult<OrderListItem>(items, page, pageSize, total), summary);
    }

    public async Task<Result<OrderDetail>> GetAsync(long id, CancellationToken ct)
    {
        var o = await (await ScopedAsync(Permissions.Orders.View, ct)).Include(x => x.Lines).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return o is null ? Error.NotFound("đơn hàng") : await ToDetailAsync(o, ct);
    }

    public async Task<Result<OrderDetail>> CreateAsync(SaveOrderRequest req, CancellationToken ct)
    {
        var info = await BuildInfoAsync(req, ct);
        if (info.IsFailure) return info.Error!;
        var promo = await ResolvePromotionAsync(req, info.Value, ct);
        if (promo.IsFailure) return promo.Error!;
        var orderInfo = info.Value with { DiscountAmount = info.Value.DiscountAmount + promo.Value.Discount };

        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var created = SalesOrder.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync("SALES_ORDER", ct: ct), orderInfo);
            if (created.IsFailure) return (Result<OrderDetail>)created.Error!;
            db.SalesOrders.Add(created.Value);
            await db.SaveChangesAsync(ct);
            if (promo.Value.Promotion is { } pr) db.OrderPromotions.Add(new OrderPromotion(created.Value.Id, pr.Id, promo.Value.Discount));
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<OrderDetail>)await ToDetailAsync(created.Value, ct);
        });
    }

    public async Task<Result<OrderDetail>> UpdateAsync(long id, SaveOrderRequest req, CancellationToken ct)
    {
        var o = await LoadForEditAsync(id, ct);
        if (o is null) return Error.NotFound("đơn hàng");
        var info = await BuildInfoAsync(req, ct, o.OrderDate, o.SalespersonUserId);
        if (info.IsFailure) return info.Error!;
        var promo = await ResolvePromotionAsync(req, info.Value, ct);
        if (promo.IsFailure) return promo.Error!;

        if (!string.IsNullOrEmpty(req.RowVersion))
            db.Entry(o).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(req.RowVersion);
        db.RemoveRange(o.Lines);   // dòng cũ xóa hẳn, thay bằng dòng mới
        var updated = o.Update(info.Value with { DiscountAmount = info.Value.DiscountAmount + promo.Value.Discount });
        if (updated.IsFailure) return updated.Error!;
        db.OrderPromotions.RemoveRange(await db.OrderPromotions.Where(x => x.SalesOrderId == o.Id).ToListAsync(ct));
        if (promo.Value.Promotion is { } pr) db.OrderPromotions.Add(new OrderPromotion(o.Id, pr.Id, promo.Value.Discount));
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(o, ct);
    }

    /// <summary>Xác nhận: xuất kho tất cả dòng. Thiếu hàng thì báo rõ SKU nào thiếu bao nhiêu, đơn giữ nguyên Nháp.</summary>
    public async Task<Result<OrderDetail>> ConfirmAsync(long id, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            var o = await LoadForEditAsync(id, ct);
            if (o is null) return (Result<OrderDetail>)Error.NotFound("đơn hàng");
            if (o.Status != OrderStatuses.Draft) return Error.Conflict("order.not_draft", "Đơn hàng đã được xác nhận trước đó.");

            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var now = clock.GetUtcNow().UtcDateTime;
            var doc = StockDocument.Create(o.CompanyId, await docNumbers.NextAsync("STOCK_ISSUE", ct: ct), StockDocTypes.Issue, "sale",
                o.WarehouseId ?? 0, now, $"Xuất bán đơn {o.DocNo}", o.PartnerId, "sales.SalesOrders", o.Id, o.DocNo);
            foreach (var l in o.Lines) doc.AddLine(l.ProductId, l.UomId, l.Quantity, 0, l.Id);

            var posted = await stock.PostAsync(doc, ct);
            if (posted.IsFailure) return (Result<OrderDetail>)posted.Error!;

            var usedPromo = await PromotionOfAsync(o.Id, ct);
            if (usedPromo is not null)
            {
                if (usedPromo.UsageLimit is { } limit && usedPromo.UsedCount >= limit)
                    return (Result<OrderDetail>)Error.Conflict("promotion.used_up", $"Mã {usedPromo.Code} đã hết lượt. Bỏ mã khỏi đơn rồi xác nhận lại.");
                usedPromo.Use();
            }

            var costs = doc.Lines.ToDictionary(l => l.SourceLineId!.Value, l => l.UnitCost);
            var confirmed = o.Confirm(costs, currentUser.UserId, now);
            if (confirmed.IsFailure) return (Result<OrderDetail>)confirmed.Error!;
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<OrderDetail>)await ToDetailAsync(o, ct);
        });
    }

    public async Task<Result<OrderDetail>> CompleteAsync(long id, CancellationToken ct)
    {
        var o = await LoadForEditAsync(id, ct);
        if (o is null) return Error.NotFound("đơn hàng");
        var r = o.Complete();
        if (r.IsFailure) return r.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(o, ct);
    }

    public async Task<Result<OrderDetail>> CancelAsync(long id, string reason, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            var o = await LoadForEditAsync(id, ct);
            if (o is null) return (Result<OrderDetail>)Error.NotFound("đơn hàng");
            var can = o.CanCancel();
            if (can.IsFailure) return (Result<OrderDetail>)can.Error!;

            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var now = clock.GetUtcNow().UtcDateTime;
            if (o.StockWasIssued)
            {
                // Hàng đã xuất -> nhập lại đúng giá vốn lúc xuất để giá vốn kho không bị lệch
                var doc = StockDocument.Create(o.CompanyId, await docNumbers.NextAsync("STOCK_RECEIPT", ct: ct), StockDocTypes.Receipt, "sale_return",
                    o.WarehouseId ?? 0, now, $"Nhập lại hàng do hủy đơn {o.DocNo}", o.PartnerId, "sales.SalesOrders", o.Id, o.DocNo);
                foreach (var l in o.Lines) doc.AddLine(l.ProductId, l.UomId, l.Quantity, l.UnitCost, l.Id);
                var posted = await stock.PostAsync(doc, ct);
                if (posted.IsFailure) return (Result<OrderDetail>)posted.Error!;
            }
            if (o.StockWasIssued && await PromotionOfAsync(o.Id, ct) is { } usedPromo) usedPromo.Release();
            o.Cancel(reason, now);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<OrderDetail>)await ToDetailAsync(o, ct);
        });
    }

    /// <summary>Thu tiền đơn: cập nhật đơn và tạo phiếu thu (tiền mặt: PT, chuyển khoản / thẻ / ví: BC) để sổ quỹ khớp.</summary>
    public async Task<Result<OrderDetail>> RecordPaymentAsync(long id, RecordPaymentRequest req, CancellationToken ct)
    {
        if (PaymentMethods.All(p => p.Code != req.Method)) return Error.Validation("order.method_invalid", "Hình thức thanh toán không hợp lệ.");
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            var o = await LoadForEditAsync(id, ct);
            if (o is null) return (Result<OrderDetail>)Error.NotFound("đơn hàng");
            if (o.Status == OrderStatuses.Draft) return Error.Conflict("order.not_confirmed", "Xác nhận đơn trước khi thu tiền.");
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var r = o.RecordPayment(req.Amount, req.Method);
            if (r.IsFailure) return (Result<OrderDetail>)r.Error!;
            var v = await cash.AddVoucherAsync(new VoucherSpec(VoucherTypes.Receipt, VoucherCategories.Customer, req.Method, null, o.PartnerId,
                LocalToday(), req.Amount, $"Thu tiền đơn {o.DocNo}", SalesOrderId: o.Id), ct);
            if (v.IsFailure) return (Result<OrderDetail>)v.Error!;
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<OrderDetail>)await ToDetailAsync(o, ct);
        });
    }

    /// <summary>
    /// Khách trả hàng: hàng còn tốt nhập lại kho đúng giá vốn lúc bán, hàng lỗi không nhập lại;
    /// hoàn tiền (tiền mặt / chuyển khoản) tạo phiếu chi; giảm tổng tiền đơn (doanh thu thuần).
    /// </summary>
    public async Task<Result<OrderDetail>> CreateReturnAsync(long id, CreateReturnRequest req, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            var o = await LoadForEditAsync(id, ct);
            if (o is null) return (Result<OrderDetail>)Error.NotFound("đơn hàng");
            if (o.Status is not (OrderStatuses.Confirmed or OrderStatuses.Completed))
                return Error.Conflict("order.not_delivered", "Chỉ trả hàng được với đơn đã xác nhận / hoàn thành.");
            if (req.Lines.Select(l => l.SalesOrderLineId).Distinct().Count() != req.Lines.Count)
                return Error.Validation("return.duplicate", "Mỗi sản phẩm chỉ chọn 1 lần.");

            var returned = await ReturnedQtyAsync(o.Id, ct);
            // Giảm giá cấp đơn chia đều theo giá trị dòng: trả hết hàng thì tiền trả = đúng tiền hàng đã bán
            var factor = o.SubTotal == 0 ? 0 : (o.SubTotal - o.DiscountAmount) / o.SubTotal;
            var infos = new List<ReturnLineInfo>();
            foreach (var rl in req.Lines.Where(l => l.Quantity > 0))
            {
                var line = o.Lines.FirstOrDefault(l => l.Id == rl.SalesOrderLineId);
                if (line is null) return Error.Validation("return.line", "Sản phẩm không có trong đơn.");
                var left = line.Quantity - returned.GetValueOrDefault(line.Id);
                if (rl.Quantity > left) return Error.Validation("return.too_many", $"{line.Description}: chỉ còn trả được {left:0.##}.");
                infos.Add(new ReturnLineInfo(line.Id, line.ProductId, rl.Quantity, line.Quantity == 0 ? 0 : line.LineTotal / line.Quantity * factor, rl.Condition));
            }
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var now = clock.GetUtcNow().UtcDateTime;
            var created = SalesReturn.Create(o.CompanyId, await docNumbers.NextAsync("SALES_RETURN", ct: ct), o, now, req.Reason, req.RefundMethod, infos);
            if (created.IsFailure) return (Result<OrderDetail>)created.Error!;
            var ret = created.Value;

            var maxValue = o.TotalAmount - o.ShippingFee;   // phí ship không hoàn khi trả hàng
            if (ret.TotalAmount > maxValue) ret.CapTotal(Math.Max(0, maxValue));
            var refund = req.RefundMethod == "credit_note" ? 0 : Math.Round(req.RefundAmount, 0);
            if (refund > ret.TotalAmount) return Error.Validation("return.refund_too_large", $"Tiền hoàn không được lớn hơn giá trị hàng trả ({ret.TotalAmount:N0} đ).");
            var mustRefund = Math.Min(o.AmountPaid, o.AmountPaid - (o.TotalAmount - ret.TotalAmount));
            if (refund < mustRefund)
                return Error.Validation("return.refund_too_small", $"Khách đã thanh toán, cần hoàn tối thiểu {mustRefund:N0} đ.");
            var reg = o.RegisterReturn(ret.TotalAmount, refund);
            if (reg.IsFailure) return (Result<OrderDetail>)reg.Error!;
            db.SalesReturns.Add(ret);
            await db.SaveChangesAsync(ct);

            var good = ret.Lines.Where(l => l.Condition == "good").ToList();
            if (good.Count > 0)
            {
                var doc = StockDocument.Create(o.CompanyId, await docNumbers.NextAsync("STOCK_RECEIPT", ct: ct), StockDocTypes.Receipt, "sale_return",
                    o.WarehouseId ?? 0, now, $"Khách trả hàng {ret.DocNo} - đơn {o.DocNo}", o.PartnerId, "sales.SalesReturns", ret.Id, ret.DocNo);
                foreach (var l in good)
                {
                    var ol = o.Lines.First(x => x.Id == l.SalesOrderLineId);
                    doc.AddLine(l.ProductId, ol.UomId, l.Quantity, ol.UnitCost, ol.Id);
                }
                var posted = await stock.PostAsync(doc, ct);
                if (posted.IsFailure) return (Result<OrderDetail>)posted.Error!;
                ret.LinkStockDocument(doc.Id);
            }
            if (refund > 0)
            {
                var v = await cash.AddVoucherAsync(new VoucherSpec(VoucherTypes.Payment, VoucherCategories.Refund,
                    req.RefundMethod == "cash" ? "cash" : "bank_transfer", req.BankAccountId, o.PartnerId, LocalToday(), refund,
                    $"Hoàn tiền trả hàng {ret.DocNo} - đơn {o.DocNo}", SalesOrderId: o.Id), ct);
                if (v.IsFailure) return (Result<OrderDetail>)v.Error!;
            }
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<OrderDetail>)await ToDetailAsync(o, ct);
        });
    }

    private async Task<Dictionary<long, decimal>> ReturnedQtyAsync(long orderId, CancellationToken ct)
        => await (from l in db.SalesReturnLines
                  join r in db.SalesReturns on l.SalesReturnId equals r.Id
                  where r.SalesOrderId == orderId
                  group l by l.SalesOrderLineId into g
                  select new { g.Key, Qty = g.Sum(x => x.Quantity) }).ToDictionaryAsync(x => x.Key, x => x.Qty, ct);

    public async Task<Result<PromotionCheckResult>> CheckPromotionAsync(string code, decimal subTotal, decimal shippingFee, string channel, CancellationToken ct)
    {
        var p = await db.Promotions.FirstOrDefaultAsync(x => x.Code == (code ?? "").Trim().ToUpper(), ct);
        if (p is null) return Error.Validation("promotion.not_found", "Mã giảm giá không tồn tại.");
        var d = p.DiscountFor(subTotal, shippingFee, channel, clock.GetUtcNow().UtcDateTime.AddHours(7));
        return d.IsFailure ? d.Error! : new PromotionCheckResult(p.Id, p.Code, p.Name, d.Value);
    }

    /// <summary>Kiểm tra mã giảm giá của đơn (nếu có) và tính tiền giảm trên tiền hàng.</summary>
    private async Task<Result<(Promotion? Promotion, decimal Discount)>> ResolvePromotionAsync(SaveOrderRequest req, OrderInfo info, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.PromotionCode)) return ((Promotion?)null, 0m);
        var p = await db.Promotions.FirstOrDefaultAsync(x => x.Code == req.PromotionCode.Trim().ToUpper(), ct);
        if (p is null) return Error.Validation("promotion.not_found", "Mã giảm giá không tồn tại.");
        var sub = info.Lines.Sum(l => l.Quantity * l.UnitPrice - Math.Round(l.Quantity * l.UnitPrice * l.DiscountPercent / 100, 0));
        var d = p.DiscountFor(sub - info.DiscountAmount, info.ShippingFee, info.Channel, clock.GetUtcNow().UtcDateTime.AddHours(7));
        if (d.IsFailure) return d.Error!;
        return ((Promotion?)p, d.Value);
    }

    private async Task<Promotion?> PromotionOfAsync(long orderId, CancellationToken ct)
        => await db.Promotions.FirstOrDefaultAsync(p => db.OrderPromotions.Any(x => x.SalesOrderId == orderId && x.PromotionId == p.Id), ct);

    private DateOnly LocalToday() => DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime.AddHours(7));

    // ---------- Hàm hỗ trợ ----------

    private async Task<IQueryable<SalesOrder>> ScopedAsync(string permission, CancellationToken ct)
    {
        var me = currentUser.RequireUserId();
        var owners = await dataScope.VisibleOwnersAsync(permission, ct);
        return owners is null
            ? db.SalesOrders
            : db.SalesOrders.Where(o => (o.SalespersonUserId != null && owners.Contains(o.SalespersonUserId.Value)) || o.CreatedBy == me);
    }

    private async Task<SalesOrder?> LoadForEditAsync(long id, CancellationToken ct)
        => await (await ScopedAsync(Permissions.Orders.Edit, ct)).Include(o => o.Lines).FirstOrDefaultAsync(o => o.Id == id, ct);

    private async Task<Result<OrderInfo>> BuildInfoAsync(SaveOrderRequest r, CancellationToken ct, DateTime? orderDate = null, long? salesperson = null)
    {
        if (Channels.All(c => c.Code != r.Channel)) return Error.Validation("order.channel_invalid", "Kênh bán không hợp lệ.");
        if (r.PaymentMethodCode is { } m && PaymentMethods.All(p => p.Code != m))
            return Error.Validation("order.method_invalid", "Hình thức thanh toán không hợp lệ.");

        long customerId;
        if (r.CustomerId is { } cid)
        {
            if (!await db.Partners.AnyAsync(p => p.Id == cid && p.IsCustomer, ct))
                return Error.Validation("order.customer_invalid", "Khách hàng không tồn tại.");
            customerId = cid;
        }
        else customerId = await GetOrCreateWalkInAsync(ct);

        var warehouseId = r.WarehouseId ?? await db.Warehouses.OrderBy(w => w.Id).Select(w => w.Id).FirstOrDefaultAsync(ct);
        if (!await db.Warehouses.AnyAsync(w => w.Id == warehouseId, ct)) return Error.Validation("order.warehouse_invalid", "Kho không hợp lệ.");

        var ids = r.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.Products.Where(p => ids.Contains(p.Id) && p.IsSellable).ToDictionaryAsync(p => p.Id, ct);
        if (products.Count != ids.Count) return Error.Validation("order.product_invalid", "Có sản phẩm không tồn tại hoặc ngừng bán.");

        var lines = r.Lines.Select(l => new OrderLineInfo(l.ProductId, products[l.ProductId].UomId, products[l.ProductId].Name,
            l.Quantity, l.UnitPrice, l.DiscountPercent)).ToList();
        return new OrderInfo(customerId, orderDate ?? clock.GetUtcNow().UtcDateTime, r.Channel, warehouseId,
            salesperson ?? currentUser.RequireUserId(), r.ReceiverName, r.ReceiverPhone, r.ShippingAddress,
            r.ShippingFee, r.DiscountAmount, r.PaymentMethodCode, r.Note, lines);
    }

    /// <summary>Khách không để lại thông tin thì ghi vào khách hàng chung "Khách lẻ" (tự tạo lần đầu).</summary>
    private async Task<long> GetOrCreateWalkInAsync(CancellationToken ct)
    {
        var id = await db.Partners.Where(p => p.Code == WalkInCode).Select(p => (long?)p.Id).FirstOrDefaultAsync(ct);
        if (id is { } existing) return existing;
        var p = Partner.CreateCustomer(currentUser.RequireCompanyId(), WalkInCode,
            new PartnerInfo(Partner.Individual, "Khách lẻ", null, null, null, null, null, null, null, null, null, null, "Khách mua tại quầy không để lại thông tin"));
        db.Partners.Add(p);
        await db.SaveChangesAsync(ct);
        return p.Id;
    }

    private async Task<OrderDetail> ToDetailAsync(SalesOrder o, CancellationToken ct)
    {
        var ids = o.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.Products.IgnoreQueryFilters().Where(p => ids.Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, p => new { p.Code, p.Name, p.Color, p.Size }, ct);
        var customer = await db.Partners.IgnoreQueryFilters().Where(p => p.Id == o.PartnerId).Select(p => new { p.Name, p.Code }).FirstAsync(ct);
        var returnedQty = await ReturnedQtyAsync(o.Id, ct);
        var lines = o.Lines.OrderBy(l => l.LineNumber).Select(l => new OrderLineDto(l.Id, l.ProductId, products[l.ProductId].Code,
            products[l.ProductId].Name, products[l.ProductId].Color, products[l.ProductId].Size, l.Quantity, l.UnitPrice,
            l.DiscountPercent, l.LineTotal, l.UnitCost, returnedQty.GetValueOrDefault(l.Id))).ToList();
        var returns = await db.SalesReturns.AsNoTracking().Include(r => r.Lines).Where(r => r.SalesOrderId == o.Id).OrderBy(r => r.Id).ToListAsync(ct);
        var returnDtos = returns.Select(r => new SalesReturnDto(r.Id, r.DocNo, r.ReturnDate, r.Reason, r.RefundMethod, r.TotalAmount,
            r.Lines.Select(l => new ReturnLineDto(l.ProductId, products.GetValueOrDefault(l.ProductId)?.Code ?? "",
                products.GetValueOrDefault(l.ProductId)?.Name ?? "", l.Quantity, l.UnitPrice, l.LineTotal, l.Condition)).ToList())).ToList();
        var quote = o.QuotationId is { } qid ? await db.Quotations.IgnoreQueryFilters().Where(q => q.Id == qid).Select(q => q.DocNo).FirstOrDefaultAsync(ct) : null;
        var ship = await db.Shipments.AsNoTracking().Where(s => s.SalesOrderId == o.Id).OrderByDescending(s => s.Id)
            .Select(s => new { s.Id, s.DocNo, s.Status }).FirstOrDefaultAsync(ct);
        var tickets = await db.Tickets.CountAsync(t => t.SalesOrderId == o.Id, ct);
        var links = new OrderLinks(o.QuotationId, quote, ship?.Id, ship?.DocNo, ship?.Status, tickets);
        var promo = await (from op in db.OrderPromotions join pr in db.Promotions.IgnoreQueryFilters() on op.PromotionId equals pr.Id
                           where op.SalesOrderId == o.Id select new { pr.Code, op.DiscountAmount }).FirstOrDefaultAsync(ct);
        var returnedCost = o.Lines.Sum(l => returnedQty.GetValueOrDefault(l.Id) * l.UnitCost);
        var grossProfit = o.Status is OrderStatuses.Confirmed or OrderStatuses.Completed
            ? o.Lines.Sum(l => l.LineSubTotal - l.Quantity * l.UnitCost) - o.DiscountAmount - o.ReturnedAmount + returnedCost : 0;

        return new OrderDetail(o.Id, o.DocNo, o.OrderDate, o.Channel, o.PartnerId, customer.Name, customer.Code == WalkInCode,
            o.WarehouseId, o.SalespersonUserId, o.ReceiverName, o.ReceiverPhone, o.ShippingStreet, o.Status, o.PaymentStatus,
            o.DeliveryStatus, o.PaymentMethodCode, o.SubTotal, o.DiscountAmount, o.ShippingFee, o.TotalAmount, o.AmountPaid,
            o.AmountDue, Math.Round(grossProfit, 0), o.Note, o.CancelReason, o.ConfirmedAt, o.CreatedAt, lines,
            Convert.ToBase64String(o.RowVersion), o.ReturnedAmount, returnDtos, links, promo?.Code, promo?.DiscountAmount ?? 0);
    }

    /// <summary>0h ngày D theo giờ Việt Nam, đổi ra UTC (OrderDate lưu UTC).</summary>
    internal static DateTime LocalDayStartUtc(DateOnly day) => day.ToDateTime(TimeOnly.MinValue).AddHours(-7);
}
