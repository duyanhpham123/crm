using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Accounting;
using MyERP.Api.Models.Entities.Purchasing;
using MyERP.Api.Models.Entities.Sales;
using MyERP.Api.Services.Common;
using MyERP.Api.Services.Sales;

namespace MyERP.Api.Services.Accounting;

/// <summary>Thông tin để tạo 1 phiếu thu / chi từ nghiệp vụ khác (thu tiền đơn, COD, hoàn tiền...).</summary>
public sealed record VoucherSpec(string Type, string Category, string Method, long? BankAccountId, long? PartnerId, DateOnly Date,
    decimal Amount, string Reason, string? PersonName = null, string? Reference = null, long? SalesOrderId = null, long? PurchaseOrderId = null);

public interface ICashService
{
    Task<AccountingLookups> GetLookupsAsync(CancellationToken ct);
    Task<VoucherPage> ListAsync(VoucherQuery query, CancellationToken ct);
    Task<Result<CreateVoucherResult>> CreateAsync(CreateVoucherRequest request, CancellationToken ct);
    Task<Result<VoucherListItem>> CancelAsync(long id, CancellationToken ct);
    Task<Result<CashBook>> CashBookAsync(string fund, DateOnly? from, DateOnly? to, CancellationToken ct);
    Task<DebtPage> ReceivablesAsync(string? search, int page, int pageSize, CancellationToken ct);
    Task<DebtPage> PayablesAsync(string? search, int page, int pageSize, CancellationToken ct);
    Task<IReadOnlyList<DebtDocument>> CustomerDocumentsAsync(long partnerId, CancellationToken ct);
    Task<IReadOnlyList<DebtDocument>> SupplierDocumentsAsync(long partnerId, CancellationToken ct);
    Task<IReadOnlyList<PartnerOption>> PartnersAsync(string kind, string? search, CancellationToken ct);
    Task<AccountingOverview> OverviewAsync(DateOnly? from, DateOnly? to, CancellationToken ct);
    Task<Result<BankAccountDto>> SaveBankAccountAsync(long? id, SaveBankAccountRequest request, CancellationToken ct);

    /// <summary>Thêm phiếu vào DbContext (chưa SaveChanges) - dùng trong transaction của nghiệp vụ gọi tới.</summary>
    Task<Result<CashVoucher>> AddVoucherAsync(VoucherSpec spec, CancellationToken ct);
}

/// <summary>
/// Kế toán tiền: phiếu thu / chi, sổ quỹ tiền mặt &amp; ngân hàng, công nợ khách hàng / nhà cung cấp, lãi lỗ.
/// Mọi khoản tiền ra vào (thu tiền đơn, COD, hoàn tiền, trả NCC) đều đi qua đây nên sổ quỹ luôn khớp.
/// </summary>
public sealed class CashService(AppDbContext db, ICurrentUser currentUser, IDocumentNumberService docNumbers, TimeProvider clock) : ICashService
{
    public const string CashFund = "cash";

    private DateOnly Today => DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime.AddHours(7));

    public async Task<AccountingLookups> GetLookupsAsync(CancellationToken ct)
    {
        var balances = await FundBalancesAsync(ct);
        var banks = await db.BankAccounts.OrderBy(b => b.Id).ToListAsync(ct);
        return new AccountingLookups(
            banks.Select(b => new BankAccountDto(b.Id, b.BankName, b.BankBranch, b.AccountNo, b.AccountName, b.IsActive,
                balances.FirstOrDefault(f => f.Key == b.Id.ToString())?.Balance ?? 0)).ToList(),
            VoucherCategories.All.Select(c => new VoucherCategoryDto(c.Code, c.Type, c.Name)).ToList(),
            OrderService.PaymentMethods.Where(m => m.Code != "cod").ToList());
    }

    // ---------- Phiếu thu / chi ----------

    public async Task<VoucherPage> ListAsync(VoucherQuery q, CancellationToken ct)
    {
        var page = Math.Max(1, q.Page);
        var size = Math.Clamp(q.PageSize, 1, 100);
        var query = db.CashVouchers.AsNoTracking().AsQueryable();
        if (!string.IsNullOrEmpty(q.Type)) query = query.Where(v => v.PaymentType == q.Type);
        if (!string.IsNullOrEmpty(q.Category)) query = query.Where(v => v.Category == q.Category);
        if (q.Fund == CashFund) query = query.Where(v => v.BankAccountId == null);
        else if (long.TryParse(q.Fund, out var bankId)) query = query.Where(v => v.BankAccountId == bankId);
        if (q.From is { } f) query = query.Where(v => v.PaymentDate >= f);
        if (q.To is { } t) query = query.Where(v => v.PaymentDate <= t);
        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var s = q.Search.Trim();
            query = query.Where(v => v.DocNo.Contains(s) || v.Reason.Contains(s) || (v.PersonName != null && v.PersonName.Contains(s))
                || db.Partners.Any(p => p.Id == v.PartnerId && (p.Name.Contains(s) || (p.Phone != null && p.Phone.Contains(s)))));
        }

        var posted = query.Where(v => v.Status == "posted");
        var receipt = await posted.Where(v => v.PaymentType == VoucherTypes.Receipt).SumAsync(v => (decimal?)v.Amount, ct) ?? 0;
        var payment = await posted.Where(v => v.PaymentType == VoucherTypes.Payment).SumAsync(v => (decimal?)v.Amount, ct) ?? 0;
        var total = await query.CountAsync(ct);
        var items = await query.OrderByDescending(v => v.PaymentDate).ThenByDescending(v => v.Id)
            .Skip((page - 1) * size).Take(size).ToListAsync(ct);
        return new VoucherPage(new PagedResult<VoucherListItem>(await ToItemsAsync(items, ct), page, size, total),
            new VoucherSummary(receipt, payment, receipt - payment));
    }

    public async Task<Result<CreateVoucherResult>> CreateAsync(CreateVoucherRequest r, CancellationToken ct)
    {
        var cat = VoucherCategories.All.FirstOrDefault(c => c.Code == r.Category);
        if (cat.Code is null || cat.Type != r.Type) return Error.Validation("voucher.category", "Loại thu / chi không hợp lệ.");
        if (r.Category is VoucherCategories.Cod or VoucherCategories.Refund)
            return Error.Validation("voucher.system_category", "Phiếu COD / hoàn tiền được tạo tự động từ Vận chuyển và Trả hàng.");
        var method = r.Method ?? (r.BankAccountId is null ? "cash" : "bank_transfer");
        if (method == "cash" && r.BankAccountId is not null) return Error.Validation("voucher.method", "Tiền mặt thì không chọn tài khoản ngân hàng.");
        if (r.Amount <= 0) return Error.Validation("voucher.amount", "Số tiền phải lớn hơn 0.");

        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var created = new List<CashVoucher>();
            Result<CashVoucher> Add(CashVoucher v) { created.Add(v); return v; }

            if (r.Category == VoucherCategories.Customer)
            {
                var orders = await CustomerOpenOrdersAsync(r.PartnerId, r.SalesOrderId, ct);
                if (orders.IsFailure) return (Result<CreateVoucherResult>)orders.Error!;
                var due = orders.Value.Sum(o => o.AmountDue);
                if (r.Amount > due) return Error.Validation("voucher.over_due", $"Số tiền lớn hơn công nợ còn phải thu ({due:N0} đ).");
                var left = r.Amount;
                foreach (var o in orders.Value)
                {
                    if (left <= 0) break;
                    var part = Math.Min(left, o.AmountDue);
                    var pay = o.RecordPayment(part, method);
                    if (pay.IsFailure) return (Result<CreateVoucherResult>)pay.Error!;
                    var v = await AddVoucherAsync(new VoucherSpec(r.Type, r.Category, method, r.BankAccountId, o.PartnerId, r.Date, part,
                        orders.Value.Count > 1 || r.SalesOrderId is null ? $"{r.Reason.Trim()} - đơn {o.DocNo}" : r.Reason, r.PersonName, r.Reference, SalesOrderId: o.Id), ct);
                    if (v.IsFailure) return (Result<CreateVoucherResult>)v.Error!;
                    Add(v.Value);
                    left -= part;
                }
            }
            else if (r.Category == VoucherCategories.Supplier)
            {
                var pos = await SupplierOpenOrdersAsync(r.PartnerId, r.PurchaseOrderId, ct);
                if (pos.IsFailure) return (Result<CreateVoucherResult>)pos.Error!;
                var due = pos.Value.Sum(o => o.AmountDue);
                if (r.Amount > due) return Error.Validation("voucher.over_due", $"Số tiền lớn hơn công nợ còn phải trả ({due:N0} đ).");
                var left = r.Amount;
                foreach (var o in pos.Value)
                {
                    if (left <= 0) break;
                    var part = Math.Min(left, o.AmountDue);
                    var pay = o.RecordPayment(part);
                    if (pay.IsFailure) return (Result<CreateVoucherResult>)pay.Error!;
                    var v = await AddVoucherAsync(new VoucherSpec(r.Type, r.Category, method, r.BankAccountId, o.PartnerId, r.Date, part,
                        pos.Value.Count > 1 || r.PurchaseOrderId is null ? $"{r.Reason.Trim()} - đơn nhập {o.DocNo}" : r.Reason, r.PersonName, r.Reference, PurchaseOrderId: o.Id), ct);
                    if (v.IsFailure) return (Result<CreateVoucherResult>)v.Error!;
                    Add(v.Value);
                    left -= part;
                }
            }
            else
            {
                if (r.PartnerId is { } pid && !await db.Partners.AnyAsync(p => p.Id == pid, ct))
                    return Error.Validation("voucher.partner", "Đối tượng không tồn tại.");
                var v = await AddVoucherAsync(new VoucherSpec(r.Type, r.Category, method, r.BankAccountId, r.PartnerId, r.Date, r.Amount,
                    r.Reason, r.PersonName, r.Reference), ct);
                if (v.IsFailure) return (Result<CreateVoucherResult>)v.Error!;
                Add(v.Value);
            }

            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<CreateVoucherResult>)new CreateVoucherResult(await ToItemsAsync(created, ct));
        });
    }

    public async Task<Result<VoucherListItem>> CancelAsync(long id, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            var v = await db.CashVouchers.FirstOrDefaultAsync(x => x.Id == id, ct);
            if (v is null) return (Result<VoucherListItem>)Error.NotFound("phiếu thu chi");
            if (v.Category is VoucherCategories.Cod or VoucherCategories.Refund)
                return Error.Conflict("voucher.system", "Phiếu COD / hoàn tiền do hệ thống tạo, không hủy được ở đây.");

            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var r = v.Cancel();
            if (r.IsFailure) return (Result<VoucherListItem>)r.Error!;
            if (v.SalesOrderId is { } oid && v.Category == VoucherCategories.Customer)
            {
                var o = await db.SalesOrders.FirstAsync(x => x.Id == oid, ct);
                var rev = o.ReversePayment(v.Amount);
                if (rev.IsFailure) return (Result<VoucherListItem>)rev.Error!;
            }
            if (v.PurchaseOrderId is { } pid)
            {
                var p = await db.PurchaseOrders.FirstAsync(x => x.Id == pid, ct);
                var rev = p.ReversePayment(v.Amount);
                if (rev.IsFailure) return (Result<VoucherListItem>)rev.Error!;
            }
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (Result<VoucherListItem>)(await ToItemsAsync([v], ct))[0];
        });
    }

    public async Task<Result<CashVoucher>> AddVoucherAsync(VoucherSpec s, CancellationToken ct)
    {
        long? bankId = null, cashAccountId = null;
        if (s.Method == "cash") cashAccountId = await CashAccountIdAsync(ct);
        else
        {
            bankId = s.BankAccountId ?? await db.BankAccounts.Where(b => b.IsActive).OrderBy(b => b.Id).Select(b => (long?)b.Id).FirstOrDefaultAsync(ct);
            if (bankId is null) return Error.Validation("voucher.no_bank", "Chưa có tài khoản ngân hàng. Thêm ở Kế toán > Tài khoản ngân hàng.");
            if (s.BankAccountId is { } given && !await db.BankAccounts.AnyAsync(b => b.Id == given, ct))
                return Error.Validation("voucher.bank", "Tài khoản ngân hàng không hợp lệ.");
        }
        var seq = (s.Type, bankId is null) switch
        {
            (VoucherTypes.Receipt, true) => "CASH_RECEIPT",
            (VoucherTypes.Receipt, false) => "BANK_RECEIPT",
            (_, true) => "CASH_PAYMENT",
            _ => "BANK_PAYMENT",
        };
        var v = CashVoucher.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync(seq, s.Date, ct),
            new VoucherInfo(s.Type, s.Category, s.Method, bankId, cashAccountId, s.PartnerId, s.Date, s.Amount, s.Reason, s.PersonName,
                s.Reference, s.SalesOrderId, s.PurchaseOrderId));
        if (v.IsFailure) return v.Error!;
        db.CashVouchers.Add(v.Value);
        return v.Value;
    }

    // ---------- Sổ quỹ ----------

    public async Task<Result<CashBook>> CashBookAsync(string fund, DateOnly? from, DateOnly? to, CancellationToken ct)
    {
        var f = from ?? Today.AddDays(1 - Today.Day);
        var t = to ?? Today;
        IQueryable<CashVoucher> q = db.CashVouchers.AsNoTracking().Where(v => v.Status == "posted");
        string name;
        if (fund == CashFund) { q = q.Where(v => v.BankAccountId == null); name = "Quỹ tiền mặt"; }
        else if (long.TryParse(fund, out var bankId) && await db.BankAccounts.FirstOrDefaultAsync(b => b.Id == bankId, ct) is { } bank)
        {
            q = q.Where(v => v.BankAccountId == bankId);
            name = $"{bank.BankName} - {bank.AccountNo}";
        }
        else return Error.Validation("cashbook.fund", "Quỹ không hợp lệ.");

        var opening = await q.Where(v => v.PaymentDate < f)
            .SumAsync(v => (decimal?)(v.PaymentType == VoucherTypes.Receipt ? v.Amount : -v.Amount), ct) ?? 0;
        var rows = await q.Where(v => v.PaymentDate >= f && v.PaymentDate <= t).OrderBy(v => v.PaymentDate).ThenBy(v => v.Id).ToListAsync(ct);
        var names = await PartnerNamesAsync(rows.Select(r => r.PartnerId), ct);
        var balance = opening;
        var list = new List<CashBookRow>(rows.Count);
        foreach (var v in rows)
        {
            balance += v.SignedAmount;
            list.Add(new CashBookRow(v.Id, v.PaymentDate, v.DocNo, v.Reason, v.PartnerId is { } p ? names.GetValueOrDefault(p) : v.PersonName,
                v.PaymentType == VoucherTypes.Receipt ? v.Amount : 0, v.PaymentType == VoucherTypes.Payment ? v.Amount : 0, balance));
        }
        return new CashBook(fund, name, f, t, opening, list.Sum(x => x.In), list.Sum(x => x.Out), balance, list, await FundBalancesAsync(ct));
    }

    private async Task<IReadOnlyList<FundBalance>> FundBalancesAsync(CancellationToken ct)
    {
        var sums = await db.CashVouchers.AsNoTracking().Where(v => v.Status == "posted")
            .GroupBy(v => v.BankAccountId)
            .Select(g => new { g.Key, Balance = g.Sum(v => v.PaymentType == VoucherTypes.Receipt ? v.Amount : -v.Amount) })
            .ToListAsync(ct);
        var banks = await db.BankAccounts.AsNoTracking().OrderBy(b => b.Id).ToListAsync(ct);
        var list = new List<FundBalance> { new(CashFund, "Tiền mặt", sums.FirstOrDefault(s => s.Key == null)?.Balance ?? 0) };
        list.AddRange(banks.Select(b => new FundBalance(b.Id.ToString(), $"{b.BankName} - {b.AccountNo}", sums.FirstOrDefault(s => s.Key == b.Id)?.Balance ?? 0)));
        return list;
    }

    // ---------- Công nợ ----------

    private IQueryable<SalesOrder> OpenCustomerOrders()
        => db.SalesOrders.Where(o => (o.Status == OrderStatuses.Confirmed || o.Status == OrderStatuses.Completed) && o.TotalAmount - o.AmountPaid > 0);

    private IQueryable<PurchaseOrder> OpenSupplierOrders()
        => db.PurchaseOrders.Where(o => o.Status == PurchaseStatuses.Completed && o.TotalAmount - o.AmountPaid > 0);

    public async Task<DebtPage> ReceivablesAsync(string? search, int page, int pageSize, CancellationToken ct)
    {
        var grouped = OpenCustomerOrders().GroupBy(o => o.PartnerId).Select(g => new
        {
            PartnerId = g.Key, Count = g.Count(), Total = g.Sum(o => o.TotalAmount), Paid = g.Sum(o => o.AmountPaid), Oldest = g.Min(o => o.OrderDate),
        });
        var rows = await grouped.ToListAsync(ct);
        return await ToDebtPageAsync(rows.Select(r => (r.PartnerId, r.Count, r.Total, r.Paid, (DateOnly?)DateOnly.FromDateTime(r.Oldest.AddHours(7)))).ToList(),
            search, page, pageSize, ct);
    }

    public async Task<DebtPage> PayablesAsync(string? search, int page, int pageSize, CancellationToken ct)
    {
        var rows = await OpenSupplierOrders().GroupBy(o => o.PartnerId).Select(g => new
        {
            PartnerId = g.Key, Count = g.Count(), Total = g.Sum(o => o.TotalAmount), Paid = g.Sum(o => o.AmountPaid), Oldest = g.Min(o => o.OrderDate),
        }).ToListAsync(ct);
        return await ToDebtPageAsync(rows.Select(r => (r.PartnerId, r.Count, r.Total, r.Paid, (DateOnly?)r.Oldest)).ToList(), search, page, pageSize, ct);
    }

    private async Task<DebtPage> ToDebtPageAsync(List<(long PartnerId, int Count, decimal Total, decimal Paid, DateOnly? Oldest)> rows,
        string? search, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var ids = rows.Select(r => r.PartnerId).ToList();
        var partners = await db.Partners.IgnoreQueryFilters().Where(p => ids.Contains(p.Id))
            .Select(p => new { p.Id, p.Code, p.Name, p.Phone }).ToDictionaryAsync(p => p.Id, ct);
        var list = rows.Select(r => new DebtRow(r.PartnerId, partners[r.PartnerId].Code, partners[r.PartnerId].Name, partners[r.PartnerId].Phone,
            r.Count, r.Total, r.Paid, r.Total - r.Paid, r.Oldest)).ToList();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = TextSearch.Fold(search);
            list = list.Where(r => TextSearch.Fold(r.Name).Contains(s) || r.Code.Contains(search.Trim(), StringComparison.OrdinalIgnoreCase)
                || (r.Phone ?? "").Contains(search.Trim())).ToList();
        }
        var ordered = list.OrderByDescending(r => r.Due).ToList();
        return new DebtPage(new PagedResult<DebtRow>(ordered.Skip((page - 1) * pageSize).Take(pageSize).ToList(), page, pageSize, ordered.Count),
            ordered.Sum(r => r.Due), ordered.Count);
    }

    public async Task<IReadOnlyList<DebtDocument>> CustomerDocumentsAsync(long partnerId, CancellationToken ct)
        => (await OpenCustomerOrders().Where(o => o.PartnerId == partnerId).OrderBy(o => o.OrderDate).AsNoTracking().ToListAsync(ct))
            .Select(o => new DebtDocument(o.Id, o.DocNo, DateOnly.FromDateTime(o.OrderDate.AddHours(7)), o.TotalAmount, o.AmountPaid, o.AmountDue)).ToList();

    public async Task<IReadOnlyList<DebtDocument>> SupplierDocumentsAsync(long partnerId, CancellationToken ct)
        => (await db.PurchaseOrders.Where(o => o.PartnerId == partnerId && (o.Status == PurchaseStatuses.Confirmed || o.Status == PurchaseStatuses.Completed)
                && o.TotalAmount - o.AmountPaid > 0).OrderBy(o => o.OrderDate).AsNoTracking().ToListAsync(ct))
            .Select(o => new DebtDocument(o.Id, o.DocNo, o.OrderDate, o.TotalAmount, o.AmountPaid, o.AmountDue)).ToList();

    public async Task<IReadOnlyList<PartnerOption>> PartnersAsync(string kind, string? search, CancellationToken ct)
    {
        var q = db.Partners.AsNoTracking().Where(p => kind == "supplier" ? p.IsSupplier : p.IsCustomer);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            q = q.Where(p => p.Name.Contains(s) || p.Code.Contains(s) || (p.Phone != null && p.Phone.Contains(s)));
        }
        var partners = await q.OrderBy(p => p.Name).Take(15).Select(p => new { p.Id, p.Code, p.Name, p.Phone }).ToListAsync(ct);
        var ids = partners.Select(p => p.Id).ToList();
        var dues = kind == "supplier"
            ? await OpenSupplierOrders().Where(o => ids.Contains(o.PartnerId)).GroupBy(o => o.PartnerId).Select(g => new { g.Key, Due = g.Sum(o => o.TotalAmount - o.AmountPaid) }).ToDictionaryAsync(x => x.Key, x => x.Due, ct)
            : await OpenCustomerOrders().Where(o => ids.Contains(o.PartnerId)).GroupBy(o => o.PartnerId).Select(g => new { g.Key, Due = g.Sum(o => o.TotalAmount - o.AmountPaid) }).ToDictionaryAsync(x => x.Key, x => x.Due, ct);
        return partners.Select(p => new PartnerOption(p.Id, p.Code, p.Name, p.Phone, dues.GetValueOrDefault(p.Id))).ToList();
    }

    private async Task<Result<List<SalesOrder>>> CustomerOpenOrdersAsync(long? partnerId, long? orderId, CancellationToken ct)
    {
        if (orderId is { } oid)
        {
            var o = await db.SalesOrders.FirstOrDefaultAsync(x => x.Id == oid, ct);
            if (o is null) return Error.NotFound("đơn hàng");
            if (partnerId is { } p && o.PartnerId != p) return Error.Validation("voucher.order_partner", "Đơn hàng không thuộc khách hàng đã chọn.");
            if (o.Status is not (OrderStatuses.Confirmed or OrderStatuses.Completed)) return Error.Validation("voucher.order_status", "Chỉ thu tiền cho đơn đã xác nhận.");
            return new List<SalesOrder> { o };
        }
        if (partnerId is null) return Error.Validation("voucher.partner_required", "Chọn khách hàng cần thu tiền.");
        var list = await OpenCustomerOrders().Where(o => o.PartnerId == partnerId).OrderBy(o => o.OrderDate).ThenBy(o => o.Id).ToListAsync(ct);
        if (list.Count == 0) return Error.Validation("voucher.no_debt", "Khách hàng này không còn nợ đơn nào.");
        return list;
    }

    private async Task<Result<List<PurchaseOrder>>> SupplierOpenOrdersAsync(long? partnerId, long? orderId, CancellationToken ct)
    {
        if (orderId is { } oid)
        {
            var o = await db.PurchaseOrders.FirstOrDefaultAsync(x => x.Id == oid, ct);
            if (o is null) return Error.NotFound("đơn nhập");
            if (partnerId is { } p && o.PartnerId != p) return Error.Validation("voucher.order_partner", "Đơn nhập không thuộc nhà cung cấp đã chọn.");
            return new List<PurchaseOrder> { o };
        }
        if (partnerId is null) return Error.Validation("voucher.partner_required", "Chọn nhà cung cấp cần trả tiền.");
        var list = await OpenSupplierOrders().Where(o => o.PartnerId == partnerId).OrderBy(o => o.OrderDate).ThenBy(o => o.Id).ToListAsync(ct);
        if (list.Count == 0) return Error.Validation("voucher.no_debt", "Không còn nợ nhà cung cấp này (chỉ tính đơn đã nhận hàng).");
        return list;
    }

    // ---------- Lãi lỗ tổng quan ----------

    public async Task<AccountingOverview> OverviewAsync(DateOnly? from, DateOnly? to, CancellationToken ct)
    {
        var f = from ?? Today.AddDays(1 - Today.Day);
        var t = to ?? Today;
        var fu = OrderService.LocalDayStartUtc(f);
        var tu = OrderService.LocalDayStartUtc(t.AddDays(1));

        var orders = db.SalesOrders.AsNoTracking().Where(o => (o.Status == OrderStatuses.Confirmed || o.Status == OrderStatuses.Completed)
            && o.OrderDate >= fu && o.OrderDate < tu);
        var revenue = await orders.SumAsync(o => (decimal?)(o.SubTotal - o.DiscountAmount), ct) ?? 0;
        var cogs = await db.SalesOrderLines.AsNoTracking().Where(l => orders.Any(o => o.Id == l.SalesOrderId))
            .SumAsync(l => (decimal?)(l.Quantity * l.UnitCost), ct) ?? 0;

        var returns = db.SalesReturns.AsNoTracking().Where(r => r.ReturnDate >= fu && r.ReturnDate < tu);
        var returnValue = await returns.SumAsync(r => (decimal?)r.TotalAmount, ct) ?? 0;
        var returnedCost = await (from rl in db.SalesReturnLines.AsNoTracking()
                                  join ol in db.SalesOrderLines.AsNoTracking() on rl.SalesOrderLineId equals ol.Id
                                  where returns.Any(r => r.Id == rl.SalesReturnId)
                                  select (decimal?)(rl.Quantity * ol.UnitCost)).SumAsync(ct) ?? 0;

        var vouchers = db.CashVouchers.AsNoTracking().Where(v => v.Status == "posted" && v.PaymentDate >= f && v.PaymentDate <= t);
        var byCat = await vouchers.Where(v => v.PaymentType == VoucherTypes.Payment).GroupBy(v => v.Category)
            .Select(g => new { g.Key, Total = g.Sum(v => v.Amount), Count = g.Count() }).ToListAsync(ct);
        var expenses = byCat.Where(c => VoucherCategories.IsExpense(c.Key))
            .Select(c => new NamedValue(VoucherCategories.NameOf(c.Key), c.Total, c.Count)).OrderByDescending(x => x.Value).ToList();
        var cashIn = await vouchers.Where(v => v.PaymentType == VoucherTypes.Receipt).SumAsync(v => (decimal?)v.Amount, ct) ?? 0;
        var cashOut = await vouchers.Where(v => v.PaymentType == VoucherTypes.Payment).SumAsync(v => (decimal?)v.Amount, ct) ?? 0;

        var netRevenue = revenue - returnValue;
        var gross = netRevenue - (cogs - returnedCost);
        var totalExpense = expenses.Sum(e => e.Value);
        var receivable = await OpenCustomerOrders().SumAsync(o => (decimal?)(o.TotalAmount - o.AmountPaid), ct) ?? 0;
        var payable = await OpenSupplierOrders().SumAsync(o => (decimal?)(o.TotalAmount - o.AmountPaid), ct) ?? 0;
        return new AccountingOverview(f, t, revenue, returnValue, netRevenue, cogs - returnedCost, gross, expenses, totalExpense,
            gross - totalExpense, cashIn, cashOut, await FundBalancesAsync(ct), receivable, payable);
    }

    // ---------- Tài khoản ngân hàng ----------

    public async Task<Result<BankAccountDto>> SaveBankAccountAsync(long? id, SaveBankAccountRequest r, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(r.BankName) || string.IsNullOrWhiteSpace(r.AccountNo) || string.IsNullOrWhiteSpace(r.AccountName))
            return Error.Validation("bank.required", "Nhập tên ngân hàng, số tài khoản và tên chủ tài khoản.");
        if (await db.BankAccounts.AnyAsync(b => b.AccountNo == r.AccountNo.Trim() && b.Id != id, ct))
            return Error.Conflict("bank.duplicate", "Số tài khoản đã có.");
        BankAccount b;
        if (id is { } existing)
        {
            var found = await db.BankAccounts.FirstOrDefaultAsync(x => x.Id == existing, ct);
            if (found is null) return Error.NotFound("tài khoản ngân hàng");
            b = found;
            b.Update(r.BankName, r.BankBranch, r.AccountNo, r.AccountName, r.IsActive);
        }
        else
        {
            var ledger = await db.LedgerAccounts.Where(a => a.Code == "1121").Select(a => (long?)a.Id).FirstOrDefaultAsync(ct);
            if (ledger is null) return Error.Validation("bank.no_ledger", "Chưa có tài khoản kế toán 1121.");
            b = BankAccount.Create(currentUser.RequireCompanyId(), ledger.Value, r.BankName, r.BankBranch, r.AccountNo, r.AccountName);
            db.BankAccounts.Add(b);
        }
        await db.SaveChangesAsync(ct);
        var balance = (await FundBalancesAsync(ct)).FirstOrDefault(f => f.Key == b.Id.ToString())?.Balance ?? 0;
        return new BankAccountDto(b.Id, b.BankName, b.BankBranch, b.AccountNo, b.AccountName, b.IsActive, balance);
    }

    // ---------- Hỗ trợ ----------

    private async Task<long> CashAccountIdAsync(CancellationToken ct)
        => await db.LedgerAccounts.Where(a => a.Code == "1111").Select(a => a.Id).FirstAsync(ct);

    private async Task<Dictionary<long, string>> PartnerNamesAsync(IEnumerable<long?> ids, CancellationToken ct)
    {
        var list = ids.Where(i => i is not null).Select(i => i!.Value).Distinct().ToList();
        return await db.Partners.IgnoreQueryFilters().Where(p => list.Contains(p.Id)).ToDictionaryAsync(p => p.Id, p => p.Name, ct);
    }

    private async Task<List<VoucherListItem>> ToItemsAsync(IReadOnlyList<CashVoucher> items, CancellationToken ct)
    {
        var names = await PartnerNamesAsync(items.Select(i => i.PartnerId), ct);
        var orderIds = items.Where(i => i.SalesOrderId != null).Select(i => i.SalesOrderId!.Value).Distinct().ToList();
        var poIds = items.Where(i => i.PurchaseOrderId != null).Select(i => i.PurchaseOrderId!.Value).Distinct().ToList();
        var orders = await db.SalesOrders.IgnoreQueryFilters().Where(o => orderIds.Contains(o.Id)).ToDictionaryAsync(o => o.Id, o => o.DocNo, ct);
        var pos = await db.PurchaseOrders.IgnoreQueryFilters().Where(o => poIds.Contains(o.Id)).ToDictionaryAsync(o => o.Id, o => o.DocNo, ct);
        var banks = await db.BankAccounts.AsNoTracking().ToDictionaryAsync(b => b.Id, b => b.BankName, ct);
        return items.Select(v => new VoucherListItem(v.Id, v.DocNo, v.PaymentType, v.Category, VoucherCategories.NameOf(v.Category), v.PaymentDate,
            v.Amount, v.BankAccountId is { } b ? banks.GetValueOrDefault(b, "Ngân hàng") : "Tiền mặt", v.PartnerId,
            v.PartnerId is { } p ? names.GetValueOrDefault(p) : null, v.PersonName, v.Reason,
            v.SalesOrderId is not null ? "order" : v.PurchaseOrderId is not null ? "purchase" : null,
            v.SalesOrderId ?? v.PurchaseOrderId,
            v.SalesOrderId is { } o ? orders.GetValueOrDefault(o) : v.PurchaseOrderId is { } po ? pos.GetValueOrDefault(po) : null,
            v.Status)).ToList();
    }
}
