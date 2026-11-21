using MyERP.Api.Models.Entities.Chat;
using MyERP.Api.Models.Entities.Documents;
using MyERP.Api.Models.Entities.Projects;
using MyERP.Api.Models.Entities.Website;

namespace MyERP.Tests.Models;

public class ProjectTaskTests
{
    private static readonly DateTime Now = new(2026, 11, 21, 3, 0, 0, DateTimeKind.Utc);
    private static readonly TaskStage Todo = TaskStage.Create(1, "Cần làm", 10, false);
    private static readonly TaskStage Done = TaskStage.Create(1, "Hoàn thành", 40, true);

    private static TaskInfo Info(string title = "Chụp ảnh BST", DateOnly? due = null, string priority = "normal")
        => new(title, null, null, priority, 5, null, null, due, 4);

    private static ProjectTask NewTask(DateOnly? due = null) => ProjectTask.Create(1, "CV-00001", 9, Info(due: due), Todo, Now).Value;

    /// <summary>Mục checklist mới chưa lưu đều có Id = 0; gán Id giả để thử bật / tắt từng mục.</summary>
    private static void SetId(TaskChecklistItem item, long id) => typeof(TaskChecklistItem).GetProperty("Id")!.SetValue(item, id);

    [Fact]
    public void Requires_title_and_valid_priority()
    {
        Assert.True(ProjectTask.Create(1, "CV-1", 9, Info(title: " "), Todo, Now).IsFailure);
        Assert.True(ProjectTask.Create(1, "CV-1", 9, Info(priority: "asap"), Todo, Now).IsFailure);
    }

    [Fact]
    public void Due_date_must_not_be_before_start()
    {
        var r = ProjectTask.Create(1, "CV-1", 9, new TaskInfo("A", null, null, "normal", null, null, new DateOnly(2026, 11, 20), new DateOnly(2026, 11, 19), null), Todo, Now);
        Assert.True(r.IsFailure);
    }

    [Fact]
    public void Moving_to_done_column_completes_and_back_reopens()
    {
        var t = NewTask();
        t.MoveTo(Done, Now);
        Assert.True(t.IsDone);
        Assert.Equal(100, t.ProgressPercent);
        Assert.Equal(Now, t.CompletedAt);

        t.MoveTo(Todo, Now.AddHours(1));
        Assert.False(t.IsDone);
        Assert.Null(t.CompletedAt);
        Assert.Equal(0, t.ProgressPercent);
    }

    [Fact]
    public void Checklist_drives_progress_but_never_reaches_100_until_done()
    {
        var t = NewTask();
        var a = t.AddChecklistItem("Chuẩn bị đồ").Value; SetId(a, 1);
        var b = t.AddChecklistItem("Book studio").Value; SetId(b, 2);
        Assert.Equal(0, t.ProgressPercent);

        Assert.True(t.ToggleChecklistItem(1, true).IsSuccess);
        Assert.Equal(50, t.ProgressPercent);
        t.ToggleChecklistItem(2, true);
        Assert.Equal(99, t.ProgressPercent);          // xong hết mục nhưng chưa kéo sang "Hoàn thành"

        t.RemoveChecklistItem(2);
        Assert.Equal(99, t.ProgressPercent);          // còn 1 mục, đã xong
        Assert.True(t.ToggleChecklistItem(42, true).IsFailure);
    }

    [Fact]
    public void Manual_progress_only_when_open()
    {
        var t = NewTask();
        Assert.True(t.SetProgress(40).IsSuccess);
        Assert.Equal(40, t.ProgressPercent);
        Assert.True(t.SetProgress(120).IsFailure);
        t.MoveTo(Done, Now);
        Assert.True(t.SetProgress(50).IsFailure);
    }

    [Fact]
    public void Overdue_when_open_and_due_date_passed()
    {
        var t = NewTask(due: new DateOnly(2026, 11, 20));
        Assert.True(t.IsOverdue(new DateOnly(2026, 11, 21)));
        Assert.False(t.IsOverdue(new DateOnly(2026, 11, 20)));
        t.MoveTo(Done, Now);
        Assert.False(t.IsOverdue(new DateOnly(2026, 11, 25)));
    }

    [Fact]
    public void Timesheet_validates_hours_and_date()
    {
        var today = new DateOnly(2026, 11, 21);
        Assert.True(Timesheet.Create(5, 1, null, today, 2.5m, null, today, Now).IsSuccess);
        Assert.True(Timesheet.Create(5, 1, null, today, 0, null, today, Now).IsFailure);
        Assert.True(Timesheet.Create(5, 1, null, today, 25, null, today, Now).IsFailure);
        Assert.True(Timesheet.Create(5, 1, null, today.AddDays(1), 1, null, today, Now).IsFailure);
        Assert.True(Timesheet.Create(5, null, null, today, 1, null, today, Now).IsFailure);
    }
}

public class ProjectTests
{
    private static readonly DateTime Now = new(2026, 11, 21, 3, 0, 0, DateTimeKind.Utc);

    private static ProjectInfo Info(long? manager = 7, string status = "active")
        => new("Khai trương Q7", null, manager, null, new DateOnly(2026, 11, 1), new DateOnly(2026, 12, 15), 150_000_000, status, null);

    [Fact]
    public void Manager_is_always_a_member()
    {
        var p = Project.Create(1, "DA2026-001", Info(), Now).Value;
        p.SetMembers([8, 9], Now);
        Assert.Equal(3, p.Members.Count);
        Assert.Equal("manager", p.Members.Single(m => m.UserId == 7).MemberRole);

        p.SetMembers([9], Now);                       // bỏ 8, quản lý 7 vẫn còn
        Assert.Equal([7, 9], p.Members.Select(m => m.UserId).Order());
    }

    [Fact]
    public void Changing_manager_demotes_old_manager()
    {
        var p = Project.Create(1, "DA2026-001", Info(), Now).Value;
        p.SetMembers([8], Now);
        p.Update(Info(manager: 8), Now);
        Assert.Equal("member", p.Members.Single(m => m.UserId == 7).MemberRole);
        Assert.Equal("manager", p.Members.Single(m => m.UserId == 8).MemberRole);
    }

    [Fact]
    public void Completed_project_is_100_percent()
    {
        var p = Project.Create(1, "DA2026-001", Info(), Now).Value;
        p.SetProgress(45.5m);
        Assert.Equal(45.5m, p.ProgressPercent);
        p.Update(Info(status: "completed"), Now);
        Assert.Equal(100, p.ProgressPercent);
        p.SetProgress(10);
        Assert.Equal(100, p.ProgressPercent);
    }

    [Fact]
    public void End_date_must_be_after_start()
    {
        var bad = new ProjectInfo("A", null, null, null, new DateOnly(2026, 12, 1), new DateOnly(2026, 11, 1), 0, "planning", null);
        Assert.True(Project.Create(1, "DA-1", bad, Now).IsFailure);
    }
}

public class DocumentTests
{
    private static readonly DateOnly Today = new(2026, 11, 21);

    [Theory]
    [InlineData("active", 21, false, true)]       // còn 21 ngày -> sắp hết hạn
    [InlineData("active", 31, false, false)]      // còn 31 ngày -> chưa cảnh báo
    [InlineData("active", 0, false, true)]        // hết hạn hôm nay
    [InlineData("active", -1, true, false)]       // đã qua ngày hết hạn
    [InlineData("archived", -10, false, false)]   // đã lưu trữ thì thôi
    public void Expiry_status(string status, int daysLeft, bool expired, bool expiring)
    {
        var expiry = Today.AddDays(daysLeft);
        Assert.Equal(expired, Document.EffectiveStatus(status, expiry, Today) == "expired");
        Assert.Equal(expiring, Document.IsExpiring(status, expiry, Today));
    }

    [Fact]
    public void Versions_are_numbered_in_order()
    {
        var d = Document.Create(1, 5, new DocumentInfo("HĐ thuê mặt bằng", "contract", null, null, "active", null, null, 960_000_000, "hd-01")).Value;
        Assert.Equal("HD-01", d.Code);
        Assert.Equal(1, d.AddVersion(10, "bản scan", 5, DateTime.UtcNow).VersionNo);
        Assert.Equal(2, d.AddVersion(11, "bản đã ký", 5, DateTime.UtcNow).VersionNo);
        Assert.Equal(2, d.CurrentVersionNo);
    }

    [Fact]
    public void Rejects_invalid_type_and_dates()
    {
        Assert.True(Document.Create(1, 5, new DocumentInfo("A", "invoice", null, null, "active", null, null, null, null)).IsFailure);
        Assert.True(Document.Create(1, 5, new DocumentInfo("A", "contract", null, null, "active", new DateOnly(2026, 12, 1), new DateOnly(2026, 1, 1), null, null)).IsFailure);
    }
}

public class ChatTests
{
    private static readonly DateTime Now = new(2026, 11, 21, 3, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void Group_needs_name_and_another_member()
    {
        Assert.True(Channel.CreateGroup(1, " ", 5, [6], Now).IsFailure);
        Assert.True(Channel.CreateGroup(1, "Ca tối", 5, [5], Now).IsFailure);
        var g = Channel.CreateGroup(1, "Ca tối", 5, [6, 7, 6], Now).Value;
        Assert.Equal(3, g.Members.Count);
        Assert.Equal("owner", g.Members.Single(m => m.UserId == 5).MemberRole);
    }

    [Fact]
    public void Only_members_post_except_company_channel()
    {
        var g = Channel.CreateGroup(1, "Kho", 5, [6], Now).Value;
        Assert.True(g.Post(9, "chào", null, null, Now).IsFailure);
        Assert.True(g.Post(6, "chào", null, null, Now).IsSuccess);
        Assert.True(g.Post(6, "  ", null, null, Now).IsFailure);
        Assert.True(g.Post(6, new string('a', Channel.MaxBody + 1), null, null, Now).IsFailure);

        var company = Channel.CreateShared(1, "company", "Toàn công ty", null, Now);
        Assert.True(company.Post(9, "xin chào", null, null, Now).IsSuccess);
        Assert.True(company.IsMember(9));                // tự thêm để đếm tin chưa đọc
    }

    [Fact]
    public void Direct_chat_cannot_be_with_self()
    {
        Assert.True(Channel.CreateDirect(1, 5, 5, Now).IsFailure);
        Assert.Equal(2, Channel.CreateDirect(1, 5, 6, Now).Value.Members.Count);
    }

    [Fact]
    public void Leaving_owner_hands_over_group()
    {
        var g = Channel.CreateGroup(1, "Kho", 5, [6], Now).Value;
        Assert.True(g.Leave(5).IsSuccess);
        Assert.Equal("owner", g.Members.Single().MemberRole);
    }

    [Fact]
    public void Message_edit_recall_and_reactions_by_owner_rules()
    {
        var g = Channel.CreateGroup(1, "Kho", 5, [6], Now).Value;
        var m = g.Post(5, "Hàng về chiều nay", null, null, Now).Value;
        Assert.True(m.Edit(6, "sửa", Now).IsFailure);
        Assert.True(m.Edit(5, "Hàng về 3h chiều nay", Now).IsSuccess);
        Assert.True(m.IsEdited);

        Assert.True(m.ToggleReaction(6, "👍", Now).IsSuccess);
        Assert.Single(m.Reactions);
        m.ToggleReaction(6, "👍", Now);                 // bấm lại thì bỏ
        Assert.Empty(m.Reactions);
        Assert.True(m.ToggleReaction(6, "🍕", Now).IsFailure);

        Assert.True(m.Recall(6).IsFailure);
        Assert.True(m.Recall(5).IsSuccess);
        Assert.True(m.ToggleReaction(6, "👍", Now).IsFailure);
    }

    [Fact]
    public void Read_marker_only_moves_forward()
    {
        var g = Channel.CreateGroup(1, "Kho", 5, [6], Now).Value;
        var me = g.Members.Single(x => x.UserId == 6);
        me.MarkRead(10);
        me.MarkRead(7);
        Assert.Equal(10, me.LastReadMessageId);
    }
}

public class WebsiteTests
{
    private static readonly DateTime Now = new(2026, 11, 21, 3, 0, 0, DateTimeKind.Utc);

    [Theory]
    [InlineData("Áo thun Basic - Đen!", "ao-thun-basic-den")]
    [InlineData("  Giày   sneaker  trắng ", "giay-sneaker-trang")]
    [InlineData("Đầm hoa nhí VDM10", "dam-hoa-nhi-vdm10")]
    [InlineData("!!!", "")]
    public void Slug_from_vietnamese(string text, string expected) => Assert.Equal(expected, Slug.From(text));

    [Fact]
    public void Site_domain_is_normalized_and_validated()
    {
        var s = Site.Create(1, new SiteInfo("MyStyle", "https://MyStyle.vn/", null, null, true)).Value;
        Assert.Equal("mystyle.vn", s.Domain);
        Assert.True(Site.Create(1, new SiteInfo("MyStyle", "my style.vn", null, null, true)).IsFailure);
    }

    [Fact]
    public void Publishing_sets_published_at_once()
    {
        var p = Post.Create(1, 5, new ContentInfo("Black Friday", null, null, "Nội dung", null, null, null, null, false), Now).Value;
        Assert.Equal("black-friday", p.Slug);
        Assert.Null(p.PublishedAt);
        p.Update(new ContentInfo("Black Friday", null, null, "Nội dung", null, null, null, null, true), Now);
        Assert.Equal(Now, p.PublishedAt);
        p.Update(new ContentInfo("Black Friday 2", "bf", null, null, null, null, null, null, true), Now.AddDays(1));
        Assert.Equal(Now, p.PublishedAt);
        Assert.Equal("bf", p.Slug);
    }

    [Fact]
    public void Menu_validates_urls()
    {
        var m = Menu.Create(1, "header");
        Assert.True(m.ReplaceItems([("Nam", "/collections/nam", false), ("Facebook", "https://facebook.com/x", true)]).IsSuccess);
        Assert.Equal(2, m.Items.Count);
        Assert.True(m.ReplaceItems([("Lỗi", "javascript:alert(1)", false)]).IsFailure);
        Assert.Equal(2, m.Items.Count);                 // lỗi thì giữ nguyên menu cũ
    }

    [Fact]
    public void Contact_requires_valid_phone_or_email()
    {
        Assert.True(ContactSubmission.Create(1, "Hà", null, null, "hi", null, null, null, null, null, true, Now).IsFailure);
        Assert.True(ContactSubmission.Create(1, "Hà", "12345", null, "hi", null, null, null, null, null, true, Now).IsFailure);
        Assert.True(ContactSubmission.Create(1, "Hà", null, "not-an-email", "hi", null, null, null, null, null, true, Now).IsFailure);
        var c = ContactSubmission.Create(1, "Hà", "+84 912 678 345", null, "hi", null, null, null, null, null, true, Now).Value;
        Assert.Equal("0912678345", c.Phone);
        Assert.True(c.LinkLead(3).IsSuccess);
        Assert.True(c.LinkLead(4).IsFailure);
    }
}

public class MultiSiteTests
{
    private static Site NewSite() => Site.Create(1, new SiteInfo("MyStyle", "mystyle.vn", null, null, true)).Value;

    [Fact]
    public void Api_key_is_shown_once_and_stored_hashed()
    {
        var s = NewSite();
        var key = s.IssueApiKey(DateTime.UtcNow);
        Assert.StartsWith(Site.KeyPrefix, key);
        Assert.True(key.Length >= 40);
        Assert.Equal(Site.HashKey(key), s.ApiKeyHash);
        Assert.DoesNotContain(key, s.ApiKeyHash);
        Assert.Equal(key[..10], s.ApiKeyPrefix);

        var second = s.IssueApiKey(DateTime.UtcNow);          // tạo lại = khóa cũ hết hiệu lực
        Assert.NotEqual(key, second);
        Assert.NotEqual(Site.HashKey(key), s.ApiKeyHash);
        s.RevokeApiKey();
        Assert.Null(s.ApiKeyHash);
    }

    [Fact]
    public void Webhook_requires_http_url_and_generates_secret()
    {
        var s = NewSite();
        Assert.True(s.SetWebhook("ftp://x.vn/hook", false).IsFailure);
        Assert.True(s.SetWebhook("not a url", false).IsFailure);
        Assert.True(s.SetWebhook("https://mystyle.vn/api/revalidate", false).IsSuccess);
        var secret = s.RevalidateSecret;
        Assert.False(string.IsNullOrEmpty(secret));
        s.SetWebhook("https://mystyle.vn/api/revalidate", false);
        Assert.Equal(secret, s.RevalidateSecret);              // giữ mật khẩu cũ nếu không yêu cầu đổi
        s.SetWebhook("https://mystyle.vn/api/revalidate", true);
        Assert.NotEqual(secret, s.RevalidateSecret);
        s.SetWebhook(null, false);
        Assert.Null(s.RevalidateUrl);
    }

    [Fact]
    public void Site_product_price_override_must_not_be_negative()
    {
        var sp = SiteProduct.Create(1, 2, DateTime.UtcNow);
        Assert.True(sp.Update(-1, false).IsFailure);
        Assert.True(sp.Update(199_000, true).IsSuccess);
        Assert.Equal(199_000, sp.PriceOverride);
        Assert.True(sp.IsFeatured);
    }
}
