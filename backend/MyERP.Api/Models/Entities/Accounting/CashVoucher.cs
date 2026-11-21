using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Accounting;

public static class VoucherTypes
{
    public const string Receipt = "receipt";   // phiếu thu / báo có
    public const string Payment = "payment";   // phiếu chi / báo nợ
}

/// <summary>Loại thu / chi. Thu tiền khách, trả NCC, COD, hoàn tiền do hệ thống gắn với chứng từ gốc.</summary>
public static class VoucherCategories
{
    public const string Customer = "customer";
    public const string Supplier = "supplier";
    public const string Cod = "cod";
    public const string Refund = "refund";
    public const string Shipping = "shipping";

    public static readonly IReadOnlyList<(string Code, string Type, string Name)> All =
    [
        (Customer, VoucherTypes.Receipt, "Thu tiền khách hàng"),
        (Cod, VoucherTypes.Receipt, "Thu tiền COD từ hãng vận chuyển"),
        ("other_income", VoucherTypes.Receipt, "Thu khác"),
        (Supplier, VoucherTypes.Payment, "Trả tiền nhà cung cấp"),
        (Refund, VoucherTypes.Payment, "Hoàn tiền khách hàng"),
        (Shipping, VoucherTypes.Payment, "Phí vận chuyển"),
        ("rent", VoucherTypes.Payment, "Thuê mặt bằng"),
        ("salary", VoucherTypes.Payment, "Lương nhân viên"),
        ("marketing", VoucherTypes.Payment, "Quảng cáo, marketing"),
        ("utilities", VoucherTypes.Payment, "Điện, nước, internet"),
        ("other_expense", VoucherTypes.Payment, "Chi khác"),
    ];

    /// <summary>Loại chi tính là chi phí hoạt động (báo cáo lãi lỗ). Trả NCC, hoàn tiền không phải chi phí.</summary>
    public static bool IsExpense(string? c) => c is Shipping or "rent" or "salary" or "marketing" or "utilities" or "other_expense";

    public static string NameOf(string? code) => All.FirstOrDefault(x => x.Code == code).Name ?? code ?? "";
}

public sealed record VoucherInfo(
    string Type, string Category, string Method, long? BankAccountId, long? CashAccountId, long? PartnerId,
    DateOnly Date, decimal Amount, string Reason, string? PersonName, string? Reference,
    long? SalesOrderId = null, long? PurchaseOrderId = null);

/// <summary>
/// Bảng acc.Payments - phiếu thu / chi (tiền mặt: PT / PC, ngân hàng: BC / BN). Ghi sổ ngay (posted).
/// Hủy phiếu = đánh dấu cancelled, không xóa (giữ dấu vết kiểm toán).
/// </summary>
public sealed class CashVoucher : AuditableEntity, ICompanyOwned
{
    private CashVoucher() { }

    public long CompanyId { get; private set; }
    public string DocNo { get; private set; } = "";
    public string PaymentType { get; private set; } = VoucherTypes.Receipt;
    public string PaymentMethodCode { get; private set; } = "cash";
    public long? PartnerId { get; private set; }
    public DateOnly PaymentDate { get; private set; }
    public decimal Amount { get; private set; }
    public long? BankAccountId { get; private set; }
    public long? CashAccountId { get; private set; }
    public string Reason { get; private set; } = "";
    public string? PersonName { get; private set; }
    public string? BankReference { get; private set; }
    public string Status { get; private set; } = "posted";
    public string? Category { get; private set; }
    public long? SalesOrderId { get; private set; }
    public long? PurchaseOrderId { get; private set; }

    public bool IsCash => BankAccountId is null;
    /// <summary>Dương = tiền vào quỹ, âm = tiền ra.</summary>
    public decimal SignedAmount => PaymentType == VoucherTypes.Receipt ? Amount : -Amount;

    public static Result<CashVoucher> Create(long companyId, string docNo, VoucherInfo i)
    {
        if (i.Amount <= 0) return Error.Validation("voucher.amount", "Số tiền phải lớn hơn 0.");
        if (string.IsNullOrWhiteSpace(i.Reason)) return Error.Validation("voucher.reason", "Nhập nội dung thu / chi.");
        if (i.BankAccountId is null && i.CashAccountId is null) return Error.Validation("voucher.fund", "Chọn quỹ tiền mặt hoặc tài khoản ngân hàng.");
        return new CashVoucher
        {
            CompanyId = companyId, DocNo = docNo, PaymentType = i.Type, Category = i.Category, PaymentMethodCode = i.Method,
            BankAccountId = i.BankAccountId, CashAccountId = i.BankAccountId is null ? i.CashAccountId : null,
            PartnerId = i.PartnerId, PaymentDate = i.Date, Amount = Math.Round(i.Amount, 0), Reason = i.Reason.Trim(),
            PersonName = Clean(i.PersonName), BankReference = Clean(i.Reference),
            SalesOrderId = i.SalesOrderId, PurchaseOrderId = i.PurchaseOrderId,
        };
    }

    public Result Cancel()
    {
        if (Status == "cancelled") return Error.Conflict("voucher.cancelled", "Phiếu đã hủy.");
        Status = "cancelled";
        return Result.Success();
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

/// <summary>Bảng acc.BankAccounts - tài khoản ngân hàng của công ty.</summary>
public sealed class BankAccount : Entity, ICompanyOwned
{
    private BankAccount() { }
    public long CompanyId { get; private set; }
    public long AccountId { get; private set; }
    public string BankName { get; private set; } = "";
    public string? BankBranch { get; private set; }
    public string AccountNo { get; private set; } = "";
    public string AccountName { get; private set; } = "";
    public bool IsActive { get; private set; } = true;

    public static BankAccount Create(long companyId, long ledgerAccountId, string bank, string? branch, string no, string name)
        => new() { CompanyId = companyId, AccountId = ledgerAccountId, BankName = bank.Trim(), BankBranch = branch?.Trim(), AccountNo = no.Trim(), AccountName = name.Trim() };

    public void Update(string bank, string? branch, string no, string name, bool active)
    {
        BankName = bank.Trim(); BankBranch = branch?.Trim(); AccountNo = no.Trim(); AccountName = name.Trim(); IsActive = active;
    }
}

/// <summary>Bảng acc.Accounts (hệ thống tài khoản) - chỉ đọc mã / tên để chọn TK tiền mặt, tiền gửi.</summary>
public sealed class LedgerAccount : Entity, ICompanyOwned
{
    private LedgerAccount() { }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
}
