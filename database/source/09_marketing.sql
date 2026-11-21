/* =====================================================================
   MyERP - 09. MARKETING (mkt): chiến dịch, phân khúc, mẫu tin nhắn,
   gửi email/SMS/Zalo, quản lý đồng ý nhận tin (Nghị định 13/2023/NĐ-CP).
   ===================================================================== */
CREATE SCHEMA mkt;
GO

CREATE TABLE mkt.Campaigns (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    Code         VARCHAR(30)   NOT NULL,
    Name         NVARCHAR(200) NOT NULL,
    Channel      VARCHAR(12)   NOT NULL,
    StartDate    DATE          NOT NULL,
    EndDate      DATE          NULL,
    Budget       DECIMAL(18,2) NOT NULL DEFAULT 0,
    ActualCost   DECIMAL(18,2) NOT NULL DEFAULT 0,
    TargetLeads  INT           NULL,
    UtmSource    VARCHAR(100)  NULL,
    UtmMedium    VARCHAR(100)  NULL,
    UtmCampaign  VARCHAR(100)  NULL,
    Status       VARCHAR(10)   NOT NULL DEFAULT 'draft',
    OwnerUserId  BIGINT        NULL,
    Description  NVARCHAR(MAX) NULL,
    CreatedAt    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted    BIT NOT NULL DEFAULT 0,
    RowVersion   ROWVERSION NOT NULL,
    CONSTRAINT PK_Campaigns PRIMARY KEY (Id),
    CONSTRAINT FK_Campaigns_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Campaigns_Owner FOREIGN KEY (OwnerUserId) REFERENCES core.Users(Id),
    CONSTRAINT UQ_Campaigns UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Campaigns_Channel CHECK (Channel IN ('facebook','google','tiktok','zalo','email','sms','seo','event','offline','other')),
    CONSTRAINT CK_Campaigns_Status CHECK (Status IN ('draft','running','paused','completed','cancelled')),
    CONSTRAINT CK_Campaigns_Dates CHECK (EndDate IS NULL OR EndDate >= StartDate)
);

ALTER TABLE crm.Leads ADD CONSTRAINT FK_Leads_Campaigns FOREIGN KEY (CampaignId) REFERENCES mkt.Campaigns(Id);
CREATE INDEX IX_Leads_Campaign ON crm.Leads(CampaignId) WHERE CampaignId IS NOT NULL;

/* Mã giảm giá thuộc chiến dịch nào -> tính doanh thu, ROI của chiến dịch */
ALTER TABLE sales.Promotions ADD CampaignId BIGINT NULL CONSTRAINT FK_Promotions_Campaigns REFERENCES mkt.Campaigns(Id);

/* Chi phí theo ngày (nhập tay hoặc đồng bộ từ Facebook/Google Ads) */
CREATE TABLE mkt.CampaignDailyStats (
    CampaignId   BIGINT        NOT NULL,
    StatDate     DATE          NOT NULL,
    Impressions  BIGINT        NOT NULL DEFAULT 0,
    Clicks       BIGINT        NOT NULL DEFAULT 0,
    Spend        DECIMAL(18,2) NOT NULL DEFAULT 0,
    Leads        INT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_CampaignDailyStats PRIMARY KEY (CampaignId, StatDate),
    CONSTRAINT FK_CampaignDailyStats_Campaigns FOREIGN KEY (CampaignId) REFERENCES mkt.Campaigns(Id) ON DELETE CASCADE
);

CREATE TABLE mkt.Segments (
    Id               BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId        BIGINT        NOT NULL,
    Name             NVARCHAR(150) NOT NULL,
    TargetType       VARCHAR(10)   NOT NULL DEFAULT 'partner',  -- partner | lead
    IsDynamic        BIT           NOT NULL DEFAULT 1,          -- tự cập nhật theo bộ lọc
    FilterDefinition NVARCHAR(MAX) NULL,                        -- JSON điều kiện lọc
    MemberCount      INT           NOT NULL DEFAULT 0,
    LastRefreshedAt  DATETIME2(3)  NULL,
    CreatedAt        DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_Segments PRIMARY KEY (Id),
    CONSTRAINT FK_Segments_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT CK_Segments_Target CHECK (TargetType IN ('partner','lead')),
    CONSTRAINT CK_Segments_Json CHECK (FilterDefinition IS NULL OR ISJSON(FilterDefinition) = 1)
);
CREATE TABLE mkt.SegmentMembers (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    SegmentId  BIGINT NOT NULL,
    PartnerId  BIGINT NULL,
    LeadId     BIGINT NULL,
    AddedAt    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_SegmentMembers PRIMARY KEY (Id),
    CONSTRAINT FK_SegmentMembers_Segments FOREIGN KEY (SegmentId) REFERENCES mkt.Segments(Id) ON DELETE CASCADE,
    CONSTRAINT FK_SegmentMembers_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_SegmentMembers_Leads FOREIGN KEY (LeadId) REFERENCES crm.Leads(Id),
    CONSTRAINT CK_SegmentMembers_Target CHECK ((PartnerId IS NOT NULL AND LeadId IS NULL) OR (PartnerId IS NULL AND LeadId IS NOT NULL))
);
CREATE INDEX IX_SegmentMembers_Segment ON mkt.SegmentMembers(SegmentId);

CREATE TABLE mkt.MessageTemplates (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId  BIGINT        NOT NULL,
    Channel    VARCHAR(8)    NOT NULL,
    Name       NVARCHAR(150) NOT NULL,
    Subject    NVARCHAR(255) NULL,
    Body       NVARCHAR(MAX) NOT NULL,        -- hỗ trợ biến {{customer_name}}
    ZaloTemplateId VARCHAR(50) NULL,          -- ZNS template đã duyệt
    IsActive   BIT           NOT NULL DEFAULT 1,
    CreatedAt  DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_MessageTemplates PRIMARY KEY (Id),
    CONSTRAINT FK_MessageTemplates_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT CK_MessageTemplates_Channel CHECK (Channel IN ('email','sms','zalo'))
);

CREATE TABLE mkt.MessageBlasts (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    CampaignId   BIGINT        NULL,
    TemplateId   BIGINT        NOT NULL,
    SegmentId    BIGINT        NOT NULL,
    Name         NVARCHAR(200) NOT NULL,
    ScheduledAt  DATETIME2(0)  NULL,
    StartedAt    DATETIME2(3)  NULL,
    FinishedAt   DATETIME2(3)  NULL,
    Status       VARCHAR(10)   NOT NULL DEFAULT 'draft',
    TotalRecipients INT        NOT NULL DEFAULT 0,
    SentCount    INT           NOT NULL DEFAULT 0,
    OpenCount    INT           NOT NULL DEFAULT 0,
    ClickCount   INT           NOT NULL DEFAULT 0,
    CreatedAt    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_MessageBlasts PRIMARY KEY (Id),
    CONSTRAINT FK_MessageBlasts_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_MessageBlasts_Campaigns FOREIGN KEY (CampaignId) REFERENCES mkt.Campaigns(Id),
    CONSTRAINT FK_MessageBlasts_Templates FOREIGN KEY (TemplateId) REFERENCES mkt.MessageTemplates(Id),
    CONSTRAINT FK_MessageBlasts_Segments FOREIGN KEY (SegmentId) REFERENCES mkt.Segments(Id),
    CONSTRAINT CK_MessageBlasts_Status CHECK (Status IN ('draft','scheduled','sending','sent','cancelled'))
);
CREATE TABLE mkt.MessageRecipients (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    BlastId     BIGINT        NOT NULL,
    PartnerId   BIGINT        NULL,
    LeadId      BIGINT        NULL,
    Address     VARCHAR(255)  NOT NULL,       -- email hoặc số điện thoại
    Status      VARCHAR(12)   NOT NULL DEFAULT 'queued',
    SentAt      DATETIME2(3)  NULL,
    OpenedAt    DATETIME2(3)  NULL,
    ClickedAt   DATETIME2(3)  NULL,
    ErrorMessage NVARCHAR(500) NULL,
    ProviderMessageId VARCHAR(100) NULL,
    CONSTRAINT PK_MessageRecipients PRIMARY KEY (Id),
    CONSTRAINT FK_MessageRecipients_Blasts FOREIGN KEY (BlastId) REFERENCES mkt.MessageBlasts(Id) ON DELETE CASCADE,
    CONSTRAINT FK_MessageRecipients_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_MessageRecipients_Leads FOREIGN KEY (LeadId) REFERENCES crm.Leads(Id),
    CONSTRAINT CK_MessageRecipients_Status CHECK (Status IN ('queued','sent','delivered','opened','clicked','bounced','failed','unsubscribed'))
);
CREATE INDEX IX_MessageRecipients_Blast ON mkt.MessageRecipients(BlastId, Status);

/* Đồng ý / từ chối nhận tin - bắt buộc theo luật bảo vệ dữ liệu cá nhân */
CREATE TABLE mkt.Consents (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT        NOT NULL,
    Address     VARCHAR(255)  NOT NULL,       -- email / số điện thoại
    Channel     VARCHAR(8)    NOT NULL,
    PartnerId   BIGINT        NULL,
    LeadId      BIGINT        NULL,
    IsGranted   BIT           NOT NULL,
    Source      NVARCHAR(150) NULL,           -- 'Form website', 'Link hủy đăng ký'
    IpAddress   VARCHAR(45)   NULL,
    ChangedAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Consents PRIMARY KEY (Id),
    CONSTRAINT FK_Consents_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Consents_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_Consents_Leads FOREIGN KEY (LeadId) REFERENCES crm.Leads(Id),
    CONSTRAINT UQ_Consents UNIQUE (CompanyId, Address, Channel),
    CONSTRAINT CK_Consents_Channel CHECK (Channel IN ('email','sms','zalo','call'))
);
GO
