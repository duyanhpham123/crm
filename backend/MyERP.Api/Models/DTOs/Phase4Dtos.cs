namespace MyERP.Api.Models.DTOs;

// ===================== DỰ ÁN & CÔNG VIỆC =====================

public sealed record TaskStageDto(long Id, string Name, int SortOrder, bool IsDone);

public sealed record ProjectLookups(IReadOnlyList<OptionDto> Users, IReadOnlyList<OptionDto> Departments, IReadOnlyList<TaskStageDto> Stages,
    IReadOnlyList<OptionDto> Projects, long CurrentUserId);

public sealed record ProjectListItem(long Id, string Code, string Name, string Status, string? ManagerName, string? PartnerName, DateOnly? StartDate,
    DateOnly? EndDate, decimal Budget, decimal ProgressPercent, int TaskCount, int DoneCount, int OverdueCount, int MemberCount, decimal Hours, bool IsLate);

public sealed record ProjectSummary(int Active, int MyOpenTasks, int OverdueTasks, int DueThisWeek, int DoneThisMonth);

public sealed record ProjectPage(PagedResult<ProjectListItem> Rows, ProjectSummary Summary);

public sealed record ProjectMemberDto(long UserId, string FullName, string Role, int OpenTasks, decimal Hours);

public sealed record ProjectDetail(long Id, string Code, string Name, string Status, long? PartnerId, string? PartnerName, long? ManagerUserId,
    string? ManagerName, long? DepartmentId, string? DepartmentName, DateOnly? StartDate, DateOnly? EndDate, decimal Budget, decimal ProgressPercent,
    string? Description, IReadOnlyList<ProjectMemberDto> Members, int TaskCount, int DoneCount, int OverdueCount, decimal EstimatedHours,
    decimal LoggedHours, bool IsLate, bool CanEdit, string RowVersion);

public sealed record SaveProjectRequest(string Name, long? PartnerId, long? ManagerUserId, long? DepartmentId, DateOnly? StartDate, DateOnly? EndDate,
    decimal Budget, string Status, string? Description, IReadOnlyList<long>? MemberIds, string? RowVersion = null);

public sealed record TaskCard(long Id, string Code, string Title, long? ProjectId, string? ProjectName, long? StageId, string Priority,
    long? AssigneeUserId, string? AssigneeName, string? DepartmentName, DateOnly? DueDate, bool IsOverdue, bool IsDone, decimal ProgressPercent,
    int ChecklistDone, int ChecklistTotal, int SortOrder);

public sealed record TaskBoard(IReadOnlyList<TaskStageDto> Stages, IReadOnlyList<TaskCard> Tasks, int Total, bool Truncated);

public sealed record ChecklistItemDto(long Id, string Title, bool IsDone);

public sealed record TimesheetDto(long Id, long UserId, string UserName, DateOnly WorkDate, decimal Hours, string? Note);

public sealed record TaskDetail(long Id, string Code, string Title, string? Description, long? ProjectId, string? ProjectName, long? StageId,
    string? StageName, string Priority, long? AssigneeUserId, string? AssigneeName, string? ReporterName, long? DepartmentId, string? DepartmentName,
    DateOnly? StartDate, DateOnly? DueDate, bool IsOverdue, DateTime? CompletedAt, decimal? EstimatedHours, decimal LoggedHours, decimal ProgressPercent,
    string? EntityName, long? EntityId, IReadOnlyList<ChecklistItemDto> Checklist, IReadOnlyList<TimesheetDto> Timesheets, DateTime CreatedAt,
    bool CanEdit, string RowVersion);

public sealed record SaveTaskRequest(string Title, string? Description, long? ProjectId, string Priority, long? AssigneeUserId, long? DepartmentId,
    DateOnly? StartDate, DateOnly? DueDate, decimal? EstimatedHours, long? StageId = null, string? EntityName = null, long? EntityId = null,
    string? RowVersion = null);

public sealed record MoveTaskRequest(long StageId);

public sealed record ProgressRequest(decimal Percent);

public sealed record TitleRequest(string Title);

public sealed record DoneRequest(bool IsDone);

public sealed record LogTimeRequest(DateOnly Date, decimal Hours, string? Note);

// ===================== TÀI LIỆU =====================

public sealed record FolderDto(long Id, string Name, long? ParentId, long? DepartmentId, string? DepartmentName, int DocumentCount);

public sealed record DocumentLookups(IReadOnlyList<FolderDto> Folders, IReadOnlyList<OptionDto> Departments, IReadOnlyList<CodeOption> Types,
    IReadOnlyList<CodeOption> Statuses, long MaxUploadBytes, IReadOnlyList<string> AllowedExtensions);

public sealed record DocumentListItem(long Id, string? Code, string Title, string Type, long? FolderId, string? FolderName, string? PartnerName,
    string Status, DateOnly? EffectiveDate, DateOnly? ExpiryDate, int? DaysToExpiry, bool IsExpiring, decimal? ContractValue, int VersionNo,
    string? FileName, long? SizeBytes, string? OwnerName, DateTime UpdatedAt);

public sealed record DocumentSummary(int Total, int Contracts, int Expiring, int Expired, int PendingSignature, decimal ActiveContractValue);

public sealed record DocumentPage(PagedResult<DocumentListItem> Rows, DocumentSummary Summary);

public sealed record DocumentVersionDto(long Id, int VersionNo, long AttachmentId, string FileName, string ContentType, long SizeBytes, string? Note,
    string? CreatedByName, DateTime CreatedAt);

public sealed record DocumentDetail(long Id, string? Code, string Title, string Type, long? FolderId, string? FolderName, long? PartnerId,
    string? PartnerName, string Status, string RawStatus, DateOnly? EffectiveDate, DateOnly? ExpiryDate, int? DaysToExpiry, bool IsExpiring,
    decimal? ContractValue, string? OwnerName, IReadOnlyList<DocumentVersionDto> Versions, DateTime CreatedAt, bool CanEdit, string RowVersion);

public sealed record SaveDocumentRequest(string Title, string Type, long? FolderId, long? PartnerId, string Status, DateOnly? EffectiveDate,
    DateOnly? ExpiryDate, decimal? ContractValue, string? Code, string? RowVersion = null);

public sealed record SaveFolderRequest(string Name, long? ParentId, long? DepartmentId);

/// <summary>File tải về: nội dung + tên + kiểu.</summary>
public sealed record FileDownload(Stream Content, string FileName, string ContentType);

// ===================== CHAT NỘI BỘ =====================

public sealed record ChatChannelDto(long Id, string Name, string Type, int MemberCount, string? LastMessage, string? LastSenderName,
    DateTime? LastMessageAt, int Unread, long? OtherUserId);

public sealed record ReactionDto(string Reaction, int Count, bool Mine, IReadOnlyList<string> Names);

public sealed record ChatMessageDto(long Id, long ChannelId, long SenderId, string SenderName, string? Body, long? ParentMessageId,
    string? ParentPreview, string? ParentSender, DateTime CreatedAt, bool IsEdited, bool IsDeleted, bool IsMine, IReadOnlyList<ReactionDto> Reactions);

public sealed record ChatMemberDto(long UserId, string FullName, string Role, string? DepartmentName);

public sealed record ChatChannelDetail(long Id, string Name, string Type, bool CanAddMembers, bool CanLeave, IReadOnlyList<ChatMemberDto> Members,
    IReadOnlyList<ChatMessageDto> Messages, bool HasMore);

public sealed record ChatMessagesPage(IReadOnlyList<ChatMessageDto> Messages, bool HasMore);

public sealed record CreateGroupRequest(string Name, IReadOnlyList<long> MemberIds);

public sealed record DirectRequest(long UserId);

public sealed record PostMessageRequest(string Body, long? ParentMessageId);

public sealed record EditMessageRequest(string Body);

public sealed record ReactRequest(string Reaction);

public sealed record AddMembersRequest(IReadOnlyList<long> UserIds);

public sealed record ReadRequest(long MessageId);

public sealed record ChatUnread(int Total, int Channels);

// ===================== WEBSITE =====================

/// <summary>Thông tin hiển thị trên website. ShippingFee / FreeShippingFrom: phí giao hàng và mức đơn được miễn phí (đ).</summary>
public sealed record SiteSettings(string? Slogan, string? Hotline, string? Email, string? Address, string? OpeningHours, string? Facebook,
    string? Instagram, string? TikTok, string? Zalo, string? PrimaryColor, decimal? ShippingFee = null, decimal? FreeShippingFrom = null);

/// <summary>Một website trong danh sách quản trị. Khóa API chỉ hiện vài ký tự đầu (khóa gốc hiện 1 lần lúc tạo).</summary>
public sealed record SiteListItem(long Id, string Name, string Domain, bool IsActive, bool HasApiKey, string? ApiKeyPrefix, DateTime? ApiKeyCreatedAt,
    string? RevalidateUrl, DateTime? LastSyncAt, string? LastSyncStatus, int ProductCount);

public sealed record ApiKeyResult(string Key, string Prefix);

public sealed record WebhookRequest(string? Url, bool NewSecret = false);

public sealed record WebhookResult(string? Url, string? Secret);

public sealed record SyncResult(string Status);

public sealed record SiteDto(long Id, string Name, string Domain, string? LogoUrl, bool IsActive, SiteSettings Settings);

public sealed record SaveSiteRequest(string Name, string Domain, string? LogoUrl, bool IsActive, SiteSettings? Settings);

public sealed record WebContactDto(long Id, string FullName, string? Phone, string? Email, string? Message, string? PageUrl, string? UtmSource,
    string? UtmCampaign, DateTime CreatedAt, long? LeadId, string? LeadCode);

public sealed record WebPostRow(long Id, string Title, long ViewCount, DateTime? PublishedAt);

public sealed record WebsiteOverview(SiteDto? Site, int PublishedModels, int TotalModels, int PublishedPosts, int DraftPosts, int Pages,
    int NewContacts, int ContactsThisMonth, int OnlineOrders30d, decimal OnlineRevenue30d, IReadOnlyList<WebContactDto> RecentContacts,
    IReadOnlyList<WebPostRow> TopPosts);

public sealed record WebPageDto(long Id, string Title, string Slug, string? Content, string? MetaTitle, string? MetaDescription, bool IsPublished,
    DateTime? PublishedAt, DateTime? UpdatedAt);

public sealed record PostListItem(long Id, string Title, string Slug, long? CategoryId, string? CategoryName, string? Summary, string? ThumbnailUrl,
    string? AuthorName, bool IsPublished, DateTime? PublishedAt, long ViewCount, DateTime CreatedAt);

public sealed record PostDetail(long Id, string Title, string Slug, long? CategoryId, string? Summary, string? Content, string? ThumbnailUrl,
    string? MetaTitle, string? MetaDescription, bool IsPublished, DateTime? PublishedAt, long ViewCount);

public sealed record SaveContentRequest(string Title, string? Slug, string? Summary, string? Content, string? ThumbnailUrl, long? CategoryId,
    string? MetaTitle, string? MetaDescription, bool IsPublished);

public sealed record WebProductRow(long ModelId, string Code, string Name, string? CategoryName, decimal SalePrice, int Variants,
    int ActiveVariants, decimal Stock, string? ImageUrl, string? Slug, bool IsPublished, bool IsActive, decimal? PriceOverride, bool IsFeatured);

/// <summary>Bày / ẩn mẫu trên 1 website; PriceOverride = giá riêng cho website này (null = giá bán ở Kho).</summary>
public sealed record WebProductUpdate(bool IsPublished, decimal? PriceOverride = null, bool IsFeatured = false);

public sealed record MenuItemDto(string Label, string Url, bool OpenNewTab);

public sealed record MenuDto(string Code, IReadOnlyList<MenuItemDto> Items);

public sealed record SaveMenuRequest(IReadOnlyList<MenuItemDto> Items);

/// <summary>Form liên hệ công khai trên website. Website (ô ẩn) phải để trống - chặn bot tự điền.</summary>
public sealed record PublicContactRequest(string FullName, string? Phone, string? Email, string? Message, string? PageUrl, string? UtmSource,
    string? UtmMedium, string? UtmCampaign, bool Consent, string? Website = null);

public sealed record PublicCategory(string Slug, string Name, int Count);

public sealed record PublicProduct(string Slug, string Code, string Name, string? Category, string? CategorySlug, decimal Price, decimal? MaxPrice,
    string? ImageUrl, string? Description, IReadOnlyList<string> Colors, IReadOnlyList<string> Sizes, bool InStock, bool IsFeatured);

/// <summary>1 lựa chọn màu - size. Available = số lượng còn bán được (tối đa 99 để không lộ tồn kho thật).</summary>
public sealed record PublicVariant(string Sku, string? Color, string? Size, decimal Price, bool InStock, int Available);

public sealed record PublicProductDetail(string Slug, string Code, string Name, string? Category, string? CategorySlug, decimal Price, decimal? MaxPrice,
    string? ImageUrl, string? Description, string? Material, string? Gender, IReadOnlyList<string> Colors, IReadOnlyList<string> Sizes, bool InStock,
    IReadOnlyList<PublicVariant> Variants, IReadOnlyList<PublicProduct> Related);

public sealed record PublicOrderItem(string Sku, int Quantity);

/// <summary>Đơn đặt từ website. PaymentMethod: cod | bank_transfer. Giá luôn tính lại ở ERP, không lấy giá trình duyệt gửi.</summary>
public sealed record PublicOrderRequest(string CustomerName, string Phone, string? Email, string Address, string? Note, string PaymentMethod,
    string? PromotionCode, IReadOnlyList<PublicOrderItem> Items);

public sealed record PublicOrderLine(string Sku, string Name, int Quantity, decimal UnitPrice, decimal Amount);

public sealed record PublicOrderResult(string OrderNo, IReadOnlyList<PublicOrderLine> Lines, decimal SubTotal, decimal Discount, decimal ShippingFee,
    decimal Total, string PaymentMethod, string Message);

public sealed record PublicPromotion(string Code, string Name, decimal Discount);

public sealed record PublicPost(string Slug, string Title, string? Summary, string? Content, string? ThumbnailUrl, string? Category, DateTime? PublishedAt);

public sealed record PublicSite(string Name, string Domain, string? LogoUrl, SiteSettings Settings, IReadOnlyList<MenuItemDto> Menu,
    IReadOnlyList<MenuItemDto> FooterMenu, IReadOnlyList<PublicCategory> Categories, string? CompanyName, string? TaxCode);
