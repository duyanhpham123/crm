using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using MyERP.Api.Infrastructure;
using MyERP.Api.Infrastructure.Authorization;
using MyERP.Api.Models;
using MyERP.Api.Models.DTOs;
using MyERP.Api.Services.Chat;
using MyERP.Api.Services.Documents;
using MyERP.Api.Services.Projects;
using MyERP.Api.Services.Website;

namespace MyERP.Api.Controllers;

/// <summary>Dự án & công việc: dự án, bảng Kanban, checklist, ghi giờ làm.</summary>
[Route("api/projects")]
[HasPermission(Permissions.Projects.View)]
public sealed class ProjectsController(IProjectService projects) : ApiControllerBase
{
    [HttpGet("lookups")]
    public Task<ProjectLookups> Lookups(CancellationToken ct) => projects.GetLookupsAsync(ct);

    /// <summary>GET /api/projects?status=open|planning|active|on_hold|completed|cancelled&amp;search=</summary>
    [HttpGet]
    public Task<ProjectPage> List([FromQuery] string? search, [FromQuery] string? status, [FromQuery] int page = 1, [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
        => projects.ListProjectsAsync(search, status, page, pageSize, ct);

    [HttpGet("{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct) => FromResult(await projects.GetProjectAsync(id, ct), Ok);

    [HttpPost]
    [HasPermission(Permissions.Projects.Create)]
    public async Task<IActionResult> Create(SaveProjectRequest request, CancellationToken ct)
        => FromResult(await projects.CreateProjectAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    [HttpPut("{id:long}")]
    [HasPermission(Permissions.Projects.Edit)]
    public async Task<IActionResult> Update(long id, SaveProjectRequest request, CancellationToken ct)
        => FromResult(await projects.UpdateProjectAsync(id, request, ct), Ok);

    /// <summary>GET /api/projects/tasks?projectId=&amp;assignee=me|none|{userId}&amp;status=open|overdue|done&amp;priority=&amp;search=</summary>
    [HttpGet("tasks")]
    public Task<TaskBoard> Board([FromQuery] long? projectId, [FromQuery] string? assignee, [FromQuery] string? status, [FromQuery] string? priority,
        [FromQuery] string? search, CancellationToken ct)
        => projects.BoardAsync(projectId, assignee, status, priority, search, ct);

    [HttpGet("tasks/{id:long}")]
    public async Task<IActionResult> GetTask(long id, CancellationToken ct) => FromResult(await projects.GetTaskAsync(id, ct), Ok);

    [HttpPost("tasks")]
    [HasPermission(Permissions.Projects.Create)]
    public async Task<IActionResult> CreateTask(SaveTaskRequest request, CancellationToken ct)
        => FromResult(await projects.CreateTaskAsync(request, ct), dto => CreatedAtAction(nameof(GetTask), new { id = dto.Id }, dto));

    [HttpPut("tasks/{id:long}")]
    [HasPermission(Permissions.Projects.Edit)]
    public async Task<IActionResult> UpdateTask(long id, SaveTaskRequest request, CancellationToken ct)
        => FromResult(await projects.UpdateTaskAsync(id, request, ct), Ok);

    /// <summary>POST /api/projects/tasks/5/move  body: { stageId } - kéo thả trên bảng Kanban.</summary>
    [HttpPost("tasks/{id:long}/move")]
    [HasPermission(Permissions.Projects.Edit)]
    public async Task<IActionResult> Move(long id, MoveTaskRequest request, CancellationToken ct)
        => FromResult(await projects.MoveTaskAsync(id, request.StageId, ct), Ok);

    [HttpPut("tasks/{id:long}/progress")]
    [HasPermission(Permissions.Projects.Edit)]
    public async Task<IActionResult> Progress(long id, ProgressRequest request, CancellationToken ct)
        => FromResult(await projects.SetProgressAsync(id, request.Percent, ct), Ok);

    [HttpPost("tasks/{id:long}/checklist")]
    [HasPermission(Permissions.Projects.Edit)]
    public async Task<IActionResult> AddChecklist(long id, TitleRequest request, CancellationToken ct)
        => FromResult(await projects.AddChecklistAsync(id, request.Title, ct), Ok);

    [HttpPut("tasks/{id:long}/checklist/{itemId:long}")]
    [HasPermission(Permissions.Projects.Edit)]
    public async Task<IActionResult> ToggleChecklist(long id, long itemId, DoneRequest request, CancellationToken ct)
        => FromResult(await projects.ToggleChecklistAsync(id, itemId, request.IsDone, ct), Ok);

    [HttpDelete("tasks/{id:long}/checklist/{itemId:long}")]
    [HasPermission(Permissions.Projects.Edit)]
    public async Task<IActionResult> RemoveChecklist(long id, long itemId, CancellationToken ct)
        => FromResult(await projects.RemoveChecklistAsync(id, itemId, ct), Ok);

    [HttpPost("tasks/{id:long}/timesheets")]
    [HasPermission(Permissions.Projects.Edit)]
    public async Task<IActionResult> LogTime(long id, LogTimeRequest request, CancellationToken ct)
        => FromResult(await projects.LogTimeAsync(id, request, ct), Ok);

    [HttpDelete("tasks/{id:long}")]
    [HasPermission(Permissions.Projects.Delete)]
    public async Task<IActionResult> DeleteTask(long id, CancellationToken ct) => FromResult(await projects.DeleteTaskAsync(id, ct), NoContent);
}

/// <summary>Tài liệu: thư mục, hợp đồng, phiên bản file.</summary>
[Route("api/documents")]
[HasPermission(Permissions.Documents.View)]
public sealed class DocumentsController(IDocumentService documents) : ApiControllerBase
{
    [HttpGet("lookups")]
    public Task<DocumentLookups> Lookups(CancellationToken ct) => documents.GetLookupsAsync(ct);

    /// <summary>GET /api/documents?folderId=&amp;type=contract&amp;status=expiring|expired|active...&amp;search=&amp;partnerId=</summary>
    [HttpGet]
    public Task<DocumentPage> List([FromQuery] long? folderId, [FromQuery] string? type, [FromQuery] string? status, [FromQuery] string? search,
        [FromQuery] long? partnerId, [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => documents.ListAsync(folderId, type, status, search, partnerId, page, pageSize, ct);

    [HttpGet("{id:long}")]
    public async Task<IActionResult> Get(long id, CancellationToken ct) => FromResult(await documents.GetAsync(id, ct), Ok);

    [HttpPost]
    [HasPermission(Permissions.Documents.Create)]
    public async Task<IActionResult> Create(SaveDocumentRequest request, CancellationToken ct)
        => FromResult(await documents.CreateAsync(request, ct), dto => CreatedAtAction(nameof(Get), new { id = dto.Id }, dto));

    [HttpPut("{id:long}")]
    [HasPermission(Permissions.Documents.Edit)]
    public async Task<IActionResult> Update(long id, SaveDocumentRequest request, CancellationToken ct) => FromResult(await documents.UpdateAsync(id, request, ct), Ok);

    /// <summary>POST /api/documents/5/versions (multipart/form-data: file, note) - tải file / phiên bản mới.</summary>
    [HttpPost("{id:long}/versions")]
    [HasPermission(Permissions.Documents.Edit)]
    [RequestSizeLimit(25 * 1024 * 1024)]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> Upload(long id, IFormFile file, [FromForm] string? note, CancellationToken ct)
        => FromResult(await documents.UploadVersionAsync(id, file, note, ct), Ok);

    [HttpDelete("{id:long}")]
    [HasPermission(Permissions.Documents.Delete)]
    public async Task<IActionResult> Delete(long id, CancellationToken ct) => FromResult(await documents.DeleteAsync(id, ct), NoContent);

    /// <summary>GET /api/documents/files/12 - tải file của một phiên bản.</summary>
    [HttpGet("files/{attachmentId:long}")]
    [Produces("application/octet-stream")]
    public async Task<IActionResult> Download(long attachmentId, CancellationToken ct)
        => FromResult(await documents.DownloadAsync(attachmentId, ct), f => File(f.Content, f.ContentType, f.FileName));

    [HttpPost("folders")]
    [HasPermission(Permissions.Documents.Create)]
    public async Task<IActionResult> CreateFolder(SaveFolderRequest request, CancellationToken ct) => FromResult(await documents.CreateFolderAsync(request, ct), Ok);

    [HttpPut("folders/{id:long}")]
    [HasPermission(Permissions.Documents.Edit)]
    public async Task<IActionResult> UpdateFolder(long id, SaveFolderRequest request, CancellationToken ct)
        => FromResult(await documents.UpdateFolderAsync(id, request, ct), Ok);

    [HttpDelete("folders/{id:long}")]
    [HasPermission(Permissions.Documents.Delete)]
    public async Task<IActionResult> DeleteFolder(long id, CancellationToken ct) => FromResult(await documents.DeleteFolderAsync(id, ct), NoContent);
}

/// <summary>Chat nội bộ: kênh toàn công ty, nhóm, nhắn riêng.</summary>
[Route("api/chat")]
[HasPermission(Permissions.Chat.View)]
public sealed class ChatController(IChatService chat) : ApiControllerBase
{
    [HttpGet("channels")]
    public Task<IReadOnlyList<ChatChannelDto>> Channels(CancellationToken ct) => chat.ChannelsAsync(ct);

    /// <summary>Tổng tin chưa đọc - hiện số trên biểu tượng Chat.</summary>
    [HttpGet("unread")]
    public Task<ChatUnread> Unread(CancellationToken ct) => chat.UnreadAsync(ct);

    [HttpGet("users")]
    public Task<IReadOnlyList<OptionDto>> Users(CancellationToken ct) => chat.ColleaguesAsync(ct);

    [HttpGet("channels/{id:long}")]
    public async Task<IActionResult> Channel(long id, CancellationToken ct) => FromResult(await chat.GetChannelAsync(id, ct), Ok);

    /// <summary>GET /api/chat/channels/5/messages?beforeId=123 - tải tin cũ hơn.</summary>
    [HttpGet("channels/{id:long}/messages")]
    public async Task<IActionResult> Messages(long id, [FromQuery] long? beforeId, CancellationToken ct) => FromResult(await chat.MessagesAsync(id, beforeId, ct), Ok);

    [HttpPost("channels")]
    [HasPermission(Permissions.Chat.Create)]
    public async Task<IActionResult> CreateGroup(CreateGroupRequest request, CancellationToken ct) => FromResult(await chat.CreateGroupAsync(request, ct), Ok);

    [HttpPost("direct")]
    [HasPermission(Permissions.Chat.Create)]
    public async Task<IActionResult> Direct(DirectRequest request, CancellationToken ct) => FromResult(await chat.DirectAsync(request.UserId, ct), Ok);

    [HttpPost("channels/{id:long}/messages")]
    [HasPermission(Permissions.Chat.Create)]
    public async Task<IActionResult> Post(long id, PostMessageRequest request, CancellationToken ct) => FromResult(await chat.PostAsync(id, request, ct), Ok);

    [HttpPost("channels/{id:long}/read")]
    [HasPermission(Permissions.Chat.View)]
    public async Task<IActionResult> Read(long id, ReadRequest request, CancellationToken ct) => FromResult(await chat.MarkReadAsync(id, request.MessageId, ct), NoContent);

    [HttpPost("channels/{id:long}/members")]
    [HasPermission(Permissions.Chat.Create)]
    public async Task<IActionResult> AddMembers(long id, AddMembersRequest request, CancellationToken ct)
        => FromResult(await chat.AddMembersAsync(id, request.UserIds ?? [], ct), NoContent);

    [HttpPost("channels/{id:long}/leave")]
    [HasPermission(Permissions.Chat.View)]
    public async Task<IActionResult> Leave(long id, CancellationToken ct) => FromResult(await chat.LeaveAsync(id, ct), NoContent);

    [HttpPut("messages/{id:long}")]
    [HasPermission(Permissions.Chat.Edit)]
    public async Task<IActionResult> Edit(long id, EditMessageRequest request, CancellationToken ct) => FromResult(await chat.EditAsync(id, request.Body, ct), Ok);

    [HttpDelete("messages/{id:long}")]
    [HasPermission(Permissions.Chat.Edit)]
    public async Task<IActionResult> Recall(long id, CancellationToken ct) => FromResult(await chat.RecallAsync(id, ct), Ok);

    [HttpPost("messages/{id:long}/reactions")]
    [HasPermission(Permissions.Chat.Edit)]
    public async Task<IActionResult> React(long id, ReactRequest request, CancellationToken ct) => FromResult(await chat.ReactAsync(id, request.Reaction, ct), Ok);
}

/// <summary>
/// Quản trị website bán hàng. Mọi API nhận ?siteId= (không truyền = website đầu tiên) - mỗi website có sản phẩm, bài viết, menu, liên hệ riêng.
/// </summary>
[Route("api/website")]
[HasPermission(Permissions.Website.View)]
public sealed class WebsiteController(IWebsiteService website) : ApiControllerBase
{
    // ----- Danh sách website & kết nối (khóa API, webhook) -----

    [HttpGet("sites")]
    public Task<IReadOnlyList<SiteListItem>> Sites(CancellationToken ct) => website.SitesAsync(ct);

    [HttpPost("sites")]
    [HasPermission(Permissions.Website.Create)]
    public async Task<IActionResult> CreateSite(SaveSiteRequest request, CancellationToken ct) => FromResult(await website.CreateSiteAsync(request, ct), Ok);

    /// <summary>POST /api/website/sites/2/api-key - tạo khóa mới (khóa cũ hết hiệu lực). Khóa gốc chỉ trả về 1 lần.</summary>
    [HttpPost("sites/{id:long}/api-key")]
    [HasPermission(Permissions.Website.Edit)]
    public async Task<IActionResult> IssueKey(long id, CancellationToken ct) => FromResult(await website.IssueApiKeyAsync(id, ct), Ok);

    [HttpDelete("sites/{id:long}/api-key")]
    [HasPermission(Permissions.Website.Edit)]
    public async Task<IActionResult> RevokeKey(long id, CancellationToken ct) => FromResult(await website.RevokeApiKeyAsync(id, ct), NoContent);

    /// <summary>Webhook + mật khẩu (chỉ người có quyền sửa mới xem được mật khẩu).</summary>
    [HttpGet("sites/{id:long}/webhook")]
    [HasPermission(Permissions.Website.Edit)]
    public async Task<IActionResult> Webhook(long id, CancellationToken ct) => FromResult(await website.GetWebhookAsync(id, ct), Ok);

    [HttpPut("sites/{id:long}/webhook")]
    [HasPermission(Permissions.Website.Edit)]
    public async Task<IActionResult> SaveWebhook(long id, WebhookRequest request, CancellationToken ct) => FromResult(await website.SaveWebhookAsync(id, request, ct), Ok);

    /// <summary>POST /api/website/sites/2/revalidate - báo website làm mới toàn bộ ngay, trả về kết quả gọi webhook.</summary>
    [HttpPost("sites/{id:long}/revalidate")]
    [HasPermission(Permissions.Website.Edit)]
    public async Task<IActionResult> Revalidate(long id, CancellationToken ct) => FromResult(await website.RevalidateNowAsync(id, ct), Ok);

    // ----- Nội dung của 1 website -----

    [HttpGet("overview")]
    public Task<WebsiteOverview> Overview([FromQuery] long? siteId, CancellationToken ct) => website.OverviewAsync(siteId, ct);

    [HttpGet("site")]
    public Task<SiteDto> Site([FromQuery] long? siteId, CancellationToken ct) => website.GetSiteAsync(siteId, ct);

    [HttpPut("site")]
    [HasPermission(Permissions.Website.Edit)]
    public async Task<IActionResult> SaveSite([FromQuery] long? siteId, SaveSiteRequest request, CancellationToken ct) => FromResult(await website.SaveSiteAsync(siteId, request, ct), Ok);

    [HttpGet("pages")]
    public Task<IReadOnlyList<WebPageDto>> Pages([FromQuery] long? siteId, CancellationToken ct) => website.PagesAsync(siteId, ct);

    [HttpPost("pages")]
    [HasPermission(Permissions.Website.Create)]
    public async Task<IActionResult> CreatePage([FromQuery] long? siteId, SaveContentRequest request, CancellationToken ct) => FromResult(await website.SavePageAsync(siteId, null, request, ct), Ok);

    [HttpPut("pages/{id:long}")]
    [HasPermission(Permissions.Website.Edit)]
    public async Task<IActionResult> UpdatePage([FromQuery] long? siteId, long id, SaveContentRequest request, CancellationToken ct) => FromResult(await website.SavePageAsync(siteId, id, request, ct), Ok);

    [HttpDelete("pages/{id:long}")]
    [HasPermission(Permissions.Website.Delete)]
    public async Task<IActionResult> DeletePage([FromQuery] long? siteId, long id, CancellationToken ct) => FromResult(await website.DeletePageAsync(siteId, id, ct), NoContent);

    /// <summary>GET /api/website/posts?siteId=&amp;state=published|draft&amp;categoryId=&amp;search=</summary>
    [HttpGet("posts")]
    public Task<PagedResult<PostListItem>> Posts([FromQuery] long? siteId, [FromQuery] string? search, [FromQuery] long? categoryId, [FromQuery] string? state,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => website.PostsAsync(siteId, search, categoryId, state, page, pageSize, ct);

    [HttpGet("posts/{id:long}")]
    public async Task<IActionResult> Post([FromQuery] long? siteId, long id, CancellationToken ct) => FromResult(await website.GetPostAsync(siteId, id, ct), Ok);

    [HttpPost("posts")]
    [HasPermission(Permissions.Website.Create)]
    public async Task<IActionResult> CreatePost([FromQuery] long? siteId, SaveContentRequest request, CancellationToken ct) => FromResult(await website.SavePostAsync(siteId, null, request, ct), Ok);

    [HttpPut("posts/{id:long}")]
    [HasPermission(Permissions.Website.Edit)]
    public async Task<IActionResult> UpdatePost([FromQuery] long? siteId, long id, SaveContentRequest request, CancellationToken ct) => FromResult(await website.SavePostAsync(siteId, id, request, ct), Ok);

    [HttpDelete("posts/{id:long}")]
    [HasPermission(Permissions.Website.Delete)]
    public async Task<IActionResult> DeletePost([FromQuery] long? siteId, long id, CancellationToken ct) => FromResult(await website.DeletePostAsync(siteId, id, ct), NoContent);

    [HttpGet("categories")]
    public Task<IReadOnlyList<OptionDto>> Categories([FromQuery] long? siteId, CancellationToken ct) => website.CategoriesAsync(siteId, ct);

    [HttpPost("categories")]
    [HasPermission(Permissions.Website.Create)]
    public async Task<IActionResult> CreateCategory([FromQuery] long? siteId, Inventory.NameRequest request, CancellationToken ct) => FromResult(await website.CreateCategoryAsync(siteId, request.Name, ct), Ok);

    /// <summary>GET /api/website/products?siteId=&amp;state=published|hidden|featured&amp;search= - theo mẫu sản phẩm.</summary>
    [HttpGet("products")]
    public Task<PagedResult<WebProductRow>> Products([FromQuery] long? siteId, [FromQuery] string? search, [FromQuery] string? state, [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => website.ProductsAsync(siteId, search, state, page, pageSize, ct);

    /// <summary>PUT /api/website/products/5?siteId=  body: { isPublished, priceOverride, isFeatured }</summary>
    [HttpPut("products/{modelId:long}")]
    [HasPermission(Permissions.Website.Edit)]
    public async Task<IActionResult> Publish([FromQuery] long? siteId, long modelId, WebProductUpdate request, CancellationToken ct)
        => FromResult(await website.PublishModelAsync(siteId, modelId, request, ct), Ok);

    [HttpGet("menus/{code}")]
    public Task<MenuDto> Menu([FromQuery] long? siteId, string code, CancellationToken ct) => website.MenuAsync(siteId, code, ct);

    [HttpPut("menus/{code}")]
    [HasPermission(Permissions.Website.Edit)]
    public async Task<IActionResult> SaveMenu([FromQuery] long? siteId, string code, SaveMenuRequest request, CancellationToken ct) => FromResult(await website.SaveMenuAsync(siteId, code, request, ct), Ok);

    /// <summary>GET /api/website/contacts?siteId=&amp;state=new|converted&amp;search=</summary>
    [HttpGet("contacts")]
    public Task<PagedResult<WebContactDto>> Contacts([FromQuery] long? siteId, [FromQuery] string? state, [FromQuery] string? search, [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20, CancellationToken ct = default)
        => website.ContactsAsync(siteId, state, search, page, pageSize, ct);

    /// <summary>POST /api/website/contacts/5/convert - tạo khách tiềm năng (Lead) trong CRM.</summary>
    [HttpPost("contacts/{id:long}/convert")]
    [HasPermission(Permissions.Crm.Create)]
    public async Task<IActionResult> Convert([FromQuery] long? siteId, long id, CancellationToken ct) => FromResult(await website.ConvertContactAsync(siteId, id, ct), Ok);
}

/// <summary>
/// API cho website tự code (Next.js...). Gọi từ MÁY CHỦ của website kèm header X-Site-Key (khóa tạo ở app Website > Kết nối) -
/// không để khóa lộ ra trình duyệt. Dữ liệu trả về là của đúng website đó. Form liên hệ / đặt hàng: gửi kèm X-Client-IP (IP của khách).
/// </summary>
[Route("api/public")]
[Authorize(AuthenticationSchemes = SiteKeyDefaults.Scheme)]
public sealed class PublicWebsiteController(IPublicWebsiteService site) : ApiControllerBase
{
    private string? ClientIp => Request.Headers[SiteKeyDefaults.ClientIpHeader].FirstOrDefault() is { Length: > 0 and <= 45 } ip
        ? ip : HttpContext.Connection.RemoteIpAddress?.ToString();

    /// <summary>Tên, logo, liên hệ, phí ship, menu đầu / chân trang, danh mục sản phẩm.</summary>
    [HttpGet("site")]
    public Task<PublicSite> Site(CancellationToken ct) => site.SiteAsync(ct);

    /// <summary>GET /api/public/products?category=ao-thun&amp;search=&amp;featured=true&amp;sort=price_asc|price_desc|newest</summary>
    [HttpGet("products")]
    public Task<IReadOnlyList<PublicProduct>> Products([FromQuery] string? category, [FromQuery] string? search, [FromQuery] bool featured = false,
        [FromQuery] string? sort = null, CancellationToken ct = default)
        => site.ProductsAsync(category, search, featured, sort, ct);

    /// <summary>Chi tiết + từng màu / size (SKU, giá, còn hàng) + sản phẩm cùng danh mục.</summary>
    [HttpGet("products/{slug}")]
    public async Task<IActionResult> Product(string slug, CancellationToken ct) => FromResult(await site.ProductAsync(slug, ct), Ok);

    [HttpGet("posts")]
    public Task<IReadOnlyList<PublicPost>> Posts([FromQuery] string? category, CancellationToken ct) => site.PostsAsync(category, ct);

    [HttpGet("posts/{slug}")]
    public async Task<IActionResult> Post(string slug, CancellationToken ct) => FromResult(await site.PostAsync(slug, ct), Ok);

    [HttpGet("pages/{slug}")]
    public async Task<IActionResult> Page(string slug, CancellationToken ct) => FromResult(await site.PageAsync(slug, ct), Ok);

    /// <summary>GET /api/public/promotions/check?code=GIAM20K&amp;subTotal=450000</summary>
    [HttpGet("promotions/check")]
    public async Task<IActionResult> CheckPromotion([FromQuery] string code, [FromQuery] decimal subTotal, CancellationToken ct)
        => FromResult(await site.CheckPromotionAsync(code, subTotal, ct), Ok);

    [HttpPost("contact")]
    [EnableRateLimiting(ServiceRegistration.PublicRateLimitPolicy)]
    public async Task<IActionResult> Contact(PublicContactRequest request, CancellationToken ct)
        => FromResult(await site.SubmitContactAsync(request, ClientIp, ct), () => Ok(new { message = "Cảm ơn bạn! Cửa hàng sẽ liên hệ lại sớm." }));

    /// <summary>Đặt hàng: tạo đơn Nháp kênh Website trong app Đơn hàng (giá, phí ship, mã giảm giá tính lại ở ERP).</summary>
    [HttpPost("orders")]
    [EnableRateLimiting(ServiceRegistration.PublicRateLimitPolicy)]
    public async Task<IActionResult> PlaceOrder(PublicOrderRequest request, CancellationToken ct) => FromResult(await site.PlaceOrderAsync(request, ct), Ok);
}
