/* =====================================================================
   MyERP - 14. TÀI LIỆU (doc) & CHAT NỘI BỘ (chat)
   ===================================================================== */
CREATE SCHEMA doc;
GO
CREATE SCHEMA chat;
GO

CREATE TABLE doc.Folders (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT        NOT NULL,
    ParentId    BIGINT        NULL,
    Name        NVARCHAR(255) NOT NULL,
    OwnerUserId BIGINT        NULL,
    DepartmentId BIGINT       NULL,          -- thư mục của phòng ban
    Path        VARCHAR(1000) NULL,
    CreatedAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted   BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_Folders PRIMARY KEY (Id),
    CONSTRAINT FK_Folders_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Folders_Parent FOREIGN KEY (ParentId) REFERENCES doc.Folders(Id),
    CONSTRAINT FK_Folders_Owner FOREIGN KEY (OwnerUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Folders_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id)
);

CREATE TABLE doc.Documents (
    Id               BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId        BIGINT        NOT NULL,
    FolderId         BIGINT        NULL,
    Code             VARCHAR(30)   NULL,
    Title            NVARCHAR(255) NOT NULL,
    DocumentType     VARCHAR(12)   NOT NULL DEFAULT 'other',
    PartnerId        BIGINT        NULL,
    EntityName       VARCHAR(100)  NULL,
    EntityId         BIGINT        NULL,
    CurrentVersionNo INT           NOT NULL DEFAULT 1,
    OwnerUserId      BIGINT        NULL,
    Status           VARCHAR(20)   NOT NULL DEFAULT 'draft',
    EffectiveDate    DATE          NULL,
    ExpiryDate       DATE          NULL,      -- nhắc hợp đồng sắp hết hạn
    ContractValue    DECIMAL(18,2) NULL,
    CreatedAt        DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted        BIT NOT NULL DEFAULT 0,
    RowVersion       ROWVERSION NOT NULL,
    CONSTRAINT PK_Documents PRIMARY KEY (Id),
    CONSTRAINT FK_Documents_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Documents_Folders FOREIGN KEY (FolderId) REFERENCES doc.Folders(Id),
    CONSTRAINT FK_Documents_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_Documents_Owner FOREIGN KEY (OwnerUserId) REFERENCES core.Users(Id),
    CONSTRAINT CK_Documents_Type CHECK (DocumentType IN ('contract','policy','process','form','report','other')),
    CONSTRAINT CK_Documents_Status CHECK (Status IN ('draft','pending_signature','signed','active','expired','archived'))
);
CREATE INDEX IX_Documents_Folder ON doc.Documents(FolderId) WHERE IsDeleted = 0;
CREATE INDEX IX_Documents_Expiry ON doc.Documents(ExpiryDate) WHERE ExpiryDate IS NOT NULL AND IsDeleted = 0;

CREATE TABLE doc.DocumentVersions (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    DocumentId   BIGINT        NOT NULL,
    VersionNo    INT           NOT NULL,
    AttachmentId BIGINT        NOT NULL,
    ChangeNote   NVARCHAR(500) NULL,
    CreatedAt    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy    BIGINT        NULL,
    CONSTRAINT PK_DocumentVersions PRIMARY KEY (Id),
    CONSTRAINT FK_DocumentVersions_Documents FOREIGN KEY (DocumentId) REFERENCES doc.Documents(Id) ON DELETE CASCADE,
    CONSTRAINT FK_DocumentVersions_Attachments FOREIGN KEY (AttachmentId) REFERENCES core.Attachments(Id),
    CONSTRAINT UQ_DocumentVersions UNIQUE (DocumentId, VersionNo)
);

/* Chia sẻ: cho user / phòng ban / vai trò */
CREATE TABLE doc.Shares (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    FolderId     BIGINT      NULL,
    DocumentId   BIGINT      NULL,
    UserId       BIGINT      NULL,
    DepartmentId BIGINT      NULL,
    RoleId       BIGINT      NULL,
    Permission   VARCHAR(6)  NOT NULL DEFAULT 'view',
    SharedAt     DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    SharedBy     BIGINT      NULL,
    CONSTRAINT PK_Shares PRIMARY KEY (Id),
    CONSTRAINT FK_Shares_Folders FOREIGN KEY (FolderId) REFERENCES doc.Folders(Id),
    CONSTRAINT FK_Shares_Documents FOREIGN KEY (DocumentId) REFERENCES doc.Documents(Id),
    CONSTRAINT FK_Shares_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Shares_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT FK_Shares_Roles FOREIGN KEY (RoleId) REFERENCES core.Roles(Id),
    CONSTRAINT CK_Shares_Target CHECK ((FolderId IS NOT NULL AND DocumentId IS NULL) OR (FolderId IS NULL AND DocumentId IS NOT NULL)),
    CONSTRAINT CK_Shares_Grantee CHECK (UserId IS NOT NULL OR DepartmentId IS NOT NULL OR RoleId IS NOT NULL),
    CONSTRAINT CK_Shares_Permission CHECK (Permission IN ('view','edit','manage'))
);

/* Ký số / ký điện tử */
CREATE TABLE doc.SignatureRequests (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    DocumentId   BIGINT        NOT NULL,
    SignOrder    INT           NOT NULL DEFAULT 1,
    SignerUserId BIGINT        NULL,          -- người ký nội bộ
    SignerName   NVARCHAR(150) NULL,          -- người ký bên ngoài
    SignerEmail  VARCHAR(255)  NULL,
    Provider     VARCHAR(20)   NULL,          -- vnpt_ca | viettel_ca | fpt_ca | internal
    Status       VARCHAR(10)   NOT NULL DEFAULT 'pending',
    SignedAt     DATETIME2(3)  NULL,
    RejectReason NVARCHAR(500) NULL,
    CONSTRAINT PK_SignatureRequests PRIMARY KEY (Id),
    CONSTRAINT FK_SignatureRequests_Documents FOREIGN KEY (DocumentId) REFERENCES doc.Documents(Id) ON DELETE CASCADE,
    CONSTRAINT FK_SignatureRequests_Users FOREIGN KEY (SignerUserId) REFERENCES core.Users(Id),
    CONSTRAINT CK_SignatureRequests_Status CHECK (Status IN ('pending','signed','rejected','expired')),
    CONSTRAINT CK_SignatureRequests_Signer CHECK (SignerUserId IS NOT NULL OR SignerEmail IS NOT NULL)
);

/* ---------- Chat nội bộ ---------- */
CREATE TABLE chat.Channels (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    Name         NVARCHAR(150) NULL,          -- NULL với chat 1-1
    ChannelType  VARCHAR(10)   NOT NULL,
    DepartmentId BIGINT        NULL,
    EntityName   VARCHAR(100)  NULL,          -- kênh thảo luận gắn với đơn hàng / dự án
    EntityId     BIGINT        NULL,
    IsPrivate    BIT           NOT NULL DEFAULT 1,
    LastMessageAt DATETIME2(3) NULL,
    CreatedAt    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy    BIGINT        NULL,
    IsArchived   BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_Channels PRIMARY KEY (Id),
    CONSTRAINT FK_Channels_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Channels_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT CK_Channels_Type CHECK (ChannelType IN ('direct','group','department','company','entity'))
);

CREATE TABLE chat.Messages (
    Id               BIGINT IDENTITY(1,1) NOT NULL,
    ChannelId        BIGINT        NOT NULL,
    SenderUserId     BIGINT        NOT NULL,
    Body             NVARCHAR(MAX) NULL,
    ParentMessageId  BIGINT        NULL,      -- trả lời theo luồng
    AttachmentId     BIGINT        NULL,
    IsEdited         BIT           NOT NULL DEFAULT 0,
    EditedAt         DATETIME2(3)  NULL,
    IsDeleted        BIT           NOT NULL DEFAULT 0,
    CreatedAt        DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Messages PRIMARY KEY (Id),
    CONSTRAINT FK_Messages_Channels FOREIGN KEY (ChannelId) REFERENCES chat.Channels(Id),
    CONSTRAINT FK_Messages_Users FOREIGN KEY (SenderUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Messages_Parent FOREIGN KEY (ParentMessageId) REFERENCES chat.Messages(Id),
    CONSTRAINT FK_Messages_Attachments FOREIGN KEY (AttachmentId) REFERENCES core.Attachments(Id),
    CONSTRAINT CK_Messages_Content CHECK (Body IS NOT NULL OR AttachmentId IS NOT NULL)
);
CREATE INDEX IX_Messages_Channel ON chat.Messages(ChannelId, Id DESC);

CREATE TABLE chat.ChannelMembers (
    ChannelId         BIGINT       NOT NULL,
    UserId            BIGINT       NOT NULL,
    MemberRole        VARCHAR(6)   NOT NULL DEFAULT 'member',
    LastReadMessageId BIGINT       NULL,      -- tính số tin chưa đọc
    IsMuted           BIT          NOT NULL DEFAULT 0,
    JoinedAt          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ChannelMembers PRIMARY KEY (ChannelId, UserId),
    CONSTRAINT FK_ChannelMembers_Channels FOREIGN KEY (ChannelId) REFERENCES chat.Channels(Id) ON DELETE CASCADE,
    CONSTRAINT FK_ChannelMembers_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id),
    CONSTRAINT CK_ChannelMembers_Role CHECK (MemberRole IN ('owner','admin','member'))
);
CREATE INDEX IX_ChannelMembers_User ON chat.ChannelMembers(UserId);

CREATE TABLE chat.MessageReactions (
    MessageId  BIGINT       NOT NULL,
    UserId     BIGINT       NOT NULL,
    Reaction   NVARCHAR(10) NOT NULL,
    CreatedAt  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_MessageReactions PRIMARY KEY (MessageId, UserId, Reaction),
    CONSTRAINT FK_MessageReactions_Messages FOREIGN KEY (MessageId) REFERENCES chat.Messages(Id) ON DELETE CASCADE,
    CONSTRAINT FK_MessageReactions_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id)
);
GO
