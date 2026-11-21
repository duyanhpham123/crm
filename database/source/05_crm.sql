/* =====================================================================
   MyERP - 05. CRM (crm): lead, pipeline, cơ hội, hoạt động chăm sóc.
   Luồng: Lead -> (chuyển đổi) -> Partner + Opportunity -> Báo giá -> Đơn hàng
   ===================================================================== */
CREATE SCHEMA crm;
GO

CREATE TABLE crm.LeadSources (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId BIGINT        NOT NULL,
    Code      VARCHAR(30)   NOT NULL,
    Name      NVARCHAR(100) NOT NULL,       -- Website, Facebook Ads, Zalo, Giới thiệu, Hội chợ
    IsActive  BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_LeadSources PRIMARY KEY (Id),
    CONSTRAINT FK_LeadSources_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_LeadSources UNIQUE (CompanyId, Code)
);

CREATE TABLE crm.SalesTeams (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId     BIGINT        NOT NULL,
    Name          NVARCHAR(100) NOT NULL,
    LeaderUserId  BIGINT        NULL,
    MonthlyTarget DECIMAL(18,2) NOT NULL DEFAULT 0,
    IsActive      BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_SalesTeams PRIMARY KEY (Id),
    CONSTRAINT FK_SalesTeams_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_SalesTeams_Leader FOREIGN KEY (LeaderUserId) REFERENCES core.Users(Id)
);
CREATE TABLE crm.SalesTeamMembers (
    TeamId  BIGINT NOT NULL,
    UserId  BIGINT NOT NULL,
    MonthlyTarget DECIMAL(18,2) NOT NULL DEFAULT 0,
    CONSTRAINT PK_SalesTeamMembers PRIMARY KEY (TeamId, UserId),
    CONSTRAINT FK_SalesTeamMembers_Teams FOREIGN KEY (TeamId) REFERENCES crm.SalesTeams(Id) ON DELETE CASCADE,
    CONSTRAINT FK_SalesTeamMembers_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id)
);

CREATE TABLE crm.Pipelines (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId BIGINT        NOT NULL,
    Name      NVARCHAR(100) NOT NULL,
    IsDefault BIT           NOT NULL DEFAULT 0,
    IsActive  BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_Pipelines PRIMARY KEY (Id),
    CONSTRAINT FK_Pipelines_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id)
);
CREATE TABLE crm.Stages (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    PipelineId  BIGINT        NOT NULL,
    Name        NVARCHAR(100) NOT NULL,
    SortOrder   INT           NOT NULL,
    Probability DECIMAL(5,2)  NOT NULL DEFAULT 0,
    StageType   VARCHAR(5)    NOT NULL DEFAULT 'open',
    Color       VARCHAR(10)   NULL,
    CONSTRAINT PK_Stages PRIMARY KEY (Id),
    CONSTRAINT FK_Stages_Pipelines FOREIGN KEY (PipelineId) REFERENCES crm.Pipelines(Id) ON DELETE CASCADE,
    CONSTRAINT CK_Stages_Type CHECK (StageType IN ('open','won','lost')),
    CONSTRAINT CK_Stages_Prob CHECK (Probability BETWEEN 0 AND 100)
);

CREATE TABLE crm.LostReasons (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId BIGINT        NOT NULL,
    Name      NVARCHAR(150) NOT NULL,       -- 'Giá cao', 'Chọn đối thủ', 'Không có ngân sách'
    IsActive  BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_LostReasons PRIMARY KEY (Id),
    CONSTRAINT FK_LostReasons_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id)
);

CREATE TABLE crm.Leads (
    Id                     BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId              BIGINT         NOT NULL,
    Code                   VARCHAR(30)    NOT NULL,
    FullName               NVARCHAR(150)  NOT NULL,
    OrganizationName       NVARCHAR(255)  NULL,
    Position               NVARCHAR(100)  NULL,
    Phone                  VARCHAR(20)    NULL,
    Email                  VARCHAR(255)   NULL,
    Street                 NVARCHAR(255)  NULL,
    ProvinceCode           VARCHAR(10)    NULL,
    SourceId               BIGINT         NULL,
    CampaignId             BIGINT         NULL,      -- FK ở 09_marketing
    UtmSource              VARCHAR(100)   NULL,
    UtmMedium              VARCHAR(100)   NULL,
    UtmCampaign            VARCHAR(100)   NULL,
    InterestNote           NVARCHAR(1000) NULL,
    EstimatedValue         DECIMAL(18,2)  NULL,
    Score                  INT            NOT NULL DEFAULT 0,
    Status                 VARCHAR(12)    NOT NULL DEFAULT 'new',
    OwnerUserId            BIGINT         NULL,
    TeamId                 BIGINT         NULL,
    ConvertedPartnerId     BIGINT         NULL,
    ConvertedOpportunityId BIGINT         NULL,      -- FK thêm sau khi có Opportunities
    ConvertedAt            DATETIME2(3)   NULL,
    DisqualifyReason       NVARCHAR(500)  NULL,
    CreatedAt              DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted              BIT NOT NULL DEFAULT 0,
    RowVersion             ROWVERSION NOT NULL,
    CONSTRAINT PK_Leads PRIMARY KEY (Id),
    CONSTRAINT FK_Leads_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Leads_Provinces FOREIGN KEY (ProvinceCode) REFERENCES md.Provinces(Code),
    CONSTRAINT FK_Leads_Sources FOREIGN KEY (SourceId) REFERENCES crm.LeadSources(Id),
    CONSTRAINT FK_Leads_Owner FOREIGN KEY (OwnerUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Leads_Teams FOREIGN KEY (TeamId) REFERENCES crm.SalesTeams(Id),
    CONSTRAINT FK_Leads_Partner FOREIGN KEY (ConvertedPartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT UQ_Leads_Company_Code UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Leads_Status CHECK (Status IN ('new','contacted','qualified','unqualified','converted'))
);
CREATE INDEX IX_Leads_Owner_Status ON crm.Leads(OwnerUserId, Status) WHERE IsDeleted = 0;
CREATE INDEX IX_Leads_Phone ON crm.Leads(CompanyId, Phone) WHERE Phone IS NOT NULL;   -- chống trùng lead
CREATE INDEX IX_Leads_Email ON crm.Leads(CompanyId, Email) WHERE Email IS NOT NULL;

CREATE TABLE crm.Opportunities (
    Id                BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId         BIGINT         NOT NULL,
    Code              VARCHAR(30)    NOT NULL,
    Name              NVARCHAR(255)  NOT NULL,
    PartnerId         BIGINT         NOT NULL,
    ContactId         BIGINT         NULL,
    LeadId            BIGINT         NULL,
    PipelineId        BIGINT         NOT NULL,
    StageId           BIGINT         NOT NULL,
    ExpectedRevenue   DECIMAL(18,2)  NOT NULL DEFAULT 0,
    Probability       DECIMAL(5,2)   NOT NULL DEFAULT 0,
    WeightedRevenue   AS (CAST(ExpectedRevenue * Probability / 100 AS DECIMAL(18,2))) PERSISTED,
    CurrencyCode      CHAR(3)        NOT NULL DEFAULT 'VND',
    ExpectedCloseDate DATE           NULL,
    Priority          TINYINT        NOT NULL DEFAULT 1,   -- 0..3 sao
    OwnerUserId       BIGINT         NULL,
    TeamId            BIGINT         NULL,
    Status            VARCHAR(5)     NOT NULL DEFAULT 'open',
    LostReasonId      BIGINT         NULL,
    LostNote          NVARCHAR(500)  NULL,
    ClosedAt          DATETIME2(3)   NULL,
    Description       NVARCHAR(MAX)  NULL,
    StageChangedAt    DATETIME2(3)   NULL,
    CreatedAt         DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted         BIT NOT NULL DEFAULT 0,
    RowVersion        ROWVERSION NOT NULL,
    CONSTRAINT PK_Opportunities PRIMARY KEY (Id),
    CONSTRAINT FK_Opportunities_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Opportunities_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_Opportunities_Contacts FOREIGN KEY (ContactId) REFERENCES md.PartnerContacts(Id),
    CONSTRAINT FK_Opportunities_Leads FOREIGN KEY (LeadId) REFERENCES crm.Leads(Id),
    CONSTRAINT FK_Opportunities_Pipelines FOREIGN KEY (PipelineId) REFERENCES crm.Pipelines(Id),
    CONSTRAINT FK_Opportunities_Stages FOREIGN KEY (StageId) REFERENCES crm.Stages(Id),
    CONSTRAINT FK_Opportunities_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT FK_Opportunities_Owner FOREIGN KEY (OwnerUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Opportunities_Teams FOREIGN KEY (TeamId) REFERENCES crm.SalesTeams(Id),
    CONSTRAINT FK_Opportunities_LostReasons FOREIGN KEY (LostReasonId) REFERENCES crm.LostReasons(Id),
    CONSTRAINT UQ_Opportunities_Company_Code UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Opportunities_Status CHECK (Status IN ('open','won','lost')),
    CONSTRAINT CK_Opportunities_Prob CHECK (Probability BETWEEN 0 AND 100),
    CONSTRAINT CK_Opportunities_Revenue CHECK (ExpectedRevenue >= 0)
);
CREATE INDEX IX_Opportunities_Pipeline ON crm.Opportunities(PipelineId, StageId) WHERE IsDeleted = 0;
CREATE INDEX IX_Opportunities_Owner ON crm.Opportunities(OwnerUserId, Status) WHERE IsDeleted = 0;
CREATE INDEX IX_Opportunities_Partner ON crm.Opportunities(PartnerId);

ALTER TABLE crm.Leads ADD CONSTRAINT FK_Leads_Opportunity FOREIGN KEY (ConvertedOpportunityId) REFERENCES crm.Opportunities(Id);

/* Lịch sử chuyển giai đoạn - để đo thời gian mỗi giai đoạn, tỷ lệ chuyển đổi */
CREATE TABLE crm.OpportunityStageHistory (
    Id             BIGINT IDENTITY(1,1) NOT NULL,
    OpportunityId  BIGINT       NOT NULL,
    FromStageId    BIGINT       NULL,
    ToStageId      BIGINT       NOT NULL,
    ChangedAt      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ChangedBy      BIGINT       NULL,
    CONSTRAINT PK_OpportunityStageHistory PRIMARY KEY (Id),
    CONSTRAINT FK_OppStageHistory_Opp FOREIGN KEY (OpportunityId) REFERENCES crm.Opportunities(Id) ON DELETE CASCADE,
    CONSTRAINT FK_OppStageHistory_From FOREIGN KEY (FromStageId) REFERENCES crm.Stages(Id),
    CONSTRAINT FK_OppStageHistory_To FOREIGN KEY (ToStageId) REFERENCES crm.Stages(Id)
);

/* Hoạt động: gọi điện, gặp mặt, email, công việc - gắn được vào bất kỳ đối tượng nào */
CREATE TABLE crm.Activities (
    Id             BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId      BIGINT         NOT NULL,
    ActivityType   VARCHAR(10)    NOT NULL,
    Subject        NVARCHAR(255)  NOT NULL,
    Description    NVARCHAR(MAX)  NULL,
    EntityName     VARCHAR(100)   NOT NULL,     -- 'crm.Leads','crm.Opportunities','md.Partners'
    EntityId       BIGINT         NOT NULL,
    PartnerId      BIGINT         NULL,         -- denormalize để xem nhanh lịch sử theo khách
    ContactId      BIGINT         NULL,
    DueAt          DATETIME2(0)   NULL,
    StartAt        DATETIME2(0)   NULL,
    EndAt          DATETIME2(0)   NULL,
    Location       NVARCHAR(255)  NULL,
    CallDirection  VARCHAR(8)     NULL,         -- inbound | outbound
    CallDurationSec INT           NULL,
    RecordingUrl   VARCHAR(500)   NULL,
    Status         VARCHAR(10)    NOT NULL DEFAULT 'planned',
    Outcome        NVARCHAR(1000) NULL,
    AssignedUserId BIGINT         NULL,
    RemindAt       DATETIME2(0)   NULL,
    CompletedAt    DATETIME2(3)   NULL,
    CreatedAt      DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted      BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_Activities PRIMARY KEY (Id),
    CONSTRAINT FK_Activities_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Activities_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_Activities_Contacts FOREIGN KEY (ContactId) REFERENCES md.PartnerContacts(Id),
    CONSTRAINT FK_Activities_Assigned FOREIGN KEY (AssignedUserId) REFERENCES core.Users(Id),
    CONSTRAINT CK_Activities_Type CHECK (ActivityType IN ('call','meeting','email','task','note','sms','zalo')),
    CONSTRAINT CK_Activities_Status CHECK (Status IN ('planned','done','cancelled')),
    CONSTRAINT CK_Activities_Direction CHECK (CallDirection IS NULL OR CallDirection IN ('inbound','outbound'))
);
CREATE INDEX IX_Activities_Entity ON crm.Activities(EntityName, EntityId) WHERE IsDeleted = 0;
CREATE INDEX IX_Activities_Assigned_Due ON crm.Activities(AssignedUserId, DueAt) WHERE Status = 'planned' AND IsDeleted = 0;
CREATE INDEX IX_Activities_Partner ON crm.Activities(PartnerId, CreatedAt DESC);
GO
