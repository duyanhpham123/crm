using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Support;

public static class TicketStatuses
{
    public const string New = "new";
    public const string Open = "open";           // đang xử lý
    public const string Pending = "pending";     // chờ khách phản hồi
    public const string Resolved = "resolved";
    public const string Closed = "closed";
    public const string Cancelled = "cancelled";

    public static bool IsActive(string s) => s is New or Open or Pending;
    public static readonly string[] All = [New, Open, Pending, Resolved, Closed, Cancelled];
}

public sealed record TicketInfo(
    string Subject, string? Description, long? PartnerId, string? ReporterName, string? ReporterPhone, long? SalesOrderId,
    long? CategoryId, string Channel, string Priority, long? AssignedUserId);

/// <summary>
/// Bảng cs.Tickets - phiếu hỗ trợ / khiếu nại / đổi trả của khách.
/// Hạn phản hồi và hạn xử lý tính theo chính sách SLA của mức ưu tiên.
/// </summary>
public sealed class Ticket : AuditableEntity, ICompanyOwned
{
    public static readonly string[] Channels = ["phone", "email", "zalo", "facebook", "web", "walk_in", "other"];
    public static readonly string[] Priorities = ["low", "normal", "high", "urgent"];

    private Ticket() { }

    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Subject { get; private set; } = "";
    public string? Description { get; private set; }
    public long? PartnerId { get; private set; }
    public string? ReporterName { get; private set; }
    public string? ReporterPhone { get; private set; }
    public long? SalesOrderId { get; private set; }
    public long? CategoryId { get; private set; }
    public string Channel { get; private set; } = "phone";
    public string Priority { get; private set; } = "normal";
    public string Status { get; private set; } = TicketStatuses.New;
    public long? AssignedUserId { get; private set; }
    public long? SlaPolicyId { get; private set; }
    public DateTime? FirstResponseDueAt { get; private set; }
    public DateTime? ResolutionDueAt { get; private set; }
    public DateTime? FirstRespondedAt { get; private set; }
    public DateTime? ResolvedAt { get; private set; }
    public DateTime? ClosedAt { get; private set; }
    public string? Resolution { get; private set; }
    public byte? SatisfactionScore { get; private set; }
    public string? SatisfactionNote { get; private set; }

    private readonly List<TicketMessage> _messages = [];
    public IReadOnlyList<TicketMessage> Messages => _messages;

    public bool IsOverdue(DateTime now) => TicketStatuses.IsActive(Status) && ResolutionDueAt is { } due && due < now;

    public static Result<Ticket> Create(long companyId, string code, TicketInfo info, SlaPolicy? sla, DateTime now)
    {
        var t = new Ticket { CompanyId = companyId, Code = code };
        var r = t.Apply(info);
        if (r.IsFailure) return r.Error!;
        t.ApplySla(sla, now);
        return t;
    }

    public Result Update(TicketInfo info, SlaPolicy? sla)
    {
        if (!TicketStatuses.IsActive(Status)) return Error.Conflict("ticket.closed", "Phiếu đã đóng, không sửa được.");
        var oldPriority = Priority;
        var r = Apply(info);
        if (r.IsSuccess && oldPriority != Priority) ApplySla(sla, CreatedAt == default ? DateTime.UtcNow : CreatedAt);
        return r;
    }

    private Result Apply(TicketInfo i)
    {
        if (string.IsNullOrWhiteSpace(i.Subject)) return Error.Validation("ticket.subject", "Nhập tiêu đề.");
        if (!Channels.Contains(i.Channel)) return Error.Validation("ticket.channel", "Kênh tiếp nhận không hợp lệ.");
        if (!Priorities.Contains(i.Priority)) return Error.Validation("ticket.priority", "Mức ưu tiên không hợp lệ.");
        if (i.PartnerId is null && string.IsNullOrWhiteSpace(i.ReporterName) && string.IsNullOrWhiteSpace(i.ReporterPhone))
            return Error.Validation("ticket.reporter", "Chọn khách hàng hoặc nhập tên / SĐT người báo.");
        string? phone = null;
        if (!string.IsNullOrWhiteSpace(i.ReporterPhone))
        {
            phone = PhoneNumber.IsValid(i.ReporterPhone) ? PhoneNumber.Normalize(i.ReporterPhone) : null;
            if (phone is null) return Error.Validation("ticket.phone", "Số điện thoại không hợp lệ.");
        }
        Subject = i.Subject.Trim(); Description = Clean(i.Description); PartnerId = i.PartnerId;
        ReporterName = Clean(i.ReporterName); ReporterPhone = phone; SalesOrderId = i.SalesOrderId; CategoryId = i.CategoryId;
        Channel = i.Channel; Priority = i.Priority; AssignedUserId = i.AssignedUserId;
        return Result.Success();
    }

    private void ApplySla(SlaPolicy? sla, DateTime from)
    {
        SlaPolicyId = sla?.Id;
        FirstResponseDueAt = sla is null ? null : from.AddMinutes(sla.FirstResponseMinutes);
        ResolutionDueAt = sla is null ? null : from.AddMinutes(sla.ResolutionMinutes);
    }

    /// <summary>Trả lời khách hoặc ghi chú nội bộ. Trả lời đầu tiên của nhân viên = phản hồi lần đầu.</summary>
    public Result AddMessage(long userId, string body, bool isInternal, DateTime now)
    {
        if (string.IsNullOrWhiteSpace(body)) return Error.Validation("ticket.body", "Nhập nội dung.");
        if (Status is TicketStatuses.Closed or TicketStatuses.Cancelled) return Error.Conflict("ticket.closed", "Phiếu đã đóng.");
        _messages.Add(TicketMessage.Create(userId, body.Trim(), isInternal, now));
        if (!isInternal)
        {
            FirstRespondedAt ??= now;
            if (Status == TicketStatuses.New) Status = TicketStatuses.Open;
        }
        return Result.Success();
    }

    public Result ChangeStatus(string next, string? resolution, DateTime now)
    {
        if (!TicketStatuses.All.Contains(next)) return Error.Validation("ticket.status", "Trạng thái không hợp lệ.");
        if (Status is TicketStatuses.Closed or TicketStatuses.Cancelled)
            return Error.Conflict("ticket.closed", "Phiếu đã đóng.");
        if (next == TicketStatuses.Resolved)
        {
            if (string.IsNullOrWhiteSpace(resolution) && string.IsNullOrWhiteSpace(Resolution))
                return Error.Validation("ticket.resolution", "Nhập cách đã xử lý cho khách.");
            Resolution = string.IsNullOrWhiteSpace(resolution) ? Resolution : resolution.Trim();
            ResolvedAt = now;
        }
        if (next == TicketStatuses.Closed) { ClosedAt = now; ResolvedAt ??= now; }
        if (TicketStatuses.IsActive(next)) { ResolvedAt = null; ClosedAt = null; }
        Status = next;
        return Result.Success();
    }

    public Result Assign(long? userId)
    {
        if (!TicketStatuses.IsActive(Status)) return Error.Conflict("ticket.closed", "Phiếu đã đóng.");
        AssignedUserId = userId;
        if (Status == TicketStatuses.New && userId is not null) Status = TicketStatuses.Open;
        return Result.Success();
    }

    public Result Rate(byte score, string? note)
    {
        if (score is < 1 or > 5) return Error.Validation("ticket.score", "Điểm đánh giá từ 1 đến 5.");
        if (Status is not (TicketStatuses.Resolved or TicketStatuses.Closed)) return Error.Conflict("ticket.not_resolved", "Chỉ đánh giá được phiếu đã xử lý xong.");
        SatisfactionScore = score;
        SatisfactionNote = Clean(note);
        return Result.Success();
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

public sealed class TicketMessage
{
    private TicketMessage() { }
    public long Id { get; private set; }
    public long TicketId { get; private set; }
    public long? AuthorUserId { get; private set; }
    public string? AuthorName { get; private set; }
    public string Body { get; private set; } = "";
    public bool IsInternal { get; private set; }
    public DateTime CreatedAt { get; private set; }

    internal static TicketMessage Create(long userId, string body, bool isInternal, DateTime now)
        => new() { AuthorUserId = userId, Body = body, IsInternal = isInternal, CreatedAt = now };
}

/// <summary>Bảng cs.TicketCategories</summary>
public sealed class TicketCategory : Entity, ICompanyOwned
{
    private TicketCategory() { }
    public long CompanyId { get; private set; }
    public string Name { get; private set; } = "";
    public bool IsActive { get; private set; } = true;
}

/// <summary>Bảng cs.SlaPolicies - thời hạn phản hồi / xử lý theo mức ưu tiên.</summary>
public sealed class SlaPolicy : Entity, ICompanyOwned
{
    private SlaPolicy() { }
    public long CompanyId { get; private set; }
    public string Name { get; private set; } = "";
    public string Priority { get; private set; } = "normal";
    public int FirstResponseMinutes { get; private set; }
    public int ResolutionMinutes { get; private set; }
}
