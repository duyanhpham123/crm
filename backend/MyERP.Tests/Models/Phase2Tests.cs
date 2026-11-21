using MyERP.Api.Models.Entities.Accounting;
using MyERP.Api.Models.Entities.Logistics;
using MyERP.Api.Models.Entities.Purchasing;
using MyERP.Api.Models.Entities.Sales;
using MyERP.Api.Models.Entities.Support;

namespace MyERP.Tests.Models;

public class QuotationTests
{
    private static QuotationInfo Info(decimal discount = 50_000) => new(5, new DateOnly(2026, 11, 20), new DateOnly(2026, 11, 30), 1,
        discount, 30_000, "Thanh toán 50% khi đặt", null,
        [new OrderLineInfo(10, 1, "Áo polo", 50, 249_000, 10), new OrderLineInfo(11, 1, "Quần kaki", 20, 389_000, 0)]);

    [Fact]
    public void Totals_and_revision_after_sent()
    {
        var q = Quotation.Create(1, "BG2611-00001", Info()).Value;
        Assert.Equal(11_205_000 + 7_780_000, q.SubTotal);
        Assert.Equal(q.SubTotal - 50_000 + 30_000, q.TotalAmount);
        q.MarkSent(DateTime.UtcNow);
        Assert.True(q.Update(Info(0)).IsSuccess);
        Assert.Equal(1, q.RevisionNo);
    }

    [Fact]
    public void Expired_when_sent_and_past_valid_until()
    {
        var q = Quotation.Create(1, "BG", Info()).Value;
        Assert.False(q.IsExpired(new DateOnly(2026, 12, 5)));      // nháp chưa gửi thì không tính hết hạn
        q.MarkSent(DateTime.UtcNow);
        Assert.True(q.IsExpired(new DateOnly(2026, 12, 1)));
        Assert.False(q.IsExpired(new DateOnly(2026, 11, 30)));
    }

    [Fact]
    public void Accepted_quotation_is_locked_and_reject_needs_reason()
    {
        var q = Quotation.Create(1, "BG", Info()).Value;
        Assert.True(q.Reject(" ").IsFailure);
        Assert.True(q.Accept(DateTime.UtcNow).IsSuccess);
        Assert.True(q.Update(Info()).IsFailure);
        Assert.True(q.Cancel().IsFailure);
    }

    [Fact]
    public void Valid_until_before_quote_date_rejected()
        => Assert.Equal("quotation.valid_until", Quotation.Create(1, "BG", Info() with { ValidUntil = new DateOnly(2026, 11, 1) }).Error!.Code);
}

public class ShipmentTests
{
    private static readonly DateTime Now = new(2026, 11, 20, 3, 0, 0, DateTimeKind.Utc);

    private static Shipment New(decimal cod = 500_000) => Shipment.Create(1, "VD2611-00001", 9, 1,
        new ShipmentInfo(1, " ghn123 ", "Nhanh", "Lan", "0912 345 678", "Hà Nội", 1, 500, cod, 25_000, "sender", null), Now).Value;

    [Fact]
    public void Happy_path_collects_cod_on_delivery()
    {
        var s = New();
        Assert.Equal("GHN123", s.TrackingNo);
        Assert.Equal(CodStatuses.Pending, s.CodStatus);
        Assert.True(s.ChangeStatus(ShipmentStatuses.PickedUp, null, null, Now).IsSuccess);
        Assert.True(s.ChangeStatus(ShipmentStatuses.Delivered, null, null, Now).IsSuccess);
        Assert.Equal(CodStatuses.Collected, s.CodStatus);
        Assert.True(s.MarkCodReconciled().IsSuccess);
        Assert.True(s.MarkCodReconciled().IsFailure);              // không đối soát 2 lần
        Assert.Equal(3, s.Events.Count);
    }

    [Fact]
    public void Invalid_transition_and_failed_needs_reason()
    {
        var s = New();
        Assert.Equal("shipment.invalid_status", s.ChangeStatus(ShipmentStatuses.Delivered, null, null, Now).Error!.Code);
        s.ChangeStatus(ShipmentStatuses.PickedUp, null, null, Now);
        Assert.Equal("shipment.reason", s.ChangeStatus(ShipmentStatuses.Failed, " ", null, Now).Error!.Code);
        Assert.True(s.ChangeStatus(ShipmentStatuses.Failed, "Khách không nghe máy", null, Now).IsSuccess);
        Assert.True(s.ChangeStatus(ShipmentStatuses.Returning, null, null, Now).IsSuccess);
        Assert.True(s.ChangeStatus(ShipmentStatuses.Returned, null, null, Now).IsSuccess);
        Assert.Equal(CodStatuses.None, s.CodStatus);
    }

    [Fact]
    public void Cannot_edit_after_pickup_and_bad_phone_rejected()
    {
        var s = New(0);
        Assert.Equal(CodStatuses.None, s.CodStatus);
        s.ChangeStatus(ShipmentStatuses.PickedUp, null, null, Now);
        Assert.True(s.Update(new ShipmentInfo(1, null, null, "Lan", "0912345678", "HN", 1, null, 0, 0, "sender", null)).IsFailure);
        var bad = Shipment.Create(1, "VD", 1, 1, new ShipmentInfo(1, null, null, "Lan", "123", "HN", 1, null, 0, 0, "sender", null), Now);
        Assert.Equal("shipment.phone", bad.Error!.Code);
    }
}

public class TicketTests
{
    private static readonly DateTime Now = new(2026, 11, 20, 2, 0, 0, DateTimeKind.Utc);

    private static TicketInfo Info(string priority = "high") =>
        new("Áo bị lỗi đường may", "Khách muốn đổi size", 5, null, null, 9, 1, "zalo", priority, null);

    [Fact]
    public void Sla_due_dates_and_first_response()
    {
        var sla = (SlaPolicy)Activator.CreateInstance(typeof(SlaPolicy), true)!;
        typeof(SlaPolicy).GetProperty("FirstResponseMinutes")!.SetValue(sla, 60);
        typeof(SlaPolicy).GetProperty("ResolutionMinutes")!.SetValue(sla, 480);
        var t = Ticket.Create(1, "TK2611-00001", Info(), sla, Now).Value;
        Assert.Equal(Now.AddHours(8), t.ResolutionDueAt);
        Assert.True(t.IsOverdue(Now.AddHours(9)));

        Assert.True(t.AddMessage(1, "Ghi chú: kiểm tra kho", true, Now).IsSuccess);
        Assert.Null(t.FirstRespondedAt);                            // ghi chú nội bộ không tính phản hồi khách
        Assert.True(t.AddMessage(1, "Shop đổi cho chị size M nhé", false, Now.AddMinutes(5)).IsSuccess);
        Assert.Equal(Now.AddMinutes(5), t.FirstRespondedAt);
        Assert.Equal(TicketStatuses.Open, t.Status);
    }

    [Fact]
    public void Resolve_needs_resolution_then_rate()
    {
        var t = Ticket.Create(1, "TK", Info(), null, Now).Value;
        Assert.True(t.Rate(5, null).IsFailure);
        Assert.Equal("ticket.resolution", t.ChangeStatus(TicketStatuses.Resolved, null, Now).Error!.Code);
        Assert.True(t.ChangeStatus(TicketStatuses.Resolved, "Đã đổi size M", Now).IsSuccess);
        Assert.False(t.IsOverdue(Now.AddDays(10)));
        Assert.True(t.Rate(5, "Hài lòng").IsSuccess);
        Assert.True(t.Rate(6, null).IsFailure);
    }

    [Fact]
    public void Ticket_needs_customer_or_reporter()
        => Assert.Equal("ticket.reporter", Ticket.Create(1, "TK", Info() with { PartnerId = null }, null, Now).Error!.Code);
}

public class MoneyFlowTests
{
    private static SalesOrder ConfirmedOrder()
    {
        var o = SalesOrder.Create(1, "DH", new OrderInfo(5, DateTime.UtcNow, "shopee", 1, 2, null, null, null, 0, 0, null, null,
            [new OrderLineInfo(10, 1, "Áo", 2, 200_000, 0)])).Value;      // 400.000
        o.Confirm(new Dictionary<long, decimal>(), 1, DateTime.UtcNow);
        return o;
    }

    [Fact]
    public void Return_after_full_payment_requires_refund()
    {
        var o = ConfirmedOrder();
        o.RecordPayment(400_000, "cash");
        Assert.True(o.RegisterReturn(200_000, 200_000).IsSuccess);
        Assert.Equal(200_000, o.TotalAmount);
        Assert.Equal(200_000, o.AmountPaid);
        Assert.Equal("paid", o.PaymentStatus);
        Assert.Equal(200_000, o.ReturnedAmount);
    }

    [Fact]
    public void Reverse_payment_restores_due()
    {
        var o = ConfirmedOrder();
        o.RecordPayment(400_000, "cash");
        Assert.True(o.ReversePayment(150_000).IsSuccess);
        Assert.Equal("partial", o.PaymentStatus);
        Assert.Equal(150_000, o.AmountDue);
        Assert.True(o.ReversePayment(999_999).IsFailure);
    }

    [Fact]
    public void Purchase_payment_limits_and_cancel_guard()
    {
        var p = PurchaseOrder.Create(1, "DM", 1, new PurchaseInfo(3, new DateOnly(2026, 11, 1), null, 1, 0, null,
            [new PurchaseLineInfo(10, 1, null, 10, 100_000, 0)])).Value;
        Assert.True(p.RecordPayment(100_000).IsFailure);            // nháp chưa trả được
        p.Confirm(DateTime.UtcNow);
        Assert.True(p.RecordPayment(300_000).IsSuccess);            // trả trước 1 phần
        Assert.Equal(700_000, p.AmountDue);
        Assert.Equal("purchase.paid", p.Cancel().Error!.Code);
        Assert.True(p.RecordPayment(800_000).IsFailure);
    }

    [Fact]
    public void Voucher_requires_fund_reason_and_positive_amount()
    {
        var ok = CashVoucher.Create(1, "PT", new VoucherInfo(VoucherTypes.Receipt, "other_income", "cash", null, 2, null,
            new DateOnly(2026, 11, 20), 100_000, "Thu thanh lý kệ", null, null));
        Assert.True(ok.IsSuccess);
        Assert.Equal(100_000, ok.Value.SignedAmount);
        Assert.True(CashVoucher.Create(1, "PC", new VoucherInfo(VoucherTypes.Payment, "rent", "cash", null, null, null,
            new DateOnly(2026, 11, 20), 100_000, "Tiền nhà", null, null)).IsFailure);   // không có quỹ
        Assert.True(VoucherCategories.IsExpense("rent"));
        Assert.False(VoucherCategories.IsExpense(VoucherCategories.Supplier));
    }
}
