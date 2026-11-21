using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Core;
using MyERP.Api.Models.Entities.Inventory;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Settings;

public interface ISettingsService
{
    Task<CompanyInfoDto> GetCompanyAsync(CancellationToken ct);
    Task<Result<CompanyInfoDto>> UpdateCompanyAsync(CompanyInfoDto request, CancellationToken ct);
    Task<IReadOnlyList<DepartmentDto>> DepartmentsAsync(CancellationToken ct);
    Task<Result<DepartmentDto>> SaveDepartmentAsync(long? id, SaveDepartmentRequest request, CancellationToken ct);
    Task<IReadOnlyList<WarehouseDto>> WarehousesAsync(CancellationToken ct);
    Task<Result<WarehouseDto>> SaveWarehouseAsync(long? id, SaveWarehouseRequest request, CancellationToken ct);
    Task<IReadOnlyList<AppToggleDto>> AppsAsync(CancellationToken ct);
    Task<Result<AppToggleDto>> ToggleAppAsync(int appId, bool enabled, CancellationToken ct);
    Task<IReadOnlyList<SequenceDto>> SequencesAsync(CancellationToken ct);
    Task<Result<SequenceDto>> SaveSequenceAsync(long id, SaveSequenceRequest request, CancellationToken ct);
}

/// <summary>
/// Cài đặt: thông tin công ty (in trên báo giá / chứng từ), phòng ban, kho, bật / tắt ứng dụng, quy tắc đánh số chứng từ.
/// </summary>
public sealed class SettingsService(AppDbContext db, ICurrentUser currentUser, TimeProvider clock) : ISettingsService
{
    private const string PrintFooterKey = "print.footer", ReturnPolicyKey = "print.return_policy";
    private static readonly string[] LockedApps = ["settings", "users"];

    private static readonly Dictionary<string, string> SequenceLabels = new()
    {
        ["QUOTATION"] = "Báo giá", ["SALES_ORDER"] = "Đơn bán hàng", ["SALES_RETURN"] = "Phiếu trả hàng", ["PURCHASE_ORDER"] = "Đơn nhập hàng",
        ["STOCK_RECEIPT"] = "Phiếu nhập kho", ["STOCK_ISSUE"] = "Phiếu xuất kho", ["SHIPMENT"] = "Vận đơn", ["CASH_RECEIPT"] = "Phiếu thu tiền mặt",
        ["CASH_PAYMENT"] = "Phiếu chi tiền mặt", ["BANK_RECEIPT"] = "Báo có ngân hàng", ["BANK_PAYMENT"] = "Báo nợ ngân hàng", ["TICKET"] = "Phiếu CSKH",
        ["PARTNER"] = "Mã khách hàng", ["SUPPLIER"] = "Mã nhà cung cấp", ["PRODUCT"] = "Mã sản phẩm", ["EMPLOYEE"] = "Mã nhân viên",
        ["CAMPAIGN"] = "Chiến dịch marketing", ["LEAD"] = "Lead", ["OPPORTUNITY"] = "Cơ hội",
    };

    // ---------- Công ty ----------

    public async Task<CompanyInfoDto> GetCompanyAsync(CancellationToken ct)
    {
        var id = currentUser.RequireCompanyId();
        var c = await db.Companies.AsNoTracking().FirstAsync(x => x.Id == id, ct);
        var settings = await db.Settings.AsNoTracking().Where(s => s.CompanyId == id && (s.SettingKey == PrintFooterKey || s.SettingKey == ReturnPolicyKey))
            .ToDictionaryAsync(s => s.SettingKey, s => s.SettingValue, ct);
        return new CompanyInfoDto(c.Name, c.ShortName, c.TaxCode, c.Address, c.Phone, c.Email, c.Website, c.LegalRepresentative,
            settings.GetValueOrDefault(PrintFooterKey), settings.GetValueOrDefault(ReturnPolicyKey));
    }

    public async Task<Result<CompanyInfoDto>> UpdateCompanyAsync(CompanyInfoDto r, CancellationToken ct)
    {
        var id = currentUser.RequireCompanyId();
        var c = await db.Companies.FirstAsync(x => x.Id == id, ct);
        var u = c.Update(r.Name, r.ShortName, r.TaxCode, r.Address, r.Phone, r.Email, r.Website, r.LegalRepresentative);
        if (u.IsFailure) return u.Error!;
        await SetAsync(id, PrintFooterKey, r.PrintFooter, ct);
        await SetAsync(id, ReturnPolicyKey, r.ReturnPolicy, ct);
        await db.SaveChangesAsync(ct);
        return await GetCompanyAsync(ct);
    }

    private async Task SetAsync(long companyId, string key, string? value, CancellationToken ct)
    {
        var s = await db.Settings.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.SettingKey == key, ct);
        if (s is null) { s = new Setting(companyId, key); db.Settings.Add(s); }
        s.Set(string.IsNullOrWhiteSpace(value) ? null : value.Trim(), currentUser.RequireUserId(), clock.GetUtcNow().UtcDateTime);
    }

    // ---------- Phòng ban ----------

    public async Task<IReadOnlyList<DepartmentDto>> DepartmentsAsync(CancellationToken ct)
        => await db.Departments.AsNoTracking().OrderBy(d => d.SortOrder).ThenBy(d => d.Name)
            .Select(d => new DepartmentDto(d.Id, d.Code, d.Name, d.ParentId, d.SortOrder, d.IsActive,
                db.Employees.Count(e => e.DepartmentId == d.Id && (e.EmploymentStatus == "probation" || e.EmploymentStatus == "official")),
                db.UserCompanies.Count(u => u.DepartmentId == d.Id)))
            .ToListAsync(ct);

    public async Task<Result<DepartmentDto>> SaveDepartmentAsync(long? id, SaveDepartmentRequest r, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(r.Name)) return Error.Validation("department.name", "Nhập tên phòng ban.");
        if (r.ParentId is { } pid && (pid == id || !await db.Departments.AnyAsync(d => d.Id == pid, ct))) return Error.Validation("department.parent", "Phòng ban cha không hợp lệ.");
        Department d;
        if (id is { } existing)
        {
            var found = await db.Departments.FirstOrDefaultAsync(x => x.Id == existing, ct);
            if (found is null) return Error.NotFound("phòng ban");
            if (!r.IsActive && await db.Employees.AnyAsync(e => e.DepartmentId == existing && (e.EmploymentStatus == "probation" || e.EmploymentStatus == "official"), ct))
                return Error.Conflict("department.in_use", "Phòng ban còn nhân viên đang làm, chuyển nhân viên trước khi ngừng dùng.");
            d = found;
            d.Update(r.Name, r.ParentId, r.SortOrder, r.IsActive);
        }
        else
        {
            var code = (r.Code ?? "").Trim().ToUpperInvariant();
            if (code.Length is < 2 or > 20 || !code.All(ch => char.IsAsciiLetterOrDigit(ch) || ch == '_')) return Error.Validation("department.code", "Mã 2-20 ký tự chữ / số không dấu.");
            if (await db.Departments.IgnoreQueryFilters().AnyAsync(x => x.CompanyId == currentUser.RequireCompanyId() && x.Code == code, ct))
                return Error.Conflict("department.code_taken", "Mã phòng ban đã có.");
            d = Department.Create(currentUser.RequireCompanyId(), null, code, r.Name, r.SortOrder);
            if (r.ParentId is not null) d.Update(r.Name, r.ParentId, r.SortOrder, true);
            db.Departments.Add(d);
        }
        await db.SaveChangesAsync(ct);
        return (await DepartmentsAsync(ct)).First(x => x.Id == d.Id);
    }

    // ---------- Kho ----------

    public async Task<IReadOnlyList<WarehouseDto>> WarehousesAsync(CancellationToken ct)
        => await db.Warehouses.IgnoreQueryFilters().AsNoTracking().Where(w => w.CompanyId == currentUser.RequireCompanyId()).OrderBy(w => w.Id)
            .Select(w => new WarehouseDto(w.Id, w.Code, w.Name, w.Street, w.AllowNegativeStock, w.IsActive,
                db.StockBalances.Count(b => b.WarehouseId == w.Id && b.QtyOnHand != 0),
                db.StockBalances.Where(b => b.WarehouseId == w.Id).Sum(b => (decimal?)(b.QtyOnHand * b.AvgCost)) ?? 0))
            .ToListAsync(ct);

    public async Task<Result<WarehouseDto>> SaveWarehouseAsync(long? id, SaveWarehouseRequest r, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(r.Name)) return Error.Validation("warehouse.name", "Nhập tên kho.");
        var companyId = currentUser.RequireCompanyId();
        Warehouse w;
        if (id is { } existing)
        {
            var found = await db.Warehouses.IgnoreQueryFilters().FirstOrDefaultAsync(x => x.Id == existing && x.CompanyId == companyId, ct);
            if (found is null) return Error.NotFound("kho");
            if (!r.IsActive && found.IsActive)
            {
                if (await db.StockBalances.AnyAsync(b => b.WarehouseId == existing && b.QtyOnHand != 0, ct))
                    return Error.Conflict("warehouse.has_stock", "Kho còn hàng tồn, không ngừng dùng được.");
                if (!await db.Warehouses.AnyAsync(x => x.Id != existing, ct))
                    return Error.Conflict("warehouse.last", "Phải còn ít nhất 1 kho đang dùng.");
            }
            w = found;
            w.Update(r.Name, r.Street, r.AllowNegativeStock, r.IsActive);
        }
        else
        {
            var code = (r.Code ?? "").Trim().ToUpperInvariant();
            if (code.Length is < 2 or > 20 || !code.All(char.IsAsciiLetterOrDigit)) return Error.Validation("warehouse.code", "Mã kho 2-20 ký tự chữ / số không dấu.");
            if (await db.Warehouses.IgnoreQueryFilters().AnyAsync(x => x.CompanyId == companyId && x.Code == code, ct))
                return Error.Conflict("warehouse.code_taken", "Mã kho đã có.");
            w = Warehouse.Create(companyId, null, code, r.Name);
            w.Update(r.Name, r.Street, r.AllowNegativeStock, true);
            db.Warehouses.Add(w);
        }
        await db.SaveChangesAsync(ct);
        return (await WarehousesAsync(ct)).First(x => x.Id == w.Id);
    }

    // ---------- Ứng dụng ----------

    public async Task<IReadOnlyList<AppToggleDto>> AppsAsync(CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        return await (from a in db.Apps
                      join ca in db.CompanyApps.Where(x => x.CompanyId == companyId) on a.Id equals ca.AppId
                      orderby a.SortOrder
                      select new AppToggleDto(a.Id, a.Code, a.Name, a.Icon, a.Color, ca.IsEnabled, LockedApps.Contains(a.Code))).ToListAsync(ct);
    }

    public async Task<Result<AppToggleDto>> ToggleAppAsync(int appId, bool enabled, CancellationToken ct)
    {
        var companyId = currentUser.RequireCompanyId();
        var app = await db.Apps.FirstOrDefaultAsync(a => a.Id == appId, ct);
        var ca = await db.CompanyApps.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.AppId == appId, ct);
        if (app is null || ca is null) return Error.NotFound("ứng dụng");
        if (LockedApps.Contains(app.Code) && !enabled) return Error.Conflict("app.locked", "Không tắt được ứng dụng Cài đặt / Người dùng.");
        ca.SetEnabled(enabled);
        await db.SaveChangesAsync(ct);
        return new AppToggleDto(app.Id, app.Code, app.Name, app.Icon, app.Color, enabled, LockedApps.Contains(app.Code));
    }

    // ---------- Đánh số chứng từ ----------

    public async Task<IReadOnlyList<SequenceDto>> SequencesAsync(CancellationToken ct)
    {
        var list = await db.Sequences.AsNoTracking().Where(s => SequenceLabels.Keys.Contains(s.Code)).ToListAsync(ct);
        return list.OrderBy(s => SequenceLabels.Keys.ToList().IndexOf(s.Code)).Select(ToDto).ToList();
    }

    public async Task<Result<SequenceDto>> SaveSequenceAsync(long id, SaveSequenceRequest r, CancellationToken ct)
    {
        var s = await db.Sequences.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (s is null) return Error.NotFound("dãy số");
        var u = s.Update(r.Prefix, r.DatePattern, r.Padding);
        if (u.IsFailure) return u.Error!;
        await db.SaveChangesAsync(ct);
        return ToDto(s);
    }

    private SequenceDto ToDto(Sequence s)
    {
        var now = clock.GetUtcNow().UtcDateTime.AddHours(7);
        var example = s.Prefix + (s.DatePattern is { } p ? now.ToString(p) : "") + "-" + 1.ToString().PadLeft(s.Padding, '0');
        return new SequenceDto(s.Id, s.Code, SequenceLabels.GetValueOrDefault(s.Code, s.Code), s.Prefix, s.DatePattern, s.Padding, example);
    }
}
