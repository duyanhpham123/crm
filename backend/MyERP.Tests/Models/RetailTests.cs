using MyERP.Api.Models.Entities.Inventory;
using MyERP.Api.Models.Entities.MasterData;
using MyERP.Api.Models.Entities.Purchasing;
using MyERP.Api.Models.Entities.Sales;

namespace MyERP.Tests.Models;

public class ProductVariantTests
{
    private static ProductModel Model(string code = "atb01") => ProductModel.Create(1, code,
        new ProductModelInfo(" Áo thun basic ", 2, 3, 1, 199000, 85000, "unisex", "Cotton", null, null));

    [Fact]
    public void Generates_sku_per_color_and_size()
    {
        var m = Model();
        var created = m.GenerateVariants(["Đen", "Xanh rêu", "đen"], ["m", "L"]);

        Assert.Equal(4, created.Count);                       // "đen" trùng "Đen" bị bỏ
        Assert.Equal("ATB01", m.Code);
        var v = created.Single(x => x.Color == "Xanh rêu" && x.Size == "M");
        Assert.Equal("ATB01-XANHREU-M", v.Code);
        Assert.Equal("Áo thun basic - Xanh rêu - M", v.Name);
        Assert.Equal(199000, v.SalePrice);
        Assert.Equal(2, v.CategoryId);
    }

    [Fact]
    public void Generating_again_only_adds_missing_variants()
    {
        var m = Model();
        m.GenerateVariants(["Đen"], ["M"]);
        var more = m.GenerateVariants(["Đen", "Trắng"], ["M"]);
        Assert.Single(more);
        Assert.Equal("ATB01-TRANG-M", more[0].Code);
    }

    [Fact]
    public void No_variants_gives_single_sku()
    {
        var m = Model("TUI01");
        var created = m.GenerateVariants([], []);
        Assert.Equal("TUI01", Assert.Single(created).Code);
    }

    [Fact]
    public void Renaming_model_renames_variants()
    {
        var m = Model();
        m.GenerateVariants(["Đen"], ["M"]);
        m.Update(new ProductModelInfo("Áo thun oversize", null, null, 1, 199000, 85000, null, null, null, null));
        Assert.Equal("Áo thun oversize - Đen - M", m.Variants[0].Name);
    }

    [Theory]
    [InlineData("Đỏ đô", "DODO")]
    [InlineData("Xanh navy đậm", "XANHNAVY")]
    [InlineData("Free size", "FREESIZE")]
    public void Code_part_strips_accents(string input, string expected) => Assert.Equal(expected, ProductModel.CodePart(input));
}

public class StockCostTests
{
    private static readonly DateTime Now = new(2026, 11, 21, 8, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void Weighted_average_cost_on_receipt()
    {
        var b = StockBalance.ForTest(10, 100_000);
        b.Receive(30, 120_000, Now);
        Assert.Equal(40, b.QtyOnHand);
        Assert.Equal(115_000, b.AvgCost);                     // (10×100k + 30×120k) / 40
    }

    [Fact]
    public void Receipt_into_empty_or_negative_stock_takes_new_cost()
    {
        var b = StockBalance.ForTest(-2, 90_000);
        b.Receive(5, 110_000, Now);
        Assert.Equal(110_000, b.AvgCost);
        Assert.Equal(3, b.QtyOnHand);
    }

    [Fact]
    public void Issue_keeps_average_cost()
    {
        var b = StockBalance.ForTest(10, 100_000);
        b.Issue(4, Now);
        Assert.Equal(6, b.QtyOnHand);
        Assert.Equal(100_000, b.AvgCost);
    }
}

public class SalesOrderTests
{
    private static OrderInfo Info(decimal discount = 20_000, decimal ship = 30_000) => new(5, DateTime.UtcNow, "shopee", 1, 2,
        "Lan", "0912 345 678", "Hà Nội", ship, discount, null, null,
        [new OrderLineInfo(10, 1, "Áo", 2, 199_000, 10), new OrderLineInfo(11, 1, "Quần", 1, 350_000, 0)]);

    [Fact]
    public void Totals_with_line_and_order_discount_and_shipping()
    {
        var o = SalesOrder.Create(1, "DH2611-00001", Info()).Value;

        Assert.Equal(358_200, o.Lines[0].LineTotal);           // 2 × 199k - 10%
        Assert.Equal(708_200, o.SubTotal);
        Assert.Equal(718_200, o.TotalAmount);                  // 708.2k - 20k + 30k ship
        Assert.Equal("0912345678", o.ReceiverPhone);
        Assert.Equal(OrderStatuses.Draft, o.Status);
    }

    [Fact]
    public void Discount_larger_than_subtotal_rejected()
        => Assert.Equal("order.discount_too_large", SalesOrder.Create(1, "DH", Info(discount: 999_999_999)).Error!.Code);

    [Fact]
    public void Order_without_lines_rejected()
        => Assert.True(SalesOrder.Create(1, "DH", Info() with { Lines = [] }).IsFailure);

    [Fact]
    public void Payment_flow_partial_then_paid_and_no_overpay()
    {
        var o = SalesOrder.Create(1, "DH", Info(0, 0)).Value;   // 708.200
        Assert.True(o.RecordPayment(500_000, "cash").IsSuccess);
        Assert.Equal("partial", o.PaymentStatus);
        Assert.Equal("order.payment_too_large", o.RecordPayment(300_000, "cash").Error!.Code);
        Assert.True(o.RecordPayment(208_200, "bank_transfer").IsSuccess);
        Assert.Equal("paid", o.PaymentStatus);
        Assert.Equal(0, o.AmountDue);
    }

    [Fact]
    public void Lifecycle_rules()
    {
        var o = SalesOrder.Create(1, "DH", Info()).Value;
        Assert.True(o.Complete().IsFailure);                    // chưa xác nhận
        Assert.True(o.Confirm(new Dictionary<long, decimal>(), 1, DateTime.UtcNow).IsSuccess);
        Assert.True(o.StockWasIssued);
        Assert.True(o.Update(Info()).IsFailure);                // đã xác nhận thì khóa sửa
        Assert.True(o.Complete().IsSuccess);
        Assert.Equal("order.completed", o.CanCancel().Error!.Code);
    }
}

public class PurchaseOrderTests
{
    [Fact]
    public void Landed_cost_allocates_other_cost_by_value()
    {
        var p = PurchaseOrder.Create(1, "DM", 1, new PurchaseInfo(3, new DateOnly(2026, 11, 1), null, 1, 100_000, null,
        [
            new PurchaseLineInfo(10, 1, null, 100, 80_000, 0),    // 8.000.000
            new PurchaseLineInfo(11, 1, null, 20, 100_000, 0)     // 2.000.000
        ])).Value;

        Assert.Equal(10_100_000, p.TotalAmount);
        // Id dòng chưa có (chưa lưu DB) nên cả 2 = 0: kiểm tra theo thứ tự dòng
        var lines = p.Lines;
        var share0 = 100_000m * lines[0].LineSubTotal / p.SubTotal;   // 80.000
        Assert.Equal(80_800, Math.Round((lines[0].LineSubTotal + share0) / lines[0].Quantity, 4));
    }

    [Fact]
    public void Cannot_receive_before_confirm_or_cancel_after_receive()
    {
        var p = PurchaseOrder.Create(1, "DM", 1, new PurchaseInfo(3, new DateOnly(2026, 11, 1), null, 1, 0, null,
            [new PurchaseLineInfo(10, 1, null, 5, 80_000, 0)])).Value;
        Assert.True(p.CanReceive().IsFailure);
        p.Confirm(DateTime.UtcNow);
        Assert.True(p.CanReceive().IsSuccess);
        p.MarkReceived();
        Assert.Equal(PurchaseStatuses.Completed, p.Status);
        Assert.True(p.Cancel().IsFailure);
    }
}
