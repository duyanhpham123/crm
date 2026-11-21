using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Projects;

public sealed record ProjectInfo(string Name, long? PartnerId, long? ManagerUserId, long? DepartmentId, DateOnly? StartDate, DateOnly? EndDate,
    decimal Budget, string Status, string? Description);

/// <summary>prj.Projects - dự án / đầu việc lớn (khai trương cửa hàng, chụp lookbook, kiểm kê cuối năm...).</summary>
public sealed class Project : AuditableEntity, ICompanyOwned
{
    public static readonly string[] Statuses = ["planning", "active", "on_hold", "completed", "cancelled"];

    private Project() { }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public string Name { get; private set; } = "";
    public long? PartnerId { get; private set; }
    public long? SalesOrderId { get; private set; }
    public long? ManagerUserId { get; private set; }
    public long? DepartmentId { get; private set; }
    public DateOnly? StartDate { get; private set; }
    public DateOnly? EndDate { get; private set; }
    public decimal Budget { get; private set; }
    public string Status { get; private set; } = "planning";
    public decimal ProgressPercent { get; private set; }
    public string? Description { get; private set; }

    private readonly List<ProjectMember> _members = [];
    public IReadOnlyList<ProjectMember> Members => _members;

    public bool IsClosed => Status is "completed" or "cancelled";

    public static Result<Project> Create(long companyId, string code, ProjectInfo info, DateTime nowUtc)
    {
        var p = new Project { CompanyId = companyId, Code = code };
        var r = p.Update(info, nowUtc);
        return r.IsFailure ? r.Error! : p;
    }

    public Result Update(ProjectInfo i, DateTime nowUtc)
    {
        if (string.IsNullOrWhiteSpace(i.Name)) return Error.Validation("project.name", "Nhập tên dự án.");
        if (!Statuses.Contains(i.Status)) return Error.Validation("project.status", "Trạng thái không hợp lệ.");
        if (i.StartDate is { } s && i.EndDate is { } e && e < s) return Error.Validation("project.dates", "Ngày kết thúc phải sau ngày bắt đầu.");
        if (i.Budget < 0) return Error.Validation("project.budget", "Ngân sách không hợp lệ.");
        Name = i.Name.Trim(); PartnerId = i.PartnerId; DepartmentId = i.DepartmentId; StartDate = i.StartDate; EndDate = i.EndDate;
        Budget = i.Budget; Status = i.Status; Description = string.IsNullOrWhiteSpace(i.Description) ? null : i.Description.Trim();
        ManagerUserId = i.ManagerUserId;
        foreach (var x in _members.Where(x => x.MemberRole == "manager" && x.UserId != ManagerUserId)) x.SetRole("member");
        if (i.ManagerUserId is { } m) AddMember(m, "manager", nowUtc);
        if (Status == "completed") ProgressPercent = 100;
        return Result.Success();
    }

    /// <summary>Thay danh sách thành viên. Người quản lý luôn là thành viên với vai trò manager.</summary>
    public void SetMembers(IEnumerable<long> userIds, DateTime nowUtc)
    {
        var keep = userIds.Distinct().ToHashSet();
        if (ManagerUserId is { } m) keep.Add(m);
        _members.RemoveAll(x => !keep.Contains(x.UserId));
        foreach (var id in keep) AddMember(id, id == ManagerUserId ? "manager" : "member", nowUtc);
    }

    private void AddMember(long userId, string role, DateTime nowUtc)
    {
        var existing = _members.FirstOrDefault(x => x.UserId == userId);
        if (existing is null) _members.Add(new ProjectMember(userId, role, nowUtc));
        else if (role == "manager") existing.SetRole("manager");
    }

    /// <summary>Tiến độ = trung bình tiến độ các công việc (việc ở cột hoàn thành tính 100%).</summary>
    public void SetProgress(decimal percent)
    {
        if (Status == "completed") { ProgressPercent = 100; return; }
        ProgressPercent = Math.Clamp(Math.Round(percent, 2), 0, 100);
    }

    public bool IsMember(long userId) => ManagerUserId == userId || _members.Any(m => m.UserId == userId);
}

public sealed class ProjectMember
{
    private ProjectMember() { }
    internal ProjectMember(long userId, string role, DateTime nowUtc) { UserId = userId; MemberRole = role; JoinedAt = nowUtc; }
    public long ProjectId { get; private set; }
    public long UserId { get; private set; }
    public string MemberRole { get; private set; } = "member";
    public DateTime JoinedAt { get; private set; }
    internal void SetRole(string role) => MemberRole = role;
}

/// <summary>prj.TaskStages - cột Kanban. ProjectId NULL = cột dùng chung cho mọi công việc.</summary>
public sealed class TaskStage : ICompanyOwned
{
    private TaskStage() { }
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public long? ProjectId { get; private set; }
    public string Name { get; private set; } = "";
    public int SortOrder { get; private set; }
    public bool IsDone { get; private set; }

    public static TaskStage Create(long companyId, string name, int sortOrder, bool isDone)
        => new() { CompanyId = companyId, Name = name.Trim(), SortOrder = sortOrder, IsDone = isDone };
}

public sealed record TaskInfo(string Title, string? Description, long? ProjectId, string Priority, long? AssigneeUserId, long? DepartmentId,
    DateOnly? StartDate, DateOnly? DueDate, decimal? EstimatedHours);

/// <summary>prj.Tasks - một công việc giao cho người / phòng ban, có thể thuộc dự án hoặc không.</summary>
public sealed class ProjectTask : AuditableEntity, ICompanyOwned
{
    public static readonly string[] Priorities = ["low", "normal", "high", "urgent"];

    private ProjectTask() { }
    public long CompanyId { get; private set; }
    public string Code { get; private set; } = "";
    public long? ProjectId { get; private set; }
    public long? ParentTaskId { get; private set; }
    public string Title { get; private set; } = "";
    public string? Description { get; private set; }
    public long? StageId { get; private set; }
    public string Priority { get; private set; } = "normal";
    public long? AssigneeUserId { get; private set; }
    public long? ReporterUserId { get; private set; }
    public long? DepartmentId { get; private set; }
    public string? EntityName { get; private set; }
    public long? EntityId { get; private set; }
    public DateOnly? StartDate { get; private set; }
    /// <summary>Hạn chót - lưu giờ Việt Nam, chỉ dùng phần ngày.</summary>
    public DateTime? DueDate { get; private set; }
    public DateTime? CompletedAt { get; private set; }
    public decimal? EstimatedHours { get; private set; }
    public decimal ProgressPercent { get; private set; }
    public int SortOrder { get; private set; }

    private readonly List<TaskChecklistItem> _checklist = [];
    public IReadOnlyList<TaskChecklistItem> Checklist => _checklist;

    public bool IsDone => CompletedAt is not null;
    public DateOnly? DueDay => DueDate is { } d ? DateOnly.FromDateTime(d) : null;
    public bool IsOverdue(DateOnly today) => !IsDone && DueDay is { } d && d < today;

    public static Result<ProjectTask> Create(long companyId, string code, long reporterId, TaskInfo info, TaskStage stage, DateTime nowUtc)
    {
        var t = new ProjectTask { CompanyId = companyId, Code = code, ReporterUserId = reporterId };
        var r = t.Update(info);
        if (r.IsFailure) return r.Error!;
        t.MoveTo(stage, nowUtc);
        return t;
    }

    public Result Update(TaskInfo i)
    {
        if (string.IsNullOrWhiteSpace(i.Title)) return Error.Validation("task.title", "Nhập tên công việc.");
        if (i.Title.Trim().Length > 255) return Error.Validation("task.title", "Tên công việc tối đa 255 ký tự.");
        if (!Priorities.Contains(i.Priority)) return Error.Validation("task.priority", "Mức ưu tiên không hợp lệ.");
        if (i.StartDate is { } s && i.DueDate is { } d && d < s) return Error.Validation("task.dates", "Hạn chót phải sau ngày bắt đầu.");
        if (i.EstimatedHours is < 0 or > 10000) return Error.Validation("task.hours", "Số giờ dự kiến không hợp lệ.");
        Title = i.Title.Trim(); Description = string.IsNullOrWhiteSpace(i.Description) ? null : i.Description.Trim();
        ProjectId = i.ProjectId; Priority = i.Priority; AssigneeUserId = i.AssigneeUserId; DepartmentId = i.DepartmentId;
        StartDate = i.StartDate; DueDate = i.DueDate?.ToDateTime(TimeOnly.MinValue); EstimatedHours = i.EstimatedHours;
        return Result.Success();
    }

    /// <summary>Kéo sang cột khác. Cột "hoàn thành" thì ghi nhận thời điểm xong và tiến độ 100%.</summary>
    public void MoveTo(TaskStage stage, DateTime nowUtc)
    {
        StageId = stage.Id;
        if (stage.IsDone)
        {
            CompletedAt ??= nowUtc;
            ProgressPercent = 100;
        }
        else
        {
            CompletedAt = null;
            RecalcProgress(keepManual: ProgressPercent < 100);
        }
    }

    public void SetSortOrder(int order) => SortOrder = order;

    public void SetLink(string? entityName, long? entityId) { EntityName = entityName; EntityId = entityId; }

    public Result SetProgress(decimal percent)
    {
        if (IsDone) return Error.Validation("task.done", "Công việc đã hoàn thành.");
        if (percent is < 0 or > 100) return Error.Validation("task.progress", "Tiến độ từ 0 đến 100%.");
        ProgressPercent = Math.Round(percent, 0);
        return Result.Success();
    }

    public Result<TaskChecklistItem> AddChecklistItem(string title)
    {
        if (string.IsNullOrWhiteSpace(title)) return Error.Validation("checklist.title", "Nhập nội dung.");
        if (_checklist.Count >= 50) return Error.Validation("checklist.limit", "Tối đa 50 mục.");
        var item = new TaskChecklistItem(title.Trim(), (_checklist.Count == 0 ? 0 : _checklist.Max(x => x.SortOrder)) + 10);
        _checklist.Add(item);
        RecalcProgress(keepManual: false);
        return item;
    }

    public Result ToggleChecklistItem(long itemId, bool done)
    {
        var item = _checklist.FirstOrDefault(x => x.Id == itemId);
        if (item is null) return Error.NotFound("mục việc");
        item.SetDone(done);
        RecalcProgress(keepManual: false);
        return Result.Success();
    }

    public Result RemoveChecklistItem(long itemId)
    {
        var item = _checklist.FirstOrDefault(x => x.Id == itemId);
        if (item is null) return Error.NotFound("mục việc");
        _checklist.Remove(item);
        RecalcProgress(keepManual: false);
        return Result.Success();
    }

    /// <summary>Có checklist thì tiến độ = tỷ lệ mục đã xong; không có thì giữ số nhập tay.</summary>
    private void RecalcProgress(bool keepManual)
    {
        if (IsDone) { ProgressPercent = 100; return; }
        if (_checklist.Count > 0) ProgressPercent = Math.Min(99, Math.Round(_checklist.Count(x => x.IsDone) * 100m / _checklist.Count, 0));
        else if (!keepManual) ProgressPercent = 0;
    }
}

public sealed class TaskChecklistItem
{
    private TaskChecklistItem() { }
    internal TaskChecklistItem(string title, int sortOrder) { Title = title; SortOrder = sortOrder; }
    public long Id { get; private set; }
    public long TaskId { get; private set; }
    public string Title { get; private set; } = "";
    public bool IsDone { get; private set; }
    public int SortOrder { get; private set; }
    internal void SetDone(bool done) => IsDone = done;
}

/// <summary>prj.Timesheets - giờ làm cho công việc / dự án.</summary>
public sealed class Timesheet
{
    private Timesheet() { }
    public long Id { get; private set; }
    public long? TaskId { get; private set; }
    public long? ProjectId { get; private set; }
    public long UserId { get; private set; }
    public DateOnly WorkDate { get; private set; }
    public decimal Hours { get; private set; }
    public string? Note { get; private set; }
    public bool IsBillable { get; private set; }
    public DateTime CreatedAt { get; private set; }

    public static Result<Timesheet> Create(long userId, long? taskId, long? projectId, DateOnly date, decimal hours, string? note, DateOnly today, DateTime nowUtc)
    {
        if (hours is <= 0 or > 24) return Error.Validation("timesheet.hours", "Số giờ từ 0,25 đến 24.");
        if (date > today) return Error.Validation("timesheet.date", "Không ghi giờ cho ngày chưa tới.");
        if (taskId is null && projectId is null) return Error.Validation("timesheet.target", "Chọn công việc hoặc dự án.");
        return new Timesheet
        {
            UserId = userId, TaskId = taskId, ProjectId = projectId, WorkDate = date, Hours = Math.Round(hours, 2),
            Note = string.IsNullOrWhiteSpace(note) ? null : note.Trim(), CreatedAt = nowUtc
        };
    }
}
