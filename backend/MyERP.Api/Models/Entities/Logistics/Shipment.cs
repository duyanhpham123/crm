using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Logistics;

public static class ShipmentStatuses
{
    public const string Ready = "ready";             // đã đóng gói, chờ hãng lấy
    public const string PickedUp = "picked_up";
    public const string InTransit = "in_transit";
    public const string Delivered = "delivered";
    public const string Failed = "failed";           // giao không thành công (sẽ giao lại hoặc hoàn)
    public const string Returning = "returning";
    public const string Returned = "returned";       // hàng đã về kho
    public const string Cancelled = "cancelled";

    /// <summary>Trạng thái kế tiếp được phép chuyển tới.</summary>
    public static readonly IReadOnlyDictionary<string, string[]> Next = new Dictionary<string, string[]>
    {
        [Ready] = [PickedUp, Cancelled],
        [PickedUp] = [InTransit, Delivered, Failed],
        [InTransit] = [Delivered, Failed],
        [Failed] = [InTransit, Returning],
        [Returning] = [Returned],
        [Delivered] = [],
        [Returned] = [],
        [Cancelled] = [],
    };

    public static readonly IReadOnlyDictionary<string, string> Names = new Dictionary<string, string>
    {
        [Ready] = "Chờ lấy hàng", [PickedUp] = "Đã lấy hàng", [InTransit] = "Đang giao", [Delivered] = "Đã giao",
        [Failed] = "Giao thất bại", [Returning] = "Đang hoàn", [Returned] = "Đã hoàn về kho", [Cancelled] = "Đã hủy",
    };

    public static bool IsActive(string s) => s is not (Cancelled or Returned);
}

public static class CodStatuses
{
    public const string None = "none";
    public const string Pending = "pending";        // còn đang giao, chưa thu
    public const string Collected = "collected";    // hãng đã thu của khách, chưa trả shop
    public const string Reconciled = "reconciled";  // hãng đã chuyển tiền cho shop
}

/// <summary>Bảng lgs.Carriers - hãng vận chuyển (GHN, GHTK, Viettel Post...) hoặc shop tự giao.</summary>
public sealed class Carrier : Entity, ICompanyOwned
{
    private Carrier() { }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public string CarrierType { get; private set; } = "third_party";
    public bool IsActive { get; private set; } = true;
}

public sealed record ShipmentInfo(
    long CarrierId, string? TrackingNo, string? ServiceType, string ReceiverName, string ReceiverPhone, string Street,
    int PackageCount, decimal? WeightGram, decimal CodAmount, decimal ShippingFee, string FeePayer, string? Note);

/// <summary>
/// Bảng lgs.Shipments - vận đơn giao hàng cho 1 đơn bán.
/// Chờ lấy -> Đã lấy -> Đang giao -> Đã giao (đơn hoàn thành, COD hãng đang giữ) / Thất bại -> Giao lại / Hoàn hàng.
/// </summary>
public sealed class Shipment : AuditableEntity, ICompanyOwned
{
    private Shipment() { }

    public long CompanyId { get; private set; }
    public string DocNo { get; private set; } = "";
    public long? SalesOrderId { get; private set; }
    public long CarrierId { get; private set; }
    public string? TrackingNo { get; private set; }
    public string? ServiceType { get; private set; }
    public long FromWarehouseId { get; private set; }
    public string ReceiverName { get; private set; } = "";
    public string ReceiverPhone { get; private set; } = "";
    public string Street { get; private set; } = "";
    public int PackageCount { get; private set; } = 1;
    public decimal? WeightGram { get; private set; }
    public decimal CodAmount { get; private set; }
    public decimal ShippingFee { get; private set; }
    public string FeePayer { get; private set; } = "sender";
    public string Status { get; private set; } = ShipmentStatuses.Ready;
    public string CodStatus { get; private set; } = CodStatuses.None;
    public DateTime? PickedUpAt { get; private set; }
    public DateTime? DeliveredAt { get; private set; }
    public string? FailedReason { get; private set; }
    public string? Note { get; private set; }

    private readonly List<ShipmentEvent> _events = [];
    public IReadOnlyList<ShipmentEvent> Events => _events;

    public static Result<Shipment> Create(long companyId, string docNo, long salesOrderId, long warehouseId, ShipmentInfo i, DateTime now)
    {
        var s = new Shipment { CompanyId = companyId, DocNo = docNo, SalesOrderId = salesOrderId, FromWarehouseId = warehouseId };
        var r = s.Apply(i);
        if (r.IsFailure) return r.Error!;
        s.CodStatus = s.CodAmount > 0 ? CodStatuses.Pending : CodStatuses.None;
        s._events.Add(ShipmentEvent.Create(now, ShipmentStatuses.Ready, "Tạo vận đơn, chờ hãng lấy hàng", null));
        return s;
    }

    /// <summary>Sửa thông tin (chỉ khi hãng chưa lấy hàng).</summary>
    public Result Update(ShipmentInfo i)
    {
        if (Status != ShipmentStatuses.Ready) return Error.Conflict("shipment.locked", "Hãng đã lấy hàng, không sửa được vận đơn.");
        var r = Apply(i);
        if (r.IsSuccess) CodStatus = CodAmount > 0 ? CodStatuses.Pending : CodStatuses.None;
        return r;
    }

    private Result Apply(ShipmentInfo i)
    {
        if (string.IsNullOrWhiteSpace(i.ReceiverName) || string.IsNullOrWhiteSpace(i.Street))
            return Error.Validation("shipment.receiver", "Nhập tên và địa chỉ người nhận.");
        var phone = PhoneNumber.IsValid(i.ReceiverPhone) ? PhoneNumber.Normalize(i.ReceiverPhone) : null;
        if (phone is null) return Error.Validation("shipment.phone", "Số điện thoại người nhận không hợp lệ.");
        if (i.CodAmount < 0 || i.ShippingFee < 0) return Error.Validation("shipment.amount", "Tiền COD / phí ship không hợp lệ.");
        if (i.FeePayer is not ("sender" or "receiver")) return Error.Validation("shipment.fee_payer", "Người trả phí không hợp lệ.");
        CarrierId = i.CarrierId; TrackingNo = Clean(i.TrackingNo)?.ToUpperInvariant(); ServiceType = Clean(i.ServiceType);
        ReceiverName = i.ReceiverName.Trim(); ReceiverPhone = phone; Street = i.Street.Trim();
        PackageCount = Math.Max(1, i.PackageCount); WeightGram = i.WeightGram; CodAmount = Math.Round(i.CodAmount, 0);
        ShippingFee = Math.Round(i.ShippingFee, 0); FeePayer = i.FeePayer; Note = Clean(i.Note);
        return Result.Success();
    }

    public Result ChangeStatus(string next, string? note, string? location, DateTime now)
    {
        if (!ShipmentStatuses.Next.TryGetValue(Status, out var allowed) || !allowed.Contains(next))
            return Error.Conflict("shipment.invalid_status",
                $"Không chuyển được từ \"{ShipmentStatuses.Names.GetValueOrDefault(Status, Status)}\" sang \"{ShipmentStatuses.Names.GetValueOrDefault(next, next)}\".");
        if (next == ShipmentStatuses.Failed && string.IsNullOrWhiteSpace(note))
            return Error.Validation("shipment.reason", "Nhập lý do giao thất bại.");

        Status = next;
        if (next == ShipmentStatuses.PickedUp) PickedUpAt = now;
        if (next == ShipmentStatuses.Delivered)
        {
            DeliveredAt = now;
            if (CodAmount > 0) CodStatus = CodStatuses.Collected;
        }
        if (next == ShipmentStatuses.Failed) FailedReason = note!.Trim();
        if (next is ShipmentStatuses.Returned or ShipmentStatuses.Cancelled) CodStatus = CodStatuses.None;
        _events.Add(ShipmentEvent.Create(now, next, string.IsNullOrWhiteSpace(note) ? ShipmentStatuses.Names[next] : note.Trim(), location));
        return Result.Success();
    }

    public Result MarkCodReconciled()
    {
        if (CodStatus != CodStatuses.Collected) return Error.Conflict("shipment.cod_not_collected", $"Vận đơn {DocNo} chưa giao xong hoặc đã đối soát.");
        CodStatus = CodStatuses.Reconciled;
        return Result.Success();
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

/// <summary>Bảng lgs.ShipmentTrackingEvents - hành trình vận đơn.</summary>
public sealed class ShipmentEvent
{
    private ShipmentEvent() { }
    public long Id { get; private set; }
    public long ShipmentId { get; private set; }
    public DateTime EventAt { get; private set; }
    public string StatusCode { get; private set; } = "";
    public string? Description { get; private set; }
    public string? Location { get; private set; }

    internal static ShipmentEvent Create(DateTime at, string status, string? description, string? location)
        => new() { EventAt = at, StatusCode = status, Description = description, Location = string.IsNullOrWhiteSpace(location) ? null : location.Trim() };
}
