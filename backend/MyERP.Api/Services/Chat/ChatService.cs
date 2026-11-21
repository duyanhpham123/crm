using Microsoft.EntityFrameworkCore;
using MyERP.Api.Common;
using MyERP.Api.Data;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Models.Entities.Chat;
using MyERP.Api.Services.Common;

namespace MyERP.Api.Services.Chat;

public interface IChatService
{
    Task<IReadOnlyList<ChatChannelDto>> ChannelsAsync(CancellationToken ct);
    Task<ChatUnread> UnreadAsync(CancellationToken ct);
    Task<IReadOnlyList<OptionDto>> ColleaguesAsync(CancellationToken ct);
    Task<Result<ChatChannelDetail>> GetChannelAsync(long id, CancellationToken ct);
    Task<Result<ChatMessagesPage>> MessagesAsync(long id, long? beforeId, CancellationToken ct);
    Task<Result<ChatChannelDto>> CreateGroupAsync(CreateGroupRequest request, CancellationToken ct);
    Task<Result<ChatChannelDto>> DirectAsync(long userId, CancellationToken ct);
    Task<Result<ChatMessageDto>> PostAsync(long channelId, PostMessageRequest request, CancellationToken ct);
    Task<Result<ChatMessageDto>> EditAsync(long messageId, string body, CancellationToken ct);
    Task<Result<ChatMessageDto>> RecallAsync(long messageId, CancellationToken ct);
    Task<Result<ChatMessageDto>> ReactAsync(long messageId, string reaction, CancellationToken ct);
    Task<Result> MarkReadAsync(long channelId, long messageId, CancellationToken ct);
    Task<Result> AddMembersAsync(long channelId, IReadOnlyList<long> userIds, CancellationToken ct);
    Task<Result> LeaveAsync(long channelId, CancellationToken ct);
}

/// <summary>
/// Chat nội bộ: kênh toàn công ty (tự tạo, ai cũng thấy), nhóm tự lập, nhắn riêng 1-1. Trình duyệt hỏi lại vài giây một lần
/// để nhận tin mới (không cần máy chủ đẩy). Số tin chưa đọc tính theo LastReadMessageId của từng người.
/// </summary>
public sealed class ChatService(AppDbContext db, ICurrentUser currentUser, TimeProvider clock) : IChatService
{
    public const int PageSize = 50;
    public const string CompanyChannelName = "Toàn công ty";

    private DateTime NowUtc => clock.GetUtcNow().UtcDateTime;
    private long Me => currentUser.RequireUserId();

    private IQueryable<Channel> MyChannels(long me)
        => db.Channels.Where(c => !c.IsArchived && (c.ChannelType == "company" || c.Members.Any(m => m.UserId == me)));

    private async Task EnsureCompanyChannelAsync(CancellationToken ct)
    {
        if (await db.Channels.AnyAsync(c => c.ChannelType == "company", ct)) return;
        db.Channels.Add(Channel.CreateShared(currentUser.RequireCompanyId(), "company", CompanyChannelName, null, NowUtc));
        await db.SaveChangesAsync(ct);
    }

    public async Task<IReadOnlyList<ChatChannelDto>> ChannelsAsync(CancellationToken ct)
    {
        await EnsureCompanyChannelAsync(ct);
        var me = Me;
        var rows = await MyChannels(me).AsNoTracking()
            .Select(c => new
            {
                c.Id, c.Name, c.ChannelType, c.LastMessageAt, c.CreatedAt,
                MemberCount = c.Members.Count,
                LastRead = c.Members.Where(m => m.UserId == me).Select(m => m.LastReadMessageId).FirstOrDefault(),
                Other = c.ChannelType == "direct" ? c.Members.Where(m => m.UserId != me).Select(m => (long?)m.UserId).FirstOrDefault() : null,
                Last = db.Messages.Where(m => m.ChannelId == c.Id).OrderByDescending(m => m.Id)
                    .Select(m => new { m.Body, m.IsDeleted, m.AttachmentId, Sender = db.Users.Where(u => u.Id == m.SenderUserId).Select(u => u.FullName).FirstOrDefault() })
                    .FirstOrDefault(),
            }).ToListAsync(ct);
        var otherIds = rows.Where(r => r.Other != null).Select(r => r.Other!.Value).Distinct().ToList();
        var others = await db.Users.Where(u => otherIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName, ct);
        var unread = await UnreadByChannelAsync(me, rows.Select(r => r.Id).ToList(), ct);
        return rows.Select(r => new ChatChannelDto(r.Id,
                r.ChannelType == "direct" ? (r.Other is { } o ? others.GetValueOrDefault(o) ?? "?" : "?") : r.Name ?? "Nhóm",
                r.ChannelType, r.MemberCount,
                r.Last is null ? null : r.Last.IsDeleted ? "Tin nhắn đã thu hồi" : r.Last.Body ?? "📎 File đính kèm",
                r.Last?.Sender, r.LastMessageAt, unread.GetValueOrDefault(r.Id), r.Other))
            .OrderByDescending(c => c.Type == "company").ThenByDescending(c => c.LastMessageAt ?? DateTime.MinValue).ToList();
    }

    /// <summary>Tin chưa đọc = tin của người khác, chưa thu hồi, sau tin cuối mình đã đọc.</summary>
    private async Task<Dictionary<long, int>> UnreadByChannelAsync(long me, IReadOnlyList<long> channelIds, CancellationToken ct)
        => await (from m in db.Messages
                  where channelIds.Contains(m.ChannelId) && m.SenderUserId != me && !m.IsDeleted
                  let lastRead = db.ChannelMembers.Where(x => x.ChannelId == m.ChannelId && x.UserId == me).Select(x => x.LastReadMessageId).FirstOrDefault()
                  where lastRead == null || m.Id > lastRead
                  group m by m.ChannelId into g
                  select new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);

    public async Task<ChatUnread> UnreadAsync(CancellationToken ct)
    {
        var me = Me;
        var ids = await MyChannels(me).Select(c => c.Id).ToListAsync(ct);
        var byChannel = await UnreadByChannelAsync(me, ids, ct);
        return new ChatUnread(byChannel.Values.Sum(), byChannel.Count);
    }

    public async Task<IReadOnlyList<OptionDto>> ColleaguesAsync(CancellationToken ct)
    {
        var company = currentUser.RequireCompanyId();
        var me = Me;
        return await (from u in db.Users
                      join uc in db.UserCompanies on u.Id equals uc.UserId
                      where uc.CompanyId == company && u.IsActive && u.Id != me
                      join d in db.Departments on uc.DepartmentId equals d.Id into dj
                      from d in dj.DefaultIfEmpty()
                      orderby u.FullName
                      select new OptionDto(u.Id, u.FullName, d != null ? d.Name : null)).ToListAsync(ct);
    }

    private async Task<Channel?> LoadAsync(long id, CancellationToken ct)
    {
        var me = Me;
        return await MyChannels(me).Include(c => c.Members).FirstOrDefaultAsync(c => c.Id == id, ct);
    }

    public async Task<Result<ChatChannelDetail>> GetChannelAsync(long id, CancellationToken ct)
    {
        var c = await LoadAsync(id, ct);
        if (c is null) return Error.NotFound("kênh chat");
        var me = Me;
        var page = await PageAsync(c.Id, null, me, ct);
        var memberIds = c.Members.Select(m => m.UserId).ToList();
        var company = currentUser.RequireCompanyId();
        var members = await (from u in db.Users
                             where memberIds.Contains(u.Id)
                             join uc in db.UserCompanies.Where(x => x.CompanyId == company) on u.Id equals uc.UserId into ucj
                             from uc in ucj.DefaultIfEmpty()
                             join d in db.Departments on uc.DepartmentId equals d.Id into dj
                             from d in dj.DefaultIfEmpty()
                             select new { u.Id, u.FullName, Dept = d != null ? d.Name : null }).ToListAsync(ct);
        var dtoMembers = members.Select(m => new ChatMemberDto(m.Id, m.FullName, c.Members.First(x => x.UserId == m.Id).MemberRole, m.Dept))
            .OrderByDescending(m => m.Role == "owner").ThenBy(m => m.FullName).ToList();
        var name = c.ChannelType == "direct" ? dtoMembers.FirstOrDefault(m => m.UserId != me)?.FullName ?? "?" : c.Name ?? "Nhóm";
        return new ChatChannelDetail(c.Id, name, c.ChannelType, c.ChannelType == "group" && c.IsMember(me), c.ChannelType == "group" && c.IsMember(me),
            c.ChannelType == "company" ? [] : dtoMembers, page.Messages, page.HasMore);
    }

    public async Task<Result<ChatMessagesPage>> MessagesAsync(long id, long? beforeId, CancellationToken ct)
    {
        var c = await LoadAsync(id, ct);
        return c is null ? Error.NotFound("kênh chat") : await PageAsync(c.Id, beforeId, Me, ct);
    }

    private async Task<ChatMessagesPage> PageAsync(long channelId, long? beforeId, long me, CancellationToken ct)
    {
        var q = db.Messages.AsNoTracking().Where(m => m.ChannelId == channelId);
        if (beforeId is { } b) q = q.Where(m => m.Id < b);
        var ids = await q.OrderByDescending(m => m.Id).Select(m => m.Id).Take(PageSize + 1).ToListAsync(ct);
        var hasMore = ids.Count > PageSize;
        var list = await ToDtosAsync(ids.Take(PageSize).ToList(), me, ct);
        return new ChatMessagesPage(list, hasMore);
    }

    private async Task<List<ChatMessageDto>> ToDtosAsync(IReadOnlyList<long> ids, long me, CancellationToken ct)
    {
        var msgs = await db.Messages.AsNoTracking().Include(m => m.Reactions).Where(m => ids.Contains(m.Id)).OrderBy(m => m.Id).ToListAsync(ct);
        var parentIds = msgs.Where(m => m.ParentMessageId != null).Select(m => m.ParentMessageId!.Value).Distinct().ToList();
        var parents = await db.Messages.AsNoTracking().Where(m => parentIds.Contains(m.Id))
            .Select(m => new { m.Id, m.Body, m.IsDeleted, m.SenderUserId }).ToDictionaryAsync(m => m.Id, ct);
        var userIds = msgs.Select(m => m.SenderUserId).Concat(msgs.SelectMany(m => m.Reactions.Select(r => r.UserId)))
            .Concat(parents.Values.Select(p => p.SenderUserId)).Distinct().ToList();
        var names = await db.Users.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName, ct);
        return msgs.Select(m =>
        {
            var parent = m.ParentMessageId is { } pid ? parents.GetValueOrDefault(pid) : null;
            var preview = parent is null ? null : parent.IsDeleted ? "Tin nhắn đã thu hồi" : Short(parent.Body);
            List<ReactionDto> reactions = m.IsDeleted ? [] : m.Reactions.GroupBy(r => r.Reaction)
                .Select(g => new ReactionDto(g.Key, g.Count(), g.Any(r => r.UserId == me), g.Select(r => names.GetValueOrDefault(r.UserId) ?? "?").ToList()))
                .OrderByDescending(r => r.Count).ToList();
            return new ChatMessageDto(m.Id, m.ChannelId, m.SenderUserId, names.GetValueOrDefault(m.SenderUserId) ?? "?", m.IsDeleted ? null : m.Body,
                m.ParentMessageId, preview, parent is null ? null : names.GetValueOrDefault(parent.SenderUserId), m.CreatedAt, m.IsEdited, m.IsDeleted,
                m.SenderUserId == me, reactions);
        }).ToList();
    }

    private static string? Short(string? s) => s is null ? null : s.Length > 80 ? s[..80] + "…" : s;

    public async Task<Result<ChatChannelDto>> CreateGroupAsync(CreateGroupRequest r, CancellationToken ct)
    {
        var ids = (r.MemberIds ?? []).Distinct().ToList();
        if (ids.Count > 200) return Error.Validation("channel.members", "Nhóm tối đa 200 người.");
        var valid = await ValidUsersAsync(ids, ct);
        if (valid.IsFailure) return valid.Error!;
        var created = Channel.CreateGroup(currentUser.RequireCompanyId(), r.Name, Me, ids, NowUtc);
        if (created.IsFailure) return created.Error!;
        db.Channels.Add(created.Value);
        await db.SaveChangesAsync(ct);
        return (await ChannelsAsync(ct)).First(c => c.Id == created.Value.Id);
    }

    /// <summary>Mở (hoặc tạo) cuộc trò chuyện riêng với một đồng nghiệp.</summary>
    public async Task<Result<ChatChannelDto>> DirectAsync(long userId, CancellationToken ct)
    {
        var me = Me;
        if (userId == me) return Error.Validation("channel.self", "Không thể nhắn tin cho chính mình.");
        var valid = await ValidUsersAsync([userId], ct);
        if (valid.IsFailure) return valid.Error!;
        var existing = await db.Channels.Where(c => c.ChannelType == "direct" && c.Members.Count == 2
                && c.Members.Any(m => m.UserId == me) && c.Members.Any(m => m.UserId == userId))
            .Select(c => (long?)c.Id).FirstOrDefaultAsync(ct);
        if (existing is null)
        {
            var created = Channel.CreateDirect(currentUser.RequireCompanyId(), me, userId, NowUtc);
            if (created.IsFailure) return created.Error!;
            db.Channels.Add(created.Value);
            await db.SaveChangesAsync(ct);
            existing = created.Value.Id;
        }
        return (await ChannelsAsync(ct)).First(c => c.Id == existing);
    }

    private async Task<Result> ValidUsersAsync(IReadOnlyList<long> ids, CancellationToken ct)
    {
        if (ids.Count == 0) return Result.Success();
        var company = currentUser.RequireCompanyId();
        var n = await (from u in db.Users join uc in db.UserCompanies on u.Id equals uc.UserId
                       where uc.CompanyId == company && u.IsActive && ids.Contains(u.Id) select u.Id).Distinct().CountAsync(ct);
        return n == ids.Count ? Result.Success() : Error.Validation("chat.users", "Có người dùng không hợp lệ.");
    }

    public async Task<Result<ChatMessageDto>> PostAsync(long channelId, PostMessageRequest r, CancellationToken ct)
    {
        var c = await LoadAsync(channelId, ct);
        if (c is null) return Error.NotFound("kênh chat");
        if (r.ParentMessageId is { } pid && !await db.Messages.AnyAsync(m => m.Id == pid && m.ChannelId == channelId, ct))
            return Error.Validation("message.parent", "Tin nhắn trả lời không hợp lệ.");
        var me = Me;
        var posted = c.Post(me, r.Body, r.ParentMessageId, null, NowUtc);
        if (posted.IsFailure) return posted.Error!;
        db.Messages.Add(posted.Value);
        await db.SaveChangesAsync(ct);
        c.EnsureMember(me, NowUtc).MarkRead(posted.Value.Id);
        await db.SaveChangesAsync(ct);
        return (await ToDtosAsync([posted.Value.Id], me, ct))[0];
    }

    private async Task<(Message? Msg, Result Access)> LoadMessageAsync(long messageId, CancellationToken ct)
    {
        var m = await db.Messages.Include(x => x.Reactions).FirstOrDefaultAsync(x => x.Id == messageId, ct);
        if (m is null) return (null, Error.NotFound("tin nhắn"));
        var c = await LoadAsync(m.ChannelId, ct);
        return c is null ? (null, Error.NotFound("tin nhắn")) : (m, Result.Success());
    }

    public Task<Result<ChatMessageDto>> EditAsync(long messageId, string body, CancellationToken ct) => MutateAsync(messageId, (m, me) => m.Edit(me, body, NowUtc), ct);
    public Task<Result<ChatMessageDto>> RecallAsync(long messageId, CancellationToken ct) => MutateAsync(messageId, (m, me) => m.Recall(me), ct);
    public Task<Result<ChatMessageDto>> ReactAsync(long messageId, string reaction, CancellationToken ct)
        => MutateAsync(messageId, (m, me) => m.ToggleReaction(me, reaction, NowUtc), ct);

    private async Task<Result<ChatMessageDto>> MutateAsync(long messageId, Func<Message, long, Result> action, CancellationToken ct)
    {
        var (m, access) = await LoadMessageAsync(messageId, ct);
        if (m is null) return access.Error!;
        var me = Me;
        var r = action(m, me);
        if (r.IsFailure) return r.Error!;
        await db.SaveChangesAsync(ct);
        return (await ToDtosAsync([m.Id], me, ct))[0];
    }

    public async Task<Result> MarkReadAsync(long channelId, long messageId, CancellationToken ct)
    {
        var c = await LoadAsync(channelId, ct);
        if (c is null) return Error.NotFound("kênh chat");
        var maxId = await db.Messages.Where(m => m.ChannelId == channelId).MaxAsync(m => (long?)m.Id, ct) ?? 0;
        c.EnsureMember(Me, NowUtc).MarkRead(Math.Min(messageId, maxId));
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result> AddMembersAsync(long channelId, IReadOnlyList<long> userIds, CancellationToken ct)
    {
        var c = await LoadAsync(channelId, ct);
        if (c is null) return Error.NotFound("kênh chat");
        var valid = await ValidUsersAsync(userIds.Distinct().ToList(), ct);
        if (valid.IsFailure) return valid;
        var r = c.AddMembers(Me, userIds, NowUtc);
        if (r.IsFailure) return r;
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result> LeaveAsync(long channelId, CancellationToken ct)
    {
        var c = await LoadAsync(channelId, ct);
        if (c is null) return Error.NotFound("kênh chat");
        var r = c.Leave(Me);
        if (r.IsFailure) return r;
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }
}
