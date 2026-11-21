using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Accounting;
using MyERP.Api.Models.Entities.Logistics;
using MyERP.Api.Models.Entities.Sales;
using MyERP.Api.Services.Accounting;
using MyERP.Api.Services.Common;
using MyERP.Api.Services.Sales;

namespace MyERP.Api.Services.Logistics;

public interface IShipmentService
{
    Task<LogisticsLookups> GetLookupsAsync(CancellationToken ct);
    Task<ShipmentPage> ListAsync(ShipmentQuery query, CancellationToken ct);
    Task<IReadOnlyList<ReadyToShipOrder>> ReadyOrdersAsync(string? search, CancellationToken ct);
    Task<Result<ShipmentDetail>> GetAsync(long id, CancellationToken ct);
    Task<Result<ShipmentDetail>> CreateAsync(SaveShipmentRequest request, CancellationToken ct);
    Task<Result<ShipmentDetail>> UpdateAsync(long id, SaveShipmentRequest request, CancellationToken ct);
    Task<Result<ShipmentDetail>> ChangeStatusAsync(long id, ShipmentStatusRequest request, CancellationToken ct);
    Task<Result<CodReconcileResult>> ReconcileCodAsync(CodReconcileRequest request, CancellationToken ct);
}

/// <summary>
/// Vận chuyển: tạo vận đơn cho đơn đã xác nhận, cập nhật hành trình.
/// Giao xong -> đơn hoàn thành; hoàn hàng về kho -> đơn tự hủy và nhập lại kho.
/// Đối soát COD: hãng chuyển tiền thu hộ -> phiếu báo có + phiếu chi phí ship, đơn được ghi đã thu.
/// </summary>
public sealed class ShipmentService(AppDbContext db, ICurrentUser currentUser, IDocumentNumberService docNumbers,
    IOrderService orders, ICashService cash, TimeProvider clock) : IShipmentService
{
    public async Task<LogisticsLookups> GetLookupsAsync(CancellationToken ct)
        => new(await db.Carriers.Where(c => c.IsActive).OrderBy(c => c.Id).Select(c => new OptionDto(c.Id, c.Name, c.Code)).ToListAsync(ct),
            ShipmentStatuses.Names.Select(kv => new CodeOption(kv.Key, kv.Value)).ToList(),
            await db.BankAccounts.Where(b => b.IsActive).Select(b => new OptionDto(b.Id, b.BankName + " - " + b.AccountNo, null)).ToListAsync(ct));

    public async Task<ShipmentPage> ListAsync(ShipmentQuery q, CancellationToken ct)
    {
        var page = Math.Max(1, q.Page);
        var size = Math.Clamp(q.PageSize, 1, 100);
        var query = db.Shipments.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var s = q.Search.Trim();
            query = query.Where(x => x.DocNo.Contains(s) || (x.TrackingNo != null && x.TrackingNo.Contains(s)) || x.ReceiverName.Contains(s)
                || x.ReceiverPhone.Contains(s) || db.SalesOrders.Any(o => o.Id == x.SalesOrderId && o.DocNo.Contains(s)));
        }
        if (q.Status == "in_transit") query = query.Where(x => x.Status == ShipmentStatuses.PickedUp || x.Status == ShipmentStatuses.InTransit);
        else if (!string.IsNullOrEmpty(q.Status)) query = query.Where(x => x.Status == q.Status);
        if (q.CarrierId is { } cid) query = query.Where(x => x.CarrierId == cid);
        if (!string.IsNullOrEmpty(q.CodStatus)) query = query.Where(x => x.CodStatus == q.CodStatus);

        var all = db.Shipments.AsNoTracking();
        var summary = new ShipmentSummary(
            await all.CountAsync(x => x.Status == ShipmentStatuses.Ready, ct),
            await all.CountAsync(x => x.Status == ShipmentStatuses.PickedUp || x.Status == ShipmentStatuses.InTransit, ct),
            await all.CountAsync(x => x.Status == ShipmentStatuses.Failed, ct),
            await all.CountAsync(x => x.Status == ShipmentStatuses.Returning, ct),
            await all.Where(x => x.CodStatus == CodStatuses.Collected).SumAsync(x => (decimal?)x.CodAmount, ct) ?? 0,
            await all.Where(x => x.CodStatus == CodStatuses.Pending).SumAsync(x => (decimal?)x.CodAmount, ct) ?? 0);

        var total = await query.CountAsync(ct);
        var rows = await query.OrderByDescending(x => x.Id).Skip((page - 1) * size).Take(size)
            .Select(x => new ShipmentListItem(x.Id, x.DocNo, x.CreatedAt, x.SalesOrderId,
                db.SalesOrders.Where(o => o.Id == x.SalesOrderId).Select(o => o.DocNo).FirstOrDefault(),
                db.Carriers.Where(c => c.Id == x.CarrierId).Select(c => c.Name).FirstOrDefault() ?? "",
                x.TrackingNo, x.ReceiverName, x.ReceiverPhone, x.Street, x.CodAmount, x.ShippingFee, x.Status, x.CodStatus, x.FailedReason))
            .ToListAsync(ct);
        return new ShipmentPage(new PagedResult<ShipmentListItem>(rows, page, size, total), summary);
    }

    public async Task<IReadOnlyList<ReadyToShipOrder>> ReadyOrdersAsync(string? search, CancellationToken ct)
    {
        var q = db.SalesOrders.AsNoTracking().Where(o => o.Status == OrderStatuses.Confirmed
            && !db.Shipments.Any(s => s.SalesOrderId == o.Id && s.Status != ShipmentStatuses.Cancelled && s.Status != ShipmentStatuses.Returned));
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            q = q.Where(o => o.DocNo.Contains(s) || (o.ReceiverName != null && o.ReceiverName.Contains(s)) || (o.ReceiverPhone != null && o.ReceiverPhone.Contains(s)));
        }
        return await q.OrderBy(o => o.OrderDate).Take(50).Select(o => new ReadyToShipOrder(o.Id, o.DocNo, o.OrderDate, o.Channel,
            db.Partners.Where(p => p.Id == o.PartnerId).Select(p => p.Name).FirstOrDefault() ?? "",
            o.ReceiverName ?? db.Partners.Where(p => p.Id == o.PartnerId).Select(p => p.Name).FirstOrDefault(),
            o.ReceiverPhone ?? db.Partners.Where(p => p.Id == o.PartnerId).Select(p => p.Phone).FirstOrDefault(),
            o.ShippingStreet ?? db.Partners.Where(p => p.Id == o.PartnerId).Select(p => p.Street).FirstOrDefault(),
            o.TotalAmount, o.TotalAmount - o.AmountPaid, o.PaymentMethodCode)).ToListAsync(ct);
    }

    public async Task<Result<ShipmentDetail>> GetAsync(long id, CancellationToken ct)
    {
        var s = await db.Shipments.Include(x => x.Events).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return s is null ? Error.NotFound("vận đơn") : await ToDetailAsync(s, ct);
    }

    public async Task<Result<ShipmentDetail>> CreateAsync(SaveShipmentRequest r, CancellationToken ct)
    {
        if (r.SalesOrderId is not { } orderId) return Error.Validation("shipment.order", "Chọn đơn hàng cần giao.");
        var order = await db.SalesOrders.FirstOrDefaultAsync(o => o.Id == orderId, ct);
        if (order is null) return Error.NotFound("đơn hàng");
        if (order.Status != OrderStatuses.Confirmed) return Error.Conflict("shipment.order_status", "Chỉ tạo vận đơn cho đơn đã xác nhận (đã xuất kho) và chưa hoàn thành.");
        if (await db.Shipments.AnyAsync(s => s.SalesOrderId == orderId && s.Status != ShipmentStatuses.Cancelled && s.Status != ShipmentStatuses.Returned, ct))
            return Error.Conflict("shipment.exists", "Đơn này đã có vận đơn đang giao.");
        var check = await ValidateAsync(r, null, order.AmountDue, ct);
        if (check.IsFailure) return check.Error!;

        var now = clock.GetUtcNow().UtcDateTime;
        var created = Shipment.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync("SHIPMENT", ct: ct), orderId,
            order.WarehouseId ?? 0, ToInfo(r), now);
        if (created.IsFailure) return created.Error!;
        db.Shipments.Add(created.Value);
        order.SetDeliveryStatus("shipping");
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(created.Value, ct);
    }

    public async Task<Result<ShipmentDetail>> UpdateAsync(long id, SaveShipmentRequest r, CancellationToken ct)
    {
        var s = await db.Shipments.Include(x => x.Events).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (s is null) return Error.NotFound("vận đơn");
        if (!string.IsNullOrEmpty(r.RowVersion)) db.Entry(s).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(r.RowVersion);
        var due = s.SalesOrderId is { } oid ? await db.SalesOrders.Where(o => o.Id == oid).Select(o => o.TotalAmount - o.AmountPaid).FirstAsync(ct) : 0;
        var check = await ValidateAsync(r, s.Id, due, ct);
        if (check.IsFailure) return check.Error!;
        var u = s.Update(ToInfo(r));
        if (u.IsFailure) return u.Error!;
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(s, ct);
    }

    public async Task<Result<ShipmentDetail>> ChangeStatusAsync(long id, ShipmentStatusRequest r, CancellationToken ct)
    {
        var s = await db.Shipments.Include(x => x.Events).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (s is null) return Error.NotFound("vận đơn");
        var changed = s.ChangeStatus(r.Status, r.Note, r.Location, clock.GetUtcNow().UtcDateTime);
        if (changed.IsFailure) return changed.Error!;

        var order = s.SalesOrderId is { } oid ? await db.SalesOrders.FirstOrDefaultAsync(o => o.Id == oid, ct) : null;
        if (order is not null)
        {
            switch (r.Status)
            {
                case ShipmentStatuses.Delivered when order.Status == OrderStatuses.Confirmed:
                    order.Complete();
                    break;
                case ShipmentStatuses.Cancelled:
                    order.SetDeliveryStatus("pending");
                    break;
                case ShipmentStatuses.Returning:
                    order.SetDeliveryStatus("returning");
                    break;
            }
        }
        await db.SaveChangesAsync(ct);

        // Hàng hoàn về kho: hủy đơn để nhập lại kho đúng giá vốn (OrderService tự tạo phiếu nhập)
        if (r.Status == ShipmentStatuses.Returned && order is { Status: OrderStatuses.Confirmed })
        {
            var cancelled = await orders.CancelAsync(order.Id, $"Giao không thành công, hàng hoàn về theo vận đơn {s.DocNo}", ct);
            if (cancelled.IsFailure) return cancelled.Error!;
            db.ChangeTracker.Clear();
            var o2 = await db.SalesOrders.FirstAsync(o => o.Id == order.Id, ct);
            o2.SetDeliveryStatus("returned");
            await db.SaveChangesAsync(ct);
        }
        return await GetAsync(id, ct);
    }

    /// <summary>
    /// Đối soát COD với 1 hãng: các vận đơn đã giao (hãng đang giữ tiền) -> 1 phiếu báo có tổng COD
    /// + 1 phiếu chi tổng phí ship; mỗi đơn được ghi nhận đã thu tiền.
    /// </summary>
    public async Task<Result<CodReconcileResult>> ReconcileCodAsync(CodReconcileRequest r, CancellationToken ct)
    {
        if (r.ShipmentIds.Count == 0) return Error.Validation("cod.empty", "Chọn vận đơn cần đối soát.");
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            var carrier = await db.Carriers.FirstOrDefaultAsync(c => c.Id == r.CarrierId, ct);
            if (carrier is null) return (Result<CodReconcileResult>)Error.NotFound("hãng vận chuyển");
            var list = await db.Shipments.Where(s => r.ShipmentIds.Contains(s.Id)).ToListAsync(ct);
            if (list.Count != r.ShipmentIds.Distinct().Count() || list.Any(s => s.CarrierId != r.CarrierId))
                return Error.Validation("cod.invalid", "Có vận đơn không thuộc hãng đã chọn.");

            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var today = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime.AddHours(7));
            var orderIds = list.Where(s => s.SalesOrderId != null).Select(s => s.SalesOrderId!.Value).ToList();
            var orderMap = await db.SalesOrders.Where(o => orderIds.Contains(o.Id)).ToDictionaryAsync(o => o.Id, ct);
            foreach (var s in list)
            {
                var m = s.MarkCodReconciled();
                if (m.IsFailure) return (Result<CodReconcileResult>)m.Error!;
                if (s.SalesOrderId is { } oid && orderMap.TryGetValue(oid, out var o) && o.AmountDue > 0)
                {
                    var pay = o.RecordPayment(Math.Min(s.CodAmount, o.AmountDue), "cod");
                    if (pay.IsFailure) return (Result<CodReconcileResult>)pay.Error!;
                }
            }
            var totalCod = list.Sum(s => s.CodAmount);
            var totalFee = list.Where(s => s.FeePayer == "sender").Sum(s => s.ShippingFee);
            var refs = string.Join(", ", list.Select(s => s.DocNo).Take(5)) + (list.Count > 5 ? $"... ({list.Count} vận đơn)" : "");
            var receipt = await cash.AddVoucherAsync(new VoucherSpec(VoucherTypes.Receipt, VoucherCategories.Cod, "bank_transfer", r.BankAccountId,
                null, today, totalCod, $"{carrier.Name} chuyển tiền COD: {refs}", carrier.Name, r.Reference), ct);
            if (receipt.IsFailure) return (Result<CodReconcileResult>)receipt.Error!;
            string? feeDoc = null;
            if (totalFee > 0)
            {
                var fee = await cash.AddVoucherAsync(new VoucherSpec(VoucherTypes.Payment, VoucherCategories.Shipping, "bank_transfer", r.BankAccountId,
                    null, today, totalFee, $"Phí vận chuyển {carrier.Name} trừ vào COD: {refs}", carrier.Name, r.Reference), ct);
                if (fee.IsFailure) return (Result<CodReconcileResult>)fee.Error!;
                feeDoc = fee.Value.DocNo;
            }
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<CodReconcileResult>)new CodReconcileResult(list.Count, totalCod, totalFee, totalCod - totalFee, receipt.Value.DocNo, feeDoc);
        });
    }

    private async Task<Result> ValidateAsync(SaveShipmentRequest r, long? selfId, decimal amountDue, CancellationToken ct)
    {
        if (!await db.Carriers.AnyAsync(c => c.Id == r.CarrierId, ct)) return Error.Validation("shipment.carrier", "Chọn hãng vận chuyển.");
        if (r.CodAmount > amountDue) return Error.Validation("shipment.cod_too_large", $"Tiền COD không được lớn hơn số khách còn phải trả ({amountDue:N0} đ).");
        if (!string.IsNullOrWhiteSpace(r.TrackingNo))
        {
            var t = r.TrackingNo.Trim().ToUpperInvariant();
            if (await db.Shipments.AnyAsync(s => s.CarrierId == r.CarrierId && s.TrackingNo == t && s.Id != selfId, ct))
                return Error.Conflict("shipment.tracking_taken", "Mã vận đơn của hãng đã được dùng.");
        }
        return Result.Success();
    }

    private static ShipmentInfo ToInfo(SaveShipmentRequest r) => new(r.CarrierId, r.TrackingNo, r.ServiceType, r.ReceiverName, r.ReceiverPhone,
        r.Street, r.PackageCount, r.WeightGram, r.CodAmount, r.ShippingFee, r.FeePayer, r.Note);

    private async Task<ShipmentDetail> ToDetailAsync(Shipment s, CancellationToken ct)
    {
        var carrier = await db.Carriers.Where(c => c.Id == s.CarrierId).Select(c => c.Name).FirstOrDefaultAsync(ct) ?? "";
        var order = s.SalesOrderId is { } oid
            ? await db.SalesOrders.IgnoreQueryFilters().Where(o => o.Id == oid).Select(o => new { o.DocNo, o.Status, Due = o.TotalAmount - o.AmountPaid }).FirstOrDefaultAsync(ct)
            : null;
        return new ShipmentDetail(s.Id, s.DocNo, s.CreatedAt, s.SalesOrderId, order?.DocNo, order?.Status, order?.Due ?? 0, s.CarrierId, carrier,
            s.TrackingNo, s.ServiceType, s.ReceiverName, s.ReceiverPhone, s.Street, s.PackageCount, s.WeightGram, s.CodAmount, s.ShippingFee,
            s.FeePayer, s.Status, s.CodStatus, s.PickedUpAt, s.DeliveredAt, s.FailedReason, s.Note,
            ShipmentStatuses.Next.GetValueOrDefault(s.Status, []),
            s.Events.OrderByDescending(e => e.EventAt).ThenByDescending(e => e.Id).Select(e => new ShipmentEventDto(e.EventAt, e.StatusCode, e.Description, e.Location)).ToList(),
            Convert.ToBase64String(s.RowVersion));
    }
}
