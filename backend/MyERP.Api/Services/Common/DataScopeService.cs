using Microsoft.EntityFrameworkCore;
using MyERP.Api.Data;
using MyERP.Api.Models;

namespace MyERP.Api.Services.Common;

/// <summary>
/// Tính phạm vi dữ liệu người dùng được thấy theo một quyền.
/// Dùng chung cho mọi module có dữ liệu "người phụ trách" (Lead, Khách hàng, Cơ hội, Đơn hàng...).
/// </summary>
public interface IDataScopeService
{
    /// <summary>
    /// Danh sách Id người phụ trách mà người dùng được thấy dữ liệu của họ.
    /// null = không giới hạn (toàn công ty). Ném UnauthorizedAccessException nếu không có quyền.
    ///   own        -> chỉ mình
    ///   department -> mọi người cùng phòng ban
    ///   branch     -> mọi người cùng chi nhánh
    ///   company/all-> null
    /// </summary>
    Task<IReadOnlyList<long>?> VisibleOwnersAsync(string permission, CancellationToken ct);
}

public sealed class DataScopeService(AppDbContext db, ICurrentUser currentUser) : IDataScopeService
{
    public async Task<IReadOnlyList<long>?> VisibleOwnersAsync(string permission, CancellationToken ct)
    {
        var scope = await currentUser.GetScopeAsync(permission, ct) ?? throw new UnauthorizedAccessException();
        var me = currentUser.RequireUserId();
        var companyId = currentUser.RequireCompanyId();

        return scope switch
        {
            DataScope.Own => [me],
            DataScope.Department when currentUser.DepartmentId is { } dept => await db.UserCompanies
                .Where(x => x.CompanyId == companyId && x.DepartmentId == dept).Select(x => x.UserId).ToListAsync(ct),
            DataScope.Branch when currentUser.BranchId is { } branch => await db.UserCompanies
                .Where(x => x.CompanyId == companyId && x.BranchId == branch).Select(x => x.UserId).ToListAsync(ct),
            DataScope.Department or DataScope.Branch => [me],   // chưa gán phòng ban / chi nhánh: chỉ thấy của mình
            _ => null
        };
    }
}
