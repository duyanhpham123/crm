using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Projects;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Projects;

public interface IProjectService
{
    Task<ProjectLookups> GetLookupsAsync(CancellationToken ct);
    Task<ProjectPage> ListProjectsAsync(string? search, string? status, int page, int pageSize, CancellationToken ct);
    Task<Result<ProjectDetail>> GetProjectAsync(long id, CancellationToken ct);
    Task<Result<ProjectDetail>> CreateProjectAsync(SaveProjectRequest request, CancellationToken ct);
    Task<Result<ProjectDetail>> UpdateProjectAsync(long id, SaveProjectRequest request, CancellationToken ct);
    Task<TaskBoard> BoardAsync(long? projectId, string? assignee, string? status, string? priority, string? search, CancellationToken ct);
    Task<Result<TaskDetail>> GetTaskAsync(long id, CancellationToken ct);
    Task<Result<TaskDetail>> CreateTaskAsync(SaveTaskRequest request, CancellationToken ct);
    Task<Result<TaskDetail>> UpdateTaskAsync(long id, SaveTaskRequest request, CancellationToken ct);
    Task<Result<TaskDetail>> MoveTaskAsync(long id, long stageId, CancellationToken ct);
    Task<Result<TaskDetail>> SetProgressAsync(long id, decimal percent, CancellationToken ct);
    Task<Result<TaskDetail>> AddChecklistAsync(long id, string title, CancellationToken ct);
    Task<Result<TaskDetail>> ToggleChecklistAsync(long id, long itemId, bool done, CancellationToken ct);
    Task<Result<TaskDetail>> RemoveChecklistAsync(long id, long itemId, CancellationToken ct);
    Task<Result<TaskDetail>> LogTimeAsync(long id, LogTimeRequest request, CancellationToken ct);
    Task<Result> DeleteTaskAsync(long id, CancellationToken ct);
}

/// <summary>
/// Dự án & công việc: dự án có thành viên, công việc trên bảng Kanban dùng chung (Cần làm / Đang làm / Chờ duyệt / Hoàn thành),
/// checklist, ghi giờ làm. Tiến độ dự án = trung bình tiến độ công việc.
/// Phạm vi xem theo quyền project.view: own = việc của mình + dự án mình tham gia; department = thêm của phòng mình; company = tất cả.
/// </summary>
public sealed class ProjectService(AppDbContext db, ICurrentUser currentUser, IDocumentNumberService docNumbers, TimeProvider clock) : IProjectService
{
    public const int BoardLimit = 300;
    /// <summary>Bảng Kanban ẩn việc đã xong quá 30 ngày (vẫn xem được khi lọc "Đã xong").</summary>
    public const int HideDoneAfterDays = 30;

    private DateTime NowUtc => clock.GetUtcNow().UtcDateTime;
    private DateOnly Today => DateOnly.FromDateTime(NowUtc.AddHours(7));

    // ---------- Phạm vi dữ liệu ----------

    private sealed record Scope(DataScope Level, long UserId, long? DepartmentId);

    private async Task<Scope> ScopeAsync(CancellationToken ct)
        => new(await currentUser.GetScopeAsync(Permissions.Projects.View, ct) ?? DataScope.Own, currentUser.RequireUserId(), currentUser.DepartmentId);

    private IQueryable<Project> VisibleProjects(Scope s)
    {
        var q = db.Projects.AsQueryable();
        if (s.Level >= DataScope.Company) return q;
        var me = s.UserId;
        if (s.Level == DataScope.Department && s.DepartmentId is { } dept)
            return q.Where(p => p.DepartmentId == dept || p.ManagerUserId == me || p.CreatedBy == me || p.Members.Any(m => m.UserId == me));
        return q.Where(p => p.ManagerUserId == me || p.CreatedBy == me || p.Members.Any(m => m.UserId == me));
    }

    private IQueryable<ProjectTask> VisibleTasks(Scope s)
    {
        var q = db.ProjectTasks.AsQueryable();
        if (s.Level >= DataScope.Company) return q;
        var me = s.UserId;
        var projects = VisibleProjects(s).Select(p => p.Id);
        if (s.Level == DataScope.Department && s.DepartmentId is { } dept)
            return q.Where(t => t.DepartmentId == dept || t.AssigneeUserId == me || t.ReporterUserId == me || t.CreatedBy == me
                                || (t.ProjectId != null && projects.Contains(t.ProjectId.Value)));
        return q.Where(t => t.AssigneeUserId == me || t.ReporterUserId == me || t.CreatedBy == me || (t.ProjectId != null && projects.Contains(t.ProjectId.Value)));
    }

    // ---------- Danh mục ----------

    private async Task<List<TaskStage>> StagesAsync(CancellationToken ct)
    {
        var stages = await db.TaskStages.Where(s => s.ProjectId == null).OrderBy(s => s.SortOrder).ToListAsync(ct);
        if (stages.Count > 0) return stages;
        var company = currentUser.RequireCompanyId();
        stages = [TaskStage.Create(company, "Cần làm", 10, false), TaskStage.Create(company, "Đang làm", 20, false),
                  TaskStage.Create(company, "Chờ duyệt", 30, false), TaskStage.Create(company, "Hoàn thành", 40, true)];
        db.TaskStages.AddRange(stages);
        await db.SaveChangesAsync(ct);
        return stages;
    }

    private async Task<List<OptionDto>> UsersAsync(CancellationToken ct)
    {
        var company = currentUser.RequireCompanyId();
        return await (from u in db.Users
                      join uc in db.UserCompanies on u.Id equals uc.UserId
                      where uc.CompanyId == company && u.IsActive
                      join d in db.Departments on uc.DepartmentId equals d.Id into dj
                      from d in dj.DefaultIfEmpty()
                      orderby u.FullName
                      select new OptionDto(u.Id, u.FullName, d != null ? d.Name : null)).ToListAsync(ct);
    }

    public async Task<ProjectLookups> GetLookupsAsync(CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var stages = await StagesAsync(ct);
        var projects = await VisibleProjects(scope).Where(p => p.Status != "completed" && p.Status != "cancelled")
            .OrderBy(p => p.Name).Select(p => new OptionDto(p.Id, p.Name, p.Code)).ToListAsync(ct);
        var departments = await db.Departments.Where(d => d.IsActive).OrderBy(d => d.SortOrder).Select(d => new OptionDto(d.Id, d.Name, d.Code)).ToListAsync(ct);
        return new ProjectLookups(await UsersAsync(ct), departments, stages.Select(ToDto).ToList(), projects, scope.UserId);
    }

    private static TaskStageDto ToDto(TaskStage s) => new(s.Id, s.Name, s.SortOrder, s.IsDone);

    // ---------- Dự án ----------

    public async Task<ProjectPage> ListProjectsAsync(string? search, string? status, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var scope = await ScopeAsync(ct);
        var today = Today;
        var q = VisibleProjects(scope).AsNoTracking();
        if (!string.IsNullOrWhiteSpace(search)) { var s = search.Trim(); q = q.Where(p => p.Name.Contains(s) || p.Code.Contains(s)); }
        if (status == "open") q = q.Where(p => p.Status == "planning" || p.Status == "active" || p.Status == "on_hold");
        else if (!string.IsNullOrEmpty(status)) q = q.Where(p => p.Status == status);
        var total = await q.CountAsync(ct);
        var rows = await q.OrderBy(p => p.Status == "completed" || p.Status == "cancelled").ThenBy(p => p.EndDate == null).ThenBy(p => p.EndDate)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(p => new
            {
                p.Id, p.Code, p.Name, p.Status, p.StartDate, p.EndDate, p.Budget, p.ProgressPercent,
                Manager = db.Users.Where(u => u.Id == p.ManagerUserId).Select(u => u.FullName).FirstOrDefault(),
                Partner = db.Partners.Where(x => x.Id == p.PartnerId).Select(x => x.Name).FirstOrDefault(),
                Members = p.Members.Count,
            }).ToListAsync(ct);
        var ids = rows.Select(r => r.Id).ToList();
        var stats = await TaskStatsAsync(ids, today, ct);
        var hours = await db.Timesheets.Where(t => t.ProjectId != null && ids.Contains(t.ProjectId.Value))
            .GroupBy(t => t.ProjectId!.Value).Select(g => new { g.Key, H = g.Sum(x => x.Hours) }).ToDictionaryAsync(x => x.Key, x => x.H, ct);
        var items = rows.Select(r =>
        {
            var st = stats.GetValueOrDefault(r.Id);
            var closed = r.Status is "completed" or "cancelled";
            return new ProjectListItem(r.Id, r.Code, r.Name, r.Status, r.Manager, r.Partner, r.StartDate, r.EndDate, r.Budget, r.ProgressPercent,
                st?.Total ?? 0, st?.Done ?? 0, st?.Overdue ?? 0, r.Members, hours.GetValueOrDefault(r.Id), !closed && r.EndDate is { } e && e < today);
        }).ToList();
        return new ProjectPage(new PagedResult<ProjectListItem>(items, page, pageSize, total), await SummaryAsync(scope, today, ct));
    }

    private sealed record Stat(int Total, int Done, int Overdue);

    private async Task<Dictionary<long, Stat>> TaskStatsAsync(IReadOnlyList<long> projectIds, DateOnly today, CancellationToken ct)
    {
        var todayStart = today.ToDateTime(TimeOnly.MinValue);
        return await db.ProjectTasks.Where(t => t.ProjectId != null && projectIds.Contains(t.ProjectId.Value))
            .GroupBy(t => t.ProjectId!.Value)
            .Select(g => new { g.Key, Total = g.Count(), Done = g.Count(t => t.CompletedAt != null), Overdue = g.Count(t => t.CompletedAt == null && t.DueDate < todayStart) })
            .ToDictionaryAsync(x => x.Key, x => new Stat(x.Total, x.Done, x.Overdue), ct);
    }

    private async Task<ProjectSummary> SummaryAsync(Scope scope, DateOnly today, CancellationToken ct)
    {
        var todayStart = today.ToDateTime(TimeOnly.MinValue);
        var weekEnd = today.AddDays(7).ToDateTime(TimeOnly.MinValue);
        var monthStartUtc = new DateTime(today.Year, today.Month, 1).AddHours(-7);
        var tasks = VisibleTasks(scope);
        var me = scope.UserId;
        return new ProjectSummary(
            await VisibleProjects(scope).CountAsync(p => p.Status == "active" || p.Status == "planning", ct),
            await tasks.CountAsync(t => t.AssigneeUserId == me && t.CompletedAt == null, ct),
            await tasks.CountAsync(t => t.CompletedAt == null && t.DueDate < todayStart, ct),
            await tasks.CountAsync(t => t.CompletedAt == null && t.DueDate >= todayStart && t.DueDate < weekEnd, ct),
            await tasks.CountAsync(t => t.CompletedAt >= monthStartUtc, ct));
    }

    public async Task<Result<ProjectDetail>> GetProjectAsync(long id, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var p = await VisibleProjects(scope).Include(x => x.Members).AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return p is null ? Error.NotFound("dự án") : await ToDetailAsync(p, ct);
    }

    public async Task<Result<ProjectDetail>> CreateProjectAsync(SaveProjectRequest r, CancellationToken ct)
    {
        var check = await ValidateRefsAsync(r.PartnerId, r.ManagerUserId, r.DepartmentId, r.MemberIds, ct);
        if (check.IsFailure) return check.Error!;
        var date = r.StartDate ?? Today;
        var created = Project.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync("PROJECT", date, ct), ToInfo(r, currentUser.RequireUserId()), NowUtc);
        if (created.IsFailure) return created.Error!;
        var p = created.Value;
        p.SetMembers([.. r.MemberIds ?? [], currentUser.RequireUserId()], NowUtc);
        db.Projects.Add(p);
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(p, ct);
    }

    public async Task<Result<ProjectDetail>> UpdateProjectAsync(long id, SaveProjectRequest r, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var p = await VisibleProjects(scope).Include(x => x.Members).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (p is null) return Error.NotFound("dự án");
        if (!CanManage(p, scope)) return Error.Forbidden("Chỉ người quản lý dự án được sửa dự án.");
        var check = await ValidateRefsAsync(r.PartnerId, r.ManagerUserId, r.DepartmentId, r.MemberIds, ct);
        if (check.IsFailure) return check.Error!;
        if (!string.IsNullOrEmpty(r.RowVersion)) db.Entry(p).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(r.RowVersion);
        var u = p.Update(ToInfo(r, p.ManagerUserId), NowUtc);
        if (u.IsFailure) return u.Error!;
        if (r.MemberIds is not null) p.SetMembers(r.MemberIds, NowUtc);
        await db.SaveChangesAsync(ct);
        if (p.Status != "completed") await RecalcProjectAsync(p.Id, ct);
        return await ToDetailAsync(p, ct);
    }

    private static bool CanManage(Project p, Scope s) => s.Level >= DataScope.Company || p.ManagerUserId == s.UserId || p.CreatedBy == s.UserId;

    private static ProjectInfo ToInfo(SaveProjectRequest r, long? defaultManager)
        => new(r.Name, r.PartnerId, r.ManagerUserId ?? defaultManager, r.DepartmentId, r.StartDate, r.EndDate, r.Budget, r.Status, r.Description);

    private async Task<Result> ValidateRefsAsync(long? partnerId, long? managerId, long? departmentId, IReadOnlyList<long>? memberIds, CancellationToken ct)
    {
        if (partnerId is { } pid && !await db.Partners.AnyAsync(p => p.Id == pid, ct)) return Error.Validation("project.partner", "Khách hàng không hợp lệ.");
        if (departmentId is { } did && !await db.Departments.AnyAsync(d => d.Id == did, ct)) return Error.Validation("project.department", "Phòng ban không hợp lệ.");
        var users = (memberIds ?? []).Concat(managerId is { } m ? [m] : []).Distinct().ToList();
        if (users.Count > 0)
        {
            var company = currentUser.RequireCompanyId();
            var valid = await db.UserCompanies.CountAsync(uc => uc.CompanyId == company && users.Contains(uc.UserId), ct);
            if (valid != users.Count) return Error.Validation("project.members", "Có thành viên không thuộc công ty.");
        }
        return Result.Success();
    }

    private async Task<ProjectDetail> ToDetailAsync(Project p, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var today = Today;
        var todayStart = today.ToDateTime(TimeOnly.MinValue);
        var userIds = p.Members.Select(m => m.UserId).ToList();
        var names = await db.Users.Where(u => userIds.Contains(u.Id) || u.Id == p.ManagerUserId).ToDictionaryAsync(u => u.Id, u => u.FullName, ct);
        var tasks = await db.ProjectTasks.AsNoTracking().Where(t => t.ProjectId == p.Id)
            .Select(t => new { t.AssigneeUserId, t.CompletedAt, t.DueDate, t.EstimatedHours }).ToListAsync(ct);
        var hours = await db.Timesheets.Where(t => t.ProjectId == p.Id).GroupBy(t => t.UserId).Select(g => new { g.Key, H = g.Sum(x => x.Hours) })
            .ToDictionaryAsync(x => x.Key, x => x.H, ct);
        var members = p.Members.OrderByDescending(m => m.MemberRole == "manager").ThenBy(m => names.GetValueOrDefault(m.UserId))
            .Select(m => new ProjectMemberDto(m.UserId, names.GetValueOrDefault(m.UserId) ?? "?", m.MemberRole,
                tasks.Count(t => t.AssigneeUserId == m.UserId && t.CompletedAt == null), hours.GetValueOrDefault(m.UserId))).ToList();
        var partner = p.PartnerId is { } pid ? await db.Partners.Where(x => x.Id == pid).Select(x => x.Name).FirstOrDefaultAsync(ct) : null;
        var dept = p.DepartmentId is { } did ? await db.Departments.Where(x => x.Id == did).Select(x => x.Name).FirstOrDefaultAsync(ct) : null;
        var canEdit = CanManage(p, scope) && await currentUser.HasPermissionAsync(Permissions.Projects.Edit, ct);
        return new ProjectDetail(p.Id, p.Code, p.Name, p.Status, p.PartnerId, partner, p.ManagerUserId,
            p.ManagerUserId is { } mid ? names.GetValueOrDefault(mid) : null, p.DepartmentId, dept, p.StartDate, p.EndDate, p.Budget, p.ProgressPercent,
            p.Description, members, tasks.Count, tasks.Count(t => t.CompletedAt != null), tasks.Count(t => t.CompletedAt == null && t.DueDate < todayStart),
            tasks.Sum(t => t.EstimatedHours ?? 0), hours.Values.Sum(), !p.IsClosed && p.EndDate is { } e && e < today, canEdit,
            Convert.ToBase64String(p.RowVersion));
    }

    private async Task RecalcProjectAsync(long? projectId, CancellationToken ct)
    {
        if (projectId is not { } id) return;
        var p = await db.Projects.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (p is null) return;
        var avg = await db.ProjectTasks.Where(t => t.ProjectId == id).AverageAsync(t => (decimal?)t.ProgressPercent, ct) ?? 0;
        p.SetProgress(avg);
        await db.SaveChangesAsync(ct);
    }

    // ---------- Công việc ----------

    public async Task<TaskBoard> BoardAsync(long? projectId, string? assignee, string? status, string? priority, string? search, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var stages = await StagesAsync(ct);
        var today = Today;
        var todayStart = today.ToDateTime(TimeOnly.MinValue);
        var q = VisibleTasks(scope).AsNoTracking();
        if (projectId is { } pid) q = q.Where(t => t.ProjectId == pid);
        if (assignee == "me") q = q.Where(t => t.AssigneeUserId == scope.UserId);
        else if (assignee == "none") q = q.Where(t => t.AssigneeUserId == null);
        else if (long.TryParse(assignee, out var uid)) q = q.Where(t => t.AssigneeUserId == uid);
        if (!string.IsNullOrEmpty(priority)) q = q.Where(t => t.Priority == priority);
        if (!string.IsNullOrWhiteSpace(search)) { var s = search.Trim(); q = q.Where(t => t.Title.Contains(s) || t.Code.Contains(s)); }
        switch (status)
        {
            case "open": q = q.Where(t => t.CompletedAt == null); break;
            case "overdue": q = q.Where(t => t.CompletedAt == null && t.DueDate < todayStart); break;
            case "done": q = q.Where(t => t.CompletedAt != null); break;
            default:
                var cutoff = NowUtc.AddDays(-HideDoneAfterDays);
                q = q.Where(t => t.CompletedAt == null || t.CompletedAt >= cutoff);
                break;
        }
        var total = await q.CountAsync(ct);
        var rows = await q
            .OrderBy(t => t.Priority == "urgent" ? 0 : t.Priority == "high" ? 1 : t.Priority == "normal" ? 2 : 3)
            .ThenBy(t => t.DueDate == null).ThenBy(t => t.DueDate).ThenByDescending(t => t.Id)
            .Take(BoardLimit)
            .Select(t => new
            {
                t.Id, t.Code, t.Title, t.ProjectId, t.StageId, t.Priority, t.AssigneeUserId, t.DueDate, t.CompletedAt, t.ProgressPercent, t.SortOrder,
                Project = db.Projects.Where(p => p.Id == t.ProjectId).Select(p => p.Name).FirstOrDefault(),
                Assignee = db.Users.Where(u => u.Id == t.AssigneeUserId).Select(u => u.FullName).FirstOrDefault(),
                Department = db.Departments.Where(d => d.Id == t.DepartmentId).Select(d => d.Name).FirstOrDefault(),
                Done = t.Checklist.Count(c => c.IsDone), Items = t.Checklist.Count,
            }).ToListAsync(ct);
        var cards = rows.Select(t => new TaskCard(t.Id, t.Code, t.Title, t.ProjectId, t.Project, t.StageId ?? stages[0].Id, t.Priority, t.AssigneeUserId,
            t.Assignee, t.Department, t.DueDate is { } d ? DateOnly.FromDateTime(d) : null,
            t.CompletedAt == null && t.DueDate is { } dd && DateOnly.FromDateTime(dd) < today, t.CompletedAt != null, t.ProgressPercent, t.Done, t.Items,
            t.SortOrder)).ToList();
        return new TaskBoard(stages.Select(ToDto).ToList(), cards, total, total > BoardLimit);
    }

    private async Task<(ProjectTask? Task, Scope Scope)> LoadTaskAsync(long id, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var t = await VisibleTasks(scope).Include(x => x.Checklist).FirstOrDefaultAsync(x => x.Id == id, ct);
        return (t, scope);
    }

    public async Task<Result<TaskDetail>> GetTaskAsync(long id, CancellationToken ct)
    {
        var (t, _) = await LoadTaskAsync(id, ct);
        return t is null ? Error.NotFound("công việc") : await ToDetailAsync(t, ct);
    }

    public async Task<Result<TaskDetail>> CreateTaskAsync(SaveTaskRequest r, CancellationToken ct)
    {
        var scope = await ScopeAsync(ct);
        var refs = await ValidateTaskRefsAsync(r, scope, ct);
        if (refs.IsFailure) return refs.Error!;
        var stages = await StagesAsync(ct);
        var stage = r.StageId is { } sid ? stages.FirstOrDefault(s => s.Id == sid) : stages[0];
        if (stage is null) return Error.Validation("task.stage", "Cột không hợp lệ.");
        var created = ProjectTask.Create(currentUser.RequireCompanyId(), await docNumbers.NextAsync("TASK", Today, ct), scope.UserId, ToInfo(r), stage, NowUtc);
        if (created.IsFailure) return created.Error!;
        var t = created.Value;
        if (!string.IsNullOrWhiteSpace(r.EntityName) && r.EntityId is { } eid) t.SetLink(r.EntityName.Trim().ToLowerInvariant(), eid);
        db.ProjectTasks.Add(t);
        await db.SaveChangesAsync(ct);
        await RecalcProjectAsync(t.ProjectId, ct);
        return await ToDetailAsync(t, ct);
    }

    public async Task<Result<TaskDetail>> UpdateTaskAsync(long id, SaveTaskRequest r, CancellationToken ct)
    {
        var (t, scope) = await LoadTaskAsync(id, ct);
        if (t is null) return Error.NotFound("công việc");
        var refs = await ValidateTaskRefsAsync(r, scope, ct);
        if (refs.IsFailure) return refs.Error!;
        if (!string.IsNullOrEmpty(r.RowVersion)) db.Entry(t).Property(x => x.RowVersion).OriginalValue = Convert.FromBase64String(r.RowVersion);
        var oldProject = t.ProjectId;
        var u = t.Update(ToInfo(r));
        if (u.IsFailure) return u.Error!;
        if (r.StageId is { } sid && sid != t.StageId)
        {
            var stage = (await StagesAsync(ct)).FirstOrDefault(s => s.Id == sid);
            if (stage is null) return Error.Validation("task.stage", "Cột không hợp lệ.");
            t.MoveTo(stage, NowUtc);
        }
        await db.SaveChangesAsync(ct);
        await RecalcProjectAsync(t.ProjectId, ct);
        if (oldProject != t.ProjectId) await RecalcProjectAsync(oldProject, ct);
        return await ToDetailAsync(t, ct);
    }

    private async Task<Result> ValidateTaskRefsAsync(SaveTaskRequest r, Scope scope, CancellationToken ct)
    {
        if (r.ProjectId is { } pid)
        {
            var p = await VisibleProjects(scope).FirstOrDefaultAsync(x => x.Id == pid, ct);
            if (p is null) return Error.Validation("task.project", "Dự án không hợp lệ.");
            if (p.IsClosed) return Error.Validation("task.project_closed", "Dự án đã kết thúc, không thêm / sửa công việc.");
        }
        if (r.DepartmentId is { } did && !await db.Departments.AnyAsync(d => d.Id == did, ct)) return Error.Validation("task.department", "Phòng ban không hợp lệ.");
        if (r.AssigneeUserId is { } uid)
        {
            var company = currentUser.RequireCompanyId();
            if (!await db.UserCompanies.AnyAsync(uc => uc.CompanyId == company && uc.UserId == uid, ct)) return Error.Validation("task.assignee", "Người nhận việc không hợp lệ.");
        }
        return Result.Success();
    }

    private static TaskInfo ToInfo(SaveTaskRequest r) => new(r.Title, r.Description, r.ProjectId, r.Priority, r.AssigneeUserId, r.DepartmentId,
        r.StartDate, r.DueDate, r.EstimatedHours);

    public async Task<Result<TaskDetail>> MoveTaskAsync(long id, long stageId, CancellationToken ct)
    {
        var (t, _) = await LoadTaskAsync(id, ct);
        if (t is null) return Error.NotFound("công việc");
        var stage = (await StagesAsync(ct)).FirstOrDefault(s => s.Id == stageId);
        if (stage is null) return Error.Validation("task.stage", "Cột không hợp lệ.");
        t.MoveTo(stage, NowUtc);
        await db.SaveChangesAsync(ct);
        await RecalcProjectAsync(t.ProjectId, ct);
        return await ToDetailAsync(t, ct);
    }

    public Task<Result<TaskDetail>> SetProgressAsync(long id, decimal percent, CancellationToken ct) => MutateAsync(id, t => t.SetProgress(percent), ct);

    public Task<Result<TaskDetail>> AddChecklistAsync(long id, string title, CancellationToken ct)
        => MutateAsync(id, t => t.AddChecklistItem(title) is { IsFailure: true } r ? r.Error! : Result.Success(), ct);

    public Task<Result<TaskDetail>> ToggleChecklistAsync(long id, long itemId, bool done, CancellationToken ct)
        => MutateAsync(id, t => t.ToggleChecklistItem(itemId, done), ct);

    public Task<Result<TaskDetail>> RemoveChecklistAsync(long id, long itemId, CancellationToken ct)
        => MutateAsync(id, t => t.RemoveChecklistItem(itemId), ct);

    private async Task<Result<TaskDetail>> MutateAsync(long id, Func<ProjectTask, Result> action, CancellationToken ct)
    {
        var (t, _) = await LoadTaskAsync(id, ct);
        if (t is null) return Error.NotFound("công việc");
        var r = action(t);
        if (r.IsFailure) return r.Error!;
        await db.SaveChangesAsync(ct);
        await RecalcProjectAsync(t.ProjectId, ct);
        return await ToDetailAsync(t, ct);
    }

    public async Task<Result<TaskDetail>> LogTimeAsync(long id, LogTimeRequest r, CancellationToken ct)
    {
        var (t, scope) = await LoadTaskAsync(id, ct);
        if (t is null) return Error.NotFound("công việc");
        var dayTotal = await db.Timesheets.Where(x => x.UserId == scope.UserId && x.WorkDate == r.Date).SumAsync(x => (decimal?)x.Hours, ct) ?? 0;
        if (dayTotal + r.Hours > 24) return Error.Validation("timesheet.day", $"Ngày {r.Date:dd/MM} bạn đã ghi {dayTotal:0.##} giờ, tổng không quá 24 giờ.");
        var ts = Timesheet.Create(scope.UserId, t.Id, t.ProjectId, r.Date, r.Hours, r.Note, Today, NowUtc);
        if (ts.IsFailure) return ts.Error!;
        db.Timesheets.Add(ts.Value);
        await db.SaveChangesAsync(ct);
        return await ToDetailAsync(t, ct);
    }

    public async Task<Result> DeleteTaskAsync(long id, CancellationToken ct)
    {
        var (t, scope) = await LoadTaskAsync(id, ct);
        if (t is null) return Error.NotFound("công việc");
        if (scope.Level < DataScope.Company && t.ReporterUserId != scope.UserId && t.CreatedBy != scope.UserId)
            return Error.Forbidden("Chỉ người giao việc được xóa công việc.");
        db.ProjectTasks.Remove(t);
        await db.SaveChangesAsync(ct);
        await RecalcProjectAsync(t.ProjectId, ct);
        return Result.Success();
    }

    private async Task<TaskDetail> ToDetailAsync(ProjectTask t, CancellationToken ct)
    {
        var today = Today;
        var userIds = new[] { t.AssigneeUserId, t.ReporterUserId }.Where(x => x != null).Select(x => x!.Value).ToList();
        var sheets = await (from s in db.Timesheets.AsNoTracking()
                            where s.TaskId == t.Id
                            join u in db.Users on s.UserId equals u.Id
                            orderby s.WorkDate descending, s.Id descending
                            select new TimesheetDto(s.Id, s.UserId, u.FullName, s.WorkDate, s.Hours, s.Note)).ToListAsync(ct);
        var names = await db.Users.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName, ct);
        var project = t.ProjectId is { } pid ? await db.Projects.Where(p => p.Id == pid).Select(p => p.Name).FirstOrDefaultAsync(ct) : null;
        var stage = t.StageId is { } sid ? await db.TaskStages.Where(s => s.Id == sid).Select(s => s.Name).FirstOrDefaultAsync(ct) : null;
        var dept = t.DepartmentId is { } did ? await db.Departments.Where(d => d.Id == did).Select(d => d.Name).FirstOrDefaultAsync(ct) : null;
        var canEdit = await currentUser.HasPermissionAsync(Permissions.Projects.Edit, ct);
        return new TaskDetail(t.Id, t.Code, t.Title, t.Description, t.ProjectId, project, t.StageId, stage, t.Priority, t.AssigneeUserId,
            t.AssigneeUserId is { } a ? names.GetValueOrDefault(a) : null, t.ReporterUserId is { } rp ? names.GetValueOrDefault(rp) : null,
            t.DepartmentId, dept, t.StartDate, t.DueDay, t.IsOverdue(today), t.CompletedAt, t.EstimatedHours, sheets.Sum(s => s.Hours), t.ProgressPercent,
            t.EntityName, t.EntityId, t.Checklist.OrderBy(c => c.SortOrder).ThenBy(c => c.Id).Select(c => new ChecklistItemDto(c.Id, c.Title, c.IsDone)).ToList(),
            sheets, t.CreatedAt, canEdit, Convert.ToBase64String(t.RowVersion));
    }
}
