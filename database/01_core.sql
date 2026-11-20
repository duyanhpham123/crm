/* =====================================================================
   MyERP - 01. CORE: công ty, chi nhánh, phòng ban, người dùng,
   phân quyền, ứng dụng, đánh số chứng từ, audit, file, thông báo,
   duyệt, outbox (sự kiện liên module).
   ===================================================================== */
CREATE SCHEMA core;
GO

/* ---------- Công ty (multi-company) ---------- */
CREATE TABLE core.Companies (
    Id                    BIGINT IDENTITY(1,1) NOT NULL,
    Code                  VARCHAR(20)    NOT NULL,
    Name                  NVARCHAR(255)  NOT NULL,
    ShortName             NVARCHAR(100)  NULL,
    TaxCode               VARCHAR(20)    NULL,
    Address               NVARCHAR(500)  NULL,
    Phone                 VARCHAR(20)    NULL,
    Email                 VARCHAR(255)   NULL,
    Website               VARCHAR(255)   NULL,
    LogoUrl               VARCHAR(500)   NULL,
    LegalRepresentative   NVARCHAR(150)  NULL,
    CurrencyCode          CHAR(3)        NOT NULL DEFAULT 'VND',
    AccountingRegime      VARCHAR(10)    NOT NULL DEFAULT 'TT200',
    FiscalYearStartMonth  TINYINT        NOT NULL DEFAULT 1,
    TimeZone              VARCHAR(50)    NOT NULL DEFAULT 'SE Asia Standard Time',
    IsActive              BIT            NOT NULL DEFAULT 1,
    CreatedAt             DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy             BIGINT         NULL,
    UpdatedAt             DATETIME2(3)   NULL,
    UpdatedBy             BIGINT         NULL,
    IsDeleted             BIT            NOT NULL DEFAULT 0,
    RowVersion            ROWVERSION     NOT NULL,
    CONSTRAINT PK_Companies PRIMARY KEY (Id),
    CONSTRAINT UQ_Companies_Code UNIQUE (Code),
    CONSTRAINT CK_Companies_Regime CHECK (AccountingRegime IN ('TT200','TT133')),
    CONSTRAINT CK_Companies_FyMonth CHECK (FiscalYearStartMonth BETWEEN 1 AND 12)
);

CREATE TABLE core.Branches (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT         NOT NULL,
    Code        VARCHAR(20)    NOT NULL,
    Name        NVARCHAR(255)  NOT NULL,
    Address     NVARCHAR(500)  NULL,
    Phone       VARCHAR(20)    NULL,
    IsHeadOffice BIT           NOT NULL DEFAULT 0,
    IsActive    BIT            NOT NULL DEFAULT 1,
    CreatedAt   DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy   BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted   BIT NOT NULL DEFAULT 0,
    RowVersion  ROWVERSION NOT NULL,
    CONSTRAINT PK_Branches PRIMARY KEY (Id),
    CONSTRAINT FK_Branches_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_Branches_Company_Code UNIQUE (CompanyId, Code)
);

/* ---------- Người dùng (tương thích ASP.NET Core Identity) ---------- */
CREATE TABLE core.Users (
    Id                  BIGINT IDENTITY(1,1) NOT NULL,
    UserName            NVARCHAR(100)  NOT NULL,
    NormalizedUserName  NVARCHAR(100)  NOT NULL,
    Email               NVARCHAR(255)  NULL,
    NormalizedEmail     NVARCHAR(255)  NULL,
    EmailConfirmed      BIT            NOT NULL DEFAULT 0,
    PasswordHash        NVARCHAR(500)  NULL,
    SecurityStamp       NVARCHAR(100)  NULL,
    ConcurrencyStamp    NVARCHAR(100)  NULL,
    PhoneNumber         VARCHAR(20)    NULL,
    PhoneNumberConfirmed BIT           NOT NULL DEFAULT 0,
    TwoFactorEnabled    BIT            NOT NULL DEFAULT 0,
    LockoutEnd          DATETIMEOFFSET NULL,
    LockoutEnabled      BIT            NOT NULL DEFAULT 1,
    AccessFailedCount   INT            NOT NULL DEFAULT 0,
    FullName            NVARCHAR(150)  NOT NULL,
    AvatarUrl           VARCHAR(500)   NULL,
    DefaultCompanyId    BIGINT         NULL,
    Language            VARCHAR(10)    NOT NULL DEFAULT 'vi',
    IsSystemAdmin       BIT            NOT NULL DEFAULT 0,
    IsActive            BIT            NOT NULL DEFAULT 1,
    LastLoginAt         DATETIME2(3)   NULL,
    CreatedAt           DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted           BIT NOT NULL DEFAULT 0,
    RowVersion          ROWVERSION NOT NULL,
    CONSTRAINT PK_Users PRIMARY KEY (Id),
    CONSTRAINT UQ_Users_NormalizedUserName UNIQUE (NormalizedUserName),
    CONSTRAINT FK_Users_Companies FOREIGN KEY (DefaultCompanyId) REFERENCES core.Companies(Id)
);
CREATE UNIQUE INDEX UX_Users_NormalizedEmail ON core.Users(NormalizedEmail) WHERE NormalizedEmail IS NOT NULL AND IsDeleted = 0;

CREATE TABLE core.RefreshTokens (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    UserId          BIGINT        NOT NULL,
    TokenHash       VARCHAR(128)  NOT NULL,   -- chỉ lưu hash, không lưu token gốc
    ExpiresAt       DATETIME2(3)  NOT NULL,
    CreatedAt       DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedByIp     VARCHAR(45)   NULL,
    UserAgent       NVARCHAR(500) NULL,
    RevokedAt       DATETIME2(3)  NULL,
    RevokedByIp     VARCHAR(45)   NULL,
    ReplacedByTokenHash VARCHAR(128) NULL,
    CONSTRAINT PK_RefreshTokens PRIMARY KEY (Id),
    CONSTRAINT FK_RefreshTokens_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id) ON DELETE CASCADE,
    CONSTRAINT UQ_RefreshTokens_Hash UNIQUE (TokenHash)
);
CREATE INDEX IX_RefreshTokens_User ON core.RefreshTokens(UserId);

CREATE TABLE core.UserLogins (          -- đăng nhập ngoài: Google, Microsoft...
    LoginProvider   NVARCHAR(100) NOT NULL,
    ProviderKey     NVARCHAR(200) NOT NULL,
    ProviderDisplayName NVARCHAR(100) NULL,
    UserId          BIGINT NOT NULL,
    CONSTRAINT PK_UserLogins PRIMARY KEY (LoginProvider, ProviderKey),
    CONSTRAINT FK_UserLogins_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id) ON DELETE CASCADE
);

/* ---------- Phòng ban (cây) ---------- */
CREATE TABLE core.Departments (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT         NOT NULL,
    BranchId        BIGINT         NULL,
    ParentId        BIGINT         NULL,
    Code            VARCHAR(20)    NOT NULL,
    Name            NVARCHAR(255)  NOT NULL,
    ManagerUserId   BIGINT         NULL,
    Path            VARCHAR(500)   NULL,      -- '/1/5/12/' để truy vấn cây nhanh
    SortOrder       INT            NOT NULL DEFAULT 0,
    IsActive        BIT            NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted       BIT NOT NULL DEFAULT 0,
    RowVersion      ROWVERSION NOT NULL,
    CONSTRAINT PK_Departments PRIMARY KEY (Id),
    CONSTRAINT FK_Departments_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Departments_Branches FOREIGN KEY (BranchId) REFERENCES core.Branches(Id),
    CONSTRAINT FK_Departments_Parent FOREIGN KEY (ParentId) REFERENCES core.Departments(Id),
    CONSTRAINT FK_Departments_Manager FOREIGN KEY (ManagerUserId) REFERENCES core.Users(Id),
    CONSTRAINT UQ_Departments_Company_Code UNIQUE (CompanyId, Code)
);
CREATE INDEX IX_Departments_Parent ON core.Departments(ParentId);

/* Người dùng được truy cập công ty nào, thuộc chi nhánh/phòng ban nào */
CREATE TABLE core.UserCompanies (
    UserId        BIGINT NOT NULL,
    CompanyId     BIGINT NOT NULL,
    BranchId      BIGINT NULL,
    DepartmentId  BIGINT NULL,
    IsDefault     BIT    NOT NULL DEFAULT 0,
    CONSTRAINT PK_UserCompanies PRIMARY KEY (UserId, CompanyId),
    CONSTRAINT FK_UserCompanies_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id) ON DELETE CASCADE,
    CONSTRAINT FK_UserCompanies_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_UserCompanies_Branches FOREIGN KEY (BranchId) REFERENCES core.Branches(Id),
    CONSTRAINT FK_UserCompanies_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id)
);

/* ---------- Ứng dụng trên màn hình lưới (launcher) ---------- */
CREATE TABLE core.Apps (
    Id          INT IDENTITY(1,1) NOT NULL,
    Code        VARCHAR(30)   NOT NULL,      -- 'crm','sales','inventory','accounting'...
    Name        NVARCHAR(100) NOT NULL,
    Icon        VARCHAR(50)   NULL,
    Color       VARCHAR(10)   NULL,
    Route       VARCHAR(100)  NULL,
    SortOrder   INT           NOT NULL DEFAULT 0,
    IsEnabled   BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_Apps PRIMARY KEY (Id),
    CONSTRAINT UQ_Apps_Code UNIQUE (Code)
);

/* Công ty nào bật ứng dụng nào (bán theo gói) */
CREATE TABLE core.CompanyApps (
    CompanyId   BIGINT NOT NULL,
    AppId       INT    NOT NULL,
    IsEnabled   BIT    NOT NULL DEFAULT 1,
    EnabledAt   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_CompanyApps PRIMARY KEY (CompanyId, AppId),
    CONSTRAINT FK_CompanyApps_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_CompanyApps_Apps FOREIGN KEY (AppId) REFERENCES core.Apps(Id)
);

/* ---------- Phân quyền RBAC + phạm vi dữ liệu ---------- */
CREATE TABLE core.Permissions (
    Id          INT IDENTITY(1,1) NOT NULL,
    AppId       INT           NOT NULL,
    Code        VARCHAR(100)  NOT NULL,      -- 'sales.quotation.approve'
    Name        NVARCHAR(200) NOT NULL,
    Description NVARCHAR(500) NULL,
    CONSTRAINT PK_Permissions PRIMARY KEY (Id),
    CONSTRAINT FK_Permissions_Apps FOREIGN KEY (AppId) REFERENCES core.Apps(Id),
    CONSTRAINT UQ_Permissions_Code UNIQUE (Code)
);

CREATE TABLE core.Roles (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT        NULL,      -- NULL = vai trò hệ thống dùng chung
    Code            VARCHAR(50)   NOT NULL,
    Name            NVARCHAR(100) NOT NULL,
    NormalizedName  NVARCHAR(100) NOT NULL,
    Description     NVARCHAR(500) NULL,
    IsSystem        BIT           NOT NULL DEFAULT 0,
    CreatedAt       DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted       BIT NOT NULL DEFAULT 0,
    RowVersion      ROWVERSION NOT NULL,
    CONSTRAINT PK_Roles PRIMARY KEY (Id),
    CONSTRAINT FK_Roles_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_Roles_Company_Code UNIQUE (CompanyId, Code)
);

CREATE TABLE core.RolePermissions (
    RoleId        BIGINT      NOT NULL,
    PermissionId  INT         NOT NULL,
    DataScope     VARCHAR(20) NOT NULL DEFAULT 'own',   -- phạm vi dữ liệu được thấy
    CONSTRAINT PK_RolePermissions PRIMARY KEY (RoleId, PermissionId),
    CONSTRAINT FK_RolePermissions_Roles FOREIGN KEY (RoleId) REFERENCES core.Roles(Id) ON DELETE CASCADE,
    CONSTRAINT FK_RolePermissions_Permissions FOREIGN KEY (PermissionId) REFERENCES core.Permissions(Id) ON DELETE CASCADE,
    CONSTRAINT CK_RolePermissions_Scope CHECK (DataScope IN ('own','department','branch','company','all'))
);

CREATE TABLE core.UserRoles (
    UserId     BIGINT NOT NULL,
    RoleId     BIGINT NOT NULL,
    CompanyId  BIGINT NOT NULL,
    CONSTRAINT PK_UserRoles PRIMARY KEY (UserId, RoleId, CompanyId),
    CONSTRAINT FK_UserRoles_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id) ON DELETE CASCADE,
    CONSTRAINT FK_UserRoles_Roles FOREIGN KEY (RoleId) REFERENCES core.Roles(Id) ON DELETE CASCADE,
    CONSTRAINT FK_UserRoles_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id)
);

/* ---------- Đánh số chứng từ tự động: BG2611-00001, DH2611-00001 ---------- */
CREATE TABLE core.Sequences (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT       NOT NULL,
    Code         VARCHAR(30)  NOT NULL,       -- 'QUOTATION','SALES_ORDER','RECEIPT'...
    Prefix       VARCHAR(20)  NOT NULL,       -- 'BG'
    DatePattern  VARCHAR(10)  NULL,           -- 'yyMM' | 'yyyy' | NULL
    Padding      TINYINT      NOT NULL DEFAULT 5,
    ResetPolicy  VARCHAR(10)  NOT NULL DEFAULT 'monthly',
    CONSTRAINT PK_Sequences PRIMARY KEY (Id),
    CONSTRAINT FK_Sequences_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_Sequences_Company_Code UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Sequences_Reset CHECK (ResetPolicy IN ('never','yearly','monthly'))
);

/* Bộ đếm RIÊNG cho từng kỳ: tháng 10 và tháng 11 đếm độc lập.
   Nhờ vậy nhập chứng từ lùi ngày (VD đang tháng 11 nhập hóa đơn tháng 10) vẫn không trùng số. */
CREATE TABLE core.SequenceCounters (
    SequenceId  BIGINT      NOT NULL,
    Period      VARCHAR(10) NOT NULL,         -- '202611' | '2026' | 'ALL'
    NextNumber  BIGINT      NOT NULL,
    CONSTRAINT PK_SequenceCounters PRIMARY KEY (SequenceId, Period),
    CONSTRAINT FK_SequenceCounters_Sequences FOREIGN KEY (SequenceId) REFERENCES core.Sequences(Id) ON DELETE CASCADE
);
GO

/* Lấy số chứng từ tiếp theo - an toàn khi nhiều người tạo cùng lúc */
CREATE OR ALTER PROCEDURE core.usp_NextDocNo
    @CompanyId BIGINT,
    @Code      VARCHAR(30),
    @DocDate   DATE = NULL,
    @DocNo     VARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @d DATE = ISNULL(@DocDate, CAST(SYSDATETIME() AS DATE));
    DECLARE @SeqId BIGINT, @Prefix VARCHAR(20), @Pattern VARCHAR(10), @Padding TINYINT,
            @Reset VARCHAR(10), @Period VARCHAR(10), @Num BIGINT;

    BEGIN TRAN;
        -- Khóa dòng cấu hình: các lệnh lấy số cùng dãy phải xếp hàng, không bao giờ trùng
        SELECT @SeqId = Id, @Prefix = Prefix, @Pattern = DatePattern, @Padding = Padding, @Reset = ResetPolicy
        FROM core.Sequences WITH (UPDLOCK, HOLDLOCK)
        WHERE CompanyId = @CompanyId AND Code = @Code;

        IF @SeqId IS NULL
        BEGIN
            ROLLBACK;
            THROW 50001, N'Chưa cấu hình dãy số chứng từ cho mã này.', 1;
        END

        -- Kỳ đánh số lấy theo NGÀY CHỨNG TỪ (không phải ngày hiện tại)
        SET @Period = CASE @Reset WHEN 'yearly'  THEN FORMAT(@d, 'yyyy')
                                  WHEN 'monthly' THEN FORMAT(@d, 'yyyyMM')
                                  ELSE 'ALL' END;

        UPDATE core.SequenceCounters
        SET @Num = NextNumber, NextNumber = NextNumber + 1
        WHERE SequenceId = @SeqId AND Period = @Period;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @Num = 1;
            INSERT core.SequenceCounters (SequenceId, Period, NextNumber) VALUES (@SeqId, @Period, 2);
        END
    COMMIT;

    -- Lưu ý: FORMAT(@d, NULL) KHÔNG trả NULL mà trả chuỗi ngày giờ đầy đủ, nên phải kiểm tra NULL trước
    SET @DocNo = @Prefix
               + CASE WHEN @Pattern IS NULL OR @Pattern = '' THEN '' ELSE FORMAT(@d, @Pattern) END
               + '-' + RIGHT(REPLICATE('0', @Padding) + CAST(@Num AS VARCHAR(20)), @Padding);
END
GO

/* ---------- Cấu hình dạng key-value ---------- */
CREATE TABLE core.Settings (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT        NULL,          -- NULL = cấu hình toàn hệ thống
    SettingKey  VARCHAR(150)  NOT NULL,      -- 'sales.quotation.require_approval'
    SettingValue NVARCHAR(MAX) NULL,
    IsEncrypted BIT           NOT NULL DEFAULT 0,
    UpdatedAt   DATETIME2(3)  NULL,
    UpdatedBy   BIGINT        NULL,
    CONSTRAINT PK_Settings PRIMARY KEY (Id),
    CONSTRAINT FK_Settings_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_Settings_Company_Key UNIQUE (CompanyId, SettingKey)
);

/* ---------- Nhật ký thay đổi (bảng lớn, không đặt FK để ghi nhanh) ---------- */
CREATE TABLE core.AuditLogs (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT        NULL,
    UserId      BIGINT        NULL,
    ActionType  VARCHAR(20)   NOT NULL,      -- create|update|delete|login|export|approve
    EntityName  VARCHAR(100)  NOT NULL,      -- 'sales.SalesOrders'
    EntityId    VARCHAR(50)   NULL,
    OldValues   NVARCHAR(MAX) NULL,          -- JSON
    NewValues   NVARCHAR(MAX) NULL,          -- JSON
    IpAddress   VARCHAR(45)   NULL,
    UserAgent   NVARCHAR(500) NULL,
    CorrelationId VARCHAR(64) NULL,
    CreatedAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_AuditLogs PRIMARY KEY (Id),
    CONSTRAINT CK_AuditLogs_OldJson CHECK (OldValues IS NULL OR ISJSON(OldValues) = 1),
    CONSTRAINT CK_AuditLogs_NewJson CHECK (NewValues IS NULL OR ISJSON(NewValues) = 1)
);
CREATE INDEX IX_AuditLogs_Entity ON core.AuditLogs(EntityName, EntityId, CreatedAt DESC);
CREATE INDEX IX_AuditLogs_User ON core.AuditLogs(UserId, CreatedAt DESC);

/* ---------- File đính kèm dùng chung cho mọi đối tượng ---------- */
CREATE TABLE core.Attachments (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT         NOT NULL,
    EntityName   VARCHAR(100)   NULL,
    EntityId     BIGINT         NULL,
    FileName     NVARCHAR(255)  NOT NULL,
    ContentType  VARCHAR(100)   NOT NULL,
    SizeBytes    BIGINT         NOT NULL,
    StorageProvider VARCHAR(20) NOT NULL DEFAULT 'local',  -- local|s3|azure|minio
    StoragePath  VARCHAR(1000)  NOT NULL,
    Checksum     VARCHAR(64)    NULL,         -- SHA-256
    CreatedAt    DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy    BIGINT         NULL,
    IsDeleted    BIT            NOT NULL DEFAULT 0,
    CONSTRAINT PK_Attachments PRIMARY KEY (Id),
    CONSTRAINT FK_Attachments_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id)
);
CREATE INDEX IX_Attachments_Entity ON core.Attachments(EntityName, EntityId) WHERE IsDeleted = 0;

/* ---------- Bình luận / lịch sử trao đổi trên từng chứng từ ---------- */
CREATE TABLE core.Comments (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT        NOT NULL,
    EntityName  VARCHAR(100)  NOT NULL,
    EntityId    BIGINT        NOT NULL,
    ParentId    BIGINT        NULL,
    Body        NVARCHAR(MAX) NOT NULL,
    IsSystem    BIT           NOT NULL DEFAULT 0,   -- tin tự sinh: "Đổi trạng thái sang Đã duyệt"
    CreatedAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy   BIGINT        NULL,
    UpdatedAt   DATETIME2(3)  NULL,
    IsDeleted   BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_Comments PRIMARY KEY (Id),
    CONSTRAINT FK_Comments_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Comments_Parent FOREIGN KEY (ParentId) REFERENCES core.Comments(Id)
);
CREATE INDEX IX_Comments_Entity ON core.Comments(EntityName, EntityId, CreatedAt);

/* ---------- Thông báo trong ứng dụng ---------- */
CREATE TABLE core.Notifications (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT        NULL,
    UserId      BIGINT        NOT NULL,
    Title       NVARCHAR(255) NOT NULL,
    Body        NVARCHAR(1000) NULL,
    Link        VARCHAR(500)  NULL,
    EntityName  VARCHAR(100)  NULL,
    EntityId    BIGINT        NULL,
    Severity    VARCHAR(10)   NOT NULL DEFAULT 'info',
    IsRead      BIT           NOT NULL DEFAULT 0,
    ReadAt      DATETIME2(3)  NULL,
    CreatedAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Notifications PRIMARY KEY (Id),
    CONSTRAINT FK_Notifications_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id) ON DELETE CASCADE,
    CONSTRAINT CK_Notifications_Severity CHECK (Severity IN ('info','success','warning','error'))
);
CREATE INDEX IX_Notifications_User_Unread ON core.Notifications(UserId, CreatedAt DESC) WHERE IsRead = 0;

/* ---------- Thẻ (tag) dùng chung ---------- */
CREATE TABLE core.Tags (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId  BIGINT        NOT NULL,
    Name       NVARCHAR(100) NOT NULL,
    Color      VARCHAR(10)   NULL,
    CONSTRAINT PK_Tags PRIMARY KEY (Id),
    CONSTRAINT FK_Tags_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_Tags_Company_Name UNIQUE (CompanyId, Name)
);
CREATE TABLE core.EntityTags (
    TagId       BIGINT       NOT NULL,
    EntityName  VARCHAR(100) NOT NULL,
    EntityId    BIGINT       NOT NULL,
    CONSTRAINT PK_EntityTags PRIMARY KEY (TagId, EntityName, EntityId),
    CONSTRAINT FK_EntityTags_Tags FOREIGN KEY (TagId) REFERENCES core.Tags(Id) ON DELETE CASCADE
);
CREATE INDEX IX_EntityTags_Entity ON core.EntityTags(EntityName, EntityId);

/* ---------- Trường tùy biến (người dùng tự thêm cột) ---------- */
CREATE TABLE core.CustomFieldDefinitions (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT        NOT NULL,
    EntityName  VARCHAR(100)  NOT NULL,
    Code        VARCHAR(50)   NOT NULL,
    Label       NVARCHAR(150) NOT NULL,
    DataType    VARCHAR(20)   NOT NULL,
    Options     NVARCHAR(MAX) NULL,           -- JSON cho kiểu select
    IsRequired  BIT           NOT NULL DEFAULT 0,
    SortOrder   INT           NOT NULL DEFAULT 0,
    IsActive    BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_CustomFieldDefinitions PRIMARY KEY (Id),
    CONSTRAINT FK_CustomFieldDefinitions_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_CustomFieldDefinitions UNIQUE (CompanyId, EntityName, Code),
    CONSTRAINT CK_CustomFieldDefinitions_Type CHECK (DataType IN ('text','number','decimal','date','datetime','bool','select','multiselect','user'))
);
CREATE TABLE core.CustomFieldValues (
    DefinitionId BIGINT        NOT NULL,
    EntityId     BIGINT        NOT NULL,
    FieldValue   NVARCHAR(MAX) NULL,
    CONSTRAINT PK_CustomFieldValues PRIMARY KEY (DefinitionId, EntityId),
    CONSTRAINT FK_CustomFieldValues_Def FOREIGN KEY (DefinitionId) REFERENCES core.CustomFieldDefinitions(Id) ON DELETE CASCADE
);

/* ---------- Quy trình duyệt dùng chung (báo giá, đơn mua, nghỉ phép...) ---------- */
CREATE TABLE core.ApprovalRules (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT        NOT NULL,
    EntityName      VARCHAR(100)  NOT NULL,   -- 'sales.Quotations'
    ApprovalLevel   TINYINT       NOT NULL,   -- 1, 2, 3...
    MinAmount       DECIMAL(18,2) NOT NULL DEFAULT 0,
    ApproverRoleId  BIGINT        NULL,
    ApproverUserId  BIGINT        NULL,
    IsDepartmentManager BIT       NOT NULL DEFAULT 0,  -- người duyệt = trưởng phòng người tạo
    IsActive        BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_ApprovalRules PRIMARY KEY (Id),
    CONSTRAINT FK_ApprovalRules_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_ApprovalRules_Roles FOREIGN KEY (ApproverRoleId) REFERENCES core.Roles(Id),
    CONSTRAINT FK_ApprovalRules_Users FOREIGN KEY (ApproverUserId) REFERENCES core.Users(Id)
);
CREATE TABLE core.ApprovalRequests (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT        NOT NULL,
    EntityName      VARCHAR(100)  NOT NULL,
    EntityId        BIGINT        NOT NULL,
    ApprovalLevel   TINYINT       NOT NULL,
    RuleId          BIGINT        NULL,
    ApproverUserId  BIGINT        NULL,
    Status          VARCHAR(20)   NOT NULL DEFAULT 'pending',
    Comment         NVARCHAR(1000) NULL,
    RequestedBy     BIGINT        NULL,
    RequestedAt     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    DecidedBy       BIGINT        NULL,
    DecidedAt       DATETIME2(3)  NULL,
    CONSTRAINT PK_ApprovalRequests PRIMARY KEY (Id),
    CONSTRAINT FK_ApprovalRequests_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_ApprovalRequests_Rules FOREIGN KEY (RuleId) REFERENCES core.ApprovalRules(Id),
    CONSTRAINT FK_ApprovalRequests_Users FOREIGN KEY (ApproverUserId) REFERENCES core.Users(Id),
    CONSTRAINT CK_ApprovalRequests_Status CHECK (Status IN ('pending','approved','rejected','cancelled'))
);
CREATE INDEX IX_ApprovalRequests_Entity ON core.ApprovalRequests(EntityName, EntityId);
CREATE INDEX IX_ApprovalRequests_Pending ON core.ApprovalRequests(ApproverUserId) WHERE Status = 'pending';

/* ---------- Outbox: sự kiện liên module (Transactional Outbox pattern)
   VD: Đơn hàng xác nhận -> ghi 'OrderConfirmed' cùng transaction ->
   background job đọc và gọi Kho, Kế toán xử lý. Không mất sự kiện. ---------- */
CREATE TABLE core.OutboxMessages (
    Id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    CompanyId    BIGINT        NULL,
    EventType    VARCHAR(200)  NOT NULL,      -- 'Sales.OrderConfirmed'
    Payload      NVARCHAR(MAX) NOT NULL,      -- JSON
    OccurredAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    ProcessedAt  DATETIME2(3)  NULL,
    RetryCount   INT           NOT NULL DEFAULT 0,
    Error        NVARCHAR(MAX) NULL,
    CONSTRAINT PK_OutboxMessages PRIMARY KEY (Id),
    CONSTRAINT CK_OutboxMessages_Json CHECK (ISJSON(Payload) = 1)
);
CREATE INDEX IX_OutboxMessages_Pending ON core.OutboxMessages(OccurredAt) WHERE ProcessedAt IS NULL;
GO
