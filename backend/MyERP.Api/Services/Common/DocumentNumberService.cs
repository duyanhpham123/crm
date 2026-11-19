using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using MyERP.Api.Data;

namespace MyERP.Api.Services.Common;

/// <summary>Sinh số chứng từ tự động (LD2611-00001, DH2611-00001...).</summary>
public interface IDocumentNumberService
{
    /// <param name="sequenceCode">Mã dãy số trong bảng core.Sequences, VD 'LEAD', 'SALES_ORDER'.</param>
    Task<string> NextAsync(string sequenceCode, DateOnly? docDate = null, CancellationToken ct = default);
}

/// <summary>Gọi stored procedure core.usp_NextDocNo - dùng chung kết nối/transaction của AppDbContext.</summary>
public sealed class DocumentNumberService(AppDbContext db, ICurrentUser currentUser, TimeProvider clock) : IDocumentNumberService
{
    public async Task<string> NextAsync(string sequenceCode, DateOnly? docDate = null, CancellationToken ct = default)
    {
        var date = docDate ?? DateOnly.FromDateTime(clock.GetLocalNow().DateTime);
        var output = new SqlParameter("@DocNo", SqlDbType.VarChar, 50) { Direction = ParameterDirection.Output };

        await db.Database.ExecuteSqlRawAsync(
            "EXEC core.usp_NextDocNo @CompanyId, @Code, @DocDate, @DocNo OUTPUT",
            [
                new SqlParameter("@CompanyId", currentUser.RequireCompanyId()),
                new SqlParameter("@Code", SqlDbType.VarChar, 30) { Value = sequenceCode },
                new SqlParameter("@DocDate", SqlDbType.Date) { Value = date.ToDateTime(TimeOnly.MinValue) },
                output
            ], ct);

        return (string)output.Value;
    }
}
