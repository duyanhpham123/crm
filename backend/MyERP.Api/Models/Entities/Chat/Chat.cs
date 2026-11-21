using MyERP.Api.Common;

namespace MyERP.Api.Models.Entities.Chat;

/// <summary>
/// chat.Channels - kênh chat. direct = 1-1, group = nhóm tự tạo, department = phòng ban,
/// company = toàn công ty (ai cũng thấy, không cần là thành viên), entity = thảo luận gắn với chứng từ.
/// </summary>
public sealed class Channel : ICompanyOwned
{
    public static readonly string[] Types = ["direct", "group", "department", "company", "entity"];
    public const int MaxBody = 4000;

    private Channel() { }
    public long Id { get; private set; }
    public long CompanyId { get; private set; }
    public string? Name { get; private set; }
    public string ChannelType { get; private set; } = "group";
    public long? DepartmentId { get; private set; }
    public string? EntityName { get; private set; }
    public long? EntityId { get; private set; }
    public bool IsPrivate { get; private set; } = true;
    public DateTime? LastMessageAt { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public long? CreatedBy { get; private set; }
    public bool IsArchived { get; private set; }

    private readonly List<ChannelMember> _members = [];
    public IReadOnlyList<ChannelMember> Members => _members;

    public static Result<Channel> CreateGroup(long companyId, string name, long ownerId, IEnumerable<long> memberIds, DateTime nowUtc)
    {
        if (string.IsNullOrWhiteSpace(name)) return Error.Validation("channel.name", "Nhập tên nhóm.");
        if (name.Trim().Length > 150) return Error.Validation("channel.name", "Tên nhóm tối đa 150 ký tự.");
        var c = new Channel { CompanyId = companyId, Name = name.Trim(), ChannelType = "group", CreatedBy = ownerId, CreatedAt = nowUtc };
        c._members.Add(new ChannelMember(ownerId, "owner", nowUtc));
        foreach (var id in memberIds.Distinct().Where(id => id != ownerId)) c._members.Add(new ChannelMember(id, "member", nowUtc));
        if (c._members.Count < 2) return Error.Validation("channel.members", "Chọn ít nhất 1 người khác vào nhóm.");
        return c;
    }

    public static Result<Channel> CreateDirect(long companyId, long userId, long otherUserId, DateTime nowUtc)
    {
        if (userId == otherUserId) return Error.Validation("channel.self", "Không thể nhắn tin cho chính mình.");
        var c = new Channel { CompanyId = companyId, ChannelType = "direct", CreatedBy = userId, CreatedAt = nowUtc };
        c._members.Add(new ChannelMember(userId, "member", nowUtc));
        c._members.Add(new ChannelMember(otherUserId, "member", nowUtc));
        return c;
    }

    public static Channel CreateShared(long companyId, string type, string name, long? departmentId, DateTime nowUtc)
        => new() { CompanyId = companyId, ChannelType = type, Name = name, DepartmentId = departmentId, IsPrivate = type != "company", CreatedAt = nowUtc };

    public bool IsMember(long userId) => _members.Any(m => m.UserId == userId);

    /// <summary>Kênh toàn công ty: mọi người đều đọc / gửi được. Kênh khác: phải là thành viên.</summary>
    public bool CanAccess(long userId) => ChannelType == "company" || IsMember(userId);

    public Result<Message> Post(long senderId, string? body, long? parentId, long? attachmentId, DateTime nowUtc)
    {
        if (IsArchived) return Error.Validation("channel.archived", "Kênh đã lưu trữ.");
        if (!CanAccess(senderId)) return Error.Forbidden("Bạn không ở trong kênh này.");
        var text = body?.Trim();
        if (string.IsNullOrEmpty(text) && attachmentId is null) return Error.Validation("message.empty", "Nhập nội dung tin nhắn.");
        if (text?.Length > MaxBody) return Error.Validation("message.long", $"Tin nhắn tối đa {MaxBody} ký tự.");
        LastMessageAt = nowUtc;
        EnsureMember(senderId, nowUtc);
        return new Message(Id, senderId, string.IsNullOrEmpty(text) ? null : text, parentId, attachmentId, nowUtc);
    }

    /// <summary>Kênh toàn công ty / phòng ban: tạo dòng thành viên khi người dùng mở kênh lần đầu (để đếm tin chưa đọc).</summary>
    public ChannelMember EnsureMember(long userId, DateTime nowUtc)
    {
        var m = _members.FirstOrDefault(x => x.UserId == userId);
        if (m is null) { m = new ChannelMember(userId, "member", nowUtc); _members.Add(m); }
        return m;
    }

    public Result AddMembers(long byUserId, IEnumerable<long> userIds, DateTime nowUtc)
    {
        if (ChannelType != "group") return Error.Validation("channel.type", "Chỉ thêm người vào nhóm chat.");
        if (!IsMember(byUserId)) return Error.Forbidden("Bạn không ở trong nhóm này.");
        foreach (var id in userIds.Distinct()) EnsureMember(id, nowUtc);
        return Result.Success();
    }

    public Result Leave(long userId)
    {
        if (ChannelType != "group") return Error.Validation("channel.type", "Chỉ rời được nhóm chat.");
        var m = _members.FirstOrDefault(x => x.UserId == userId);
        if (m is null) return Error.NotFound("thành viên");
        _members.Remove(m);
        if (m.MemberRole == "owner" && _members.Count > 0) _members[0].Promote();
        return Result.Success();
    }

    public void Rename(string name) { if (!string.IsNullOrWhiteSpace(name)) Name = name.Trim(); }
}

public sealed class ChannelMember
{
    private ChannelMember() { }
    internal ChannelMember(long userId, string role, DateTime nowUtc) { UserId = userId; MemberRole = role; JoinedAt = nowUtc; }
    public long ChannelId { get; private set; }
    public long UserId { get; private set; }
    public string MemberRole { get; private set; } = "member";
    public long? LastReadMessageId { get; private set; }
    public bool IsMuted { get; private set; }
    public DateTime JoinedAt { get; private set; }

    public void MarkRead(long messageId) { if (LastReadMessageId is null || messageId > LastReadMessageId) LastReadMessageId = messageId; }
    public void SetMuted(bool muted) => IsMuted = muted;
    internal void Promote() => MemberRole = "owner";
}

/// <summary>chat.Messages - tin nhắn. Thu hồi = IsDeleted (vẫn giữ dòng để luồng trả lời không bị gãy).</summary>
public sealed class Message
{
    public static readonly string[] AllowedReactions = ["👍", "❤️", "😂", "😮", "😢", "✅"];

    private Message() { }
    internal Message(long channelId, long senderId, string? body, long? parentId, long? attachmentId, DateTime nowUtc)
    {
        ChannelId = channelId; SenderUserId = senderId; Body = body; ParentMessageId = parentId; AttachmentId = attachmentId; CreatedAt = nowUtc;
    }
    public long Id { get; private set; }
    public long ChannelId { get; private set; }
    public long SenderUserId { get; private set; }
    public string? Body { get; private set; }
    public long? ParentMessageId { get; private set; }
    public long? AttachmentId { get; private set; }
    public bool IsEdited { get; private set; }
    public DateTime? EditedAt { get; private set; }
    public bool IsDeleted { get; private set; }
    public DateTime CreatedAt { get; private set; }

    private readonly List<MessageReaction> _reactions = [];
    public IReadOnlyList<MessageReaction> Reactions => _reactions;

    public Result Edit(long userId, string body, DateTime nowUtc)
    {
        if (userId != SenderUserId) return Error.Forbidden("Chỉ sửa được tin nhắn của mình.");
        if (IsDeleted) return Error.Validation("message.deleted", "Tin nhắn đã thu hồi.");
        var text = body?.Trim();
        if (string.IsNullOrEmpty(text)) return Error.Validation("message.empty", "Nhập nội dung tin nhắn.");
        if (text.Length > Channel.MaxBody) return Error.Validation("message.long", $"Tin nhắn tối đa {Channel.MaxBody} ký tự.");
        Body = text; IsEdited = true; EditedAt = nowUtc;
        return Result.Success();
    }

    public Result Recall(long userId)
    {
        if (userId != SenderUserId) return Error.Forbidden("Chỉ thu hồi được tin nhắn của mình.");
        IsDeleted = true;
        return Result.Success();
    }

    /// <summary>Bấm lại cùng biểu tượng thì bỏ.</summary>
    public Result ToggleReaction(long userId, string reaction, DateTime nowUtc)
    {
        if (!AllowedReactions.Contains(reaction)) return Error.Validation("reaction.invalid", "Biểu tượng không hợp lệ.");
        if (IsDeleted) return Error.Validation("message.deleted", "Tin nhắn đã thu hồi.");
        var r = _reactions.FirstOrDefault(x => x.UserId == userId && x.Reaction == reaction);
        if (r is null) _reactions.Add(new MessageReaction(userId, reaction, nowUtc));
        else _reactions.Remove(r);
        return Result.Success();
    }
}

public sealed class MessageReaction
{
    private MessageReaction() { }
    internal MessageReaction(long userId, string reaction, DateTime nowUtc) { UserId = userId; Reaction = reaction; CreatedAt = nowUtc; }
    public long MessageId { get; private set; }
    public long UserId { get; private set; }
    public string Reaction { get; private set; } = "";
    public DateTime CreatedAt { get; private set; }
}
