using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MyERP.Api.Models.Entities.Chat;
using MyERP.Api.Models.Entities.Documents;
using MyERP.Api.Models.Entities.Projects;
using MyERP.Api.Models.Entities.Website;

namespace MyERP.Api.Data.Configurations;

// Map entity Dự án / Tài liệu / Chat / Website vào các bảng prj, doc, chat, web, core.Attachments.

internal sealed class ApiTokenConfiguration : IEntityTypeConfiguration<MyERP.Api.Models.Entities.Core.ApiToken>
{
    public void Configure(EntityTypeBuilder<MyERP.Api.Models.Entities.Core.ApiToken> e)
    {
        e.ToTable("ApiTokens", "core");
        e.Property(x => x.TokenHash).HasColumnType("char(64)");
        e.Property(x => x.Prefix).HasMaxLength(16).IsUnicode(false);
        e.Property(x => x.LastUsedIp).HasMaxLength(45).IsUnicode(false);
    }
}

internal sealed class ProjectConfiguration : IEntityTypeConfiguration<Project>
{
    public void Configure(EntityTypeBuilder<Project> e)
    {
        e.ToTable("Projects", "prj");
        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false);
        e.Property(x => x.Status).HasMaxLength(10).IsUnicode(false);
        e.Property(x => x.ProgressPercent).HasPrecision(5, 2);
        e.Property(x => x.Budget).HasPrecision(18, 2);
        e.Ignore(x => x.IsClosed);
        e.HasMany(x => x.Members).WithOne().HasForeignKey(x => x.ProjectId);
    }
}

internal sealed class ProjectMemberConfiguration : IEntityTypeConfiguration<ProjectMember>
{
    public void Configure(EntityTypeBuilder<ProjectMember> e)
    {
        e.ToTable("ProjectMembers", "prj");
        e.HasKey(x => new { x.ProjectId, x.UserId });
        e.Property(x => x.MemberRole).HasMaxLength(10).IsUnicode(false);
    }
}

internal sealed class TaskStageConfiguration : IEntityTypeConfiguration<TaskStage>
{
    public void Configure(EntityTypeBuilder<TaskStage> e) => e.ToTable("TaskStages", "prj");
}

internal sealed class ProjectTaskConfiguration : IEntityTypeConfiguration<ProjectTask>
{
    public void Configure(EntityTypeBuilder<ProjectTask> e)
    {
        e.ToTable("Tasks", "prj");
        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false);
        e.Property(x => x.Priority).HasMaxLength(8).IsUnicode(false);
        e.Property(x => x.EntityName).HasMaxLength(100).IsUnicode(false);
        e.Property(x => x.DueDate).HasColumnType("datetime2(0)");
        e.Property(x => x.ProgressPercent).HasPrecision(5, 2);
        e.Property(x => x.EstimatedHours).HasPrecision(8, 2);
        e.Ignore(x => x.IsDone);
        e.Ignore(x => x.DueDay);
        e.HasMany(x => x.Checklist).WithOne().HasForeignKey(x => x.TaskId);
    }
}

internal sealed class TaskChecklistItemConfiguration : IEntityTypeConfiguration<TaskChecklistItem>
{
    public void Configure(EntityTypeBuilder<TaskChecklistItem> e) => e.ToTable("TaskChecklistItems", "prj");
}

internal sealed class TimesheetConfiguration : IEntityTypeConfiguration<Timesheet>
{
    public void Configure(EntityTypeBuilder<Timesheet> e)
    {
        e.ToTable("Timesheets", "prj");
        e.Property(x => x.Hours).HasPrecision(5, 2);
    }
}

internal sealed class AttachmentConfiguration : IEntityTypeConfiguration<Attachment>
{
    public void Configure(EntityTypeBuilder<Attachment> e)
    {
        e.ToTable("Attachments", "core");
        e.Property(x => x.EntityName).HasMaxLength(100).IsUnicode(false);
        e.Property(x => x.ContentType).HasMaxLength(100).IsUnicode(false);
        e.Property(x => x.StorageProvider).HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.StoragePath).HasMaxLength(1000).IsUnicode(false);
        e.Property(x => x.Checksum).HasMaxLength(64).IsUnicode(false);
    }
}

internal sealed class FolderConfiguration : IEntityTypeConfiguration<Folder>
{
    public void Configure(EntityTypeBuilder<Folder> e)
    {
        e.ToTable("Folders", "doc");
        e.Property(x => x.Path).HasMaxLength(1000).IsUnicode(false);
    }
}

internal sealed class DocumentConfiguration : IEntityTypeConfiguration<Document>
{
    public void Configure(EntityTypeBuilder<Document> e)
    {
        e.ToTable("Documents", "doc");
        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false);
        e.Property(x => x.DocumentType).HasMaxLength(12).IsUnicode(false);
        e.Property(x => x.Status).HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.EntityName).HasMaxLength(100).IsUnicode(false);
        e.Property(x => x.ContractValue).HasPrecision(18, 2);
        e.HasMany(x => x.Versions).WithOne().HasForeignKey(x => x.DocumentId);
    }
}

internal sealed class DocumentVersionConfiguration : IEntityTypeConfiguration<DocumentVersion>
{
    public void Configure(EntityTypeBuilder<DocumentVersion> e) => e.ToTable("DocumentVersions", "doc");
}

internal sealed class ChannelConfiguration : IEntityTypeConfiguration<Channel>
{
    public void Configure(EntityTypeBuilder<Channel> e)
    {
        e.ToTable("Channels", "chat");
        e.Property(x => x.ChannelType).HasMaxLength(10).IsUnicode(false);
        e.Property(x => x.EntityName).HasMaxLength(100).IsUnicode(false);
        e.HasMany(x => x.Members).WithOne().HasForeignKey(x => x.ChannelId);
    }
}

internal sealed class ChannelMemberConfiguration : IEntityTypeConfiguration<ChannelMember>
{
    public void Configure(EntityTypeBuilder<ChannelMember> e)
    {
        e.ToTable("ChannelMembers", "chat");
        e.HasKey(x => new { x.ChannelId, x.UserId });
        e.Property(x => x.MemberRole).HasMaxLength(6).IsUnicode(false);
    }
}

internal sealed class MessageConfiguration : IEntityTypeConfiguration<Message>
{
    public void Configure(EntityTypeBuilder<Message> e)
    {
        e.ToTable("Messages", "chat");
        e.HasMany(x => x.Reactions).WithOne().HasForeignKey(x => x.MessageId);
    }
}

internal sealed class MessageReactionConfiguration : IEntityTypeConfiguration<MessageReaction>
{
    public void Configure(EntityTypeBuilder<MessageReaction> e)
    {
        e.ToTable("MessageReactions", "chat");
        e.HasKey(x => new { x.MessageId, x.UserId, x.Reaction });
        e.Property(x => x.Reaction).HasMaxLength(10);
    }
}

internal sealed class SiteConfiguration : IEntityTypeConfiguration<Site>
{
    public void Configure(EntityTypeBuilder<Site> e)
    {
        e.ToTable("Sites", "web");
        e.Property(x => x.Domain).HasMaxLength(255).IsUnicode(false);
        e.Property(x => x.DefaultLanguage).HasMaxLength(10).IsUnicode(false);
        e.Property(x => x.LogoUrl).HasMaxLength(500).IsUnicode(false);
        e.Property(x => x.FaviconUrl).HasMaxLength(500).IsUnicode(false);
        e.Property(x => x.ApiKeyHash).HasColumnType("char(64)");
        e.Property(x => x.ApiKeyPrefix).HasMaxLength(16).IsUnicode(false);
        e.Property(x => x.RevalidateUrl).HasMaxLength(500).IsUnicode(false);
        e.Property(x => x.RevalidateSecret).HasMaxLength(100).IsUnicode(false);
        e.Property(x => x.LastSyncStatus).HasMaxLength(300);
    }
}

internal sealed class SiteProductConfiguration : IEntityTypeConfiguration<SiteProduct>
{
    public void Configure(EntityTypeBuilder<SiteProduct> e)
    {
        e.ToTable("SiteProducts", "web");
        e.HasKey(x => new { x.SiteId, x.ModelId });
        e.Property(x => x.PriceOverride).HasPrecision(18, 2);
    }
}

internal sealed class WebCartConfiguration : IEntityTypeConfiguration<WebCart>
{
    public void Configure(EntityTypeBuilder<WebCart> e)
    {
        e.ToTable("Carts", "web");
        e.Property(x => x.SessionKey).HasMaxLength(100).IsUnicode(false);
        e.Property(x => x.PromotionCode).HasMaxLength(30).IsUnicode(false);
        e.Property(x => x.Status).HasMaxLength(10).IsUnicode(false);
    }
}

internal sealed class WebPageConfiguration : IEntityTypeConfiguration<WebPage>
{
    public void Configure(EntityTypeBuilder<WebPage> e)
    {
        e.ToTable("Pages", "web");
        e.Property(x => x.Slug).HasMaxLength(255).IsUnicode(false);
    }
}

internal sealed class PostCategoryConfiguration : IEntityTypeConfiguration<PostCategory>
{
    public void Configure(EntityTypeBuilder<PostCategory> e)
    {
        e.ToTable("PostCategories", "web");
        e.Property(x => x.Slug).HasMaxLength(255).IsUnicode(false);
    }
}

internal sealed class PostConfiguration : IEntityTypeConfiguration<Post>
{
    public void Configure(EntityTypeBuilder<Post> e)
    {
        e.ToTable("Posts", "web");
        e.Property(x => x.Slug).HasMaxLength(255).IsUnicode(false);
        e.Property(x => x.ThumbnailUrl).HasMaxLength(500).IsUnicode(false);
    }
}

internal sealed class MenuConfiguration : IEntityTypeConfiguration<Menu>
{
    public void Configure(EntityTypeBuilder<Menu> e)
    {
        e.ToTable("Menus", "web");
        e.Property(x => x.Code).HasMaxLength(30).IsUnicode(false);
        e.HasMany(x => x.Items).WithOne().HasForeignKey(x => x.MenuId);
    }
}

internal sealed class MenuItemConfiguration : IEntityTypeConfiguration<MenuItem>
{
    public void Configure(EntityTypeBuilder<MenuItem> e)
    {
        e.ToTable("MenuItems", "web");
        e.Property(x => x.Url).HasMaxLength(500).IsUnicode(false);
    }
}

internal sealed class ContactSubmissionConfiguration : IEntityTypeConfiguration<ContactSubmission>
{
    public void Configure(EntityTypeBuilder<ContactSubmission> e)
    {
        e.ToTable("ContactSubmissions", "web");
        e.Property(x => x.FormCode).HasMaxLength(30).IsUnicode(false);
        e.Property(x => x.Phone).HasMaxLength(20).IsUnicode(false);
        e.Property(x => x.Email).HasMaxLength(255).IsUnicode(false);
        e.Property(x => x.PageUrl).HasMaxLength(1000).IsUnicode(false);
        e.Property(x => x.IpAddress).HasMaxLength(45).IsUnicode(false);
    }
}
