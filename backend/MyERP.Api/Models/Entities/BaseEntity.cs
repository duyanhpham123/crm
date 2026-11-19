namespace MyERP.Api.Models.Entities;

/// <summary>Thực thể có khóa chính BIGINT IDENTITY.</summary>
public abstract class Entity
{
    public long Id { get; protected set; }
}

/// <summary>
/// Thực thể có cột audit, xóa mềm và RowVersion (khớp quy ước database).
/// CreatedAt/By, UpdatedAt/By được AuditInterceptor tự điền - không cần gán tay.
/// </summary>
public abstract class AuditableEntity : Entity, IAuditable, ISoftDelete
{
    public DateTime CreatedAt { get; set; }
    public long? CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public long? UpdatedBy { get; set; }
    public bool IsDeleted { get; set; }
    public byte[] RowVersion { get; set; } = [];
}

public interface IAuditable
{
    DateTime CreatedAt { get; set; }
    long? CreatedBy { get; set; }
    DateTime? UpdatedAt { get; set; }
    long? UpdatedBy { get; set; }
}

public interface ISoftDelete
{
    bool IsDeleted { get; set; }
}

/// <summary>Dữ liệu thuộc về một công ty: DbContext tự lọc theo công ty của người đang đăng nhập.</summary>
public interface ICompanyOwned
{
    long CompanyId { get; }
}
