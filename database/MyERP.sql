/* =====================================================================
   Database MyERP – MyERP (cấu trúc + toàn bộ dữ liệu)
   Tạo lúc: 2026-11-21 14:24

   CÁCH DÙNG TRÊN MÁY MỚI:
     1. Mở file này trong SQL Server Management Studio (SSMS), kết nối tới SQL Server.
     2. Bấm Execute (F5). Xong.
     (hoặc dòng lệnh: sqlcmd -S localhost -E -C -f 65001 -i MyERP.sql)

   Nếu máy đó đã có database MyERP, script sẽ dừng lại, không ghi đè gì.
   Muốn thay hẳn: xóa database MyERP cũ trong SSMS rồi chạy lại file này.

   File này được sinh tự động bởi database\cap-nhat-file-sql.cmd – đừng sửa tay.
   Muốn đổi cấu trúc: sửa script trong database\source rồi chạy lại cmd.
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO
IF DB_ID(N'MyERP') IS NOT NULL
BEGIN
    RAISERROR(N'Database MyERP đã tồn tại trên máy này. Không chạy tiếp để tránh ghi đè dữ liệu.', 16, 1) WITH NOWAIT;
    SET NOEXEC ON;
END
GO
CREATE DATABASE [MyERP] COLLATE Latin1_General_100_CI_AI;
GO
ALTER DATABASE [MyERP] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [MyERP] SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
USE [MyERP];
GO

-- ===================== 01_core.sql =====================
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

/* Khóa truy cập cá nhân: cho phần mềm khác (VD trợ lý AI qua MCP) gọi API thay mặt người dùng, với đúng quyền của người đó.
   Chỉ lưu SHA-256 của khóa; khóa gốc hiện 1 lần lúc tạo. */
CREATE TABLE core.ApiTokens (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    UserId      BIGINT        NOT NULL,
    CompanyId   BIGINT        NOT NULL,
    Name        NVARCHAR(100) NOT NULL,
    TokenHash   CHAR(64)      NOT NULL,
    Prefix      VARCHAR(16)   NOT NULL,
    CreatedAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    ExpiresAt   DATETIME2(3)  NULL,
    LastUsedAt  DATETIME2(3)  NULL,
    LastUsedIp  VARCHAR(45)   NULL,
    RevokedAt   DATETIME2(3)  NULL,
    CONSTRAINT PK_ApiTokens PRIMARY KEY (Id),
    CONSTRAINT FK_ApiTokens_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id) ON DELETE CASCADE,
    CONSTRAINT FK_ApiTokens_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_ApiTokens_Hash UNIQUE (TokenHash)
);
CREATE INDEX IX_ApiTokens_User ON core.ApiTokens(UserId) WHERE RevokedAt IS NULL;

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
GO

-- ===================== 02_master_data.sql =====================
/* =====================================================================
   MyERP - 02. MASTER DATA (md): danh mục dùng chung cho mọi phòng ban.
   Khách hàng + nhà cung cấp + đơn vị vận chuyển = 1 bảng Partners
   (một đối tác có thể vừa mua vừa bán), tránh trùng dữ liệu.
   Địa giới hành chính 2 cấp (Tỉnh/Thành - Phường/Xã) theo mô hình từ 01/07/2025.
   ===================================================================== */
CREATE SCHEMA md;
GO

CREATE TABLE md.Currencies (
    Code          CHAR(3)       NOT NULL,
    Name          NVARCHAR(100) NOT NULL,
    Symbol        NVARCHAR(10)  NOT NULL,
    DecimalPlaces TINYINT       NOT NULL DEFAULT 0,
    IsActive      BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_Currencies PRIMARY KEY (Code)
);

CREATE TABLE md.ExchangeRates (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId     BIGINT        NOT NULL,
    CurrencyCode  CHAR(3)       NOT NULL,
    RateDate      DATE          NOT NULL,
    Rate          DECIMAL(18,6) NOT NULL,      -- 1 ngoại tệ = Rate VND
    CONSTRAINT PK_ExchangeRates PRIMARY KEY (Id),
    CONSTRAINT FK_ExchangeRates_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_ExchangeRates_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT UQ_ExchangeRates UNIQUE (CompanyId, CurrencyCode, RateDate),
    CONSTRAINT CK_ExchangeRates_Rate CHECK (Rate > 0)
);

CREATE TABLE md.Provinces (
    Code  VARCHAR(10)   NOT NULL,
    Name  NVARCHAR(100) NOT NULL,
    Type  NVARCHAR(30)  NULL,           -- Tỉnh | Thành phố
    CONSTRAINT PK_Provinces PRIMARY KEY (Code)
);
CREATE TABLE md.Wards (
    Code          VARCHAR(10)   NOT NULL,
    ProvinceCode  VARCHAR(10)   NOT NULL,
    Name          NVARCHAR(100) NOT NULL,
    Type          NVARCHAR(30)  NULL,   -- Phường | Xã | Đặc khu
    CONSTRAINT PK_Wards PRIMARY KEY (Code),
    CONSTRAINT FK_Wards_Provinces FOREIGN KEY (ProvinceCode) REFERENCES md.Provinces(Code)
);
CREATE INDEX IX_Wards_Province ON md.Wards(ProvinceCode);

CREATE TABLE md.UnitsOfMeasure (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId BIGINT        NULL,              -- NULL = dùng chung
    Code      VARCHAR(20)   NOT NULL,
    Name      NVARCHAR(50)  NOT NULL,
    IsActive  BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_UnitsOfMeasure PRIMARY KEY (Id),
    CONSTRAINT FK_UnitsOfMeasure_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_UnitsOfMeasure UNIQUE (CompanyId, Code)
);

CREATE TABLE md.PaymentMethods (
    Code      VARCHAR(20)   NOT NULL,          -- cash, bank_transfer, cod, card, ewallet
    Name      NVARCHAR(100) NOT NULL,
    IsActive  BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_PaymentMethods PRIMARY KEY (Code)
);

CREATE TABLE md.PaymentTerms (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId BIGINT        NOT NULL,
    Code      VARCHAR(20)   NOT NULL,
    Name      NVARCHAR(100) NOT NULL,          -- 'Thanh toán ngay', 'Công nợ 30 ngày'
    DueDays   INT           NOT NULL DEFAULT 0,
    IsActive  BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_PaymentTerms PRIMARY KEY (Id),
    CONSTRAINT FK_PaymentTerms_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_PaymentTerms UNIQUE (CompanyId, Code),
    CONSTRAINT CK_PaymentTerms_Days CHECK (DueDays >= 0)
);

CREATE TABLE md.Taxes (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId BIGINT        NOT NULL,
    Code      VARCHAR(20)   NOT NULL,          -- 'VAT10', 'VAT8', 'VAT0', 'KCT'
    Name      NVARCHAR(100) NOT NULL,
    TaxScope  VARCHAR(10)   NOT NULL,          -- sale | purchase | both
    Rate      DECIMAL(9,4)  NOT NULL,          -- 10.0000 = 10%
    IsActive  BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_Taxes PRIMARY KEY (Id),
    CONSTRAINT FK_Taxes_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_Taxes UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Taxes_Scope CHECK (TaxScope IN ('sale','purchase','both')),
    CONSTRAINT CK_Taxes_Rate CHECK (Rate BETWEEN 0 AND 100)
);
-- Tài khoản kế toán của thuế được thêm ở file 10_accounting.sql

/* ---------- Đối tác: khách hàng / nhà cung cấp / hãng vận chuyển ---------- */
CREATE TABLE md.PartnerGroups (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId BIGINT        NOT NULL,
    Code      VARCHAR(20)   NOT NULL,
    Name      NVARCHAR(150) NOT NULL,          -- 'Đại lý cấp 1', 'Khách lẻ', 'VIP'
    GroupType VARCHAR(10)   NOT NULL DEFAULT 'customer',
    CONSTRAINT PK_PartnerGroups PRIMARY KEY (Id),
    CONSTRAINT FK_PartnerGroups_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_PartnerGroups UNIQUE (CompanyId, Code),
    CONSTRAINT CK_PartnerGroups_Type CHECK (GroupType IN ('customer','supplier'))
);

CREATE TABLE md.Partners (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT         NOT NULL,
    Code            VARCHAR(30)    NOT NULL,
    PartnerType     VARCHAR(10)    NOT NULL DEFAULT 'company',  -- company | individual
    Name            NVARCHAR(255)  NOT NULL,
    ShortName       NVARCHAR(100)  NULL,
    TaxCode         VARCHAR(20)    NULL,
    Phone           VARCHAR(20)    NULL,
    Email           VARCHAR(255)   NULL,
    Website         VARCHAR(255)   NULL,
    Industry        NVARCHAR(100)  NULL,
    Street          NVARCHAR(255)  NULL,
    WardCode        VARCHAR(10)    NULL,
    ProvinceCode    VARCHAR(10)    NULL,
    IsCustomer      BIT            NOT NULL DEFAULT 0,
    IsSupplier      BIT            NOT NULL DEFAULT 0,
    IsCarrier       BIT            NOT NULL DEFAULT 0,
    CustomerGroupId BIGINT         NULL,
    SupplierGroupId BIGINT         NULL,
    PaymentTermId   BIGINT         NULL,
    PriceListId     BIGINT         NULL,      -- FK thêm sau khi có md.PriceLists
    CreditLimit     DECIMAL(18,2)  NOT NULL DEFAULT 0,  -- hạn mức công nợ, 0 = không giới hạn
    CurrencyCode    CHAR(3)        NOT NULL DEFAULT 'VND',
    OwnerUserId     BIGINT         NULL,      -- sale phụ trách
    DepartmentId    BIGINT         NULL,
    Source          NVARCHAR(100)  NULL,
    Note            NVARCHAR(MAX)  NULL,
    IsActive        BIT            NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted       BIT NOT NULL DEFAULT 0,
    RowVersion      ROWVERSION NOT NULL,
    CONSTRAINT PK_Partners PRIMARY KEY (Id),
    CONSTRAINT FK_Partners_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Partners_Wards FOREIGN KEY (WardCode) REFERENCES md.Wards(Code),
    CONSTRAINT FK_Partners_Provinces FOREIGN KEY (ProvinceCode) REFERENCES md.Provinces(Code),
    CONSTRAINT FK_Partners_CustomerGroup FOREIGN KEY (CustomerGroupId) REFERENCES md.PartnerGroups(Id),
    CONSTRAINT FK_Partners_SupplierGroup FOREIGN KEY (SupplierGroupId) REFERENCES md.PartnerGroups(Id),
    CONSTRAINT FK_Partners_PaymentTerms FOREIGN KEY (PaymentTermId) REFERENCES md.PaymentTerms(Id),
    CONSTRAINT FK_Partners_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT FK_Partners_Owner FOREIGN KEY (OwnerUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Partners_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT UQ_Partners_Company_Code UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Partners_Type CHECK (PartnerType IN ('company','individual')),
    CONSTRAINT CK_Partners_CreditLimit CHECK (CreditLimit >= 0)
);
CREATE INDEX IX_Partners_Name ON md.Partners(CompanyId, Name) WHERE IsDeleted = 0;
CREATE INDEX IX_Partners_Phone ON md.Partners(CompanyId, Phone) WHERE IsDeleted = 0;
CREATE INDEX IX_Partners_TaxCode ON md.Partners(CompanyId, TaxCode) WHERE TaxCode IS NOT NULL;
CREATE INDEX IX_Partners_Owner ON md.Partners(OwnerUserId) WHERE IsDeleted = 0;

CREATE TABLE md.PartnerContacts (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    PartnerId  BIGINT         NOT NULL,
    FullName   NVARCHAR(150)  NOT NULL,
    Position   NVARCHAR(100)  NULL,
    Department NVARCHAR(100)  NULL,
    Phone      VARCHAR(20)    NULL,
    Email      VARCHAR(255)   NULL,
    Birthday   DATE           NULL,
    IsPrimary  BIT            NOT NULL DEFAULT 0,
    Note       NVARCHAR(1000) NULL,
    CreatedAt  DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted  BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_PartnerContacts PRIMARY KEY (Id),
    CONSTRAINT FK_PartnerContacts_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id)
);
CREATE INDEX IX_PartnerContacts_Partner ON md.PartnerContacts(PartnerId);

CREATE TABLE md.PartnerAddresses (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    PartnerId    BIGINT        NOT NULL,
    AddressType  VARCHAR(10)   NOT NULL DEFAULT 'shipping',
    ContactName  NVARCHAR(150) NULL,
    Phone        VARCHAR(20)   NULL,
    Street       NVARCHAR(255) NOT NULL,
    WardCode     VARCHAR(10)   NULL,
    ProvinceCode VARCHAR(10)   NULL,
    IsDefault    BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_PartnerAddresses PRIMARY KEY (Id),
    CONSTRAINT FK_PartnerAddresses_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id) ON DELETE CASCADE,
    CONSTRAINT FK_PartnerAddresses_Wards FOREIGN KEY (WardCode) REFERENCES md.Wards(Code),
    CONSTRAINT FK_PartnerAddresses_Provinces FOREIGN KEY (ProvinceCode) REFERENCES md.Provinces(Code),
    CONSTRAINT CK_PartnerAddresses_Type CHECK (AddressType IN ('billing','shipping','other'))
);
CREATE INDEX IX_PartnerAddresses_Partner ON md.PartnerAddresses(PartnerId);

CREATE TABLE md.PartnerBankAccounts (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    PartnerId    BIGINT        NOT NULL,
    BankName     NVARCHAR(150) NOT NULL,
    BankBranch   NVARCHAR(150) NULL,
    AccountNo    VARCHAR(30)   NOT NULL,
    AccountName  NVARCHAR(150) NOT NULL,
    IsDefault    BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_PartnerBankAccounts PRIMARY KEY (Id),
    CONSTRAINT FK_PartnerBankAccounts_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id) ON DELETE CASCADE
);

/* ---------- Sản phẩm ---------- */
CREATE TABLE md.ProductCategories (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId BIGINT        NOT NULL,
    ParentId  BIGINT        NULL,
    Code      VARCHAR(30)   NOT NULL,
    Name      NVARCHAR(150) NOT NULL,
    Path      VARCHAR(500)  NULL,
    SortOrder INT           NOT NULL DEFAULT 0,
    IsActive  BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_ProductCategories PRIMARY KEY (Id),
    CONSTRAINT FK_ProductCategories_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_ProductCategories_Parent FOREIGN KEY (ParentId) REFERENCES md.ProductCategories(Id),
    CONSTRAINT UQ_ProductCategories UNIQUE (CompanyId, Code)
);
-- Tài khoản doanh thu/giá vốn/tồn kho theo nhóm được thêm ở 10_accounting.sql

CREATE TABLE md.Brands (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId BIGINT        NOT NULL,
    Name      NVARCHAR(150) NOT NULL,
    CONSTRAINT PK_Brands PRIMARY KEY (Id),
    CONSTRAINT FK_Brands_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_Brands UNIQUE (CompanyId, Name)
);

/* Mẫu sản phẩm (VD "Áo thun basic cổ tròn"). Mỗi mẫu có nhiều biến thể màu × size,
   mỗi biến thể là 1 dòng md.Products (SKU) - tồn kho, đơn hàng đều tính theo SKU. */
CREATE TABLE md.ProductModels (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT         NOT NULL,
    Code         VARCHAR(30)    NOT NULL,
    Name         NVARCHAR(255)  NOT NULL,
    CategoryId   BIGINT         NULL,
    BrandId      BIGINT         NULL,
    UomId        BIGINT         NOT NULL,
    SalePrice    DECIMAL(18,4)  NOT NULL DEFAULT 0,
    CostPrice    DECIMAL(18,4)  NOT NULL DEFAULT 0,
    Gender       VARCHAR(10)    NULL,                -- men | women | unisex | kids
    Material     NVARCHAR(100)  NULL,
    Season       NVARCHAR(50)   NULL,
    Description  NVARCHAR(MAX)  NULL,
    ImageUrl     VARCHAR(500)   NULL,
    IsActive     BIT            NOT NULL DEFAULT 1,
    CreatedAt    DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted    BIT NOT NULL DEFAULT 0,
    RowVersion   ROWVERSION NOT NULL,
    CONSTRAINT PK_ProductModels PRIMARY KEY (Id),
    CONSTRAINT FK_ProductModels_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_ProductModels_Categories FOREIGN KEY (CategoryId) REFERENCES md.ProductCategories(Id),
    CONSTRAINT FK_ProductModels_Brands FOREIGN KEY (BrandId) REFERENCES md.Brands(Id),
    CONSTRAINT FK_ProductModels_Uom FOREIGN KEY (UomId) REFERENCES md.UnitsOfMeasure(Id),
    CONSTRAINT UQ_ProductModels_Company_Code UNIQUE (CompanyId, Code),
    CONSTRAINT CK_ProductModels_Gender CHECK (Gender IS NULL OR Gender IN ('men','women','unisex','kids')),
    CONSTRAINT CK_ProductModels_Prices CHECK (SalePrice >= 0 AND CostPrice >= 0)
);

CREATE TABLE md.Products (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT         NOT NULL,
    Code            VARCHAR(50)    NOT NULL,            -- SKU
    Barcode         VARCHAR(50)    NULL,
    Name            NVARCHAR(255)  NOT NULL,
    ProductType     VARCHAR(12)    NOT NULL DEFAULT 'goods',
    CategoryId      BIGINT         NULL,
    BrandId         BIGINT         NULL,
    ModelId         BIGINT         NULL,                -- thuộc mẫu nào (NULL = sản phẩm đơn, không biến thể)
    Color           NVARCHAR(50)   NULL,
    Size            VARCHAR(20)    NULL,
    UomId           BIGINT         NOT NULL,            -- đơn vị tính cơ bản (tồn kho)
    PurchaseUomId   BIGINT         NULL,
    SalePrice       DECIMAL(18,4)  NOT NULL DEFAULT 0,
    CostPrice       DECIMAL(18,4)  NOT NULL DEFAULT 0,  -- giá vốn bình quân hiện tại
    CostMethod      VARCHAR(10)    NOT NULL DEFAULT 'average',
    SaleTaxId       BIGINT         NULL,
    PurchaseTaxId   BIGINT         NULL,
    IsSellable      BIT            NOT NULL DEFAULT 1,
    IsPurchasable   BIT            NOT NULL DEFAULT 1,
    IsStockTracked  BIT            NOT NULL DEFAULT 1,
    TrackingType    VARCHAR(10)    NOT NULL DEFAULT 'none',
    MinStock        DECIMAL(18,4)  NOT NULL DEFAULT 0,
    MaxStock        DECIMAL(18,4)  NULL,
    WarrantyMonths  INT            NOT NULL DEFAULT 0,
    WeightGram      DECIMAL(18,2)  NULL,
    LengthCm        DECIMAL(9,2) NULL, WidthCm DECIMAL(9,2) NULL, HeightCm DECIMAL(9,2) NULL,
    ImageUrl        VARCHAR(500)   NULL,
    Description     NVARCHAR(MAX)  NULL,
    IsPublishedWeb  BIT            NOT NULL DEFAULT 0,
    WebSlug         VARCHAR(255)   NULL,
    IsActive        BIT            NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted       BIT NOT NULL DEFAULT 0,
    RowVersion      ROWVERSION NOT NULL,
    CONSTRAINT PK_Products PRIMARY KEY (Id),
    CONSTRAINT FK_Products_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Products_Categories FOREIGN KEY (CategoryId) REFERENCES md.ProductCategories(Id),
    CONSTRAINT FK_Products_Brands FOREIGN KEY (BrandId) REFERENCES md.Brands(Id),
    CONSTRAINT FK_Products_Models FOREIGN KEY (ModelId) REFERENCES md.ProductModels(Id),
    CONSTRAINT FK_Products_Uom FOREIGN KEY (UomId) REFERENCES md.UnitsOfMeasure(Id),
    CONSTRAINT FK_Products_PurchaseUom FOREIGN KEY (PurchaseUomId) REFERENCES md.UnitsOfMeasure(Id),
    CONSTRAINT FK_Products_SaleTax FOREIGN KEY (SaleTaxId) REFERENCES md.Taxes(Id),
    CONSTRAINT FK_Products_PurchaseTax FOREIGN KEY (PurchaseTaxId) REFERENCES md.Taxes(Id),
    CONSTRAINT UQ_Products_Company_Code UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Products_Type CHECK (ProductType IN ('goods','service','consumable','combo')),
    CONSTRAINT CK_Products_CostMethod CHECK (CostMethod IN ('average','fifo','standard')),
    CONSTRAINT CK_Products_Tracking CHECK (TrackingType IN ('none','lot','serial')),
    CONSTRAINT CK_Products_Prices CHECK (SalePrice >= 0 AND CostPrice >= 0)
);
CREATE UNIQUE INDEX UX_Products_Barcode ON md.Products(CompanyId, Barcode) WHERE Barcode IS NOT NULL AND IsDeleted = 0;
CREATE INDEX IX_Products_Name ON md.Products(CompanyId, Name) WHERE IsDeleted = 0;
CREATE INDEX IX_Products_Category ON md.Products(CategoryId);
CREATE INDEX IX_Products_Model ON md.Products(ModelId) WHERE ModelId IS NOT NULL;
CREATE UNIQUE INDEX UX_Products_Model_Variant ON md.Products(ModelId, Color, Size) WHERE ModelId IS NOT NULL AND IsDeleted = 0;

/* Quy đổi đơn vị theo sản phẩm: 1 Thùng = 24 Lon */
CREATE TABLE md.ProductUoms (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    ProductId  BIGINT        NOT NULL,
    UomId      BIGINT        NOT NULL,
    Factor     DECIMAL(18,6) NOT NULL,         -- số đơn vị cơ bản trong 1 đơn vị này
    Barcode    VARCHAR(50)   NULL,
    SalePrice  DECIMAL(18,4) NULL,
    CONSTRAINT PK_ProductUoms PRIMARY KEY (Id),
    CONSTRAINT FK_ProductUoms_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id) ON DELETE CASCADE,
    CONSTRAINT FK_ProductUoms_Uom FOREIGN KEY (UomId) REFERENCES md.UnitsOfMeasure(Id),
    CONSTRAINT UQ_ProductUoms UNIQUE (ProductId, UomId),
    CONSTRAINT CK_ProductUoms_Factor CHECK (Factor > 0)
);

/* Thành phần combo / BOM đơn giản */
CREATE TABLE md.ProductComponents (
    ProductId    BIGINT        NOT NULL,
    ComponentId  BIGINT        NOT NULL,
    Quantity     DECIMAL(18,4) NOT NULL,
    CONSTRAINT PK_ProductComponents PRIMARY KEY (ProductId, ComponentId),
    CONSTRAINT FK_ProductComponents_Product FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_ProductComponents_Component FOREIGN KEY (ComponentId) REFERENCES md.Products(Id),
    CONSTRAINT CK_ProductComponents CHECK (ProductId <> ComponentId AND Quantity > 0)
);

CREATE TABLE md.ProductSuppliers (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    ProductId     BIGINT        NOT NULL,
    PartnerId     BIGINT        NOT NULL,
    SupplierSku   VARCHAR(50)   NULL,
    PurchasePrice DECIMAL(18,4) NOT NULL DEFAULT 0,
    MinQty        DECIMAL(18,4) NOT NULL DEFAULT 0,
    LeadTimeDays  INT           NOT NULL DEFAULT 0,
    IsPreferred   BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_ProductSuppliers PRIMARY KEY (Id),
    CONSTRAINT FK_ProductSuppliers_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id) ON DELETE CASCADE,
    CONSTRAINT FK_ProductSuppliers_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT UQ_ProductSuppliers UNIQUE (ProductId, PartnerId)
);

/* ---------- Bảng giá ---------- */
CREATE TABLE md.PriceLists (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    Code         VARCHAR(20)   NOT NULL,
    Name         NVARCHAR(150) NOT NULL,       -- 'Giá bán lẻ', 'Giá đại lý'
    CurrencyCode CHAR(3)       NOT NULL DEFAULT 'VND',
    ValidFrom    DATE          NULL,
    ValidTo      DATE          NULL,
    IsDefault    BIT           NOT NULL DEFAULT 0,
    IsActive     BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_PriceLists PRIMARY KEY (Id),
    CONSTRAINT FK_PriceLists_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_PriceLists_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT UQ_PriceLists UNIQUE (CompanyId, Code),
    CONSTRAINT CK_PriceLists_Dates CHECK (ValidTo IS NULL OR ValidFrom IS NULL OR ValidTo >= ValidFrom)
);
CREATE TABLE md.PriceListItems (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    PriceListId     BIGINT        NOT NULL,
    ProductId       BIGINT        NOT NULL,
    UomId           BIGINT        NULL,
    MinQty          DECIMAL(18,4) NOT NULL DEFAULT 0,   -- giá theo bậc số lượng
    Price           DECIMAL(18,4) NOT NULL,
    DiscountPercent DECIMAL(9,4)  NOT NULL DEFAULT 0,
    CONSTRAINT PK_PriceListItems PRIMARY KEY (Id),
    CONSTRAINT FK_PriceListItems_PriceLists FOREIGN KEY (PriceListId) REFERENCES md.PriceLists(Id) ON DELETE CASCADE,
    CONSTRAINT FK_PriceListItems_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_PriceListItems_Uom FOREIGN KEY (UomId) REFERENCES md.UnitsOfMeasure(Id),
    CONSTRAINT UQ_PriceListItems UNIQUE (PriceListId, ProductId, UomId, MinQty),
    CONSTRAINT CK_PriceListItems CHECK (Price >= 0 AND DiscountPercent BETWEEN 0 AND 100)
);

ALTER TABLE md.Partners ADD CONSTRAINT FK_Partners_PriceLists FOREIGN KEY (PriceListId) REFERENCES md.PriceLists(Id);
GO
GO

-- ===================== 03_hr.sql =====================
/* =====================================================================
   MyERP - 03. NHÂN SỰ (hr): hồ sơ, hợp đồng, chấm công, nghỉ phép,
   tính lương (BHXH/BHYT/BHTN, thuế TNCN), tuyển dụng.
   Đặt trước các module khác vì Vận chuyển (tài xế), Dự án... tham chiếu nhân viên.
   ===================================================================== */
CREATE SCHEMA hr;
GO

CREATE TABLE hr.Positions (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    Code         VARCHAR(20)   NOT NULL,
    Name         NVARCHAR(150) NOT NULL,     -- 'Nhân viên kinh doanh', 'Kế toán trưởng'
    DepartmentId BIGINT        NULL,
    IsActive     BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_Positions PRIMARY KEY (Id),
    CONSTRAINT FK_Positions_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Positions_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT UQ_Positions UNIQUE (CompanyId, Code)
);

CREATE TABLE hr.Employees (
    Id                BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId         BIGINT         NOT NULL,
    Code              VARCHAR(20)    NOT NULL,
    UserId            BIGINT         NULL,          -- tài khoản đăng nhập (nếu có)
    FullName          NVARCHAR(150)  NOT NULL,
    Gender            CHAR(1)        NULL,          -- M | F | O
    DateOfBirth       DATE           NULL,
    IdNumber          VARCHAR(20)    NULL,          -- CCCD: dữ liệu cá nhân nhạy cảm, mã hóa ở tầng ứng dụng
    IdIssuedDate      DATE           NULL,
    IdIssuedPlace     NVARCHAR(150)  NULL,
    Phone             VARCHAR(20)    NULL,
    PersonalEmail     VARCHAR(255)   NULL,
    WorkEmail         VARCHAR(255)   NULL,
    PermanentAddress  NVARCHAR(500)  NULL,
    CurrentAddress    NVARCHAR(500)  NULL,
    BranchId          BIGINT         NULL,
    DepartmentId      BIGINT         NULL,
    PositionId        BIGINT         NULL,
    ManagerId         BIGINT         NULL,
    HireDate          DATE           NULL,
    OfficialDate      DATE           NULL,
    TerminationDate   DATE           NULL,
    EmploymentStatus  VARCHAR(12)    NOT NULL DEFAULT 'probation',
    PersonalTaxCode   VARCHAR(20)    NULL,
    SocialInsuranceNo VARCHAR(20)    NULL,
    Dependents        TINYINT        NOT NULL DEFAULT 0,   -- người phụ thuộc (giảm trừ gia cảnh)
    BankName          NVARCHAR(150)  NULL,
    BankAccountNo     VARCHAR(30)    NULL,
    AvatarUrl         VARCHAR(500)   NULL,
    CreatedAt         DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted         BIT NOT NULL DEFAULT 0,
    RowVersion        ROWVERSION NOT NULL,
    CONSTRAINT PK_Employees PRIMARY KEY (Id),
    CONSTRAINT FK_Employees_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Employees_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Employees_Branches FOREIGN KEY (BranchId) REFERENCES core.Branches(Id),
    CONSTRAINT FK_Employees_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT FK_Employees_Positions FOREIGN KEY (PositionId) REFERENCES hr.Positions(Id),
    CONSTRAINT FK_Employees_Manager FOREIGN KEY (ManagerId) REFERENCES hr.Employees(Id),
    CONSTRAINT UQ_Employees_Company_Code UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Employees_Gender CHECK (Gender IS NULL OR Gender IN ('M','F','O')),
    CONSTRAINT CK_Employees_Status CHECK (EmploymentStatus IN ('probation','official','maternity','suspended','resigned','terminated'))
);
CREATE UNIQUE INDEX UX_Employees_User ON hr.Employees(UserId) WHERE UserId IS NOT NULL;
CREATE INDEX IX_Employees_Department ON hr.Employees(DepartmentId) WHERE IsDeleted = 0;

CREATE TABLE hr.Contracts (
    Id               BIGINT IDENTITY(1,1) NOT NULL,
    EmployeeId       BIGINT        NOT NULL,
    ContractNo       VARCHAR(30)   NOT NULL,
    ContractType     VARCHAR(15)   NOT NULL,
    StartDate        DATE          NOT NULL,
    EndDate          DATE          NULL,
    BaseSalary       DECIMAL(18,2) NOT NULL,
    InsuranceSalary  DECIMAL(18,2) NOT NULL,    -- lương đóng bảo hiểm
    Status           VARCHAR(12)   NOT NULL DEFAULT 'draft',
    SignedAt         DATE          NULL,
    AttachmentId     BIGINT        NULL,
    Note             NVARCHAR(1000) NULL,
    CreatedAt        DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_Contracts PRIMARY KEY (Id),
    CONSTRAINT FK_Contracts_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_Contracts_Attachments FOREIGN KEY (AttachmentId) REFERENCES core.Attachments(Id),
    CONSTRAINT CK_Contracts_Type CHECK (ContractType IN ('probation','fixed_term','indefinite','seasonal','service')),
    CONSTRAINT CK_Contracts_Status CHECK (Status IN ('draft','active','expired','terminated')),
    CONSTRAINT CK_Contracts_Dates CHECK (EndDate IS NULL OR EndDate >= StartDate)
);
CREATE INDEX IX_Contracts_Employee ON hr.Contracts(EmployeeId);

CREATE TABLE hr.ContractAllowances (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    ContractId  BIGINT        NOT NULL,
    Name        NVARCHAR(100) NOT NULL,         -- 'Phụ cấp ăn trưa', 'Xăng xe'
    Amount      DECIMAL(18,2) NOT NULL,
    IsTaxable   BIT           NOT NULL DEFAULT 1,
    IsInsurable BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_ContractAllowances PRIMARY KEY (Id),
    CONSTRAINT FK_ContractAllowances_Contracts FOREIGN KEY (ContractId) REFERENCES hr.Contracts(Id) ON DELETE CASCADE
);

/* ---------- Chấm công ---------- */
CREATE TABLE hr.WorkShifts (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    Code         VARCHAR(20)   NOT NULL,
    Name         NVARCHAR(100) NOT NULL,
    StartTime    TIME(0)       NOT NULL,
    EndTime      TIME(0)       NOT NULL,
    BreakMinutes INT           NOT NULL DEFAULT 60,
    WorkDayValue DECIMAL(4,2)  NOT NULL DEFAULT 1,   -- 1 ca = 1 công
    CONSTRAINT PK_WorkShifts PRIMARY KEY (Id),
    CONSTRAINT FK_WorkShifts_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_WorkShifts UNIQUE (CompanyId, Code)
);

CREATE TABLE hr.Holidays (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT        NOT NULL,
    HolidayDate DATE          NOT NULL,
    Name        NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_Holidays PRIMARY KEY (Id),
    CONSTRAINT FK_Holidays_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_Holidays UNIQUE (CompanyId, HolidayDate)
);

CREATE TABLE hr.Attendances (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    EmployeeId    BIGINT        NOT NULL,
    WorkDate      DATE          NOT NULL,
    ShiftId       BIGINT        NULL,
    CheckIn       DATETIME2(0)  NULL,
    CheckOut      DATETIME2(0)  NULL,
    WorkHours     DECIMAL(5,2)  NOT NULL DEFAULT 0,
    OvertimeHours DECIMAL(5,2)  NOT NULL DEFAULT 0,
    LateMinutes   INT           NOT NULL DEFAULT 0,
    EarlyMinutes  INT           NOT NULL DEFAULT 0,
    Source        VARCHAR(10)   NOT NULL DEFAULT 'device',
    Latitude      DECIMAL(9,6)  NULL,
    Longitude     DECIMAL(9,6)  NULL,
    Status        VARCHAR(12)   NOT NULL DEFAULT 'present',
    Note          NVARCHAR(500) NULL,
    CONSTRAINT PK_Attendances PRIMARY KEY (Id),
    CONSTRAINT FK_Attendances_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_Attendances_Shifts FOREIGN KEY (ShiftId) REFERENCES hr.WorkShifts(Id),
    CONSTRAINT UQ_Attendances UNIQUE (EmployeeId, WorkDate, ShiftId),
    CONSTRAINT CK_Attendances_Source CHECK (Source IN ('device','mobile','web','manual')),
    CONSTRAINT CK_Attendances_Status CHECK (Status IN ('present','absent','leave','holiday','business_trip')),
    CONSTRAINT CK_Attendances_Time CHECK (CheckOut IS NULL OR CheckIn IS NULL OR CheckOut >= CheckIn)
);
CREATE INDEX IX_Attendances_Date ON hr.Attendances(WorkDate);

/* ---------- Nghỉ phép ---------- */
CREATE TABLE hr.LeaveTypes (
    Id                 BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId          BIGINT        NOT NULL,
    Code               VARCHAR(20)   NOT NULL,
    Name               NVARCHAR(100) NOT NULL,   -- 'Phép năm', 'Ốm', 'Thai sản', 'Không lương'
    IsPaid             BIT           NOT NULL DEFAULT 1,
    DefaultDaysPerYear DECIMAL(5,2)  NOT NULL DEFAULT 0,
    CONSTRAINT PK_LeaveTypes PRIMARY KEY (Id),
    CONSTRAINT FK_LeaveTypes_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_LeaveTypes UNIQUE (CompanyId, Code)
);
CREATE TABLE hr.LeaveBalances (
    EmployeeId   BIGINT       NOT NULL,
    LeaveTypeId  BIGINT       NOT NULL,
    LeaveYear    SMALLINT     NOT NULL,
    EntitledDays DECIMAL(5,2) NOT NULL DEFAULT 0,
    CarriedDays  DECIMAL(5,2) NOT NULL DEFAULT 0,
    UsedDays     DECIMAL(5,2) NOT NULL DEFAULT 0,
    RemainingDays AS (EntitledDays + CarriedDays - UsedDays) PERSISTED,
    CONSTRAINT PK_LeaveBalances PRIMARY KEY (EmployeeId, LeaveTypeId, LeaveYear),
    CONSTRAINT FK_LeaveBalances_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_LeaveBalances_Types FOREIGN KEY (LeaveTypeId) REFERENCES hr.LeaveTypes(Id)
);
CREATE TABLE hr.LeaveRequests (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    EmployeeId   BIGINT        NOT NULL,
    LeaveTypeId  BIGINT        NOT NULL,
    FromDate     DATETIME2(0)  NOT NULL,
    ToDate       DATETIME2(0)  NOT NULL,
    Days         DECIMAL(5,2)  NOT NULL,
    Reason       NVARCHAR(1000) NULL,
    Status       VARCHAR(12)   NOT NULL DEFAULT 'draft',
    ApproverUserId BIGINT      NULL,
    ApprovedAt   DATETIME2(3)  NULL,
    RejectReason NVARCHAR(500) NULL,
    CreatedAt    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_LeaveRequests PRIMARY KEY (Id),
    CONSTRAINT FK_LeaveRequests_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_LeaveRequests_Types FOREIGN KEY (LeaveTypeId) REFERENCES hr.LeaveTypes(Id),
    CONSTRAINT FK_LeaveRequests_Approver FOREIGN KEY (ApproverUserId) REFERENCES core.Users(Id),
    CONSTRAINT CK_LeaveRequests_Status CHECK (Status IN ('draft','submitted','approved','rejected','cancelled')),
    CONSTRAINT CK_LeaveRequests_Dates CHECK (ToDate >= FromDate AND Days > 0)
);
CREATE INDEX IX_LeaveRequests_Employee ON hr.LeaveRequests(EmployeeId, FromDate);

/* ---------- Tính lương ---------- */
CREATE TABLE hr.PayrollPeriods (
    Id             BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId      BIGINT       NOT NULL,
    PeriodYear     SMALLINT     NOT NULL,
    PeriodMonth    TINYINT      NOT NULL,
    StandardDays   DECIMAL(5,2) NOT NULL DEFAULT 26,   -- công chuẩn
    Status         VARCHAR(12)  NOT NULL DEFAULT 'draft',
    JournalEntryId BIGINT       NULL,                   -- bút toán hạch toán lương (FK ở 10_accounting)
    ApprovedBy     BIGINT       NULL,
    ApprovedAt     DATETIME2(3) NULL,
    CreatedAt      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_PayrollPeriods PRIMARY KEY (Id),
    CONSTRAINT FK_PayrollPeriods_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_PayrollPeriods UNIQUE (CompanyId, PeriodYear, PeriodMonth),
    CONSTRAINT CK_PayrollPeriods_Month CHECK (PeriodMonth BETWEEN 1 AND 12),
    CONSTRAINT CK_PayrollPeriods_Status CHECK (Status IN ('draft','calculated','approved','paid','closed'))
);

CREATE TABLE hr.Payslips (
    Id                 BIGINT IDENTITY(1,1) NOT NULL,
    PayrollPeriodId    BIGINT        NOT NULL,
    EmployeeId         BIGINT        NOT NULL,
    ContractId         BIGINT        NULL,
    ActualDays         DECIMAL(5,2)  NOT NULL DEFAULT 0,
    PaidLeaveDays      DECIMAL(5,2)  NOT NULL DEFAULT 0,
    OvertimeHours      DECIMAL(6,2)  NOT NULL DEFAULT 0,
    BaseSalary         DECIMAL(18,2) NOT NULL DEFAULT 0,
    TotalAllowance     DECIMAL(18,2) NOT NULL DEFAULT 0,
    OvertimePay        DECIMAL(18,2) NOT NULL DEFAULT 0,
    Bonus              DECIMAL(18,2) NOT NULL DEFAULT 0,
    GrossIncome        DECIMAL(18,2) NOT NULL DEFAULT 0,
    SocialInsurance    DECIMAL(18,2) NOT NULL DEFAULT 0,   -- NLĐ 8%
    HealthInsurance    DECIMAL(18,2) NOT NULL DEFAULT 0,   -- NLĐ 1,5%
    UnemploymentInsurance DECIMAL(18,2) NOT NULL DEFAULT 0,-- NLĐ 1%
    UnionFee           DECIMAL(18,2) NOT NULL DEFAULT 0,
    TaxableIncome      DECIMAL(18,2) NOT NULL DEFAULT 0,
    PersonalIncomeTax  DECIMAL(18,2) NOT NULL DEFAULT 0,
    Advance            DECIMAL(18,2) NOT NULL DEFAULT 0,   -- tạm ứng
    OtherDeductions    DECIMAL(18,2) NOT NULL DEFAULT 0,
    NetPay             DECIMAL(18,2) NOT NULL DEFAULT 0,
    EmployerInsurance  DECIMAL(18,2) NOT NULL DEFAULT 0,   -- DN đóng (21,5%)
    Status             VARCHAR(12)   NOT NULL DEFAULT 'draft',
    PaidAt             DATETIME2(3)  NULL,
    CONSTRAINT PK_Payslips PRIMARY KEY (Id),
    CONSTRAINT FK_Payslips_Periods FOREIGN KEY (PayrollPeriodId) REFERENCES hr.PayrollPeriods(Id),
    CONSTRAINT FK_Payslips_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_Payslips_Contracts FOREIGN KEY (ContractId) REFERENCES hr.Contracts(Id),
    CONSTRAINT UQ_Payslips UNIQUE (PayrollPeriodId, EmployeeId),
    CONSTRAINT CK_Payslips_Status CHECK (Status IN ('draft','confirmed','paid'))
);

/* Chi tiết từng khoản trên phiếu lương - linh hoạt khi công thức lương thay đổi */
CREATE TABLE hr.PayslipLines (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    PayslipId  BIGINT        NOT NULL,
    Code       VARCHAR(30)   NOT NULL,
    Name       NVARCHAR(150) NOT NULL,
    Category   VARCHAR(12)   NOT NULL,
    Amount     DECIMAL(18,2) NOT NULL,
    SortOrder  INT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_PayslipLines PRIMARY KEY (Id),
    CONSTRAINT FK_PayslipLines_Payslips FOREIGN KEY (PayslipId) REFERENCES hr.Payslips(Id) ON DELETE CASCADE,
    CONSTRAINT CK_PayslipLines_Category CHECK (Category IN ('earning','deduction','employer','info'))
);

/* ---------- Tuyển dụng ---------- */
CREATE TABLE hr.JobOpenings (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    Title        NVARCHAR(200) NOT NULL,
    DepartmentId BIGINT        NULL,
    PositionId   BIGINT        NULL,
    Quantity     INT           NOT NULL DEFAULT 1,
    Description  NVARCHAR(MAX) NULL,
    SalaryFrom   DECIMAL(18,2) NULL,
    SalaryTo     DECIMAL(18,2) NULL,
    Deadline     DATE          NULL,
    Status       VARCHAR(10)   NOT NULL DEFAULT 'open',
    IsPublishedWeb BIT         NOT NULL DEFAULT 0,
    CreatedAt    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_JobOpenings PRIMARY KEY (Id),
    CONSTRAINT FK_JobOpenings_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_JobOpenings_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT FK_JobOpenings_Positions FOREIGN KEY (PositionId) REFERENCES hr.Positions(Id),
    CONSTRAINT CK_JobOpenings_Status CHECK (Status IN ('draft','open','paused','closed'))
);
CREATE TABLE hr.Candidates (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    JobOpeningId  BIGINT        NOT NULL,
    FullName      NVARCHAR(150) NOT NULL,
    Phone         VARCHAR(20)   NULL,
    Email         VARCHAR(255)  NULL,
    CvAttachmentId BIGINT       NULL,
    Source        NVARCHAR(100) NULL,
    Stage         VARCHAR(15)   NOT NULL DEFAULT 'new',
    Rating        TINYINT       NULL,
    ExpectedSalary DECIMAL(18,2) NULL,
    InterviewAt   DATETIME2(0)  NULL,
    Note          NVARCHAR(MAX) NULL,
    HiredEmployeeId BIGINT      NULL,
    CreatedAt     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_Candidates PRIMARY KEY (Id),
    CONSTRAINT FK_Candidates_JobOpenings FOREIGN KEY (JobOpeningId) REFERENCES hr.JobOpenings(Id),
    CONSTRAINT FK_Candidates_Attachments FOREIGN KEY (CvAttachmentId) REFERENCES core.Attachments(Id),
    CONSTRAINT FK_Candidates_Employees FOREIGN KEY (HiredEmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT CK_Candidates_Stage CHECK (Stage IN ('new','screening','interview','offer','hired','rejected')),
    CONSTRAINT CK_Candidates_Rating CHECK (Rating IS NULL OR Rating BETWEEN 1 AND 5)
);
GO
GO

-- ===================== 04_inventory.sql =====================
/* =====================================================================
   MyERP - 04. KHO (inv)
   Thiết kế 3 lớp:
     1. StockDocuments + Lines : chứng từ (phiếu nhập / xuất / chuyển / điều chỉnh)
     2. StockLedger            : sổ kho bất biến, mỗi dòng 1 biến động (chỉ INSERT)
     3. StockBalances          : tồn hiện tại (bảng tổng hợp để đọc nhanh)
   Tồn kho luôn tính lại được từ StockLedger => kiểm toán được.
   ===================================================================== */
CREATE SCHEMA inv;
GO

CREATE TABLE inv.Warehouses (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId     BIGINT        NOT NULL,
    BranchId      BIGINT        NULL,
    Code          VARCHAR(20)   NOT NULL,
    Name          NVARCHAR(150) NOT NULL,
    Street        NVARCHAR(255) NULL,
    WardCode      VARCHAR(10)   NULL,
    ProvinceCode  VARCHAR(10)   NULL,
    ManagerUserId BIGINT        NULL,
    AllowNegativeStock BIT      NOT NULL DEFAULT 0,
    IsActive      BIT           NOT NULL DEFAULT 1,
    CreatedAt     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted     BIT NOT NULL DEFAULT 0,
    RowVersion    ROWVERSION NOT NULL,
    CONSTRAINT PK_Warehouses PRIMARY KEY (Id),
    CONSTRAINT FK_Warehouses_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Warehouses_Branches FOREIGN KEY (BranchId) REFERENCES core.Branches(Id),
    CONSTRAINT FK_Warehouses_Wards FOREIGN KEY (WardCode) REFERENCES md.Wards(Code),
    CONSTRAINT FK_Warehouses_Provinces FOREIGN KEY (ProvinceCode) REFERENCES md.Provinces(Code),
    CONSTRAINT FK_Warehouses_Manager FOREIGN KEY (ManagerUserId) REFERENCES core.Users(Id),
    CONSTRAINT UQ_Warehouses UNIQUE (CompanyId, Code)
);

/* Vị trí trong kho: khu / kệ / ô */
CREATE TABLE inv.Locations (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    WarehouseId  BIGINT        NOT NULL,
    ParentId     BIGINT        NULL,
    Code         VARCHAR(30)   NOT NULL,      -- 'A-01-03'
    Name         NVARCHAR(100) NOT NULL,
    IsActive     BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_Locations PRIMARY KEY (Id),
    CONSTRAINT FK_Locations_Warehouses FOREIGN KEY (WarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT FK_Locations_Parent FOREIGN KEY (ParentId) REFERENCES inv.Locations(Id),
    CONSTRAINT UQ_Locations UNIQUE (WarehouseId, Code)
);

/* Lô / số serial */
CREATE TABLE inv.Lots (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT       NOT NULL,
    ProductId       BIGINT       NOT NULL,
    LotNo           VARCHAR(50)  NOT NULL,     -- số lô hoặc số serial
    ManufactureDate DATE         NULL,
    ExpiryDate      DATE         NULL,
    Note            NVARCHAR(500) NULL,
    CreatedAt       DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Lots PRIMARY KEY (Id),
    CONSTRAINT FK_Lots_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Lots_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT UQ_Lots UNIQUE (ProductId, LotNo)
);
CREATE INDEX IX_Lots_Expiry ON inv.Lots(ExpiryDate) WHERE ExpiryDate IS NOT NULL;

/* ---------- Chứng từ kho ---------- */
CREATE TABLE inv.StockDocuments (
    Id               BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId        BIGINT        NOT NULL,
    DocNo            VARCHAR(30)   NOT NULL,
    DocType          VARCHAR(12)   NOT NULL,
    Reason           VARCHAR(20)   NOT NULL,
    WarehouseId      BIGINT        NOT NULL,
    DestWarehouseId  BIGINT        NULL,          -- dùng cho chuyển kho
    PartnerId        BIGINT        NULL,
    SourceType       VARCHAR(30)   NULL,          -- 'sales.SalesOrders','pur.PurchaseOrders'...
    SourceId         BIGINT        NULL,
    SourceDocNo      VARCHAR(30)   NULL,
    DocDate          DATETIME2(0)  NOT NULL,
    Status           VARCHAR(10)   NOT NULL DEFAULT 'draft',
    DeliverName      NVARCHAR(150) NULL,          -- người giao / nhận
    Note             NVARCHAR(1000) NULL,
    TotalQuantity    DECIMAL(18,4) NOT NULL DEFAULT 0,
    TotalValue       DECIMAL(18,2) NOT NULL DEFAULT 0,
    JournalEntryId   BIGINT        NULL,          -- FK ở 10_accounting
    DoneAt           DATETIME2(3)  NULL,
    DoneBy           BIGINT        NULL,
    CreatedAt        DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted        BIT NOT NULL DEFAULT 0,
    RowVersion       ROWVERSION NOT NULL,
    CONSTRAINT PK_StockDocuments PRIMARY KEY (Id),
    CONSTRAINT FK_StockDocuments_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_StockDocuments_Warehouse FOREIGN KEY (WarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT FK_StockDocuments_DestWarehouse FOREIGN KEY (DestWarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT FK_StockDocuments_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT UQ_StockDocuments UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_StockDocuments_Type CHECK (DocType IN ('receipt','issue','transfer','adjustment')),
    CONSTRAINT CK_StockDocuments_Reason CHECK (Reason IN ('purchase','sale','sale_return','purchase_return','transfer','production','internal_use','count','opening','scrap','other')),
    CONSTRAINT CK_StockDocuments_Status CHECK (Status IN ('draft','confirmed','done','cancelled')),
    CONSTRAINT CK_StockDocuments_Transfer CHECK (DocType <> 'transfer' OR (DestWarehouseId IS NOT NULL AND DestWarehouseId <> WarehouseId))
);
CREATE INDEX IX_StockDocuments_Source ON inv.StockDocuments(SourceType, SourceId);
CREATE INDEX IX_StockDocuments_Date ON inv.StockDocuments(CompanyId, DocDate DESC);

CREATE TABLE inv.StockDocumentLines (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    DocumentId      BIGINT        NOT NULL,
    LineNumber      INT           NOT NULL,
    ProductId       BIGINT        NOT NULL,
    LotId           BIGINT        NULL,
    LocationId      BIGINT        NULL,
    DestLocationId  BIGINT        NULL,
    UomId           BIGINT        NOT NULL,
    Quantity        DECIMAL(18,4) NOT NULL,       -- theo UomId
    BaseQuantity    DECIMAL(18,4) NOT NULL,       -- quy đổi về đơn vị cơ bản
    UnitCost        DECIMAL(18,4) NOT NULL DEFAULT 0,
    LineValue       DECIMAL(18,2) NOT NULL DEFAULT 0,
    SourceLineId    BIGINT        NULL,           -- dòng đơn hàng / đơn mua gốc
    Note            NVARCHAR(500) NULL,
    CONSTRAINT PK_StockDocumentLines PRIMARY KEY (Id),
    CONSTRAINT FK_StockDocumentLines_Doc FOREIGN KEY (DocumentId) REFERENCES inv.StockDocuments(Id) ON DELETE CASCADE,
    CONSTRAINT FK_StockDocumentLines_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_StockDocumentLines_Lots FOREIGN KEY (LotId) REFERENCES inv.Lots(Id),
    CONSTRAINT FK_StockDocumentLines_Location FOREIGN KEY (LocationId) REFERENCES inv.Locations(Id),
    CONSTRAINT FK_StockDocumentLines_DestLocation FOREIGN KEY (DestLocationId) REFERENCES inv.Locations(Id),
    CONSTRAINT FK_StockDocumentLines_Uom FOREIGN KEY (UomId) REFERENCES md.UnitsOfMeasure(Id),
    CONSTRAINT UQ_StockDocumentLines UNIQUE (DocumentId, LineNumber),
    CONSTRAINT CK_StockDocumentLines_Qty CHECK (Quantity <> 0 AND UnitCost >= 0)
);
CREATE INDEX IX_StockDocumentLines_Product ON inv.StockDocumentLines(ProductId);

/* ---------- Sổ kho bất biến ---------- */
CREATE TABLE inv.StockLedger (
    Id                   BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId            BIGINT        NOT NULL,
    ProductId            BIGINT        NOT NULL,
    WarehouseId          BIGINT        NOT NULL,
    LocationId           BIGINT        NULL,
    LotId                BIGINT        NULL,
    MoveDate             DATETIME2(0)  NOT NULL,
    QtyIn                DECIMAL(18,4) NOT NULL DEFAULT 0,
    QtyOut               DECIMAL(18,4) NOT NULL DEFAULT 0,
    UnitCost             DECIMAL(18,4) NOT NULL DEFAULT 0,
    ValueIn              DECIMAL(18,2) NOT NULL DEFAULT 0,
    ValueOut             DECIMAL(18,2) NOT NULL DEFAULT 0,
    StockDocumentId      BIGINT        NOT NULL,
    StockDocumentLineId  BIGINT        NOT NULL,
    CreatedAt            DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_StockLedger PRIMARY KEY (Id),
    CONSTRAINT FK_StockLedger_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_StockLedger_Warehouses FOREIGN KEY (WarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT FK_StockLedger_Locations FOREIGN KEY (LocationId) REFERENCES inv.Locations(Id),
    CONSTRAINT FK_StockLedger_Lots FOREIGN KEY (LotId) REFERENCES inv.Lots(Id),
    CONSTRAINT FK_StockLedger_Doc FOREIGN KEY (StockDocumentId) REFERENCES inv.StockDocuments(Id),
    CONSTRAINT FK_StockLedger_DocLine FOREIGN KEY (StockDocumentLineId) REFERENCES inv.StockDocumentLines(Id),
    CONSTRAINT CK_StockLedger_Qty CHECK (QtyIn >= 0 AND QtyOut >= 0 AND (QtyIn = 0 OR QtyOut = 0))
);
CREATE INDEX IX_StockLedger_Product_Wh_Date ON inv.StockLedger(ProductId, WarehouseId, MoveDate) INCLUDE (QtyIn, QtyOut, ValueIn, ValueOut);

/* ---------- Tồn hiện tại ---------- */
CREATE TABLE inv.StockBalances (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    WarehouseId  BIGINT        NOT NULL,
    ProductId    BIGINT        NOT NULL,
    LocationId   BIGINT        NULL,
    LotId        BIGINT        NULL,
    QtyOnHand    DECIMAL(18,4) NOT NULL DEFAULT 0,
    QtyReserved  DECIMAL(18,4) NOT NULL DEFAULT 0,   -- đã giữ cho đơn hàng
    QtyIncoming  DECIMAL(18,4) NOT NULL DEFAULT 0,   -- đang về từ đơn mua
    QtyAvailable AS (QtyOnHand - QtyReserved) PERSISTED,
    AvgCost      DECIMAL(18,4) NOT NULL DEFAULT 0,
    UpdatedAt    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion   ROWVERSION    NOT NULL,
    CONSTRAINT PK_StockBalances PRIMARY KEY (Id),
    CONSTRAINT FK_StockBalances_Warehouses FOREIGN KEY (WarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT FK_StockBalances_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_StockBalances_Locations FOREIGN KEY (LocationId) REFERENCES inv.Locations(Id),
    CONSTRAINT FK_StockBalances_Lots FOREIGN KEY (LotId) REFERENCES inv.Lots(Id),
    CONSTRAINT UQ_StockBalances UNIQUE (WarehouseId, ProductId, LocationId, LotId),
    CONSTRAINT CK_StockBalances_Reserved CHECK (QtyReserved >= 0 AND QtyIncoming >= 0)
);
CREATE INDEX IX_StockBalances_Product ON inv.StockBalances(ProductId) INCLUDE (QtyOnHand, QtyReserved);

/* ---------- Kiểm kê ---------- */
CREATE TABLE inv.InventoryCounts (
    Id             BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId      BIGINT        NOT NULL,
    DocNo          VARCHAR(30)   NOT NULL,
    WarehouseId    BIGINT        NOT NULL,
    CountDate      DATETIME2(0)  NOT NULL,
    Status         VARCHAR(12)   NOT NULL DEFAULT 'draft',
    AdjustmentDocId BIGINT       NULL,           -- phiếu điều chỉnh sinh ra khi hoàn tất
    Note           NVARCHAR(1000) NULL,
    CreatedAt      DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_InventoryCounts PRIMARY KEY (Id),
    CONSTRAINT FK_InventoryCounts_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_InventoryCounts_Warehouses FOREIGN KEY (WarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT FK_InventoryCounts_AdjDoc FOREIGN KEY (AdjustmentDocId) REFERENCES inv.StockDocuments(Id),
    CONSTRAINT UQ_InventoryCounts UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_InventoryCounts_Status CHECK (Status IN ('draft','in_progress','done','cancelled'))
);
CREATE TABLE inv.InventoryCountLines (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CountId     BIGINT        NOT NULL,
    ProductId   BIGINT        NOT NULL,
    LocationId  BIGINT        NULL,
    LotId       BIGINT        NULL,
    SystemQty   DECIMAL(18,4) NOT NULL,
    CountedQty  DECIMAL(18,4) NULL,
    DiffQty     AS (ISNULL(CountedQty, SystemQty) - SystemQty) PERSISTED,
    Note        NVARCHAR(500) NULL,
    CONSTRAINT PK_InventoryCountLines PRIMARY KEY (Id),
    CONSTRAINT FK_InventoryCountLines_Counts FOREIGN KEY (CountId) REFERENCES inv.InventoryCounts(Id) ON DELETE CASCADE,
    CONSTRAINT FK_InventoryCountLines_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_InventoryCountLines_Locations FOREIGN KEY (LocationId) REFERENCES inv.Locations(Id),
    CONSTRAINT FK_InventoryCountLines_Lots FOREIGN KEY (LotId) REFERENCES inv.Lots(Id)
);
GO
GO

-- ===================== 05_crm.sql =====================
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
GO

-- ===================== 06_sales.sql =====================
/* =====================================================================
   MyERP - 06. BÁN HÀNG (sales): báo giá, đơn bán, trả hàng.
   Mỗi dòng đơn theo dõi QtyDelivered / QtyInvoiced / QtyReturned để
   biết đơn đã giao, đã xuất hóa đơn bao nhiêu (giao/xuất từng phần).
   ===================================================================== */
CREATE SCHEMA sales;
GO

CREATE TABLE sales.Quotations (
    Id                BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId         BIGINT         NOT NULL,
    BranchId          BIGINT         NULL,
    DocNo             VARCHAR(30)    NOT NULL,
    RevisionNo        INT            NOT NULL DEFAULT 0,   -- báo giá chỉnh sửa lần thứ mấy
    PartnerId         BIGINT         NOT NULL,
    ContactId         BIGINT         NULL,
    OpportunityId     BIGINT         NULL,
    QuoteDate         DATE           NOT NULL,
    ValidUntil        DATE           NULL,
    CurrencyCode      CHAR(3)        NOT NULL DEFAULT 'VND',
    ExchangeRate      DECIMAL(18,6)  NOT NULL DEFAULT 1,
    PriceListId       BIGINT         NULL,
    PaymentTermId     BIGINT         NULL,
    SalespersonUserId BIGINT         NULL,
    BillingAddressId  BIGINT         NULL,
    ShippingAddressId BIGINT         NULL,
    Status            VARCHAR(20)    NOT NULL DEFAULT 'draft',
    SubTotal          DECIMAL(18,2)  NOT NULL DEFAULT 0,   -- tổng trước chiết khấu & thuế
    DiscountAmount    DECIMAL(18,2)  NOT NULL DEFAULT 0,
    TaxAmount         DECIMAL(18,2)  NOT NULL DEFAULT 0,
    ShippingFee       DECIMAL(18,2)  NOT NULL DEFAULT 0,
    TotalAmount       DECIMAL(18,2)  NOT NULL DEFAULT 0,
    Terms             NVARCHAR(MAX)  NULL,                 -- điều khoản
    Note              NVARCHAR(MAX)  NULL,
    SentAt            DATETIME2(3)   NULL,
    AcceptedAt        DATETIME2(3)   NULL,
    RejectedReason    NVARCHAR(500)  NULL,
    CreatedAt         DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted         BIT NOT NULL DEFAULT 0,
    RowVersion        ROWVERSION NOT NULL,
    CONSTRAINT PK_Quotations PRIMARY KEY (Id),
    CONSTRAINT FK_Quotations_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Quotations_Branches FOREIGN KEY (BranchId) REFERENCES core.Branches(Id),
    CONSTRAINT FK_Quotations_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_Quotations_Contacts FOREIGN KEY (ContactId) REFERENCES md.PartnerContacts(Id),
    CONSTRAINT FK_Quotations_Opportunities FOREIGN KEY (OpportunityId) REFERENCES crm.Opportunities(Id),
    CONSTRAINT FK_Quotations_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT FK_Quotations_PriceLists FOREIGN KEY (PriceListId) REFERENCES md.PriceLists(Id),
    CONSTRAINT FK_Quotations_PaymentTerms FOREIGN KEY (PaymentTermId) REFERENCES md.PaymentTerms(Id),
    CONSTRAINT FK_Quotations_Salesperson FOREIGN KEY (SalespersonUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Quotations_BillingAddr FOREIGN KEY (BillingAddressId) REFERENCES md.PartnerAddresses(Id),
    CONSTRAINT FK_Quotations_ShippingAddr FOREIGN KEY (ShippingAddressId) REFERENCES md.PartnerAddresses(Id),
    CONSTRAINT UQ_Quotations_DocNo UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_Quotations_Status CHECK (Status IN ('draft','pending_approval','approved','sent','accepted','rejected','expired','cancelled')),
    CONSTRAINT CK_Quotations_Amounts CHECK (SubTotal >= 0 AND DiscountAmount >= 0 AND TaxAmount >= 0 AND TotalAmount >= 0),
    CONSTRAINT CK_Quotations_Dates CHECK (ValidUntil IS NULL OR ValidUntil >= QuoteDate)
);
CREATE INDEX IX_Quotations_Partner ON sales.Quotations(PartnerId, QuoteDate DESC);
CREATE INDEX IX_Quotations_Status ON sales.Quotations(CompanyId, Status) WHERE IsDeleted = 0;
CREATE INDEX IX_Quotations_Opportunity ON sales.Quotations(OpportunityId) WHERE OpportunityId IS NOT NULL;

CREATE TABLE sales.QuotationLines (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    QuotationId     BIGINT         NOT NULL,
    LineNumber      INT            NOT NULL,
    ProductId       BIGINT         NULL,          -- NULL = dòng ghi chú / mục tự do
    Description     NVARCHAR(1000) NOT NULL,
    UomId           BIGINT         NULL,
    Quantity        DECIMAL(18,4)  NOT NULL DEFAULT 1,
    UnitPrice       DECIMAL(18,4)  NOT NULL DEFAULT 0,
    DiscountPercent DECIMAL(9,4)   NOT NULL DEFAULT 0,
    DiscountAmount  DECIMAL(18,2)  NOT NULL DEFAULT 0,
    TaxId           BIGINT         NULL,
    TaxRate         DECIMAL(9,4)   NOT NULL DEFAULT 0,   -- chốt thuế suất tại thời điểm lập
    LineSubTotal    DECIMAL(18,2)  NOT NULL DEFAULT 0,   -- sau chiết khấu, trước thuế
    LineTax         DECIMAL(18,2)  NOT NULL DEFAULT 0,
    LineTotal       DECIMAL(18,2)  NOT NULL DEFAULT 0,
    IsOptional      BIT            NOT NULL DEFAULT 0,   -- hạng mục tùy chọn
    CONSTRAINT PK_QuotationLines PRIMARY KEY (Id),
    CONSTRAINT FK_QuotationLines_Quotations FOREIGN KEY (QuotationId) REFERENCES sales.Quotations(Id) ON DELETE CASCADE,
    CONSTRAINT FK_QuotationLines_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_QuotationLines_Uom FOREIGN KEY (UomId) REFERENCES md.UnitsOfMeasure(Id),
    CONSTRAINT FK_QuotationLines_Taxes FOREIGN KEY (TaxId) REFERENCES md.Taxes(Id),
    CONSTRAINT UQ_QuotationLines UNIQUE (QuotationId, LineNumber),
    CONSTRAINT CK_QuotationLines CHECK (Quantity >= 0 AND UnitPrice >= 0 AND DiscountPercent BETWEEN 0 AND 100)
);

CREATE TABLE sales.SalesOrders (
    Id                BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId         BIGINT         NOT NULL,
    BranchId          BIGINT         NULL,
    DocNo             VARCHAR(30)    NOT NULL,
    QuotationId       BIGINT         NULL,
    PartnerId         BIGINT         NOT NULL,
    ContactId         BIGINT         NULL,
    OrderDate         DATETIME2(0)   NOT NULL,
    ExpectedDeliveryDate DATE        NULL,
    Channel           VARCHAR(12)    NOT NULL DEFAULT 'direct',
    ExternalOrderNo   VARCHAR(50)    NULL,                -- mã đơn sàn TMĐT / website
    CurrencyCode      CHAR(3)        NOT NULL DEFAULT 'VND',
    ExchangeRate      DECIMAL(18,6)  NOT NULL DEFAULT 1,
    PriceListId       BIGINT         NULL,
    PaymentTermId     BIGINT         NULL,
    PaymentMethodCode VARCHAR(20)    NULL,
    SalespersonUserId BIGINT         NULL,
    WarehouseId       BIGINT         NULL,
    BillingAddressId  BIGINT         NULL,
    ShippingAddressId BIGINT         NULL,
    ReceiverName      NVARCHAR(150)  NULL,
    ReceiverPhone     VARCHAR(20)    NULL,
    ShippingStreet    NVARCHAR(255)  NULL,
    ShippingWardCode  VARCHAR(10)    NULL,
    ShippingProvinceCode VARCHAR(10) NULL,
    Status            VARCHAR(12)    NOT NULL DEFAULT 'draft',
    DeliveryStatus    VARCHAR(10)    NOT NULL DEFAULT 'pending',
    InvoiceStatus     VARCHAR(10)    NOT NULL DEFAULT 'none',
    PaymentStatus     VARCHAR(10)    NOT NULL DEFAULT 'unpaid',
    SubTotal          DECIMAL(18,2)  NOT NULL DEFAULT 0,
    DiscountAmount    DECIMAL(18,2)  NOT NULL DEFAULT 0,
    TaxAmount         DECIMAL(18,2)  NOT NULL DEFAULT 0,
    ShippingFee       DECIMAL(18,2)  NOT NULL DEFAULT 0,
    TotalAmount       DECIMAL(18,2)  NOT NULL DEFAULT 0,
    ReturnedAmount    DECIMAL(18,2)  NOT NULL DEFAULT 0,   -- giá trị hàng khách trả lại
    AmountPaid        DECIMAL(18,2)  NOT NULL DEFAULT 0,
    Note              NVARCHAR(MAX)  NULL,
    InternalNote      NVARCHAR(MAX)  NULL,
    ConfirmedAt       DATETIME2(3)   NULL,
    ConfirmedBy       BIGINT         NULL,
    CancelledAt       DATETIME2(3)   NULL,
    CancelReason      NVARCHAR(500)  NULL,
    CreatedAt         DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted         BIT NOT NULL DEFAULT 0,
    RowVersion        ROWVERSION NOT NULL,
    CONSTRAINT PK_SalesOrders PRIMARY KEY (Id),
    CONSTRAINT FK_SalesOrders_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_SalesOrders_Branches FOREIGN KEY (BranchId) REFERENCES core.Branches(Id),
    CONSTRAINT FK_SalesOrders_Quotations FOREIGN KEY (QuotationId) REFERENCES sales.Quotations(Id),
    CONSTRAINT FK_SalesOrders_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_SalesOrders_Contacts FOREIGN KEY (ContactId) REFERENCES md.PartnerContacts(Id),
    CONSTRAINT FK_SalesOrders_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT FK_SalesOrders_PriceLists FOREIGN KEY (PriceListId) REFERENCES md.PriceLists(Id),
    CONSTRAINT FK_SalesOrders_PaymentTerms FOREIGN KEY (PaymentTermId) REFERENCES md.PaymentTerms(Id),
    CONSTRAINT FK_SalesOrders_PaymentMethods FOREIGN KEY (PaymentMethodCode) REFERENCES md.PaymentMethods(Code),
    CONSTRAINT FK_SalesOrders_Salesperson FOREIGN KEY (SalespersonUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_SalesOrders_Warehouses FOREIGN KEY (WarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT FK_SalesOrders_BillingAddr FOREIGN KEY (BillingAddressId) REFERENCES md.PartnerAddresses(Id),
    CONSTRAINT FK_SalesOrders_ShippingAddr FOREIGN KEY (ShippingAddressId) REFERENCES md.PartnerAddresses(Id),
    CONSTRAINT FK_SalesOrders_Wards FOREIGN KEY (ShippingWardCode) REFERENCES md.Wards(Code),
    CONSTRAINT FK_SalesOrders_Provinces FOREIGN KEY (ShippingProvinceCode) REFERENCES md.Provinces(Code),
    CONSTRAINT UQ_SalesOrders_DocNo UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_SalesOrders_Channel CHECK (Channel IN ('direct','phone','website','shopee','lazada','tiktok','facebook','zalo','other')),
    CONSTRAINT CK_SalesOrders_Status CHECK (Status IN ('draft','confirmed','processing','completed','cancelled')),
    CONSTRAINT CK_SalesOrders_Delivery CHECK (DeliveryStatus IN ('pending','partial','shipping','delivered','returning','returned')),
    CONSTRAINT CK_SalesOrders_Invoice CHECK (InvoiceStatus IN ('none','partial','invoiced')),
    CONSTRAINT CK_SalesOrders_Payment CHECK (PaymentStatus IN ('unpaid','partial','paid','refunded')),
    CONSTRAINT CK_SalesOrders_Amounts CHECK (TotalAmount >= 0 AND AmountPaid >= 0)
);
CREATE INDEX IX_SalesOrders_Partner ON sales.SalesOrders(PartnerId, OrderDate DESC);
CREATE INDEX IX_SalesOrders_Status ON sales.SalesOrders(CompanyId, Status, OrderDate DESC) WHERE IsDeleted = 0;
CREATE INDEX IX_SalesOrders_Salesperson ON sales.SalesOrders(SalespersonUserId, OrderDate DESC);
CREATE UNIQUE INDEX UX_SalesOrders_External ON sales.SalesOrders(CompanyId, Channel, ExternalOrderNo) WHERE ExternalOrderNo IS NOT NULL;

CREATE TABLE sales.SalesOrderLines (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    SalesOrderId    BIGINT         NOT NULL,
    LineNumber      INT            NOT NULL,
    ProductId       BIGINT         NOT NULL,
    Description     NVARCHAR(1000) NULL,
    UomId           BIGINT         NOT NULL,
    Quantity        DECIMAL(18,4)  NOT NULL,
    UnitPrice       DECIMAL(18,4)  NOT NULL,
    DiscountPercent DECIMAL(9,4)   NOT NULL DEFAULT 0,
    DiscountAmount  DECIMAL(18,2)  NOT NULL DEFAULT 0,
    TaxId           BIGINT         NULL,
    TaxRate         DECIMAL(9,4)   NOT NULL DEFAULT 0,
    LineSubTotal    DECIMAL(18,2)  NOT NULL DEFAULT 0,
    LineTax         DECIMAL(18,2)  NOT NULL DEFAULT 0,
    LineTotal       DECIMAL(18,2)  NOT NULL DEFAULT 0,
    UnitCost        DECIMAL(18,4)  NOT NULL DEFAULT 0,   -- giá vốn lúc xuất, để tính lãi gộp
    QtyDelivered    DECIMAL(18,4)  NOT NULL DEFAULT 0,
    QtyInvoiced     DECIMAL(18,4)  NOT NULL DEFAULT 0,
    QtyReturned     DECIMAL(18,4)  NOT NULL DEFAULT 0,
    QuotationLineId BIGINT         NULL,
    CONSTRAINT PK_SalesOrderLines PRIMARY KEY (Id),
    CONSTRAINT FK_SalesOrderLines_Orders FOREIGN KEY (SalesOrderId) REFERENCES sales.SalesOrders(Id) ON DELETE CASCADE,
    CONSTRAINT FK_SalesOrderLines_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_SalesOrderLines_Uom FOREIGN KEY (UomId) REFERENCES md.UnitsOfMeasure(Id),
    CONSTRAINT FK_SalesOrderLines_Taxes FOREIGN KEY (TaxId) REFERENCES md.Taxes(Id),
    CONSTRAINT FK_SalesOrderLines_QuoteLine FOREIGN KEY (QuotationLineId) REFERENCES sales.QuotationLines(Id),
    CONSTRAINT UQ_SalesOrderLines UNIQUE (SalesOrderId, LineNumber),
    CONSTRAINT CK_SalesOrderLines_Qty CHECK (Quantity > 0 AND UnitPrice >= 0 AND DiscountPercent BETWEEN 0 AND 100),
    CONSTRAINT CK_SalesOrderLines_Progress CHECK (QtyDelivered >= 0 AND QtyInvoiced >= 0 AND QtyReturned >= 0 AND QtyReturned <= QtyDelivered)
);
CREATE INDEX IX_SalesOrderLines_Product ON sales.SalesOrderLines(ProductId);

/* Giữ hàng cho đơn đã xác nhận */
CREATE TABLE inv.StockReservations (
    Id                BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId         BIGINT        NOT NULL,
    SalesOrderLineId  BIGINT        NOT NULL,
    ProductId         BIGINT        NOT NULL,
    WarehouseId       BIGINT        NOT NULL,
    LotId             BIGINT        NULL,
    Quantity          DECIMAL(18,4) NOT NULL,
    Status            VARCHAR(10)   NOT NULL DEFAULT 'active',
    CreatedAt         DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    ReleasedAt        DATETIME2(3)  NULL,
    CONSTRAINT PK_StockReservations PRIMARY KEY (Id),
    CONSTRAINT FK_StockReservations_OrderLines FOREIGN KEY (SalesOrderLineId) REFERENCES sales.SalesOrderLines(Id) ON DELETE CASCADE,
    CONSTRAINT FK_StockReservations_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_StockReservations_Warehouses FOREIGN KEY (WarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT FK_StockReservations_Lots FOREIGN KEY (LotId) REFERENCES inv.Lots(Id),
    CONSTRAINT CK_StockReservations_Status CHECK (Status IN ('active','consumed','released')),
    CONSTRAINT CK_StockReservations_Qty CHECK (Quantity > 0)
);
CREATE INDEX IX_StockReservations_Product ON inv.StockReservations(ProductId, WarehouseId) WHERE Status = 'active';

/* ---------- Trả hàng ---------- */
CREATE TABLE sales.SalesReturns (
    Id             BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId      BIGINT        NOT NULL,
    DocNo          VARCHAR(30)   NOT NULL,
    SalesOrderId   BIGINT        NOT NULL,
    PartnerId      BIGINT        NOT NULL,
    WarehouseId    BIGINT        NOT NULL,
    ReturnDate     DATETIME2(0)  NOT NULL,
    Reason         NVARCHAR(500) NULL,
    RefundMethod   VARCHAR(12)   NOT NULL DEFAULT 'credit_note',
    Status         VARCHAR(10)   NOT NULL DEFAULT 'draft',
    SubTotal       DECIMAL(18,2) NOT NULL DEFAULT 0,
    TaxAmount      DECIMAL(18,2) NOT NULL DEFAULT 0,
    TotalAmount    DECIMAL(18,2) NOT NULL DEFAULT 0,
    StockDocumentId BIGINT       NULL,
    CreatedAt      DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted      BIT NOT NULL DEFAULT 0,
    RowVersion     ROWVERSION NOT NULL,
    CONSTRAINT PK_SalesReturns PRIMARY KEY (Id),
    CONSTRAINT FK_SalesReturns_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_SalesReturns_Orders FOREIGN KEY (SalesOrderId) REFERENCES sales.SalesOrders(Id),
    CONSTRAINT FK_SalesReturns_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_SalesReturns_Warehouses FOREIGN KEY (WarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT FK_SalesReturns_StockDoc FOREIGN KEY (StockDocumentId) REFERENCES inv.StockDocuments(Id),
    CONSTRAINT UQ_SalesReturns UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_SalesReturns_Refund CHECK (RefundMethod IN ('cash','bank','credit_note','exchange')),
    CONSTRAINT CK_SalesReturns_Status CHECK (Status IN ('draft','confirmed','received','refunded','cancelled'))
);
CREATE TABLE sales.SalesReturnLines (
    Id               BIGINT IDENTITY(1,1) NOT NULL,
    SalesReturnId    BIGINT        NOT NULL,
    SalesOrderLineId BIGINT        NOT NULL,
    ProductId        BIGINT        NOT NULL,
    LotId            BIGINT        NULL,
    Quantity         DECIMAL(18,4) NOT NULL,
    UnitPrice        DECIMAL(18,4) NOT NULL,
    TaxRate          DECIMAL(9,4)  NOT NULL DEFAULT 0,
    LineTotal        DECIMAL(18,2) NOT NULL DEFAULT 0,
    Condition        VARCHAR(10)   NOT NULL DEFAULT 'good',   -- hàng còn bán được hay hỏng
    CONSTRAINT PK_SalesReturnLines PRIMARY KEY (Id),
    CONSTRAINT FK_SalesReturnLines_Returns FOREIGN KEY (SalesReturnId) REFERENCES sales.SalesReturns(Id) ON DELETE CASCADE,
    CONSTRAINT FK_SalesReturnLines_OrderLines FOREIGN KEY (SalesOrderLineId) REFERENCES sales.SalesOrderLines(Id),
    CONSTRAINT FK_SalesReturnLines_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_SalesReturnLines_Lots FOREIGN KEY (LotId) REFERENCES inv.Lots(Id),
    CONSTRAINT CK_SalesReturnLines CHECK (Quantity > 0 AND Condition IN ('good','damaged'))
);

/* Khuyến mãi / mã giảm giá */
CREATE TABLE sales.Promotions (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT        NOT NULL,
    Code            VARCHAR(30)   NOT NULL,
    Name            NVARCHAR(200) NOT NULL,
    PromotionType   VARCHAR(12)   NOT NULL,      -- percent | fixed | free_ship | buy_x_get_y
    Value           DECIMAL(18,4) NOT NULL DEFAULT 0,
    MaxDiscount     DECIMAL(18,2) NULL,
    MinOrderAmount  DECIMAL(18,2) NOT NULL DEFAULT 0,
    StartAt         DATETIME2(0)  NOT NULL,
    EndAt           DATETIME2(0)  NOT NULL,
    UsageLimit      INT           NULL,
    UsedCount       INT           NOT NULL DEFAULT 0,
    Channels        VARCHAR(200)  NULL,          -- 'direct,website'
    IsActive        BIT           NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_Promotions PRIMARY KEY (Id),
    CONSTRAINT FK_Promotions_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_Promotions UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Promotions_Type CHECK (PromotionType IN ('percent','fixed','free_ship','buy_x_get_y')),
    CONSTRAINT CK_Promotions_Dates CHECK (EndAt > StartAt)
);
CREATE TABLE sales.OrderPromotions (
    SalesOrderId    BIGINT        NOT NULL,
    PromotionId     BIGINT        NOT NULL,
    DiscountAmount  DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_OrderPromotions PRIMARY KEY (SalesOrderId, PromotionId),
    CONSTRAINT FK_OrderPromotions_Orders FOREIGN KEY (SalesOrderId) REFERENCES sales.SalesOrders(Id) ON DELETE CASCADE,
    CONSTRAINT FK_OrderPromotions_Promotions FOREIGN KEY (PromotionId) REFERENCES sales.Promotions(Id)
);
GO
GO

-- ===================== 07_purchasing.sql =====================
/* =====================================================================
   MyERP - 07. MUA HÀNG (pur): yêu cầu mua -> đơn mua -> nhận hàng (kho)
   -> hóa đơn mua vào (kế toán).
   ===================================================================== */
CREATE SCHEMA pur;
GO

CREATE TABLE pur.PurchaseRequests (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT        NOT NULL,
    DocNo           VARCHAR(30)   NOT NULL,
    RequestedBy     BIGINT        NOT NULL,
    DepartmentId    BIGINT        NULL,
    RequestDate     DATE          NOT NULL,
    NeededBy        DATE          NULL,
    Purpose         NVARCHAR(1000) NULL,
    Status          VARCHAR(12)   NOT NULL DEFAULT 'draft',
    EstimatedTotal  DECIMAL(18,2) NOT NULL DEFAULT 0,
    CreatedAt       DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted       BIT NOT NULL DEFAULT 0,
    RowVersion      ROWVERSION NOT NULL,
    CONSTRAINT PK_PurchaseRequests PRIMARY KEY (Id),
    CONSTRAINT FK_PurchaseRequests_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_PurchaseRequests_Users FOREIGN KEY (RequestedBy) REFERENCES core.Users(Id),
    CONSTRAINT FK_PurchaseRequests_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT UQ_PurchaseRequests UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_PurchaseRequests_Status CHECK (Status IN ('draft','submitted','approved','rejected','ordered','cancelled'))
);
CREATE TABLE pur.PurchaseRequestLines (
    Id                 BIGINT IDENTITY(1,1) NOT NULL,
    PurchaseRequestId  BIGINT         NOT NULL,
    LineNumber         INT            NOT NULL,
    ProductId          BIGINT         NULL,
    Description        NVARCHAR(1000) NOT NULL,
    UomId              BIGINT         NULL,
    Quantity           DECIMAL(18,4)  NOT NULL,
    EstimatedPrice     DECIMAL(18,4)  NOT NULL DEFAULT 0,
    SuggestedSupplierId BIGINT        NULL,
    QtyOrdered         DECIMAL(18,4)  NOT NULL DEFAULT 0,
    CONSTRAINT PK_PurchaseRequestLines PRIMARY KEY (Id),
    CONSTRAINT FK_PurchaseRequestLines_Req FOREIGN KEY (PurchaseRequestId) REFERENCES pur.PurchaseRequests(Id) ON DELETE CASCADE,
    CONSTRAINT FK_PurchaseRequestLines_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_PurchaseRequestLines_Uom FOREIGN KEY (UomId) REFERENCES md.UnitsOfMeasure(Id),
    CONSTRAINT FK_PurchaseRequestLines_Supplier FOREIGN KEY (SuggestedSupplierId) REFERENCES md.Partners(Id),
    CONSTRAINT UQ_PurchaseRequestLines UNIQUE (PurchaseRequestId, LineNumber),
    CONSTRAINT CK_PurchaseRequestLines CHECK (Quantity > 0)
);

CREATE TABLE pur.PurchaseOrders (
    Id                BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId         BIGINT         NOT NULL,
    BranchId          BIGINT         NULL,
    DocNo             VARCHAR(30)    NOT NULL,
    PartnerId         BIGINT         NOT NULL,           -- nhà cung cấp
    ContactId         BIGINT         NULL,
    PurchaseRequestId BIGINT         NULL,
    OrderDate         DATE           NOT NULL,
    ExpectedDate      DATE           NULL,
    WarehouseId       BIGINT         NOT NULL,
    CurrencyCode      CHAR(3)        NOT NULL DEFAULT 'VND',
    ExchangeRate      DECIMAL(18,6)  NOT NULL DEFAULT 1,
    PaymentTermId     BIGINT         NULL,
    BuyerUserId       BIGINT         NULL,
    Status            VARCHAR(20)    NOT NULL DEFAULT 'draft',
    ReceiptStatus     VARCHAR(10)    NOT NULL DEFAULT 'pending',
    BillStatus        VARCHAR(10)    NOT NULL DEFAULT 'none',
    SubTotal          DECIMAL(18,2)  NOT NULL DEFAULT 0,
    DiscountAmount    DECIMAL(18,2)  NOT NULL DEFAULT 0,
    TaxAmount         DECIMAL(18,2)  NOT NULL DEFAULT 0,
    OtherCost         DECIMAL(18,2)  NOT NULL DEFAULT 0,   -- chi phí vận chuyển, bốc xếp (phân bổ vào giá vốn)
    TotalAmount       DECIMAL(18,2)  NOT NULL DEFAULT 0,
    AmountPaid        DECIMAL(18,2)  NOT NULL DEFAULT 0,   -- đã trả nhà cung cấp
    Terms             NVARCHAR(MAX)  NULL,
    Note              NVARCHAR(MAX)  NULL,
    ConfirmedAt       DATETIME2(3)   NULL,
    CreatedAt         DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted         BIT NOT NULL DEFAULT 0,
    RowVersion        ROWVERSION NOT NULL,
    CONSTRAINT PK_PurchaseOrders PRIMARY KEY (Id),
    CONSTRAINT FK_PurchaseOrders_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_PurchaseOrders_Branches FOREIGN KEY (BranchId) REFERENCES core.Branches(Id),
    CONSTRAINT FK_PurchaseOrders_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_PurchaseOrders_Contacts FOREIGN KEY (ContactId) REFERENCES md.PartnerContacts(Id),
    CONSTRAINT FK_PurchaseOrders_Requests FOREIGN KEY (PurchaseRequestId) REFERENCES pur.PurchaseRequests(Id),
    CONSTRAINT FK_PurchaseOrders_Warehouses FOREIGN KEY (WarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT FK_PurchaseOrders_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT FK_PurchaseOrders_PaymentTerms FOREIGN KEY (PaymentTermId) REFERENCES md.PaymentTerms(Id),
    CONSTRAINT FK_PurchaseOrders_Buyer FOREIGN KEY (BuyerUserId) REFERENCES core.Users(Id),
    CONSTRAINT UQ_PurchaseOrders UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_PurchaseOrders_Status CHECK (Status IN ('draft','pending_approval','approved','sent','confirmed','completed','cancelled')),
    CONSTRAINT CK_PurchaseOrders_Receipt CHECK (ReceiptStatus IN ('pending','partial','received')),
    CONSTRAINT CK_PurchaseOrders_Bill CHECK (BillStatus IN ('none','partial','billed'))
);
CREATE INDEX IX_PurchaseOrders_Partner ON pur.PurchaseOrders(PartnerId, OrderDate DESC);
CREATE INDEX IX_PurchaseOrders_Status ON pur.PurchaseOrders(CompanyId, Status) WHERE IsDeleted = 0;

CREATE TABLE pur.PurchaseOrderLines (
    Id                     BIGINT IDENTITY(1,1) NOT NULL,
    PurchaseOrderId        BIGINT         NOT NULL,
    LineNumber             INT            NOT NULL,
    ProductId              BIGINT         NOT NULL,
    Description            NVARCHAR(1000) NULL,
    UomId                  BIGINT         NOT NULL,
    Quantity               DECIMAL(18,4)  NOT NULL,
    UnitPrice              DECIMAL(18,4)  NOT NULL,
    DiscountPercent        DECIMAL(9,4)   NOT NULL DEFAULT 0,
    TaxId                  BIGINT         NULL,
    TaxRate                DECIMAL(9,4)   NOT NULL DEFAULT 0,
    LineSubTotal           DECIMAL(18,2)  NOT NULL DEFAULT 0,
    LineTax                DECIMAL(18,2)  NOT NULL DEFAULT 0,
    LineTotal              DECIMAL(18,2)  NOT NULL DEFAULT 0,
    QtyReceived            DECIMAL(18,4)  NOT NULL DEFAULT 0,
    QtyBilled              DECIMAL(18,4)  NOT NULL DEFAULT 0,
    PurchaseRequestLineId  BIGINT         NULL,
    CONSTRAINT PK_PurchaseOrderLines PRIMARY KEY (Id),
    CONSTRAINT FK_PurchaseOrderLines_Orders FOREIGN KEY (PurchaseOrderId) REFERENCES pur.PurchaseOrders(Id) ON DELETE CASCADE,
    CONSTRAINT FK_PurchaseOrderLines_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_PurchaseOrderLines_Uom FOREIGN KEY (UomId) REFERENCES md.UnitsOfMeasure(Id),
    CONSTRAINT FK_PurchaseOrderLines_Taxes FOREIGN KEY (TaxId) REFERENCES md.Taxes(Id),
    CONSTRAINT FK_PurchaseOrderLines_ReqLine FOREIGN KEY (PurchaseRequestLineId) REFERENCES pur.PurchaseRequestLines(Id),
    CONSTRAINT UQ_PurchaseOrderLines UNIQUE (PurchaseOrderId, LineNumber),
    CONSTRAINT CK_PurchaseOrderLines CHECK (Quantity > 0 AND UnitPrice >= 0 AND QtyReceived >= 0 AND QtyBilled >= 0)
);
CREATE INDEX IX_PurchaseOrderLines_Product ON pur.PurchaseOrderLines(ProductId);
GO
GO

-- ===================== 08_logistics.sql =====================
/* =====================================================================
   MyERP - 08. VẬN CHUYỂN (lgs): hãng vận chuyển (GHN, GHTK, Viettel Post,
   J&T) hoặc xe nội bộ, vận đơn, hành trình, đối soát COD.
   ===================================================================== */
CREATE SCHEMA lgs;
GO

CREATE TABLE lgs.Carriers (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    Code         VARCHAR(20)   NOT NULL,
    Name         NVARCHAR(150) NOT NULL,
    CarrierType  VARCHAR(12)   NOT NULL DEFAULT 'third_party',
    PartnerId    BIGINT        NULL,           -- để ghi công nợ với hãng
    ApiProvider  VARCHAR(20)   NULL,           -- ghn | ghtk | viettelpost | jt | ahamove
    ApiConfig    NVARCHAR(MAX) NULL,           -- JSON, token mã hóa ở tầng ứng dụng
    IsActive     BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_Carriers PRIMARY KEY (Id),
    CONSTRAINT FK_Carriers_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Carriers_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT UQ_Carriers UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Carriers_Type CHECK (CarrierType IN ('internal','third_party'))
);

CREATE TABLE lgs.Vehicles (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT        NOT NULL,
    PlateNo     VARCHAR(20)   NOT NULL,
    VehicleType NVARCHAR(50)  NOT NULL,        -- 'Xe tải 1,5 tấn', 'Xe máy'
    CapacityKg  DECIMAL(10,2) NULL,
    DefaultDriverId BIGINT    NULL,
    IsActive    BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_Vehicles PRIMARY KEY (Id),
    CONSTRAINT FK_Vehicles_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Vehicles_Driver FOREIGN KEY (DefaultDriverId) REFERENCES hr.Employees(Id),
    CONSTRAINT UQ_Vehicles UNIQUE (CompanyId, PlateNo)
);

CREATE TABLE lgs.Shipments (
    Id               BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId        BIGINT         NOT NULL,
    DocNo            VARCHAR(30)    NOT NULL,
    SalesOrderId     BIGINT         NULL,
    StockDocumentId  BIGINT         NULL,          -- phiếu xuất kho tương ứng
    CarrierId        BIGINT         NOT NULL,
    TrackingNo       VARCHAR(50)    NULL,          -- mã vận đơn của hãng
    ServiceType      VARCHAR(30)    NULL,          -- nhanh | tiết kiệm | hỏa tốc
    VehicleId        BIGINT         NULL,
    DriverEmployeeId BIGINT         NULL,
    FromWarehouseId  BIGINT         NOT NULL,
    ReceiverName     NVARCHAR(150)  NOT NULL,
    ReceiverPhone    VARCHAR(20)    NOT NULL,
    Street           NVARCHAR(255)  NOT NULL,
    WardCode         VARCHAR(10)    NULL,
    ProvinceCode     VARCHAR(10)    NULL,
    PackageCount     INT            NOT NULL DEFAULT 1,
    WeightGram       DECIMAL(18,2)  NULL,
    CodAmount        DECIMAL(18,2)  NOT NULL DEFAULT 0,  -- tiền thu hộ
    InsuranceValue   DECIMAL(18,2)  NOT NULL DEFAULT 0,
    ShippingFee      DECIMAL(18,2)  NOT NULL DEFAULT 0,  -- phí hãng tính
    FeePayer         VARCHAR(8)     NOT NULL DEFAULT 'sender',
    Status           VARCHAR(12)    NOT NULL DEFAULT 'draft',
    CodStatus        VARCHAR(12)    NOT NULL DEFAULT 'none',
    PickedUpAt       DATETIME2(3)   NULL,
    DeliveredAt      DATETIME2(3)   NULL,
    FailedReason     NVARCHAR(500)  NULL,
    Note             NVARCHAR(1000) NULL,
    CreatedAt        DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted        BIT NOT NULL DEFAULT 0,
    RowVersion       ROWVERSION NOT NULL,
    CONSTRAINT PK_Shipments PRIMARY KEY (Id),
    CONSTRAINT FK_Shipments_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Shipments_SalesOrders FOREIGN KEY (SalesOrderId) REFERENCES sales.SalesOrders(Id),
    CONSTRAINT FK_Shipments_StockDocs FOREIGN KEY (StockDocumentId) REFERENCES inv.StockDocuments(Id),
    CONSTRAINT FK_Shipments_Carriers FOREIGN KEY (CarrierId) REFERENCES lgs.Carriers(Id),
    CONSTRAINT FK_Shipments_Vehicles FOREIGN KEY (VehicleId) REFERENCES lgs.Vehicles(Id),
    CONSTRAINT FK_Shipments_Driver FOREIGN KEY (DriverEmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_Shipments_Warehouses FOREIGN KEY (FromWarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT FK_Shipments_Wards FOREIGN KEY (WardCode) REFERENCES md.Wards(Code),
    CONSTRAINT FK_Shipments_Provinces FOREIGN KEY (ProvinceCode) REFERENCES md.Provinces(Code),
    CONSTRAINT UQ_Shipments UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_Shipments_FeePayer CHECK (FeePayer IN ('sender','receiver')),
    CONSTRAINT CK_Shipments_Status CHECK (Status IN ('draft','ready','picked_up','in_transit','delivered','failed','returning','returned','cancelled')),
    CONSTRAINT CK_Shipments_Cod CHECK (CodStatus IN ('none','pending','collected','reconciled')),
    CONSTRAINT CK_Shipments_Amounts CHECK (CodAmount >= 0 AND ShippingFee >= 0)
);
CREATE UNIQUE INDEX UX_Shipments_Tracking ON lgs.Shipments(CarrierId, TrackingNo) WHERE TrackingNo IS NOT NULL;
CREATE INDEX IX_Shipments_Order ON lgs.Shipments(SalesOrderId);
CREATE INDEX IX_Shipments_Status ON lgs.Shipments(CompanyId, Status) WHERE IsDeleted = 0;

CREATE TABLE lgs.ShipmentLines (
    Id                BIGINT IDENTITY(1,1) NOT NULL,
    ShipmentId        BIGINT        NOT NULL,
    SalesOrderLineId  BIGINT        NULL,
    ProductId         BIGINT        NOT NULL,
    Quantity          DECIMAL(18,4) NOT NULL,
    CONSTRAINT PK_ShipmentLines PRIMARY KEY (Id),
    CONSTRAINT FK_ShipmentLines_Shipments FOREIGN KEY (ShipmentId) REFERENCES lgs.Shipments(Id) ON DELETE CASCADE,
    CONSTRAINT FK_ShipmentLines_OrderLines FOREIGN KEY (SalesOrderLineId) REFERENCES sales.SalesOrderLines(Id),
    CONSTRAINT FK_ShipmentLines_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT CK_ShipmentLines CHECK (Quantity > 0)
);

/* Hành trình - nhận từ webhook của hãng vận chuyển */
CREATE TABLE lgs.ShipmentTrackingEvents (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    ShipmentId   BIGINT        NOT NULL,
    EventAt      DATETIME2(0)  NOT NULL,
    StatusCode   VARCHAR(50)   NOT NULL,       -- mã trạng thái gốc của hãng
    Description  NVARCHAR(500) NULL,
    Location     NVARCHAR(255) NULL,
    RawPayload   NVARCHAR(MAX) NULL,
    ReceivedAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ShipmentTrackingEvents PRIMARY KEY (Id),
    CONSTRAINT FK_ShipmentTrackingEvents_Shipments FOREIGN KEY (ShipmentId) REFERENCES lgs.Shipments(Id) ON DELETE CASCADE
);
CREATE INDEX IX_ShipmentTrackingEvents ON lgs.ShipmentTrackingEvents(ShipmentId, EventAt);

/* Đối soát COD với hãng */
CREATE TABLE lgs.CodReconciliations (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT        NOT NULL,
    DocNo       VARCHAR(30)   NOT NULL,
    CarrierId   BIGINT        NOT NULL,
    PeriodFrom  DATE          NOT NULL,
    PeriodTo    DATE          NOT NULL,
    TotalCod    DECIMAL(18,2) NOT NULL DEFAULT 0,
    TotalFee    DECIMAL(18,2) NOT NULL DEFAULT 0,
    NetAmount   AS (TotalCod - TotalFee) PERSISTED,
    Status      VARCHAR(10)   NOT NULL DEFAULT 'draft',
    PaymentId   BIGINT        NULL,              -- phiếu thu/báo có (FK ở 10_accounting)
    CreatedAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_CodReconciliations PRIMARY KEY (Id),
    CONSTRAINT FK_CodReconciliations_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_CodReconciliations_Carriers FOREIGN KEY (CarrierId) REFERENCES lgs.Carriers(Id),
    CONSTRAINT UQ_CodReconciliations UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_CodReconciliations_Status CHECK (Status IN ('draft','confirmed','paid','cancelled')),
    CONSTRAINT CK_CodReconciliations_Dates CHECK (PeriodTo >= PeriodFrom)
);
CREATE TABLE lgs.CodReconciliationLines (
    Id                 BIGINT IDENTITY(1,1) NOT NULL,
    ReconciliationId   BIGINT        NOT NULL,
    ShipmentId         BIGINT        NOT NULL,
    CodAmount          DECIMAL(18,2) NOT NULL,
    ShippingFee        DECIMAL(18,2) NOT NULL,
    Note               NVARCHAR(255) NULL,
    CONSTRAINT PK_CodReconciliationLines PRIMARY KEY (Id),
    CONSTRAINT FK_CodReconLines_Recon FOREIGN KEY (ReconciliationId) REFERENCES lgs.CodReconciliations(Id) ON DELETE CASCADE,
    CONSTRAINT FK_CodReconLines_Shipments FOREIGN KEY (ShipmentId) REFERENCES lgs.Shipments(Id),
    CONSTRAINT UQ_CodReconLines_Shipment UNIQUE (ShipmentId)   -- 1 vận đơn chỉ đối soát 1 lần
);
GO
GO

-- ===================== 09_marketing.sql =====================
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
GO

-- ===================== 10_accounting.sql =====================
/* =====================================================================
   MyERP - 10. KẾ TOÁN (acc) theo chế độ kế toán Việt Nam (TT200/TT133).
   Nguyên tắc:
     - Mọi nghiệp vụ tài chính cuối cùng đều sinh JournalEntry (bút toán kép).
     - Bút toán đã ghi sổ (posted) không sửa/xóa, chỉ được đảo (reverse).
     - Kỳ kế toán đã khóa thì không ghi thêm.
     - Hóa đơn điện tử theo NĐ 123/2020, TT 78/2021.
   ===================================================================== */
CREATE SCHEMA acc;
GO

CREATE TABLE acc.FiscalYears (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId  BIGINT       NOT NULL,
    Code       VARCHAR(10)  NOT NULL,         -- '2026'
    StartDate  DATE         NOT NULL,
    EndDate    DATE         NOT NULL,
    Status     VARCHAR(8)   NOT NULL DEFAULT 'open',
    CONSTRAINT PK_FiscalYears PRIMARY KEY (Id),
    CONSTRAINT FK_FiscalYears_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_FiscalYears UNIQUE (CompanyId, Code),
    CONSTRAINT CK_FiscalYears_Status CHECK (Status IN ('open','closed')),
    CONSTRAINT CK_FiscalYears_Dates CHECK (EndDate > StartDate)
);
CREATE TABLE acc.FiscalPeriods (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    FiscalYearId  BIGINT       NOT NULL,
    PeriodNo      TINYINT      NOT NULL,
    StartDate     DATE         NOT NULL,
    EndDate       DATE         NOT NULL,
    Status        VARCHAR(8)   NOT NULL DEFAULT 'open',
    ClosedAt      DATETIME2(3) NULL,
    ClosedBy      BIGINT       NULL,
    CONSTRAINT PK_FiscalPeriods PRIMARY KEY (Id),
    CONSTRAINT FK_FiscalPeriods_Years FOREIGN KEY (FiscalYearId) REFERENCES acc.FiscalYears(Id) ON DELETE CASCADE,
    CONSTRAINT UQ_FiscalPeriods UNIQUE (FiscalYearId, PeriodNo),
    CONSTRAINT CK_FiscalPeriods_Status CHECK (Status IN ('open','closed')),
    CONSTRAINT CK_FiscalPeriods_Dates CHECK (EndDate >= StartDate)
);

/* Hệ thống tài khoản */
CREATE TABLE acc.Accounts (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT        NOT NULL,
    Code            VARCHAR(20)   NOT NULL,      -- '1111', '131', '33311'
    Name            NVARCHAR(255) NOT NULL,
    ParentId        BIGINT        NULL,
    AccountType     VARCHAR(15)   NOT NULL,
    NormalBalance   VARCHAR(6)    NOT NULL,
    AccountLevel    TINYINT       NOT NULL DEFAULT 1,
    IsPostable      BIT           NOT NULL DEFAULT 1,   -- chỉ TK chi tiết nhất mới hạch toán
    RequiresPartner BIT           NOT NULL DEFAULT 0,   -- 131, 331, 141... bắt buộc chọn đối tượng
    CurrencyCode    CHAR(3)       NULL,
    IsActive        BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_Accounts PRIMARY KEY (Id),
    CONSTRAINT FK_Accounts_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Accounts_Parent FOREIGN KEY (ParentId) REFERENCES acc.Accounts(Id),
    CONSTRAINT FK_Accounts_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT UQ_Accounts UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Accounts_Type CHECK (AccountType IN ('asset','liability','equity','revenue','expense','cogs','other_income','other_expense','off_balance')),
    CONSTRAINT CK_Accounts_Balance CHECK (NormalBalance IN ('debit','credit','both'))
);

/* Tài khoản mặc định cho hạch toán tự động */
CREATE TABLE acc.DefaultAccounts (
    CompanyId   BIGINT       NOT NULL,
    MappingKey  VARCHAR(40)  NOT NULL,   -- 'receivable','payable','revenue_goods','cogs','inventory','vat_out','vat_in','cash','bank'...
    AccountId   BIGINT       NOT NULL,
    CONSTRAINT PK_DefaultAccounts PRIMARY KEY (CompanyId, MappingKey),
    CONSTRAINT FK_DefaultAccounts_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_DefaultAccounts_Accounts FOREIGN KEY (AccountId) REFERENCES acc.Accounts(Id)
);

/* Gắn tài khoản vào thuế và nhóm sản phẩm (đã khai báo ở md) */
ALTER TABLE md.Taxes ADD
    SaleAccountId     BIGINT NULL CONSTRAINT FK_Taxes_SaleAccount REFERENCES acc.Accounts(Id),
    PurchaseAccountId BIGINT NULL CONSTRAINT FK_Taxes_PurchaseAccount REFERENCES acc.Accounts(Id);
ALTER TABLE md.ProductCategories ADD
    RevenueAccountId   BIGINT NULL CONSTRAINT FK_ProductCategories_Revenue REFERENCES acc.Accounts(Id),
    CogsAccountId      BIGINT NULL CONSTRAINT FK_ProductCategories_Cogs REFERENCES acc.Accounts(Id),
    InventoryAccountId BIGINT NULL CONSTRAINT FK_ProductCategories_Inventory REFERENCES acc.Accounts(Id);

/* Sổ nhật ký (loại chứng từ) */
CREATE TABLE acc.Journals (
    Id                BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId         BIGINT        NOT NULL,
    Code              VARCHAR(10)   NOT NULL,    -- BH, MH, PT, PC, BC, BN, KHO, LUONG, TH
    Name              NVARCHAR(150) NOT NULL,
    JournalType       VARCHAR(10)   NOT NULL,
    DefaultAccountId  BIGINT        NULL,
    SequenceCode      VARCHAR(30)   NULL,        -- core.Sequences.Code
    IsActive          BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_Journals PRIMARY KEY (Id),
    CONSTRAINT FK_Journals_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Journals_Accounts FOREIGN KEY (DefaultAccountId) REFERENCES acc.Accounts(Id),
    CONSTRAINT UQ_Journals UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Journals_Type CHECK (JournalType IN ('sale','purchase','cash','bank','stock','payroll','general'))
);

/* ---------- Bút toán ---------- */
CREATE TABLE acc.JournalEntries (
    Id               BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId        BIGINT         NOT NULL,
    BranchId         BIGINT         NULL,
    JournalId        BIGINT         NOT NULL,
    DocNo            VARCHAR(30)    NOT NULL,
    DocDate          DATE           NOT NULL,     -- ngày chứng từ
    PostingDate      DATE           NOT NULL,     -- ngày hạch toán
    FiscalPeriodId   BIGINT         NOT NULL,
    Description      NVARCHAR(500)  NOT NULL,
    SourceType       VARCHAR(50)    NULL,         -- 'acc.Invoices','acc.Payments','inv.StockDocuments','hr.PayrollPeriods'
    SourceId         BIGINT         NULL,
    CurrencyCode     CHAR(3)        NOT NULL DEFAULT 'VND',
    ExchangeRate     DECIMAL(18,6)  NOT NULL DEFAULT 1,
    TotalDebit       DECIMAL(18,2)  NOT NULL DEFAULT 0,
    TotalCredit      DECIMAL(18,2)  NOT NULL DEFAULT 0,
    Status           VARCHAR(10)    NOT NULL DEFAULT 'draft',
    IsAutoGenerated  BIT            NOT NULL DEFAULT 0,
    ReversalOfId     BIGINT         NULL,         -- bút toán này đảo cho bút toán nào
    PostedAt         DATETIME2(3)   NULL,
    PostedBy         BIGINT         NULL,
    CreatedAt        DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    RowVersion       ROWVERSION NOT NULL,
    CONSTRAINT PK_JournalEntries PRIMARY KEY (Id),
    CONSTRAINT FK_JournalEntries_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_JournalEntries_Branches FOREIGN KEY (BranchId) REFERENCES core.Branches(Id),
    CONSTRAINT FK_JournalEntries_Journals FOREIGN KEY (JournalId) REFERENCES acc.Journals(Id),
    CONSTRAINT FK_JournalEntries_Periods FOREIGN KEY (FiscalPeriodId) REFERENCES acc.FiscalPeriods(Id),
    CONSTRAINT FK_JournalEntries_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT FK_JournalEntries_Reversal FOREIGN KEY (ReversalOfId) REFERENCES acc.JournalEntries(Id),
    CONSTRAINT UQ_JournalEntries UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_JournalEntries_Status CHECK (Status IN ('draft','posted','reversed','cancelled')),
    CONSTRAINT CK_JournalEntries_Balanced CHECK (Status <> 'posted' OR TotalDebit = TotalCredit)
);
CREATE INDEX IX_JournalEntries_Posting ON acc.JournalEntries(CompanyId, PostingDate) WHERE Status = 'posted';
CREATE INDEX IX_JournalEntries_Source ON acc.JournalEntries(SourceType, SourceId);

CREATE TABLE acc.JournalEntryLines (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    EntryId         BIGINT         NOT NULL,
    LineNumber      INT            NOT NULL,
    AccountId       BIGINT         NOT NULL,
    PartnerId       BIGINT         NULL,          -- đối tượng công nợ
    EmployeeId      BIGINT         NULL,          -- tạm ứng, lương
    ProductId       BIGINT         NULL,
    DepartmentId    BIGINT         NULL,          -- trung tâm chi phí
    Description     NVARCHAR(500)  NULL,
    Debit           DECIMAL(18,2)  NOT NULL DEFAULT 0,
    Credit          DECIMAL(18,2)  NOT NULL DEFAULT 0,
    AmountCurrency  DECIMAL(18,2)  NULL,          -- số tiền nguyên tệ
    DueDate         DATE           NULL,          -- hạn công nợ (cho báo cáo tuổi nợ)
    CONSTRAINT PK_JournalEntryLines PRIMARY KEY (Id),
    CONSTRAINT FK_JournalEntryLines_Entries FOREIGN KEY (EntryId) REFERENCES acc.JournalEntries(Id) ON DELETE CASCADE,
    CONSTRAINT FK_JournalEntryLines_Accounts FOREIGN KEY (AccountId) REFERENCES acc.Accounts(Id),
    CONSTRAINT FK_JournalEntryLines_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_JournalEntryLines_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_JournalEntryLines_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_JournalEntryLines_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT UQ_JournalEntryLines UNIQUE (EntryId, LineNumber),
    CONSTRAINT CK_JournalEntryLines_Amounts CHECK (Debit >= 0 AND Credit >= 0 AND (Debit = 0 OR Credit = 0) AND (Debit + Credit) > 0)
);
CREATE INDEX IX_JournalEntryLines_Account ON acc.JournalEntryLines(AccountId) INCLUDE (Debit, Credit, EntryId);
CREATE INDEX IX_JournalEntryLines_Partner ON acc.JournalEntryLines(PartnerId, AccountId) INCLUDE (Debit, Credit, DueDate) WHERE PartnerId IS NOT NULL;
GO

/* Chặn sửa/xóa dòng của bút toán đã ghi sổ - bảo vệ tính toàn vẹn sổ sách */
CREATE OR ALTER TRIGGER acc.trg_JournalEntryLines_Locked
ON acc.JournalEntryLines
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 FROM acc.JournalEntries e
        WHERE e.Status IN ('posted','reversed')
          AND e.Id IN (SELECT EntryId FROM inserted UNION SELECT EntryId FROM deleted)
    )
    BEGIN
        RAISERROR(N'Bút toán đã ghi sổ, không được sửa. Hãy tạo bút toán đảo.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END
GO

/* Chặn ghi sổ vào kỳ đã khóa */
CREATE OR ALTER TRIGGER acc.trg_JournalEntries_ClosedPeriod
ON acc.JournalEntries
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 FROM inserted i
        JOIN acc.FiscalPeriods p ON p.Id = i.FiscalPeriodId
        WHERE p.Status = 'closed'
    )
    BEGIN
        RAISERROR(N'Kỳ kế toán đã khóa, không được ghi hoặc sửa bút toán.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
    IF EXISTS (
        SELECT 1 FROM inserted i
        JOIN acc.FiscalPeriods p ON p.Id = i.FiscalPeriodId
        WHERE i.PostingDate NOT BETWEEN p.StartDate AND p.EndDate
    )
    BEGIN
        RAISERROR(N'Ngày hạch toán không thuộc kỳ kế toán đã chọn.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END
GO

/* ---------- Tài khoản ngân hàng của công ty ---------- */
CREATE TABLE acc.BankAccounts (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    AccountId    BIGINT        NOT NULL,       -- TK 1121 chi tiết
    BankName     NVARCHAR(150) NOT NULL,
    BankBranch   NVARCHAR(150) NULL,
    AccountNo    VARCHAR(30)   NOT NULL,
    AccountName  NVARCHAR(150) NOT NULL,
    CurrencyCode CHAR(3)       NOT NULL DEFAULT 'VND',
    IsActive     BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_BankAccounts PRIMARY KEY (Id),
    CONSTRAINT FK_BankAccounts_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_BankAccounts_Accounts FOREIGN KEY (AccountId) REFERENCES acc.Accounts(Id),
    CONSTRAINT FK_BankAccounts_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT UQ_BankAccounts UNIQUE (CompanyId, AccountNo)
);

/* ---------- Hóa đơn bán ra / mua vào ---------- */
CREATE TABLE acc.Invoices (
    Id                  BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId           BIGINT         NOT NULL,
    BranchId            BIGINT         NULL,
    DocNo               VARCHAR(30)    NOT NULL,     -- số nội bộ
    InvoiceType         VARCHAR(12)    NOT NULL,
    PartnerId           BIGINT         NOT NULL,
    BuyerName           NVARCHAR(255)  NULL,         -- thông tin in trên hóa đơn
    BuyerTaxCode        VARCHAR(20)    NULL,
    BuyerAddress        NVARCHAR(500)  NULL,
    BuyerEmail          VARCHAR(255)   NULL,
    SalesOrderId        BIGINT         NULL,
    PurchaseOrderId     BIGINT         NULL,
    OriginalInvoiceId   BIGINT         NULL,         -- hóa đơn gốc (điều chỉnh / thay thế / trả lại)
    InvoiceDate         DATE           NOT NULL,
    DueDate             DATE           NULL,
    CurrencyCode        CHAR(3)        NOT NULL DEFAULT 'VND',
    ExchangeRate        DECIMAL(18,6)  NOT NULL DEFAULT 1,
    PaymentTermId       BIGINT         NULL,
    PaymentMethodCode   VARCHAR(20)    NULL,
    SubTotal            DECIMAL(18,2)  NOT NULL DEFAULT 0,
    DiscountAmount      DECIMAL(18,2)  NOT NULL DEFAULT 0,
    TaxAmount           DECIMAL(18,2)  NOT NULL DEFAULT 0,
    TotalAmount         DECIMAL(18,2)  NOT NULL DEFAULT 0,
    AmountPaid          DECIMAL(18,2)  NOT NULL DEFAULT 0,
    AmountDue           AS (TotalAmount - AmountPaid) PERSISTED,
    AmountInWords       NVARCHAR(500)  NULL,
    Status              VARCHAR(10)    NOT NULL DEFAULT 'draft',
    PaymentStatus       VARCHAR(10)    NOT NULL DEFAULT 'unpaid',
    JournalEntryId      BIGINT         NULL,
    -- Hóa đơn mua vào: số hóa đơn của nhà cung cấp
    SupplierInvoiceSeries VARCHAR(20)  NULL,
    SupplierInvoiceNo   VARCHAR(20)    NULL,
    -- Hóa đơn điện tử (bán ra)
    EInvoiceProvider    VARCHAR(20)    NULL,         -- viettel | vnpt | misa | bkav | fpt
    EInvoiceTemplateCode VARCHAR(10)   NULL,         -- ký hiệu mẫu số: '1'
    EInvoiceSeries      VARCHAR(10)    NULL,         -- ký hiệu: 'C26TAA'
    EInvoiceNo          VARCHAR(20)    NULL,
    EInvoiceTaxAuthCode VARCHAR(50)    NULL,         -- mã của cơ quan thuế
    EInvoiceLookupCode  VARCHAR(50)    NULL,         -- mã tra cứu
    EInvoiceStatus      VARCHAR(12)    NOT NULL DEFAULT 'none',
    EInvoiceIssuedAt    DATETIME2(3)   NULL,
    EInvoiceXmlAttachmentId BIGINT     NULL,
    Note                NVARCHAR(1000) NULL,
    CreatedAt           DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted           BIT NOT NULL DEFAULT 0,
    RowVersion          ROWVERSION NOT NULL,
    CONSTRAINT PK_Invoices PRIMARY KEY (Id),
    CONSTRAINT FK_Invoices_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Invoices_Branches FOREIGN KEY (BranchId) REFERENCES core.Branches(Id),
    CONSTRAINT FK_Invoices_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_Invoices_SalesOrders FOREIGN KEY (SalesOrderId) REFERENCES sales.SalesOrders(Id),
    CONSTRAINT FK_Invoices_PurchaseOrders FOREIGN KEY (PurchaseOrderId) REFERENCES pur.PurchaseOrders(Id),
    CONSTRAINT FK_Invoices_Original FOREIGN KEY (OriginalInvoiceId) REFERENCES acc.Invoices(Id),
    CONSTRAINT FK_Invoices_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT FK_Invoices_PaymentTerms FOREIGN KEY (PaymentTermId) REFERENCES md.PaymentTerms(Id),
    CONSTRAINT FK_Invoices_PaymentMethods FOREIGN KEY (PaymentMethodCode) REFERENCES md.PaymentMethods(Code),
    CONSTRAINT FK_Invoices_JournalEntries FOREIGN KEY (JournalEntryId) REFERENCES acc.JournalEntries(Id),
    CONSTRAINT FK_Invoices_XmlAttachment FOREIGN KEY (EInvoiceXmlAttachmentId) REFERENCES core.Attachments(Id),
    CONSTRAINT UQ_Invoices_DocNo UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_Invoices_Type CHECK (InvoiceType IN ('out_invoice','out_refund','in_invoice','in_refund')),
    CONSTRAINT CK_Invoices_Status CHECK (Status IN ('draft','posted','cancelled')),
    CONSTRAINT CK_Invoices_Payment CHECK (PaymentStatus IN ('unpaid','partial','paid')),
    CONSTRAINT CK_Invoices_EInvoice CHECK (EInvoiceStatus IN ('none','pending','issued','sent_tax','accepted','rejected','adjusted','replaced','cancelled')),
    CONSTRAINT CK_Invoices_Amounts CHECK (TotalAmount >= 0 AND AmountPaid >= 0 AND AmountPaid <= TotalAmount)
);
CREATE INDEX IX_Invoices_Partner ON acc.Invoices(PartnerId, InvoiceDate DESC);
CREATE INDEX IX_Invoices_Unpaid ON acc.Invoices(CompanyId, InvoiceType, DueDate) WHERE PaymentStatus <> 'paid' AND Status = 'posted';
CREATE INDEX IX_Invoices_SalesOrder ON acc.Invoices(SalesOrderId) WHERE SalesOrderId IS NOT NULL;
CREATE UNIQUE INDEX UX_Invoices_EInvoice ON acc.Invoices(CompanyId, EInvoiceSeries, EInvoiceNo) WHERE EInvoiceNo IS NOT NULL;
CREATE UNIQUE INDEX UX_Invoices_SupplierNo ON acc.Invoices(CompanyId, PartnerId, SupplierInvoiceSeries, SupplierInvoiceNo) WHERE SupplierInvoiceNo IS NOT NULL;

CREATE TABLE acc.InvoiceLines (
    Id                   BIGINT IDENTITY(1,1) NOT NULL,
    InvoiceId            BIGINT         NOT NULL,
    LineNumber           INT            NOT NULL,
    ProductId            BIGINT         NULL,
    Description          NVARCHAR(1000) NOT NULL,
    AccountId            BIGINT         NULL,      -- TK doanh thu / chi phí
    UomId                BIGINT         NULL,
    Quantity             DECIMAL(18,4)  NOT NULL DEFAULT 1,
    UnitPrice            DECIMAL(18,4)  NOT NULL DEFAULT 0,
    DiscountPercent      DECIMAL(9,4)   NOT NULL DEFAULT 0,
    DiscountAmount       DECIMAL(18,2)  NOT NULL DEFAULT 0,
    TaxId                BIGINT         NULL,
    TaxRate              DECIMAL(9,4)   NOT NULL DEFAULT 0,
    LineSubTotal         DECIMAL(18,2)  NOT NULL DEFAULT 0,
    LineTax              DECIMAL(18,2)  NOT NULL DEFAULT 0,
    LineTotal            DECIMAL(18,2)  NOT NULL DEFAULT 0,
    SalesOrderLineId     BIGINT         NULL,
    PurchaseOrderLineId  BIGINT         NULL,
    CONSTRAINT PK_InvoiceLines PRIMARY KEY (Id),
    CONSTRAINT FK_InvoiceLines_Invoices FOREIGN KEY (InvoiceId) REFERENCES acc.Invoices(Id) ON DELETE CASCADE,
    CONSTRAINT FK_InvoiceLines_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_InvoiceLines_Accounts FOREIGN KEY (AccountId) REFERENCES acc.Accounts(Id),
    CONSTRAINT FK_InvoiceLines_Uom FOREIGN KEY (UomId) REFERENCES md.UnitsOfMeasure(Id),
    CONSTRAINT FK_InvoiceLines_Taxes FOREIGN KEY (TaxId) REFERENCES md.Taxes(Id),
    CONSTRAINT FK_InvoiceLines_SOLine FOREIGN KEY (SalesOrderLineId) REFERENCES sales.SalesOrderLines(Id),
    CONSTRAINT FK_InvoiceLines_POLine FOREIGN KEY (PurchaseOrderLineId) REFERENCES pur.PurchaseOrderLines(Id),
    CONSTRAINT UQ_InvoiceLines UNIQUE (InvoiceId, LineNumber),
    CONSTRAINT CK_InvoiceLines CHECK (Quantity >= 0 AND UnitPrice >= 0)
);

/* ---------- Thu chi: phiếu thu, phiếu chi, báo có, báo nợ ---------- */
CREATE TABLE acc.Payments (
    Id                BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId         BIGINT         NOT NULL,
    BranchId          BIGINT         NULL,
    DocNo             VARCHAR(30)    NOT NULL,
    PaymentType       VARCHAR(8)     NOT NULL,        -- receipt (thu) | payment (chi)
    PaymentMethodCode VARCHAR(20)    NOT NULL,
    PartnerId         BIGINT         NULL,
    EmployeeId        BIGINT         NULL,            -- tạm ứng / hoàn ứng
    PaymentDate       DATE           NOT NULL,
    Amount            DECIMAL(18,2)  NOT NULL,
    CurrencyCode      CHAR(3)        NOT NULL DEFAULT 'VND',
    ExchangeRate      DECIMAL(18,6)  NOT NULL DEFAULT 1,
    BankAccountId     BIGINT         NULL,            -- tiền gửi
    CashAccountId     BIGINT         NULL,            -- TK 1111 nếu tiền mặt
    CounterAccountId  BIGINT         NULL,            -- TK đối ứng nếu không phải công nợ (VD: 642)
    Reason            NVARCHAR(500)  NOT NULL,
    PersonName        NVARCHAR(150)  NULL,            -- người nộp / người nhận
    BankReference     VARCHAR(100)   NULL,            -- mã giao dịch ngân hàng
    Status            VARCHAR(10)    NOT NULL DEFAULT 'draft',
    JournalEntryId    BIGINT         NULL,
    AllocatedAmount   DECIMAL(18,2)  NOT NULL DEFAULT 0,
    Category          VARCHAR(30)    NULL,            -- customer | supplier | cod | refund | rent | salary | marketing ...
    SalesOrderId      BIGINT         NULL,            -- thu tiền / hoàn tiền cho đơn bán
    PurchaseOrderId   BIGINT         NULL,            -- trả tiền đơn nhập
    CreatedAt         DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted         BIT NOT NULL DEFAULT 0,
    RowVersion        ROWVERSION NOT NULL,
    CONSTRAINT PK_Payments PRIMARY KEY (Id),
    CONSTRAINT FK_Payments_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Payments_Branches FOREIGN KEY (BranchId) REFERENCES core.Branches(Id),
    CONSTRAINT FK_Payments_Methods FOREIGN KEY (PaymentMethodCode) REFERENCES md.PaymentMethods(Code),
    CONSTRAINT FK_Payments_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_Payments_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_Payments_Currencies FOREIGN KEY (CurrencyCode) REFERENCES md.Currencies(Code),
    CONSTRAINT FK_Payments_BankAccounts FOREIGN KEY (BankAccountId) REFERENCES acc.BankAccounts(Id),
    CONSTRAINT FK_Payments_CashAccount FOREIGN KEY (CashAccountId) REFERENCES acc.Accounts(Id),
    CONSTRAINT FK_Payments_CounterAccount FOREIGN KEY (CounterAccountId) REFERENCES acc.Accounts(Id),
    CONSTRAINT FK_Payments_JournalEntries FOREIGN KEY (JournalEntryId) REFERENCES acc.JournalEntries(Id),
    CONSTRAINT FK_Payments_SalesOrders FOREIGN KEY (SalesOrderId) REFERENCES sales.SalesOrders(Id),
    CONSTRAINT FK_Payments_PurchaseOrders FOREIGN KEY (PurchaseOrderId) REFERENCES pur.PurchaseOrders(Id),
    CONSTRAINT UQ_Payments UNIQUE (CompanyId, DocNo),
    CONSTRAINT CK_Payments_Type CHECK (PaymentType IN ('receipt','payment')),
    CONSTRAINT CK_Payments_Status CHECK (Status IN ('draft','posted','cancelled')),
    CONSTRAINT CK_Payments_Amount CHECK (Amount > 0 AND AllocatedAmount >= 0 AND AllocatedAmount <= Amount),
    CONSTRAINT CK_Payments_Source CHECK (BankAccountId IS NOT NULL OR CashAccountId IS NOT NULL)
);
CREATE INDEX IX_Payments_Partner ON acc.Payments(PartnerId, PaymentDate DESC);
CREATE INDEX IX_Payments_Date ON acc.Payments(CompanyId, PaymentDate DESC);

/* Đối trừ: 1 phiếu thu trả cho nhiều hóa đơn, 1 hóa đơn trả bằng nhiều phiếu */
CREATE TABLE acc.PaymentAllocations (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    PaymentId  BIGINT        NOT NULL,
    InvoiceId  BIGINT        NOT NULL,
    Amount     DECIMAL(18,2) NOT NULL,
    AllocatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    AllocatedBy BIGINT       NULL,
    CONSTRAINT PK_PaymentAllocations PRIMARY KEY (Id),
    CONSTRAINT FK_PaymentAllocations_Payments FOREIGN KEY (PaymentId) REFERENCES acc.Payments(Id),
    CONSTRAINT FK_PaymentAllocations_Invoices FOREIGN KEY (InvoiceId) REFERENCES acc.Invoices(Id),
    CONSTRAINT UQ_PaymentAllocations UNIQUE (PaymentId, InvoiceId),
    CONSTRAINT CK_PaymentAllocations CHECK (Amount > 0)
);
CREATE INDEX IX_PaymentAllocations_Invoice ON acc.PaymentAllocations(InvoiceId);

/* ---------- Sao kê ngân hàng & đối chiếu ---------- */
CREATE TABLE acc.BankStatements (
    Id             BIGINT IDENTITY(1,1) NOT NULL,
    BankAccountId  BIGINT        NOT NULL,
    StatementDate  DATE          NOT NULL,
    OpeningBalance DECIMAL(18,2) NOT NULL,
    ClosingBalance DECIMAL(18,2) NOT NULL,
    Source         VARCHAR(10)   NOT NULL DEFAULT 'import',   -- import | api
    Status         VARCHAR(12)   NOT NULL DEFAULT 'open',
    CreatedAt      DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy      BIGINT        NULL,
    CONSTRAINT PK_BankStatements PRIMARY KEY (Id),
    CONSTRAINT FK_BankStatements_BankAccounts FOREIGN KEY (BankAccountId) REFERENCES acc.BankAccounts(Id),
    CONSTRAINT CK_BankStatements_Status CHECK (Status IN ('open','reconciled'))
);
CREATE TABLE acc.BankStatementLines (
    Id               BIGINT IDENTITY(1,1) NOT NULL,
    StatementId      BIGINT        NOT NULL,
    TransactionDate  DATE          NOT NULL,
    Description      NVARCHAR(500) NULL,
    Reference        VARCHAR(100)  NULL,
    Amount           DECIMAL(18,2) NOT NULL,       -- dương = tiền vào, âm = tiền ra
    CounterpartyName NVARCHAR(255) NULL,
    CounterpartyAccount VARCHAR(30) NULL,
    MatchedPaymentId BIGINT        NULL,
    MatchedAt        DATETIME2(3)  NULL,
    CONSTRAINT PK_BankStatementLines PRIMARY KEY (Id),
    CONSTRAINT FK_BankStatementLines_Statements FOREIGN KEY (StatementId) REFERENCES acc.BankStatements(Id) ON DELETE CASCADE,
    CONSTRAINT FK_BankStatementLines_Payments FOREIGN KEY (MatchedPaymentId) REFERENCES acc.Payments(Id)
);
CREATE INDEX IX_BankStatementLines_Unmatched ON acc.BankStatementLines(StatementId) WHERE MatchedPaymentId IS NULL;

/* ---------- Tài sản cố định & chi phí trả trước (khấu hao) ---------- */
CREATE TABLE acc.FixedAssets (
    Id                   BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId            BIGINT        NOT NULL,
    Code                 VARCHAR(30)   NOT NULL,
    Name                 NVARCHAR(255) NOT NULL,
    AssetType            VARCHAR(10)   NOT NULL DEFAULT 'fixed',     -- fixed (211) | prepaid (242)
    DepartmentId         BIGINT        NULL,
    PurchaseDate         DATE          NOT NULL,
    StartDepreciationDate DATE         NOT NULL,
    OriginalCost         DECIMAL(18,2) NOT NULL,
    UsefulLifeMonths     INT           NOT NULL,
    AccumulatedDepreciation DECIMAL(18,2) NOT NULL DEFAULT 0,
    AssetAccountId       BIGINT        NOT NULL,
    DepreciationAccountId BIGINT       NULL,         -- 214
    ExpenseAccountId     BIGINT        NOT NULL,     -- 6274, 6414, 6424
    Status               VARCHAR(10)   NOT NULL DEFAULT 'active',
    InvoiceId            BIGINT        NULL,
    CreatedAt            DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_FixedAssets PRIMARY KEY (Id),
    CONSTRAINT FK_FixedAssets_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_FixedAssets_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT FK_FixedAssets_AssetAccount FOREIGN KEY (AssetAccountId) REFERENCES acc.Accounts(Id),
    CONSTRAINT FK_FixedAssets_DeprAccount FOREIGN KEY (DepreciationAccountId) REFERENCES acc.Accounts(Id),
    CONSTRAINT FK_FixedAssets_ExpenseAccount FOREIGN KEY (ExpenseAccountId) REFERENCES acc.Accounts(Id),
    CONSTRAINT FK_FixedAssets_Invoices FOREIGN KEY (InvoiceId) REFERENCES acc.Invoices(Id),
    CONSTRAINT UQ_FixedAssets UNIQUE (CompanyId, Code),
    CONSTRAINT CK_FixedAssets_Type CHECK (AssetType IN ('fixed','prepaid')),
    CONSTRAINT CK_FixedAssets_Status CHECK (Status IN ('active','fully_depreciated','disposed')),
    CONSTRAINT CK_FixedAssets_Values CHECK (OriginalCost > 0 AND UsefulLifeMonths > 0 AND AccumulatedDepreciation BETWEEN 0 AND OriginalCost)
);
CREATE TABLE acc.DepreciationLines (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    FixedAssetId    BIGINT        NOT NULL,
    FiscalPeriodId  BIGINT        NOT NULL,
    Amount          DECIMAL(18,2) NOT NULL,
    JournalEntryId  BIGINT        NULL,
    CONSTRAINT PK_DepreciationLines PRIMARY KEY (Id),
    CONSTRAINT FK_DepreciationLines_Assets FOREIGN KEY (FixedAssetId) REFERENCES acc.FixedAssets(Id),
    CONSTRAINT FK_DepreciationLines_Periods FOREIGN KEY (FiscalPeriodId) REFERENCES acc.FiscalPeriods(Id),
    CONSTRAINT FK_DepreciationLines_Entries FOREIGN KEY (JournalEntryId) REFERENCES acc.JournalEntries(Id),
    CONSTRAINT UQ_DepreciationLines UNIQUE (FixedAssetId, FiscalPeriodId)
);

/* ---------- Nối FK từ các module khác vào kế toán ---------- */
ALTER TABLE hr.PayrollPeriods ADD CONSTRAINT FK_PayrollPeriods_JournalEntries FOREIGN KEY (JournalEntryId) REFERENCES acc.JournalEntries(Id);
ALTER TABLE inv.StockDocuments ADD CONSTRAINT FK_StockDocuments_JournalEntries FOREIGN KEY (JournalEntryId) REFERENCES acc.JournalEntries(Id);
ALTER TABLE lgs.CodReconciliations ADD CONSTRAINT FK_CodReconciliations_Payments FOREIGN KEY (PaymentId) REFERENCES acc.Payments(Id);
GO
GO

-- ===================== 11_support.sql =====================
/* =====================================================================
   MyERP - 11. CHĂM SÓC KHÁCH HÀNG (cs): ticket, SLA, bảo hành.
   ===================================================================== */
CREATE SCHEMA cs;
GO

CREATE TABLE cs.TicketCategories (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId BIGINT        NOT NULL,
    Name      NVARCHAR(100) NOT NULL,      -- 'Khiếu nại', 'Hỗ trợ kỹ thuật', 'Bảo hành', 'Đổi trả'
    DefaultAssigneeUserId BIGINT NULL,
    IsActive  BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_TicketCategories PRIMARY KEY (Id),
    CONSTRAINT FK_TicketCategories_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_TicketCategories_Assignee FOREIGN KEY (DefaultAssigneeUserId) REFERENCES core.Users(Id)
);

CREATE TABLE cs.SlaPolicies (
    Id                    BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId             BIGINT        NOT NULL,
    Name                  NVARCHAR(100) NOT NULL,
    Priority              VARCHAR(8)    NOT NULL,
    FirstResponseMinutes  INT           NOT NULL,
    ResolutionMinutes     INT           NOT NULL,
    BusinessHoursOnly     BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_SlaPolicies PRIMARY KEY (Id),
    CONSTRAINT FK_SlaPolicies_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT CK_SlaPolicies_Priority CHECK (Priority IN ('low','normal','high','urgent')),
    CONSTRAINT CK_SlaPolicies_Minutes CHECK (FirstResponseMinutes > 0 AND ResolutionMinutes >= FirstResponseMinutes)
);

CREATE TABLE cs.Tickets (
    Id                 BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId          BIGINT         NOT NULL,
    Code               VARCHAR(30)    NOT NULL,
    Subject            NVARCHAR(255)  NOT NULL,
    Description        NVARCHAR(MAX)  NULL,
    PartnerId          BIGINT         NULL,
    ContactId          BIGINT         NULL,
    ReporterName       NVARCHAR(150)  NULL,
    ReporterPhone      VARCHAR(20)    NULL,
    ReporterEmail      VARCHAR(255)   NULL,
    SalesOrderId       BIGINT         NULL,
    ProductId          BIGINT         NULL,
    CategoryId         BIGINT         NULL,
    Channel            VARCHAR(10)    NOT NULL DEFAULT 'phone',
    Priority           VARCHAR(8)     NOT NULL DEFAULT 'normal',
    Status             VARCHAR(10)    NOT NULL DEFAULT 'new',
    AssignedUserId     BIGINT         NULL,
    DepartmentId       BIGINT         NULL,
    SlaPolicyId        BIGINT         NULL,
    FirstResponseDueAt DATETIME2(0)   NULL,
    ResolutionDueAt    DATETIME2(0)   NULL,
    FirstRespondedAt   DATETIME2(3)   NULL,
    ResolvedAt         DATETIME2(3)   NULL,
    ClosedAt           DATETIME2(3)   NULL,
    Resolution         NVARCHAR(MAX)  NULL,
    SatisfactionScore  TINYINT        NULL,
    SatisfactionNote   NVARCHAR(1000) NULL,
    CreatedAt          DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted          BIT NOT NULL DEFAULT 0,
    RowVersion         ROWVERSION NOT NULL,
    CONSTRAINT PK_Tickets PRIMARY KEY (Id),
    CONSTRAINT FK_Tickets_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Tickets_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_Tickets_Contacts FOREIGN KEY (ContactId) REFERENCES md.PartnerContacts(Id),
    CONSTRAINT FK_Tickets_SalesOrders FOREIGN KEY (SalesOrderId) REFERENCES sales.SalesOrders(Id),
    CONSTRAINT FK_Tickets_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_Tickets_Categories FOREIGN KEY (CategoryId) REFERENCES cs.TicketCategories(Id),
    CONSTRAINT FK_Tickets_Assigned FOREIGN KEY (AssignedUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Tickets_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT FK_Tickets_Sla FOREIGN KEY (SlaPolicyId) REFERENCES cs.SlaPolicies(Id),
    CONSTRAINT UQ_Tickets UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Tickets_Channel CHECK (Channel IN ('phone','email','zalo','facebook','web','walk_in','other')),
    CONSTRAINT CK_Tickets_Priority CHECK (Priority IN ('low','normal','high','urgent')),
    CONSTRAINT CK_Tickets_Status CHECK (Status IN ('new','open','pending','resolved','closed','cancelled')),
    CONSTRAINT CK_Tickets_Score CHECK (SatisfactionScore IS NULL OR SatisfactionScore BETWEEN 1 AND 5)
);
CREATE INDEX IX_Tickets_Assigned ON cs.Tickets(AssignedUserId, Status) WHERE IsDeleted = 0;
CREATE INDEX IX_Tickets_Partner ON cs.Tickets(PartnerId, CreatedAt DESC);
CREATE INDEX IX_Tickets_SlaDue ON cs.Tickets(ResolutionDueAt) WHERE Status IN ('new','open','pending');

CREATE TABLE cs.TicketMessages (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    TicketId      BIGINT        NOT NULL,
    AuthorUserId  BIGINT        NULL,          -- nhân viên
    AuthorName    NVARCHAR(150) NULL,          -- khách (nếu từ email/web)
    Body          NVARCHAR(MAX) NOT NULL,
    IsInternal    BIT           NOT NULL DEFAULT 0,   -- ghi chú nội bộ, khách không thấy
    CreatedAt     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_TicketMessages PRIMARY KEY (Id),
    CONSTRAINT FK_TicketMessages_Tickets FOREIGN KEY (TicketId) REFERENCES cs.Tickets(Id) ON DELETE CASCADE,
    CONSTRAINT FK_TicketMessages_Users FOREIGN KEY (AuthorUserId) REFERENCES core.Users(Id)
);
CREATE INDEX IX_TicketMessages_Ticket ON cs.TicketMessages(TicketId, CreatedAt);

CREATE TABLE cs.Warranties (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId     BIGINT        NOT NULL,
    Code          VARCHAR(30)   NOT NULL,
    PartnerId     BIGINT        NOT NULL,
    ProductId     BIGINT        NOT NULL,
    LotId         BIGINT        NULL,          -- số serial
    SalesOrderId  BIGINT        NULL,
    StartDate     DATE          NOT NULL,
    EndDate       DATE          NOT NULL,
    Status        VARCHAR(10)   NOT NULL DEFAULT 'active',
    CreatedAt     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_Warranties PRIMARY KEY (Id),
    CONSTRAINT FK_Warranties_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Warranties_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_Warranties_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT FK_Warranties_Lots FOREIGN KEY (LotId) REFERENCES inv.Lots(Id),
    CONSTRAINT FK_Warranties_SalesOrders FOREIGN KEY (SalesOrderId) REFERENCES sales.SalesOrders(Id),
    CONSTRAINT UQ_Warranties UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Warranties_Status CHECK (Status IN ('active','expired','void')),
    CONSTRAINT CK_Warranties_Dates CHECK (EndDate >= StartDate)
);
CREATE INDEX IX_Warranties_Lot ON cs.Warranties(LotId) WHERE LotId IS NOT NULL;

CREATE TABLE cs.WarrantyClaims (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    WarrantyId   BIGINT         NOT NULL,
    TicketId     BIGINT         NULL,
    ClaimDate    DATE           NOT NULL,
    Issue        NVARCHAR(1000) NOT NULL,
    Resolution   NVARCHAR(1000) NULL,
    ResolutionType VARCHAR(10)  NULL,          -- repair | replace | refund | reject
    Cost         DECIMAL(18,2)  NOT NULL DEFAULT 0,
    Status       VARCHAR(12)    NOT NULL DEFAULT 'received',
    CompletedAt  DATETIME2(3)   NULL,
    CONSTRAINT PK_WarrantyClaims PRIMARY KEY (Id),
    CONSTRAINT FK_WarrantyClaims_Warranties FOREIGN KEY (WarrantyId) REFERENCES cs.Warranties(Id),
    CONSTRAINT FK_WarrantyClaims_Tickets FOREIGN KEY (TicketId) REFERENCES cs.Tickets(Id),
    CONSTRAINT CK_WarrantyClaims_Type CHECK (ResolutionType IS NULL OR ResolutionType IN ('repair','replace','refund','reject')),
    CONSTRAINT CK_WarrantyClaims_Status CHECK (Status IN ('received','processing','completed','returned'))
);
GO
GO

-- ===================== 12_project.sql =====================
/* =====================================================================
   MyERP - 12. DỰ ÁN & CÔNG VIỆC (prj): dự án, giao việc liên phòng ban,
   Kanban, chấm giờ (timesheet).
   ===================================================================== */
CREATE SCHEMA prj;
GO

CREATE TABLE prj.Projects (
    Id             BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId      BIGINT        NOT NULL,
    Code           VARCHAR(30)   NOT NULL,
    Name           NVARCHAR(255) NOT NULL,
    PartnerId      BIGINT        NULL,
    SalesOrderId   BIGINT        NULL,
    ManagerUserId  BIGINT        NULL,
    DepartmentId   BIGINT        NULL,
    StartDate      DATE          NULL,
    EndDate        DATE          NULL,
    Budget         DECIMAL(18,2) NOT NULL DEFAULT 0,
    Status         VARCHAR(10)   NOT NULL DEFAULT 'planning',
    ProgressPercent DECIMAL(5,2) NOT NULL DEFAULT 0,
    Description    NVARCHAR(MAX) NULL,
    CreatedAt      DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted      BIT NOT NULL DEFAULT 0,
    RowVersion     ROWVERSION NOT NULL,
    CONSTRAINT PK_Projects PRIMARY KEY (Id),
    CONSTRAINT FK_Projects_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Projects_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_Projects_SalesOrders FOREIGN KEY (SalesOrderId) REFERENCES sales.SalesOrders(Id),
    CONSTRAINT FK_Projects_Manager FOREIGN KEY (ManagerUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Projects_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT UQ_Projects UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Projects_Status CHECK (Status IN ('planning','active','on_hold','completed','cancelled')),
    CONSTRAINT CK_Projects_Progress CHECK (ProgressPercent BETWEEN 0 AND 100)
);

CREATE TABLE prj.ProjectMembers (
    ProjectId  BIGINT       NOT NULL,
    UserId     BIGINT       NOT NULL,
    MemberRole VARCHAR(10)  NOT NULL DEFAULT 'member',
    JoinedAt   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ProjectMembers PRIMARY KEY (ProjectId, UserId),
    CONSTRAINT FK_ProjectMembers_Projects FOREIGN KEY (ProjectId) REFERENCES prj.Projects(Id) ON DELETE CASCADE,
    CONSTRAINT FK_ProjectMembers_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id),
    CONSTRAINT CK_ProjectMembers_Role CHECK (MemberRole IN ('manager','member','viewer'))
);

/* Cột Kanban: ProjectId NULL = cột mặc định cho việc không thuộc dự án */
CREATE TABLE prj.TaskStages (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId  BIGINT        NOT NULL,
    ProjectId  BIGINT        NULL,
    Name       NVARCHAR(100) NOT NULL,
    SortOrder  INT           NOT NULL DEFAULT 0,
    IsDone     BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_TaskStages PRIMARY KEY (Id),
    CONSTRAINT FK_TaskStages_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_TaskStages_Projects FOREIGN KEY (ProjectId) REFERENCES prj.Projects(Id)
);

CREATE TABLE prj.Tasks (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT         NOT NULL,
    Code            VARCHAR(30)    NOT NULL,
    ProjectId       BIGINT         NULL,
    ParentTaskId    BIGINT         NULL,
    Title           NVARCHAR(255)  NOT NULL,
    Description     NVARCHAR(MAX)  NULL,
    StageId         BIGINT         NULL,
    Priority        VARCHAR(8)     NOT NULL DEFAULT 'normal',
    AssigneeUserId  BIGINT         NULL,
    ReporterUserId  BIGINT         NULL,
    DepartmentId    BIGINT         NULL,      -- giao cho phòng ban (VD: Kế toán xuất hóa đơn)
    EntityName      VARCHAR(100)   NULL,      -- việc phát sinh từ chứng từ nào
    EntityId        BIGINT         NULL,
    StartDate       DATE           NULL,
    DueDate         DATETIME2(0)   NULL,
    CompletedAt     DATETIME2(3)   NULL,
    EstimatedHours  DECIMAL(8,2)   NULL,
    ProgressPercent DECIMAL(5,2)   NOT NULL DEFAULT 0,
    SortOrder       INT            NOT NULL DEFAULT 0,
    CreatedAt       DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted       BIT NOT NULL DEFAULT 0,
    RowVersion      ROWVERSION NOT NULL,
    CONSTRAINT PK_Tasks PRIMARY KEY (Id),
    CONSTRAINT FK_Tasks_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Tasks_Projects FOREIGN KEY (ProjectId) REFERENCES prj.Projects(Id),
    CONSTRAINT FK_Tasks_Parent FOREIGN KEY (ParentTaskId) REFERENCES prj.Tasks(Id),
    CONSTRAINT FK_Tasks_Stages FOREIGN KEY (StageId) REFERENCES prj.TaskStages(Id),
    CONSTRAINT FK_Tasks_Assignee FOREIGN KEY (AssigneeUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Tasks_Reporter FOREIGN KEY (ReporterUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Tasks_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT UQ_Tasks UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Tasks_Priority CHECK (Priority IN ('low','normal','high','urgent')),
    CONSTRAINT CK_Tasks_Progress CHECK (ProgressPercent BETWEEN 0 AND 100)
);
CREATE INDEX IX_Tasks_Assignee ON prj.Tasks(AssigneeUserId, DueDate) WHERE CompletedAt IS NULL AND IsDeleted = 0;
CREATE INDEX IX_Tasks_Project ON prj.Tasks(ProjectId, StageId) WHERE IsDeleted = 0;
CREATE INDEX IX_Tasks_Entity ON prj.Tasks(EntityName, EntityId) WHERE EntityName IS NOT NULL;

CREATE TABLE prj.TaskWatchers (
    TaskId BIGINT NOT NULL,
    UserId BIGINT NOT NULL,
    CONSTRAINT PK_TaskWatchers PRIMARY KEY (TaskId, UserId),
    CONSTRAINT FK_TaskWatchers_Tasks FOREIGN KEY (TaskId) REFERENCES prj.Tasks(Id) ON DELETE CASCADE,
    CONSTRAINT FK_TaskWatchers_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id)
);

CREATE TABLE prj.TaskChecklistItems (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    TaskId    BIGINT        NOT NULL,
    Title     NVARCHAR(255) NOT NULL,
    IsDone    BIT           NOT NULL DEFAULT 0,
    SortOrder INT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_TaskChecklistItems PRIMARY KEY (Id),
    CONSTRAINT FK_TaskChecklistItems_Tasks FOREIGN KEY (TaskId) REFERENCES prj.Tasks(Id) ON DELETE CASCADE
);

CREATE TABLE prj.Timesheets (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    TaskId    BIGINT        NULL,
    ProjectId BIGINT        NULL,
    UserId    BIGINT        NOT NULL,
    WorkDate  DATE          NOT NULL,
    Hours     DECIMAL(5,2)  NOT NULL,
    Note      NVARCHAR(500) NULL,
    IsBillable BIT          NOT NULL DEFAULT 0,
    CreatedAt DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Timesheets PRIMARY KEY (Id),
    CONSTRAINT FK_Timesheets_Tasks FOREIGN KEY (TaskId) REFERENCES prj.Tasks(Id),
    CONSTRAINT FK_Timesheets_Projects FOREIGN KEY (ProjectId) REFERENCES prj.Projects(Id),
    CONSTRAINT FK_Timesheets_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id),
    CONSTRAINT CK_Timesheets_Hours CHECK (Hours > 0 AND Hours <= 24)
);
CREATE INDEX IX_Timesheets_User_Date ON prj.Timesheets(UserId, WorkDate);
GO
GO

-- ===================== 13_website.sql =====================
/* =====================================================================
   MyERP - 13. WEBSITE (web): trang, bài viết, menu, tài khoản khách,
   giỏ hàng, form liên hệ. Sản phẩm dùng chung md.Products (IsPublishedWeb),
   đơn online đổ thẳng vào sales.SalesOrders (Channel = 'website').
   ===================================================================== */
CREATE SCHEMA web;
GO

CREATE TABLE web.Sites (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT        NOT NULL,
    Name            NVARCHAR(150) NOT NULL,
    Domain          VARCHAR(255)  NOT NULL,
    DefaultLanguage VARCHAR(10)   NOT NULL DEFAULT 'vi',
    LogoUrl         VARCHAR(500)  NULL,
    FaviconUrl      VARCHAR(500)  NULL,
    PriceListId     BIGINT        NULL,
    WarehouseId     BIGINT        NULL,          -- kho trừ tồn cho đơn online
    Settings        NVARCHAR(MAX) NULL,          -- JSON: màu, script GA, pixel...
    IsActive        BIT           NOT NULL DEFAULT 1,
    -- Website tự code (Next.js...) gọi API bằng khóa riêng; ERP lưu SHA-256 của khóa, khóa gốc chỉ hiện 1 lần
    ApiKeyHash       CHAR(64)      NULL,
    ApiKeyPrefix     VARCHAR(16)   NULL,
    ApiKeyCreatedAt  DATETIME2(3)  NULL,
    RevalidateUrl    VARCHAR(500)  NULL,     -- webhook báo website làm mới trang khi dữ liệu đổi
    RevalidateSecret VARCHAR(100)  NULL,
    LastSyncAt       DATETIME2(3)  NULL,
    LastSyncStatus   NVARCHAR(300) NULL,
    BotUserId        BIGINT        NULL,     -- tài khoản (không đăng nhập được) ghi người tạo cho đơn online
    CONSTRAINT PK_Sites PRIMARY KEY (Id),
    CONSTRAINT FK_Sites_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Sites_PriceLists FOREIGN KEY (PriceListId) REFERENCES md.PriceLists(Id),
    CONSTRAINT FK_Sites_Warehouses FOREIGN KEY (WarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT UQ_Sites_Domain UNIQUE (Domain),
    CONSTRAINT FK_Sites_BotUser FOREIGN KEY (BotUserId) REFERENCES core.Users(Id)
);
CREATE UNIQUE INDEX UX_Sites_ApiKeyHash ON web.Sites(ApiKeyHash) WHERE ApiKeyHash IS NOT NULL;

/* Mẫu sản phẩm bày bán trên từng website (mỗi web chọn mẫu riêng, giá riêng nếu cần) */
CREATE TABLE web.SiteProducts (
    SiteId        BIGINT        NOT NULL,
    ModelId       BIGINT        NOT NULL,
    PriceOverride DECIMAL(18,2) NULL,        -- NULL = giá bán của từng biến thể
    IsFeatured    BIT           NOT NULL DEFAULT 0,
    SortOrder     INT           NOT NULL DEFAULT 0,
    AddedAt       DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_SiteProducts PRIMARY KEY (SiteId, ModelId),
    CONSTRAINT FK_SiteProducts_Sites FOREIGN KEY (SiteId) REFERENCES web.Sites(Id) ON DELETE CASCADE,
    CONSTRAINT FK_SiteProducts_Models FOREIGN KEY (ModelId) REFERENCES md.ProductModels(Id),
    CONSTRAINT CK_SiteProducts_Price CHECK (PriceOverride IS NULL OR PriceOverride >= 0)
);

CREATE TABLE web.Pages (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    SiteId          BIGINT        NOT NULL,
    Slug            VARCHAR(255)  NOT NULL,
    Title           NVARCHAR(255) NOT NULL,
    Content         NVARCHAR(MAX) NULL,
    MetaTitle       NVARCHAR(255) NULL,
    MetaDescription NVARCHAR(500) NULL,
    IsPublished     BIT           NOT NULL DEFAULT 0,
    PublishedAt     DATETIME2(3)  NULL,
    CreatedAt       DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted       BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_Pages PRIMARY KEY (Id),
    CONSTRAINT FK_Pages_Sites FOREIGN KEY (SiteId) REFERENCES web.Sites(Id),
    CONSTRAINT UQ_Pages_Slug UNIQUE (SiteId, Slug)
);

CREATE TABLE web.PostCategories (
    Id       BIGINT IDENTITY(1,1) NOT NULL,
    SiteId   BIGINT        NOT NULL,
    ParentId BIGINT        NULL,
    Slug     VARCHAR(255)  NOT NULL,
    Name     NVARCHAR(150) NOT NULL,
    CONSTRAINT PK_PostCategories PRIMARY KEY (Id),
    CONSTRAINT FK_PostCategories_Sites FOREIGN KEY (SiteId) REFERENCES web.Sites(Id),
    CONSTRAINT FK_PostCategories_Parent FOREIGN KEY (ParentId) REFERENCES web.PostCategories(Id),
    CONSTRAINT UQ_PostCategories_Slug UNIQUE (SiteId, Slug)
);

CREATE TABLE web.Posts (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    SiteId          BIGINT        NOT NULL,
    CategoryId      BIGINT        NULL,
    Slug            VARCHAR(255)  NOT NULL,
    Title           NVARCHAR(255) NOT NULL,
    Summary         NVARCHAR(1000) NULL,
    Content         NVARCHAR(MAX) NULL,
    ThumbnailUrl    VARCHAR(500)  NULL,
    AuthorUserId    BIGINT        NULL,
    MetaTitle       NVARCHAR(255) NULL,
    MetaDescription NVARCHAR(500) NULL,
    IsPublished     BIT           NOT NULL DEFAULT 0,
    PublishedAt     DATETIME2(3)  NULL,
    ViewCount       BIGINT        NOT NULL DEFAULT 0,
    CreatedAt       DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted       BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_Posts PRIMARY KEY (Id),
    CONSTRAINT FK_Posts_Sites FOREIGN KEY (SiteId) REFERENCES web.Sites(Id),
    CONSTRAINT FK_Posts_Categories FOREIGN KEY (CategoryId) REFERENCES web.PostCategories(Id),
    CONSTRAINT FK_Posts_Author FOREIGN KEY (AuthorUserId) REFERENCES core.Users(Id),
    CONSTRAINT UQ_Posts_Slug UNIQUE (SiteId, Slug)
);
CREATE INDEX IX_Posts_Published ON web.Posts(SiteId, PublishedAt DESC) WHERE IsPublished = 1 AND IsDeleted = 0;

CREATE TABLE web.Menus (
    Id       BIGINT IDENTITY(1,1) NOT NULL,
    SiteId   BIGINT       NOT NULL,
    Code     VARCHAR(30)  NOT NULL,          -- 'header','footer'
    CONSTRAINT PK_Menus PRIMARY KEY (Id),
    CONSTRAINT FK_Menus_Sites FOREIGN KEY (SiteId) REFERENCES web.Sites(Id),
    CONSTRAINT UQ_Menus UNIQUE (SiteId, Code)
);
CREATE TABLE web.MenuItems (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    MenuId    BIGINT        NOT NULL,
    ParentId  BIGINT        NULL,
    Label     NVARCHAR(100) NOT NULL,
    Url       VARCHAR(500)  NOT NULL,
    SortOrder INT           NOT NULL DEFAULT 0,
    OpenNewTab BIT          NOT NULL DEFAULT 0,
    CONSTRAINT PK_MenuItems PRIMARY KEY (Id),
    CONSTRAINT FK_MenuItems_Menus FOREIGN KEY (MenuId) REFERENCES web.Menus(Id) ON DELETE CASCADE,
    CONSTRAINT FK_MenuItems_Parent FOREIGN KEY (ParentId) REFERENCES web.MenuItems(Id)
);

/* Tài khoản khách mua online - tách khỏi core.Users (nhân viên) */
CREATE TABLE web.CustomerAccounts (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    SiteId        BIGINT        NOT NULL,
    PartnerId     BIGINT        NULL,
    Email         VARCHAR(255)  NULL,
    Phone         VARCHAR(20)   NULL,
    PasswordHash  NVARCHAR(500) NULL,
    FullName      NVARCHAR(150) NOT NULL,
    EmailConfirmed BIT          NOT NULL DEFAULT 0,
    IsActive      BIT           NOT NULL DEFAULT 1,
    LastLoginAt   DATETIME2(3)  NULL,
    CreatedAt     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_CustomerAccounts PRIMARY KEY (Id),
    CONSTRAINT FK_CustomerAccounts_Sites FOREIGN KEY (SiteId) REFERENCES web.Sites(Id),
    CONSTRAINT FK_CustomerAccounts_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT CK_CustomerAccounts_Login CHECK (Email IS NOT NULL OR Phone IS NOT NULL)
);
CREATE UNIQUE INDEX UX_CustomerAccounts_Email ON web.CustomerAccounts(SiteId, Email) WHERE Email IS NOT NULL;
CREATE UNIQUE INDEX UX_CustomerAccounts_Phone ON web.CustomerAccounts(SiteId, Phone) WHERE Phone IS NOT NULL;

CREATE TABLE web.Carts (
    Id                BIGINT IDENTITY(1,1) NOT NULL,
    SiteId            BIGINT        NOT NULL,
    CustomerAccountId BIGINT        NULL,
    SessionKey        VARCHAR(100)  NOT NULL,      -- khách vãng lai
    PromotionCode     VARCHAR(30)   NULL,
    SalesOrderId      BIGINT        NULL,          -- sau khi đặt hàng
    Status            VARCHAR(10)   NOT NULL DEFAULT 'active',
    CreatedAt         DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt         DATETIME2(3)  NULL,
    CONSTRAINT PK_Carts PRIMARY KEY (Id),
    CONSTRAINT FK_Carts_Sites FOREIGN KEY (SiteId) REFERENCES web.Sites(Id),
    CONSTRAINT FK_Carts_Customers FOREIGN KEY (CustomerAccountId) REFERENCES web.CustomerAccounts(Id),
    CONSTRAINT FK_Carts_SalesOrders FOREIGN KEY (SalesOrderId) REFERENCES sales.SalesOrders(Id),
    CONSTRAINT CK_Carts_Status CHECK (Status IN ('active','ordered','abandoned'))
);
CREATE INDEX IX_Carts_Session ON web.Carts(SessionKey) WHERE Status = 'active';

CREATE TABLE web.CartItems (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    CartId     BIGINT        NOT NULL,
    ProductId  BIGINT        NOT NULL,
    Quantity   DECIMAL(18,4) NOT NULL,
    UnitPrice  DECIMAL(18,4) NOT NULL,
    AddedAt    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_CartItems PRIMARY KEY (Id),
    CONSTRAINT FK_CartItems_Carts FOREIGN KEY (CartId) REFERENCES web.Carts(Id) ON DELETE CASCADE,
    CONSTRAINT FK_CartItems_Products FOREIGN KEY (ProductId) REFERENCES md.Products(Id),
    CONSTRAINT UQ_CartItems UNIQUE (CartId, ProductId),
    CONSTRAINT CK_CartItems CHECK (Quantity > 0)
);

/* Form liên hệ -> tự tạo Lead trong CRM */
CREATE TABLE web.ContactSubmissions (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    SiteId      BIGINT         NOT NULL,
    FormCode    VARCHAR(30)    NOT NULL DEFAULT 'contact',
    FullName    NVARCHAR(150)  NOT NULL,
    Phone       VARCHAR(20)    NULL,
    Email       VARCHAR(255)   NULL,
    Message     NVARCHAR(2000) NULL,
    PageUrl     VARCHAR(1000)  NULL,
    UtmSource   VARCHAR(100)   NULL,
    UtmMedium   VARCHAR(100)   NULL,
    UtmCampaign VARCHAR(100)   NULL,
    IpAddress   VARCHAR(45)    NULL,
    ConsentGiven BIT           NOT NULL DEFAULT 0,
    LeadId      BIGINT         NULL,
    CreatedAt   DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ContactSubmissions PRIMARY KEY (Id),
    CONSTRAINT FK_ContactSubmissions_Sites FOREIGN KEY (SiteId) REFERENCES web.Sites(Id),
    CONSTRAINT FK_ContactSubmissions_Leads FOREIGN KEY (LeadId) REFERENCES crm.Leads(Id),
    CONSTRAINT CK_ContactSubmissions_Contact CHECK (Phone IS NOT NULL OR Email IS NOT NULL)
);
CREATE INDEX IX_ContactSubmissions_Site ON web.ContactSubmissions(SiteId, CreatedAt DESC);
GO
GO

-- ===================== 14_document_chat.sql =====================
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
GO

-- ===================== 20_views.sql =====================
/* =====================================================================
   MyERP - 20. VIEW / FUNCTION báo cáo dùng chung
   ===================================================================== */

/* Tồn kho khả dụng + cảnh báo dưới định mức */
CREATE OR ALTER VIEW inv.vw_StockAvailability
AS
SELECT  b.CompanyId,
        w.Id   AS WarehouseId, w.Code AS WarehouseCode, w.Name AS WarehouseName,
        p.Id   AS ProductId,   p.Code AS ProductCode,   p.Name AS ProductName,
        SUM(b.QtyOnHand)    AS QtyOnHand,
        SUM(b.QtyReserved)  AS QtyReserved,
        SUM(b.QtyAvailable) AS QtyAvailable,
        SUM(b.QtyIncoming)  AS QtyIncoming,
        p.MinStock,
        CAST(CASE WHEN SUM(b.QtyAvailable) < p.MinStock THEN 1 ELSE 0 END AS BIT) AS IsBelowMin,
        SUM(b.QtyOnHand * b.AvgCost) AS StockValue
FROM inv.StockBalances b
JOIN inv.Warehouses w ON w.Id = b.WarehouseId
JOIN md.Products   p ON p.Id = b.ProductId
GROUP BY b.CompanyId, w.Id, w.Code, w.Name, p.Id, p.Code, p.Name, p.MinStock;
GO

/* Bảng cân đối số phát sinh: đầu kỳ - phát sinh - cuối kỳ */
CREATE OR ALTER FUNCTION acc.fn_TrialBalance (@CompanyId BIGINT, @FromDate DATE, @ToDate DATE)
RETURNS TABLE
AS
RETURN
    SELECT  a.Id AS AccountId, a.Code, a.Name, a.AccountType,
            SUM(CASE WHEN e.PostingDate <  @FromDate THEN l.Debit - l.Credit ELSE 0 END) AS OpeningBalance,
            SUM(CASE WHEN e.PostingDate BETWEEN @FromDate AND @ToDate THEN l.Debit  ELSE 0 END) AS PeriodDebit,
            SUM(CASE WHEN e.PostingDate BETWEEN @FromDate AND @ToDate THEN l.Credit ELSE 0 END) AS PeriodCredit,
            SUM(CASE WHEN e.PostingDate <= @ToDate THEN l.Debit - l.Credit ELSE 0 END) AS ClosingBalance
    FROM acc.JournalEntryLines l
    JOIN acc.JournalEntries e ON e.Id = l.EntryId AND e.Status = 'posted'
    JOIN acc.Accounts a       ON a.Id = l.AccountId
    WHERE e.CompanyId = @CompanyId AND e.PostingDate <= @ToDate
    GROUP BY a.Id, a.Code, a.Name, a.AccountType;
GO

/* Tuổi nợ phải thu theo khách hàng */
CREATE OR ALTER VIEW acc.vw_ReceivableAging
AS
SELECT  i.CompanyId, i.PartnerId, p.Code AS PartnerCode, p.Name AS PartnerName,
        SUM(i.AmountDue) AS TotalDue,
        SUM(CASE WHEN i.DueDate IS NULL OR i.DueDate >= CAST(SYSDATETIME() AS DATE) THEN i.AmountDue ELSE 0 END) AS NotDue,
        SUM(CASE WHEN DATEDIFF(DAY, i.DueDate, SYSDATETIME()) BETWEEN 1  AND 30 THEN i.AmountDue ELSE 0 END) AS Overdue1_30,
        SUM(CASE WHEN DATEDIFF(DAY, i.DueDate, SYSDATETIME()) BETWEEN 31 AND 60 THEN i.AmountDue ELSE 0 END) AS Overdue31_60,
        SUM(CASE WHEN DATEDIFF(DAY, i.DueDate, SYSDATETIME()) BETWEEN 61 AND 90 THEN i.AmountDue ELSE 0 END) AS Overdue61_90,
        SUM(CASE WHEN DATEDIFF(DAY, i.DueDate, SYSDATETIME()) > 90 THEN i.AmountDue ELSE 0 END) AS OverdueOver90
FROM acc.Invoices i
JOIN md.Partners p ON p.Id = i.PartnerId
WHERE i.InvoiceType = 'out_invoice' AND i.Status = 'posted' AND i.PaymentStatus <> 'paid' AND i.IsDeleted = 0
GROUP BY i.CompanyId, i.PartnerId, p.Code, p.Name;
GO

/* Pipeline bán hàng theo giai đoạn */
CREATE OR ALTER VIEW crm.vw_PipelineSummary
AS
SELECT  o.CompanyId, o.PipelineId, s.Id AS StageId, s.Name AS StageName, s.SortOrder,
        o.OwnerUserId,
        COUNT(*)               AS OpportunityCount,
        SUM(o.ExpectedRevenue) AS ExpectedRevenue,
        SUM(o.WeightedRevenue) AS WeightedRevenue
FROM crm.Opportunities o
JOIN crm.Stages s ON s.Id = o.StageId
WHERE o.IsDeleted = 0 AND o.Status = 'open'
GROUP BY o.CompanyId, o.PipelineId, s.Id, s.Name, s.SortOrder, o.OwnerUserId;
GO

/* Doanh thu & lãi gộp theo tháng, nhân viên */
CREATE OR ALTER VIEW sales.vw_MonthlySales
AS
SELECT  so.CompanyId,
        YEAR(so.OrderDate)  AS SalesYear,
        MONTH(so.OrderDate) AS SalesMonth,
        so.SalespersonUserId,
        so.Channel,
        COUNT(DISTINCT so.Id)                       AS OrderCount,
        SUM(l.LineSubTotal)                         AS Revenue,
        SUM(l.UnitCost * l.Quantity)                AS Cogs,
        SUM(l.LineSubTotal - l.UnitCost * l.Quantity) AS GrossProfit
FROM sales.SalesOrders so
JOIN sales.SalesOrderLines l ON l.SalesOrderId = so.Id
WHERE so.Status IN ('confirmed','processing','completed') AND so.IsDeleted = 0
GROUP BY so.CompanyId, YEAR(so.OrderDate), MONTH(so.OrderDate), so.SalespersonUserId, so.Channel;
GO
GO

-- ===================== DỮ LIỆU =====================
EXEC sp_MSforeachtable N'ALTER TABLE ? NOCHECK CONSTRAINT ALL; ALTER TABLE ? DISABLE TRIGGER ALL;';
GO

-- acc.Accounts (79 dòng)
SET IDENTITY_INSERT [acc].[Accounts] ON;
INSERT INTO [acc].[Accounts] ([Id], [CompanyId], [Code], [Name], [ParentId], [AccountType], [NormalBalance], [AccountLevel], [IsPostable], [RequiresPartner], [CurrencyCode], [IsActive]) VALUES
(1, 1, '111', N'Tiền mặt', NULL, 'asset', 'debit', 1, 0, 0, NULL, 1),
(2, 1, '1111', N'Tiền Việt Nam', 1, 'asset', 'debit', 2, 1, 0, NULL, 1),
(3, 1, '1112', N'Ngoại tệ', 1, 'asset', 'debit', 2, 1, 0, NULL, 1),
(4, 1, '112', N'Tiền gửi ngân hàng', NULL, 'asset', 'debit', 1, 0, 0, NULL, 1),
(5, 1, '1121', N'Tiền Việt Nam', 4, 'asset', 'debit', 2, 1, 0, NULL, 1),
(6, 1, '1122', N'Ngoại tệ', 4, 'asset', 'debit', 2, 1, 0, NULL, 1),
(7, 1, '131', N'Phải thu của khách hàng', NULL, 'asset', 'both', 1, 1, 1, NULL, 1),
(8, 1, '133', N'Thuế GTGT được khấu trừ', NULL, 'asset', 'debit', 1, 0, 0, NULL, 1),
(9, 1, '1331', N'Thuế GTGT được khấu trừ của hàng hóa, dịch vụ', 8, 'asset', 'debit', 2, 1, 0, NULL, 1),
(10, 1, '1332', N'Thuế GTGT được khấu trừ của TSCĐ', 8, 'asset', 'debit', 2, 1, 0, NULL, 1),
(11, 1, '138', N'Phải thu khác', NULL, 'asset', 'debit', 1, 0, 0, NULL, 1),
(12, 1, '1388', N'Phải thu khác', 11, 'asset', 'debit', 2, 1, 1, NULL, 1),
(13, 1, '141', N'Tạm ứng', NULL, 'asset', 'debit', 1, 1, 0, NULL, 1),
(14, 1, '151', N'Hàng mua đang đi đường', NULL, 'asset', 'debit', 1, 1, 0, NULL, 1),
(15, 1, '152', N'Nguyên liệu, vật liệu', NULL, 'asset', 'debit', 1, 1, 0, NULL, 1),
(16, 1, '153', N'Công cụ, dụng cụ', NULL, 'asset', 'debit', 1, 1, 0, NULL, 1),
(17, 1, '154', N'Chi phí sản xuất, kinh doanh dở dang', NULL, 'asset', 'debit', 1, 1, 0, NULL, 1),
(18, 1, '155', N'Thành phẩm', NULL, 'asset', 'debit', 1, 1, 0, NULL, 1),
(19, 1, '156', N'Hàng hóa', NULL, 'asset', 'debit', 1, 0, 0, NULL, 1),
(20, 1, '1561', N'Giá mua hàng hóa', 19, 'asset', 'debit', 2, 1, 0, NULL, 1),
(21, 1, '1562', N'Chi phí thu mua hàng hóa', 19, 'asset', 'debit', 2, 1, 0, NULL, 1),
(22, 1, '157', N'Hàng gửi đi bán', NULL, 'asset', 'debit', 1, 1, 0, NULL, 1),
(23, 1, '211', N'Tài sản cố định hữu hình', NULL, 'asset', 'debit', 1, 1, 0, NULL, 1),
(24, 1, '213', N'Tài sản cố định vô hình', NULL, 'asset', 'debit', 1, 1, 0, NULL, 1),
(25, 1, '214', N'Hao mòn tài sản cố định', NULL, 'asset', 'credit', 1, 0, 0, NULL, 1),
(26, 1, '2141', N'Hao mòn TSCĐ hữu hình', 25, 'asset', 'credit', 2, 1, 0, NULL, 1),
(27, 1, '2143', N'Hao mòn TSCĐ vô hình', 25, 'asset', 'credit', 2, 1, 0, NULL, 1),
(28, 1, '242', N'Chi phí trả trước', NULL, 'asset', 'debit', 1, 1, 0, NULL, 1),
(29, 1, '331', N'Phải trả cho người bán', NULL, 'liability', 'both', 1, 1, 1, NULL, 1),
(30, 1, '333', N'Thuế và các khoản phải nộp Nhà nước', NULL, 'liability', 'credit', 1, 0, 0, NULL, 1),
(31, 1, '3331', N'Thuế giá trị gia tăng phải nộp', 30, 'liability', 'credit', 2, 0, 0, NULL, 1),
(32, 1, '33311', N'Thuế GTGT đầu ra', 31, 'liability', 'credit', 3, 1, 0, NULL, 1),
(33, 1, '33312', N'Thuế GTGT hàng nhập khẩu', 31, 'liability', 'credit', 3, 1, 0, NULL, 1),
(34, 1, '3334', N'Thuế thu nhập doanh nghiệp', 30, 'liability', 'credit', 2, 1, 0, NULL, 1),
(35, 1, '3335', N'Thuế thu nhập cá nhân', 30, 'liability', 'credit', 2, 1, 0, NULL, 1),
(36, 1, '3338', N'Thuế khác', 30, 'liability', 'credit', 2, 1, 0, NULL, 1),
(37, 1, '334', N'Phải trả người lao động', NULL, 'liability', 'credit', 1, 0, 0, NULL, 1),
(38, 1, '3341', N'Phải trả công nhân viên', 37, 'liability', 'credit', 2, 1, 0, NULL, 1),
(39, 1, '335', N'Chi phí phải trả', NULL, 'liability', 'credit', 1, 1, 0, NULL, 1),
(40, 1, '338', N'Phải trả, phải nộp khác', NULL, 'liability', 'credit', 1, 0, 0, NULL, 1),
(41, 1, '3382', N'Kinh phí công đoàn', 40, 'liability', 'credit', 2, 1, 0, NULL, 1),
(42, 1, '3383', N'Bảo hiểm xã hội', 40, 'liability', 'credit', 2, 1, 0, NULL, 1),
(43, 1, '3384', N'Bảo hiểm y tế', 40, 'liability', 'credit', 2, 1, 0, NULL, 1),
(44, 1, '3386', N'Bảo hiểm thất nghiệp', 40, 'liability', 'credit', 2, 1, 0, NULL, 1),
(45, 1, '3387', N'Doanh thu chưa thực hiện', 40, 'liability', 'credit', 2, 1, 0, NULL, 1),
(46, 1, '3388', N'Phải trả, phải nộp khác', 40, 'liability', 'credit', 2, 1, 1, NULL, 1),
(47, 1, '341', N'Vay và nợ thuê tài chính', NULL, 'liability', 'credit', 1, 1, 1, NULL, 1),
(48, 1, '411', N'Vốn đầu tư của chủ sở hữu', NULL, 'equity', 'credit', 1, 0, 0, NULL, 1),
(49, 1, '4111', N'Vốn góp của chủ sở hữu', 48, 'equity', 'credit', 2, 1, 0, NULL, 1),
(50, 1, '421', N'Lợi nhuận sau thuế chưa phân phối', NULL, 'equity', 'both', 1, 0, 0, NULL, 1),
(51, 1, '4211', N'LNST chưa phân phối năm trước', 50, 'equity', 'both', 2, 1, 0, NULL, 1),
(52, 1, '4212', N'LNST chưa phân phối năm nay', 50, 'equity', 'both', 2, 1, 0, NULL, 1),
(53, 1, '511', N'Doanh thu bán hàng và cung cấp dịch vụ', NULL, 'revenue', 'credit', 1, 0, 0, NULL, 1),
(54, 1, '5111', N'Doanh thu bán hàng hóa', 53, 'revenue', 'credit', 2, 1, 0, NULL, 1),
(55, 1, '5112', N'Doanh thu bán thành phẩm', 53, 'revenue', 'credit', 2, 1, 0, NULL, 1),
(56, 1, '5113', N'Doanh thu cung cấp dịch vụ', 53, 'revenue', 'credit', 2, 1, 0, NULL, 1),
(57, 1, '515', N'Doanh thu hoạt động tài chính', NULL, 'revenue', 'credit', 1, 1, 0, NULL, 1),
(58, 1, '521', N'Các khoản giảm trừ doanh thu', NULL, 'revenue', 'debit', 1, 0, 0, NULL, 1),
(59, 1, '5211', N'Chiết khấu thương mại', 58, 'revenue', 'debit', 2, 1, 0, NULL, 1),
(60, 1, '5212', N'Hàng bán bị trả lại', 58, 'revenue', 'debit', 2, 1, 0, NULL, 1),
(61, 1, '5213', N'Giảm giá hàng bán', 58, 'revenue', 'debit', 2, 1, 0, NULL, 1),
(62, 1, '632', N'Giá vốn hàng bán', NULL, 'cogs', 'debit', 1, 1, 0, NULL, 1),
(63, 1, '635', N'Chi phí tài chính', NULL, 'expense', 'debit', 1, 1, 0, NULL, 1),
(64, 1, '641', N'Chi phí bán hàng', NULL, 'expense', 'debit', 1, 0, 0, NULL, 1),
(65, 1, '6411', N'Chi phí nhân viên', 64, 'expense', 'debit', 2, 1, 0, NULL, 1),
(66, 1, '6414', N'Chi phí khấu hao TSCĐ', 64, 'expense', 'debit', 2, 1, 0, NULL, 1),
(67, 1, '6417', N'Chi phí dịch vụ mua ngoài', 64, 'expense', 'debit', 2, 1, 0, NULL, 1),
(68, 1, '6418', N'Chi phí bằng tiền khác', 64, 'expense', 'debit', 2, 1, 0, NULL, 1),
(69, 1, '642', N'Chi phí quản lý doanh nghiệp', NULL, 'expense', 'debit', 1, 0, 0, NULL, 1),
(70, 1, '6421', N'Chi phí nhân viên quản lý', 69, 'expense', 'debit', 2, 1, 0, NULL, 1),
(71, 1, '6424', N'Chi phí khấu hao TSCĐ', 69, 'expense', 'debit', 2, 1, 0, NULL, 1),
(72, 1, '6425', N'Thuế, phí và lệ phí', 69, 'expense', 'debit', 2, 1, 0, NULL, 1),
(73, 1, '6427', N'Chi phí dịch vụ mua ngoài', 69, 'expense', 'debit', 2, 1, 0, NULL, 1),
(74, 1, '6428', N'Chi phí bằng tiền khác', 69, 'expense', 'debit', 2, 1, 0, NULL, 1),
(75, 1, '711', N'Thu nhập khác', NULL, 'other_income', 'credit', 1, 1, 0, NULL, 1),
(76, 1, '811', N'Chi phí khác', NULL, 'other_expense', 'debit', 1, 1, 0, NULL, 1),
(77, 1, '821', N'Chi phí thuế thu nhập doanh nghiệp', NULL, 'expense', 'debit', 1, 0, 0, NULL, 1),
(78, 1, '8211', N'Chi phí thuế TNDN hiện hành', 77, 'expense', 'debit', 2, 1, 0, NULL, 1),
(79, 1, '911', N'Xác định kết quả kinh doanh', NULL, 'equity', 'both', 1, 1, 0, NULL, 1)
;
SET IDENTITY_INSERT [acc].[Accounts] OFF;
GO

-- acc.BankAccounts (1 dòng)
SET IDENTITY_INSERT [acc].[BankAccounts] ON;
INSERT INTO [acc].[BankAccounts] ([Id], [CompanyId], [AccountId], [BankName], [BankBranch], [AccountNo], [AccountName], [CurrencyCode], [IsActive]) VALUES
(1, 1, 5, N'Vietcombank', N'Chi nhánh Hà Nội', '0011000000001', N'CONG TY ABC', 'VND', 1)
;
SET IDENTITY_INSERT [acc].[BankAccounts] OFF;
GO

-- acc.DefaultAccounts (27 dòng)
INSERT INTO [acc].[DefaultAccounts] ([CompanyId], [MappingKey], [AccountId]) VALUES
(1, 'admin_expense', 74),
(1, 'advance', 13),
(1, 'bank', 5),
(1, 'cash', 2),
(1, 'cogs', 62),
(1, 'fx_gain', 57),
(1, 'fx_loss', 63),
(1, 'health_insurance', 43),
(1, 'inventory', 20),
(1, 'payable', 29),
(1, 'pit_payable', 35),
(1, 'pnl', 79),
(1, 'purchase_cost', 21),
(1, 'receivable', 7),
(1, 'retained_earnings', 52),
(1, 'revenue_goods', 54),
(1, 'revenue_service', 56),
(1, 'salary_payable', 38),
(1, 'sales_discount', 59),
(1, 'sales_return', 60),
(1, 'selling_expense', 67),
(1, 'shipping_expense', 67),
(1, 'social_insurance', 42),
(1, 'unemployment_insurance', 44),
(1, 'union_fee', 41),
(1, 'vat_in', 9),
(1, 'vat_out', 32)
;
GO

-- acc.FiscalPeriods (12 dòng)
SET IDENTITY_INSERT [acc].[FiscalPeriods] ON;
INSERT INTO [acc].[FiscalPeriods] ([Id], [FiscalYearId], [PeriodNo], [StartDate], [EndDate], [Status], [ClosedAt], [ClosedBy]) VALUES
(1, 1, 1, '2026-01-01', '2026-01-31', 'open', NULL, NULL),
(2, 1, 2, '2026-02-01', '2026-02-28', 'open', NULL, NULL),
(3, 1, 3, '2026-03-01', '2026-03-31', 'open', NULL, NULL),
(4, 1, 4, '2026-04-01', '2026-04-30', 'open', NULL, NULL),
(5, 1, 5, '2026-05-01', '2026-05-31', 'open', NULL, NULL),
(6, 1, 6, '2026-06-01', '2026-06-30', 'open', NULL, NULL),
(7, 1, 7, '2026-07-01', '2026-07-31', 'open', NULL, NULL),
(8, 1, 8, '2026-08-01', '2026-08-31', 'open', NULL, NULL),
(9, 1, 9, '2026-09-01', '2026-09-30', 'open', NULL, NULL),
(10, 1, 10, '2026-10-01', '2026-10-31', 'open', NULL, NULL),
(11, 1, 11, '2026-11-01', '2026-11-30', 'open', NULL, NULL),
(12, 1, 12, '2026-12-01', '2026-12-31', 'open', NULL, NULL)
;
SET IDENTITY_INSERT [acc].[FiscalPeriods] OFF;
GO

-- acc.FiscalYears (1 dòng)
SET IDENTITY_INSERT [acc].[FiscalYears] ON;
INSERT INTO [acc].[FiscalYears] ([Id], [CompanyId], [Code], [StartDate], [EndDate], [Status]) VALUES
(1, 1, '2026', '2026-01-01', '2026-12-31', 'open')
;
SET IDENTITY_INSERT [acc].[FiscalYears] OFF;
GO

-- acc.Journals (9 dòng)
SET IDENTITY_INSERT [acc].[Journals] ON;
INSERT INTO [acc].[Journals] ([Id], [CompanyId], [Code], [Name], [JournalType], [DefaultAccountId], [SequenceCode], [IsActive]) VALUES
(1, 1, 'BH', N'Nhật ký bán hàng', 'sale', 54, 'INVOICE_OUT', 1),
(2, 1, 'MH', N'Nhật ký mua hàng', 'purchase', 20, 'INVOICE_IN', 1),
(3, 1, 'PT', N'Phiếu thu tiền mặt', 'cash', 2, 'CASH_RECEIPT', 1),
(4, 1, 'PC', N'Phiếu chi tiền mặt', 'cash', 2, 'CASH_PAYMENT', 1),
(5, 1, 'BC', N'Báo có ngân hàng', 'bank', 5, 'BANK_RECEIPT', 1),
(6, 1, 'BN', N'Báo nợ ngân hàng', 'bank', 5, 'BANK_PAYMENT', 1),
(7, 1, 'KHO', N'Nhật ký kho', 'stock', 20, 'JOURNAL_ENTRY', 1),
(8, 1, 'LUONG', N'Nhật ký lương', 'payroll', 38, 'JOURNAL_ENTRY', 1),
(9, 1, 'TH', N'Nhật ký chung', 'general', NULL, 'JOURNAL_ENTRY', 1)
;
SET IDENTITY_INSERT [acc].[Journals] OFF;
GO

-- acc.Payments (170 dòng)
SET IDENTITY_INSERT [acc].[Payments] ON;
INSERT INTO [acc].[Payments] ([Id], [CompanyId], [BranchId], [DocNo], [PaymentType], [PaymentMethodCode], [PartnerId], [EmployeeId], [PaymentDate], [Amount], [CurrencyCode], [ExchangeRate], [BankAccountId], [CashAccountId], [CounterAccountId], [Reason], [PersonName], [BankReference], [Status], [JournalEntryId], [AllocatedAmount], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted], [Category], [SalesOrderId], [PurchaseOrderId]) VALUES
(1, 1, NULL, 'BC2609-00001', 'receipt', 'bank_transfer', NULL, NULL, '2026-09-17', 400000000.00, 'VND', 1.000000, 1, NULL, NULL, N'Chủ shop góp vốn kinh doanh', N'Chủ cửa hàng', NULL, 'posted', NULL, 0.00, '2026-09-17T03:00:00.0000000', 1, NULL, NULL, 0, 'other_income', NULL, NULL),
(2, 1, NULL, 'PT2609-00001', 'receipt', 'cash', NULL, NULL, '2026-09-17', 30000000.00, 'VND', 1.000000, NULL, 2, NULL, N'Nạp quỹ tiền mặt đầu kỳ', N'Chủ cửa hàng', NULL, 'posted', NULL, 0.00, '2026-09-17T03:00:00.0000000', 1, NULL, NULL, 0, 'other_income', NULL, NULL),
(3, 1, NULL, 'PT2609-00002', 'receipt', 'cash', 38, NULL, '2026-09-24', 836000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2609-00001', NULL, NULL, 'posted', NULL, 0.00, '2026-09-24T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 1, NULL),
(4, 1, NULL, 'PT2609-00003', 'receipt', 'cash', 29, NULL, '2026-09-25', 1080000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2609-00002', NULL, NULL, 'posted', NULL, 0.00, '2026-09-25T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 2, NULL),
(5, 1, NULL, 'BC2609-00003', 'receipt', 'ewallet', 39, NULL, '2026-09-30', 578000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2609-00003', NULL, NULL, 'posted', NULL, 0.00, '2026-09-30T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 3, NULL),
(6, 1, NULL, 'BC2610-00001', 'receipt', 'ewallet', 37, NULL, '2026-10-02', 748200.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2609-00005', NULL, NULL, 'posted', NULL, 0.00, '2026-10-02T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 5, NULL),
(7, 1, NULL, 'BC2610-00002', 'receipt', 'ewallet', 40, NULL, '2026-10-03', 489000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2609-00006', NULL, NULL, 'posted', NULL, 0.00, '2026-10-03T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 6, NULL),
(8, 1, NULL, 'BC2609-00002', 'receipt', 'bank_transfer', 29, NULL, '2026-09-28', 229000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2609-00008', NULL, NULL, 'posted', NULL, 0.00, '2026-09-28T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 8, NULL),
(9, 1, NULL, 'PT2609-00004', 'receipt', 'cash', 37, NULL, '2026-09-30', 1438000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2609-00010', NULL, NULL, 'posted', NULL, 0.00, '2026-09-30T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 10, NULL),
(10, 1, NULL, 'PT2610-00001', 'receipt', 'cash', 29, NULL, '2026-10-01', 520000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00002', NULL, NULL, 'posted', NULL, 0.00, '2026-10-01T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 12, NULL),
(11, 1, NULL, 'BC2610-00003', 'receipt', 'ewallet', 41, NULL, '2026-10-07', 489000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2610-00004', NULL, NULL, 'posted', NULL, 0.00, '2026-10-07T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 14, NULL),
(12, 1, NULL, 'BC2610-00005', 'receipt', 'ewallet', 37, NULL, '2026-10-08', 808000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2610-00005', NULL, NULL, 'posted', NULL, 0.00, '2026-10-08T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 15, NULL),
(13, 1, NULL, 'BC2610-00006', 'receipt', 'ewallet', 39, NULL, '2026-10-09', 1207000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2610-00007', NULL, NULL, 'posted', NULL, 0.00, '2026-10-09T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 17, NULL),
(14, 1, NULL, 'PT2610-00002', 'receipt', 'cash', 29, NULL, '2026-10-06', 847200.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00009', NULL, NULL, 'posted', NULL, 0.00, '2026-10-06T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 19, NULL),
(15, 1, NULL, 'PT2610-00003', 'receipt', 'cash', 29, NULL, '2026-10-07', 199000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00011', NULL, NULL, 'posted', NULL, 0.00, '2026-10-07T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 21, NULL),
(16, 1, NULL, 'BC2610-00007', 'receipt', 'ewallet', 38, NULL, '2026-10-12', 279000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2610-00012', NULL, NULL, 'posted', NULL, 0.00, '2026-10-12T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 22, NULL),
(17, 1, NULL, 'PT2610-00004', 'receipt', 'cash', 38, NULL, '2026-10-09', 2529000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00014', NULL, NULL, 'posted', NULL, 0.00, '2026-10-09T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 24, NULL),
(18, 1, NULL, 'BC2610-00010', 'receipt', 'ewallet', 36, NULL, '2026-10-14', 578000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2610-00015', NULL, NULL, 'posted', NULL, 0.00, '2026-10-14T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 25, NULL),
(19, 1, NULL, 'BC2610-00013', 'receipt', 'ewallet', 39, NULL, '2026-10-15', 448000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2610-00017', NULL, NULL, 'posted', NULL, 0.00, '2026-10-15T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 27, NULL),
(20, 1, NULL, 'BC2610-00008', 'receipt', 'bank_transfer', 29, NULL, '2026-10-12', 249000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2610-00020', NULL, NULL, 'posted', NULL, 0.00, '2026-10-12T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 30, NULL),
(21, 1, NULL, 'BC2610-00014', 'receipt', 'ewallet', 37, NULL, '2026-10-17', 948000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2610-00021', NULL, NULL, 'posted', NULL, 0.00, '2026-10-17T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 31, NULL),
(22, 1, NULL, 'BC2610-00009', 'receipt', 'bank_transfer', 29, NULL, '2026-10-13', 159000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2610-00022', NULL, NULL, 'posted', NULL, 0.00, '2026-10-13T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 32, NULL),
(23, 1, NULL, 'BC2610-00016', 'receipt', 'ewallet', 35, NULL, '2026-10-19', 578000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2610-00023', NULL, NULL, 'posted', NULL, 0.00, '2026-10-19T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 33, NULL),
(24, 1, NULL, 'PT2610-00005', 'receipt', 'cash', 37, NULL, '2026-10-15', 1335000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00025', NULL, NULL, 'posted', NULL, 0.00, '2026-10-15T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 35, NULL),
(25, 1, NULL, 'BC2610-00017', 'receipt', 'ewallet', 38, NULL, '2026-10-20', 775200.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2610-00026', NULL, NULL, 'posted', NULL, 0.00, '2026-10-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 36, NULL),
(26, 1, NULL, 'PT2610-00006', 'receipt', 'cash', 29, NULL, '2026-10-17', 249000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00028', NULL, NULL, 'posted', NULL, 0.00, '2026-10-17T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 38, NULL),
(27, 1, NULL, 'BC2610-00015', 'receipt', 'bank_transfer', 29, NULL, '2026-10-17', 690000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2610-00029', NULL, NULL, 'posted', NULL, 0.00, '2026-10-17T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 39, NULL),
(28, 1, NULL, 'BC2610-00020', 'receipt', 'ewallet', 37, NULL, '2026-10-22', 928000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2610-00030', NULL, NULL, 'posted', NULL, 0.00, '2026-10-22T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 40, NULL),
(29, 1, NULL, 'BC2610-00021', 'receipt', 'ewallet', 39, NULL, '2026-10-23', 956000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2610-00032', NULL, NULL, 'posted', NULL, 0.00, '2026-10-23T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 42, NULL),
(30, 1, NULL, 'BC2610-00022', 'receipt', 'ewallet', 35, NULL, '2026-10-24', 807000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2610-00033', NULL, NULL, 'posted', NULL, 0.00, '2026-10-24T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 43, NULL),
(31, 1, NULL, 'BC2610-00024', 'receipt', 'ewallet', 38, NULL, '2026-10-25', 189000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2610-00036', NULL, NULL, 'posted', NULL, 0.00, '2026-10-25T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 46, NULL),
(32, 1, NULL, 'PT2610-00007', 'receipt', 'cash', 29, NULL, '2026-10-22', 459000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00039', NULL, NULL, 'posted', NULL, 0.00, '2026-10-22T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 49, NULL),
(33, 1, NULL, 'PT2610-00008', 'receipt', 'cash', 38, NULL, '2026-10-22', 1018200.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00040', NULL, NULL, 'posted', NULL, 0.00, '2026-10-22T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 50, NULL),
(34, 1, NULL, 'BC2610-00025', 'receipt', 'ewallet', 36, NULL, '2026-10-27', 109000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2610-00041', NULL, NULL, 'posted', NULL, 0.00, '2026-10-27T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 51, NULL),
(35, 1, NULL, 'BC2610-00023', 'receipt', 'bank_transfer', 29, NULL, '2026-10-24', 159000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2610-00042', NULL, NULL, 'posted', NULL, 0.00, '2026-10-24T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 52, NULL),
(36, 1, NULL, 'BC2610-00029', 'receipt', 'ewallet', 34, NULL, '2026-10-29', 443100.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2610-00043', NULL, NULL, 'posted', NULL, 0.00, '2026-10-29T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 53, NULL),
(37, 1, NULL, 'BC2610-00030', 'receipt', 'ewallet', 37, NULL, '2026-10-29', 528000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2610-00044', NULL, NULL, 'posted', NULL, 0.00, '2026-10-29T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 54, NULL),
(38, 1, NULL, 'PT2610-00009', 'receipt', 'cash', 29, NULL, '2026-10-26', 919000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00047', NULL, NULL, 'posted', NULL, 0.00, '2026-10-26T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 57, NULL),
(39, 1, NULL, 'PT2610-00010', 'receipt', 'cash', 37, NULL, '2026-10-26', 887000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00048', NULL, NULL, 'posted', NULL, 0.00, '2026-10-26T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 58, NULL),
(40, 1, NULL, 'BC2610-00031', 'receipt', 'ewallet', 35, NULL, '2026-10-31', 777000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2610-00049', NULL, NULL, 'posted', NULL, 0.00, '2026-10-31T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 59, NULL),
(41, 1, NULL, 'BC2610-00026', 'receipt', 'bank_transfer', 29, NULL, '2026-10-28', 249000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2610-00052', NULL, NULL, 'posted', NULL, 0.00, '2026-10-28T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 62, NULL),
(42, 1, NULL, 'BC2611-00001', 'receipt', 'ewallet', 34, NULL, '2026-11-02', 489000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2610-00053', NULL, NULL, 'posted', NULL, 0.00, '2026-11-02T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 63, NULL),
(43, 1, NULL, 'BC2611-00002', 'receipt', 'ewallet', 37, NULL, '2026-11-03', 622200.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2610-00055', NULL, NULL, 'posted', NULL, 0.00, '2026-11-03T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 65, NULL),
(44, 1, NULL, 'PT2610-00011', 'receipt', 'cash', 34, NULL, '2026-10-30', 837100.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00058', NULL, NULL, 'posted', NULL, 0.00, '2026-10-30T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 68, NULL),
(45, 1, NULL, 'BC2611-00005', 'receipt', 'ewallet', 35, NULL, '2026-11-04', 657000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2610-00059', NULL, NULL, 'posted', NULL, 0.00, '2026-11-04T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 69, NULL),
(46, 1, NULL, 'PT2610-00012', 'receipt', 'cash', 29, NULL, '2026-10-31', 727000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2610-00060', NULL, NULL, 'posted', NULL, 0.00, '2026-10-31T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 70, NULL),
(47, 1, NULL, 'PT2611-00001', 'receipt', 'cash', 29, NULL, '2026-11-01', 159000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00002', NULL, NULL, 'posted', NULL, 0.00, '2026-11-01T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 72, NULL),
(48, 1, NULL, 'BC2611-00008', 'receipt', 'ewallet', 33, NULL, '2026-11-06', 109000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00003', NULL, NULL, 'posted', NULL, 0.00, '2026-11-06T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 73, NULL),
(49, 1, NULL, 'BC2611-00009', 'receipt', 'ewallet', 36, NULL, '2026-11-06', 419000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00004', NULL, NULL, 'posted', NULL, 0.00, '2026-11-06T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 74, NULL),
(50, 1, NULL, 'BC2611-00003', 'receipt', 'bank_transfer', 33, NULL, '2026-11-03', 849000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2611-00006', NULL, NULL, 'posted', NULL, 0.00, '2026-11-03T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 76, NULL),
(51, 1, NULL, 'BC2611-00004', 'receipt', 'bank_transfer', 29, NULL, '2026-11-03', 249000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2611-00007', NULL, NULL, 'posted', NULL, 0.00, '2026-11-03T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 77, NULL),
(52, 1, NULL, 'BC2611-00011', 'receipt', 'ewallet', 34, NULL, '2026-11-08', 1269000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00008', NULL, NULL, 'posted', NULL, 0.00, '2026-11-08T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 78, NULL),
(53, 1, NULL, 'PT2611-00002', 'receipt', 'cash', 29, NULL, '2026-11-04', 459000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00010', NULL, NULL, 'posted', NULL, 0.00, '2026-11-04T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 80, NULL),
(54, 1, NULL, 'BC2611-00012', 'receipt', 'ewallet', 33, NULL, '2026-11-09', 189000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2611-00011', NULL, NULL, 'posted', NULL, 0.00, '2026-11-09T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 81, NULL),
(55, 1, NULL, 'BC2611-00013', 'receipt', 'ewallet', 35, NULL, '2026-11-10', 1590000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00012', NULL, NULL, 'posted', NULL, 0.00, '2026-11-10T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 82, NULL),
(56, 1, NULL, 'PT2611-00003', 'receipt', 'cash', 29, NULL, '2026-11-05', 224100.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00014', NULL, NULL, 'posted', NULL, 0.00, '2026-11-05T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 84, NULL),
(57, 1, NULL, 'BC2611-00014', 'receipt', 'ewallet', 34, NULL, '2026-11-11', 359000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2611-00015', NULL, NULL, 'posted', NULL, 0.00, '2026-11-11T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 85, NULL),
(58, 1, NULL, 'BC2611-00010', 'receipt', 'bank_transfer', 29, NULL, '2026-11-06', 428000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2611-00018', NULL, NULL, 'posted', NULL, 0.00, '2026-11-06T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 88, NULL),
(59, 1, NULL, 'PT2611-00004', 'receipt', 'cash', 29, NULL, '2026-11-07', 597000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00019', NULL, NULL, 'posted', NULL, 0.00, '2026-11-07T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 89, NULL),
(60, 1, NULL, 'BC2611-00018', 'receipt', 'ewallet', 32, NULL, '2026-11-12', 189000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00020', NULL, NULL, 'posted', NULL, 0.00, '2026-11-12T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 90, NULL),
(61, 1, NULL, 'PT2611-00005', 'receipt', 'cash', 34, NULL, '2026-11-08', 1127000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00022', NULL, NULL, 'posted', NULL, 0.00, '2026-11-08T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 92, NULL),
(62, 1, NULL, 'BC2611-00019', 'receipt', 'ewallet', 35, NULL, '2026-11-13', 909000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2611-00023', NULL, NULL, 'posted', NULL, 0.00, '2026-11-13T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 93, NULL),
(63, 1, NULL, 'PT2611-00006', 'receipt', 'cash', 29, NULL, '2026-11-09', 159000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00025', NULL, NULL, 'posted', NULL, 0.00, '2026-11-09T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 95, NULL),
(64, 1, NULL, 'PT2611-00007', 'receipt', 'cash', 29, NULL, '2026-11-09', 299000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00026', NULL, NULL, 'posted', NULL, 0.00, '2026-11-09T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 96, NULL),
(65, 1, NULL, 'BC2611-00022', 'receipt', 'ewallet', 33, NULL, '2026-11-14', 419000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00027', NULL, NULL, 'posted', NULL, 0.00, '2026-11-14T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 97, NULL),
(66, 1, NULL, 'BC2611-00023', 'receipt', 'ewallet', 31, NULL, '2026-11-15', 1468200.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00029', NULL, NULL, 'posted', NULL, 0.00, '2026-11-15T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 99, NULL),
(67, 1, NULL, 'BC2611-00024', 'receipt', 'ewallet', 30, NULL, '2026-11-16', 189000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2611-00031', NULL, NULL, 'posted', NULL, 0.00, '2026-11-16T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 101, NULL),
(68, 1, NULL, 'BC2611-00025', 'receipt', 'ewallet', 34, NULL, '2026-11-16', 1088000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00032', NULL, NULL, 'posted', NULL, 0.00, '2026-11-16T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 102, NULL),
(69, 1, NULL, 'BC2611-00015', 'receipt', 'bank_transfer', 33, NULL, '2026-11-11', 498000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2611-00033', NULL, NULL, 'posted', NULL, 0.00, '2026-11-11T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 103, NULL),
(70, 1, NULL, 'BC2611-00028', 'receipt', 'ewallet', 33, NULL, '2026-11-17', 429000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2611-00034', NULL, NULL, 'posted', NULL, 0.00, '2026-11-17T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 104, NULL),
(71, 1, NULL, 'PT2611-00008', 'receipt', 'cash', 29, NULL, '2026-11-12', 159000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00036', NULL, NULL, 'posted', NULL, 0.00, '2026-11-12T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 106, NULL),
(72, 1, NULL, 'PT2611-00009', 'receipt', 'cash', 29, NULL, '2026-11-12', 690000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00037', NULL, NULL, 'posted', NULL, 0.00, '2026-11-12T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 107, NULL),
(73, 1, NULL, 'BC2611-00029', 'receipt', 'ewallet', 34, NULL, '2026-11-18', 389100.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2611-00038', NULL, NULL, 'posted', NULL, 0.00, '2026-11-18T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 108, NULL),
(74, 1, NULL, 'BC2611-00020', 'receipt', 'bank_transfer', 30, NULL, '2026-11-13', 677000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2611-00040', NULL, NULL, 'posted', NULL, 0.00, '2026-11-13T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 110, NULL),
(75, 1, NULL, 'BC2611-00021', 'receipt', 'bank_transfer', 29, NULL, '2026-11-13', 1380000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2611-00041', NULL, NULL, 'posted', NULL, 0.00, '2026-11-13T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 111, NULL),
(76, 1, NULL, 'BC2611-00030', 'receipt', 'ewallet', 31, NULL, '2026-11-18', 967000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2611-00042', NULL, NULL, 'posted', NULL, 0.00, '2026-11-18T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 112, NULL),
(77, 1, NULL, 'PT2611-00010', 'receipt', 'cash', 29, NULL, '2026-11-14', 358200.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00045', NULL, NULL, 'posted', NULL, 0.00, '2026-11-14T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 115, NULL),
(78, 1, NULL, 'BC2611-00034', 'receipt', 'ewallet', 32, NULL, '2026-11-19', 389000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00046', NULL, NULL, 'posted', NULL, 0.00, '2026-11-19T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 116, NULL),
(79, 1, NULL, 'BC2611-00035', 'receipt', 'ewallet', 30, NULL, '2026-11-20', 848000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00047', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 117, NULL),
(80, 1, NULL, 'BC2611-00036', 'receipt', 'ewallet', 33, NULL, '2026-11-20', 189000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00048', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 118, NULL),
(81, 1, NULL, 'PT2611-00011', 'receipt', 'cash', 41, NULL, '2026-11-15', 668100.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00050', NULL, NULL, 'posted', NULL, 0.00, '2026-11-15T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 120, NULL),
(82, 1, NULL, 'PT2611-00012', 'receipt', 'cash', 29, NULL, '2026-11-15', 299000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00051', NULL, NULL, 'posted', NULL, 0.00, '2026-11-15T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 121, NULL),
(83, 1, NULL, 'BC2611-00037', 'receipt', 'ewallet', 41, NULL, '2026-11-20', 628000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2611-00052', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 122, NULL),
(84, 1, NULL, 'BC2611-00026', 'receipt', 'bank_transfer', 29, NULL, '2026-11-16', 249000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2611-00054', NULL, NULL, 'posted', NULL, 0.00, '2026-11-16T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 124, NULL),
(85, 1, NULL, 'BC2611-00027', 'receipt', 'bank_transfer', 33, NULL, '2026-11-16', 1149000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2611-00055', NULL, NULL, 'posted', NULL, 0.00, '2026-11-16T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 125, NULL),
(86, 1, NULL, 'BC2611-00038', 'receipt', 'ewallet', 31, NULL, '2026-11-20', 1936000.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00056', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 126, NULL),
(87, 1, NULL, 'BC2611-00039', 'receipt', 'ewallet', 30, NULL, '2026-11-20', 429000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2611-00057', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 127, NULL),
(88, 1, NULL, 'PT2611-00013', 'receipt', 'cash', 29, NULL, '2026-11-17', 690000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00060', NULL, NULL, 'posted', NULL, 0.00, '2026-11-17T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 130, NULL),
(89, 1, NULL, 'PT2611-00014', 'receipt', 'cash', 29, NULL, '2026-11-17', 359000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00061', NULL, NULL, 'posted', NULL, 0.00, '2026-11-17T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 131, NULL),
(90, 1, NULL, 'BC2611-00040', 'receipt', 'ewallet', 40, NULL, '2026-11-20', 585100.00, 'VND', 1.000000, 1, NULL, NULL, N'Shopee thanh toán đơn DH2611-00062', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 132, NULL),
(91, 1, NULL, 'BC2611-00031', 'receipt', 'bank_transfer', 30, NULL, '2026-11-18', 1766100.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2611-00064', NULL, NULL, 'posted', NULL, 0.00, '2026-11-18T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 134, NULL),
(92, 1, NULL, 'PT2611-00015', 'receipt', 'cash', 29, NULL, '2026-11-18', 199000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00069', NULL, NULL, 'posted', NULL, 0.00, '2026-11-18T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 139, NULL),
(93, 1, NULL, 'PT2611-00016', 'receipt', 'cash', 29, NULL, '2026-11-19', 539100.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00076', NULL, NULL, 'posted', NULL, 0.00, '2026-11-19T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 146, NULL),
(94, 1, NULL, 'BC2611-00041', 'receipt', 'bank_transfer', 30, NULL, '2026-11-20', 897000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thu tiền đơn DH2611-00079', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 149, NULL),
(95, 1, NULL, 'PT2611-00017', 'receipt', 'cash', 29, NULL, '2026-11-20', 518000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00089', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 159, NULL),
(96, 1, NULL, 'PT2611-00018', 'receipt', 'cash', 29, NULL, '2026-11-20', 399000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00090', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 160, NULL),
(97, 1, NULL, 'BC2611-00042', 'receipt', 'ewallet', 30, NULL, '2026-11-20', 419000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2611-00095', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 165, NULL),
(98, 1, NULL, 'BC2611-00043', 'receipt', 'ewallet', 38, NULL, '2026-11-20', 720000.00, 'VND', 1.000000, 1, NULL, NULL, N'TikTok Shop thanh toán đơn DH2611-00096', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 166, NULL),
(99, 1, NULL, 'PT2611-00019', 'receipt', 'cash', 29, NULL, '2026-11-20', 468000.00, 'VND', 1.000000, NULL, 2, NULL, N'Thu tiền đơn DH2611-00099', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'customer', 169, NULL),
(100, 1, NULL, 'BC2609-00004', 'receipt', 'bank_transfer', NULL, NULL, '2026-09-30', 1040000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Nhanh chuyển tiền COD tuần 21/09 (1 vận đơn)', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-09-30T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(101, 1, NULL, 'BC2610-00011', 'receipt', 'bank_transfer', NULL, NULL, '2026-10-14', 5031100.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Nhanh chuyển tiền COD tuần 05/10 (3 vận đơn)', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-10-14T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(102, 1, NULL, 'BC2610-00018', 'receipt', 'bank_transfer', NULL, NULL, '2026-10-21', 1676000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Nhanh chuyển tiền COD tuần 12/10 (2 vận đơn)', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-10-21T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(103, 1, NULL, 'BC2610-00027', 'receipt', 'bank_transfer', NULL, NULL, '2026-10-28', 738000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Nhanh chuyển tiền COD tuần 19/10 (1 vận đơn)', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-10-28T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(104, 1, NULL, 'BC2611-00006', 'receipt', 'bank_transfer', NULL, NULL, '2026-11-04', 1215000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Nhanh chuyển tiền COD tuần 26/10 (3 vận đơn)', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-11-04T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(105, 1, NULL, 'BC2611-00016', 'receipt', 'bank_transfer', NULL, NULL, '2026-11-11', 279000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Nhanh chuyển tiền COD tuần 02/11 (1 vận đơn)', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-11-11T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(106, 1, NULL, 'BC2611-00032', 'receipt', 'bank_transfer', NULL, NULL, '2026-11-18', 999000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Nhanh chuyển tiền COD tuần 09/11 (2 vận đơn)', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-11-18T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(107, 1, NULL, 'BC2611-00044', 'receipt', 'bank_transfer', NULL, NULL, '2026-11-20', 1334200.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Nhanh chuyển tiền COD tuần 16/11 (1 vận đơn)', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(108, 1, NULL, 'BC2610-00004', 'receipt', 'bank_transfer', NULL, NULL, '2026-10-07', 2435000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Tiết Kiệm chuyển tiền COD tuần 28/09 (3 vận đơn)', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-10-07T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(109, 1, NULL, 'BC2610-00012', 'receipt', 'bank_transfer', NULL, NULL, '2026-10-14', 469000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Tiết Kiệm chuyển tiền COD tuần 05/10 (1 vận đơn)', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-10-14T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(110, 1, NULL, 'BC2610-00019', 'receipt', 'bank_transfer', NULL, NULL, '2026-10-21', 1248000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Tiết Kiệm chuyển tiền COD tuần 12/10 (2 vận đơn)', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-10-21T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(111, 1, NULL, 'BC2610-00028', 'receipt', 'bank_transfer', NULL, NULL, '2026-10-28', 1159000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Tiết Kiệm chuyển tiền COD tuần 19/10 (2 vận đơn)', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-10-28T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(112, 1, NULL, 'BC2611-00007', 'receipt', 'bank_transfer', NULL, NULL, '2026-11-04', 1674100.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Tiết Kiệm chuyển tiền COD tuần 26/10 (2 vận đơn)', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-11-04T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(113, 1, NULL, 'BC2611-00017', 'receipt', 'bank_transfer', NULL, NULL, '2026-11-11', 3313000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Tiết Kiệm chuyển tiền COD tuần 02/11 (4 vận đơn)', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-11-11T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(114, 1, NULL, 'BC2611-00033', 'receipt', 'bank_transfer', NULL, NULL, '2026-11-18', 2411000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Tiết Kiệm chuyển tiền COD tuần 09/11 (3 vận đơn)', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-11-18T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(115, 1, NULL, 'BC2611-00045', 'receipt', 'bank_transfer', NULL, NULL, '2026-11-20', 469000.00, 'VND', 1.000000, 1, NULL, NULL, N'Giao Hàng Tiết Kiệm chuyển tiền COD tuần 16/11 (1 vận đơn)', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'cod', NULL, NULL),
(116, 1, NULL, 'BN2609-00007', 'payment', 'bank_transfer', NULL, NULL, '2026-09-30', 28000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Nhanh tuần 21/09', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-09-30T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(117, 1, NULL, 'BN2610-00005', 'payment', 'bank_transfer', NULL, NULL, '2026-10-14', 84000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Nhanh tuần 05/10', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-10-14T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(118, 1, NULL, 'BN2610-00011', 'payment', 'bank_transfer', NULL, NULL, '2026-10-21', 56000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Nhanh tuần 12/10', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-10-21T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(119, 1, NULL, 'BN2610-00017', 'payment', 'bank_transfer', NULL, NULL, '2026-10-28', 28000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Nhanh tuần 19/10', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-10-28T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(120, 1, NULL, 'BN2611-00004', 'payment', 'bank_transfer', NULL, NULL, '2026-11-04', 84000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Nhanh tuần 26/10', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-11-04T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(121, 1, NULL, 'BN2611-00009', 'payment', 'bank_transfer', NULL, NULL, '2026-11-11', 28000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Nhanh tuần 02/11', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-11-11T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(122, 1, NULL, 'BN2611-00015', 'payment', 'bank_transfer', NULL, NULL, '2026-11-18', 56000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Nhanh tuần 09/11', N'Giao Hàng Nhanh', NULL, 'posted', NULL, 0.00, '2026-11-18T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(123, 1, NULL, 'BN2610-00002', 'payment', 'bank_transfer', NULL, NULL, '2026-10-07', 75000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Tiết Kiệm tuần 28/09', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-10-07T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(124, 1, NULL, 'BN2610-00006', 'payment', 'bank_transfer', NULL, NULL, '2026-10-14', 25000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Tiết Kiệm tuần 05/10', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-10-14T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(125, 1, NULL, 'BN2610-00012', 'payment', 'bank_transfer', NULL, NULL, '2026-10-21', 50000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Tiết Kiệm tuần 12/10', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-10-21T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(126, 1, NULL, 'BN2610-00018', 'payment', 'bank_transfer', NULL, NULL, '2026-10-28', 50000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Tiết Kiệm tuần 19/10', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-10-28T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(127, 1, NULL, 'BN2611-00005', 'payment', 'bank_transfer', NULL, NULL, '2026-11-04', 50000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Tiết Kiệm tuần 26/10', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-11-04T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(128, 1, NULL, 'BN2611-00010', 'payment', 'bank_transfer', NULL, NULL, '2026-11-11', 100000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Tiết Kiệm tuần 02/11', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-11-11T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(129, 1, NULL, 'BN2611-00016', 'payment', 'bank_transfer', NULL, NULL, '2026-11-18', 75000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển Giao Hàng Tiết Kiệm tuần 09/11', N'Giao Hàng Tiết Kiệm', NULL, 'posted', NULL, 0.00, '2026-11-18T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(130, 1, NULL, 'BN2609-00008', 'payment', 'bank_transfer', NULL, NULL, '2026-09-30', 22000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển J&T Express tuần 21/09', N'J&T Express', NULL, 'posted', NULL, 0.00, '2026-09-30T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(131, 1, NULL, 'BN2610-00007', 'payment', 'bank_transfer', NULL, NULL, '2026-10-14', 44000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển J&T Express tuần 05/10', N'J&T Express', NULL, 'posted', NULL, 0.00, '2026-10-14T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(132, 1, NULL, 'BN2610-00013', 'payment', 'bank_transfer', NULL, NULL, '2026-10-21', 22000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển J&T Express tuần 12/10', N'J&T Express', NULL, 'posted', NULL, 0.00, '2026-10-21T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(133, 1, NULL, 'BN2610-00019', 'payment', 'bank_transfer', NULL, NULL, '2026-10-28', 66000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển J&T Express tuần 19/10', N'J&T Express', NULL, 'posted', NULL, 0.00, '2026-10-28T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(134, 1, NULL, 'BN2611-00006', 'payment', 'bank_transfer', NULL, NULL, '2026-11-04', 66000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển J&T Express tuần 26/10', N'J&T Express', NULL, 'posted', NULL, 0.00, '2026-11-04T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(135, 1, NULL, 'BN2611-00011', 'payment', 'bank_transfer', NULL, NULL, '2026-11-11', 44000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển J&T Express tuần 02/11', N'J&T Express', NULL, 'posted', NULL, 0.00, '2026-11-11T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(136, 1, NULL, 'BN2611-00017', 'payment', 'bank_transfer', NULL, NULL, '2026-11-18', 110000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển J&T Express tuần 09/11', N'J&T Express', NULL, 'posted', NULL, 0.00, '2026-11-18T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(137, 1, NULL, 'BN2610-00003', 'payment', 'bank_transfer', NULL, NULL, '2026-10-07', 54000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển SPX Express (Shopee) tuần 28/09', N'SPX Express (Shopee)', NULL, 'posted', NULL, 0.00, '2026-10-07T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(138, 1, NULL, 'BN2610-00008', 'payment', 'bank_transfer', NULL, NULL, '2026-10-14', 36000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển SPX Express (Shopee) tuần 05/10', N'SPX Express (Shopee)', NULL, 'posted', NULL, 0.00, '2026-10-14T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(139, 1, NULL, 'BN2610-00014', 'payment', 'bank_transfer', NULL, NULL, '2026-10-21', 54000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển SPX Express (Shopee) tuần 12/10', N'SPX Express (Shopee)', NULL, 'posted', NULL, 0.00, '2026-10-21T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(140, 1, NULL, 'BN2610-00020', 'payment', 'bank_transfer', NULL, NULL, '2026-10-28', 36000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển SPX Express (Shopee) tuần 19/10', N'SPX Express (Shopee)', NULL, 'posted', NULL, 0.00, '2026-10-28T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(141, 1, NULL, 'BN2611-00007', 'payment', 'bank_transfer', NULL, NULL, '2026-11-04', 54000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển SPX Express (Shopee) tuần 26/10', N'SPX Express (Shopee)', NULL, 'posted', NULL, 0.00, '2026-11-04T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(142, 1, NULL, 'BN2611-00012', 'payment', 'bank_transfer', NULL, NULL, '2026-11-11', 72000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển SPX Express (Shopee) tuần 02/11', N'SPX Express (Shopee)', NULL, 'posted', NULL, 0.00, '2026-11-11T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(143, 1, NULL, 'BN2611-00018', 'payment', 'bank_transfer', NULL, NULL, '2026-11-18', 72000.00, 'VND', 1.000000, 1, NULL, NULL, N'Phí vận chuyển SPX Express (Shopee) tuần 09/11', N'SPX Express (Shopee)', NULL, 'posted', NULL, 0.00, '2026-11-18T03:00:00.0000000', 1, NULL, NULL, 0, 'shipping', NULL, NULL),
(144, 1, NULL, 'BN2609-00003', 'payment', 'bank_transfer', 25, NULL, '2026-09-28', 22977000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thanh toán đơn nhập DM2609-0001', NULL, NULL, 'posted', NULL, 0.00, '2026-09-28T03:00:00.0000000', 1, NULL, NULL, 0, 'supplier', NULL, 1),
(145, 1, NULL, 'BN2609-00004', 'payment', 'bank_transfer', 26, NULL, '2026-09-28', 62635000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thanh toán đơn nhập DM2609-0002', NULL, NULL, 'posted', NULL, 0.00, '2026-09-28T03:00:00.0000000', 1, NULL, NULL, 0, 'supplier', NULL, 2),
(146, 1, NULL, 'BN2609-00005', 'payment', 'bank_transfer', 27, NULL, '2026-09-29', 13670000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thanh toán đơn nhập DM2609-0003', NULL, NULL, 'posted', NULL, 0.00, '2026-09-29T03:00:00.0000000', 1, NULL, NULL, 0, 'supplier', NULL, 3),
(147, 1, NULL, 'BN2609-00006', 'payment', 'bank_transfer', 28, NULL, '2026-09-29', 67520000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thanh toán đơn nhập DM2609-0004', NULL, NULL, 'posted', NULL, 0.00, '2026-09-29T03:00:00.0000000', 1, NULL, NULL, 0, 'supplier', NULL, 4),
(148, 1, NULL, 'BN2611-00001', 'payment', 'bank_transfer', 25, NULL, '2026-11-01', 8692000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thanh toán đơn nhập DM2610-0001', NULL, NULL, 'posted', NULL, 0.00, '2026-11-01T03:00:00.0000000', 1, NULL, NULL, 0, 'supplier', NULL, 5),
(149, 1, NULL, 'BN2611-00002', 'payment', 'bank_transfer', 27, NULL, '2026-11-02', 4405000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thanh toán đơn nhập DM2610-0002', NULL, NULL, 'posted', NULL, 0.00, '2026-11-02T03:00:00.0000000', 1, NULL, NULL, 0, 'supplier', NULL, 6),
(150, 1, NULL, 'BN2611-00003', 'payment', 'bank_transfer', 28, NULL, '2026-11-02', 9465000.00, 'VND', 1.000000, 1, NULL, NULL, N'Thanh toán đơn nhập DM2610-0003', NULL, NULL, 'posted', NULL, 0.00, '2026-11-02T03:00:00.0000000', 1, NULL, NULL, 0, 'supplier', NULL, 7),
(151, 1, NULL, 'BN2611-00019', 'payment', 'bank_transfer', 26, NULL, '2026-11-20', 11628000.00, 'VND', 1.000000, 1, NULL, NULL, N'Đặt cọc đơn nhập DM2611-0001', NULL, NULL, 'posted', NULL, 0.00, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 'supplier', NULL, 8),
(152, 1, NULL, 'BN2609-00001', 'payment', 'bank_transfer', NULL, NULL, '2026-09-21', 15000000.00, 'VND', 1.000000, 1, NULL, NULL, N'Tiền thuê mặt bằng cửa hàng tháng 10', N'Chủ nhà - Ông Tuấn', NULL, 'posted', NULL, 0.00, '2026-09-21T03:00:00.0000000', 1, NULL, NULL, 0, 'rent', NULL, NULL),
(153, 1, NULL, 'BN2610-00015', 'payment', 'bank_transfer', NULL, NULL, '2026-10-21', 15000000.00, 'VND', 1.000000, 1, NULL, NULL, N'Tiền thuê mặt bằng cửa hàng tháng 11', N'Chủ nhà - Ông Tuấn', NULL, 'posted', NULL, 0.00, '2026-10-21T03:00:00.0000000', 1, NULL, NULL, 0, 'rent', NULL, NULL),
(154, 1, NULL, 'BN2610-00009', 'payment', 'bank_transfer', NULL, NULL, '2026-10-16', 24000000.00, 'VND', 1.000000, 1, NULL, NULL, N'Lương tháng 9 (trước khi dùng phần mềm)', NULL, NULL, 'posted', NULL, 0.00, '2026-10-16T03:00:00.0000000', 1, NULL, NULL, 0, 'salary', NULL, NULL),
(156, 1, NULL, 'PC2610-00001', 'payment', 'cash', NULL, NULL, '2026-10-11', 2350000.00, 'VND', 1.000000, NULL, 2, NULL, N'Tiền điện, nước, internet tháng 10', N'EVN, VNPT', NULL, 'posted', NULL, 0.00, '2026-10-11T03:00:00.0000000', 1, NULL, NULL, 0, 'utilities', NULL, NULL),
(157, 1, NULL, 'PC2611-00002', 'payment', 'cash', NULL, NULL, '2026-11-10', 2480000.00, 'VND', 1.000000, NULL, 2, NULL, N'Tiền điện, nước, internet tháng 11', N'EVN, VNPT', NULL, 'posted', NULL, 0.00, '2026-11-10T03:00:00.0000000', 1, NULL, NULL, 0, 'utilities', NULL, NULL),
(158, 1, NULL, 'PC2609-00001', 'payment', 'cash', NULL, NULL, '2026-09-26', 3200000.00, 'VND', 1.000000, NULL, 2, NULL, N'Mua móc treo, túi giấy, tem nhãn', N'Cửa hàng bao bì Minh Phát', NULL, 'posted', NULL, 0.00, '2026-09-26T03:00:00.0000000', 1, NULL, NULL, 0, 'other_expense', NULL, NULL),
(159, 1, NULL, 'PC2611-00001', 'payment', 'cash', NULL, NULL, '2026-11-02', 1500000.00, 'VND', 1.000000, NULL, 2, NULL, N'Mua băng keo, hộp carton đóng hàng', N'Cửa hàng bao bì Minh Phát', NULL, 'posted', NULL, 0.00, '2026-11-02T03:00:00.0000000', 1, NULL, NULL, 0, 'other_expense', NULL, NULL),
(160, 1, NULL, 'BN2611-00013', 'payment', 'card', NULL, NULL, '2026-11-13', 2200000.00, 'VND', 1.000000, 1, NULL, NULL, N'Chạy quảng cáo TikTok tuần 8', N'Meta / TikTok', NULL, 'posted', NULL, 0.00, '2026-11-13T03:00:00.0000000', 1, NULL, NULL, 0, 'marketing', NULL, NULL),
(161, 1, NULL, 'BN2611-00008', 'payment', 'card', NULL, NULL, '2026-11-06', 2600000.00, 'VND', 1.000000, 1, NULL, NULL, N'Chạy quảng cáo Facebook tuần 7', N'Meta / TikTok', NULL, 'posted', NULL, 0.00, '2026-11-06T03:00:00.0000000', 1, NULL, NULL, 0, 'marketing', NULL, NULL),
(162, 1, NULL, 'BN2610-00021', 'payment', 'card', NULL, NULL, '2026-10-30', 1800000.00, 'VND', 1.000000, 1, NULL, NULL, N'Chạy quảng cáo TikTok tuần 6', N'Meta / TikTok', NULL, 'posted', NULL, 0.00, '2026-10-30T03:00:00.0000000', 1, NULL, NULL, 0, 'marketing', NULL, NULL),
(163, 1, NULL, 'BN2610-00016', 'payment', 'card', NULL, NULL, '2026-10-23', 2200000.00, 'VND', 1.000000, 1, NULL, NULL, N'Chạy quảng cáo Facebook tuần 5', N'Meta / TikTok', NULL, 'posted', NULL, 0.00, '2026-10-23T03:00:00.0000000', 1, NULL, NULL, 0, 'marketing', NULL, NULL),
(164, 1, NULL, 'BN2610-00010', 'payment', 'card', NULL, NULL, '2026-10-16', 2600000.00, 'VND', 1.000000, 1, NULL, NULL, N'Chạy quảng cáo TikTok tuần 4', N'Meta / TikTok', NULL, 'posted', NULL, 0.00, '2026-10-16T03:00:00.0000000', 1, NULL, NULL, 0, 'marketing', NULL, NULL),
(165, 1, NULL, 'BN2610-00004', 'payment', 'card', NULL, NULL, '2026-10-09', 1800000.00, 'VND', 1.000000, 1, NULL, NULL, N'Chạy quảng cáo Facebook tuần 3', N'Meta / TikTok', NULL, 'posted', NULL, 0.00, '2026-10-09T03:00:00.0000000', 1, NULL, NULL, 0, 'marketing', NULL, NULL),
(166, 1, NULL, 'BN2610-00001', 'payment', 'card', NULL, NULL, '2026-10-02', 2200000.00, 'VND', 1.000000, 1, NULL, NULL, N'Chạy quảng cáo TikTok tuần 2', N'Meta / TikTok', NULL, 'posted', NULL, 0.00, '2026-10-02T03:00:00.0000000', 1, NULL, NULL, 0, 'marketing', NULL, NULL),
(167, 1, NULL, 'BN2609-00002', 'payment', 'card', NULL, NULL, '2026-09-25', 2600000.00, 'VND', 1.000000, 1, NULL, NULL, N'Chạy quảng cáo Facebook tuần 1', N'Meta / TikTok', NULL, 'posted', NULL, 0.00, '2026-09-25T03:00:00.0000000', 1, NULL, NULL, 0, 'marketing', NULL, NULL),
(168, 1, NULL, 'PC2611-00003', 'payment', 'cash', 29, NULL, '2026-11-18', 359000.00, 'VND', 1.000000, NULL, 2, NULL, N'Hoàn tiền trả hàng TH2611-00001 - đơn DH2611-00061', NULL, NULL, 'posted', NULL, 0.00, '2026-11-18T08:00:00.0000000', 1, NULL, NULL, 0, 'refund', 131, NULL),
(169, 1, NULL, 'PC2611-00004', 'payment', 'cash', 29, NULL, '2026-11-18', 690000.00, 'VND', 1.000000, NULL, 2, NULL, N'Hoàn tiền trả hàng TH2611-00002 - đơn DH2611-00060', NULL, NULL, 'posted', NULL, 0.00, '2026-11-18T07:00:00.0000000', 1, NULL, NULL, 0, 'refund', 130, NULL),
(170, 1, NULL, 'PC2611-00005', 'payment', 'cash', 29, NULL, '2026-11-16', 299000.00, 'VND', 1.000000, NULL, 2, NULL, N'Hoàn tiền trả hàng TH2611-00003 - đơn DH2611-00051', NULL, NULL, 'posted', NULL, 0.00, '2026-11-16T12:00:00.0000000', 1, NULL, NULL, 0, 'refund', 121, NULL),
(171, 1, NULL, 'BN2611-00020', 'payment', 'bank_transfer', NULL, NULL, '2026-11-05', 31208654.00, 'VND', 1.000000, 1, NULL, NULL, N'Chi lương tháng 10/2026 (4 nhân viên)', N'Nhân viên', NULL, 'posted', NULL, 0.00, '2026-11-05T00:00:00.0000000', 1, NULL, NULL, 0, 'salary', NULL, NULL)
;
SET IDENTITY_INSERT [acc].[Payments] OFF;
GO

-- chat.ChannelMembers (14 dòng)
INSERT INTO [chat].[ChannelMembers] ([ChannelId], [UserId], [MemberRole], [LastReadMessageId], [IsMuted], [JoinedAt]) VALUES
(1, 1, 'member', 17, 0, '2026-10-22T03:09:29.2720000'),
(1, 2, 'member', 16, 0, '2026-10-22T03:09:29.2720000'),
(1, 4, 'member', 17, 0, '2026-11-21T06:13:50.7940000'),
(1, 7, 'member', 16, 0, '2026-10-22T03:09:29.2720000'),
(2, 1, 'member', 14, 0, '2026-10-22T03:09:29.2720000'),
(2, 2, 'owner', 14, 0, '2026-10-22T03:09:29.2720000'),
(2, 3, 'member', 14, 0, '2026-10-22T03:09:29.2720000'),
(2, 4, 'member', 14, 0, '2026-10-22T03:09:29.2720000'),
(2, 6, 'member', 14, 0, '2026-10-22T03:09:29.2720000'),
(3, 1, 'member', 10, 0, '2026-10-22T03:09:29.2720000'),
(3, 5, 'member', 10, 0, '2026-10-22T03:09:29.2720000'),
(3, 7, 'owner', 10, 0, '2026-10-22T03:09:29.2720000'),
(4, 1, 'member', 15, 0, '2026-10-22T03:09:29.2720000'),
(4, 2, 'member', 15, 0, '2026-10-22T03:09:29.2720000')
;
GO

-- chat.Channels (4 dòng)
SET IDENTITY_INSERT [chat].[Channels] ON;
INSERT INTO [chat].[Channels] ([Id], [CompanyId], [Name], [ChannelType], [DepartmentId], [EntityName], [EntityId], [IsPrivate], [LastMessageAt], [CreatedAt], [CreatedBy], [IsArchived]) VALUES
(1, 1, N'Toàn công ty', 'company', NULL, NULL, NULL, 0, '2026-11-21T06:09:00.3660000', '2026-10-22T03:09:29.2720000', NULL, 0),
(2, 1, N'Cửa hàng Lê Lợi', 'group', NULL, NULL, NULL, 1, '2026-11-21T01:09:29.2720000', '2026-10-22T03:09:29.2720000', 2, 0),
(3, 1, N'Marketing & Online', 'group', NULL, NULL, NULL, 1, '2026-11-20T05:59:29.2720000', '2026-10-22T03:09:29.2720000', 7, 0),
(4, 1, NULL, 'direct', NULL, NULL, NULL, 1, '2026-11-21T02:24:29.2720000', '2026-11-16T03:09:29.2720000', 2, 0)
;
SET IDENTITY_INSERT [chat].[Channels] OFF;
GO

-- chat.MessageReactions (6 dòng)
INSERT INTO [chat].[MessageReactions] ([MessageId], [UserId], [Reaction], [CreatedAt]) VALUES
(1, 2, N'👍', '2026-11-19T02:54:29.2720000'),
(1, 7, N'👍', '2026-11-19T02:54:29.2720000'),
(3, 2, N'✅', '2026-11-19T03:34:29.2720000'),
(13, 1, N'🎉', '2026-11-20T22:14:29.2720000'),
(13, 3, N'👍', '2026-11-20T22:14:29.2720000'),
(13, 7, N'❤️', '2026-11-20T22:14:29.2720000')
;
GO

-- chat.Messages (17 dòng)
SET IDENTITY_INSERT [chat].[Messages] ON;
INSERT INTO [chat].[Messages] ([Id], [ChannelId], [SenderUserId], [Body], [ParentMessageId], [AttachmentId], [IsEdited], [EditedAt], [IsDeleted], [CreatedAt]) VALUES
(1, 1, 1, N'Chào cả nhà! Từ tuần này mình dùng chat nội bộ trên MyERP thay cho nhóm Zalo nhé, có gì trao đổi việc ở đây cho dễ tìm lại.', NULL, NULL, 0, NULL, 0, '2026-11-19T02:49:29.2720000'),
(2, 1, 2, N'Ok anh, em đã nhắc các bạn ở cửa hàng rồi ạ.', NULL, NULL, 0, NULL, 0, '2026-11-19T03:09:29.2720000'),
(3, 1, 7, N'Marketing đã tạo mã giảm giá BLACKFRIDAY, áp dụng từ thứ 6 tuần này. Mọi người tư vấn khách giúp em nhé 🙌', NULL, NULL, 0, NULL, 0, '2026-11-19T03:29:29.2720000'),
(4, 2, 2, N'Sáng mai 8h họp nhanh ca sáng 10 phút nha các em.', NULL, NULL, 0, NULL, 0, '2026-11-20T02:09:29.2720000'),
(5, 2, 3, N'Dạ chị.', NULL, NULL, 0, NULL, 0, '2026-11-20T02:19:29.2720000'),
(6, 2, 6, N'Hàng áo khoác bomber về chiều nay, ca chiều ai rảnh phụ anh kiểm hàng với.', NULL, NULL, 0, NULL, 0, '2026-11-20T02:59:29.2720000'),
(7, 2, 4, N'Em phụ anh Tùng được ạ.', NULL, NULL, 0, NULL, 0, '2026-11-20T03:09:29.2720000'),
(8, 3, 7, N'Vy ơi, lookbook Tết em chọn outfit tới đâu rồi?', NULL, NULL, 0, NULL, 0, '2026-11-20T05:29:29.2720000'),
(9, 3, 5, N'Em chọn xong đồ nam rồi chị, đồ nữ chiều nay em gửi danh sách ạ.', NULL, NULL, 0, NULL, 0, '2026-11-20T05:49:29.2720000'),
(10, 3, 7, N'Ok em, nhớ chọn thêm giày sneaker trắng phối cùng nhé, đang bán chạy.', NULL, NULL, 0, NULL, 0, '2026-11-20T05:59:29.2720000'),
(11, 4, 2, N'Anh ơi, bản thiết kế standee khai trương Q7 Mai gửi rồi, anh xem giúp em trong hôm nay được không ạ?', NULL, NULL, 0, NULL, 0, '2026-11-20T17:09:29.2720000'),
(12, 4, 1, N'Ok em, chiều anh xem rồi duyệt trên app Dự án luôn.', NULL, NULL, 0, NULL, 0, '2026-11-20T17:19:29.2720000'),
(13, 1, 2, N'Doanh thu hôm qua cửa hàng Lê Lợi vượt chỉ tiêu 15% 🎉 Cảm ơn cả team!', NULL, NULL, 0, NULL, 0, '2026-11-20T22:09:29.2720000'),
(14, 2, 3, N'Chị ơi khách hỏi áo polo pique size XL màu navy còn không ạ? Em check kho thấy còn 2 cái.', NULL, NULL, 0, NULL, 0, '2026-11-21T01:09:29.2720000'),
(15, 4, 2, N'À anh ơi, hợp đồng thuê mặt bằng Lê Lợi còn khoảng 3 tuần là hết hạn, mình gia hạn luôn nha anh?', NULL, NULL, 0, NULL, 0, '2026-11-21T02:24:29.2720000'),
(16, 1, 7, N'Nhắc mọi người: tối nay 20h livestream TikTok, ai rảnh vào thả tim giúp em với ạ ❤️', NULL, NULL, 0, NULL, 0, '2026-11-21T02:39:29.2720000'),
(17, 1, 1, N'hello mọi người', NULL, NULL, 0, NULL, 0, '2026-11-21T06:09:00.3660000')
;
SET IDENTITY_INSERT [chat].[Messages] OFF;
GO

-- core.ApprovalRules (3 dòng)
SET IDENTITY_INSERT [core].[ApprovalRules] ON;
INSERT INTO [core].[ApprovalRules] ([Id], [CompanyId], [EntityName], [ApprovalLevel], [MinAmount], [ApproverRoleId], [ApproverUserId], [IsDepartmentManager], [IsActive]) VALUES
(1, 1, 'sales.Quotations', 1, 100000000.00, 4, NULL, 0, 1),
(2, 1, 'sales.Quotations', 2, 500000000.00, 2, NULL, 0, 1),
(3, 1, 'pur.PurchaseOrders', 1, 50000000.00, 2, NULL, 0, 1)
;
SET IDENTITY_INSERT [core].[ApprovalRules] OFF;
GO

-- core.Apps (17 dòng)
SET IDENTITY_INSERT [core].[Apps] ON;
INSERT INTO [core].[Apps] ([Id], [Code], [Name], [Icon], [Color], [Route], [SortOrder], [IsEnabled]) VALUES
(1, 'crm', N'CRM', 'heart-handshake', '#D4537E', '/crm', 10, 1),
(2, 'quotation', N'Báo giá', 'file-dollar', '#D85A30', '/quotations', 20, 1),
(3, 'order', N'Đơn hàng', 'shopping-cart', '#378ADD', '/orders', 30, 1),
(4, 'inventory', N'Kho', 'building-warehouse', '#BA7517', '/inventory', 40, 1),
(5, 'logistics', N'Vận chuyển', 'truck-delivery', '#0F6E56', '/logistics', 50, 1),
(6, 'purchasing', N'Mua hàng', 'basket-down', '#639922', '/purchasing', 60, 1),
(7, 'accounting', N'Kế toán', 'calculator', '#534AB7', '/accounting', 70, 1),
(8, 'hr', N'Nhân sự', 'users', '#7F77DD', '/hr', 80, 1),
(9, 'marketing', N'Marketing', 'speakerphone', '#D85A30', '/marketing', 90, 1),
(10, 'website', N'Website', 'world', '#185FA5', '/website', 100, 1),
(11, 'support', N'CSKH', 'headset', '#1D9E75', '/support', 110, 1),
(12, 'project', N'Dự án, việc', 'checklist', '#993556', '/projects', 120, 1),
(13, 'document', N'Tài liệu', 'folder', '#888780', '/documents', 130, 1),
(14, 'chat', N'Chat nội bộ', 'messages', '#378ADD', '/chat', 140, 1),
(15, 'report', N'Báo cáo', 'chart-pie', '#0F6E56', '/reports', 150, 1),
(16, 'users', N'Người dùng', 'user-shield', '#5F5E5A', '/users', 160, 1),
(17, 'settings', N'Cài đặt', 'settings', '#444441', '/settings', 170, 1)
;
SET IDENTITY_INSERT [core].[Apps] OFF;
GO

-- core.Branches (1 dòng)
SET IDENTITY_INSERT [core].[Branches] ON;
INSERT INTO [core].[Branches] ([Id], [CompanyId], [Code], [Name], [Address], [Phone], [IsHeadOffice], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'HO', N'Trụ sở chính', NULL, NULL, 1, 1, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0)
;
SET IDENTITY_INSERT [core].[Branches] OFF;
GO

-- core.Companies (1 dòng)
SET IDENTITY_INSERT [core].[Companies] ON;
INSERT INTO [core].[Companies] ([Id], [Code], [Name], [ShortName], [TaxCode], [Address], [Phone], [Email], [Website], [LogoUrl], [LegalRepresentative], [CurrencyCode], [AccountingRegime], [FiscalYearStartMonth], [TimeZone], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 'ABC', N'Công ty TNHH Thời trang MyStyle', N'MyStyle Fashion', '0109876543', N'125 Nguyễn Trãi, Thanh Xuân, Hà Nội', '0901234567', 'shop@mystyle.vn', 'facebook.com/mystyle.vn', NULL, N'Nguyễn Thu Hà', 'VND', 'TT200', 1, 'SE Asia Standard Time', 1, '2026-11-19T02:33:24.3540000', NULL, NULL, NULL, 0)
;
SET IDENTITY_INSERT [core].[Companies] OFF;
GO

-- core.CompanyApps (17 dòng)
INSERT INTO [core].[CompanyApps] ([CompanyId], [AppId], [IsEnabled], [EnabledAt]) VALUES
(1, 1, 1, '2026-11-19T02:33:24.3560000'),
(1, 2, 1, '2026-11-19T02:33:24.3560000'),
(1, 3, 1, '2026-11-19T02:33:24.3560000'),
(1, 4, 1, '2026-11-19T02:33:24.3560000'),
(1, 5, 1, '2026-11-19T02:33:24.3560000'),
(1, 6, 1, '2026-11-19T02:33:24.3560000'),
(1, 7, 1, '2026-11-19T02:33:24.3560000'),
(1, 8, 1, '2026-11-19T02:33:24.3560000'),
(1, 9, 1, '2026-11-19T02:33:24.3560000'),
(1, 10, 1, '2026-11-19T02:33:24.3560000'),
(1, 11, 1, '2026-11-19T02:33:24.3560000'),
(1, 12, 1, '2026-11-19T02:33:24.3560000'),
(1, 13, 1, '2026-11-19T02:33:24.3560000'),
(1, 14, 1, '2026-11-19T02:33:24.3560000'),
(1, 15, 1, '2026-11-19T02:33:24.3560000'),
(1, 16, 1, '2026-11-19T02:33:24.3560000'),
(1, 17, 1, '2026-11-19T02:33:24.3560000')
;
GO

-- core.Departments (10 dòng)
SET IDENTITY_INSERT [core].[Departments] ON;
INSERT INTO [core].[Departments] ([Id], [CompanyId], [BranchId], [ParentId], [Code], [Name], [ManagerUserId], [Path], [SortOrder], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 1, NULL, 'BGD', N'Ban giám đốc', NULL, '/1/', 1, 1, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(2, 1, 1, NULL, 'KD', N'Phòng Kinh doanh', NULL, '/2/', 2, 1, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(3, 1, 1, NULL, 'MKT', N'Phòng Marketing', NULL, '/3/', 3, 1, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(4, 1, 1, NULL, 'KT', N'Phòng Kế toán', NULL, '/4/', 4, 1, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(5, 1, 1, NULL, 'KHO', N'Kho vận', NULL, '/5/', 5, 1, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(6, 1, 1, NULL, 'MH', N'Phòng Mua hàng', NULL, '/6/', 6, 1, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(7, 1, 1, NULL, 'NS', N'Phòng Nhân sự', NULL, '/7/', 7, 1, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(8, 1, 1, NULL, 'CSKH', N'Chăm sóc khách hàng', NULL, '/8/', 8, 1, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(9, 1, 1, NULL, 'IT', N'Phòng IT', NULL, '/9/', 9, 1, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(10, 1, NULL, NULL, 'CH', N'Cửa hàng', NULL, NULL, 15, 1, '2026-11-21T00:55:41.0740000', NULL, NULL, NULL, 0)
;
SET IDENTITY_INSERT [core].[Departments] OFF;
GO

-- core.Permissions (110 dòng)
SET IDENTITY_INSERT [core].[Permissions] ON;
INSERT INTO [core].[Permissions] ([Id], [AppId], [Code], [Name], [Description]) VALUES
(1, 1, 'crm.view', N'Xem - CRM', NULL),
(2, 1, 'crm.create', N'Tạo - CRM', NULL),
(3, 1, 'crm.edit', N'Sửa - CRM', NULL),
(4, 1, 'crm.delete', N'Xóa - CRM', NULL),
(5, 1, 'crm.approve', N'Duyệt - CRM', NULL),
(6, 1, 'crm.export', N'Xuất dữ liệu - CRM', NULL),
(7, 2, 'quotation.view', N'Xem - Báo giá', NULL),
(8, 2, 'quotation.create', N'Tạo - Báo giá', NULL),
(9, 2, 'quotation.edit', N'Sửa - Báo giá', NULL),
(10, 2, 'quotation.delete', N'Xóa - Báo giá', NULL),
(11, 2, 'quotation.approve', N'Duyệt - Báo giá', NULL),
(12, 2, 'quotation.export', N'Xuất dữ liệu - Báo giá', NULL),
(13, 3, 'order.view', N'Xem - Đơn hàng', NULL),
(14, 3, 'order.create', N'Tạo - Đơn hàng', NULL),
(15, 3, 'order.edit', N'Sửa - Đơn hàng', NULL),
(16, 3, 'order.delete', N'Xóa - Đơn hàng', NULL),
(17, 3, 'order.approve', N'Duyệt - Đơn hàng', NULL),
(18, 3, 'order.export', N'Xuất dữ liệu - Đơn hàng', NULL),
(19, 4, 'inventory.view', N'Xem - Kho', NULL),
(20, 4, 'inventory.create', N'Tạo - Kho', NULL),
(21, 4, 'inventory.edit', N'Sửa - Kho', NULL),
(22, 4, 'inventory.delete', N'Xóa - Kho', NULL),
(23, 4, 'inventory.approve', N'Duyệt - Kho', NULL),
(24, 4, 'inventory.export', N'Xuất dữ liệu - Kho', NULL),
(25, 5, 'logistics.view', N'Xem - Vận chuyển', NULL),
(26, 5, 'logistics.create', N'Tạo - Vận chuyển', NULL),
(27, 5, 'logistics.edit', N'Sửa - Vận chuyển', NULL),
(28, 5, 'logistics.delete', N'Xóa - Vận chuyển', NULL),
(29, 5, 'logistics.approve', N'Duyệt - Vận chuyển', NULL),
(30, 5, 'logistics.export', N'Xuất dữ liệu - Vận chuyển', NULL),
(31, 6, 'purchasing.view', N'Xem - Mua hàng', NULL),
(32, 6, 'purchasing.create', N'Tạo - Mua hàng', NULL),
(33, 6, 'purchasing.edit', N'Sửa - Mua hàng', NULL),
(34, 6, 'purchasing.delete', N'Xóa - Mua hàng', NULL),
(35, 6, 'purchasing.approve', N'Duyệt - Mua hàng', NULL),
(36, 6, 'purchasing.export', N'Xuất dữ liệu - Mua hàng', NULL),
(37, 7, 'accounting.view', N'Xem - Kế toán', NULL),
(38, 7, 'accounting.create', N'Tạo - Kế toán', NULL),
(39, 7, 'accounting.edit', N'Sửa - Kế toán', NULL),
(40, 7, 'accounting.delete', N'Xóa - Kế toán', NULL),
(41, 7, 'accounting.approve', N'Duyệt - Kế toán', NULL),
(42, 7, 'accounting.export', N'Xuất dữ liệu - Kế toán', NULL),
(43, 8, 'hr.view', N'Xem - Nhân sự', NULL),
(44, 8, 'hr.create', N'Tạo - Nhân sự', NULL),
(45, 8, 'hr.edit', N'Sửa - Nhân sự', NULL),
(46, 8, 'hr.delete', N'Xóa - Nhân sự', NULL),
(47, 8, 'hr.approve', N'Duyệt - Nhân sự', NULL),
(48, 8, 'hr.export', N'Xuất dữ liệu - Nhân sự', NULL),
(49, 9, 'marketing.view', N'Xem - Marketing', NULL),
(50, 9, 'marketing.create', N'Tạo - Marketing', NULL),
(51, 9, 'marketing.edit', N'Sửa - Marketing', NULL),
(52, 9, 'marketing.delete', N'Xóa - Marketing', NULL),
(53, 9, 'marketing.approve', N'Duyệt - Marketing', NULL),
(54, 9, 'marketing.export', N'Xuất dữ liệu - Marketing', NULL),
(55, 10, 'website.view', N'Xem - Website', NULL),
(56, 10, 'website.create', N'Tạo - Website', NULL),
(57, 10, 'website.edit', N'Sửa - Website', NULL),
(58, 10, 'website.delete', N'Xóa - Website', NULL),
(59, 10, 'website.approve', N'Duyệt - Website', NULL),
(60, 10, 'website.export', N'Xuất dữ liệu - Website', NULL),
(61, 11, 'support.view', N'Xem - CSKH', NULL),
(62, 11, 'support.create', N'Tạo - CSKH', NULL),
(63, 11, 'support.edit', N'Sửa - CSKH', NULL),
(64, 11, 'support.delete', N'Xóa - CSKH', NULL),
(65, 11, 'support.approve', N'Duyệt - CSKH', NULL),
(66, 11, 'support.export', N'Xuất dữ liệu - CSKH', NULL),
(67, 12, 'project.view', N'Xem - Dự án, việc', NULL),
(68, 12, 'project.create', N'Tạo - Dự án, việc', NULL),
(69, 12, 'project.edit', N'Sửa - Dự án, việc', NULL),
(70, 12, 'project.delete', N'Xóa - Dự án, việc', NULL),
(71, 12, 'project.approve', N'Duyệt - Dự án, việc', NULL),
(72, 12, 'project.export', N'Xuất dữ liệu - Dự án, việc', NULL),
(73, 13, 'document.view', N'Xem - Tài liệu', NULL),
(74, 13, 'document.create', N'Tạo - Tài liệu', NULL),
(75, 13, 'document.edit', N'Sửa - Tài liệu', NULL),
(76, 13, 'document.delete', N'Xóa - Tài liệu', NULL),
(77, 13, 'document.approve', N'Duyệt - Tài liệu', NULL),
(78, 13, 'document.export', N'Xuất dữ liệu - Tài liệu', NULL),
(79, 14, 'chat.view', N'Xem - Chat nội bộ', NULL),
(80, 14, 'chat.create', N'Tạo - Chat nội bộ', NULL),
(81, 14, 'chat.edit', N'Sửa - Chat nội bộ', NULL),
(82, 14, 'chat.delete', N'Xóa - Chat nội bộ', NULL),
(83, 14, 'chat.approve', N'Duyệt - Chat nội bộ', NULL),
(84, 14, 'chat.export', N'Xuất dữ liệu - Chat nội bộ', NULL),
(85, 15, 'report.view', N'Xem - Báo cáo', NULL),
(86, 15, 'report.create', N'Tạo - Báo cáo', NULL),
(87, 15, 'report.edit', N'Sửa - Báo cáo', NULL),
(88, 15, 'report.delete', N'Xóa - Báo cáo', NULL),
(89, 15, 'report.approve', N'Duyệt - Báo cáo', NULL),
(90, 15, 'report.export', N'Xuất dữ liệu - Báo cáo', NULL),
(91, 16, 'users.view', N'Xem - Người dùng', NULL),
(92, 16, 'users.create', N'Tạo - Người dùng', NULL),
(93, 16, 'users.edit', N'Sửa - Người dùng', NULL),
(94, 16, 'users.delete', N'Xóa - Người dùng', NULL),
(95, 16, 'users.approve', N'Duyệt - Người dùng', NULL),
(96, 16, 'users.export', N'Xuất dữ liệu - Người dùng', NULL),
(97, 17, 'settings.view', N'Xem - Cài đặt', NULL),
(98, 17, 'settings.create', N'Tạo - Cài đặt', NULL),
(99, 17, 'settings.edit', N'Sửa - Cài đặt', NULL),
(100, 17, 'settings.delete', N'Xóa - Cài đặt', NULL),
(101, 17, 'settings.approve', N'Duyệt - Cài đặt', NULL),
(102, 17, 'settings.export', N'Xuất dữ liệu - Cài đặt', NULL),
(103, 7, 'accounting.entry.post', N'Ghi sổ bút toán', NULL),
(104, 7, 'accounting.period.close', N'Khóa sổ kỳ kế toán', NULL),
(105, 7, 'accounting.einvoice.issue', N'Phát hành hóa đơn điện tử', NULL),
(106, 3, 'order.price.override', N'Sửa giá bán dưới bảng giá', NULL),
(107, 3, 'order.credit.override', N'Bán vượt hạn mức công nợ', NULL),
(108, 4, 'inventory.negative.allow', N'Xuất kho âm', NULL),
(109, 8, 'hr.payroll.view', N'Xem bảng lương', NULL),
(110, 16, 'users.impersonate', N'Đăng nhập thay người dùng', NULL)
;
SET IDENTITY_INSERT [core].[Permissions] OFF;
GO

-- core.RolePermissions (327 dòng)
INSERT INTO [core].[RolePermissions] ([RoleId], [PermissionId], [DataScope]) VALUES
(1, 1, 'all'),
(1, 2, 'all'),
(1, 3, 'all'),
(1, 4, 'all'),
(1, 5, 'all'),
(1, 6, 'all'),
(1, 7, 'all'),
(1, 8, 'all'),
(1, 9, 'all'),
(1, 10, 'all'),
(1, 11, 'all'),
(1, 12, 'all'),
(1, 13, 'all'),
(1, 14, 'all'),
(1, 15, 'all'),
(1, 16, 'all'),
(1, 17, 'all'),
(1, 18, 'all'),
(1, 19, 'all'),
(1, 20, 'all'),
(1, 21, 'all'),
(1, 22, 'all'),
(1, 23, 'all'),
(1, 24, 'all'),
(1, 25, 'all'),
(1, 26, 'all'),
(1, 27, 'all'),
(1, 28, 'all'),
(1, 29, 'all'),
(1, 30, 'all'),
(1, 31, 'all'),
(1, 32, 'all'),
(1, 33, 'all'),
(1, 34, 'all'),
(1, 35, 'all'),
(1, 36, 'all'),
(1, 37, 'all'),
(1, 38, 'all'),
(1, 39, 'all'),
(1, 40, 'all'),
(1, 41, 'all'),
(1, 42, 'all'),
(1, 43, 'all'),
(1, 44, 'all'),
(1, 45, 'all'),
(1, 46, 'all'),
(1, 47, 'all'),
(1, 48, 'all'),
(1, 49, 'all'),
(1, 50, 'all'),
(1, 51, 'all'),
(1, 52, 'all'),
(1, 53, 'all'),
(1, 54, 'all'),
(1, 55, 'all'),
(1, 56, 'all'),
(1, 57, 'all'),
(1, 58, 'all'),
(1, 59, 'all'),
(1, 60, 'all'),
(1, 61, 'all'),
(1, 62, 'all'),
(1, 63, 'all'),
(1, 64, 'all'),
(1, 65, 'all'),
(1, 66, 'all'),
(1, 67, 'all'),
(1, 68, 'all'),
(1, 69, 'all'),
(1, 70, 'all'),
(1, 71, 'all'),
(1, 72, 'all'),
(1, 73, 'all'),
(1, 74, 'all'),
(1, 75, 'all'),
(1, 76, 'all'),
(1, 77, 'all'),
(1, 78, 'all'),
(1, 79, 'all'),
(1, 80, 'all'),
(1, 81, 'all'),
(1, 82, 'all'),
(1, 83, 'all'),
(1, 84, 'all'),
(1, 85, 'all'),
(1, 86, 'all'),
(1, 87, 'all'),
(1, 88, 'all'),
(1, 89, 'all'),
(1, 90, 'all'),
(1, 91, 'all'),
(1, 92, 'all'),
(1, 93, 'all'),
(1, 94, 'all'),
(1, 95, 'all'),
(1, 96, 'all'),
(1, 97, 'all'),
(1, 98, 'all'),
(1, 99, 'all'),
(1, 100, 'all'),
(1, 101, 'all'),
(1, 102, 'all'),
(1, 103, 'all'),
(1, 104, 'all'),
(1, 105, 'all'),
(1, 106, 'all'),
(1, 107, 'all'),
(1, 108, 'all'),
(1, 109, 'all'),
(1, 110, 'all'),
(2, 1, 'company'),
(2, 5, 'company'),
(2, 6, 'company'),
(2, 7, 'company'),
(2, 11, 'company'),
(2, 12, 'company'),
(2, 13, 'company'),
(2, 17, 'company'),
(2, 18, 'company'),
(2, 19, 'company'),
(2, 23, 'company'),
(2, 24, 'company'),
(2, 25, 'company'),
(2, 29, 'company'),
(2, 30, 'company'),
(2, 31, 'company'),
(2, 35, 'company'),
(2, 36, 'company'),
(2, 37, 'company'),
(2, 41, 'company'),
(2, 42, 'company'),
(2, 43, 'company'),
(2, 47, 'company'),
(2, 48, 'company'),
(2, 49, 'company'),
(2, 53, 'company'),
(2, 54, 'company'),
(2, 55, 'company'),
(2, 59, 'company'),
(2, 60, 'company'),
(2, 61, 'company'),
(2, 65, 'company'),
(2, 66, 'company'),
(2, 67, 'company'),
(2, 68, 'own'),
(2, 69, 'own'),
(2, 71, 'company'),
(2, 72, 'company'),
(2, 73, 'company'),
(2, 74, 'own'),
(2, 75, 'own'),
(2, 77, 'company'),
(2, 78, 'company'),
(2, 79, 'company'),
(2, 80, 'own'),
(2, 81, 'own'),
(2, 83, 'company'),
(2, 84, 'company'),
(2, 85, 'company'),
(2, 89, 'company'),
(2, 90, 'company'),
(2, 91, 'company'),
(2, 95, 'company'),
(2, 96, 'company'),
(2, 97, 'company'),
(2, 101, 'company'),
(2, 102, 'company'),
(3, 1, 'own'),
(3, 2, 'own'),
(3, 3, 'own'),
(3, 6, 'own'),
(3, 7, 'own'),
(3, 8, 'own'),
(3, 9, 'own'),
(3, 13, 'own'),
(3, 14, 'own'),
(3, 15, 'own'),
(3, 67, 'own'),
(3, 68, 'own'),
(3, 69, 'own'),
(3, 73, 'own'),
(3, 74, 'own'),
(3, 75, 'own'),
(3, 79, 'own'),
(3, 80, 'own'),
(3, 81, 'own'),
(4, 1, 'department'),
(4, 2, 'department'),
(4, 3, 'department'),
(4, 4, 'department'),
(4, 5, 'department'),
(4, 6, 'department'),
(4, 7, 'department'),
(4, 8, 'department'),
(4, 9, 'department'),
(4, 10, 'department'),
(4, 11, 'department'),
(4, 12, 'department'),
(4, 13, 'department'),
(4, 14, 'department'),
(4, 15, 'department'),
(4, 16, 'department'),
(4, 17, 'department'),
(4, 18, 'department'),
(4, 67, 'own'),
(4, 68, 'own'),
(4, 69, 'own'),
(4, 73, 'own'),
(4, 74, 'own'),
(4, 75, 'own'),
(4, 79, 'own'),
(4, 80, 'own'),
(4, 81, 'own'),
(4, 85, 'department'),
(4, 90, 'department'),
(5, 13, 'company'),
(5, 25, 'company'),
(5, 31, 'company'),
(5, 37, 'company'),
(5, 38, 'company'),
(5, 39, 'company'),
(5, 40, 'company'),
(5, 41, 'company'),
(5, 42, 'company'),
(5, 67, 'own'),
(5, 68, 'own'),
(5, 69, 'own'),
(5, 73, 'own'),
(5, 74, 'own'),
(5, 75, 'own'),
(5, 79, 'own'),
(5, 80, 'own'),
(5, 81, 'own'),
(5, 85, 'company'),
(5, 90, 'company'),
(6, 13, 'company'),
(6, 19, 'company'),
(6, 20, 'company'),
(6, 21, 'company'),
(6, 23, 'company'),
(6, 24, 'company'),
(6, 25, 'company'),
(6, 26, 'company'),
(6, 27, 'company'),
(6, 30, 'company'),
(6, 31, 'company'),
(6, 67, 'own'),
(6, 68, 'own'),
(6, 69, 'own'),
(6, 73, 'own'),
(6, 74, 'own'),
(6, 75, 'own'),
(6, 79, 'own'),
(6, 80, 'own'),
(6, 81, 'own'),
(7, 19, 'company'),
(7, 31, 'company'),
(7, 32, 'company'),
(7, 33, 'company'),
(7, 36, 'company'),
(7, 67, 'own'),
(7, 68, 'own'),
(7, 69, 'own'),
(7, 73, 'own'),
(7, 74, 'own'),
(7, 75, 'own'),
(7, 79, 'own'),
(7, 80, 'own'),
(7, 81, 'own'),
(8, 43, 'company'),
(8, 44, 'company'),
(8, 45, 'company'),
(8, 46, 'company'),
(8, 47, 'company'),
(8, 48, 'company'),
(8, 67, 'own'),
(8, 68, 'own'),
(8, 69, 'own'),
(8, 73, 'own'),
(8, 74, 'own'),
(8, 75, 'own'),
(8, 79, 'own'),
(8, 80, 'own'),
(8, 81, 'own'),
(9, 1, 'company'),
(9, 49, 'company'),
(9, 50, 'company'),
(9, 51, 'company'),
(9, 52, 'company'),
(9, 54, 'company'),
(9, 55, 'company'),
(9, 56, 'company'),
(9, 57, 'company'),
(9, 58, 'company'),
(9, 67, 'own'),
(9, 68, 'own'),
(9, 69, 'own'),
(9, 73, 'own'),
(9, 74, 'own'),
(9, 75, 'own'),
(9, 79, 'own'),
(9, 80, 'own'),
(9, 81, 'own'),
(10, 1, 'company'),
(10, 13, 'company'),
(10, 61, 'department'),
(10, 62, 'department'),
(10, 63, 'department'),
(10, 66, 'department'),
(10, 67, 'own'),
(10, 68, 'own'),
(10, 69, 'own'),
(10, 73, 'own'),
(10, 74, 'own'),
(10, 75, 'own'),
(10, 79, 'own'),
(10, 80, 'own'),
(10, 81, 'own'),
(11, 67, 'own'),
(11, 68, 'own'),
(11, 69, 'own'),
(11, 73, 'own'),
(11, 74, 'own'),
(11, 75, 'own'),
(11, 79, 'own'),
(11, 80, 'own'),
(11, 81, 'own')
;
GO

-- core.Roles (11 dòng)
SET IDENTITY_INSERT [core].[Roles] ON;
INSERT INTO [core].[Roles] ([Id], [CompanyId], [Code], [Name], [NormalizedName], [Description], [IsSystem], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, NULL, 'admin', N'Quản trị hệ thống', N'QUẢN TRỊ HỆ THỐNG', NULL, 1, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(2, 1, 'director', N'Ban giám đốc', N'BAN GIÁM ĐỐC', NULL, 0, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(3, 1, 'sales', N'Nhân viên kinh doanh', N'NHÂN VIÊN KINH DOANH', NULL, 0, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(4, 1, 'sales_lead', N'Trưởng phòng kinh doanh', N'TRƯỞNG PHÒNG KINH DOANH', NULL, 0, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(5, 1, 'accountant', N'Kế toán', N'KẾ TOÁN', NULL, 0, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(6, 1, 'warehouse', N'Thủ kho', N'THỦ KHO', NULL, 0, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(7, 1, 'purchaser', N'Nhân viên mua hàng', N'NHÂN VIÊN MUA HÀNG', NULL, 0, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(8, 1, 'hr', N'Nhân sự', N'NHÂN SỰ', NULL, 0, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(9, 1, 'marketing', N'Marketing', N'MARKETING', NULL, 0, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(10, 1, 'support', N'Chăm sóc khách hàng', N'CHĂM SÓC KHÁCH HÀNG', NULL, 0, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0),
(11, 1, 'employee', N'Nhân viên', N'NHÂN VIÊN', NULL, 0, '2026-11-19T02:33:24.3560000', NULL, NULL, NULL, 0)
;
SET IDENTITY_INSERT [core].[Roles] OFF;
GO

-- core.SequenceCounters (42 dòng)
INSERT INTO [core].[SequenceCounters] ([SequenceId], [Period], [NextNumber]) VALUES
(1, 'ALL', 21),
(3, 'ALL', 7),
(4, '202610', 8),
(4, '202611', 9),
(5, '202610', 8),
(5, '202611', 4),
(6, '202610', 4),
(6, '202611', 6),
(7, '202609', 11),
(7, '202610', 62),
(7, '202611', 102),
(8, '202611', 4),
(10, '202609', 5),
(10, '202610', 4),
(10, '202611', 3),
(11, '202609', 5),
(11, '202610', 4),
(11, '202611', 3),
(12, '202609', 11),
(12, '202610', 55),
(12, '202611', 87),
(16, '202609', 7),
(16, '202610', 38),
(16, '202611', 58),
(20, '202609', 5),
(20, '202610', 13),
(20, '202611', 20),
(21, '202609', 2),
(21, '202610', 2),
(21, '202611', 6),
(22, '202609', 5),
(22, '202610', 32),
(22, '202611', 46),
(23, '202609', 9),
(23, '202610', 22),
(23, '202611', 21),
(25, '202610', 2),
(25, '202611', 10),
(27, '2026', 5),
(28, 'ALL', 27),
(29, '2026', 5),
(31, 'ALL', 5)
;
GO

-- core.Sequences (31 dòng)
SET IDENTITY_INSERT [core].[Sequences] ON;
INSERT INTO [core].[Sequences] ([Id], [CompanyId], [Code], [Prefix], [DatePattern], [Padding], [ResetPolicy]) VALUES
(1, 1, 'PARTNER', 'KH', NULL, 6, 'never'),
(2, 1, 'PRODUCT', 'SP', NULL, 6, 'never'),
(3, 1, 'EMPLOYEE', 'NV', NULL, 5, 'never'),
(4, 1, 'LEAD', 'LD', 'yyMM', 5, 'monthly'),
(5, 1, 'OPPORTUNITY', 'CH', 'yyMM', 5, 'monthly'),
(6, 1, 'QUOTATION', 'BG', 'yyMM', 5, 'monthly'),
(7, 1, 'SALES_ORDER', 'DH', 'yyMM', 5, 'monthly'),
(8, 1, 'SALES_RETURN', 'TH', 'yyMM', 5, 'monthly'),
(9, 1, 'PURCHASE_REQUEST', 'YCM', 'yyMM', 4, 'monthly'),
(10, 1, 'PURCHASE_ORDER', 'DM', 'yyMM', 4, 'monthly'),
(11, 1, 'STOCK_RECEIPT', 'PN', 'yyMM', 5, 'monthly'),
(12, 1, 'STOCK_ISSUE', 'PX', 'yyMM', 5, 'monthly'),
(13, 1, 'STOCK_TRANSFER', 'PCK', 'yyMM', 4, 'monthly'),
(14, 1, 'STOCK_ADJUST', 'PDC', 'yyMM', 4, 'monthly'),
(15, 1, 'INVENTORY_COUNT', 'KK', 'yyMM', 3, 'monthly'),
(16, 1, 'SHIPMENT', 'VD', 'yyMM', 5, 'monthly'),
(17, 1, 'COD_RECON', 'DS', 'yyMM', 3, 'monthly'),
(18, 1, 'INVOICE_OUT', 'HDB', 'yyMM', 5, 'monthly'),
(19, 1, 'INVOICE_IN', 'HDM', 'yyMM', 5, 'monthly'),
(20, 1, 'CASH_RECEIPT', 'PT', 'yyMM', 5, 'monthly'),
(21, 1, 'CASH_PAYMENT', 'PC', 'yyMM', 5, 'monthly'),
(22, 1, 'BANK_RECEIPT', 'BC', 'yyMM', 5, 'monthly'),
(23, 1, 'BANK_PAYMENT', 'BN', 'yyMM', 5, 'monthly'),
(24, 1, 'JOURNAL_ENTRY', 'BT', 'yyMM', 5, 'monthly'),
(25, 1, 'TICKET', 'TK', 'yyMM', 5, 'monthly'),
(26, 1, 'WARRANTY', 'BH', 'yyyy', 6, 'yearly'),
(27, 1, 'PROJECT', 'DA', 'yyyy', 3, 'yearly'),
(28, 1, 'TASK', 'CV', NULL, 6, 'never'),
(29, 1, 'CAMPAIGN', 'CD', 'yyyy', 3, 'yearly'),
(30, 1, 'FIXED_ASSET', 'TS', NULL, 5, 'never'),
(31, 1, 'SUPPLIER', 'NCC', NULL, 4, 'never')
;
SET IDENTITY_INSERT [core].[Sequences] OFF;
GO

-- core.Settings (8 dòng)
SET IDENTITY_INSERT [core].[Settings] ON;
INSERT INTO [core].[Settings] ([Id], [CompanyId], [SettingKey], [SettingValue], [IsEncrypted], [UpdatedAt], [UpdatedBy]) VALUES
(1, 1, 'sales.quotation.require_approval', N'true', 0, NULL, NULL),
(2, 1, 'sales.order.check_credit_limit', N'true', 0, NULL, NULL),
(3, 1, 'inventory.cost_method', N'average', 0, NULL, NULL),
(4, 1, 'inventory.allow_negative', N'false', 0, NULL, NULL),
(5, 1, 'accounting.auto_post_invoice', N'false', 0, NULL, NULL),
(6, 1, 'hr.payroll.standard_days', N'26', 0, NULL, NULL),
(7, 1, 'print.return_policy', N'Đổi size / màu trong 7 ngày, sản phẩm còn tem mác, chưa qua sử dụng. Hàng lỗi do sản xuất đổi mới miễn phí.', 0, '2026-11-21T00:55:41.0730000', 1),
(8, 1, 'print.footer', N'Cảm ơn quý khách đã tin tưởng MyStyle!', 0, '2026-11-21T00:55:41.0730000', 1)
;
SET IDENTITY_INSERT [core].[Settings] OFF;
GO

-- core.UserCompanies (7 dòng)
INSERT INTO [core].[UserCompanies] ([UserId], [CompanyId], [BranchId], [DepartmentId], [IsDefault]) VALUES
(1, 1, 1, 9, 1),
(2, 1, 1, 10, 1),
(3, 1, 1, 10, 1),
(4, 1, 1, 10, 1),
(5, 1, 1, 2, 1),
(6, 1, 1, 5, 1),
(7, 1, 1, 3, 1)
;
GO

-- core.UserRoles (13 dòng)
INSERT INTO [core].[UserRoles] ([UserId], [RoleId], [CompanyId]) VALUES
(1, 1, 1),
(2, 2, 1),
(2, 11, 1),
(3, 3, 1),
(3, 11, 1),
(4, 3, 1),
(4, 11, 1),
(5, 3, 1),
(5, 11, 1),
(6, 6, 1),
(6, 11, 1),
(7, 9, 1),
(7, 11, 1)
;
GO

-- core.Users (8 dòng)
SET IDENTITY_INSERT [core].[Users] ON;
INSERT INTO [core].[Users] ([Id], [UserName], [NormalizedUserName], [Email], [NormalizedEmail], [EmailConfirmed], [PasswordHash], [SecurityStamp], [ConcurrencyStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEnd], [LockoutEnabled], [AccessFailedCount], [FullName], [AvatarUrl], [DefaultCompanyId], [Language], [IsSystemAdmin], [IsActive], [LastLoginAt], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, N'admin', N'ADMIN', N'duyanh@gmail.com', N'DUYANH@GMAIL.COM', 0, N'AQAAAAIAAYagAAAAEBtb6iiRfAd5mFl4lacExqtGYg7xXth9dOrz1HtRU4Deo6jC84+Fk/VC+Waw+HF8zw==', N'92d2432a18664b9098a9951fa4357228', N'1ED543E7-8663-4AE7-B115-CC0246C04E57', NULL, 0, 0, NULL, 1, 0, N'Quản trị hệ thống', NULL, 1, 'vi', 1, 1, '2026-11-21T06:57:23.4810000', '2026-11-19T02:33:24.3780000', NULL, '2026-11-21T06:57:23.5560000', NULL, 0),
(2, N'nhung', N'NHUNG', N'nhung@mystyle.vn', N'NHUNG@MYSTYLE.VN', 0, NULL, N'6ED99879-D2A5-404A-A984-EAD28A88C8F8', N'08AA61B9-6B84-406C-BBE3-F0AECCC5CC86', '0912340001', 0, 0, NULL, 1, 0, N'Trần Thị Hồng Nhung', NULL, 1, 'vi', 0, 1, NULL, '2026-11-21T03:09:29.2800000', NULL, NULL, NULL, 0),
(3, N'chau', N'CHAU', N'chau@mystyle.vn', N'CHAU@MYSTYLE.VN', 0, NULL, N'E2CBBF10-4C0D-463B-BF07-8C10AC1892AD', N'0EE5566A-21DA-4272-91A2-9F30BD2FDE62', '0912340002', 0, 0, NULL, 1, 0, N'Lê Minh Châu', NULL, 1, 'vi', 0, 1, NULL, '2026-11-21T03:09:29.2800000', NULL, NULL, NULL, 0),
(4, N'ducanh', N'DUCANH', N'ducanh@mystyle.vn', N'DUCANH@MYSTYLE.VN', 0, N'AQAAAAIAAYagAAAAEBtb6iiRfAd5mFl4lacExqtGYg7xXth9dOrz1HtRU4Deo6jC84+Fk/VC+Waw+HF8zw==', N'C2FA3BF3-26FD-40C7-B343-7A03B3951AE0', N'0D9A9305-09D1-4832-816B-71B3ECC86EBA', '0912340003', 0, 0, NULL, 1, 0, N'Phạm Đức Anh', NULL, 1, 'vi', 0, 1, '2026-11-21T06:13:25.7190000', '2026-11-21T03:09:29.2800000', NULL, '2026-11-21T06:13:26.0120000', NULL, 0),
(5, N'thaovy', N'THAOVY', N'thaovy@mystyle.vn', N'THAOVY@MYSTYLE.VN', 0, NULL, N'BFC601EA-36DE-4FCF-ABFE-17ED06C414CC', N'BDDAC95F-5670-4892-88E1-33DCB7C6B344', '0912340004', 0, 0, NULL, 1, 0, N'Nguyễn Thảo Vy', NULL, 1, 'vi', 0, 1, NULL, '2026-11-21T03:09:29.2800000', NULL, NULL, NULL, 0),
(6, N'tung', N'TUNG', N'tung@mystyle.vn', N'TUNG@MYSTYLE.VN', 0, NULL, N'E078879F-0467-48BB-937F-04A3BBEC7E79', N'ED49F226-868D-4B02-8EEE-9E84226341D3', '0912340005', 0, 0, NULL, 1, 0, N'Hoàng Văn Tùng', NULL, 1, 'vi', 0, 1, NULL, '2026-11-21T03:09:29.2800000', NULL, NULL, NULL, 0),
(7, N'mai', N'MAI', N'mai@mystyle.vn', N'MAI@MYSTYLE.VN', 0, NULL, N'EA3B3A74-8F59-4E70-B988-C9665962BB45', N'C54E78BA-5D7D-4837-9A0E-E118764A37D4', '0912340006', 0, 0, NULL, 1, 0, N'Vũ Thanh Mai', NULL, 1, 'vi', 0, 1, NULL, '2026-11-21T03:09:29.2800000', NULL, NULL, NULL, 0),
(10, N'website.bot.1', N'WEBSITE.BOT.1', NULL, NULL, 0, NULL, N'905D72FC-D639-4567-867A-173183DF8ED5', N'2B8A661E-07F6-4224-97ED-C6690575FAF4', NULL, 0, 0, NULL, 1, 0, N'Website (bán online)', NULL, 1, 'vi', 0, 0, NULL, '2026-11-21T06:31:24.0420000', NULL, NULL, NULL, 0)
;
SET IDENTITY_INSERT [core].[Users] OFF;
GO

-- crm.Leads (15 dòng)
SET IDENTITY_INSERT [crm].[Leads] ON;
INSERT INTO [crm].[Leads] ([Id], [CompanyId], [Code], [FullName], [OrganizationName], [Position], [Phone], [Email], [Street], [ProvinceCode], [SourceId], [CampaignId], [UtmSource], [UtmMedium], [UtmCampaign], [InterestNote], [EstimatedValue], [Score], [Status], [OwnerUserId], [TeamId], [ConvertedPartnerId], [ConvertedOpportunityId], [ConvertedAt], [DisqualifyReason], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'LD2610-00001', N'Trần Thị Bình', N'Công ty CP Hưng Thịnh', N'Giám đốc mua hàng', '0912345678', 'binh.tran@hungthinh.vn', NULL, NULL, 2, NULL, NULL, NULL, 'demo-data', N'Cần phần mềm quản lý kho cho 3 chi nhánh', 350000000.00, 0, 'converted', 1, NULL, 17, 13, '2026-10-11T08:54:25.7940000', NULL, '2026-10-09T08:05:02.2210000', 1, NULL, NULL, 0),
(2, 1, 'LD2610-00002', N'Lê Văn Cường', N'Đại Việt Tech', N'CTO', '0903111222', 'cuong@daiviet.tech', NULL, NULL, 1, NULL, NULL, NULL, 'demo-data', N'Triển khai ERP toàn công ty, 120 người dùng', 480000000.00, 0, 'converted', 1, NULL, 18, 14, '2026-10-15T08:54:25.7940000', NULL, '2026-10-13T07:28:02.4350000', 1, NULL, NULL, 0),
(3, 1, 'LD2610-00003', N'Phạm Minh Đức', N'Nhựa Tân Tiến', N'Trưởng phòng KD', '0389999000', 'duc.pm@tantien.com.vn', NULL, NULL, 6, NULL, NULL, NULL, 'demo-data', N'Được anh Cường giới thiệu, quan tâm module bán hàng', 120000000.00, 0, 'contacted', 1, NULL, NULL, NULL, NULL, NULL, '2026-10-16T06:51:02.4350000', 1, NULL, NULL, 0),
(4, 1, 'LD2610-00004', N'Nguyễn Thu Hà', N'Dược phẩm An Khang', N'Kế toán trưởng', '0977222333', 'ha.nguyen@ankhang.vn', NULL, NULL, 4, NULL, NULL, NULL, 'demo-data', N'Cần hóa đơn điện tử + kế toán TT200', 210000000.00, 0, 'converted', 1, NULL, 19, 16, '2026-10-22T08:54:25.7940000', NULL, '2026-10-20T06:14:02.4350000', 1, NULL, NULL, 0),
(5, 1, 'LD2610-00005', N'Đỗ Quang Huy', N'Gạch men Đồng Tâm Việt', N'Giám đốc', '0868333444', 'huy.do@dongtamviet.vn', NULL, NULL, 7, NULL, NULL, NULL, 'demo-data', N'Gặp tại hội chợ Vietbuild', 95000000.00, 0, 'unqualified', 1, NULL, NULL, NULL, NULL, N'Không có ngân sách năm nay', '2026-10-24T05:37:02.4350000', 1, NULL, NULL, 0),
(6, 1, 'LD2610-00006', N'Vũ Thị Lan', N'Logistic Sài Gòn Xanh', N'COO', '0934555666', 'lan.vu@sgxanh.vn', NULL, NULL, 3, NULL, NULL, NULL, 'demo-data', N'Quan tâm module vận chuyển, đối soát COD', 160000000.00, 0, 'contacted', 1, NULL, NULL, NULL, NULL, NULL, '2026-10-27T05:00:02.4350000', 1, NULL, NULL, 0),
(7, 1, 'LD2610-00007', N'Hoàng Anh Tuấn', N'Thời trang Mộc Lan', N'Chủ cửa hàng', '0395666777', 'tuan@moclan.shop', NULL, NULL, 5, NULL, NULL, NULL, 'demo-data', N'Bán online, cần đồng bộ đơn Shopee / TikTok Shop', 45000000.00, 0, 'new', 1, NULL, NULL, NULL, NULL, NULL, '2026-10-31T04:23:02.4360000', 1, NULL, NULL, 0),
(8, 1, 'LD2611-00001', N'Bùi Ngọc Mai', N'Trường mầm non Hoa Sen', N'Hiệu trưởng', '0789777888', 'mai.bui@hoasen.edu.vn', NULL, NULL, 2, NULL, NULL, NULL, 'demo-data', NULL, 30000000.00, 0, 'unqualified', 1, NULL, NULL, NULL, NULL, N'Nhu cầu không phù hợp, chỉ cần phần mềm học phí', '2026-11-03T03:46:02.4360000', 1, NULL, NULL, 0),
(9, 1, 'LD2611-00002', N'Ngô Đình Khoa', N'Cơ khí Chính xác Miền Bắc', N'Phó giám đốc', '0916888999', 'khoa.ngo@ckmb.vn', NULL, NULL, 8, NULL, NULL, NULL, 'demo-data', N'Đang dùng Excel, muốn quản lý sản xuất + kho', 270000000.00, 0, 'contacted', 1, NULL, NULL, NULL, NULL, NULL, '2026-11-06T03:09:02.4360000', 1, NULL, NULL, 0),
(10, 1, 'LD2611-00003', N'Trịnh Thị Thảo', N'Mỹ phẩm Thảo Mộc', N'Marketing Manager', '0329000111', 'thao@thaomoc.vn', NULL, NULL, 2, NULL, NULL, NULL, 'demo-data', N'Hỏi về CRM + chăm sóc khách hàng qua Zalo', 80000000.00, 0, 'new', 1, NULL, NULL, NULL, NULL, NULL, '2026-11-09T02:32:02.4360000', 1, NULL, NULL, 0),
(11, 1, 'LD2611-00004', N'Đặng Văn Long', N'Xây dựng Long Phát', N'Giám đốc', '0947111000', 'long.dang@longphat.vn', NULL, NULL, 6, NULL, NULL, NULL, 'demo-data', N'Quản lý dự án công trình, vật tư, công nợ nhà thầu', 520000000.00, 0, 'converted', 1, NULL, 20, 17, '2026-11-13T08:54:25.7940000', NULL, '2026-11-12T01:55:02.4360000', 1, NULL, NULL, 0),
(12, 1, 'LD2611-00005', N'Lý Thanh Tâm', NULL, NULL, '0763222111', NULL, NULL, NULL, 1, NULL, NULL, NULL, 'demo-data', N'Để lại số qua form liên hệ, chưa rõ nhu cầu', NULL, 0, 'new', 1, NULL, NULL, NULL, NULL, NULL, '2026-11-14T01:18:02.4360000', 1, NULL, NULL, 0),
(13, 1, 'LD2611-00006', N'Phan Quốc Bảo', N'Nội thất Bảo An', N'Chủ doanh nghiệp', '0858333222', 'bao@noithatbaoan.vn', NULL, NULL, 4, NULL, NULL, NULL, 'demo-data', N'Cần báo giá gói Bán hàng + Kho', 150000000.00, 0, 'new', 1, NULL, NULL, NULL, NULL, NULL, '2026-11-16T00:41:02.4360000', 1, NULL, NULL, 0),
(14, 1, 'LD2611-00007', N'Châu Mỹ Linh', N'Spa Linh Châu', N'Chủ spa', '0707444333', 'linh@linhchauspa.vn', NULL, NULL, 3, NULL, NULL, NULL, 'demo-data', N'Quản lý lịch hẹn và khách hàng thân thiết', 25000000.00, 0, 'new', 1, NULL, NULL, NULL, NULL, NULL, '2026-11-18T00:04:02.4360000', 1, NULL, NULL, 0),
(15, 1, 'LD2611-00008', N'Tạ Minh Nhật', N'Điện máy Nhật Minh', N'Trưởng phòng IT', '0981555444', 'nhat.ta@nhatminh.com.vn', NULL, NULL, 1, NULL, NULL, NULL, 'demo-data', N'Hẹn demo tuần sau', 300000000.00, 0, 'new', 1, NULL, NULL, NULL, NULL, NULL, '2026-11-19T23:27:02.4360000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [crm].[Leads] OFF;
GO

-- crm.LeadSources (9 dòng)
SET IDENTITY_INSERT [crm].[LeadSources] ON;
INSERT INTO [crm].[LeadSources] ([Id], [CompanyId], [Code], [Name], [IsActive]) VALUES
(1, 1, 'WEBSITE', N'Website', 1),
(2, 1, 'FACEBOOK', N'Facebook', 1),
(3, 1, 'ZALO', N'Zalo', 1),
(4, 1, 'GOOGLE', N'Google Ads', 1),
(5, 1, 'TIKTOK', N'TikTok', 1),
(6, 1, 'REFERRAL', N'Giới thiệu', 1),
(7, 1, 'EVENT', N'Sự kiện, hội chợ', 1),
(8, 1, 'COLD_CALL', N'Gọi điện chủ động', 1),
(9, 1, 'OTHER', N'Khác', 1)
;
SET IDENTITY_INSERT [crm].[LeadSources] OFF;
GO

-- crm.LostReasons (6 dòng)
SET IDENTITY_INSERT [crm].[LostReasons] ON;
INSERT INTO [crm].[LostReasons] ([Id], [CompanyId], [Name], [IsActive]) VALUES
(1, 1, N'Giá cao', 1),
(2, 1, N'Chọn đối thủ', 1),
(3, 1, N'Không có ngân sách', 1),
(4, 1, N'Không còn nhu cầu', 1),
(5, 1, N'Không liên lạc được', 1),
(6, 1, N'Sản phẩm không phù hợp', 1)
;
SET IDENTITY_INSERT [crm].[LostReasons] OFF;
GO

-- crm.Opportunities (10 dòng)
SET IDENTITY_INSERT [crm].[Opportunities] ON;
INSERT INTO [crm].[Opportunities] ([Id], [CompanyId], [Code], [Name], [PartnerId], [ContactId], [LeadId], [PipelineId], [StageId], [ExpectedRevenue], [Probability], [CurrencyCode], [ExpectedCloseDate], [Priority], [OwnerUserId], [TeamId], [Status], [LostReasonId], [LostNote], [ClosedAt], [Description], [StageChangedAt], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(13, 1, 'CH2610-00001', N'Phần mềm quản lý kho 3 chi nhánh', 17, 15, 1, 1, 4, 350000000.00, 60.00, 'VND', '2026-12-10', 2, 1, NULL, 'open', NULL, NULL, NULL, N'Đã gửi báo giá gói Kho + Bán hàng, chờ phản hồi', '2026-11-01T08:54:25.7940000', '2026-10-13T08:54:25.7940000', 1, NULL, NULL, 0),
(14, 1, 'CH2610-00002', N'Triển khai ERP toàn công ty - 120 người dùng', 18, 16, 2, 1, 5, 480000000.00, 80.00, 'VND', '2026-11-30', 3, 1, NULL, 'open', NULL, NULL, NULL, N'Đang đàm phán chiết khấu 8%', '2026-11-03T08:54:25.7940000', '2026-10-17T08:54:25.7940000', 1, NULL, NULL, 0),
(15, 1, 'CH2610-00003', N'Gói bảo trì & hỗ trợ năm 2027', 18, 16, 2, 1, 6, 60000000.00, 100.00, 'VND', NULL, 1, 1, NULL, 'won', NULL, NULL, '2026-11-15T08:54:25.7940000', N'Đã ký hợp đồng', '2026-11-15T08:54:25.7940000', '2026-10-21T08:54:25.7940000', 1, NULL, NULL, 0),
(16, 1, 'CH2610-00004', N'Kế toán TT200 + hóa đơn điện tử', 19, 17, 4, 1, 3, 210000000.00, 40.00, 'VND', '2026-12-20', 1, 1, NULL, 'open', NULL, NULL, NULL, N'Khảo sát quy trình kế toán 2 chi nhánh', '2026-11-07T08:54:25.7940000', '2026-10-24T08:54:25.7940000', 1, NULL, NULL, 0),
(17, 1, 'CH2611-00001', N'Quản lý dự án công trình & vật tư', 20, 18, 11, 1, 2, 520000000.00, 20.00, 'VND', '2027-01-04', 2, 1, NULL, 'open', NULL, NULL, NULL, N'Hẹn demo với ban giám đốc', '2026-11-17T08:54:25.7940000', '2026-11-14T08:54:25.7940000', 1, NULL, NULL, 0),
(18, 1, 'CH2610-00005', N'Module mua hàng + kho nguyên vật liệu', 21, 19, NULL, 1, 1, 180000000.00, 10.00, 'VND', '2027-01-19', 0, 1, NULL, 'open', NULL, NULL, NULL, NULL, '2026-11-09T08:54:25.7940000', '2026-10-29T08:54:25.7940000', 1, NULL, NULL, 0),
(19, 1, 'CH2610-00006', N'Phần mềm bán lẻ cho 5 cửa hàng', 22, 20, NULL, 1, 7, 95000000.00, 0.00, 'VND', NULL, 1, 1, NULL, 'lost', 1, N'Đối thủ báo giá thấp hơn 20%', '2026-11-08T08:54:25.7940000', NULL, '2026-11-08T08:54:25.7940000', '2026-10-20T08:54:25.7940000', 1, NULL, NULL, 0),
(20, 1, 'CH2611-00002', N'CRM chăm sóc khách hàng thân thiết', 24, 21, NULL, 1, 4, 40000000.00, 60.00, 'VND', '2026-11-17', 1, 1, NULL, 'open', NULL, NULL, NULL, N'Đã quá ngày dự kiến chốt, cần gọi lại', '2026-11-12T08:54:25.7940000', '2026-11-04T08:54:25.7940000', 1, NULL, NULL, 0),
(21, 1, 'CH2610-00007', N'Gói phần mềm cá nhân', 23, NULL, NULL, 1, 6, 15000000.00, 100.00, 'VND', NULL, 0, 1, NULL, 'won', NULL, NULL, '2026-10-31T08:54:25.7940000', NULL, '2026-10-31T08:54:25.7940000', '2026-10-25T08:54:25.7940000', 1, NULL, NULL, 0),
(22, 1, 'CH2611-00003', N'Mở rộng hệ thống cho chi nhánh thứ 4', 17, 15, 1, 1, 1, 120000000.00, 10.00, 'VND', '2027-02-18', 1, 1, NULL, 'open', NULL, NULL, NULL, N'Phát sinh từ dự án kho', '2026-11-19T08:54:25.7940000', '2026-11-17T08:54:25.7940000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [crm].[Opportunities] OFF;
GO

-- crm.Pipelines (1 dòng)
SET IDENTITY_INSERT [crm].[Pipelines] ON;
INSERT INTO [crm].[Pipelines] ([Id], [CompanyId], [Name], [IsDefault], [IsActive]) VALUES
(1, 1, N'Quy trình bán hàng', 1, 1)
;
SET IDENTITY_INSERT [crm].[Pipelines] OFF;
GO

-- crm.Stages (7 dòng)
SET IDENTITY_INSERT [crm].[Stages] ON;
INSERT INTO [crm].[Stages] ([Id], [PipelineId], [Name], [SortOrder], [Probability], [StageType], [Color]) VALUES
(1, 1, N'Mới', 10, 10.00, 'open', NULL),
(2, 1, N'Đã liên hệ', 20, 20.00, 'open', NULL),
(3, 1, N'Khảo sát nhu cầu', 30, 40.00, 'open', NULL),
(4, 1, N'Đã gửi báo giá', 40, 60.00, 'open', NULL),
(5, 1, N'Đàm phán', 50, 80.00, 'open', NULL),
(6, 1, N'Thành công', 60, 100.00, 'won', NULL),
(7, 1, N'Thất bại', 70, 0.00, 'lost', NULL)
;
SET IDENTITY_INSERT [crm].[Stages] OFF;
GO

-- cs.SlaPolicies (4 dòng)
SET IDENTITY_INSERT [cs].[SlaPolicies] ON;
INSERT INTO [cs].[SlaPolicies] ([Id], [CompanyId], [Name], [Priority], [FirstResponseMinutes], [ResolutionMinutes], [BusinessHoursOnly]) VALUES
(1, 1, N'Khẩn cấp', 'urgent', 30, 240, 1),
(2, 1, N'Cao', 'high', 60, 480, 1),
(3, 1, N'Bình thường', 'normal', 240, 1440, 1),
(4, 1, N'Thấp', 'low', 480, 4320, 1)
;
SET IDENTITY_INSERT [cs].[SlaPolicies] OFF;
GO

-- cs.TicketCategories (5 dòng)
SET IDENTITY_INSERT [cs].[TicketCategories] ON;
INSERT INTO [cs].[TicketCategories] ([Id], [CompanyId], [Name], [DefaultAssigneeUserId], [IsActive]) VALUES
(1, 1, N'Hỗ trợ sử dụng', NULL, 1),
(2, 1, N'Khiếu nại', NULL, 1),
(3, 1, N'Bảo hành', NULL, 1),
(4, 1, N'Đổi trả', NULL, 1),
(5, 1, N'Góp ý', NULL, 1)
;
SET IDENTITY_INSERT [cs].[TicketCategories] OFF;
GO

-- cs.TicketMessages (10 dòng)
SET IDENTITY_INSERT [cs].[TicketMessages] ON;
INSERT INTO [cs].[TicketMessages] ([Id], [TicketId], [AuthorUserId], [AuthorName], [Body], [IsInternal], [CreatedAt]) VALUES
(1, 1, 1, NULL, N'Đã báo xưởng kiểm tra lô áo này', 1, '2026-11-10T15:27:41.0770000'),
(2, 1, 1, NULL, N'Shop xin lỗi chị, shop gửi áo mới và nhận lại áo lỗi, chị không mất phí ship ạ.', 0, '2026-11-10T15:42:41.0770000'),
(3, 2, 1, NULL, N'Shop kiểm tra camera đóng gói, đúng là thiếu. Shop gửi bù mũ trong hôm nay ạ.', 0, '2026-11-13T03:42:41.0770000'),
(4, 3, 1, NULL, N'Với chiều cao cân nặng này anh mặc size 30 vừa đẹp ạ.', 0, '2026-11-08T03:42:41.0770000'),
(5, 4, 1, NULL, N'Chờ ảnh để gửi NCC Bình Tiên xem', 1, '2026-11-19T09:27:41.0770000'),
(6, 4, 1, NULL, N'Shop đã nhận thông tin, chị gửi giúp shop vài ảnh đế giày ạ.', 0, '2026-11-19T09:42:41.0770000'),
(7, 5, 1, NULL, N'Size L màu trắng shop còn hàng, anh mang áo qua cửa hàng đổi giúp shop nhé.', 0, '2026-11-19T19:42:41.0770000'),
(8, 6, 1, NULL, N'Đã gọi GHTK, hàng đang ở kho trung chuyển', 1, '2026-11-19T13:27:41.0770000'),
(9, 9, 1, NULL, N'Cảm ơn anh đã góp ý, đợt hàng tới shop sẽ nhập thêm size XXL ạ.', 0, '2026-10-30T19:42:41.0770000'),
(10, 10, 1, NULL, N'Đơn hủy trên Shopee sẽ được Shopee hoàn về ví trong 3-5 ngày ạ.', 0, '2026-11-15T15:42:41.0770000')
;
SET IDENTITY_INSERT [cs].[TicketMessages] OFF;
GO

-- cs.Tickets (10 dòng)
SET IDENTITY_INSERT [cs].[Tickets] ON;
INSERT INTO [cs].[Tickets] ([Id], [CompanyId], [Code], [Subject], [Description], [PartnerId], [ContactId], [ReporterName], [ReporterPhone], [ReporterEmail], [SalesOrderId], [ProductId], [CategoryId], [Channel], [Priority], [Status], [AssignedUserId], [DepartmentId], [SlaPolicyId], [FirstResponseDueAt], [ResolutionDueAt], [FirstRespondedAt], [ResolvedAt], [ClosedAt], [Resolution], [SatisfactionScore], [SatisfactionNote], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'TK2611-00001', N'Áo bị lỗi đường may ở tay', N'Khách nhận hàng thấy đường may tay áo bị bung, muốn đổi cái mới.', 33, NULL, NULL, NULL, NULL, 97, NULL, 4, 'zalo', 'high', 'resolved', 1, NULL, 2, '2026-11-10T16:17:41.0000000', '2026-11-10T23:17:41.0000000', '2026-11-10T15:42:41.0770000', '2026-11-10T21:17:41.0770000', NULL, N'Đổi áo mới, shop chịu phí ship 2 chiều', 5, NULL, '2026-11-10T15:17:41.0770000', 1, NULL, NULL, 0),
(2, 1, 'TK2611-00002', N'Giao thiếu 1 mũ trong đơn', N'Đơn có 2 sản phẩm nhưng khách chỉ nhận được áo, thiếu mũ.', 31, NULL, NULL, NULL, NULL, 99, NULL, 2, 'facebook', 'high', 'resolved', 1, NULL, 2, '2026-11-13T04:17:41.0000000', '2026-11-13T11:17:41.0000000', '2026-11-13T03:42:41.0770000', '2026-11-13T09:17:41.0770000', NULL, N'Gửi bù mũ qua GHN, tặng voucher 50k', 4, NULL, '2026-11-13T03:17:41.0770000', 1, NULL, NULL, 0),
(3, 1, 'TK2611-00003', N'Hỏi bảng size quần jeans', N'Khách cao 1m70 nặng 65kg hỏi nên mặc size nào.', 26, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'zalo', 'low', 'closed', 1, NULL, 4, '2026-11-08T11:17:41.0000000', '2026-11-11T03:17:41.0000000', '2026-11-08T03:42:41.0770000', '2026-11-08T09:17:41.0770000', '2026-11-09T09:17:41.0770000', N'Tư vấn size 30', 5, NULL, '2026-11-08T03:17:41.0770000', 1, NULL, NULL, 0),
(4, 1, 'TK2611-00004', N'Giày sneaker bị ố vàng sau 2 tuần', N'Khách phản ánh đế giày bị ố vàng, muốn bảo hành.', 31, NULL, NULL, NULL, NULL, 129, NULL, 3, 'phone', 'normal', 'open', 1, NULL, 3, '2026-11-19T13:17:41.0000000', '2026-11-20T09:17:41.0000000', '2026-11-19T09:42:41.0770000', NULL, NULL, NULL, NULL, NULL, '2026-11-19T09:17:41.0770000', 1, NULL, NULL, 0),
(5, 1, 'TK2611-00005', N'Muốn đổi sang size L', N'Khách mua áo polo size M nhưng mặc chật, muốn đổi L.', 31, NULL, NULL, NULL, NULL, 126, NULL, 4, 'walk_in', 'normal', 'pending', 1, NULL, 3, '2026-11-19T23:17:41.0000000', '2026-11-20T19:17:41.0000000', '2026-11-19T19:42:41.0770000', NULL, NULL, NULL, NULL, NULL, '2026-11-19T19:17:41.0770000', 1, NULL, NULL, 0),
(6, 1, 'TK2611-00006', N'Đơn chưa nhận được sau 5 ngày', N'Khách đặt trên website 5 ngày chưa nhận được hàng.', 31, NULL, NULL, NULL, NULL, 119, NULL, 2, 'web', 'urgent', 'open', 1, NULL, 1, '2026-11-19T13:47:41.0000000', '2026-11-19T17:17:41.0000000', NULL, NULL, NULL, NULL, NULL, NULL, '2026-11-19T13:17:41.0770000', 1, NULL, NULL, 0),
(7, 1, 'TK2611-00007', N'Hỏi chính sách mua sỉ', N'Chủ shop ở Đà Nẵng muốn lấy sỉ 100 áo thun.', 30, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'phone', 'normal', 'new', NULL, NULL, 3, '2026-11-20T16:17:41.0000000', '2026-11-21T12:17:41.0000000', NULL, NULL, NULL, NULL, NULL, NULL, '2026-11-20T12:17:41.0770000', 1, NULL, NULL, 0),
(8, 1, 'TK2611-00008', N'Váy bị phai màu sau lần giặt đầu', N'Khách giặt máy lần đầu thì váy bị phai màu.', 41, NULL, NULL, NULL, NULL, 128, NULL, 2, 'facebook', 'high', 'new', NULL, NULL, 2, '2026-11-20T07:17:41.0000000', '2026-11-20T14:17:41.0000000', NULL, NULL, NULL, NULL, NULL, NULL, '2026-11-20T06:17:41.0770000', 1, NULL, NULL, 0),
(9, 1, 'TK2610-00001', N'Góp ý: nên có thêm size XXL áo khoác', N'Khách to người muốn mua áo khoác bomber size XXL.', 32, NULL, NULL, NULL, NULL, NULL, NULL, 5, 'facebook', 'low', 'closed', 1, NULL, 4, '2026-10-31T03:17:41.0000000', '2026-11-02T19:17:41.0000000', '2026-10-30T19:42:41.0770000', '2026-10-31T01:17:41.0770000', '2026-11-01T01:17:41.0770000', N'Ghi nhận, đề xuất nhập thêm size XXL', 4, NULL, '2026-10-30T19:17:41.0770000', 1, NULL, NULL, 0),
(10, 1, 'TK2611-00009', N'Hoàn tiền đơn hủy trên Shopee', N'Khách hủy đơn trên Shopee nhưng chưa thấy tiền hoàn.', 23, NULL, NULL, NULL, NULL, NULL, NULL, 2, 'other', 'normal', 'resolved', 1, NULL, 3, '2026-11-15T19:17:41.0000000', '2026-11-16T15:17:41.0000000', '2026-11-15T15:42:41.0770000', '2026-11-15T21:17:41.0770000', NULL, N'Hướng dẫn khách kiểm tra ví ShopeePay', 3, NULL, '2026-11-15T15:17:41.0770000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [cs].[Tickets] OFF;
GO

-- doc.Documents (12 dòng)
SET IDENTITY_INSERT [doc].[Documents] ON;
INSERT INTO [doc].[Documents] ([Id], [CompanyId], [FolderId], [Code], [Title], [DocumentType], [PartnerId], [EntityName], [EntityId], [CurrentVersionNo], [OwnerUserId], [Status], [EffectiveDate], [ExpiryDate], [ContractValue], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 1, 'HD-TMB-01', N'Hợp đồng thuê mặt bằng cửa hàng 123 Lê Lợi', 'contract', NULL, NULL, NULL, 0, 1, 'active', '2024-12-12', '2026-12-12', 960000000.00, '2024-12-11T03:09:29.2720000', 1, NULL, NULL, 0),
(2, 1, 1, 'HD-TMB-02', N'Hợp đồng thuê mặt bằng chi nhánh Q7 (45 Nguyễn Thị Thập)', 'contract', NULL, NULL, NULL, 0, 2, 'signed', '2026-11-05', '2029-11-04', 1620000000.00, '2026-11-04T03:09:29.2720000', 1, NULL, NULL, 0),
(3, 1, 1, 'HD-NCC-01', N'Hợp đồng nguyên tắc cung cấp hàng may mặc 2026', 'contract', 25, NULL, NULL, 0, 1, 'active', '2026-01-25', '2027-01-25', 500000000.00, '2026-01-24T03:09:29.2720000', 1, NULL, NULL, 0),
(4, 1, 1, 'HD-NCC-03', N'Hợp đồng cung cấp vải và quần jeans', 'contract', 27, NULL, NULL, 0, 1, 'active', '2026-05-05', '2027-05-05', 300000000.00, '2026-05-04T03:09:29.2720000', 1, NULL, NULL, 0),
(5, 1, 1, 'HD-NCC-04', N'Hợp đồng phân phối giày da 2025', 'contract', 28, NULL, NULL, 0, 1, 'active', '2025-10-17', '2026-10-17', 180000000.00, '2025-10-16T03:09:29.2720000', 1, NULL, NULL, 0),
(6, 1, 1, 'HD-VC-01', N'Hợp đồng dịch vụ giao hàng GHN', 'contract', NULL, NULL, NULL, 0, 6, 'pending_signature', NULL, NULL, NULL, '2026-11-18T03:09:29.2720000', 1, NULL, NULL, 0),
(7, 1, 2, NULL, N'Chính sách đổi trả hàng (áp dụng 2026)', 'policy', NULL, NULL, NULL, 0, 1, 'active', '2026-01-05', NULL, NULL, '2026-01-04T03:09:29.2720000', 1, NULL, NULL, 0),
(8, 1, 2, NULL, N'Quy định chấm công, nghỉ phép', 'policy', NULL, NULL, NULL, 0, 1, 'active', '2026-01-05', NULL, NULL, '2026-01-04T03:09:29.2720000', 1, NULL, NULL, 0),
(9, 1, 4, NULL, N'Quy trình nhập kho và kiểm hàng', 'process', NULL, NULL, NULL, 0, 6, 'active', '2026-06-24', NULL, NULL, '2026-06-23T03:09:29.2720000', 6, NULL, NULL, 0),
(10, 1, 3, NULL, N'Mẫu phiếu bảo hành giày', 'form', NULL, NULL, NULL, 0, 1, 'active', NULL, NULL, NULL, '2026-07-24T03:09:29.2720000', 1, NULL, NULL, 0),
(11, 1, 3, NULL, N'Mẫu biên bản bàn giao ca', 'form', NULL, NULL, NULL, 0, 2, 'draft', NULL, NULL, NULL, '2026-11-19T03:09:29.2720000', 2, NULL, NULL, 0),
(12, 1, 5, NULL, N'Báo cáo hiệu quả quảng cáo tháng 10', 'report', NULL, NULL, NULL, 0, 7, 'active', NULL, NULL, NULL, '2026-11-01T03:09:29.2720000', 7, NULL, NULL, 0)
;
SET IDENTITY_INSERT [doc].[Documents] OFF;
GO

-- doc.Folders (5 dòng)
SET IDENTITY_INSERT [doc].[Folders] ON;
INSERT INTO [doc].[Folders] ([Id], [CompanyId], [ParentId], [Name], [OwnerUserId], [DepartmentId], [Path], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, NULL, N'Hợp đồng', 1, NULL, NULL, '2026-08-23T03:09:29.2720000', 1, NULL, NULL, 0),
(2, 1, NULL, N'Quy trình - Quy định', 1, NULL, NULL, '2026-08-23T03:09:29.2720000', 1, NULL, NULL, 0),
(3, 1, NULL, N'Biểu mẫu', 1, NULL, NULL, '2026-08-23T03:09:29.2720000', 1, NULL, NULL, 0),
(4, 1, NULL, N'Kho vận', 6, 5, NULL, '2026-09-22T03:09:29.2720000', 1, NULL, NULL, 0),
(5, 1, NULL, N'Marketing', 7, 3, NULL, '2026-09-22T03:09:29.2720000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [doc].[Folders] OFF;
GO

-- hr.Attendances (186 dòng)
SET IDENTITY_INSERT [hr].[Attendances] ON;
INSERT INTO [hr].[Attendances] ([Id], [EmployeeId], [WorkDate], [ShiftId], [CheckIn], [CheckOut], [WorkHours], [OvertimeHours], [LateMinutes], [EarlyMinutes], [Source], [Latitude], [Longitude], [Status], [Note]) VALUES
(1, 1, '2026-10-01', 1, '2026-10-01T07:52:00.0000000', '2026-10-01T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(2, 2, '2026-10-01', 1, '2026-10-01T07:55:00.0000000', '2026-10-01T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(3, 3, '2026-10-01', 1, '2026-10-01T07:58:00.0000000', '2026-10-01T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(4, 4, '2026-10-01', 1, '2026-10-01T07:51:00.0000000', '2026-10-01T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(5, 1, '2026-10-02', 1, '2026-10-02T07:51:00.0000000', '2026-10-02T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(6, 2, '2026-10-02', 1, '2026-10-02T07:54:00.0000000', '2026-10-02T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(7, 3, '2026-10-02', 1, '2026-10-02T07:57:00.0000000', '2026-10-02T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(8, 4, '2026-10-02', 1, '2026-10-02T08:00:00.0000000', '2026-10-02T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(9, 1, '2026-10-03', 1, '2026-10-03T08:00:00.0000000', '2026-10-03T19:00:00.0000000', 8.00, 2.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(10, 2, '2026-10-03', 1, '2026-10-03T07:53:00.0000000', '2026-10-03T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(11, 3, '2026-10-03', 1, '2026-10-03T07:56:00.0000000', '2026-10-03T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(12, 4, '2026-10-03', 1, '2026-10-03T07:59:00.0000000', '2026-10-03T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(13, 1, '2026-10-05', 1, '2026-10-05T07:58:00.0000000', '2026-10-05T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(14, 2, '2026-10-05', 1, '2026-10-05T07:51:00.0000000', '2026-10-05T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(15, 3, '2026-10-05', 1, '2026-10-05T08:15:00.0000000', '2026-10-05T17:00:00.0000000', 8.00, 0.00, 15, 0, 'web', NULL, NULL, 'present', NULL),
(16, 4, '2026-10-05', 1, '2026-10-05T07:57:00.0000000', '2026-10-05T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(17, 1, '2026-10-06', 1, '2026-10-06T07:57:00.0000000', '2026-10-06T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(18, 2, '2026-10-06', 1, '2026-10-06T08:00:00.0000000', '2026-10-06T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(19, 3, '2026-10-06', 1, '2026-10-06T07:53:00.0000000', '2026-10-06T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(20, 4, '2026-10-06', 1, '2026-10-06T07:56:00.0000000', '2026-10-06T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(21, 1, '2026-10-07', 1, '2026-10-07T07:56:00.0000000', '2026-10-07T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(22, 2, '2026-10-07', 1, '2026-10-07T07:59:00.0000000', '2026-10-07T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(23, 3, '2026-10-07', 1, '2026-10-07T07:52:00.0000000', '2026-10-07T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(24, 4, '2026-10-07', 1, '2026-10-07T07:55:00.0000000', '2026-10-07T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(25, 1, '2026-10-08', 1, '2026-10-08T07:55:00.0000000', '2026-10-08T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(26, 2, '2026-10-08', 1, '2026-10-08T07:58:00.0000000', '2026-10-08T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(27, 3, '2026-10-08', 1, '2026-10-08T07:51:00.0000000', '2026-10-08T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(28, 4, '2026-10-08', 1, '2026-10-08T07:54:00.0000000', '2026-10-08T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(29, 1, '2026-10-09', 1, '2026-10-09T07:54:00.0000000', '2026-10-09T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(30, 2, '2026-10-09', 1, '2026-10-09T07:57:00.0000000', '2026-10-09T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(31, 3, '2026-10-09', 1, '2026-10-09T08:00:00.0000000', '2026-10-09T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(32, 4, '2026-10-09', 1, '2026-10-09T07:53:00.0000000', '2026-10-09T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(33, 1, '2026-10-10', 1, '2026-10-10T07:53:00.0000000', '2026-10-10T19:00:00.0000000', 8.00, 2.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(34, 2, '2026-10-10', 1, '2026-10-10T07:56:00.0000000', '2026-10-10T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(35, 3, '2026-10-10', 1, '2026-10-10T08:20:00.0000000', '2026-10-10T17:00:00.0000000', 8.00, 0.00, 20, 0, 'web', NULL, NULL, 'present', NULL),
(36, 4, '2026-10-10', 1, '2026-10-10T07:52:00.0000000', '2026-10-10T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(37, 1, '2026-10-12', 1, '2026-10-12T07:51:00.0000000', '2026-10-12T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(38, 2, '2026-10-12', 1, '2026-10-12T07:54:00.0000000', '2026-10-12T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(39, 3, '2026-10-12', 1, '2026-10-12T07:57:00.0000000', '2026-10-12T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(40, 4, '2026-10-12', 1, '2026-10-12T08:00:00.0000000', '2026-10-12T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(41, 1, '2026-10-13', 1, '2026-10-13T08:00:00.0000000', '2026-10-13T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(42, 2, '2026-10-13', 1, '2026-10-13T07:53:00.0000000', '2026-10-13T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(43, 3, '2026-10-13', 1, '2026-10-13T07:56:00.0000000', '2026-10-13T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(44, 4, '2026-10-13', 1, '2026-10-13T07:59:00.0000000', '2026-10-13T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(45, 1, '2026-10-14', 1, '2026-10-14T07:59:00.0000000', '2026-10-14T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(46, 2, '2026-10-14', 1, NULL, NULL, 0.00, 0.00, 0, 0, 'manual', NULL, NULL, 'absent', N'Nghỉ không báo trước'),
(47, 3, '2026-10-14', 1, '2026-10-14T07:55:00.0000000', '2026-10-14T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(48, 4, '2026-10-14', 1, '2026-10-14T07:58:00.0000000', '2026-10-14T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(49, 1, '2026-10-15', 1, '2026-10-15T07:58:00.0000000', '2026-10-15T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(50, 2, '2026-10-15', 1, '2026-10-15T07:51:00.0000000', '2026-10-15T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(51, 3, '2026-10-15', 1, '2026-10-15T08:10:00.0000000', '2026-10-15T17:00:00.0000000', 8.00, 0.00, 10, 0, 'web', NULL, NULL, 'present', NULL),
(52, 4, '2026-10-15', 1, '2026-10-15T07:57:00.0000000', '2026-10-15T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(53, 1, '2026-10-16', 1, '2026-10-16T07:57:00.0000000', '2026-10-16T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(54, 2, '2026-10-16', 1, '2026-10-16T08:00:00.0000000', '2026-10-16T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(55, 3, '2026-10-16', 1, '2026-10-16T07:53:00.0000000', '2026-10-16T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(56, 4, '2026-10-16', 1, '2026-10-16T07:56:00.0000000', '2026-10-16T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(57, 1, '2026-10-17', 1, '2026-10-17T07:56:00.0000000', '2026-10-17T19:00:00.0000000', 8.00, 2.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(58, 2, '2026-10-17', 1, '2026-10-17T07:59:00.0000000', '2026-10-17T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(59, 3, '2026-10-17', 1, '2026-10-17T07:52:00.0000000', '2026-10-17T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(60, 4, '2026-10-17', 1, '2026-10-17T07:55:00.0000000', '2026-10-17T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(61, 1, '2026-10-19', 1, '2026-10-19T07:54:00.0000000', '2026-10-19T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(62, 2, '2026-10-19', 1, '2026-10-19T07:57:00.0000000', '2026-10-19T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(63, 3, '2026-10-19', 1, '2026-10-19T08:00:00.0000000', '2026-10-19T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(64, 4, '2026-10-19', 1, '2026-10-19T07:53:00.0000000', '2026-10-19T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(65, 1, '2026-10-20', 1, '2026-10-20T07:53:00.0000000', '2026-10-20T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(66, 2, '2026-10-20', 1, NULL, NULL, 0.00, 0.00, 0, 0, 'manual', NULL, NULL, 'leave', N'Nghỉ phép năm'),
(67, 3, '2026-10-20', 1, '2026-10-20T08:15:00.0000000', '2026-10-20T17:00:00.0000000', 8.00, 0.00, 15, 0, 'web', NULL, NULL, 'present', NULL),
(68, 4, '2026-10-20', 1, '2026-10-20T07:52:00.0000000', '2026-10-20T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(69, 1, '2026-10-21', 1, '2026-10-21T07:52:00.0000000', '2026-10-21T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(70, 2, '2026-10-21', 1, NULL, NULL, 0.00, 0.00, 0, 0, 'manual', NULL, NULL, 'leave', N'Nghỉ phép năm'),
(71, 3, '2026-10-21', 1, '2026-10-21T07:58:00.0000000', '2026-10-21T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(72, 4, '2026-10-21', 1, '2026-10-21T07:51:00.0000000', '2026-10-21T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(73, 1, '2026-10-22', 1, '2026-10-22T07:51:00.0000000', '2026-10-22T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(74, 2, '2026-10-22', 1, '2026-10-22T07:54:00.0000000', '2026-10-22T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(75, 3, '2026-10-22', 1, '2026-10-22T07:57:00.0000000', '2026-10-22T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(76, 4, '2026-10-22', 1, '2026-10-22T08:00:00.0000000', '2026-10-22T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(77, 1, '2026-10-23', 1, '2026-10-23T08:00:00.0000000', '2026-10-23T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(78, 2, '2026-10-23', 1, '2026-10-23T07:53:00.0000000', '2026-10-23T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(79, 3, '2026-10-23', 1, '2026-10-23T07:56:00.0000000', '2026-10-23T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(80, 4, '2026-10-23', 1, '2026-10-23T07:59:00.0000000', '2026-10-23T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(81, 1, '2026-10-24', 1, '2026-10-24T07:59:00.0000000', '2026-10-24T19:00:00.0000000', 8.00, 2.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(82, 2, '2026-10-24', 1, '2026-10-24T07:52:00.0000000', '2026-10-24T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(83, 3, '2026-10-24', 1, '2026-10-24T07:55:00.0000000', '2026-10-24T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(84, 4, '2026-10-24', 1, '2026-10-24T07:58:00.0000000', '2026-10-24T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(85, 1, '2026-10-26', 1, '2026-10-26T07:57:00.0000000', '2026-10-26T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(86, 2, '2026-10-26', 1, '2026-10-26T08:00:00.0000000', '2026-10-26T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(87, 3, '2026-10-26', 1, '2026-10-26T07:53:00.0000000', '2026-10-26T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(88, 4, '2026-10-26', 1, '2026-10-26T07:56:00.0000000', '2026-10-26T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(89, 1, '2026-10-27', 1, '2026-10-27T07:56:00.0000000', '2026-10-27T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(90, 2, '2026-10-27', 1, '2026-10-27T07:59:00.0000000', '2026-10-27T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(91, 3, '2026-10-27', 1, '2026-10-27T07:52:00.0000000', '2026-10-27T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(92, 4, '2026-10-27', 1, '2026-10-27T07:55:00.0000000', '2026-10-27T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(93, 1, '2026-10-28', 1, '2026-10-28T07:55:00.0000000', '2026-10-28T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(94, 2, '2026-10-28', 1, '2026-10-28T07:58:00.0000000', '2026-10-28T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(95, 3, '2026-10-28', 1, '2026-10-28T07:51:00.0000000', '2026-10-28T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(96, 4, '2026-10-28', 1, '2026-10-28T07:54:00.0000000', '2026-10-28T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(97, 1, '2026-10-29', 1, '2026-10-29T07:54:00.0000000', '2026-10-29T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(98, 2, '2026-10-29', 1, '2026-10-29T07:57:00.0000000', '2026-10-29T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(99, 3, '2026-10-29', 1, '2026-10-29T08:00:00.0000000', '2026-10-29T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(100, 4, '2026-10-29', 1, '2026-10-29T07:53:00.0000000', '2026-10-29T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(101, 1, '2026-10-30', 1, '2026-10-30T07:53:00.0000000', '2026-10-30T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(102, 2, '2026-10-30', 1, '2026-10-30T07:56:00.0000000', '2026-10-30T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(103, 3, '2026-10-30', 1, '2026-10-30T08:10:00.0000000', '2026-10-30T17:00:00.0000000', 8.00, 0.00, 10, 0, 'web', NULL, NULL, 'present', NULL),
(104, 4, '2026-10-30', 1, '2026-10-30T07:52:00.0000000', '2026-10-30T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(105, 1, '2026-10-31', 1, '2026-10-31T07:52:00.0000000', '2026-10-31T19:00:00.0000000', 8.00, 2.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(106, 2, '2026-10-31', 1, '2026-10-31T07:55:00.0000000', '2026-10-31T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(107, 3, '2026-10-31', 1, '2026-10-31T07:58:00.0000000', '2026-10-31T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(108, 4, '2026-10-31', 1, '2026-10-31T07:51:00.0000000', '2026-10-31T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(109, 1, '2026-11-02', 1, '2026-11-02T07:51:00.0000000', '2026-11-02T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(110, 2, '2026-11-02', 1, '2026-11-02T07:54:00.0000000', '2026-11-02T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(111, 3, '2026-11-02', 1, '2026-11-02T07:57:00.0000000', '2026-11-02T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(112, 4, '2026-11-02', 1, '2026-11-02T08:00:00.0000000', '2026-11-02T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(113, 1, '2026-11-03', 1, '2026-11-03T08:00:00.0000000', '2026-11-03T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(114, 2, '2026-11-03', 1, '2026-11-03T07:53:00.0000000', '2026-11-03T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(115, 3, '2026-11-03', 1, '2026-11-03T07:56:00.0000000', '2026-11-03T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(116, 4, '2026-11-03', 1, '2026-11-03T07:59:00.0000000', '2026-11-03T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(117, 1, '2026-11-04', 1, '2026-11-04T07:59:00.0000000', '2026-11-04T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(118, 2, '2026-11-04', 1, '2026-11-04T07:52:00.0000000', '2026-11-04T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(119, 3, '2026-11-04', 1, '2026-11-04T08:14:00.0000000', '2026-11-04T17:00:00.0000000', 8.00, 0.00, 14, 0, 'web', NULL, NULL, 'present', NULL),
(120, 4, '2026-11-04', 1, '2026-11-04T07:58:00.0000000', '2026-11-04T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(121, 1, '2026-11-05', 1, '2026-11-05T07:58:00.0000000', '2026-11-05T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(122, 2, '2026-11-05', 1, '2026-11-05T07:51:00.0000000', '2026-11-05T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(123, 3, '2026-11-05', 1, '2026-11-05T07:54:00.0000000', '2026-11-05T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(124, 4, '2026-11-05', 1, '2026-11-05T07:57:00.0000000', '2026-11-05T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(125, 1, '2026-11-06', 1, NULL, NULL, 0.00, 0.00, 0, 0, 'manual', NULL, NULL, 'leave', N'Nghỉ phép năm'),
(126, 2, '2026-11-06', 1, '2026-11-06T08:00:00.0000000', '2026-11-06T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(127, 3, '2026-11-06', 1, '2026-11-06T07:53:00.0000000', '2026-11-06T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(128, 4, '2026-11-06', 1, '2026-11-06T07:56:00.0000000', '2026-11-06T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(129, 1, '2026-11-07', 1, '2026-11-07T07:56:00.0000000', '2026-11-07T19:00:00.0000000', 8.00, 2.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(130, 2, '2026-11-07', 1, '2026-11-07T07:59:00.0000000', '2026-11-07T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(131, 3, '2026-11-07', 1, '2026-11-07T07:52:00.0000000', '2026-11-07T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(132, 4, '2026-11-07', 1, '2026-11-07T07:55:00.0000000', '2026-11-07T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(133, 1, '2026-11-09', 1, '2026-11-09T07:54:00.0000000', '2026-11-09T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(134, 2, '2026-11-09', 1, '2026-11-09T07:57:00.0000000', '2026-11-09T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(135, 3, '2026-11-09', 1, '2026-11-09T08:19:00.0000000', '2026-11-09T17:00:00.0000000', 8.00, 0.00, 19, 0, 'web', NULL, NULL, 'present', NULL),
(136, 4, '2026-11-09', 1, '2026-11-09T07:53:00.0000000', '2026-11-09T12:00:00.0000000', 4.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', N'Xin về sớm (nửa ngày)'),
(137, 1, '2026-11-10', 1, '2026-11-10T07:53:00.0000000', '2026-11-10T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(138, 2, '2026-11-10', 1, '2026-11-10T07:56:00.0000000', '2026-11-10T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(139, 3, '2026-11-10', 1, '2026-11-10T07:59:00.0000000', '2026-11-10T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(140, 4, '2026-11-10', 1, '2026-11-10T07:52:00.0000000', '2026-11-10T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(141, 5, '2026-11-10', 1, '2026-11-10T07:55:00.0000000', '2026-11-10T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(142, 1, '2026-11-11', 1, '2026-11-11T07:52:00.0000000', '2026-11-11T20:00:00.0000000', 8.00, 3.00, 0, 0, 'web', NULL, NULL, 'present', N'Tăng ca sale 11.11'),
(143, 2, '2026-11-11', 1, '2026-11-11T07:55:00.0000000', '2026-11-11T20:00:00.0000000', 8.00, 3.00, 0, 0, 'web', NULL, NULL, 'present', N'Tăng ca sale 11.11'),
(144, 3, '2026-11-11', 1, '2026-11-11T07:58:00.0000000', '2026-11-11T20:00:00.0000000', 8.00, 3.00, 0, 0, 'web', NULL, NULL, 'present', N'Tăng ca sale 11.11'),
(145, 4, '2026-11-11', 1, '2026-11-11T07:51:00.0000000', '2026-11-11T20:00:00.0000000', 8.00, 3.00, 0, 0, 'web', NULL, NULL, 'present', N'Tăng ca sale 11.11'),
(146, 5, '2026-11-11', 1, '2026-11-11T07:54:00.0000000', '2026-11-11T20:00:00.0000000', 8.00, 3.00, 0, 0, 'web', NULL, NULL, 'present', N'Tăng ca sale 11.11'),
(147, 1, '2026-11-12', 1, '2026-11-12T07:51:00.0000000', '2026-11-12T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(148, 2, '2026-11-12', 1, '2026-11-12T07:54:00.0000000', '2026-11-12T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(149, 3, '2026-11-12', 1, '2026-11-12T07:57:00.0000000', '2026-11-12T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(150, 4, '2026-11-12', 1, '2026-11-12T08:00:00.0000000', '2026-11-12T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(151, 5, '2026-11-12', 1, '2026-11-12T07:53:00.0000000', '2026-11-12T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(152, 1, '2026-11-13', 1, '2026-11-13T08:00:00.0000000', '2026-11-13T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(153, 2, '2026-11-13', 1, '2026-11-13T07:53:00.0000000', '2026-11-13T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(154, 3, '2026-11-13', 1, '2026-11-13T07:56:00.0000000', '2026-11-13T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(155, 4, '2026-11-13', 1, '2026-11-13T07:59:00.0000000', '2026-11-13T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(156, 5, '2026-11-13', 1, '2026-11-13T07:52:00.0000000', '2026-11-13T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(157, 1, '2026-11-14', 1, '2026-11-14T07:59:00.0000000', '2026-11-14T19:00:00.0000000', 8.00, 2.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(158, 2, '2026-11-14', 1, '2026-11-14T07:52:00.0000000', '2026-11-14T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(159, 3, '2026-11-14', 1, '2026-11-14T08:24:00.0000000', '2026-11-14T17:00:00.0000000', 8.00, 0.00, 24, 0, 'web', NULL, NULL, 'present', NULL),
(160, 4, '2026-11-14', 1, '2026-11-14T07:58:00.0000000', '2026-11-14T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(161, 5, '2026-11-14', 1, '2026-11-14T07:51:00.0000000', '2026-11-14T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(162, 1, '2026-11-16', 1, '2026-11-16T07:57:00.0000000', '2026-11-16T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(163, 2, '2026-11-16', 1, '2026-11-16T08:00:00.0000000', '2026-11-16T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(164, 3, '2026-11-16', 1, '2026-11-16T07:53:00.0000000', '2026-11-16T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(165, 4, '2026-11-16', 1, '2026-11-16T07:56:00.0000000', '2026-11-16T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(166, 5, '2026-11-16', 1, '2026-11-16T07:59:00.0000000', '2026-11-16T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(167, 1, '2026-11-17', 1, '2026-11-17T07:56:00.0000000', '2026-11-17T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(168, 2, '2026-11-17', 1, '2026-11-17T07:59:00.0000000', '2026-11-17T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(169, 3, '2026-11-17', 1, '2026-11-17T07:52:00.0000000', '2026-11-17T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(170, 4, '2026-11-17', 1, '2026-11-17T07:55:00.0000000', '2026-11-17T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(171, 5, '2026-11-17', 1, '2026-11-17T07:58:00.0000000', '2026-11-17T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(172, 1, '2026-11-18', 1, '2026-11-18T07:55:00.0000000', '2026-11-18T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(173, 2, '2026-11-18', 1, '2026-11-18T07:58:00.0000000', '2026-11-18T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(174, 3, '2026-11-18', 1, '2026-11-18T07:51:00.0000000', '2026-11-18T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(175, 4, '2026-11-18', 1, '2026-11-18T07:54:00.0000000', '2026-11-18T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(176, 5, '2026-11-18', 1, '2026-11-18T07:57:00.0000000', '2026-11-18T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(177, 1, '2026-11-19', 1, '2026-11-19T07:54:00.0000000', '2026-11-19T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(178, 2, '2026-11-19', 1, '2026-11-19T07:57:00.0000000', '2026-11-19T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(179, 3, '2026-11-19', 1, '2026-11-19T08:14:00.0000000', '2026-11-19T17:00:00.0000000', 8.00, 0.00, 14, 0, 'web', NULL, NULL, 'present', NULL),
(180, 4, '2026-11-19', 1, '2026-11-19T07:53:00.0000000', '2026-11-19T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(181, 5, '2026-11-19', 1, '2026-11-19T07:56:00.0000000', '2026-11-19T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(182, 1, '2026-11-20', 1, '2026-11-20T07:53:00.0000000', '2026-11-20T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(183, 2, '2026-11-20', 1, '2026-11-20T07:56:00.0000000', '2026-11-20T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(184, 3, '2026-11-20', 1, '2026-11-20T07:59:00.0000000', '2026-11-20T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(185, 4, '2026-11-20', 1, '2026-11-20T07:52:00.0000000', '2026-11-20T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL),
(186, 5, '2026-11-20', 1, '2026-11-20T07:55:00.0000000', '2026-11-20T17:00:00.0000000', 8.00, 0.00, 0, 0, 'web', NULL, NULL, 'present', NULL)
;
SET IDENTITY_INSERT [hr].[Attendances] OFF;
GO

-- hr.ContractAllowances (6 dòng)
SET IDENTITY_INSERT [hr].[ContractAllowances] ON;
INSERT INTO [hr].[ContractAllowances] ([Id], [ContractId], [Name], [Amount], [IsTaxable], [IsInsurable]) VALUES
(1, 1, N'Phụ cấp ăn trưa, xăng xe', 1000000.00, 0, 0),
(2, 2, N'Phụ cấp ăn trưa, xăng xe', 730000.00, 0, 0),
(3, 3, N'Phụ cấp ăn trưa, xăng xe', 730000.00, 0, 0),
(4, 4, N'Phụ cấp ăn trưa, xăng xe', 730000.00, 0, 0),
(5, 5, N'Phụ cấp ăn trưa, xăng xe', 730000.00, 0, 0),
(6, 6, N'Phụ cấp ăn trưa, xăng xe', 730000.00, 0, 0)
;
SET IDENTITY_INSERT [hr].[ContractAllowances] OFF;
GO

-- hr.Contracts (6 dòng)
SET IDENTITY_INSERT [hr].[Contracts] ON;
INSERT INTO [hr].[Contracts] ([Id], [EmployeeId], [ContractNo], [ContractType], [StartDate], [EndDate], [BaseSalary], [InsuranceSalary], [Status], [SignedAt], [AttachmentId], [Note], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
(1, 1, 'HD-NV-00001-01', 'indefinite', '2025-03-01', NULL, 10000000.00, 10000000.00, 'active', NULL, NULL, NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL),
(2, 2, 'HD-NV-00002-01', 'fixed_term', '2025-09-01', NULL, 6500000.00, 6500000.00, 'active', NULL, NULL, NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL),
(3, 3, 'HD-NV-00003-01', 'fixed_term', '2026-02-15', NULL, 6500000.00, 6500000.00, 'active', NULL, NULL, NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL),
(4, 4, 'HD-NV-00004-01', 'fixed_term', '2025-12-01', NULL, 7500000.00, 7500000.00, 'active', NULL, NULL, NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL),
(5, 5, 'HD-NV-00005-01', 'probation', '2026-11-10', NULL, 5800000.00, 5800000.00, 'active', NULL, NULL, NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL),
(6, 6, 'HD-NV-00006-01', 'fixed_term', '2025-11-01', '2026-09-30', 8000000.00, 8000000.00, 'expired', NULL, NULL, NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL)
;
SET IDENTITY_INSERT [hr].[Contracts] OFF;
GO

-- hr.Employees (6 dòng)
SET IDENTITY_INSERT [hr].[Employees] ON;
INSERT INTO [hr].[Employees] ([Id], [CompanyId], [Code], [UserId], [FullName], [Gender], [DateOfBirth], [IdNumber], [IdIssuedDate], [IdIssuedPlace], [Phone], [PersonalEmail], [WorkEmail], [PermanentAddress], [CurrentAddress], [BranchId], [DepartmentId], [PositionId], [ManagerId], [HireDate], [OfficialDate], [TerminationDate], [EmploymentStatus], [PersonalTaxCode], [SocialInsuranceNo], [Dependents], [BankName], [BankAccountNo], [AvatarUrl], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'NV-00001', 2, N'Trần Thị Hồng Nhung', 'F', '1992-04-12', NULL, NULL, NULL, '0912340001', NULL, NULL, NULL, NULL, NULL, 10, 1, NULL, '2025-03-01', NULL, NULL, 'official', NULL, NULL, 1, N'Vietcombank', '0021000111001', NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL, 0),
(2, 1, 'NV-00002', 3, N'Lê Minh Châu', 'F', '1999-08-25', NULL, NULL, NULL, '0912340002', NULL, NULL, NULL, NULL, NULL, 10, 2, NULL, '2025-09-01', NULL, NULL, 'official', NULL, NULL, 0, N'Vietcombank', '0021000111002', NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL, 0),
(3, 1, 'NV-00003', 4, N'Phạm Đức Anh', 'M', '2000-01-30', NULL, NULL, NULL, '0912340003', NULL, NULL, NULL, NULL, NULL, 10, 2, NULL, '2026-02-15', NULL, NULL, 'official', NULL, NULL, 0, N'Vietcombank', '0021000111003', NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL, 0),
(4, 1, 'NV-00004', 5, N'Nguyễn Thảo Vy', 'F', '1998-11-05', NULL, NULL, NULL, '0912340004', NULL, NULL, NULL, NULL, NULL, 2, 3, NULL, '2025-12-01', NULL, NULL, 'official', NULL, NULL, 0, N'Vietcombank', '0021000111004', NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL, 0),
(5, 1, 'NV-00005', 6, N'Hoàng Văn Tùng', 'M', '2002-06-18', NULL, NULL, NULL, '0912340005', NULL, NULL, NULL, NULL, NULL, 5, 4, NULL, '2026-11-10', NULL, NULL, 'probation', NULL, NULL, 0, NULL, NULL, NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL, 0),
(6, 1, 'NV-00006', 7, N'Vũ Thanh Mai', 'F', '1997-03-09', NULL, NULL, NULL, '0912340006', NULL, NULL, NULL, NULL, NULL, 3, 6, NULL, '2025-11-01', NULL, '2026-09-30', 'resigned', NULL, NULL, 0, NULL, NULL, NULL, '2026-11-21T00:55:41.0730000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [hr].[Employees] OFF;
GO

-- hr.LeaveBalances (5 dòng)
INSERT INTO [hr].[LeaveBalances] ([EmployeeId], [LeaveTypeId], [LeaveYear], [EntitledDays], [CarriedDays], [UsedDays]) VALUES
(1, 1, 2026, 12.00, 0.00, 1.00),
(2, 1, 2026, 12.00, 0.00, 2.00),
(3, 1, 2026, 12.00, 0.00, 0.00),
(4, 1, 2026, 12.00, 0.00, 0.00),
(5, 1, 2026, 12.00, 0.00, 0.00)
;
GO

-- hr.LeaveRequests (4 dòng)
SET IDENTITY_INSERT [hr].[LeaveRequests] ON;
INSERT INTO [hr].[LeaveRequests] ([Id], [EmployeeId], [LeaveTypeId], [FromDate], [ToDate], [Days], [Reason], [Status], [ApproverUserId], [ApprovedAt], [RejectReason], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
(1, 1, 1, '2026-11-06T00:00:00.0000000', '2026-11-06T23:59:00.0000000', 1.00, N'Đi khám sức khỏe', 'approved', 1, '2026-11-03T00:00:00.0000000', NULL, '2026-11-01T00:00:00.0000000', 1, NULL, NULL),
(2, 2, 1, '2026-10-20T00:00:00.0000000', '2026-10-21T23:59:00.0000000', 2.00, N'Về quê dự đám cưới', 'approved', 1, '2026-10-17T00:00:00.0000000', NULL, '2026-10-15T00:00:00.0000000', 1, NULL, NULL),
(3, 3, 1, '2026-11-11T00:00:00.0000000', '2026-11-11T23:59:00.0000000', 1.00, N'Đi chơi', 'rejected', 1, '2026-11-08T00:00:00.0000000', N'Trùng ngày sale 11.11, cửa hàng cần đủ người', '2026-11-06T00:00:00.0000000', 1, NULL, NULL),
(4, 4, 1, '2026-11-25T00:00:00.0000000', '2026-11-26T23:59:00.0000000', 2.00, N'Việc gia đình', 'submitted', NULL, NULL, NULL, '2026-11-20T00:00:00.0000000', 1, NULL, NULL)
;
SET IDENTITY_INSERT [hr].[LeaveRequests] OFF;
GO

-- hr.LeaveTypes (6 dòng)
SET IDENTITY_INSERT [hr].[LeaveTypes] ON;
INSERT INTO [hr].[LeaveTypes] ([Id], [CompanyId], [Code], [Name], [IsPaid], [DefaultDaysPerYear]) VALUES
(1, 1, 'ANNUAL', N'Nghỉ phép năm', 1, 12.00),
(2, 1, 'SICK', N'Nghỉ ốm', 1, 0.00),
(3, 1, 'MATERNITY', N'Nghỉ thai sản', 1, 0.00),
(4, 1, 'WEDDING', N'Nghỉ kết hôn', 1, 3.00),
(5, 1, 'FUNERAL', N'Nghỉ tang', 1, 3.00),
(6, 1, 'UNPAID', N'Nghỉ không lương', 0, 0.00)
;
SET IDENTITY_INSERT [hr].[LeaveTypes] OFF;
GO

-- hr.PayrollPeriods (1 dòng)
SET IDENTITY_INSERT [hr].[PayrollPeriods] ON;
INSERT INTO [hr].[PayrollPeriods] ([Id], [CompanyId], [PeriodYear], [PeriodMonth], [StandardDays], [Status], [JournalEntryId], [ApprovedBy], [ApprovedAt], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy]) VALUES
(1, 1, 2026, 10, 26.00, 'paid', NULL, 1, '2026-11-03T00:00:00.0000000', '2026-11-01T00:00:00.0000000', 1, NULL, NULL)
;
SET IDENTITY_INSERT [hr].[PayrollPeriods] OFF;
GO

-- hr.Payslips (4 dòng)
SET IDENTITY_INSERT [hr].[Payslips] ON;
INSERT INTO [hr].[Payslips] ([Id], [PayrollPeriodId], [EmployeeId], [ContractId], [ActualDays], [PaidLeaveDays], [OvertimeHours], [BaseSalary], [TotalAllowance], [OvertimePay], [Bonus], [GrossIncome], [SocialInsurance], [HealthInsurance], [UnemploymentInsurance], [UnionFee], [TaxableIncome], [PersonalIncomeTax], [Advance], [OtherDeductions], [NetPay], [EmployerInsurance], [Status], [PaidAt]) VALUES
(1, 1, 1, 1, 27.00, 0.00, 10.00, 10000000.00, 1000000.00, 721154.00, 0.00, 11721154.00, 800000.00, 150000.00, 100000.00, 0.00, 0.00, 0.00, 0.00, 0.00, 10671154.00, 2150000.00, 'paid', '2026-11-05T00:00:00.0000000'),
(2, 1, 2, 2, 24.00, 2.00, 0.00, 6500000.00, 730000.00, 0.00, 0.00, 7230000.00, 520000.00, 97500.00, 65000.00, 0.00, 0.00, 0.00, 0.00, 0.00, 6547500.00, 1397500.00, 'paid', '2026-11-05T00:00:00.0000000'),
(3, 1, 3, 3, 27.00, 0.00, 0.00, 6500000.00, 730000.00, 0.00, 0.00, 7230000.00, 520000.00, 97500.00, 65000.00, 0.00, 0.00, 0.00, 0.00, 0.00, 6547500.00, 1397500.00, 'paid', '2026-11-05T00:00:00.0000000'),
(4, 1, 4, 4, 27.00, 0.00, 0.00, 7500000.00, 730000.00, 0.00, 0.00, 8230000.00, 600000.00, 112500.00, 75000.00, 0.00, 0.00, 0.00, 0.00, 0.00, 7442500.00, 1612500.00, 'paid', '2026-11-05T00:00:00.0000000')
;
SET IDENTITY_INSERT [hr].[Payslips] OFF;
GO

-- hr.Positions (6 dòng)
SET IDENTITY_INSERT [hr].[Positions] ON;
INSERT INTO [hr].[Positions] ([Id], [CompanyId], [Code], [Name], [DepartmentId], [IsActive]) VALUES
(1, 1, 'CHT', N'Cửa hàng trưởng', NULL, 1),
(2, 1, 'NVBH', N'Nhân viên bán hàng', NULL, 1),
(3, 1, 'NVOL', N'Nhân viên bán online', NULL, 1),
(4, 1, 'NVK', N'Nhân viên kho', NULL, 1),
(5, 1, 'KT', N'Kế toán', NULL, 1),
(6, 1, 'MKT', N'Nhân viên marketing', NULL, 1)
;
SET IDENTITY_INSERT [hr].[Positions] OFF;
GO

-- hr.WorkShifts (1 dòng)
SET IDENTITY_INSERT [hr].[WorkShifts] ON;
INSERT INTO [hr].[WorkShifts] ([Id], [CompanyId], [Code], [Name], [StartTime], [EndTime], [BreakMinutes], [WorkDayValue]) VALUES
(1, 1, 'HC', N'Hành chính', '08:00:00.0000000', '17:00:00.0000000', 60, 1.00)
;
SET IDENTITY_INSERT [hr].[WorkShifts] OFF;
GO

-- inv.StockBalances (168 dòng)
SET IDENTITY_INSERT [inv].[StockBalances] ON;
INSERT INTO [inv].[StockBalances] ([Id], [CompanyId], [WarehouseId], [ProductId], [LocationId], [LotId], [QtyOnHand], [QtyReserved], [QtyIncoming], [AvgCost], [UpdatedAt]) VALUES
(1, 1, 1, 1, NULL, NULL, 4.0000, 0.0000, 0.0000, 80000.0000, '2026-11-20T09:42:54.7200000'),
(2, 1, 1, 2, NULL, NULL, 4.0000, 0.0000, 0.0000, 80000.0000, '2026-11-20T09:42:54.7200000'),
(3, 1, 1, 3, NULL, NULL, 5.0000, 0.0000, 0.0000, 80000.0000, '2026-11-20T09:42:54.7200000'),
(4, 1, 1, 4, NULL, NULL, 6.0000, 0.0000, 0.0000, 150000.0000, '2026-11-20T09:42:54.7200000'),
(5, 1, 1, 5, NULL, NULL, 10.0000, 0.0000, 0.0000, 150000.0000, '2026-11-20T15:17:41.0770000'),
(6, 1, 1, 6, NULL, NULL, 12.0000, 0.0000, 0.0000, 150000.0000, '2026-11-20T09:42:54.7200000'),
(7, 1, 1, 7, NULL, NULL, 5.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(8, 1, 1, 8, NULL, NULL, 8.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(9, 1, 1, 9, NULL, NULL, 11.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(10, 1, 1, 10, NULL, NULL, 1.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(11, 1, 1, 11, NULL, NULL, 7.0000, 0.0000, 0.0000, 110000.0000, '2026-11-20T09:42:54.7200000'),
(12, 1, 1, 12, NULL, NULL, 6.0000, 0.0000, 0.0000, 110000.0000, '2026-11-20T09:42:54.7200000'),
(13, 1, 1, 13, NULL, NULL, 2.0000, 0.0000, 0.0000, 110000.0000, '2026-11-20T09:42:54.7200000'),
(14, 1, 1, 14, NULL, NULL, 6.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(15, 1, 1, 15, NULL, NULL, 9.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(16, 1, 1, 16, NULL, NULL, 12.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(17, 1, 1, 17, NULL, NULL, 5.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(18, 1, 1, 18, NULL, NULL, 8.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(19, 1, 1, 19, NULL, NULL, 11.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(20, 1, 1, 20, NULL, NULL, 1.0000, 0.0000, 0.0000, 220000.0000, '2026-11-20T09:42:54.7200000'),
(21, 1, 1, 21, NULL, NULL, 4.0000, 0.0000, 0.0000, 220000.0000, '2026-11-20T09:42:54.7200000'),
(22, 1, 1, 22, NULL, NULL, 10.0000, 0.0000, 0.0000, 220000.0000, '2026-11-20T09:42:54.7200000'),
(23, 1, 1, 23, NULL, NULL, 2.0000, 0.0000, 0.0000, 220000.0000, '2026-11-20T09:42:54.7200000'),
(24, 1, 1, 24, NULL, NULL, 8.0000, 0.0000, 0.0000, 220000.0000, '2026-11-20T09:42:54.7200000'),
(25, 1, 1, 25, NULL, NULL, 9.0000, 0.0000, 0.0000, 45000.0000, '2026-11-20T09:42:54.7200000'),
(26, 1, 1, 26, NULL, NULL, 4.0000, 0.0000, 0.0000, 28000.0000, '2026-11-20T09:42:54.7200000'),
(27, 1, 1, 27, NULL, NULL, 5.0000, 0.0000, 0.0000, 450000.0000, '2026-11-20T09:42:54.7200000'),
(28, 1, 1, 28, NULL, NULL, 4.0000, 0.0000, 0.0000, 450000.0000, '2026-11-20T09:42:54.7200000'),
(29, 1, 1, 29, NULL, NULL, 10.0000, 0.0000, 0.0000, 450000.0000, '2026-11-20T09:42:54.7200000'),
(30, 1, 1, 30, NULL, NULL, 1.0000, 0.0000, 0.0000, 450000.0000, '2026-11-20T09:42:54.7200000'),
(31, 1, 1, 31, NULL, NULL, 8.0000, 0.0000, 0.0000, 450000.0000, '2026-11-20T09:42:54.7200000'),
(32, 1, 1, 32, NULL, NULL, 10.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(33, 1, 1, 33, NULL, NULL, 5.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(34, 1, 1, 34, NULL, NULL, 6.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(35, 1, 1, 35, NULL, NULL, 9.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(36, 1, 1, 36, NULL, NULL, 12.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(37, 1, 1, 37, NULL, NULL, 5.0000, 0.0000, 0.0000, 95000.0000, '2026-11-20T09:42:54.7200000'),
(38, 1, 1, 38, NULL, NULL, 8.0000, 0.0000, 0.0000, 45000.0000, '2026-11-20T09:42:54.7200000'),
(39, 1, 1, 39, NULL, NULL, 11.0000, 0.0000, 0.0000, 190000.0000, '2026-11-20T09:42:54.7200000'),
(40, 1, 1, 40, NULL, NULL, 1.0000, 0.0000, 0.0000, 260000.0000, '2026-11-20T09:42:54.7200000'),
(41, 1, 1, 41, NULL, NULL, 5.0000, 0.0000, 0.0000, 260000.0000, '2026-11-20T09:42:54.7200000'),
(42, 1, 1, 42, NULL, NULL, 4.0000, 0.0000, 0.0000, 260000.0000, '2026-11-20T09:42:54.7200000'),
(43, 1, 1, 43, NULL, NULL, 2.0000, 0.0000, 0.0000, 110000.0000, '2026-11-20T09:42:54.7200000'),
(44, 1, 1, 44, NULL, NULL, 9.0000, 0.0000, 0.0000, 110000.0000, '2026-11-20T09:42:54.7200000'),
(45, 1, 1, 45, NULL, NULL, 8.0000, 0.0000, 0.0000, 110000.0000, '2026-11-20T09:42:54.7200000'),
(46, 1, 1, 46, NULL, NULL, 4.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(47, 1, 1, 47, NULL, NULL, 5.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(48, 1, 1, 48, NULL, NULL, 4.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(49, 1, 1, 49, NULL, NULL, 5.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(50, 1, 1, 50, NULL, NULL, 3.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(51, 1, 1, 51, NULL, NULL, 5.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(52, 1, 1, 52, NULL, NULL, 4.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(53, 1, 1, 53, NULL, NULL, 3.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(54, 1, 1, 54, NULL, NULL, 6.0000, 0.0000, 0.0000, 220000.0000, '2026-11-20T09:42:54.7200000'),
(55, 1, 1, 55, NULL, NULL, 5.0000, 0.0000, 0.0000, 220000.0000, '2026-11-20T09:42:54.7200000'),
(56, 1, 1, 56, NULL, NULL, 4.0000, 0.0000, 0.0000, 220000.0000, '2026-11-20T09:42:54.7200000'),
(57, 1, 1, 57, NULL, NULL, 10.0000, 0.0000, 0.0000, 220000.0000, '2026-11-20T09:42:54.7200000'),
(58, 1, 1, 58, NULL, NULL, 9.0000, 0.0000, 0.0000, 220000.0000, '2026-11-20T09:42:54.7200000'),
(59, 1, 1, 59, NULL, NULL, 11.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(60, 1, 1, 60, NULL, NULL, 1.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(61, 1, 1, 61, NULL, NULL, 7.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(62, 1, 1, 62, NULL, NULL, 10.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(63, 1, 1, 63, NULL, NULL, 5.0000, 0.0000, 0.0000, 185000.0000, '2026-11-20T09:42:54.7200000'),
(64, 1, 1, 64, NULL, NULL, 6.0000, 0.0000, 0.0000, 185000.0000, '2026-11-20T09:42:54.7200000'),
(65, 1, 1, 65, NULL, NULL, 9.0000, 0.0000, 0.0000, 185000.0000, '2026-11-20T09:42:54.7200000'),
(66, 1, 1, 66, NULL, NULL, 12.0000, 0.0000, 0.0000, 70000.0000, '2026-11-20T09:42:54.7200000'),
(67, 1, 1, 67, NULL, NULL, 5.0000, 0.0000, 0.0000, 70000.0000, '2026-11-20T09:42:54.7200000'),
(68, 1, 1, 68, NULL, NULL, 8.0000, 0.0000, 0.0000, 70000.0000, '2026-11-20T09:42:54.7200000'),
(69, 1, 1, 69, NULL, NULL, 5.0000, 0.0000, 0.0000, 200000.0000, '2026-11-20T09:42:54.7200000'),
(70, 1, 1, 70, NULL, NULL, 2.0000, 0.0000, 0.0000, 200000.0000, '2026-11-20T09:42:54.7200000'),
(71, 1, 1, 71, NULL, NULL, 5.0000, 0.0000, 0.0000, 200000.0000, '2026-11-20T09:42:54.7200000'),
(72, 1, 1, 72, NULL, NULL, 5.0000, 0.0000, 0.0000, 200000.0000, '2026-11-20T09:42:54.7200000'),
(73, 1, 1, 73, NULL, NULL, 2.0000, 0.0000, 0.0000, 200000.0000, '2026-11-20T09:42:54.7200000'),
(74, 1, 1, 74, NULL, NULL, 5.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(75, 1, 1, 75, NULL, NULL, 4.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(76, 1, 1, 76, NULL, NULL, 4.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(77, 1, 1, 77, NULL, NULL, 4.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(78, 1, 1, 78, NULL, NULL, 8.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(79, 1, 1, 79, NULL, NULL, 11.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(80, 1, 1, 80, NULL, NULL, 5.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(81, 1, 1, 81, NULL, NULL, 7.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(82, 1, 1, 82, NULL, NULL, 4.0000, 0.0000, 0.0000, 80000.0000, '2026-11-20T09:42:54.7200000'),
(83, 1, 1, 83, NULL, NULL, 5.0000, 0.0000, 0.0000, 80000.0000, '2026-11-20T09:42:54.7200000'),
(84, 1, 1, 84, NULL, NULL, 4.0000, 0.0000, 0.0000, 80000.0000, '2026-11-20T09:42:54.7200000'),
(85, 1, 1, 85, NULL, NULL, 9.0000, 0.0000, 0.0000, 160000.0000, '2026-11-20T09:42:54.7200000'),
(86, 1, 1, 86, NULL, NULL, 12.0000, 0.0000, 0.0000, 160000.0000, '2026-11-20T09:42:54.7200000'),
(87, 1, 1, 87, NULL, NULL, 5.0000, 0.0000, 0.0000, 160000.0000, '2026-11-20T09:42:54.7200000'),
(88, 1, 1, 88, NULL, NULL, 8.0000, 0.0000, 0.0000, 150000.0000, '2026-11-20T09:42:54.7200000'),
(89, 1, 1, 89, NULL, NULL, 11.0000, 0.0000, 0.0000, 150000.0000, '2026-11-20T09:42:54.7200000'),
(90, 1, 1, 90, NULL, NULL, 1.0000, 0.0000, 0.0000, 150000.0000, '2026-11-20T09:42:54.7200000'),
(91, 1, 1, 91, NULL, NULL, 8.0000, 0.0000, 0.0000, 120000.0000, '2026-11-20T15:17:41.0770000'),
(92, 1, 1, 92, NULL, NULL, 10.0000, 0.0000, 0.0000, 160000.0000, '2026-11-20T09:42:54.7200000'),
(93, 1, 1, 93, NULL, NULL, 2.0000, 0.0000, 0.0000, 160000.0000, '2026-11-20T09:42:54.7200000'),
(94, 1, 1, 94, NULL, NULL, 6.0000, 0.0000, 0.0000, 160000.0000, '2026-11-20T09:42:54.7200000'),
(95, 1, 1, 95, NULL, NULL, 9.0000, 0.0000, 0.0000, 190000.0000, '2026-11-20T09:42:54.7200000'),
(96, 1, 1, 96, NULL, NULL, 12.0000, 0.0000, 0.0000, 190000.0000, '2026-11-20T09:42:54.7200000'),
(97, 1, 1, 97, NULL, NULL, 5.0000, 0.0000, 0.0000, 450000.0000, '2026-11-20T09:42:54.7200000'),
(98, 1, 1, 98, NULL, NULL, 4.0000, 0.0000, 0.0000, 450000.0000, '2026-11-20T09:42:54.7200000'),
(99, 1, 1, 99, NULL, NULL, 10.0000, 0.0000, 0.0000, 450000.0000, '2026-11-20T09:42:54.7200000'),
(100, 1, 1, 100, NULL, NULL, 1.0000, 0.0000, 0.0000, 450000.0000, '2026-11-20T09:42:54.7200000'),
(101, 1, 1, 101, NULL, NULL, 8.0000, 0.0000, 0.0000, 450000.0000, '2026-11-20T09:42:54.7200000'),
(102, 1, 1, 102, NULL, NULL, 4.0000, 0.0000, 0.0000, 28000.0000, '2026-11-20T09:42:54.7200000'),
(103, 1, 1, 103, NULL, NULL, 4.0000, 0.0000, 0.0000, 120000.0000, '2026-11-20T09:42:54.7200000'),
(104, 1, 1, 104, NULL, NULL, 5.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(105, 1, 1, 105, NULL, NULL, 4.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(106, 1, 1, 106, NULL, NULL, 4.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(107, 1, 1, 107, NULL, NULL, 4.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(108, 1, 1, 108, NULL, NULL, 4.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(109, 1, 1, 109, NULL, NULL, 5.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(110, 1, 1, 110, NULL, NULL, 2.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(111, 1, 1, 111, NULL, NULL, 5.0000, 0.0000, 0.0000, 310000.0000, '2026-11-20T09:42:54.7200000'),
(112, 1, 1, 112, NULL, NULL, 4.0000, 0.0000, 0.0000, 80000.0000, '2026-11-20T09:42:54.7200000'),
(113, 1, 1, 113, NULL, NULL, 3.0000, 0.0000, 0.0000, 80000.0000, '2026-11-20T09:42:54.7200000'),
(114, 1, 1, 114, NULL, NULL, 5.0000, 0.0000, 0.0000, 80000.0000, '2026-11-20T09:42:54.7200000'),
(115, 1, 1, 115, NULL, NULL, 4.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(116, 1, 1, 116, NULL, NULL, 5.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(117, 1, 1, 117, NULL, NULL, 4.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(118, 1, 1, 118, NULL, NULL, 5.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(119, 1, 1, 119, NULL, NULL, 11.0000, 0.0000, 0.0000, 140000.0000, '2026-11-20T09:42:54.7200000'),
(120, 1, 1, 120, NULL, NULL, 1.0000, 0.0000, 0.0000, 140000.0000, '2026-11-20T09:42:54.7200000'),
(121, 1, 1, 121, NULL, NULL, 7.0000, 0.0000, 0.0000, 140000.0000, '2026-11-20T09:42:54.7200000'),
(122, 1, 1, 122, NULL, NULL, 10.0000, 0.0000, 0.0000, 140000.0000, '2026-11-20T09:42:54.7200000'),
(123, 1, 1, 123, NULL, NULL, 5.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(124, 1, 1, 124, NULL, NULL, 6.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(125, 1, 1, 125, NULL, NULL, 9.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(126, 1, 1, 126, NULL, NULL, 12.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(127, 1, 1, 127, NULL, NULL, 5.0000, 0.0000, 0.0000, 150000.0000, '2026-11-20T09:42:54.7200000'),
(128, 1, 1, 128, NULL, NULL, 8.0000, 0.0000, 0.0000, 150000.0000, '2026-11-20T09:42:54.7200000'),
(129, 1, 1, 129, NULL, NULL, 11.0000, 0.0000, 0.0000, 150000.0000, '2026-11-20T09:42:54.7200000'),
(130, 1, 1, 130, NULL, NULL, 1.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(131, 1, 1, 131, NULL, NULL, 5.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(132, 1, 1, 132, NULL, NULL, 5.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(133, 1, 1, 133, NULL, NULL, 2.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(134, 1, 1, 134, NULL, NULL, 6.0000, 0.0000, 0.0000, 70000.0000, '2026-11-20T09:42:54.7200000'),
(135, 1, 1, 135, NULL, NULL, 9.0000, 0.0000, 0.0000, 70000.0000, '2026-11-20T09:42:54.7200000'),
(136, 1, 1, 136, NULL, NULL, 12.0000, 0.0000, 0.0000, 70000.0000, '2026-11-20T09:42:54.7200000'),
(137, 1, 1, 137, NULL, NULL, 5.0000, 0.0000, 0.0000, 160000.0000, '2026-11-20T09:42:54.7200000'),
(138, 1, 1, 138, NULL, NULL, 8.0000, 0.0000, 0.0000, 160000.0000, '2026-11-20T09:42:54.7200000'),
(139, 1, 1, 139, NULL, NULL, 11.0000, 0.0000, 0.0000, 160000.0000, '2026-11-20T09:42:54.7200000'),
(140, 1, 1, 140, NULL, NULL, 5.0000, 0.0000, 0.0000, 120000.0000, '2026-11-20T09:42:54.7200000'),
(141, 1, 1, 141, NULL, NULL, 7.0000, 0.0000, 0.0000, 140000.0000, '2026-11-20T09:42:54.7200000'),
(142, 1, 1, 142, NULL, NULL, 10.0000, 0.0000, 0.0000, 140000.0000, '2026-11-20T09:42:54.7200000'),
(143, 1, 1, 143, NULL, NULL, 2.0000, 0.0000, 0.0000, 140000.0000, '2026-11-20T09:42:54.7200000'),
(144, 1, 1, 144, NULL, NULL, 6.0000, 0.0000, 0.0000, 140000.0000, '2026-11-20T09:42:54.7200000'),
(145, 1, 1, 145, NULL, NULL, 5.0000, 0.0000, 0.0000, 200000.0000, '2026-11-20T09:42:54.7200000'),
(146, 1, 1, 146, NULL, NULL, 5.0000, 0.0000, 0.0000, 200000.0000, '2026-11-20T09:42:54.7200000'),
(147, 1, 1, 147, NULL, NULL, 5.0000, 0.0000, 0.0000, 200000.0000, '2026-11-20T09:42:54.7200000'),
(148, 1, 1, 148, NULL, NULL, 5.0000, 0.0000, 0.0000, 200000.0000, '2026-11-20T09:42:54.7200000'),
(149, 1, 1, 149, NULL, NULL, 5.0000, 0.0000, 0.0000, 200000.0000, '2026-11-20T09:42:54.7200000'),
(150, 1, 1, 150, NULL, NULL, 4.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(151, 1, 1, 151, NULL, NULL, 5.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(152, 1, 1, 152, NULL, NULL, 4.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(153, 1, 1, 153, NULL, NULL, 4.0000, 0.0000, 0.0000, 65000.0000, '2026-11-20T09:42:54.7200000'),
(154, 1, 1, 154, NULL, NULL, 6.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(155, 1, 1, 155, NULL, NULL, 9.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(156, 1, 1, 156, NULL, NULL, 12.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(157, 1, 1, 157, NULL, NULL, 5.0000, 0.0000, 0.0000, 105000.0000, '2026-11-20T09:42:54.7200000'),
(158, 1, 1, 158, NULL, NULL, 8.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(159, 1, 1, 159, NULL, NULL, 11.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(160, 1, 1, 160, NULL, NULL, 1.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(161, 1, 1, 161, NULL, NULL, 7.0000, 0.0000, 0.0000, 165000.0000, '2026-11-20T09:42:54.7200000'),
(162, 1, 1, 162, NULL, NULL, 10.0000, 0.0000, 0.0000, 45000.0000, '2026-11-20T09:42:54.7200000'),
(163, 1, 1, 163, NULL, NULL, 2.0000, 0.0000, 0.0000, 185000.0000, '2026-11-20T09:42:54.7200000'),
(164, 1, 1, 164, NULL, NULL, 6.0000, 0.0000, 0.0000, 185000.0000, '2026-11-20T09:42:54.7200000'),
(165, 1, 1, 165, NULL, NULL, 9.0000, 0.0000, 0.0000, 185000.0000, '2026-11-20T09:42:54.7200000'),
(166, 1, 1, 166, NULL, NULL, 6.0000, 0.0000, 0.0000, 260000.0000, '2026-11-20T09:42:54.7200000'),
(167, 1, 1, 167, NULL, NULL, 5.0000, 0.0000, 0.0000, 260000.0000, '2026-11-20T09:42:54.7200000'),
(168, 1, 1, 168, NULL, NULL, 4.0000, 0.0000, 0.0000, 260000.0000, '2026-11-20T09:42:54.7200000')
;
SET IDENTITY_INSERT [inv].[StockBalances] OFF;
GO

-- inv.StockDocumentLines (520 dòng)
SET IDENTITY_INSERT [inv].[StockDocumentLines] ON;
INSERT INTO [inv].[StockDocumentLines] ([Id], [DocumentId], [LineNumber], [ProductId], [LotId], [LocationId], [DestLocationId], [UomId], [Quantity], [BaseQuantity], [UnitCost], [LineValue], [SourceLineId], [Note]) VALUES
(1, 1, 1, 1, NULL, NULL, NULL, 1, 3.0000, 3.0000, 80000.0000, 240000.00, 1, NULL),
(2, 1, 2, 2, NULL, NULL, NULL, 1, 4.0000, 4.0000, 80000.0000, 320000.00, 2, NULL),
(3, 1, 3, 3, NULL, NULL, NULL, 1, 4.0000, 4.0000, 80000.0000, 320000.00, 3, NULL),
(4, 1, 4, 25, NULL, NULL, NULL, 1, 4.0000, 4.0000, 45000.0000, 180000.00, 4, NULL),
(5, 1, 5, 26, NULL, NULL, NULL, 12, 5.0000, 5.0000, 28000.0000, 140000.00, 5, NULL),
(6, 1, 6, 38, NULL, NULL, NULL, 1, 4.0000, 4.0000, 45000.0000, 180000.00, 6, NULL),
(7, 1, 7, 40, NULL, NULL, NULL, 1, 1.0000, 1.0000, 260000.0000, 260000.00, 7, NULL),
(8, 1, 8, 41, NULL, NULL, NULL, 1, 5.0000, 5.0000, 260000.0000, 1300000.00, 8, NULL),
(9, 1, 9, 42, NULL, NULL, NULL, 1, 5.0000, 5.0000, 260000.0000, 1300000.00, 9, NULL),
(10, 1, 10, 66, NULL, NULL, NULL, 1, 3.0000, 3.0000, 70000.0000, 210000.00, 10, NULL),
(11, 1, 11, 67, NULL, NULL, NULL, 1, 5.0000, 5.0000, 70000.0000, 350000.00, 11, NULL),
(12, 1, 12, 68, NULL, NULL, NULL, 1, 3.0000, 3.0000, 70000.0000, 210000.00, 12, NULL),
(13, 1, 13, 74, NULL, NULL, NULL, 1, 4.0000, 4.0000, 65000.0000, 260000.00, 13, NULL),
(14, 1, 14, 75, NULL, NULL, NULL, 1, 5.0000, 5.0000, 65000.0000, 325000.00, 14, NULL),
(15, 1, 15, 76, NULL, NULL, NULL, 1, 4.0000, 4.0000, 65000.0000, 260000.00, 15, NULL),
(16, 1, 16, 77, NULL, NULL, NULL, 1, 4.0000, 4.0000, 65000.0000, 260000.00, 16, NULL),
(17, 1, 17, 78, NULL, NULL, NULL, 1, 5.0000, 5.0000, 105000.0000, 525000.00, 17, NULL),
(18, 1, 18, 79, NULL, NULL, NULL, 1, 3.0000, 3.0000, 105000.0000, 315000.00, 18, NULL),
(19, 1, 19, 80, NULL, NULL, NULL, 1, 3.0000, 3.0000, 105000.0000, 315000.00, 19, NULL),
(20, 1, 20, 81, NULL, NULL, NULL, 1, 3.0000, 3.0000, 105000.0000, 315000.00, 20, NULL),
(21, 1, 21, 82, NULL, NULL, NULL, 1, 4.0000, 4.0000, 80000.0000, 320000.00, 21, NULL),
(22, 1, 22, 83, NULL, NULL, NULL, 1, 4.0000, 4.0000, 80000.0000, 320000.00, 22, NULL),
(23, 1, 23, 84, NULL, NULL, NULL, 1, 5.0000, 5.0000, 80000.0000, 400000.00, 23, NULL),
(24, 1, 24, 91, NULL, NULL, NULL, 1, 3.0000, 3.0000, 120000.0000, 360000.00, 24, NULL),
(25, 1, 25, 102, NULL, NULL, NULL, 12, 4.0000, 4.0000, 28000.0000, 112000.00, 25, NULL),
(26, 1, 26, 103, NULL, NULL, NULL, 1, 4.0000, 4.0000, 120000.0000, 480000.00, 26, NULL),
(27, 1, 27, 112, NULL, NULL, NULL, 1, 3.0000, 3.0000, 80000.0000, 240000.00, 27, NULL),
(28, 1, 28, 113, NULL, NULL, NULL, 1, 5.0000, 5.0000, 80000.0000, 400000.00, 28, NULL),
(29, 1, 29, 114, NULL, NULL, NULL, 1, 4.0000, 4.0000, 80000.0000, 320000.00, 29, NULL),
(30, 1, 30, 115, NULL, NULL, NULL, 1, 5.0000, 5.0000, 65000.0000, 325000.00, 30, NULL),
(31, 1, 31, 116, NULL, NULL, NULL, 1, 3.0000, 3.0000, 65000.0000, 195000.00, 31, NULL),
(32, 1, 32, 117, NULL, NULL, NULL, 1, 6.0000, 6.0000, 65000.0000, 390000.00, 32, NULL),
(33, 1, 33, 118, NULL, NULL, NULL, 1, 3.0000, 3.0000, 65000.0000, 195000.00, 33, NULL),
(34, 1, 34, 123, NULL, NULL, NULL, 1, 3.0000, 3.0000, 105000.0000, 315000.00, 34, NULL),
(35, 1, 35, 124, NULL, NULL, NULL, 1, 3.0000, 3.0000, 105000.0000, 315000.00, 35, NULL),
(36, 1, 36, 125, NULL, NULL, NULL, 1, 3.0000, 3.0000, 105000.0000, 315000.00, 36, NULL),
(37, 1, 37, 126, NULL, NULL, NULL, 1, 4.0000, 4.0000, 105000.0000, 420000.00, 37, NULL),
(38, 1, 38, 130, NULL, NULL, NULL, 1, 6.0000, 6.0000, 65000.0000, 390000.00, 38, NULL),
(39, 1, 39, 131, NULL, NULL, NULL, 1, 4.0000, 4.0000, 65000.0000, 260000.00, 39, NULL),
(40, 1, 40, 132, NULL, NULL, NULL, 1, 4.0000, 4.0000, 65000.0000, 260000.00, 40, NULL),
(41, 1, 41, 133, NULL, NULL, NULL, 1, 3.0000, 3.0000, 65000.0000, 195000.00, 41, NULL),
(42, 1, 42, 134, NULL, NULL, NULL, 1, 3.0000, 3.0000, 70000.0000, 210000.00, 42, NULL),
(43, 1, 43, 135, NULL, NULL, NULL, 1, 4.0000, 4.0000, 70000.0000, 280000.00, 43, NULL),
(44, 1, 44, 136, NULL, NULL, NULL, 1, 4.0000, 4.0000, 70000.0000, 280000.00, 44, NULL),
(45, 1, 45, 140, NULL, NULL, NULL, 1, 3.0000, 3.0000, 120000.0000, 360000.00, 45, NULL),
(46, 1, 46, 150, NULL, NULL, NULL, 1, 5.0000, 5.0000, 65000.0000, 325000.00, 46, NULL),
(47, 1, 47, 151, NULL, NULL, NULL, 1, 3.0000, 3.0000, 65000.0000, 195000.00, 47, NULL),
(48, 1, 48, 152, NULL, NULL, NULL, 1, 3.0000, 3.0000, 65000.0000, 195000.00, 48, NULL),
(49, 1, 49, 153, NULL, NULL, NULL, 1, 5.0000, 5.0000, 65000.0000, 325000.00, 49, NULL),
(50, 1, 50, 154, NULL, NULL, NULL, 1, 3.0000, 3.0000, 105000.0000, 315000.00, 50, NULL),
(51, 1, 51, 155, NULL, NULL, NULL, 1, 4.0000, 4.0000, 105000.0000, 420000.00, 51, NULL),
(52, 1, 52, 156, NULL, NULL, NULL, 1, 5.0000, 5.0000, 105000.0000, 525000.00, 52, NULL),
(53, 1, 53, 157, NULL, NULL, NULL, 1, 3.0000, 3.0000, 105000.0000, 315000.00, 53, NULL),
(54, 1, 54, 162, NULL, NULL, NULL, 1, 4.0000, 4.0000, 45000.0000, 180000.00, 54, NULL),
(55, 1, 55, 166, NULL, NULL, NULL, 1, 6.0000, 6.0000, 260000.0000, 1560000.00, 55, NULL),
(56, 1, 56, 167, NULL, NULL, NULL, 1, 9.0000, 9.0000, 260000.0000, 2340000.00, 56, NULL),
(57, 1, 57, 168, NULL, NULL, NULL, 1, 4.0000, 4.0000, 260000.0000, 1040000.00, 57, NULL),
(58, 2, 1, 4, NULL, NULL, NULL, 1, 8.0000, 8.0000, 150000.0000, 1200000.00, 58, NULL),
(59, 2, 2, 5, NULL, NULL, NULL, 1, 12.0000, 12.0000, 150000.0000, 1800000.00, 59, NULL),
(60, 2, 3, 6, NULL, NULL, NULL, 1, 12.0000, 12.0000, 150000.0000, 1800000.00, 60, NULL),
(61, 2, 4, 7, NULL, NULL, NULL, 1, 5.0000, 5.0000, 165000.0000, 825000.00, 61, NULL),
(62, 2, 5, 8, NULL, NULL, NULL, 1, 11.0000, 11.0000, 165000.0000, 1815000.00, 62, NULL),
(63, 2, 6, 9, NULL, NULL, NULL, 1, 16.0000, 16.0000, 165000.0000, 2640000.00, 63, NULL),
(64, 2, 7, 10, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 64, NULL),
(65, 2, 8, 11, NULL, NULL, NULL, 1, 7.0000, 7.0000, 110000.0000, 770000.00, 65, NULL),
(66, 2, 9, 12, NULL, NULL, NULL, 1, 8.0000, 8.0000, 110000.0000, 880000.00, 66, NULL),
(67, 2, 10, 13, NULL, NULL, NULL, 1, 2.0000, 2.0000, 110000.0000, 220000.00, 67, NULL),
(68, 2, 11, 39, NULL, NULL, NULL, 1, 14.0000, 14.0000, 190000.0000, 2660000.00, 68, NULL),
(69, 2, 12, 43, NULL, NULL, NULL, 1, 2.0000, 2.0000, 110000.0000, 220000.00, 69, NULL),
(70, 2, 13, 44, NULL, NULL, NULL, 1, 11.0000, 11.0000, 110000.0000, 1210000.00, 70, NULL),
(71, 2, 14, 45, NULL, NULL, NULL, 1, 8.0000, 8.0000, 110000.0000, 880000.00, 71, NULL),
(72, 2, 15, 59, NULL, NULL, NULL, 1, 11.0000, 11.0000, 165000.0000, 1815000.00, 72, NULL),
(73, 2, 16, 60, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 73, NULL),
(74, 2, 17, 61, NULL, NULL, NULL, 1, 8.0000, 8.0000, 165000.0000, 1320000.00, 74, NULL),
(75, 2, 18, 62, NULL, NULL, NULL, 1, 13.0000, 13.0000, 165000.0000, 2145000.00, 75, NULL),
(76, 2, 19, 85, NULL, NULL, NULL, 1, 9.0000, 9.0000, 160000.0000, 1440000.00, 76, NULL),
(77, 2, 20, 86, NULL, NULL, NULL, 1, 14.0000, 14.0000, 160000.0000, 2240000.00, 77, NULL),
(78, 2, 21, 87, NULL, NULL, NULL, 1, 7.0000, 7.0000, 160000.0000, 1120000.00, 78, NULL),
(79, 2, 22, 88, NULL, NULL, NULL, 1, 8.0000, 8.0000, 150000.0000, 1200000.00, 79, NULL),
(80, 2, 23, 89, NULL, NULL, NULL, 1, 11.0000, 11.0000, 150000.0000, 1650000.00, 80, NULL),
(81, 2, 24, 90, NULL, NULL, NULL, 1, 2.0000, 2.0000, 150000.0000, 300000.00, 81, NULL),
(82, 2, 25, 92, NULL, NULL, NULL, 1, 12.0000, 12.0000, 160000.0000, 1920000.00, 82, NULL),
(83, 2, 26, 93, NULL, NULL, NULL, 1, 2.0000, 2.0000, 160000.0000, 320000.00, 83, NULL),
(84, 2, 27, 94, NULL, NULL, NULL, 1, 9.0000, 9.0000, 160000.0000, 1440000.00, 84, NULL),
(85, 2, 28, 95, NULL, NULL, NULL, 1, 9.0000, 9.0000, 190000.0000, 1710000.00, 85, NULL),
(86, 2, 29, 96, NULL, NULL, NULL, 1, 13.0000, 13.0000, 190000.0000, 2470000.00, 86, NULL),
(87, 2, 30, 119, NULL, NULL, NULL, 1, 11.0000, 11.0000, 140000.0000, 1540000.00, 87, NULL),
(88, 2, 31, 120, NULL, NULL, NULL, 1, 7.0000, 7.0000, 140000.0000, 980000.00, 88, NULL),
(89, 2, 32, 121, NULL, NULL, NULL, 1, 7.0000, 7.0000, 140000.0000, 980000.00, 89, NULL),
(90, 2, 33, 122, NULL, NULL, NULL, 1, 11.0000, 11.0000, 140000.0000, 1540000.00, 90, NULL),
(91, 2, 34, 127, NULL, NULL, NULL, 1, 8.0000, 8.0000, 150000.0000, 1200000.00, 91, NULL),
(92, 2, 35, 128, NULL, NULL, NULL, 1, 8.0000, 8.0000, 150000.0000, 1200000.00, 92, NULL),
(93, 2, 36, 129, NULL, NULL, NULL, 1, 13.0000, 13.0000, 150000.0000, 1950000.00, 93, NULL),
(94, 2, 37, 137, NULL, NULL, NULL, 1, 6.0000, 6.0000, 160000.0000, 960000.00, 94, NULL),
(95, 2, 38, 138, NULL, NULL, NULL, 1, 10.0000, 10.0000, 160000.0000, 1600000.00, 95, NULL),
(96, 2, 39, 139, NULL, NULL, NULL, 1, 16.0000, 16.0000, 160000.0000, 2560000.00, 96, NULL),
(97, 2, 40, 141, NULL, NULL, NULL, 1, 8.0000, 8.0000, 140000.0000, 1120000.00, 97, NULL),
(98, 2, 41, 142, NULL, NULL, NULL, 1, 12.0000, 12.0000, 140000.0000, 1680000.00, 98, NULL),
(99, 2, 42, 143, NULL, NULL, NULL, 1, 5.0000, 5.0000, 140000.0000, 700000.00, 99, NULL),
(100, 2, 43, 144, NULL, NULL, NULL, 1, 6.0000, 6.0000, 140000.0000, 840000.00, 100, NULL),
(101, 2, 44, 158, NULL, NULL, NULL, 1, 10.0000, 10.0000, 165000.0000, 1650000.00, 101, NULL),
(102, 2, 45, 159, NULL, NULL, NULL, 1, 14.0000, 14.0000, 165000.0000, 2310000.00, 102, NULL),
(103, 2, 46, 160, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 103, NULL),
(104, 2, 47, 161, NULL, NULL, NULL, 1, 8.0000, 8.0000, 165000.0000, 1320000.00, 104, NULL),
(105, 3, 1, 63, NULL, NULL, NULL, 1, 4.0000, 4.0000, 185000.0000, 740000.00, 105, NULL),
(106, 3, 2, 64, NULL, NULL, NULL, 1, 3.0000, 3.0000, 185000.0000, 555000.00, 106, NULL),
(107, 3, 3, 65, NULL, NULL, NULL, 1, 4.0000, 4.0000, 185000.0000, 740000.00, 107, NULL),
(108, 3, 4, 69, NULL, NULL, NULL, 1, 7.0000, 7.0000, 200000.0000, 1400000.00, 108, NULL),
(109, 3, 5, 70, NULL, NULL, NULL, 1, 4.0000, 4.0000, 200000.0000, 800000.00, 109, NULL),
(110, 3, 6, 71, NULL, NULL, NULL, 1, 5.0000, 5.0000, 200000.0000, 1000000.00, 110, NULL),
(111, 3, 7, 72, NULL, NULL, NULL, 1, 4.0000, 4.0000, 200000.0000, 800000.00, 111, NULL),
(112, 3, 8, 73, NULL, NULL, NULL, 1, 6.0000, 6.0000, 200000.0000, 1200000.00, 112, NULL),
(113, 3, 9, 145, NULL, NULL, NULL, 1, 3.0000, 3.0000, 200000.0000, 600000.00, 113, NULL),
(114, 3, 10, 146, NULL, NULL, NULL, 1, 6.0000, 6.0000, 200000.0000, 1200000.00, 114, NULL),
(115, 3, 11, 147, NULL, NULL, NULL, 1, 3.0000, 3.0000, 200000.0000, 600000.00, 115, NULL),
(116, 3, 12, 148, NULL, NULL, NULL, 1, 7.0000, 7.0000, 200000.0000, 1400000.00, 116, NULL),
(117, 3, 13, 149, NULL, NULL, NULL, 1, 3.0000, 3.0000, 200000.0000, 600000.00, 117, NULL),
(118, 3, 14, 163, NULL, NULL, NULL, 1, 3.0000, 3.0000, 185000.0000, 555000.00, 118, NULL),
(119, 3, 15, 164, NULL, NULL, NULL, 1, 3.0000, 3.0000, 185000.0000, 555000.00, 119, NULL),
(120, 3, 16, 165, NULL, NULL, NULL, 1, 5.0000, 5.0000, 185000.0000, 925000.00, 120, NULL),
(121, 4, 1, 14, NULL, NULL, NULL, 21, 5.0000, 5.0000, 95000.0000, 475000.00, 121, NULL),
(122, 4, 2, 15, NULL, NULL, NULL, 21, 3.0000, 3.0000, 95000.0000, 285000.00, 122, NULL),
(123, 4, 3, 16, NULL, NULL, NULL, 21, 3.0000, 3.0000, 95000.0000, 285000.00, 123, NULL),
(124, 4, 4, 17, NULL, NULL, NULL, 21, 5.0000, 5.0000, 95000.0000, 475000.00, 124, NULL),
(125, 4, 5, 18, NULL, NULL, NULL, 21, 3.0000, 3.0000, 95000.0000, 285000.00, 125, NULL),
(126, 4, 6, 19, NULL, NULL, NULL, 21, 3.0000, 3.0000, 95000.0000, 285000.00, 126, NULL),
(127, 4, 7, 20, NULL, NULL, NULL, 21, 2.0000, 2.0000, 220000.0000, 440000.00, 127, NULL),
(128, 4, 8, 21, NULL, NULL, NULL, 21, 4.0000, 4.0000, 220000.0000, 880000.00, 128, NULL),
(129, 4, 9, 22, NULL, NULL, NULL, 21, 14.0000, 14.0000, 220000.0000, 3080000.00, 129, NULL),
(130, 4, 10, 23, NULL, NULL, NULL, 21, 2.0000, 2.0000, 220000.0000, 440000.00, 130, NULL),
(131, 4, 11, 24, NULL, NULL, NULL, 21, 8.0000, 8.0000, 220000.0000, 1760000.00, 131, NULL),
(132, 4, 12, 27, NULL, NULL, NULL, 21, 5.0000, 5.0000, 450000.0000, 2250000.00, 132, NULL),
(133, 4, 13, 28, NULL, NULL, NULL, 21, 4.0000, 4.0000, 450000.0000, 1800000.00, 133, NULL),
(134, 4, 14, 29, NULL, NULL, NULL, 21, 10.0000, 10.0000, 450000.0000, 4500000.00, 134, NULL),
(135, 4, 15, 30, NULL, NULL, NULL, 21, 1.0000, 1.0000, 450000.0000, 450000.00, 135, NULL),
(136, 4, 16, 31, NULL, NULL, NULL, 21, 10.0000, 10.0000, 450000.0000, 4500000.00, 136, NULL),
(137, 4, 17, 32, NULL, NULL, NULL, 21, 5.0000, 5.0000, 95000.0000, 475000.00, 137, NULL),
(138, 4, 18, 33, NULL, NULL, NULL, 21, 3.0000, 3.0000, 95000.0000, 285000.00, 138, NULL),
(139, 4, 19, 34, NULL, NULL, NULL, 21, 5.0000, 5.0000, 95000.0000, 475000.00, 139, NULL),
(140, 4, 20, 35, NULL, NULL, NULL, 21, 3.0000, 3.0000, 95000.0000, 285000.00, 140, NULL),
(141, 4, 21, 36, NULL, NULL, NULL, 21, 5.0000, 5.0000, 95000.0000, 475000.00, 141, NULL),
(142, 4, 22, 37, NULL, NULL, NULL, 21, 3.0000, 3.0000, 95000.0000, 285000.00, 142, NULL),
(143, 4, 23, 46, NULL, NULL, NULL, 21, 3.0000, 3.0000, 310000.0000, 930000.00, 143, NULL),
(144, 4, 24, 47, NULL, NULL, NULL, 21, 6.0000, 6.0000, 310000.0000, 1860000.00, 144, NULL),
(145, 4, 25, 48, NULL, NULL, NULL, 21, 3.0000, 3.0000, 310000.0000, 930000.00, 145, NULL),
(146, 4, 26, 49, NULL, NULL, NULL, 21, 3.0000, 3.0000, 310000.0000, 930000.00, 146, NULL),
(147, 4, 27, 50, NULL, NULL, NULL, 21, 4.0000, 4.0000, 310000.0000, 1240000.00, 147, NULL),
(148, 4, 28, 51, NULL, NULL, NULL, 21, 3.0000, 3.0000, 310000.0000, 930000.00, 148, NULL),
(149, 4, 29, 52, NULL, NULL, NULL, 21, 3.0000, 3.0000, 310000.0000, 930000.00, 149, NULL),
(150, 4, 30, 53, NULL, NULL, NULL, 21, 3.0000, 3.0000, 310000.0000, 930000.00, 150, NULL),
(151, 4, 31, 54, NULL, NULL, NULL, 21, 6.0000, 6.0000, 220000.0000, 1320000.00, 151, NULL),
(152, 4, 32, 55, NULL, NULL, NULL, 21, 5.0000, 5.0000, 220000.0000, 1100000.00, 152, NULL),
(153, 4, 33, 56, NULL, NULL, NULL, 21, 5.0000, 5.0000, 220000.0000, 1100000.00, 153, NULL),
(154, 4, 34, 57, NULL, NULL, NULL, 21, 10.0000, 10.0000, 220000.0000, 2200000.00, 154, NULL),
(155, 4, 35, 58, NULL, NULL, NULL, 21, 12.0000, 12.0000, 220000.0000, 2640000.00, 155, NULL),
(156, 4, 36, 97, NULL, NULL, NULL, 21, 7.0000, 7.0000, 450000.0000, 3150000.00, 156, NULL),
(157, 4, 37, 98, NULL, NULL, NULL, 21, 4.0000, 4.0000, 450000.0000, 1800000.00, 157, NULL),
(158, 4, 38, 99, NULL, NULL, NULL, 21, 13.0000, 13.0000, 450000.0000, 5850000.00, 158, NULL),
(159, 4, 39, 100, NULL, NULL, NULL, 21, 1.0000, 1.0000, 450000.0000, 450000.00, 159, NULL),
(160, 4, 40, 101, NULL, NULL, NULL, 21, 8.0000, 8.0000, 450000.0000, 3600000.00, 160, NULL),
(161, 4, 41, 104, NULL, NULL, NULL, 21, 4.0000, 4.0000, 310000.0000, 1240000.00, 161, NULL),
(162, 4, 42, 105, NULL, NULL, NULL, 21, 3.0000, 3.0000, 310000.0000, 930000.00, 162, NULL),
(163, 4, 43, 106, NULL, NULL, NULL, 21, 7.0000, 7.0000, 310000.0000, 2170000.00, 163, NULL),
(164, 4, 44, 107, NULL, NULL, NULL, 21, 4.0000, 4.0000, 310000.0000, 1240000.00, 164, NULL),
(165, 4, 45, 108, NULL, NULL, NULL, 21, 5.0000, 5.0000, 310000.0000, 1550000.00, 165, NULL),
(166, 4, 46, 109, NULL, NULL, NULL, 21, 4.0000, 4.0000, 310000.0000, 1240000.00, 166, NULL),
(167, 4, 47, 110, NULL, NULL, NULL, 21, 6.0000, 6.0000, 310000.0000, 1860000.00, 167, NULL),
(168, 4, 48, 111, NULL, NULL, NULL, 21, 3.0000, 3.0000, 310000.0000, 930000.00, 168, NULL),
(169, 5, 1, 1, NULL, NULL, NULL, 1, 2.0000, 2.0000, 80000.0000, 160000.00, 169, NULL),
(170, 5, 2, 2, NULL, NULL, NULL, 1, 5.0000, 5.0000, 80000.0000, 400000.00, 170, NULL),
(171, 5, 3, 3, NULL, NULL, NULL, 1, 2.0000, 2.0000, 80000.0000, 160000.00, 171, NULL),
(172, 5, 4, 25, NULL, NULL, NULL, 1, 6.0000, 6.0000, 45000.0000, 270000.00, 172, NULL),
(173, 5, 5, 26, NULL, NULL, NULL, 12, 3.0000, 3.0000, 28000.0000, 84000.00, 173, NULL),
(174, 5, 6, 38, NULL, NULL, NULL, 1, 6.0000, 6.0000, 45000.0000, 270000.00, 174, NULL),
(175, 5, 7, 66, NULL, NULL, NULL, 1, 9.0000, 9.0000, 70000.0000, 630000.00, 175, NULL),
(176, 5, 8, 67, NULL, NULL, NULL, 1, 2.0000, 2.0000, 70000.0000, 140000.00, 176, NULL),
(177, 5, 9, 68, NULL, NULL, NULL, 1, 8.0000, 8.0000, 70000.0000, 560000.00, 177, NULL),
(178, 5, 10, 74, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 178, NULL),
(179, 5, 11, 75, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 179, NULL),
(180, 5, 12, 76, NULL, NULL, NULL, 1, 4.0000, 4.0000, 65000.0000, 260000.00, 180, NULL),
(181, 5, 13, 77, NULL, NULL, NULL, 1, 4.0000, 4.0000, 65000.0000, 260000.00, 181, NULL),
(182, 5, 14, 78, NULL, NULL, NULL, 1, 7.0000, 7.0000, 105000.0000, 735000.00, 182, NULL),
(183, 5, 15, 79, NULL, NULL, NULL, 1, 8.0000, 8.0000, 105000.0000, 840000.00, 183, NULL),
(184, 5, 16, 80, NULL, NULL, NULL, 1, 2.0000, 2.0000, 105000.0000, 210000.00, 184, NULL),
(185, 5, 17, 81, NULL, NULL, NULL, 1, 5.0000, 5.0000, 105000.0000, 525000.00, 185, NULL),
(186, 5, 18, 82, NULL, NULL, NULL, 1, 3.0000, 3.0000, 80000.0000, 240000.00, 186, NULL),
(187, 5, 19, 83, NULL, NULL, NULL, 1, 2.0000, 2.0000, 80000.0000, 160000.00, 187, NULL),
(188, 5, 20, 84, NULL, NULL, NULL, 1, 5.0000, 5.0000, 80000.0000, 400000.00, 188, NULL),
(189, 5, 21, 91, NULL, NULL, NULL, 1, 6.0000, 6.0000, 120000.0000, 720000.00, 189, NULL),
(190, 5, 22, 102, NULL, NULL, NULL, 12, 3.0000, 3.0000, 28000.0000, 84000.00, 190, NULL),
(191, 5, 23, 103, NULL, NULL, NULL, 1, 2.0000, 2.0000, 120000.0000, 240000.00, 191, NULL),
(192, 5, 24, 112, NULL, NULL, NULL, 1, 3.0000, 3.0000, 80000.0000, 240000.00, 192, NULL),
(193, 5, 25, 113, NULL, NULL, NULL, 1, 2.0000, 2.0000, 80000.0000, 160000.00, 193, NULL),
(194, 5, 26, 114, NULL, NULL, NULL, 1, 2.0000, 2.0000, 80000.0000, 160000.00, 194, NULL),
(195, 5, 27, 115, NULL, NULL, NULL, 1, 3.0000, 3.0000, 65000.0000, 195000.00, 195, NULL),
(196, 5, 28, 116, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 196, NULL),
(197, 5, 29, 117, NULL, NULL, NULL, 1, 4.0000, 4.0000, 65000.0000, 260000.00, 197, NULL),
(198, 5, 30, 118, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 198, NULL),
(199, 5, 31, 123, NULL, NULL, NULL, 1, 2.0000, 2.0000, 105000.0000, 210000.00, 199, NULL),
(200, 5, 32, 124, NULL, NULL, NULL, 1, 6.0000, 6.0000, 105000.0000, 630000.00, 200, NULL),
(201, 5, 33, 125, NULL, NULL, NULL, 1, 7.0000, 7.0000, 105000.0000, 735000.00, 201, NULL),
(202, 5, 34, 126, NULL, NULL, NULL, 1, 9.0000, 9.0000, 105000.0000, 945000.00, 202, NULL),
(203, 5, 35, 130, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 203, NULL),
(204, 5, 36, 131, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 204, NULL),
(205, 5, 37, 132, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 205, NULL),
(206, 5, 38, 133, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 206, NULL),
(207, 5, 39, 134, NULL, NULL, NULL, 1, 4.0000, 4.0000, 70000.0000, 280000.00, 207, NULL),
(208, 5, 40, 135, NULL, NULL, NULL, 1, 8.0000, 8.0000, 70000.0000, 560000.00, 208, NULL),
(209, 5, 41, 136, NULL, NULL, NULL, 1, 11.0000, 11.0000, 70000.0000, 770000.00, 209, NULL),
(210, 5, 42, 140, NULL, NULL, NULL, 1, 2.0000, 2.0000, 120000.0000, 240000.00, 210, NULL),
(211, 5, 43, 150, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 211, NULL),
(212, 5, 44, 151, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 212, NULL),
(213, 5, 45, 152, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 213, NULL),
(214, 5, 46, 153, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 214, NULL),
(215, 5, 47, 154, NULL, NULL, NULL, 1, 5.0000, 5.0000, 105000.0000, 525000.00, 215, NULL),
(216, 5, 48, 155, NULL, NULL, NULL, 1, 6.0000, 6.0000, 105000.0000, 630000.00, 216, NULL),
(217, 5, 49, 156, NULL, NULL, NULL, 1, 12.0000, 12.0000, 105000.0000, 1260000.00, 217, NULL),
(218, 5, 50, 157, NULL, NULL, NULL, 1, 3.0000, 3.0000, 105000.0000, 315000.00, 218, NULL),
(219, 5, 51, 162, NULL, NULL, NULL, 1, 8.0000, 8.0000, 45000.0000, 360000.00, 219, NULL),
(220, 6, 1, 63, NULL, NULL, NULL, 1, 2.0000, 2.0000, 185000.0000, 370000.00, 220, NULL),
(221, 6, 2, 64, NULL, NULL, NULL, 1, 4.0000, 4.0000, 185000.0000, 740000.00, 221, NULL),
(222, 6, 3, 65, NULL, NULL, NULL, 1, 6.0000, 6.0000, 185000.0000, 1110000.00, 222, NULL),
(223, 6, 4, 69, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 223, NULL),
(224, 6, 5, 70, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 224, NULL),
(225, 6, 6, 71, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 225, NULL),
(226, 6, 7, 72, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 226, NULL),
(227, 6, 8, 73, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 227, NULL),
(228, 6, 9, 145, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 228, NULL),
(229, 6, 10, 146, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 229, NULL),
(230, 6, 11, 147, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 230, NULL),
(231, 6, 12, 148, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 231, NULL),
(232, 6, 13, 149, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 232, NULL),
(233, 6, 14, 163, NULL, NULL, NULL, 1, 2.0000, 2.0000, 185000.0000, 370000.00, 233, NULL),
(234, 6, 15, 164, NULL, NULL, NULL, 1, 4.0000, 4.0000, 185000.0000, 740000.00, 234, NULL),
(235, 6, 16, 165, NULL, NULL, NULL, 1, 8.0000, 8.0000, 185000.0000, 1480000.00, 235, NULL),
(236, 7, 1, 14, NULL, NULL, NULL, 21, 4.0000, 4.0000, 95000.0000, 380000.00, 236, NULL),
(237, 7, 2, 15, NULL, NULL, NULL, 21, 6.0000, 6.0000, 95000.0000, 570000.00, 237, NULL),
(238, 7, 3, 16, NULL, NULL, NULL, 21, 10.0000, 10.0000, 95000.0000, 950000.00, 238, NULL),
(239, 7, 4, 17, NULL, NULL, NULL, 21, 2.0000, 2.0000, 95000.0000, 190000.00, 239, NULL),
(240, 7, 5, 18, NULL, NULL, NULL, 21, 5.0000, 5.0000, 95000.0000, 475000.00, 240, NULL),
(241, 7, 6, 19, NULL, NULL, NULL, 21, 8.0000, 8.0000, 95000.0000, 760000.00, 241, NULL),
(242, 7, 7, 32, NULL, NULL, NULL, 21, 8.0000, 8.0000, 95000.0000, 760000.00, 242, NULL),
(243, 7, 8, 33, NULL, NULL, NULL, 21, 2.0000, 2.0000, 95000.0000, 190000.00, 243, NULL),
(244, 7, 9, 34, NULL, NULL, NULL, 21, 4.0000, 4.0000, 95000.0000, 380000.00, 244, NULL),
(245, 7, 10, 35, NULL, NULL, NULL, 21, 9.0000, 9.0000, 95000.0000, 855000.00, 245, NULL),
(246, 7, 11, 36, NULL, NULL, NULL, 21, 12.0000, 12.0000, 95000.0000, 1140000.00, 246, NULL),
(247, 7, 12, 37, NULL, NULL, NULL, 21, 2.0000, 2.0000, 95000.0000, 190000.00, 247, NULL),
(248, 7, 13, 46, NULL, NULL, NULL, 21, 4.0000, 4.0000, 310000.0000, 1240000.00, 248, NULL),
(249, 7, 14, 47, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 249, NULL),
(250, 7, 15, 48, NULL, NULL, NULL, 21, 5.0000, 5.0000, 310000.0000, 1550000.00, 250, NULL),
(251, 7, 16, 49, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 251, NULL),
(252, 7, 17, 50, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 252, NULL),
(253, 7, 18, 51, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 253, NULL),
(254, 7, 19, 52, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 254, NULL),
(255, 7, 20, 53, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 255, NULL),
(256, 7, 21, 104, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 256, NULL),
(257, 7, 22, 105, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 257, NULL),
(258, 7, 23, 106, NULL, NULL, NULL, 21, 3.0000, 3.0000, 310000.0000, 930000.00, 258, NULL),
(259, 7, 24, 107, NULL, NULL, NULL, 21, 3.0000, 3.0000, 310000.0000, 930000.00, 259, NULL),
(260, 7, 25, 108, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 260, NULL),
(261, 7, 26, 109, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 261, NULL),
(262, 7, 27, 110, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 262, NULL),
(263, 7, 28, 111, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 263, NULL),
(264, 8, 1, 5, NULL, NULL, NULL, 1, 1.0000, 1.0000, 150000.0000, 150000.00, 1, NULL),
(265, 8, 2, 75, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 2, NULL),
(266, 8, 3, 131, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 3, NULL),
(267, 9, 1, 146, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 4, NULL),
(268, 9, 2, 47, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 5, NULL),
(269, 10, 1, 62, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 6, NULL),
(270, 10, 2, 117, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 7, NULL),
(271, 11, 1, 106, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 8, NULL),
(272, 11, 2, 158, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 9, NULL),
(273, 12, 1, 94, NULL, NULL, NULL, 1, 2.0000, 2.0000, 160000.0000, 320000.00, 10, NULL),
(274, 13, 1, 69, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 11, NULL),
(275, 14, 1, 136, NULL, NULL, NULL, 1, 1.0000, 1.0000, 70000.0000, 70000.00, 12, NULL),
(276, 15, 1, 14, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 13, NULL),
(277, 16, 1, 110, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 14, NULL),
(278, 16, 2, 165, NULL, NULL, NULL, 1, 1.0000, 1.0000, 185000.0000, 185000.00, 15, NULL),
(279, 16, 3, 70, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 16, NULL),
(280, 17, 1, 58, NULL, NULL, NULL, 21, 2.0000, 2.0000, 220000.0000, 440000.00, 17, NULL),
(281, 17, 2, 114, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 18, NULL),
(282, 17, 3, 3, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 19, NULL),
(283, 18, 1, 143, NULL, NULL, NULL, 1, 1.0000, 1.0000, 140000.0000, 140000.00, 20, NULL),
(284, 18, 2, 44, NULL, NULL, NULL, 1, 1.0000, 1.0000, 110000.0000, 110000.00, 21, NULL),
(285, 19, 1, 22, NULL, NULL, NULL, 21, 1.0000, 1.0000, 220000.0000, 220000.00, 22, NULL),
(286, 20, 1, 73, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 25, NULL),
(287, 21, 1, 9, NULL, NULL, NULL, 1, 2.0000, 2.0000, 165000.0000, 330000.00, 26, NULL),
(288, 22, 1, 108, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 28, NULL),
(289, 22, 2, 162, NULL, NULL, NULL, 1, 1.0000, 1.0000, 45000.0000, 45000.00, 29, NULL),
(290, 22, 3, 67, NULL, NULL, NULL, 1, 2.0000, 2.0000, 70000.0000, 140000.00, 30, NULL),
(291, 23, 1, 148, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 31, NULL),
(292, 23, 2, 50, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 32, NULL),
(293, 23, 3, 109, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 33, NULL),
(294, 24, 1, 139, NULL, NULL, NULL, 1, 2.0000, 2.0000, 160000.0000, 320000.00, 34, NULL),
(295, 24, 2, 38, NULL, NULL, NULL, 1, 1.0000, 1.0000, 45000.0000, 45000.00, 35, NULL),
(296, 25, 1, 99, NULL, NULL, NULL, 21, 1.0000, 1.0000, 450000.0000, 450000.00, 36, NULL),
(297, 26, 1, 113, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 37, NULL),
(298, 27, 1, 17, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 38, NULL),
(299, 28, 1, 71, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 39, NULL),
(300, 29, 1, 146, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 40, NULL),
(301, 29, 2, 47, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 41, NULL),
(302, 29, 3, 107, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 42, NULL),
(303, 30, 1, 62, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 43, NULL),
(304, 30, 2, 117, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 44, NULL),
(305, 31, 1, 106, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 45, NULL),
(306, 31, 2, 158, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 46, NULL),
(307, 31, 3, 63, NULL, NULL, NULL, 1, 1.0000, 1.0000, 185000.0000, 185000.00, 47, NULL),
(308, 32, 1, 26, NULL, NULL, NULL, 12, 1.0000, 1.0000, 28000.0000, 28000.00, 48, NULL),
(309, 32, 2, 90, NULL, NULL, NULL, 1, 1.0000, 1.0000, 150000.0000, 150000.00, 49, NULL),
(310, 33, 1, 76, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 50, NULL),
(311, 33, 2, 132, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 51, NULL),
(312, 34, 1, 110, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 52, NULL),
(313, 35, 1, 14, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 53, NULL),
(314, 36, 1, 69, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 54, NULL),
(315, 37, 1, 150, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 55, NULL),
(316, 38, 1, 103, NULL, NULL, NULL, 1, 1.0000, 1.0000, 120000.0000, 120000.00, 56, NULL),
(317, 38, 2, 155, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 57, NULL),
(318, 39, 1, 143, NULL, NULL, NULL, 1, 1.0000, 1.0000, 140000.0000, 140000.00, 58, NULL),
(319, 39, 2, 44, NULL, NULL, NULL, 1, 1.0000, 1.0000, 110000.0000, 110000.00, 59, NULL),
(320, 39, 3, 104, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 60, NULL),
(321, 40, 1, 22, NULL, NULL, NULL, 21, 2.0000, 2.0000, 220000.0000, 440000.00, 61, NULL),
(322, 40, 2, 86, NULL, NULL, NULL, 1, 1.0000, 1.0000, 160000.0000, 160000.00, 62, NULL),
(323, 41, 1, 73, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 63, NULL),
(324, 41, 2, 130, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 64, NULL),
(325, 42, 1, 115, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 65, NULL),
(326, 42, 2, 4, NULL, NULL, NULL, 1, 1.0000, 1.0000, 150000.0000, 150000.00, 66, NULL),
(327, 43, 1, 32, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 67, NULL),
(328, 44, 1, 108, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 68, NULL),
(329, 45, 1, 148, NULL, NULL, NULL, 1, 2.0000, 2.0000, 200000.0000, 400000.00, 69, NULL),
(330, 46, 1, 65, NULL, NULL, NULL, 1, 1.0000, 1.0000, 185000.0000, 185000.00, 70, NULL),
(331, 47, 1, 78, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 71, NULL),
(332, 47, 2, 135, NULL, NULL, NULL, 1, 1.0000, 1.0000, 70000.0000, 70000.00, 72, NULL),
(333, 47, 3, 34, NULL, NULL, NULL, 21, 2.0000, 2.0000, 95000.0000, 190000.00, 73, NULL),
(334, 48, 1, 17, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 74, NULL),
(335, 48, 2, 83, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 75, NULL),
(336, 48, 3, 141, NULL, NULL, NULL, 1, 1.0000, 1.0000, 140000.0000, 140000.00, 76, NULL),
(337, 49, 1, 71, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 77, NULL),
(338, 49, 2, 126, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 78, NULL),
(339, 50, 1, 153, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 81, NULL),
(340, 51, 1, 106, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 82, NULL),
(341, 52, 1, 146, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 86, NULL),
(342, 53, 1, 117, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 87, NULL),
(343, 53, 2, 8, NULL, NULL, NULL, 1, 2.0000, 2.0000, 165000.0000, 330000.00, 88, NULL),
(344, 53, 3, 77, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 89, NULL),
(345, 54, 1, 26, NULL, NULL, NULL, 12, 1.0000, 1.0000, 28000.0000, 28000.00, 90, NULL),
(346, 55, 1, 150, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 91, NULL),
(347, 56, 1, 69, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 92, NULL),
(348, 57, 1, 36, NULL, NULL, NULL, 21, 2.0000, 2.0000, 95000.0000, 190000.00, 93, NULL),
(349, 58, 1, 110, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 94, NULL),
(350, 58, 2, 165, NULL, NULL, NULL, 1, 1.0000, 1.0000, 185000.0000, 185000.00, 95, NULL),
(351, 59, 1, 82, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 96, NULL),
(352, 60, 1, 22, NULL, NULL, NULL, 21, 1.0000, 1.0000, 220000.0000, 220000.00, 97, NULL),
(353, 60, 2, 86, NULL, NULL, NULL, 1, 1.0000, 1.0000, 160000.0000, 160000.00, 98, NULL),
(354, 61, 1, 156, NULL, NULL, NULL, 1, 2.0000, 2.0000, 105000.0000, 210000.00, 99, NULL),
(355, 61, 2, 61, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 100, NULL),
(356, 62, 1, 73, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 101, NULL),
(357, 62, 2, 130, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 102, NULL),
(358, 62, 3, 25, NULL, NULL, NULL, 1, 1.0000, 1.0000, 45000.0000, 45000.00, 103, NULL),
(359, 63, 1, 115, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 104, NULL),
(360, 63, 2, 4, NULL, NULL, NULL, 1, 1.0000, 1.0000, 150000.0000, 150000.00, 105, NULL),
(361, 63, 3, 74, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 106, NULL),
(362, 64, 1, 78, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 108, NULL),
(363, 65, 1, 148, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 109, NULL),
(364, 66, 1, 32, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 110, NULL),
(365, 67, 1, 120, NULL, NULL, NULL, 1, 2.0000, 2.0000, 140000.0000, 280000.00, 111, NULL),
(366, 68, 1, 39, NULL, NULL, NULL, 1, 1.0000, 1.0000, 190000.0000, 190000.00, 114, NULL),
(367, 68, 2, 102, NULL, NULL, NULL, 12, 1.0000, 1.0000, 28000.0000, 28000.00, 115, NULL),
(368, 69, 1, 113, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 116, NULL),
(369, 69, 2, 2, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 117, NULL),
(370, 69, 3, 72, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 118, NULL),
(371, 70, 1, 153, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 119, NULL),
(372, 70, 2, 56, NULL, NULL, NULL, 21, 1.0000, 1.0000, 220000.0000, 220000.00, 120, NULL),
(373, 71, 1, 84, NULL, NULL, NULL, 1, 2.0000, 2.0000, 80000.0000, 160000.00, 121, NULL),
(374, 71, 2, 142, NULL, NULL, NULL, 1, 1.0000, 1.0000, 140000.0000, 140000.00, 122, NULL),
(375, 72, 1, 76, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 123, NULL),
(376, 73, 1, 117, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 124, NULL),
(377, 74, 1, 26, NULL, NULL, NULL, 12, 1.0000, 1.0000, 28000.0000, 28000.00, 125, NULL),
(378, 75, 1, 159, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 126, NULL),
(379, 76, 1, 110, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 127, NULL),
(380, 76, 2, 165, NULL, NULL, NULL, 1, 2.0000, 2.0000, 185000.0000, 370000.00, 128, NULL),
(381, 76, 3, 70, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 129, NULL),
(382, 77, 1, 150, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 130, NULL),
(383, 77, 2, 52, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 131, NULL),
(384, 78, 1, 124, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 132, NULL),
(385, 79, 1, 36, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 133, NULL),
(386, 79, 2, 97, NULL, NULL, NULL, 21, 1.0000, 1.0000, 450000.0000, 450000.00, 134, NULL),
(387, 80, 1, 82, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 135, NULL),
(388, 80, 2, 138, NULL, NULL, NULL, 1, 1.0000, 1.0000, 160000.0000, 160000.00, 136, NULL),
(389, 81, 1, 73, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 137, NULL),
(390, 82, 1, 115, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 138, NULL),
(391, 83, 1, 46, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 139, NULL),
(392, 83, 2, 105, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 140, NULL),
(393, 83, 3, 157, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 141, NULL),
(394, 84, 1, 156, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 145, NULL),
(395, 85, 1, 120, NULL, NULL, NULL, 1, 1.0000, 1.0000, 140000.0000, 140000.00, 146, NULL),
(396, 86, 1, 32, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 147, NULL),
(397, 87, 1, 163, NULL, NULL, NULL, 1, 1.0000, 1.0000, 185000.0000, 185000.00, 148, NULL),
(398, 88, 1, 78, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 149, NULL),
(399, 88, 2, 135, NULL, NULL, NULL, 1, 1.0000, 1.0000, 70000.0000, 70000.00, 150, NULL),
(400, 89, 1, 113, NULL, NULL, NULL, 1, 2.0000, 2.0000, 80000.0000, 160000.00, 151, NULL),
(401, 89, 2, 2, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 152, NULL),
(402, 90, 1, 153, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 153, NULL),
(403, 91, 1, 39, NULL, NULL, NULL, 1, 1.0000, 1.0000, 190000.0000, 190000.00, 154, NULL),
(404, 91, 2, 102, NULL, NULL, NULL, 12, 1.0000, 1.0000, 28000.0000, 28000.00, 155, NULL),
(405, 91, 3, 154, NULL, NULL, NULL, 1, 2.0000, 2.0000, 105000.0000, 210000.00, 156, NULL),
(406, 92, 1, 84, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 157, NULL),
(407, 92, 2, 142, NULL, NULL, NULL, 1, 1.0000, 1.0000, 140000.0000, 140000.00, 158, NULL),
(408, 92, 3, 42, NULL, NULL, NULL, 1, 1.0000, 1.0000, 260000.0000, 260000.00, 159, NULL),
(409, 93, 1, 127, NULL, NULL, NULL, 1, 1.0000, 1.0000, 150000.0000, 150000.00, 160, NULL),
(410, 93, 2, 20, NULL, NULL, NULL, 21, 1.0000, 1.0000, 220000.0000, 220000.00, 161, NULL),
(411, 94, 1, 48, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 162, NULL),
(412, 95, 1, 117, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 163, NULL),
(413, 96, 1, 91, NULL, NULL, NULL, 1, 1.0000, 1.0000, 120000.0000, 120000.00, 164, NULL),
(414, 97, 1, 159, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 165, NULL),
(415, 98, 1, 76, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 166, NULL),
(416, 99, 1, 36, NULL, NULL, NULL, 21, 2.0000, 2.0000, 95000.0000, 190000.00, 167, NULL),
(417, 99, 2, 97, NULL, NULL, NULL, 21, 1.0000, 1.0000, 450000.0000, 450000.00, 168, NULL),
(418, 100, 1, 115, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 172, NULL),
(419, 101, 1, 167, NULL, NULL, NULL, 1, 1.0000, 1.0000, 260000.0000, 260000.00, 173, NULL),
(420, 101, 2, 70, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 174, NULL),
(421, 102, 1, 124, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 175, NULL),
(422, 102, 2, 16, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 176, NULL),
(423, 103, 1, 87, NULL, NULL, NULL, 1, 1.0000, 1.0000, 160000.0000, 160000.00, 177, NULL),
(424, 104, 1, 156, NULL, NULL, NULL, 1, 2.0000, 2.0000, 105000.0000, 210000.00, 178, NULL),
(425, 105, 1, 130, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 179, NULL),
(426, 106, 1, 46, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 180, NULL),
(427, 107, 1, 94, NULL, NULL, NULL, 1, 1.0000, 1.0000, 160000.0000, 160000.00, 181, NULL),
(428, 108, 1, 163, NULL, NULL, NULL, 1, 1.0000, 1.0000, 185000.0000, 185000.00, 182, NULL),
(429, 108, 2, 68, NULL, NULL, NULL, 1, 2.0000, 2.0000, 70000.0000, 140000.00, 183, NULL),
(430, 109, 1, 78, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 184, NULL),
(431, 109, 2, 135, NULL, NULL, NULL, 1, 1.0000, 1.0000, 70000.0000, 70000.00, 185, NULL),
(432, 109, 3, 34, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 186, NULL),
(433, 110, 1, 50, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 187, NULL),
(434, 110, 2, 110, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 188, NULL),
(435, 111, 1, 120, NULL, NULL, NULL, 1, 2.0000, 2.0000, 140000.0000, 280000.00, 189, NULL),
(436, 111, 2, 12, NULL, NULL, NULL, 1, 1.0000, 1.0000, 110000.0000, 110000.00, 190, NULL),
(437, 112, 1, 39, NULL, NULL, NULL, 1, 1.0000, 1.0000, 190000.0000, 190000.00, 191, NULL),
(438, 113, 1, 2, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 192, NULL),
(439, 113, 2, 73, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 193, NULL),
(440, 113, 3, 129, NULL, NULL, NULL, 1, 2.0000, 2.0000, 150000.0000, 300000.00, 194, NULL),
(441, 114, 1, 84, NULL, NULL, NULL, 1, 2.0000, 2.0000, 80000.0000, 160000.00, 195, NULL),
(442, 115, 1, 127, NULL, NULL, NULL, 1, 1.0000, 1.0000, 150000.0000, 150000.00, 196, NULL),
(443, 116, 1, 159, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 197, NULL),
(444, 116, 2, 64, NULL, NULL, NULL, 1, 1.0000, 1.0000, 185000.0000, 185000.00, 198, NULL),
(445, 117, 1, 133, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 199, NULL),
(446, 118, 1, 48, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 200, NULL),
(447, 118, 2, 107, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 201, NULL),
(448, 119, 1, 117, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 202, NULL),
(449, 119, 2, 8, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 203, NULL),
(450, 119, 3, 77, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 204, NULL),
(451, 120, 1, 91, NULL, NULL, NULL, 1, 1.0000, 1.0000, 120000.0000, 120000.00, 205, NULL),
(452, 121, 1, 82, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 206, NULL),
(453, 121, 2, 138, NULL, NULL, NULL, 1, 1.0000, 1.0000, 160000.0000, 160000.00, 207, NULL),
(454, 122, 1, 53, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 208, NULL),
(455, 122, 2, 112, NULL, NULL, NULL, 1, 2.0000, 2.0000, 80000.0000, 160000.00, 209, NULL),
(456, 122, 3, 1, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 210, NULL),
(457, 123, 1, 124, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 211, NULL),
(458, 124, 1, 99, NULL, NULL, NULL, 21, 1.0000, 1.0000, 450000.0000, 450000.00, 212, NULL),
(459, 124, 2, 152, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 213, NULL),
(460, 125, 1, 167, NULL, NULL, NULL, 1, 2.0000, 2.0000, 260000.0000, 520000.00, 214, NULL),
(461, 125, 2, 70, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 215, NULL),
(462, 125, 3, 125, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 216, NULL),
(463, 126, 1, 87, NULL, NULL, NULL, 1, 1.0000, 1.0000, 160000.0000, 160000.00, 217, NULL),
(464, 127, 1, 163, NULL, NULL, NULL, 1, 1.0000, 1.0000, 185000.0000, 185000.00, 218, NULL),
(465, 127, 2, 68, NULL, NULL, NULL, 1, 1.0000, 1.0000, 70000.0000, 70000.00, 219, NULL),
(466, 127, 3, 122, NULL, NULL, NULL, 1, 1.0000, 1.0000, 140000.0000, 140000.00, 220, NULL),
(467, 128, 1, 130, NULL, NULL, NULL, 1, 2.0000, 2.0000, 65000.0000, 130000.00, 221, NULL),
(468, 129, 1, 46, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 222, NULL),
(469, 130, 1, 5, NULL, NULL, NULL, 1, 1.0000, 1.0000, 150000.0000, 150000.00, 223, NULL),
(470, 131, 1, 120, NULL, NULL, NULL, 1, 1.0000, 1.0000, 140000.0000, 140000.00, 224, NULL),
(471, 131, 2, 12, NULL, NULL, NULL, 1, 1.0000, 1.0000, 110000.0000, 110000.00, 225, NULL),
(472, 132, 1, 136, NULL, NULL, NULL, 1, 1.0000, 1.0000, 70000.0000, 70000.00, 226, NULL),
(473, 132, 2, 35, NULL, NULL, NULL, 21, 2.0000, 2.0000, 95000.0000, 190000.00, 227, NULL),
(474, 133, 1, 50, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 228, NULL),
(475, 133, 2, 110, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 229, NULL),
(476, 133, 3, 164, NULL, NULL, NULL, 1, 1.0000, 1.0000, 185000.0000, 185000.00, 230, NULL),
(477, 134, 1, 127, NULL, NULL, NULL, 1, 1.0000, 1.0000, 150000.0000, 150000.00, 231, NULL),
(478, 135, 1, 2, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 235, NULL),
(479, 136, 1, 84, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 236, NULL),
(480, 137, 1, 133, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 238, NULL),
(481, 137, 2, 31, NULL, NULL, NULL, 21, 1.0000, 1.0000, 450000.0000, 450000.00, 239, NULL),
(482, 138, 1, 48, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 241, NULL),
(483, 138, 2, 107, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 242, NULL),
(484, 138, 3, 161, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 243, NULL),
(485, 139, 1, 9, NULL, NULL, NULL, 1, 2.0000, 2.0000, 165000.0000, 330000.00, 244, NULL),
(486, 139, 2, 77, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 245, NULL),
(487, 140, 1, 167, NULL, NULL, NULL, 1, 1.0000, 1.0000, 260000.0000, 260000.00, 247, NULL),
(488, 141, 1, 139, NULL, NULL, NULL, 1, 2.0000, 2.0000, 160000.0000, 320000.00, 248, NULL),
(489, 141, 2, 38, NULL, NULL, NULL, 1, 1.0000, 1.0000, 45000.0000, 45000.00, 249, NULL),
(490, 141, 3, 102, NULL, NULL, NULL, 12, 1.0000, 1.0000, 28000.0000, 28000.00, 250, NULL),
(491, 142, 1, 14, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 253, NULL),
(492, 142, 2, 81, NULL, NULL, NULL, 1, 1.0000, 1.0000, 105000.0000, 105000.00, 254, NULL),
(493, 142, 3, 137, NULL, NULL, NULL, 1, 1.0000, 1.0000, 160000.0000, 160000.00, 255, NULL),
(494, 143, 1, 103, NULL, NULL, NULL, 1, 1.0000, 1.0000, 120000.0000, 120000.00, 256, NULL),
(495, 144, 1, 9, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 257, NULL),
(496, 144, 2, 77, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 258, NULL),
(497, 144, 3, 134, NULL, NULL, NULL, 1, 1.0000, 1.0000, 70000.0000, 70000.00, 259, NULL),
(498, 145, 1, 130, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 260, NULL),
(499, 145, 2, 26, NULL, NULL, NULL, 12, 1.0000, 1.0000, 28000.0000, 28000.00, 261, NULL),
(500, 146, 1, 106, NULL, NULL, NULL, 21, 2.0000, 2.0000, 310000.0000, 620000.00, 262, NULL)
;
INSERT INTO [inv].[StockDocumentLines] ([Id], [DocumentId], [LineNumber], [ProductId], [LotId], [LocationId], [DestLocationId], [UomId], [Quantity], [BaseQuantity], [UnitCost], [LineValue], [SourceLineId], [Note]) VALUES
(501, 147, 1, 99, NULL, NULL, NULL, 21, 1.0000, 1.0000, 450000.0000, 450000.00, 263, NULL),
(502, 148, 1, 2, NULL, NULL, NULL, 1, 1.0000, 1.0000, 80000.0000, 80000.00, 264, NULL),
(503, 148, 2, 73, NULL, NULL, NULL, 1, 1.0000, 1.0000, 200000.0000, 200000.00, 265, NULL),
(504, 149, 1, 143, NULL, NULL, NULL, 1, 1.0000, 1.0000, 140000.0000, 140000.00, 266, NULL),
(505, 150, 1, 5, NULL, NULL, NULL, 1, 1.0000, 1.0000, 150000.0000, 150000.00, 271, NULL),
(506, 150, 2, 75, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 272, NULL),
(507, 151, 1, 139, NULL, NULL, NULL, 1, 1.0000, 1.0000, 160000.0000, 160000.00, 273, NULL),
(508, 152, 1, 133, NULL, NULL, NULL, 1, 1.0000, 1.0000, 65000.0000, 65000.00, 275, NULL),
(509, 152, 2, 31, NULL, NULL, NULL, 21, 1.0000, 1.0000, 450000.0000, 450000.00, 276, NULL),
(510, 152, 3, 92, NULL, NULL, NULL, 1, 2.0000, 2.0000, 160000.0000, 320000.00, 277, NULL),
(511, 153, 1, 108, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 281, NULL),
(512, 153, 2, 162, NULL, NULL, NULL, 1, 1.0000, 1.0000, 45000.0000, 45000.00, 282, NULL),
(513, 154, 1, 62, NULL, NULL, NULL, 1, 1.0000, 1.0000, 165000.0000, 165000.00, 283, NULL),
(514, 155, 1, 53, NULL, NULL, NULL, 21, 1.0000, 1.0000, 310000.0000, 310000.00, 284, NULL),
(515, 156, 1, 136, NULL, NULL, NULL, 1, 1.0000, 1.0000, 70000.0000, 70000.00, 286, NULL),
(516, 156, 2, 35, NULL, NULL, NULL, 21, 1.0000, 1.0000, 95000.0000, 95000.00, 287, NULL),
(517, 156, 3, 96, NULL, NULL, NULL, 1, 1.0000, 1.0000, 190000.0000, 190000.00, 288, NULL),
(518, 157, 1, 58, NULL, NULL, NULL, 21, 1.0000, 1.0000, 220000.0000, 220000.00, 289, NULL),
(519, 158, 1, 5, NULL, NULL, NULL, 1, 1.0000, 1.0000, 150000.0000, 150000.00, 223, NULL),
(520, 159, 1, 91, NULL, NULL, NULL, 1, 1.0000, 1.0000, 120000.0000, 120000.00, 205, NULL)
;
SET IDENTITY_INSERT [inv].[StockDocumentLines] OFF;
GO

-- inv.StockDocuments (159 dòng)
SET IDENTITY_INSERT [inv].[StockDocuments] ON;
INSERT INTO [inv].[StockDocuments] ([Id], [CompanyId], [DocNo], [DocType], [Reason], [WarehouseId], [DestWarehouseId], [PartnerId], [SourceType], [SourceId], [SourceDocNo], [DocDate], [Status], [DeliverName], [Note], [TotalQuantity], [TotalValue], [JournalEntryId], [DoneAt], [DoneBy], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'PN2609-00001', 'receipt', 'purchase', 1, NULL, 25, 'pur.PurchaseOrders', 1, 'DM2609-0001', '2026-09-24T12:42:55.0000000', 'done', NULL, N'Nhập hàng theo đơn DM2609-0001', 228.0000, 22977000.00, NULL, '2026-09-24T09:42:54.7200000', 1, '2026-09-24T09:42:54.7200000', 1, NULL, NULL, 0),
(2, 1, 'PN2609-00002', 'receipt', 'purchase', 1, NULL, 26, 'pur.PurchaseOrders', 2, 'DM2609-0002', '2026-09-25T12:42:55.0000000', 'done', NULL, N'Nhập hàng theo đơn DM2609-0002', 407.0000, 62635000.00, NULL, '2026-09-25T09:42:54.7200000', 1, '2026-09-25T09:42:54.7200000', 1, NULL, NULL, 0),
(3, 1, 'PN2609-00003', 'receipt', 'purchase', 1, NULL, 27, 'pur.PurchaseOrders', 3, 'DM2609-0003', '2026-09-25T12:42:55.0000000', 'done', NULL, N'Nhập hàng theo đơn DM2609-0003', 70.0000, 13670000.00, NULL, '2026-09-25T09:42:54.7200000', 1, '2026-09-25T09:42:54.7200000', 1, NULL, NULL, 0),
(4, 1, 'PN2609-00004', 'receipt', 'purchase', 1, NULL, 28, 'pur.PurchaseOrders', 4, 'DM2609-0004', '2026-09-26T12:42:55.0000000', 'done', NULL, N'Nhập hàng theo đơn DM2609-0004', 241.0000, 67520000.00, NULL, '2026-09-26T09:42:54.7200000', 1, '2026-09-26T09:42:54.7200000', 1, NULL, NULL, 0),
(5, 1, 'PN2610-00001', 'receipt', 'purchase', 1, NULL, 25, 'pur.PurchaseOrders', 5, 'DM2610-0001', '2026-10-28T12:42:55.0000000', 'done', NULL, N'Nhập hàng theo đơn DM2610-0001', 215.0000, 17383000.00, NULL, '2026-10-28T09:42:54.7200000', 1, '2026-10-28T09:42:54.7200000', 1, NULL, NULL, 0),
(6, 1, 'PN2610-00002', 'receipt', 'purchase', 1, NULL, 27, 'pur.PurchaseOrders', 6, 'DM2610-0002', '2026-10-29T12:42:55.0000000', 'done', NULL, N'Nhập hàng theo đơn DM2610-0002', 46.0000, 8810000.00, NULL, '2026-10-29T09:42:54.7200000', 1, '2026-10-29T09:42:54.7200000', 1, NULL, NULL, 0),
(7, 1, 'PN2610-00003', 'receipt', 'purchase', 1, NULL, 28, 'pur.PurchaseOrders', 7, 'DM2610-0003', '2026-10-30T12:42:55.0000000', 'done', NULL, N'Nhập hàng theo đơn DM2610-0003', 111.0000, 18930000.00, NULL, '2026-10-30T09:42:54.7200000', 1, '2026-10-30T09:42:54.7200000', 1, NULL, NULL, 0),
(8, 1, 'PX2609-00001', 'issue', 'sale', 1, NULL, 38, 'sales.SalesOrders', 1, 'DH2609-00001', '2026-09-24T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2609-00001', 4.0000, 345000.00, NULL, '2026-09-24T02:10:00.0000000', 1, '2026-09-24T02:10:00.0000000', 1, NULL, NULL, 0),
(9, 1, 'PX2609-00002', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 2, 'DH2609-00002', '2026-09-25T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2609-00002', 2.0000, 510000.00, NULL, '2026-09-25T03:10:00.0000000', 1, '2026-09-25T03:10:00.0000000', 1, NULL, NULL, 0),
(10, 1, 'PX2609-00003', 'issue', 'sale', 1, NULL, 39, 'sales.SalesOrders', 3, 'DH2609-00003', '2026-09-25T09:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2609-00003', 2.0000, 230000.00, NULL, '2026-09-25T09:10:00.0000000', 1, '2026-09-25T09:10:00.0000000', 1, NULL, NULL, 0),
(11, 1, 'PX2609-00004', 'issue', 'sale', 1, NULL, 40, 'sales.SalesOrders', 4, 'DH2609-00004', '2026-09-25T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2609-00004', 2.0000, 475000.00, NULL, '2026-09-25T12:10:00.0000000', 1, '2026-09-25T12:10:00.0000000', 1, NULL, NULL, 0),
(12, 1, 'PX2609-00005', 'issue', 'sale', 1, NULL, 37, 'sales.SalesOrders', 5, 'DH2609-00005', '2026-09-27T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2609-00005', 2.0000, 320000.00, NULL, '2026-09-27T03:10:00.0000000', 1, '2026-09-27T03:10:00.0000000', 1, NULL, NULL, 0),
(13, 1, 'PX2609-00006', 'issue', 'sale', 1, NULL, 40, 'sales.SalesOrders', 6, 'DH2609-00006', '2026-09-28T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2609-00006', 1.0000, 200000.00, NULL, '2026-09-28T04:10:00.0000000', 1, '2026-09-28T04:10:00.0000000', 1, NULL, NULL, 0),
(14, 1, 'PX2609-00007', 'issue', 'sale', 1, NULL, 38, 'sales.SalesOrders', 7, 'DH2609-00007', '2026-09-28T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2609-00007', 1.0000, 70000.00, NULL, '2026-09-28T06:10:00.0000000', 1, '2026-09-28T06:10:00.0000000', 1, NULL, NULL, 0),
(15, 1, 'PX2609-00008', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 8, 'DH2609-00008', '2026-09-28T13:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2609-00008', 1.0000, 95000.00, NULL, '2026-09-28T13:10:00.0000000', 1, '2026-09-28T13:10:00.0000000', 1, NULL, NULL, 0),
(16, 1, 'PX2609-00009', 'issue', 'sale', 1, NULL, 41, 'sales.SalesOrders', 9, 'DH2609-00009', '2026-09-29T07:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2609-00009', 3.0000, 695000.00, NULL, '2026-09-29T07:10:00.0000000', 1, '2026-09-29T07:10:00.0000000', 1, NULL, NULL, 0),
(17, 1, 'PX2609-00010', 'issue', 'sale', 1, NULL, 37, 'sales.SalesOrders', 10, 'DH2609-00010', '2026-09-30T07:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2609-00010', 4.0000, 600000.00, NULL, '2026-09-30T07:10:00.0000000', 1, '2026-09-30T07:10:00.0000000', 1, NULL, NULL, 0),
(18, 1, 'PX2610-00001', 'issue', 'sale', 1, NULL, 39, 'sales.SalesOrders', 11, 'DH2610-00001', '2026-10-01T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00001', 2.0000, 250000.00, NULL, '2026-10-01T05:10:00.0000000', 1, '2026-10-01T05:10:00.0000000', 1, NULL, NULL, 0),
(19, 1, 'PX2610-00002', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 12, 'DH2610-00002', '2026-10-01T08:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00002', 1.0000, 220000.00, NULL, '2026-10-01T08:10:00.0000000', 1, '2026-10-01T08:10:00.0000000', 1, NULL, NULL, 0),
(20, 1, 'PX2610-00003', 'issue', 'sale', 1, NULL, 41, 'sales.SalesOrders', 14, 'DH2610-00004', '2026-10-02T11:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00004', 1.0000, 200000.00, NULL, '2026-10-02T11:10:00.0000000', 1, '2026-10-02T11:10:00.0000000', 1, NULL, NULL, 0),
(21, 1, 'PX2610-00004', 'issue', 'sale', 1, NULL, 37, 'sales.SalesOrders', 15, 'DH2610-00005', '2026-10-03T11:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00005', 2.0000, 330000.00, NULL, '2026-10-03T11:10:00.0000000', 1, '2026-10-03T11:10:00.0000000', 1, NULL, NULL, 0),
(22, 1, 'PX2610-00005', 'issue', 'sale', 1, NULL, 39, 'sales.SalesOrders', 17, 'DH2610-00007', '2026-10-04T09:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00007', 4.0000, 495000.00, NULL, '2026-10-04T09:10:00.0000000', 1, '2026-10-04T09:10:00.0000000', 1, NULL, NULL, 0),
(23, 1, 'PX2610-00006', 'issue', 'sale', 1, NULL, 40, 'sales.SalesOrders', 18, 'DH2610-00008', '2026-10-04T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00008', 3.0000, 820000.00, NULL, '2026-10-04T12:10:00.0000000', 1, '2026-10-04T12:10:00.0000000', 1, NULL, NULL, 0),
(24, 1, 'PX2610-00007', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 19, 'DH2610-00009', '2026-10-06T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00009', 3.0000, 365000.00, NULL, '2026-10-06T03:10:00.0000000', 1, '2026-10-06T03:10:00.0000000', 1, NULL, NULL, 0),
(25, 1, 'PX2610-00008', 'issue', 'sale', 1, NULL, 36, 'sales.SalesOrders', 20, 'DH2610-00010', '2026-10-06T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00010', 1.0000, 450000.00, NULL, '2026-10-06T12:10:00.0000000', 1, '2026-10-06T12:10:00.0000000', 1, NULL, NULL, 0),
(26, 1, 'PX2610-00009', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 21, 'DH2610-00011', '2026-10-07T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00011', 1.0000, 80000.00, NULL, '2026-10-07T04:10:00.0000000', 1, '2026-10-07T04:10:00.0000000', 1, NULL, NULL, 0),
(27, 1, 'PX2610-00010', 'issue', 'sale', 1, NULL, 38, 'sales.SalesOrders', 22, 'DH2610-00012', '2026-10-07T10:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00012', 1.0000, 95000.00, NULL, '2026-10-07T10:10:00.0000000', 1, '2026-10-07T10:10:00.0000000', 1, NULL, NULL, 0),
(28, 1, 'PX2610-00011', 'issue', 'sale', 1, NULL, 39, 'sales.SalesOrders', 23, 'DH2610-00013', '2026-10-07T13:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00013', 1.0000, 200000.00, NULL, '2026-10-07T13:10:00.0000000', 1, '2026-10-07T13:10:00.0000000', 1, NULL, NULL, 0),
(29, 1, 'PX2610-00012', 'issue', 'sale', 1, NULL, 38, 'sales.SalesOrders', 24, 'DH2610-00014', '2026-10-09T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00014', 4.0000, 1130000.00, NULL, '2026-10-09T02:10:00.0000000', 1, '2026-10-09T02:10:00.0000000', 1, NULL, NULL, 0),
(30, 1, 'PX2610-00013', 'issue', 'sale', 1, NULL, 36, 'sales.SalesOrders', 25, 'DH2610-00015', '2026-10-09T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00015', 2.0000, 230000.00, NULL, '2026-10-09T04:10:00.0000000', 1, '2026-10-09T04:10:00.0000000', 1, NULL, NULL, 0),
(31, 1, 'PX2610-00014', 'issue', 'sale', 1, NULL, 37, 'sales.SalesOrders', 26, 'DH2610-00016', '2026-10-09T07:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00016', 4.0000, 970000.00, NULL, '2026-10-09T07:10:00.0000000', 1, '2026-10-09T07:10:00.0000000', 1, NULL, NULL, 0),
(32, 1, 'PX2610-00015', 'issue', 'sale', 1, NULL, 39, 'sales.SalesOrders', 27, 'DH2610-00017', '2026-10-10T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00017', 2.0000, 178000.00, NULL, '2026-10-10T05:10:00.0000000', 1, '2026-10-10T05:10:00.0000000', 1, NULL, NULL, 0),
(33, 1, 'PX2610-00016', 'issue', 'sale', 1, NULL, 40, 'sales.SalesOrders', 28, 'DH2610-00018', '2026-10-10T08:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00018', 2.0000, 130000.00, NULL, '2026-10-10T08:10:00.0000000', 1, '2026-10-10T08:10:00.0000000', 1, NULL, NULL, 0),
(34, 1, 'PX2610-00017', 'issue', 'sale', 1, NULL, 38, 'sales.SalesOrders', 29, 'DH2610-00019', '2026-10-12T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00019', 1.0000, 310000.00, NULL, '2026-10-12T06:10:00.0000000', 1, '2026-10-12T06:10:00.0000000', 1, NULL, NULL, 0),
(35, 1, 'PX2610-00018', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 30, 'DH2610-00020', '2026-10-12T08:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00020', 1.0000, 95000.00, NULL, '2026-10-12T08:10:00.0000000', 1, '2026-10-12T08:10:00.0000000', 1, NULL, NULL, 0),
(36, 1, 'PX2610-00019', 'issue', 'sale', 1, NULL, 37, 'sales.SalesOrders', 31, 'DH2610-00021', '2026-10-12T11:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00021', 2.0000, 400000.00, NULL, '2026-10-12T11:10:00.0000000', 1, '2026-10-12T11:10:00.0000000', 1, NULL, NULL, 0),
(37, 1, 'PX2610-00020', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 32, 'DH2610-00022', '2026-10-13T09:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00022', 1.0000, 65000.00, NULL, '2026-10-13T09:10:00.0000000', 1, '2026-10-13T09:10:00.0000000', 1, NULL, NULL, 0),
(38, 1, 'PX2610-00021', 'issue', 'sale', 1, NULL, 35, 'sales.SalesOrders', 33, 'DH2610-00023', '2026-10-14T09:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00023', 2.0000, 225000.00, NULL, '2026-10-14T09:10:00.0000000', 1, '2026-10-14T09:10:00.0000000', 1, NULL, NULL, 0),
(39, 1, 'PX2610-00022', 'issue', 'sale', 1, NULL, 36, 'sales.SalesOrders', 34, 'DH2610-00024', '2026-10-14T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00024', 3.0000, 560000.00, NULL, '2026-10-14T12:10:00.0000000', 1, '2026-10-14T12:10:00.0000000', 1, NULL, NULL, 0),
(40, 1, 'PX2610-00023', 'issue', 'sale', 1, NULL, 37, 'sales.SalesOrders', 35, 'DH2610-00025', '2026-10-15T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00025', 3.0000, 600000.00, NULL, '2026-10-15T03:10:00.0000000', 1, '2026-10-15T03:10:00.0000000', 1, NULL, NULL, 0),
(41, 1, 'PX2610-00024', 'issue', 'sale', 1, NULL, 38, 'sales.SalesOrders', 36, 'DH2610-00026', '2026-10-15T10:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00026', 3.0000, 330000.00, NULL, '2026-10-15T10:10:00.0000000', 1, '2026-10-15T10:10:00.0000000', 1, NULL, NULL, 0),
(42, 1, 'PX2610-00025', 'issue', 'sale', 1, NULL, 39, 'sales.SalesOrders', 37, 'DH2610-00027', '2026-10-15T13:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00027', 2.0000, 215000.00, NULL, '2026-10-15T13:10:00.0000000', 1, '2026-10-15T13:10:00.0000000', 1, NULL, NULL, 0),
(43, 1, 'PX2610-00026', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 38, 'DH2610-00028', '2026-10-17T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00028', 1.0000, 95000.00, NULL, '2026-10-17T02:10:00.0000000', 1, '2026-10-17T02:10:00.0000000', 1, NULL, NULL, 0),
(44, 1, 'PX2610-00027', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 39, 'DH2610-00029', '2026-10-17T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00029', 1.0000, 310000.00, NULL, '2026-10-17T04:10:00.0000000', 1, '2026-10-17T04:10:00.0000000', 1, NULL, NULL, 0),
(45, 1, 'PX2610-00028', 'issue', 'sale', 1, NULL, 37, 'sales.SalesOrders', 40, 'DH2610-00030', '2026-10-17T11:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00030', 2.0000, 400000.00, NULL, '2026-10-17T11:10:00.0000000', 1, '2026-10-17T11:10:00.0000000', 1, NULL, NULL, 0),
(46, 1, 'PX2610-00029', 'issue', 'sale', 1, NULL, 35, 'sales.SalesOrders', 41, 'DH2610-00031', '2026-10-17T13:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00031', 1.0000, 185000.00, NULL, '2026-10-17T13:10:00.0000000', 1, '2026-10-17T13:10:00.0000000', 1, NULL, NULL, 0),
(47, 1, 'PX2610-00030', 'issue', 'sale', 1, NULL, 39, 'sales.SalesOrders', 42, 'DH2610-00032', '2026-10-18T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00032', 4.0000, 365000.00, NULL, '2026-10-18T05:10:00.0000000', 1, '2026-10-18T05:10:00.0000000', 1, NULL, NULL, 0),
(48, 1, 'PX2610-00031', 'issue', 'sale', 1, NULL, 35, 'sales.SalesOrders', 43, 'DH2610-00033', '2026-10-19T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00033', 3.0000, 315000.00, NULL, '2026-10-19T05:10:00.0000000', 1, '2026-10-19T05:10:00.0000000', 1, NULL, NULL, 0),
(49, 1, 'PX2610-00032', 'issue', 'sale', 1, NULL, 36, 'sales.SalesOrders', 44, 'DH2610-00034', '2026-10-19T08:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00034', 2.0000, 305000.00, NULL, '2026-10-19T08:10:00.0000000', 1, '2026-10-19T08:10:00.0000000', 1, NULL, NULL, 0),
(50, 1, 'PX2610-00033', 'issue', 'sale', 1, NULL, 38, 'sales.SalesOrders', 46, 'DH2610-00036', '2026-10-20T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00036', 1.0000, 65000.00, NULL, '2026-10-20T06:10:00.0000000', 1, '2026-10-20T06:10:00.0000000', 1, NULL, NULL, 0),
(51, 1, 'PX2610-00034', 'issue', 'sale', 1, NULL, 34, 'sales.SalesOrders', 47, 'DH2610-00037', '2026-10-21T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00037', 1.0000, 310000.00, NULL, '2026-10-21T06:10:00.0000000', 1, '2026-10-21T06:10:00.0000000', 1, NULL, NULL, 0),
(52, 1, 'PX2610-00035', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 49, 'DH2610-00039', '2026-10-22T09:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00039', 1.0000, 200000.00, NULL, '2026-10-22T09:10:00.0000000', 1, '2026-10-22T09:10:00.0000000', 1, NULL, NULL, 0),
(53, 1, 'PX2610-00036', 'issue', 'sale', 1, NULL, 38, 'sales.SalesOrders', 50, 'DH2610-00040', '2026-10-22T10:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00040', 4.0000, 460000.00, NULL, '2026-10-22T10:10:00.0000000', 1, '2026-10-22T10:10:00.0000000', 1, NULL, NULL, 0),
(54, 1, 'PX2610-00037', 'issue', 'sale', 1, NULL, 36, 'sales.SalesOrders', 51, 'DH2610-00041', '2026-10-22T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00041', 1.0000, 28000.00, NULL, '2026-10-22T12:10:00.0000000', 1, '2026-10-22T12:10:00.0000000', 1, NULL, NULL, 0),
(55, 1, 'PX2610-00038', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 52, 'DH2610-00042', '2026-10-24T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00042', 1.0000, 65000.00, NULL, '2026-10-24T04:10:00.0000000', 1, '2026-10-24T04:10:00.0000000', 1, NULL, NULL, 0),
(56, 1, 'PX2610-00039', 'issue', 'sale', 1, NULL, 34, 'sales.SalesOrders', 53, 'DH2610-00043', '2026-10-24T10:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00043', 1.0000, 200000.00, NULL, '2026-10-24T10:10:00.0000000', 1, '2026-10-24T10:10:00.0000000', 1, NULL, NULL, 0),
(57, 1, 'PX2610-00040', 'issue', 'sale', 1, NULL, 37, 'sales.SalesOrders', 54, 'DH2610-00044', '2026-10-24T11:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00044', 2.0000, 190000.00, NULL, '2026-10-24T11:10:00.0000000', 1, '2026-10-24T11:10:00.0000000', 1, NULL, NULL, 0),
(58, 1, 'PX2610-00041', 'issue', 'sale', 1, NULL, 35, 'sales.SalesOrders', 55, 'DH2610-00045', '2026-10-24T13:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00045', 2.0000, 495000.00, NULL, '2026-10-24T13:10:00.0000000', 1, '2026-10-24T13:10:00.0000000', 1, NULL, NULL, 0),
(59, 1, 'PX2610-00042', 'issue', 'sale', 1, NULL, 38, 'sales.SalesOrders', 56, 'DH2610-00046', '2026-10-25T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00046', 1.0000, 80000.00, NULL, '2026-10-25T02:10:00.0000000', 1, '2026-10-25T02:10:00.0000000', 1, NULL, NULL, 0),
(60, 1, 'PX2610-00043', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 57, 'DH2610-00047', '2026-10-26T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00047', 2.0000, 380000.00, NULL, '2026-10-26T02:10:00.0000000', 1, '2026-10-26T02:10:00.0000000', 1, NULL, NULL, 0),
(61, 1, 'PX2610-00044', 'issue', 'sale', 1, NULL, 37, 'sales.SalesOrders', 58, 'DH2610-00048', '2026-10-26T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00048', 3.0000, 375000.00, NULL, '2026-10-26T03:10:00.0000000', 1, '2026-10-26T03:10:00.0000000', 1, NULL, NULL, 0),
(62, 1, 'PX2610-00045', 'issue', 'sale', 1, NULL, 35, 'sales.SalesOrders', 59, 'DH2610-00049', '2026-10-26T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00049', 3.0000, 310000.00, NULL, '2026-10-26T05:10:00.0000000', 1, '2026-10-26T05:10:00.0000000', 1, NULL, NULL, 0),
(63, 1, 'PX2610-00046', 'issue', 'sale', 1, NULL, 36, 'sales.SalesOrders', 60, 'DH2610-00050', '2026-10-26T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00050', 3.0000, 280000.00, NULL, '2026-10-26T12:10:00.0000000', 1, '2026-10-26T12:10:00.0000000', 1, NULL, NULL, 0),
(64, 1, 'PX2610-00047', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 62, 'DH2610-00052', '2026-10-28T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00052', 1.0000, 105000.00, NULL, '2026-10-28T04:10:00.0000000', 1, '2026-10-28T04:10:00.0000000', 1, NULL, NULL, 0),
(65, 1, 'PX2610-00048', 'issue', 'sale', 1, NULL, 34, 'sales.SalesOrders', 63, 'DH2610-00053', '2026-10-28T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00053', 1.0000, 200000.00, NULL, '2026-10-28T06:10:00.0000000', 1, '2026-10-28T06:10:00.0000000', 1, NULL, NULL, 0),
(66, 1, 'PX2610-00049', 'issue', 'sale', 1, NULL, 35, 'sales.SalesOrders', 64, 'DH2610-00054', '2026-10-28T09:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00054', 1.0000, 95000.00, NULL, '2026-10-28T09:10:00.0000000', 1, '2026-10-28T09:10:00.0000000', 1, NULL, NULL, 0),
(67, 1, 'PX2610-00050', 'issue', 'sale', 1, NULL, 37, 'sales.SalesOrders', 65, 'DH2610-00055', '2026-10-29T07:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00055', 2.0000, 280000.00, NULL, '2026-10-29T07:10:00.0000000', 1, '2026-10-29T07:10:00.0000000', 1, NULL, NULL, 0),
(68, 1, 'PX2610-00051', 'issue', 'sale', 1, NULL, 36, 'sales.SalesOrders', 67, 'DH2610-00057', '2026-10-30T08:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00057', 2.0000, 218000.00, NULL, '2026-10-30T08:10:00.0000000', 1, '2026-10-30T08:10:00.0000000', 1, NULL, NULL, 0),
(69, 1, 'PX2610-00052', 'issue', 'sale', 1, NULL, 34, 'sales.SalesOrders', 68, 'DH2610-00058', '2026-10-30T10:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00058', 3.0000, 360000.00, NULL, '2026-10-30T10:10:00.0000000', 1, '2026-10-30T10:10:00.0000000', 1, NULL, NULL, 0),
(70, 1, 'PX2610-00053', 'issue', 'sale', 1, NULL, 35, 'sales.SalesOrders', 69, 'DH2610-00059', '2026-10-30T13:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00059', 2.0000, 285000.00, NULL, '2026-10-30T13:10:00.0000000', 1, '2026-10-30T13:10:00.0000000', 1, NULL, NULL, 0),
(71, 1, 'PX2610-00054', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 70, 'DH2610-00060', '2026-10-31T11:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2610-00060', 3.0000, 300000.00, NULL, '2026-10-31T11:10:00.0000000', 1, '2026-10-31T11:10:00.0000000', 1, NULL, NULL, 0),
(72, 1, 'PX2611-00001', 'issue', 'sale', 1, NULL, 34, 'sales.SalesOrders', 71, 'DH2611-00001', '2026-11-01T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00001', 1.0000, 65000.00, NULL, '2026-11-01T02:10:00.0000000', 1, '2026-11-01T02:10:00.0000000', 1, NULL, NULL, 0),
(73, 1, 'PX2611-00002', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 72, 'DH2611-00002', '2026-11-01T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00002', 1.0000, 65000.00, NULL, '2026-11-01T05:10:00.0000000', 1, '2026-11-01T05:10:00.0000000', 1, NULL, NULL, 0),
(74, 1, 'PX2611-00003', 'issue', 'sale', 1, NULL, 33, 'sales.SalesOrders', 73, 'DH2611-00003', '2026-11-01T11:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00003', 1.0000, 28000.00, NULL, '2026-11-01T11:10:00.0000000', 1, '2026-11-01T11:10:00.0000000', 1, NULL, NULL, 0),
(75, 1, 'PX2611-00004', 'issue', 'sale', 1, NULL, 36, 'sales.SalesOrders', 74, 'DH2611-00004', '2026-11-01T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00004', 1.0000, 165000.00, NULL, '2026-11-01T12:10:00.0000000', 1, '2026-11-01T12:10:00.0000000', 1, NULL, NULL, 0),
(76, 1, 'PX2611-00005', 'issue', 'sale', 1, NULL, 32, 'sales.SalesOrders', 75, 'DH2611-00005', '2026-11-02T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00005', 4.0000, 880000.00, NULL, '2026-11-02T12:10:00.0000000', 1, '2026-11-02T12:10:00.0000000', 1, NULL, NULL, 0),
(77, 1, 'PX2611-00006', 'issue', 'sale', 1, NULL, 33, 'sales.SalesOrders', 76, 'DH2611-00006', '2026-11-03T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00006', 2.0000, 375000.00, NULL, '2026-11-03T03:10:00.0000000', 1, '2026-11-03T03:10:00.0000000', 1, NULL, NULL, 0),
(78, 1, 'PX2611-00007', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 77, 'DH2611-00007', '2026-11-03T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00007', 1.0000, 105000.00, NULL, '2026-11-03T04:10:00.0000000', 1, '2026-11-03T04:10:00.0000000', 1, NULL, NULL, 0),
(79, 1, 'PX2611-00008', 'issue', 'sale', 1, NULL, 34, 'sales.SalesOrders', 78, 'DH2611-00008', '2026-11-03T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00008', 2.0000, 545000.00, NULL, '2026-11-03T06:10:00.0000000', 1, '2026-11-03T06:10:00.0000000', 1, NULL, NULL, 0),
(80, 1, 'PX2611-00009', 'issue', 'sale', 1, NULL, 35, 'sales.SalesOrders', 79, 'DH2611-00009', '2026-11-03T13:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00009', 2.0000, 240000.00, NULL, '2026-11-03T13:10:00.0000000', 1, '2026-11-03T13:10:00.0000000', 1, NULL, NULL, 0),
(81, 1, 'PX2611-00010', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 80, 'DH2611-00010', '2026-11-04T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00010', 1.0000, 200000.00, NULL, '2026-11-04T04:10:00.0000000', 1, '2026-11-04T04:10:00.0000000', 1, NULL, NULL, 0),
(82, 1, 'PX2611-00011', 'issue', 'sale', 1, NULL, 33, 'sales.SalesOrders', 81, 'DH2611-00011', '2026-11-04T07:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00011', 1.0000, 65000.00, NULL, '2026-11-04T07:10:00.0000000', 1, '2026-11-04T07:10:00.0000000', 1, NULL, NULL, 0),
(83, 1, 'PX2611-00012', 'issue', 'sale', 1, NULL, 35, 'sales.SalesOrders', 82, 'DH2611-00012', '2026-11-05T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00012', 3.0000, 725000.00, NULL, '2026-11-05T05:10:00.0000000', 1, '2026-11-05T05:10:00.0000000', 1, NULL, NULL, 0),
(84, 1, 'PX2611-00013', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 84, 'DH2611-00014', '2026-11-05T10:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00014', 1.0000, 105000.00, NULL, '2026-11-05T10:10:00.0000000', 1, '2026-11-05T10:10:00.0000000', 1, NULL, NULL, 0),
(85, 1, 'PX2611-00014', 'issue', 'sale', 1, NULL, 34, 'sales.SalesOrders', 85, 'DH2611-00015', '2026-11-06T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00015', 1.0000, 140000.00, NULL, '2026-11-06T02:10:00.0000000', 1, '2026-11-06T02:10:00.0000000', 1, NULL, NULL, 0),
(86, 1, 'PX2611-00015', 'issue', 'sale', 1, NULL, 32, 'sales.SalesOrders', 86, 'DH2611-00016', '2026-11-06T08:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00016', 1.0000, 95000.00, NULL, '2026-11-06T08:10:00.0000000', 1, '2026-11-06T08:10:00.0000000', 1, NULL, NULL, 0),
(87, 1, 'PX2611-00016', 'issue', 'sale', 1, NULL, 35, 'sales.SalesOrders', 87, 'DH2611-00017', '2026-11-06T09:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00017', 1.0000, 185000.00, NULL, '2026-11-06T09:10:00.0000000', 1, '2026-11-06T09:10:00.0000000', 1, NULL, NULL, 0),
(88, 1, 'PX2611-00017', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 88, 'DH2611-00018', '2026-11-06T11:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00018', 2.0000, 175000.00, NULL, '2026-11-06T11:10:00.0000000', 1, '2026-11-06T11:10:00.0000000', 1, NULL, NULL, 0),
(89, 1, 'PX2611-00018', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 89, 'DH2611-00019', '2026-11-07T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00019', 3.0000, 240000.00, NULL, '2026-11-07T05:10:00.0000000', 1, '2026-11-07T05:10:00.0000000', 1, NULL, NULL, 0),
(90, 1, 'PX2611-00019', 'issue', 'sale', 1, NULL, 32, 'sales.SalesOrders', 90, 'DH2611-00020', '2026-11-07T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00020', 1.0000, 65000.00, NULL, '2026-11-07T12:10:00.0000000', 1, '2026-11-07T12:10:00.0000000', 1, NULL, NULL, 0),
(91, 1, 'PX2611-00020', 'issue', 'sale', 1, NULL, 33, 'sales.SalesOrders', 91, 'DH2611-00021', '2026-11-08T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00021', 4.0000, 428000.00, NULL, '2026-11-08T03:10:00.0000000', 1, '2026-11-08T03:10:00.0000000', 1, NULL, NULL, 0),
(92, 1, 'PX2611-00021', 'issue', 'sale', 1, NULL, 34, 'sales.SalesOrders', 92, 'DH2611-00022', '2026-11-08T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00022', 3.0000, 480000.00, NULL, '2026-11-08T06:10:00.0000000', 1, '2026-11-08T06:10:00.0000000', 1, NULL, NULL, 0),
(93, 1, 'PX2611-00022', 'issue', 'sale', 1, NULL, 35, 'sales.SalesOrders', 93, 'DH2611-00023', '2026-11-08T13:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00023', 2.0000, 370000.00, NULL, '2026-11-08T13:10:00.0000000', 1, '2026-11-08T13:10:00.0000000', 1, NULL, NULL, 0),
(94, 1, 'PX2611-00023', 'issue', 'sale', 1, NULL, 34, 'sales.SalesOrders', 94, 'DH2611-00024', '2026-11-09T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00024', 1.0000, 310000.00, NULL, '2026-11-09T02:10:00.0000000', 1, '2026-11-09T02:10:00.0000000', 1, NULL, NULL, 0),
(95, 1, 'PX2611-00024', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 95, 'DH2611-00025', '2026-11-09T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00025', 1.0000, 65000.00, NULL, '2026-11-09T04:10:00.0000000', 1, '2026-11-09T04:10:00.0000000', 1, NULL, NULL, 0),
(96, 1, 'PX2611-00025', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 96, 'DH2611-00026', '2026-11-09T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00026', 1.0000, 120000.00, NULL, '2026-11-09T05:10:00.0000000', 1, '2026-11-09T05:10:00.0000000', 1, NULL, NULL, 0),
(97, 1, 'PX2611-00026', 'issue', 'sale', 1, NULL, 33, 'sales.SalesOrders', 97, 'DH2611-00027', '2026-11-09T07:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00027', 1.0000, 165000.00, NULL, '2026-11-09T07:10:00.0000000', 1, '2026-11-09T07:10:00.0000000', 1, NULL, NULL, 0),
(98, 1, 'PX2611-00027', 'issue', 'sale', 1, NULL, 31, 'sales.SalesOrders', 98, 'DH2611-00028', '2026-11-09T13:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00028', 2.0000, 130000.00, NULL, '2026-11-09T13:10:00.0000000', 1, '2026-11-09T13:10:00.0000000', 1, NULL, NULL, 0),
(99, 1, 'PX2611-00028', 'issue', 'sale', 1, NULL, 31, 'sales.SalesOrders', 99, 'DH2611-00029', '2026-11-10T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00029', 3.0000, 640000.00, NULL, '2026-11-10T05:10:00.0000000', 1, '2026-11-10T05:10:00.0000000', 1, NULL, NULL, 0),
(100, 1, 'PX2611-00029', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 101, 'DH2611-00031', '2026-11-11T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00031', 1.0000, 65000.00, NULL, '2026-11-11T02:10:00.0000000', 1, '2026-11-11T02:10:00.0000000', 1, NULL, NULL, 0),
(101, 1, 'PX2611-00030', 'issue', 'sale', 1, NULL, 34, 'sales.SalesOrders', 102, 'DH2611-00032', '2026-11-11T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00032', 2.0000, 460000.00, NULL, '2026-11-11T06:10:00.0000000', 1, '2026-11-11T06:10:00.0000000', 1, NULL, NULL, 0),
(102, 1, 'PX2611-00031', 'issue', 'sale', 1, NULL, 33, 'sales.SalesOrders', 103, 'DH2611-00033', '2026-11-11T11:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00033', 2.0000, 200000.00, NULL, '2026-11-11T11:10:00.0000000', 1, '2026-11-11T11:10:00.0000000', 1, NULL, NULL, 0),
(103, 1, 'PX2611-00032', 'issue', 'sale', 1, NULL, 33, 'sales.SalesOrders', 104, 'DH2611-00034', '2026-11-12T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00034', 1.0000, 160000.00, NULL, '2026-11-12T03:10:00.0000000', 1, '2026-11-12T03:10:00.0000000', 1, NULL, NULL, 0),
(104, 1, 'PX2611-00033', 'issue', 'sale', 1, NULL, 31, 'sales.SalesOrders', 105, 'DH2611-00035', '2026-11-12T09:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00035', 2.0000, 210000.00, NULL, '2026-11-12T09:10:00.0000000', 1, '2026-11-12T09:10:00.0000000', 1, NULL, NULL, 0),
(105, 1, 'PX2611-00034', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 106, 'DH2611-00036', '2026-11-12T10:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00036', 1.0000, 65000.00, NULL, '2026-11-12T10:10:00.0000000', 1, '2026-11-12T10:10:00.0000000', 1, NULL, NULL, 0),
(106, 1, 'PX2611-00035', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 107, 'DH2611-00037', '2026-11-12T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00037', 1.0000, 310000.00, NULL, '2026-11-12T12:10:00.0000000', 1, '2026-11-12T12:10:00.0000000', 1, NULL, NULL, 0),
(107, 1, 'PX2611-00036', 'issue', 'sale', 1, NULL, 34, 'sales.SalesOrders', 108, 'DH2611-00038', '2026-11-13T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00038', 1.0000, 160000.00, NULL, '2026-11-13T02:10:00.0000000', 1, '2026-11-13T02:10:00.0000000', 1, NULL, NULL, 0),
(108, 1, 'PX2611-00037', 'issue', 'sale', 1, NULL, 32, 'sales.SalesOrders', 109, 'DH2611-00039', '2026-11-13T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00039', 3.0000, 325000.00, NULL, '2026-11-13T04:10:00.0000000', 1, '2026-11-13T04:10:00.0000000', 1, NULL, NULL, 0),
(109, 1, 'PX2611-00038', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 110, 'DH2611-00040', '2026-11-13T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00040', 3.0000, 270000.00, NULL, '2026-11-13T06:10:00.0000000', 1, '2026-11-13T06:10:00.0000000', 1, NULL, NULL, 0),
(110, 1, 'PX2611-00039', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 111, 'DH2611-00041', '2026-11-13T07:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00041', 2.0000, 620000.00, NULL, '2026-11-13T07:10:00.0000000', 1, '2026-11-13T07:10:00.0000000', 1, NULL, NULL, 0),
(111, 1, 'PX2611-00040', 'issue', 'sale', 1, NULL, 31, 'sales.SalesOrders', 112, 'DH2611-00042', '2026-11-13T13:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00042', 3.0000, 390000.00, NULL, '2026-11-13T13:10:00.0000000', 1, '2026-11-13T13:10:00.0000000', 1, NULL, NULL, 0),
(112, 1, 'PX2611-00041', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 113, 'DH2611-00043', '2026-11-14T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00043', 1.0000, 190000.00, NULL, '2026-11-14T02:10:00.0000000', 1, '2026-11-14T02:10:00.0000000', 1, NULL, NULL, 0),
(113, 1, 'PX2611-00042', 'issue', 'sale', 1, NULL, 33, 'sales.SalesOrders', 114, 'DH2611-00044', '2026-11-14T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00044', 4.0000, 580000.00, NULL, '2026-11-14T03:10:00.0000000', 1, '2026-11-14T03:10:00.0000000', 1, NULL, NULL, 0),
(114, 1, 'PX2611-00043', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 115, 'DH2611-00045', '2026-11-14T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00045', 2.0000, 160000.00, NULL, '2026-11-14T05:10:00.0000000', 1, '2026-11-14T05:10:00.0000000', 1, NULL, NULL, 0),
(115, 1, 'PX2611-00044', 'issue', 'sale', 1, NULL, 32, 'sales.SalesOrders', 116, 'DH2611-00046', '2026-11-14T08:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00046', 1.0000, 150000.00, NULL, '2026-11-14T08:10:00.0000000', 1, '2026-11-14T08:10:00.0000000', 1, NULL, NULL, 0),
(116, 1, 'PX2611-00045', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 117, 'DH2611-00047', '2026-11-15T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00047', 2.0000, 350000.00, NULL, '2026-11-15T06:10:00.0000000', 1, '2026-11-15T06:10:00.0000000', 1, NULL, NULL, 0),
(117, 1, 'PX2611-00046', 'issue', 'sale', 1, NULL, 33, 'sales.SalesOrders', 118, 'DH2611-00048', '2026-11-15T07:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00048', 1.0000, 65000.00, NULL, '2026-11-15T07:10:00.0000000', 1, '2026-11-15T07:10:00.0000000', 1, NULL, NULL, 0),
(118, 1, 'PX2611-00047', 'issue', 'sale', 1, NULL, 31, 'sales.SalesOrders', 119, 'DH2611-00049', '2026-11-15T09:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00049', 3.0000, 930000.00, NULL, '2026-11-15T09:10:00.0000000', 1, '2026-11-15T09:10:00.0000000', 1, NULL, NULL, 0),
(119, 1, 'PX2611-00048', 'issue', 'sale', 1, NULL, 41, 'sales.SalesOrders', 120, 'DH2611-00050', '2026-11-15T11:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00050', 3.0000, 295000.00, NULL, '2026-11-15T11:10:00.0000000', 1, '2026-11-15T11:10:00.0000000', 1, NULL, NULL, 0),
(120, 1, 'PX2611-00049', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 121, 'DH2611-00051', '2026-11-15T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00051', 1.0000, 120000.00, NULL, '2026-11-15T12:10:00.0000000', 1, '2026-11-15T12:10:00.0000000', 1, NULL, NULL, 0),
(121, 1, 'PX2611-00050', 'issue', 'sale', 1, NULL, 41, 'sales.SalesOrders', 122, 'DH2611-00052', '2026-11-16T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00052', 2.0000, 240000.00, NULL, '2026-11-16T03:10:00.0000000', 1, '2026-11-16T03:10:00.0000000', 1, NULL, NULL, 0),
(122, 1, 'PX2611-00051', 'issue', 'sale', 1, NULL, 32, 'sales.SalesOrders', 123, 'DH2611-00053', '2026-11-16T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00053', 4.0000, 550000.00, NULL, '2026-11-16T04:10:00.0000000', 1, '2026-11-16T04:10:00.0000000', 1, NULL, NULL, 0),
(123, 1, 'PX2611-00052', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 124, 'DH2611-00054', '2026-11-16T10:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00054', 1.0000, 105000.00, NULL, '2026-11-16T10:10:00.0000000', 1, '2026-11-16T10:10:00.0000000', 1, NULL, NULL, 0),
(124, 1, 'PX2611-00053', 'issue', 'sale', 1, NULL, 33, 'sales.SalesOrders', 125, 'DH2611-00055', '2026-11-16T11:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00055', 2.0000, 515000.00, NULL, '2026-11-16T11:10:00.0000000', 1, '2026-11-16T11:10:00.0000000', 1, NULL, NULL, 0),
(125, 1, 'PX2611-00054', 'issue', 'sale', 1, NULL, 31, 'sales.SalesOrders', 126, 'DH2611-00056', '2026-11-16T13:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00056', 4.0000, 825000.00, NULL, '2026-11-16T13:10:00.0000000', 1, '2026-11-16T13:10:00.0000000', 1, NULL, NULL, 0),
(126, 1, 'PX2611-00055', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 127, 'DH2611-00057', '2026-11-17T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00057', 1.0000, 160000.00, NULL, '2026-11-17T02:10:00.0000000', 1, '2026-11-17T02:10:00.0000000', 1, NULL, NULL, 0),
(127, 1, 'PX2611-00056', 'issue', 'sale', 1, NULL, 41, 'sales.SalesOrders', 128, 'DH2611-00058', '2026-11-17T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00058', 3.0000, 395000.00, NULL, '2026-11-17T03:10:00.0000000', 1, '2026-11-17T03:10:00.0000000', 1, NULL, NULL, 0),
(128, 1, 'PX2611-00057', 'issue', 'sale', 1, NULL, 31, 'sales.SalesOrders', 129, 'DH2611-00059', '2026-11-17T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00059', 2.0000, 130000.00, NULL, '2026-11-17T05:10:00.0000000', 1, '2026-11-17T05:10:00.0000000', 1, NULL, NULL, 0),
(129, 1, 'PX2611-00058', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 130, 'DH2611-00060', '2026-11-17T07:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00060', 1.0000, 310000.00, NULL, '2026-11-17T07:10:00.0000000', 1, '2026-11-17T07:10:00.0000000', 1, NULL, NULL, 0),
(130, 1, 'PX2611-00059', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 131, 'DH2611-00061', '2026-11-17T08:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00061', 1.0000, 150000.00, NULL, '2026-11-17T08:10:00.0000000', 1, '2026-11-17T08:10:00.0000000', 1, NULL, NULL, 0),
(131, 1, 'PX2611-00060', 'issue', 'sale', 1, NULL, 40, 'sales.SalesOrders', 132, 'DH2611-00062', '2026-11-17T08:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00062', 2.0000, 250000.00, NULL, '2026-11-17T08:10:00.0000000', 1, '2026-11-17T08:10:00.0000000', 1, NULL, NULL, 0),
(132, 1, 'PX2611-00061', 'issue', 'sale', 1, NULL, 32, 'sales.SalesOrders', 133, 'DH2611-00063', '2026-11-18T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00063', 3.0000, 260000.00, NULL, '2026-11-18T04:10:00.0000000', 1, '2026-11-18T04:10:00.0000000', 1, NULL, NULL, 0),
(133, 1, 'PX2611-00062', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 134, 'DH2611-00064', '2026-11-18T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00064', 3.0000, 805000.00, NULL, '2026-11-18T06:10:00.0000000', 1, '2026-11-18T06:10:00.0000000', 1, NULL, NULL, 0),
(134, 1, 'PX2611-00063', 'issue', 'sale', 1, NULL, 41, 'sales.SalesOrders', 135, 'DH2611-00065', '2026-11-18T07:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00065', 1.0000, 150000.00, NULL, '2026-11-18T07:10:00.0000000', 1, '2026-11-18T07:10:00.0000000', 1, NULL, NULL, 0),
(135, 1, 'PX2611-00064', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 138, 'DH2611-00068', '2026-11-18T10:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00068', 1.0000, 80000.00, NULL, '2026-11-18T10:10:00.0000000', 1, '2026-11-18T10:10:00.0000000', 1, NULL, NULL, 0),
(136, 1, 'PX2611-00065', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 139, 'DH2611-00069', '2026-11-18T12:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00069', 1.0000, 80000.00, NULL, '2026-11-18T12:10:00.0000000', 1, '2026-11-18T12:10:00.0000000', 1, NULL, NULL, 0),
(137, 1, 'PX2611-00066', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 141, 'DH2611-00071', '2026-11-19T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00071', 2.0000, 515000.00, NULL, '2026-11-19T02:10:00.0000000', 1, '2026-11-19T02:10:00.0000000', 1, NULL, NULL, 0),
(138, 1, 'PX2611-00067', 'issue', 'sale', 1, NULL, 40, 'sales.SalesOrders', 143, 'DH2611-00073', '2026-11-19T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00073', 3.0000, 785000.00, NULL, '2026-11-19T04:10:00.0000000', 1, '2026-11-19T04:10:00.0000000', 1, NULL, NULL, 0),
(139, 1, 'PX2611-00068', 'issue', 'sale', 1, NULL, 31, 'sales.SalesOrders', 144, 'DH2611-00074', '2026-11-19T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00074', 3.0000, 395000.00, NULL, '2026-11-19T05:10:00.0000000', 1, '2026-11-19T05:10:00.0000000', 1, NULL, NULL, 0),
(140, 1, 'PX2611-00069', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 146, 'DH2611-00076', '2026-11-19T08:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00076', 1.0000, 260000.00, NULL, '2026-11-19T08:10:00.0000000', 1, '2026-11-19T08:10:00.0000000', 1, NULL, NULL, 0),
(141, 1, 'PX2611-00070', 'issue', 'sale', 1, NULL, 31, 'sales.SalesOrders', 147, 'DH2611-00077', '2026-11-19T09:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00077', 4.0000, 393000.00, NULL, '2026-11-19T09:10:00.0000000', 1, '2026-11-19T09:10:00.0000000', 1, NULL, NULL, 0),
(142, 1, 'PX2611-00071', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 149, 'DH2611-00079', '2026-11-20T02:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00079', 3.0000, 360000.00, NULL, '2026-11-20T02:10:00.0000000', 1, '2026-11-20T02:10:00.0000000', 1, NULL, NULL, 0),
(143, 1, 'PX2611-00072', 'issue', 'sale', 1, NULL, 41, 'sales.SalesOrders', 150, 'DH2611-00080', '2026-11-20T03:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00080', 1.0000, 120000.00, NULL, '2026-11-20T03:10:00.0000000', 1, '2026-11-20T03:10:00.0000000', 1, NULL, NULL, 0),
(144, 1, 'PX2611-00073', 'issue', 'sale', 1, NULL, 40, 'sales.SalesOrders', 151, 'DH2611-00081', '2026-11-20T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00081', 3.0000, 300000.00, NULL, '2026-11-20T04:10:00.0000000', 1, '2026-11-20T04:10:00.0000000', 1, NULL, NULL, 0),
(145, 1, 'PX2611-00074', 'issue', 'sale', 1, NULL, 40, 'sales.SalesOrders', 152, 'DH2611-00082', '2026-11-20T04:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00082', 2.0000, 93000.00, NULL, '2026-11-20T04:10:00.0000000', 1, '2026-11-20T04:10:00.0000000', 1, NULL, NULL, 0),
(146, 1, 'PX2611-00075', 'issue', 'sale', 1, NULL, 31, 'sales.SalesOrders', 153, 'DH2611-00083', '2026-11-20T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00083', 2.0000, 620000.00, NULL, '2026-11-20T05:10:00.0000000', 1, '2026-11-20T05:10:00.0000000', 1, NULL, NULL, 0),
(147, 1, 'PX2611-00076', 'issue', 'sale', 1, NULL, 39, 'sales.SalesOrders', 154, 'DH2611-00084', '2026-11-20T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00084', 1.0000, 450000.00, NULL, '2026-11-20T05:10:00.0000000', 1, '2026-11-20T05:10:00.0000000', 1, NULL, NULL, 0),
(148, 1, 'PX2611-00077', 'issue', 'sale', 1, NULL, 39, 'sales.SalesOrders', 155, 'DH2611-00085', '2026-11-20T05:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00085', 2.0000, 280000.00, NULL, '2026-11-20T05:10:00.0000000', 1, '2026-11-20T05:10:00.0000000', 1, NULL, NULL, 0),
(149, 1, 'PX2611-00078', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 156, 'DH2611-00086', '2026-11-20T06:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00086', 1.0000, 140000.00, NULL, '2026-11-20T06:10:00.0000000', 1, '2026-11-20T06:10:00.0000000', 1, NULL, NULL, 0),
(150, 1, 'PX2611-00079', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 159, 'DH2611-00089', '2026-11-20T07:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00089', 2.0000, 215000.00, NULL, '2026-11-20T07:10:00.0000000', 1, '2026-11-20T07:10:00.0000000', 1, NULL, NULL, 0),
(151, 1, 'PX2611-00080', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 160, 'DH2611-00090', '2026-11-20T08:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00090', 1.0000, 160000.00, NULL, '2026-11-20T08:10:00.0000000', 1, '2026-11-20T08:10:00.0000000', 1, NULL, NULL, 0),
(152, 1, 'PX2611-00081', 'issue', 'sale', 1, NULL, 39, 'sales.SalesOrders', 162, 'DH2611-00092', '2026-11-20T09:10:00.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00092', 4.0000, 835000.00, NULL, '2026-11-20T09:10:00.0000000', 1, '2026-11-20T09:10:00.0000000', 1, NULL, NULL, 0),
(153, 1, 'PX2611-00082', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 164, 'DH2611-00094', '2026-11-20T08:47:33.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00094', 2.0000, 355000.00, NULL, '2026-11-20T08:47:33.0000000', 1, '2026-11-20T08:47:33.0000000', 1, NULL, NULL, 0),
(154, 1, 'PX2611-00083', 'issue', 'sale', 1, NULL, 30, 'sales.SalesOrders', 165, 'DH2611-00095', '2026-11-20T08:10:33.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00095', 1.0000, 165000.00, NULL, '2026-11-20T08:10:33.0000000', 1, '2026-11-20T08:10:33.0000000', 1, NULL, NULL, 0),
(155, 1, 'PX2611-00084', 'issue', 'sale', 1, NULL, 38, 'sales.SalesOrders', 166, 'DH2611-00096', '2026-11-20T07:33:33.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00096', 1.0000, 310000.00, NULL, '2026-11-20T07:33:33.0000000', 1, '2026-11-20T07:33:33.0000000', 1, NULL, NULL, 0),
(156, 1, 'PX2611-00085', 'issue', 'sale', 1, NULL, 41, 'sales.SalesOrders', 168, 'DH2611-00098', '2026-11-20T06:19:33.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00098', 3.0000, 355000.00, NULL, '2026-11-20T06:19:33.0000000', 1, '2026-11-20T06:19:33.0000000', 1, NULL, NULL, 0),
(157, 1, 'PX2611-00086', 'issue', 'sale', 1, NULL, 29, 'sales.SalesOrders', 169, 'DH2611-00099', '2026-11-20T09:42:33.0000000', 'done', NULL, N'Xuất bán đơn DH2611-00099', 1.0000, 220000.00, NULL, '2026-11-20T09:42:33.0000000', 1, '2026-11-20T09:42:33.0000000', 1, NULL, NULL, 0),
(158, 1, 'PN2611-00001', 'receipt', 'sale_return', 1, NULL, 29, 'sales.SalesReturns', 1, 'TH2611-00001', '2026-11-18T08:00:00.0000000', 'done', NULL, N'Khách trả hàng TH2611-00001 - đơn DH2611-00061', 1.0000, 150000.00, NULL, '2026-11-18T08:00:00.0000000', 1, '2026-11-18T08:00:00.0000000', 1, NULL, NULL, 0),
(159, 1, 'PN2611-00002', 'receipt', 'sale_return', 1, NULL, 29, 'sales.SalesReturns', 3, 'TH2611-00003', '2026-11-16T12:00:00.0000000', 'done', NULL, N'Khách trả hàng TH2611-00003 - đơn DH2611-00051', 1.0000, 120000.00, NULL, '2026-11-16T12:00:00.0000000', 1, '2026-11-16T12:00:00.0000000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [inv].[StockDocuments] OFF;
GO

-- inv.StockLedger (520 dòng)
SET IDENTITY_INSERT [inv].[StockLedger] ON;
INSERT INTO [inv].[StockLedger] ([Id], [CompanyId], [ProductId], [WarehouseId], [LocationId], [LotId], [MoveDate], [QtyIn], [QtyOut], [UnitCost], [ValueIn], [ValueOut], [StockDocumentId], [StockDocumentLineId], [CreatedAt]) VALUES
(1, 1, 1, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 80000.0000, 240000.00, 0.00, 1, 1, '2026-11-20T09:42:54.9010000'),
(2, 1, 2, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 80000.0000, 320000.00, 0.00, 1, 2, '2026-11-20T09:42:54.9010000'),
(3, 1, 3, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 80000.0000, 320000.00, 0.00, 1, 3, '2026-11-20T09:42:54.9010000'),
(4, 1, 25, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 45000.0000, 180000.00, 0.00, 1, 4, '2026-11-20T09:42:54.9010000'),
(5, 1, 26, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 28000.0000, 140000.00, 0.00, 1, 5, '2026-11-20T09:42:54.9010000'),
(6, 1, 38, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 45000.0000, 180000.00, 0.00, 1, 6, '2026-11-20T09:42:54.9010000'),
(7, 1, 40, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 1.0000, 0.0000, 260000.0000, 260000.00, 0.00, 1, 7, '2026-11-20T09:42:54.9010000'),
(8, 1, 41, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 260000.0000, 1300000.00, 0.00, 1, 8, '2026-11-20T09:42:54.9010000'),
(9, 1, 42, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 260000.0000, 1300000.00, 0.00, 1, 9, '2026-11-20T09:42:54.9010000'),
(10, 1, 66, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 70000.0000, 210000.00, 0.00, 1, 10, '2026-11-20T09:42:54.9010000'),
(11, 1, 67, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 70000.0000, 350000.00, 0.00, 1, 11, '2026-11-20T09:42:54.9010000'),
(12, 1, 68, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 70000.0000, 210000.00, 0.00, 1, 12, '2026-11-20T09:42:54.9010000'),
(13, 1, 74, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 65000.0000, 260000.00, 0.00, 1, 13, '2026-11-20T09:42:54.9010000'),
(14, 1, 75, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 65000.0000, 325000.00, 0.00, 1, 14, '2026-11-20T09:42:54.9010000'),
(15, 1, 76, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 65000.0000, 260000.00, 0.00, 1, 15, '2026-11-20T09:42:54.9010000'),
(16, 1, 77, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 65000.0000, 260000.00, 0.00, 1, 16, '2026-11-20T09:42:54.9010000'),
(17, 1, 78, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 105000.0000, 525000.00, 0.00, 1, 17, '2026-11-20T09:42:54.9010000'),
(18, 1, 79, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 105000.0000, 315000.00, 0.00, 1, 18, '2026-11-20T09:42:54.9010000'),
(19, 1, 80, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 105000.0000, 315000.00, 0.00, 1, 19, '2026-11-20T09:42:54.9010000'),
(20, 1, 81, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 105000.0000, 315000.00, 0.00, 1, 20, '2026-11-20T09:42:54.9010000'),
(21, 1, 82, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 80000.0000, 320000.00, 0.00, 1, 21, '2026-11-20T09:42:54.9010000'),
(22, 1, 83, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 80000.0000, 320000.00, 0.00, 1, 22, '2026-11-20T09:42:54.9010000'),
(23, 1, 84, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 80000.0000, 400000.00, 0.00, 1, 23, '2026-11-20T09:42:54.9010000'),
(24, 1, 91, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 120000.0000, 360000.00, 0.00, 1, 24, '2026-11-20T09:42:54.9010000'),
(25, 1, 102, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 28000.0000, 112000.00, 0.00, 1, 25, '2026-11-20T09:42:54.9010000'),
(26, 1, 103, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 120000.0000, 480000.00, 0.00, 1, 26, '2026-11-20T09:42:54.9010000'),
(27, 1, 112, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 80000.0000, 240000.00, 0.00, 1, 27, '2026-11-20T09:42:54.9010000'),
(28, 1, 113, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 80000.0000, 400000.00, 0.00, 1, 28, '2026-11-20T09:42:54.9010000'),
(29, 1, 114, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 80000.0000, 320000.00, 0.00, 1, 29, '2026-11-20T09:42:54.9010000'),
(30, 1, 115, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 65000.0000, 325000.00, 0.00, 1, 30, '2026-11-20T09:42:54.9010000'),
(31, 1, 116, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 65000.0000, 195000.00, 0.00, 1, 31, '2026-11-20T09:42:54.9010000'),
(32, 1, 117, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 6.0000, 0.0000, 65000.0000, 390000.00, 0.00, 1, 32, '2026-11-20T09:42:54.9010000'),
(33, 1, 118, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 65000.0000, 195000.00, 0.00, 1, 33, '2026-11-20T09:42:54.9010000'),
(34, 1, 123, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 105000.0000, 315000.00, 0.00, 1, 34, '2026-11-20T09:42:54.9010000'),
(35, 1, 124, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 105000.0000, 315000.00, 0.00, 1, 35, '2026-11-20T09:42:54.9010000'),
(36, 1, 125, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 105000.0000, 315000.00, 0.00, 1, 36, '2026-11-20T09:42:54.9010000'),
(37, 1, 126, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 105000.0000, 420000.00, 0.00, 1, 37, '2026-11-20T09:42:54.9010000'),
(38, 1, 130, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 6.0000, 0.0000, 65000.0000, 390000.00, 0.00, 1, 38, '2026-11-20T09:42:54.9010000'),
(39, 1, 131, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 65000.0000, 260000.00, 0.00, 1, 39, '2026-11-20T09:42:54.9010000'),
(40, 1, 132, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 65000.0000, 260000.00, 0.00, 1, 40, '2026-11-20T09:42:54.9010000'),
(41, 1, 133, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 65000.0000, 195000.00, 0.00, 1, 41, '2026-11-20T09:42:54.9010000'),
(42, 1, 134, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 70000.0000, 210000.00, 0.00, 1, 42, '2026-11-20T09:42:54.9010000'),
(43, 1, 135, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 70000.0000, 280000.00, 0.00, 1, 43, '2026-11-20T09:42:54.9010000'),
(44, 1, 136, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 70000.0000, 280000.00, 0.00, 1, 44, '2026-11-20T09:42:54.9010000'),
(45, 1, 140, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 120000.0000, 360000.00, 0.00, 1, 45, '2026-11-20T09:42:54.9010000'),
(46, 1, 150, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 65000.0000, 325000.00, 0.00, 1, 46, '2026-11-20T09:42:54.9010000'),
(47, 1, 151, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 65000.0000, 195000.00, 0.00, 1, 47, '2026-11-20T09:42:54.9010000'),
(48, 1, 152, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 65000.0000, 195000.00, 0.00, 1, 48, '2026-11-20T09:42:54.9010000'),
(49, 1, 153, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 65000.0000, 325000.00, 0.00, 1, 49, '2026-11-20T09:42:54.9010000'),
(50, 1, 154, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 105000.0000, 315000.00, 0.00, 1, 50, '2026-11-20T09:42:54.9010000'),
(51, 1, 155, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 105000.0000, 420000.00, 0.00, 1, 51, '2026-11-20T09:42:54.9010000'),
(52, 1, 156, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 5.0000, 0.0000, 105000.0000, 525000.00, 0.00, 1, 52, '2026-11-20T09:42:54.9010000'),
(53, 1, 157, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 3.0000, 0.0000, 105000.0000, 315000.00, 0.00, 1, 53, '2026-11-20T09:42:54.9010000'),
(54, 1, 162, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 45000.0000, 180000.00, 0.00, 1, 54, '2026-11-20T09:42:54.9010000'),
(55, 1, 166, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 6.0000, 0.0000, 260000.0000, 1560000.00, 0.00, 1, 55, '2026-11-20T09:42:54.9010000'),
(56, 1, 167, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 9.0000, 0.0000, 260000.0000, 2340000.00, 0.00, 1, 56, '2026-11-20T09:42:54.9010000'),
(57, 1, 168, 1, NULL, NULL, '2026-09-24T12:42:55.0000000', 4.0000, 0.0000, 260000.0000, 1040000.00, 0.00, 1, 57, '2026-11-20T09:42:54.9010000'),
(58, 1, 4, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 8.0000, 0.0000, 150000.0000, 1200000.00, 0.00, 2, 58, '2026-11-20T09:42:54.9040000'),
(59, 1, 5, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 12.0000, 0.0000, 150000.0000, 1800000.00, 0.00, 2, 59, '2026-11-20T09:42:54.9040000'),
(60, 1, 6, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 12.0000, 0.0000, 150000.0000, 1800000.00, 0.00, 2, 60, '2026-11-20T09:42:54.9040000'),
(61, 1, 7, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 5.0000, 0.0000, 165000.0000, 825000.00, 0.00, 2, 61, '2026-11-20T09:42:54.9040000'),
(62, 1, 8, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 11.0000, 0.0000, 165000.0000, 1815000.00, 0.00, 2, 62, '2026-11-20T09:42:54.9040000'),
(63, 1, 9, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 16.0000, 0.0000, 165000.0000, 2640000.00, 0.00, 2, 63, '2026-11-20T09:42:54.9040000'),
(64, 1, 10, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 1.0000, 0.0000, 165000.0000, 165000.00, 0.00, 2, 64, '2026-11-20T09:42:54.9040000'),
(65, 1, 11, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 7.0000, 0.0000, 110000.0000, 770000.00, 0.00, 2, 65, '2026-11-20T09:42:54.9040000'),
(66, 1, 12, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 8.0000, 0.0000, 110000.0000, 880000.00, 0.00, 2, 66, '2026-11-20T09:42:54.9040000'),
(67, 1, 13, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 2.0000, 0.0000, 110000.0000, 220000.00, 0.00, 2, 67, '2026-11-20T09:42:54.9040000'),
(68, 1, 39, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 14.0000, 0.0000, 190000.0000, 2660000.00, 0.00, 2, 68, '2026-11-20T09:42:54.9040000'),
(69, 1, 43, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 2.0000, 0.0000, 110000.0000, 220000.00, 0.00, 2, 69, '2026-11-20T09:42:54.9040000'),
(70, 1, 44, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 11.0000, 0.0000, 110000.0000, 1210000.00, 0.00, 2, 70, '2026-11-20T09:42:54.9040000'),
(71, 1, 45, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 8.0000, 0.0000, 110000.0000, 880000.00, 0.00, 2, 71, '2026-11-20T09:42:54.9040000'),
(72, 1, 59, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 11.0000, 0.0000, 165000.0000, 1815000.00, 0.00, 2, 72, '2026-11-20T09:42:54.9040000'),
(73, 1, 60, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 1.0000, 0.0000, 165000.0000, 165000.00, 0.00, 2, 73, '2026-11-20T09:42:54.9040000'),
(74, 1, 61, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 8.0000, 0.0000, 165000.0000, 1320000.00, 0.00, 2, 74, '2026-11-20T09:42:54.9040000'),
(75, 1, 62, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 13.0000, 0.0000, 165000.0000, 2145000.00, 0.00, 2, 75, '2026-11-20T09:42:54.9040000'),
(76, 1, 85, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 9.0000, 0.0000, 160000.0000, 1440000.00, 0.00, 2, 76, '2026-11-20T09:42:54.9040000'),
(77, 1, 86, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 14.0000, 0.0000, 160000.0000, 2240000.00, 0.00, 2, 77, '2026-11-20T09:42:54.9040000'),
(78, 1, 87, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 7.0000, 0.0000, 160000.0000, 1120000.00, 0.00, 2, 78, '2026-11-20T09:42:54.9040000'),
(79, 1, 88, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 8.0000, 0.0000, 150000.0000, 1200000.00, 0.00, 2, 79, '2026-11-20T09:42:54.9040000'),
(80, 1, 89, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 11.0000, 0.0000, 150000.0000, 1650000.00, 0.00, 2, 80, '2026-11-20T09:42:54.9040000'),
(81, 1, 90, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 2.0000, 0.0000, 150000.0000, 300000.00, 0.00, 2, 81, '2026-11-20T09:42:54.9040000'),
(82, 1, 92, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 12.0000, 0.0000, 160000.0000, 1920000.00, 0.00, 2, 82, '2026-11-20T09:42:54.9040000'),
(83, 1, 93, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 2.0000, 0.0000, 160000.0000, 320000.00, 0.00, 2, 83, '2026-11-20T09:42:54.9040000'),
(84, 1, 94, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 9.0000, 0.0000, 160000.0000, 1440000.00, 0.00, 2, 84, '2026-11-20T09:42:54.9040000'),
(85, 1, 95, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 9.0000, 0.0000, 190000.0000, 1710000.00, 0.00, 2, 85, '2026-11-20T09:42:54.9040000'),
(86, 1, 96, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 13.0000, 0.0000, 190000.0000, 2470000.00, 0.00, 2, 86, '2026-11-20T09:42:54.9040000'),
(87, 1, 119, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 11.0000, 0.0000, 140000.0000, 1540000.00, 0.00, 2, 87, '2026-11-20T09:42:54.9040000'),
(88, 1, 120, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 7.0000, 0.0000, 140000.0000, 980000.00, 0.00, 2, 88, '2026-11-20T09:42:54.9040000'),
(89, 1, 121, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 7.0000, 0.0000, 140000.0000, 980000.00, 0.00, 2, 89, '2026-11-20T09:42:54.9040000'),
(90, 1, 122, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 11.0000, 0.0000, 140000.0000, 1540000.00, 0.00, 2, 90, '2026-11-20T09:42:54.9040000'),
(91, 1, 127, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 8.0000, 0.0000, 150000.0000, 1200000.00, 0.00, 2, 91, '2026-11-20T09:42:54.9040000'),
(92, 1, 128, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 8.0000, 0.0000, 150000.0000, 1200000.00, 0.00, 2, 92, '2026-11-20T09:42:54.9040000'),
(93, 1, 129, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 13.0000, 0.0000, 150000.0000, 1950000.00, 0.00, 2, 93, '2026-11-20T09:42:54.9040000'),
(94, 1, 137, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 6.0000, 0.0000, 160000.0000, 960000.00, 0.00, 2, 94, '2026-11-20T09:42:54.9040000'),
(95, 1, 138, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 10.0000, 0.0000, 160000.0000, 1600000.00, 0.00, 2, 95, '2026-11-20T09:42:54.9040000'),
(96, 1, 139, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 16.0000, 0.0000, 160000.0000, 2560000.00, 0.00, 2, 96, '2026-11-20T09:42:54.9040000'),
(97, 1, 141, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 8.0000, 0.0000, 140000.0000, 1120000.00, 0.00, 2, 97, '2026-11-20T09:42:54.9040000'),
(98, 1, 142, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 12.0000, 0.0000, 140000.0000, 1680000.00, 0.00, 2, 98, '2026-11-20T09:42:54.9040000'),
(99, 1, 143, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 5.0000, 0.0000, 140000.0000, 700000.00, 0.00, 2, 99, '2026-11-20T09:42:54.9040000'),
(100, 1, 144, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 6.0000, 0.0000, 140000.0000, 840000.00, 0.00, 2, 100, '2026-11-20T09:42:54.9040000'),
(101, 1, 158, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 10.0000, 0.0000, 165000.0000, 1650000.00, 0.00, 2, 101, '2026-11-20T09:42:54.9040000'),
(102, 1, 159, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 14.0000, 0.0000, 165000.0000, 2310000.00, 0.00, 2, 102, '2026-11-20T09:42:54.9040000'),
(103, 1, 160, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 1.0000, 0.0000, 165000.0000, 165000.00, 0.00, 2, 103, '2026-11-20T09:42:54.9040000'),
(104, 1, 161, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 8.0000, 0.0000, 165000.0000, 1320000.00, 0.00, 2, 104, '2026-11-20T09:42:54.9040000'),
(105, 1, 63, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 4.0000, 0.0000, 185000.0000, 740000.00, 0.00, 3, 105, '2026-11-20T09:42:54.9050000'),
(106, 1, 64, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 3.0000, 0.0000, 185000.0000, 555000.00, 0.00, 3, 106, '2026-11-20T09:42:54.9050000'),
(107, 1, 65, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 4.0000, 0.0000, 185000.0000, 740000.00, 0.00, 3, 107, '2026-11-20T09:42:54.9050000'),
(108, 1, 69, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 7.0000, 0.0000, 200000.0000, 1400000.00, 0.00, 3, 108, '2026-11-20T09:42:54.9050000'),
(109, 1, 70, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 4.0000, 0.0000, 200000.0000, 800000.00, 0.00, 3, 109, '2026-11-20T09:42:54.9050000'),
(110, 1, 71, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 5.0000, 0.0000, 200000.0000, 1000000.00, 0.00, 3, 110, '2026-11-20T09:42:54.9050000'),
(111, 1, 72, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 4.0000, 0.0000, 200000.0000, 800000.00, 0.00, 3, 111, '2026-11-20T09:42:54.9050000'),
(112, 1, 73, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 6.0000, 0.0000, 200000.0000, 1200000.00, 0.00, 3, 112, '2026-11-20T09:42:54.9050000'),
(113, 1, 145, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 3.0000, 0.0000, 200000.0000, 600000.00, 0.00, 3, 113, '2026-11-20T09:42:54.9050000'),
(114, 1, 146, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 6.0000, 0.0000, 200000.0000, 1200000.00, 0.00, 3, 114, '2026-11-20T09:42:54.9050000'),
(115, 1, 147, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 3.0000, 0.0000, 200000.0000, 600000.00, 0.00, 3, 115, '2026-11-20T09:42:54.9050000'),
(116, 1, 148, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 7.0000, 0.0000, 200000.0000, 1400000.00, 0.00, 3, 116, '2026-11-20T09:42:54.9050000'),
(117, 1, 149, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 3.0000, 0.0000, 200000.0000, 600000.00, 0.00, 3, 117, '2026-11-20T09:42:54.9050000'),
(118, 1, 163, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 3.0000, 0.0000, 185000.0000, 555000.00, 0.00, 3, 118, '2026-11-20T09:42:54.9050000'),
(119, 1, 164, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 3.0000, 0.0000, 185000.0000, 555000.00, 0.00, 3, 119, '2026-11-20T09:42:54.9050000'),
(120, 1, 165, 1, NULL, NULL, '2026-09-25T12:42:55.0000000', 5.0000, 0.0000, 185000.0000, 925000.00, 0.00, 3, 120, '2026-11-20T09:42:54.9050000'),
(121, 1, 14, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 5.0000, 0.0000, 95000.0000, 475000.00, 0.00, 4, 121, '2026-11-20T09:42:54.9070000'),
(122, 1, 15, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 95000.0000, 285000.00, 0.00, 4, 122, '2026-11-20T09:42:54.9070000'),
(123, 1, 16, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 95000.0000, 285000.00, 0.00, 4, 123, '2026-11-20T09:42:54.9070000'),
(124, 1, 17, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 5.0000, 0.0000, 95000.0000, 475000.00, 0.00, 4, 124, '2026-11-20T09:42:54.9070000'),
(125, 1, 18, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 95000.0000, 285000.00, 0.00, 4, 125, '2026-11-20T09:42:54.9070000'),
(126, 1, 19, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 95000.0000, 285000.00, 0.00, 4, 126, '2026-11-20T09:42:54.9070000'),
(127, 1, 20, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 2.0000, 0.0000, 220000.0000, 440000.00, 0.00, 4, 127, '2026-11-20T09:42:54.9070000'),
(128, 1, 21, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 4.0000, 0.0000, 220000.0000, 880000.00, 0.00, 4, 128, '2026-11-20T09:42:54.9070000'),
(129, 1, 22, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 14.0000, 0.0000, 220000.0000, 3080000.00, 0.00, 4, 129, '2026-11-20T09:42:54.9070000'),
(130, 1, 23, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 2.0000, 0.0000, 220000.0000, 440000.00, 0.00, 4, 130, '2026-11-20T09:42:54.9070000'),
(131, 1, 24, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 8.0000, 0.0000, 220000.0000, 1760000.00, 0.00, 4, 131, '2026-11-20T09:42:54.9070000'),
(132, 1, 27, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 5.0000, 0.0000, 450000.0000, 2250000.00, 0.00, 4, 132, '2026-11-20T09:42:54.9070000'),
(133, 1, 28, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 4.0000, 0.0000, 450000.0000, 1800000.00, 0.00, 4, 133, '2026-11-20T09:42:54.9070000'),
(134, 1, 29, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 10.0000, 0.0000, 450000.0000, 4500000.00, 0.00, 4, 134, '2026-11-20T09:42:54.9070000'),
(135, 1, 30, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 1.0000, 0.0000, 450000.0000, 450000.00, 0.00, 4, 135, '2026-11-20T09:42:54.9070000'),
(136, 1, 31, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 10.0000, 0.0000, 450000.0000, 4500000.00, 0.00, 4, 136, '2026-11-20T09:42:54.9070000'),
(137, 1, 32, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 5.0000, 0.0000, 95000.0000, 475000.00, 0.00, 4, 137, '2026-11-20T09:42:54.9070000'),
(138, 1, 33, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 95000.0000, 285000.00, 0.00, 4, 138, '2026-11-20T09:42:54.9070000'),
(139, 1, 34, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 5.0000, 0.0000, 95000.0000, 475000.00, 0.00, 4, 139, '2026-11-20T09:42:54.9070000'),
(140, 1, 35, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 95000.0000, 285000.00, 0.00, 4, 140, '2026-11-20T09:42:54.9070000'),
(141, 1, 36, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 5.0000, 0.0000, 95000.0000, 475000.00, 0.00, 4, 141, '2026-11-20T09:42:54.9070000'),
(142, 1, 37, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 95000.0000, 285000.00, 0.00, 4, 142, '2026-11-20T09:42:54.9070000'),
(143, 1, 46, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 310000.0000, 930000.00, 0.00, 4, 143, '2026-11-20T09:42:54.9070000'),
(144, 1, 47, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 6.0000, 0.0000, 310000.0000, 1860000.00, 0.00, 4, 144, '2026-11-20T09:42:54.9070000'),
(145, 1, 48, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 310000.0000, 930000.00, 0.00, 4, 145, '2026-11-20T09:42:54.9070000'),
(146, 1, 49, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 310000.0000, 930000.00, 0.00, 4, 146, '2026-11-20T09:42:54.9070000'),
(147, 1, 50, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 4.0000, 0.0000, 310000.0000, 1240000.00, 0.00, 4, 147, '2026-11-20T09:42:54.9070000'),
(148, 1, 51, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 310000.0000, 930000.00, 0.00, 4, 148, '2026-11-20T09:42:54.9070000'),
(149, 1, 52, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 310000.0000, 930000.00, 0.00, 4, 149, '2026-11-20T09:42:54.9070000'),
(150, 1, 53, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 310000.0000, 930000.00, 0.00, 4, 150, '2026-11-20T09:42:54.9070000'),
(151, 1, 54, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 6.0000, 0.0000, 220000.0000, 1320000.00, 0.00, 4, 151, '2026-11-20T09:42:54.9070000'),
(152, 1, 55, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 5.0000, 0.0000, 220000.0000, 1100000.00, 0.00, 4, 152, '2026-11-20T09:42:54.9070000'),
(153, 1, 56, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 5.0000, 0.0000, 220000.0000, 1100000.00, 0.00, 4, 153, '2026-11-20T09:42:54.9070000'),
(154, 1, 57, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 10.0000, 0.0000, 220000.0000, 2200000.00, 0.00, 4, 154, '2026-11-20T09:42:54.9070000'),
(155, 1, 58, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 12.0000, 0.0000, 220000.0000, 2640000.00, 0.00, 4, 155, '2026-11-20T09:42:54.9070000'),
(156, 1, 97, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 7.0000, 0.0000, 450000.0000, 3150000.00, 0.00, 4, 156, '2026-11-20T09:42:54.9070000'),
(157, 1, 98, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 4.0000, 0.0000, 450000.0000, 1800000.00, 0.00, 4, 157, '2026-11-20T09:42:54.9070000'),
(158, 1, 99, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 13.0000, 0.0000, 450000.0000, 5850000.00, 0.00, 4, 158, '2026-11-20T09:42:54.9070000'),
(159, 1, 100, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 1.0000, 0.0000, 450000.0000, 450000.00, 0.00, 4, 159, '2026-11-20T09:42:54.9070000'),
(160, 1, 101, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 8.0000, 0.0000, 450000.0000, 3600000.00, 0.00, 4, 160, '2026-11-20T09:42:54.9070000'),
(161, 1, 104, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 4.0000, 0.0000, 310000.0000, 1240000.00, 0.00, 4, 161, '2026-11-20T09:42:54.9070000'),
(162, 1, 105, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 310000.0000, 930000.00, 0.00, 4, 162, '2026-11-20T09:42:54.9070000'),
(163, 1, 106, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 7.0000, 0.0000, 310000.0000, 2170000.00, 0.00, 4, 163, '2026-11-20T09:42:54.9070000'),
(164, 1, 107, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 4.0000, 0.0000, 310000.0000, 1240000.00, 0.00, 4, 164, '2026-11-20T09:42:54.9070000'),
(165, 1, 108, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 5.0000, 0.0000, 310000.0000, 1550000.00, 0.00, 4, 165, '2026-11-20T09:42:54.9070000'),
(166, 1, 109, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 4.0000, 0.0000, 310000.0000, 1240000.00, 0.00, 4, 166, '2026-11-20T09:42:54.9070000'),
(167, 1, 110, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 6.0000, 0.0000, 310000.0000, 1860000.00, 0.00, 4, 167, '2026-11-20T09:42:54.9070000'),
(168, 1, 111, 1, NULL, NULL, '2026-09-26T12:42:55.0000000', 3.0000, 0.0000, 310000.0000, 930000.00, 0.00, 4, 168, '2026-11-20T09:42:54.9070000'),
(169, 1, 1, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 80000.0000, 160000.00, 0.00, 5, 169, '2026-11-20T09:42:54.9080000'),
(170, 1, 2, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 5.0000, 0.0000, 80000.0000, 400000.00, 0.00, 5, 170, '2026-11-20T09:42:54.9080000'),
(171, 1, 3, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 80000.0000, 160000.00, 0.00, 5, 171, '2026-11-20T09:42:54.9080000'),
(172, 1, 25, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 6.0000, 0.0000, 45000.0000, 270000.00, 0.00, 5, 172, '2026-11-20T09:42:54.9080000'),
(173, 1, 26, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 3.0000, 0.0000, 28000.0000, 84000.00, 0.00, 5, 173, '2026-11-20T09:42:54.9080000'),
(174, 1, 38, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 6.0000, 0.0000, 45000.0000, 270000.00, 0.00, 5, 174, '2026-11-20T09:42:54.9080000'),
(175, 1, 66, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 9.0000, 0.0000, 70000.0000, 630000.00, 0.00, 5, 175, '2026-11-20T09:42:54.9080000'),
(176, 1, 67, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 70000.0000, 140000.00, 0.00, 5, 176, '2026-11-20T09:42:54.9080000'),
(177, 1, 68, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 8.0000, 0.0000, 70000.0000, 560000.00, 0.00, 5, 177, '2026-11-20T09:42:54.9080000'),
(178, 1, 74, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 178, '2026-11-20T09:42:54.9080000'),
(179, 1, 75, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 179, '2026-11-20T09:42:54.9080000'),
(180, 1, 76, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 4.0000, 0.0000, 65000.0000, 260000.00, 0.00, 5, 180, '2026-11-20T09:42:54.9080000'),
(181, 1, 77, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 4.0000, 0.0000, 65000.0000, 260000.00, 0.00, 5, 181, '2026-11-20T09:42:54.9080000'),
(182, 1, 78, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 7.0000, 0.0000, 105000.0000, 735000.00, 0.00, 5, 182, '2026-11-20T09:42:54.9080000'),
(183, 1, 79, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 8.0000, 0.0000, 105000.0000, 840000.00, 0.00, 5, 183, '2026-11-20T09:42:54.9080000'),
(184, 1, 80, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 105000.0000, 210000.00, 0.00, 5, 184, '2026-11-20T09:42:54.9080000'),
(185, 1, 81, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 5.0000, 0.0000, 105000.0000, 525000.00, 0.00, 5, 185, '2026-11-20T09:42:54.9080000'),
(186, 1, 82, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 3.0000, 0.0000, 80000.0000, 240000.00, 0.00, 5, 186, '2026-11-20T09:42:54.9080000'),
(187, 1, 83, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 80000.0000, 160000.00, 0.00, 5, 187, '2026-11-20T09:42:54.9080000'),
(188, 1, 84, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 5.0000, 0.0000, 80000.0000, 400000.00, 0.00, 5, 188, '2026-11-20T09:42:54.9080000'),
(189, 1, 91, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 6.0000, 0.0000, 120000.0000, 720000.00, 0.00, 5, 189, '2026-11-20T09:42:54.9080000'),
(190, 1, 102, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 3.0000, 0.0000, 28000.0000, 84000.00, 0.00, 5, 190, '2026-11-20T09:42:54.9080000'),
(191, 1, 103, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 120000.0000, 240000.00, 0.00, 5, 191, '2026-11-20T09:42:54.9080000'),
(192, 1, 112, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 3.0000, 0.0000, 80000.0000, 240000.00, 0.00, 5, 192, '2026-11-20T09:42:54.9080000'),
(193, 1, 113, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 80000.0000, 160000.00, 0.00, 5, 193, '2026-11-20T09:42:54.9080000'),
(194, 1, 114, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 80000.0000, 160000.00, 0.00, 5, 194, '2026-11-20T09:42:54.9080000'),
(195, 1, 115, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 3.0000, 0.0000, 65000.0000, 195000.00, 0.00, 5, 195, '2026-11-20T09:42:54.9080000'),
(196, 1, 116, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 196, '2026-11-20T09:42:54.9080000'),
(197, 1, 117, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 4.0000, 0.0000, 65000.0000, 260000.00, 0.00, 5, 197, '2026-11-20T09:42:54.9080000'),
(198, 1, 118, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 198, '2026-11-20T09:42:54.9080000'),
(199, 1, 123, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 105000.0000, 210000.00, 0.00, 5, 199, '2026-11-20T09:42:54.9080000'),
(200, 1, 124, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 6.0000, 0.0000, 105000.0000, 630000.00, 0.00, 5, 200, '2026-11-20T09:42:54.9080000'),
(201, 1, 125, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 7.0000, 0.0000, 105000.0000, 735000.00, 0.00, 5, 201, '2026-11-20T09:42:54.9080000'),
(202, 1, 126, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 9.0000, 0.0000, 105000.0000, 945000.00, 0.00, 5, 202, '2026-11-20T09:42:54.9080000'),
(203, 1, 130, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 203, '2026-11-20T09:42:54.9080000'),
(204, 1, 131, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 204, '2026-11-20T09:42:54.9080000'),
(205, 1, 132, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 205, '2026-11-20T09:42:54.9080000'),
(206, 1, 133, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 206, '2026-11-20T09:42:54.9080000'),
(207, 1, 134, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 4.0000, 0.0000, 70000.0000, 280000.00, 0.00, 5, 207, '2026-11-20T09:42:54.9080000'),
(208, 1, 135, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 8.0000, 0.0000, 70000.0000, 560000.00, 0.00, 5, 208, '2026-11-20T09:42:54.9080000'),
(209, 1, 136, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 11.0000, 0.0000, 70000.0000, 770000.00, 0.00, 5, 209, '2026-11-20T09:42:54.9080000'),
(210, 1, 140, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 120000.0000, 240000.00, 0.00, 5, 210, '2026-11-20T09:42:54.9080000'),
(211, 1, 150, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 211, '2026-11-20T09:42:54.9080000'),
(212, 1, 151, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 212, '2026-11-20T09:42:54.9080000'),
(213, 1, 152, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 213, '2026-11-20T09:42:54.9080000'),
(214, 1, 153, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 2.0000, 0.0000, 65000.0000, 130000.00, 0.00, 5, 214, '2026-11-20T09:42:54.9080000'),
(215, 1, 154, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 5.0000, 0.0000, 105000.0000, 525000.00, 0.00, 5, 215, '2026-11-20T09:42:54.9080000'),
(216, 1, 155, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 6.0000, 0.0000, 105000.0000, 630000.00, 0.00, 5, 216, '2026-11-20T09:42:54.9080000'),
(217, 1, 156, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 12.0000, 0.0000, 105000.0000, 1260000.00, 0.00, 5, 217, '2026-11-20T09:42:54.9080000'),
(218, 1, 157, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 3.0000, 0.0000, 105000.0000, 315000.00, 0.00, 5, 218, '2026-11-20T09:42:54.9080000'),
(219, 1, 162, 1, NULL, NULL, '2026-10-28T12:42:55.0000000', 8.0000, 0.0000, 45000.0000, 360000.00, 0.00, 5, 219, '2026-11-20T09:42:54.9080000'),
(220, 1, 63, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 185000.0000, 370000.00, 0.00, 6, 220, '2026-11-20T09:42:54.9100000'),
(221, 1, 64, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 4.0000, 0.0000, 185000.0000, 740000.00, 0.00, 6, 221, '2026-11-20T09:42:54.9100000'),
(222, 1, 65, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 6.0000, 0.0000, 185000.0000, 1110000.00, 0.00, 6, 222, '2026-11-20T09:42:54.9100000'),
(223, 1, 69, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 200000.0000, 400000.00, 0.00, 6, 223, '2026-11-20T09:42:54.9100000'),
(224, 1, 70, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 200000.0000, 400000.00, 0.00, 6, 224, '2026-11-20T09:42:54.9100000'),
(225, 1, 71, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 200000.0000, 400000.00, 0.00, 6, 225, '2026-11-20T09:42:54.9100000'),
(226, 1, 72, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 200000.0000, 400000.00, 0.00, 6, 226, '2026-11-20T09:42:54.9100000'),
(227, 1, 73, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 200000.0000, 400000.00, 0.00, 6, 227, '2026-11-20T09:42:54.9100000'),
(228, 1, 145, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 200000.0000, 400000.00, 0.00, 6, 228, '2026-11-20T09:42:54.9100000'),
(229, 1, 146, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 200000.0000, 400000.00, 0.00, 6, 229, '2026-11-20T09:42:54.9100000'),
(230, 1, 147, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 200000.0000, 400000.00, 0.00, 6, 230, '2026-11-20T09:42:54.9100000'),
(231, 1, 148, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 200000.0000, 400000.00, 0.00, 6, 231, '2026-11-20T09:42:54.9100000'),
(232, 1, 149, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 200000.0000, 400000.00, 0.00, 6, 232, '2026-11-20T09:42:54.9100000'),
(233, 1, 163, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 2.0000, 0.0000, 185000.0000, 370000.00, 0.00, 6, 233, '2026-11-20T09:42:54.9100000'),
(234, 1, 164, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 4.0000, 0.0000, 185000.0000, 740000.00, 0.00, 6, 234, '2026-11-20T09:42:54.9100000'),
(235, 1, 165, 1, NULL, NULL, '2026-10-29T12:42:55.0000000', 8.0000, 0.0000, 185000.0000, 1480000.00, 0.00, 6, 235, '2026-11-20T09:42:54.9100000'),
(236, 1, 14, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 4.0000, 0.0000, 95000.0000, 380000.00, 0.00, 7, 236, '2026-11-20T09:42:54.9120000'),
(237, 1, 15, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 6.0000, 0.0000, 95000.0000, 570000.00, 0.00, 7, 237, '2026-11-20T09:42:54.9120000'),
(238, 1, 16, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 10.0000, 0.0000, 95000.0000, 950000.00, 0.00, 7, 238, '2026-11-20T09:42:54.9120000'),
(239, 1, 17, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 95000.0000, 190000.00, 0.00, 7, 239, '2026-11-20T09:42:54.9120000'),
(240, 1, 18, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 5.0000, 0.0000, 95000.0000, 475000.00, 0.00, 7, 240, '2026-11-20T09:42:54.9120000'),
(241, 1, 19, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 8.0000, 0.0000, 95000.0000, 760000.00, 0.00, 7, 241, '2026-11-20T09:42:54.9120000'),
(242, 1, 32, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 8.0000, 0.0000, 95000.0000, 760000.00, 0.00, 7, 242, '2026-11-20T09:42:54.9120000'),
(243, 1, 33, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 95000.0000, 190000.00, 0.00, 7, 243, '2026-11-20T09:42:54.9120000'),
(244, 1, 34, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 4.0000, 0.0000, 95000.0000, 380000.00, 0.00, 7, 244, '2026-11-20T09:42:54.9120000'),
(245, 1, 35, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 9.0000, 0.0000, 95000.0000, 855000.00, 0.00, 7, 245, '2026-11-20T09:42:54.9120000'),
(246, 1, 36, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 12.0000, 0.0000, 95000.0000, 1140000.00, 0.00, 7, 246, '2026-11-20T09:42:54.9120000'),
(247, 1, 37, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 95000.0000, 190000.00, 0.00, 7, 247, '2026-11-20T09:42:54.9120000'),
(248, 1, 46, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 4.0000, 0.0000, 310000.0000, 1240000.00, 0.00, 7, 248, '2026-11-20T09:42:54.9120000'),
(249, 1, 47, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 249, '2026-11-20T09:42:54.9120000'),
(250, 1, 48, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 5.0000, 0.0000, 310000.0000, 1550000.00, 0.00, 7, 250, '2026-11-20T09:42:54.9120000'),
(251, 1, 49, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 251, '2026-11-20T09:42:54.9120000'),
(252, 1, 50, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 252, '2026-11-20T09:42:54.9120000'),
(253, 1, 51, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 253, '2026-11-20T09:42:54.9120000'),
(254, 1, 52, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 254, '2026-11-20T09:42:54.9120000'),
(255, 1, 53, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 255, '2026-11-20T09:42:54.9120000'),
(256, 1, 104, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 256, '2026-11-20T09:42:54.9120000'),
(257, 1, 105, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 257, '2026-11-20T09:42:54.9120000'),
(258, 1, 106, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 3.0000, 0.0000, 310000.0000, 930000.00, 0.00, 7, 258, '2026-11-20T09:42:54.9120000'),
(259, 1, 107, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 3.0000, 0.0000, 310000.0000, 930000.00, 0.00, 7, 259, '2026-11-20T09:42:54.9120000'),
(260, 1, 108, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 260, '2026-11-20T09:42:54.9120000'),
(261, 1, 109, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 261, '2026-11-20T09:42:54.9120000'),
(262, 1, 110, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 262, '2026-11-20T09:42:54.9120000'),
(263, 1, 111, 1, NULL, NULL, '2026-10-30T12:42:55.0000000', 2.0000, 0.0000, 310000.0000, 620000.00, 0.00, 7, 263, '2026-11-20T09:42:54.9120000'),
(264, 1, 5, 1, NULL, NULL, '2026-09-24T02:10:00.0000000', 0.0000, 1.0000, 150000.0000, 0.00, 150000.00, 8, 264, '2026-11-20T09:42:54.9440000'),
(265, 1, 75, 1, NULL, NULL, '2026-09-24T02:10:00.0000000', 0.0000, 2.0000, 65000.0000, 0.00, 130000.00, 8, 265, '2026-11-20T09:42:54.9440000'),
(266, 1, 131, 1, NULL, NULL, '2026-09-24T02:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 8, 266, '2026-11-20T09:42:54.9440000'),
(267, 1, 146, 1, NULL, NULL, '2026-09-25T03:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 9, 267, '2026-11-20T09:42:54.9450000'),
(268, 1, 47, 1, NULL, NULL, '2026-09-25T03:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 9, 268, '2026-11-20T09:42:54.9450000'),
(269, 1, 62, 1, NULL, NULL, '2026-09-25T09:10:00.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 10, 269, '2026-11-20T09:42:54.9460000'),
(270, 1, 117, 1, NULL, NULL, '2026-09-25T09:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 10, 270, '2026-11-20T09:42:54.9460000'),
(271, 1, 106, 1, NULL, NULL, '2026-09-25T12:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 11, 271, '2026-11-20T09:42:54.9460000'),
(272, 1, 158, 1, NULL, NULL, '2026-09-25T12:10:00.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 11, 272, '2026-11-20T09:42:54.9460000'),
(273, 1, 94, 1, NULL, NULL, '2026-09-27T03:10:00.0000000', 0.0000, 2.0000, 160000.0000, 0.00, 320000.00, 12, 273, '2026-11-20T09:42:54.9470000'),
(274, 1, 69, 1, NULL, NULL, '2026-09-28T04:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 13, 274, '2026-11-20T09:42:54.9470000'),
(275, 1, 136, 1, NULL, NULL, '2026-09-28T06:10:00.0000000', 0.0000, 1.0000, 70000.0000, 0.00, 70000.00, 14, 275, '2026-11-20T09:42:54.9480000'),
(276, 1, 14, 1, NULL, NULL, '2026-09-28T13:10:00.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 15, 276, '2026-11-20T09:42:54.9480000'),
(277, 1, 110, 1, NULL, NULL, '2026-09-29T07:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 16, 277, '2026-11-20T09:42:54.9490000'),
(278, 1, 165, 1, NULL, NULL, '2026-09-29T07:10:00.0000000', 0.0000, 1.0000, 185000.0000, 0.00, 185000.00, 16, 278, '2026-11-20T09:42:54.9490000'),
(279, 1, 70, 1, NULL, NULL, '2026-09-29T07:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 16, 279, '2026-11-20T09:42:54.9490000'),
(280, 1, 58, 1, NULL, NULL, '2026-09-30T07:10:00.0000000', 0.0000, 2.0000, 220000.0000, 0.00, 440000.00, 17, 280, '2026-11-20T09:42:54.9490000'),
(281, 1, 114, 1, NULL, NULL, '2026-09-30T07:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 17, 281, '2026-11-20T09:42:54.9490000'),
(282, 1, 3, 1, NULL, NULL, '2026-09-30T07:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 17, 282, '2026-11-20T09:42:54.9490000'),
(283, 1, 143, 1, NULL, NULL, '2026-10-01T05:10:00.0000000', 0.0000, 1.0000, 140000.0000, 0.00, 140000.00, 18, 283, '2026-11-20T09:42:54.9500000'),
(284, 1, 44, 1, NULL, NULL, '2026-10-01T05:10:00.0000000', 0.0000, 1.0000, 110000.0000, 0.00, 110000.00, 18, 284, '2026-11-20T09:42:54.9500000'),
(285, 1, 22, 1, NULL, NULL, '2026-10-01T08:10:00.0000000', 0.0000, 1.0000, 220000.0000, 0.00, 220000.00, 19, 285, '2026-11-20T09:42:54.9500000'),
(286, 1, 73, 1, NULL, NULL, '2026-10-02T11:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 20, 286, '2026-11-20T09:42:54.9510000'),
(287, 1, 9, 1, NULL, NULL, '2026-10-03T11:10:00.0000000', 0.0000, 2.0000, 165000.0000, 0.00, 330000.00, 21, 287, '2026-11-20T09:42:54.9510000'),
(288, 1, 108, 1, NULL, NULL, '2026-10-04T09:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 22, 288, '2026-11-20T09:42:54.9520000'),
(289, 1, 162, 1, NULL, NULL, '2026-10-04T09:10:00.0000000', 0.0000, 1.0000, 45000.0000, 0.00, 45000.00, 22, 289, '2026-11-20T09:42:54.9520000'),
(290, 1, 67, 1, NULL, NULL, '2026-10-04T09:10:00.0000000', 0.0000, 2.0000, 70000.0000, 0.00, 140000.00, 22, 290, '2026-11-20T09:42:54.9520000'),
(291, 1, 148, 1, NULL, NULL, '2026-10-04T12:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 23, 291, '2026-11-20T09:42:54.9520000'),
(292, 1, 50, 1, NULL, NULL, '2026-10-04T12:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 23, 292, '2026-11-20T09:42:54.9520000'),
(293, 1, 109, 1, NULL, NULL, '2026-10-04T12:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 23, 293, '2026-11-20T09:42:54.9520000'),
(294, 1, 139, 1, NULL, NULL, '2026-10-06T03:10:00.0000000', 0.0000, 2.0000, 160000.0000, 0.00, 320000.00, 24, 294, '2026-11-20T09:42:54.9530000'),
(295, 1, 38, 1, NULL, NULL, '2026-10-06T03:10:00.0000000', 0.0000, 1.0000, 45000.0000, 0.00, 45000.00, 24, 295, '2026-11-20T09:42:54.9530000'),
(296, 1, 99, 1, NULL, NULL, '2026-10-06T12:10:00.0000000', 0.0000, 1.0000, 450000.0000, 0.00, 450000.00, 25, 296, '2026-11-20T09:42:54.9530000'),
(297, 1, 113, 1, NULL, NULL, '2026-10-07T04:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 26, 297, '2026-11-20T09:42:54.9540000'),
(298, 1, 17, 1, NULL, NULL, '2026-10-07T10:10:00.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 27, 298, '2026-11-20T09:42:54.9540000'),
(299, 1, 71, 1, NULL, NULL, '2026-10-07T13:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 28, 299, '2026-11-20T09:42:54.9550000'),
(300, 1, 146, 1, NULL, NULL, '2026-10-09T02:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 29, 300, '2026-11-20T09:42:54.9550000'),
(301, 1, 47, 1, NULL, NULL, '2026-10-09T02:10:00.0000000', 0.0000, 2.0000, 310000.0000, 0.00, 620000.00, 29, 301, '2026-11-20T09:42:54.9550000'),
(302, 1, 107, 1, NULL, NULL, '2026-10-09T02:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 29, 302, '2026-11-20T09:42:54.9550000'),
(303, 1, 62, 1, NULL, NULL, '2026-10-09T04:10:00.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 30, 303, '2026-11-20T09:42:54.9560000'),
(304, 1, 117, 1, NULL, NULL, '2026-10-09T04:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 30, 304, '2026-11-20T09:42:54.9560000'),
(305, 1, 106, 1, NULL, NULL, '2026-10-09T07:10:00.0000000', 0.0000, 2.0000, 310000.0000, 0.00, 620000.00, 31, 305, '2026-11-20T09:42:54.9560000'),
(306, 1, 158, 1, NULL, NULL, '2026-10-09T07:10:00.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 31, 306, '2026-11-20T09:42:54.9560000'),
(307, 1, 63, 1, NULL, NULL, '2026-10-09T07:10:00.0000000', 0.0000, 1.0000, 185000.0000, 0.00, 185000.00, 31, 307, '2026-11-20T09:42:54.9560000'),
(308, 1, 26, 1, NULL, NULL, '2026-10-10T05:10:00.0000000', 0.0000, 1.0000, 28000.0000, 0.00, 28000.00, 32, 308, '2026-11-20T09:42:54.9570000'),
(309, 1, 90, 1, NULL, NULL, '2026-10-10T05:10:00.0000000', 0.0000, 1.0000, 150000.0000, 0.00, 150000.00, 32, 309, '2026-11-20T09:42:54.9570000'),
(310, 1, 76, 1, NULL, NULL, '2026-10-10T08:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 33, 310, '2026-11-20T09:42:54.9570000'),
(311, 1, 132, 1, NULL, NULL, '2026-10-10T08:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 33, 311, '2026-11-20T09:42:54.9570000'),
(312, 1, 110, 1, NULL, NULL, '2026-10-12T06:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 34, 312, '2026-11-20T09:42:54.9580000'),
(313, 1, 14, 1, NULL, NULL, '2026-10-12T08:10:00.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 35, 313, '2026-11-20T09:42:54.9600000'),
(314, 1, 69, 1, NULL, NULL, '2026-10-12T11:10:00.0000000', 0.0000, 2.0000, 200000.0000, 0.00, 400000.00, 36, 314, '2026-11-20T09:42:54.9610000'),
(315, 1, 150, 1, NULL, NULL, '2026-10-13T09:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 37, 315, '2026-11-20T09:42:54.9620000'),
(316, 1, 103, 1, NULL, NULL, '2026-10-14T09:10:00.0000000', 0.0000, 1.0000, 120000.0000, 0.00, 120000.00, 38, 316, '2026-11-20T09:42:54.9620000'),
(317, 1, 155, 1, NULL, NULL, '2026-10-14T09:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 38, 317, '2026-11-20T09:42:54.9620000'),
(318, 1, 143, 1, NULL, NULL, '2026-10-14T12:10:00.0000000', 0.0000, 1.0000, 140000.0000, 0.00, 140000.00, 39, 318, '2026-11-20T09:42:54.9630000'),
(319, 1, 44, 1, NULL, NULL, '2026-10-14T12:10:00.0000000', 0.0000, 1.0000, 110000.0000, 0.00, 110000.00, 39, 319, '2026-11-20T09:42:54.9630000'),
(320, 1, 104, 1, NULL, NULL, '2026-10-14T12:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 39, 320, '2026-11-20T09:42:54.9630000'),
(321, 1, 22, 1, NULL, NULL, '2026-10-15T03:10:00.0000000', 0.0000, 2.0000, 220000.0000, 0.00, 440000.00, 40, 321, '2026-11-20T09:42:54.9640000'),
(322, 1, 86, 1, NULL, NULL, '2026-10-15T03:10:00.0000000', 0.0000, 1.0000, 160000.0000, 0.00, 160000.00, 40, 322, '2026-11-20T09:42:54.9640000'),
(323, 1, 73, 1, NULL, NULL, '2026-10-15T10:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 41, 323, '2026-11-20T09:42:54.9640000'),
(324, 1, 130, 1, NULL, NULL, '2026-10-15T10:10:00.0000000', 0.0000, 2.0000, 65000.0000, 0.00, 130000.00, 41, 324, '2026-11-20T09:42:54.9640000'),
(325, 1, 115, 1, NULL, NULL, '2026-10-15T13:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 42, 325, '2026-11-20T09:42:54.9650000'),
(326, 1, 4, 1, NULL, NULL, '2026-10-15T13:10:00.0000000', 0.0000, 1.0000, 150000.0000, 0.00, 150000.00, 42, 326, '2026-11-20T09:42:54.9650000'),
(327, 1, 32, 1, NULL, NULL, '2026-10-17T02:10:00.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 43, 327, '2026-11-20T09:42:54.9650000'),
(328, 1, 108, 1, NULL, NULL, '2026-10-17T04:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 44, 328, '2026-11-20T09:42:54.9660000'),
(329, 1, 148, 1, NULL, NULL, '2026-10-17T11:10:00.0000000', 0.0000, 2.0000, 200000.0000, 0.00, 400000.00, 45, 329, '2026-11-20T09:42:54.9660000'),
(330, 1, 65, 1, NULL, NULL, '2026-10-17T13:10:00.0000000', 0.0000, 1.0000, 185000.0000, 0.00, 185000.00, 46, 330, '2026-11-20T09:42:54.9670000'),
(331, 1, 78, 1, NULL, NULL, '2026-10-18T05:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 47, 331, '2026-11-20T09:42:54.9670000'),
(332, 1, 135, 1, NULL, NULL, '2026-10-18T05:10:00.0000000', 0.0000, 1.0000, 70000.0000, 0.00, 70000.00, 47, 332, '2026-11-20T09:42:54.9670000'),
(333, 1, 34, 1, NULL, NULL, '2026-10-18T05:10:00.0000000', 0.0000, 2.0000, 95000.0000, 0.00, 190000.00, 47, 333, '2026-11-20T09:42:54.9670000'),
(334, 1, 17, 1, NULL, NULL, '2026-10-19T05:10:00.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 48, 334, '2026-11-20T09:42:54.9680000'),
(335, 1, 83, 1, NULL, NULL, '2026-10-19T05:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 48, 335, '2026-11-20T09:42:54.9680000'),
(336, 1, 141, 1, NULL, NULL, '2026-10-19T05:10:00.0000000', 0.0000, 1.0000, 140000.0000, 0.00, 140000.00, 48, 336, '2026-11-20T09:42:54.9680000'),
(337, 1, 71, 1, NULL, NULL, '2026-10-19T08:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 49, 337, '2026-11-20T09:42:54.9680000'),
(338, 1, 126, 1, NULL, NULL, '2026-10-19T08:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 49, 338, '2026-11-20T09:42:54.9680000'),
(339, 1, 153, 1, NULL, NULL, '2026-10-20T06:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 50, 339, '2026-11-20T09:42:54.9690000'),
(340, 1, 106, 1, NULL, NULL, '2026-10-21T06:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 51, 340, '2026-11-20T09:42:54.9690000'),
(341, 1, 146, 1, NULL, NULL, '2026-10-22T09:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 52, 341, '2026-11-20T09:42:54.9700000'),
(342, 1, 117, 1, NULL, NULL, '2026-10-22T10:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 53, 342, '2026-11-20T09:42:54.9710000'),
(343, 1, 8, 1, NULL, NULL, '2026-10-22T10:10:00.0000000', 0.0000, 2.0000, 165000.0000, 0.00, 330000.00, 53, 343, '2026-11-20T09:42:54.9710000'),
(344, 1, 77, 1, NULL, NULL, '2026-10-22T10:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 53, 344, '2026-11-20T09:42:54.9710000'),
(345, 1, 26, 1, NULL, NULL, '2026-10-22T12:10:00.0000000', 0.0000, 1.0000, 28000.0000, 0.00, 28000.00, 54, 345, '2026-11-20T09:42:54.9710000'),
(346, 1, 150, 1, NULL, NULL, '2026-10-24T04:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 55, 346, '2026-11-20T09:42:54.9710000'),
(347, 1, 69, 1, NULL, NULL, '2026-10-24T10:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 56, 347, '2026-11-20T09:42:54.9720000'),
(348, 1, 36, 1, NULL, NULL, '2026-10-24T11:10:00.0000000', 0.0000, 2.0000, 95000.0000, 0.00, 190000.00, 57, 348, '2026-11-20T09:42:54.9720000'),
(349, 1, 110, 1, NULL, NULL, '2026-10-24T13:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 58, 349, '2026-11-20T09:42:54.9730000'),
(350, 1, 165, 1, NULL, NULL, '2026-10-24T13:10:00.0000000', 0.0000, 1.0000, 185000.0000, 0.00, 185000.00, 58, 350, '2026-11-20T09:42:54.9730000'),
(351, 1, 82, 1, NULL, NULL, '2026-10-25T02:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 59, 351, '2026-11-20T09:42:54.9730000'),
(352, 1, 22, 1, NULL, NULL, '2026-10-26T02:10:00.0000000', 0.0000, 1.0000, 220000.0000, 0.00, 220000.00, 60, 352, '2026-11-20T09:42:54.9740000'),
(353, 1, 86, 1, NULL, NULL, '2026-10-26T02:10:00.0000000', 0.0000, 1.0000, 160000.0000, 0.00, 160000.00, 60, 353, '2026-11-20T09:42:54.9740000'),
(354, 1, 156, 1, NULL, NULL, '2026-10-26T03:10:00.0000000', 0.0000, 2.0000, 105000.0000, 0.00, 210000.00, 61, 354, '2026-11-20T09:42:54.9740000'),
(355, 1, 61, 1, NULL, NULL, '2026-10-26T03:10:00.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 61, 355, '2026-11-20T09:42:54.9740000'),
(356, 1, 73, 1, NULL, NULL, '2026-10-26T05:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 62, 356, '2026-11-20T09:42:54.9750000'),
(357, 1, 130, 1, NULL, NULL, '2026-10-26T05:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 62, 357, '2026-11-20T09:42:54.9750000'),
(358, 1, 25, 1, NULL, NULL, '2026-10-26T05:10:00.0000000', 0.0000, 1.0000, 45000.0000, 0.00, 45000.00, 62, 358, '2026-11-20T09:42:54.9750000'),
(359, 1, 115, 1, NULL, NULL, '2026-10-26T12:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 63, 359, '2026-11-20T09:42:54.9750000'),
(360, 1, 4, 1, NULL, NULL, '2026-10-26T12:10:00.0000000', 0.0000, 1.0000, 150000.0000, 0.00, 150000.00, 63, 360, '2026-11-20T09:42:54.9750000'),
(361, 1, 74, 1, NULL, NULL, '2026-10-26T12:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 63, 361, '2026-11-20T09:42:54.9750000'),
(362, 1, 78, 1, NULL, NULL, '2026-10-28T04:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 64, 362, '2026-11-20T09:42:54.9760000'),
(363, 1, 148, 1, NULL, NULL, '2026-10-28T06:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 65, 363, '2026-11-20T09:42:54.9770000'),
(364, 1, 32, 1, NULL, NULL, '2026-10-28T09:10:00.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 66, 364, '2026-11-20T09:42:54.9770000'),
(365, 1, 120, 1, NULL, NULL, '2026-10-29T07:10:00.0000000', 0.0000, 2.0000, 140000.0000, 0.00, 280000.00, 67, 365, '2026-11-20T09:42:54.9780000'),
(366, 1, 39, 1, NULL, NULL, '2026-10-30T08:10:00.0000000', 0.0000, 1.0000, 190000.0000, 0.00, 190000.00, 68, 366, '2026-11-20T09:42:54.9780000'),
(367, 1, 102, 1, NULL, NULL, '2026-10-30T08:10:00.0000000', 0.0000, 1.0000, 28000.0000, 0.00, 28000.00, 68, 367, '2026-11-20T09:42:54.9780000'),
(368, 1, 113, 1, NULL, NULL, '2026-10-30T10:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 69, 368, '2026-11-20T09:42:54.9790000'),
(369, 1, 2, 1, NULL, NULL, '2026-10-30T10:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 69, 369, '2026-11-20T09:42:54.9790000'),
(370, 1, 72, 1, NULL, NULL, '2026-10-30T10:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 69, 370, '2026-11-20T09:42:54.9790000'),
(371, 1, 153, 1, NULL, NULL, '2026-10-30T13:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 70, 371, '2026-11-20T09:42:54.9790000'),
(372, 1, 56, 1, NULL, NULL, '2026-10-30T13:10:00.0000000', 0.0000, 1.0000, 220000.0000, 0.00, 220000.00, 70, 372, '2026-11-20T09:42:54.9790000'),
(373, 1, 84, 1, NULL, NULL, '2026-10-31T11:10:00.0000000', 0.0000, 2.0000, 80000.0000, 0.00, 160000.00, 71, 373, '2026-11-20T09:42:54.9800000'),
(374, 1, 142, 1, NULL, NULL, '2026-10-31T11:10:00.0000000', 0.0000, 1.0000, 140000.0000, 0.00, 140000.00, 71, 374, '2026-11-20T09:42:54.9800000'),
(375, 1, 76, 1, NULL, NULL, '2026-11-01T02:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 72, 375, '2026-11-20T09:42:54.9800000'),
(376, 1, 117, 1, NULL, NULL, '2026-11-01T05:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 73, 376, '2026-11-20T09:42:54.9810000'),
(377, 1, 26, 1, NULL, NULL, '2026-11-01T11:10:00.0000000', 0.0000, 1.0000, 28000.0000, 0.00, 28000.00, 74, 377, '2026-11-20T09:42:54.9810000'),
(378, 1, 159, 1, NULL, NULL, '2026-11-01T12:10:00.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 75, 378, '2026-11-20T09:42:54.9820000'),
(379, 1, 110, 1, NULL, NULL, '2026-11-02T12:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 76, 379, '2026-11-20T09:42:54.9820000'),
(380, 1, 165, 1, NULL, NULL, '2026-11-02T12:10:00.0000000', 0.0000, 2.0000, 185000.0000, 0.00, 370000.00, 76, 380, '2026-11-20T09:42:54.9820000'),
(381, 1, 70, 1, NULL, NULL, '2026-11-02T12:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 76, 381, '2026-11-20T09:42:54.9820000'),
(382, 1, 150, 1, NULL, NULL, '2026-11-03T03:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 77, 382, '2026-11-20T09:42:54.9830000'),
(383, 1, 52, 1, NULL, NULL, '2026-11-03T03:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 77, 383, '2026-11-20T09:42:54.9830000'),
(384, 1, 124, 1, NULL, NULL, '2026-11-03T04:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 78, 384, '2026-11-20T09:42:54.9830000'),
(385, 1, 36, 1, NULL, NULL, '2026-11-03T06:10:00.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 79, 385, '2026-11-20T09:42:54.9840000'),
(386, 1, 97, 1, NULL, NULL, '2026-11-03T06:10:00.0000000', 0.0000, 1.0000, 450000.0000, 0.00, 450000.00, 79, 386, '2026-11-20T09:42:54.9840000'),
(387, 1, 82, 1, NULL, NULL, '2026-11-03T13:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 80, 387, '2026-11-20T09:42:54.9840000'),
(388, 1, 138, 1, NULL, NULL, '2026-11-03T13:10:00.0000000', 0.0000, 1.0000, 160000.0000, 0.00, 160000.00, 80, 388, '2026-11-20T09:42:54.9840000'),
(389, 1, 73, 1, NULL, NULL, '2026-11-04T04:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 81, 389, '2026-11-20T09:42:54.9850000'),
(390, 1, 115, 1, NULL, NULL, '2026-11-04T07:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 82, 390, '2026-11-20T09:42:54.9850000'),
(391, 1, 46, 1, NULL, NULL, '2026-11-05T05:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 83, 391, '2026-11-20T09:42:54.9850000'),
(392, 1, 105, 1, NULL, NULL, '2026-11-05T05:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 83, 392, '2026-11-20T09:42:54.9850000'),
(393, 1, 157, 1, NULL, NULL, '2026-11-05T05:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 83, 393, '2026-11-20T09:42:54.9850000'),
(394, 1, 156, 1, NULL, NULL, '2026-11-05T10:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 84, 394, '2026-11-20T09:42:54.9860000'),
(395, 1, 120, 1, NULL, NULL, '2026-11-06T02:10:00.0000000', 0.0000, 1.0000, 140000.0000, 0.00, 140000.00, 85, 395, '2026-11-20T09:42:54.9860000'),
(396, 1, 32, 1, NULL, NULL, '2026-11-06T08:10:00.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 86, 396, '2026-11-20T09:42:54.9870000'),
(397, 1, 163, 1, NULL, NULL, '2026-11-06T09:10:00.0000000', 0.0000, 1.0000, 185000.0000, 0.00, 185000.00, 87, 397, '2026-11-20T09:42:54.9870000'),
(398, 1, 78, 1, NULL, NULL, '2026-11-06T11:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 88, 398, '2026-11-20T09:42:54.9880000'),
(399, 1, 135, 1, NULL, NULL, '2026-11-06T11:10:00.0000000', 0.0000, 1.0000, 70000.0000, 0.00, 70000.00, 88, 399, '2026-11-20T09:42:54.9880000'),
(400, 1, 113, 1, NULL, NULL, '2026-11-07T05:10:00.0000000', 0.0000, 2.0000, 80000.0000, 0.00, 160000.00, 89, 400, '2026-11-20T09:42:54.9880000'),
(401, 1, 2, 1, NULL, NULL, '2026-11-07T05:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 89, 401, '2026-11-20T09:42:54.9880000'),
(402, 1, 153, 1, NULL, NULL, '2026-11-07T12:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 90, 402, '2026-11-20T09:42:54.9890000'),
(403, 1, 39, 1, NULL, NULL, '2026-11-08T03:10:00.0000000', 0.0000, 1.0000, 190000.0000, 0.00, 190000.00, 91, 403, '2026-11-20T09:42:54.9890000'),
(404, 1, 102, 1, NULL, NULL, '2026-11-08T03:10:00.0000000', 0.0000, 1.0000, 28000.0000, 0.00, 28000.00, 91, 404, '2026-11-20T09:42:54.9890000'),
(405, 1, 154, 1, NULL, NULL, '2026-11-08T03:10:00.0000000', 0.0000, 2.0000, 105000.0000, 0.00, 210000.00, 91, 405, '2026-11-20T09:42:54.9890000'),
(406, 1, 84, 1, NULL, NULL, '2026-11-08T06:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 92, 406, '2026-11-20T09:42:54.9900000'),
(407, 1, 142, 1, NULL, NULL, '2026-11-08T06:10:00.0000000', 0.0000, 1.0000, 140000.0000, 0.00, 140000.00, 92, 407, '2026-11-20T09:42:54.9900000'),
(408, 1, 42, 1, NULL, NULL, '2026-11-08T06:10:00.0000000', 0.0000, 1.0000, 260000.0000, 0.00, 260000.00, 92, 408, '2026-11-20T09:42:54.9900000'),
(409, 1, 127, 1, NULL, NULL, '2026-11-08T13:10:00.0000000', 0.0000, 1.0000, 150000.0000, 0.00, 150000.00, 93, 409, '2026-11-20T09:42:54.9900000'),
(410, 1, 20, 1, NULL, NULL, '2026-11-08T13:10:00.0000000', 0.0000, 1.0000, 220000.0000, 0.00, 220000.00, 93, 410, '2026-11-20T09:42:54.9900000'),
(411, 1, 48, 1, NULL, NULL, '2026-11-09T02:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 94, 411, '2026-11-20T09:42:54.9910000'),
(412, 1, 117, 1, NULL, NULL, '2026-11-09T04:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 95, 412, '2026-11-20T09:42:54.9910000'),
(413, 1, 91, 1, NULL, NULL, '2026-11-09T05:10:00.0000000', 0.0000, 1.0000, 120000.0000, 0.00, 120000.00, 96, 413, '2026-11-20T09:42:54.9920000'),
(414, 1, 159, 1, NULL, NULL, '2026-11-09T07:10:00.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 97, 414, '2026-11-20T09:42:54.9920000'),
(415, 1, 76, 1, NULL, NULL, '2026-11-09T13:10:00.0000000', 0.0000, 2.0000, 65000.0000, 0.00, 130000.00, 98, 415, '2026-11-20T09:42:54.9930000'),
(416, 1, 36, 1, NULL, NULL, '2026-11-10T05:10:00.0000000', 0.0000, 2.0000, 95000.0000, 0.00, 190000.00, 99, 416, '2026-11-20T09:42:54.9930000'),
(417, 1, 97, 1, NULL, NULL, '2026-11-10T05:10:00.0000000', 0.0000, 1.0000, 450000.0000, 0.00, 450000.00, 99, 417, '2026-11-20T09:42:54.9930000'),
(418, 1, 115, 1, NULL, NULL, '2026-11-11T02:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 100, 418, '2026-11-20T09:42:54.9940000'),
(419, 1, 167, 1, NULL, NULL, '2026-11-11T06:10:00.0000000', 0.0000, 1.0000, 260000.0000, 0.00, 260000.00, 101, 419, '2026-11-20T09:42:54.9950000'),
(420, 1, 70, 1, NULL, NULL, '2026-11-11T06:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 101, 420, '2026-11-20T09:42:54.9950000'),
(421, 1, 124, 1, NULL, NULL, '2026-11-11T11:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 102, 421, '2026-11-20T09:42:54.9950000'),
(422, 1, 16, 1, NULL, NULL, '2026-11-11T11:10:00.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 102, 422, '2026-11-20T09:42:54.9950000'),
(423, 1, 87, 1, NULL, NULL, '2026-11-12T03:10:00.0000000', 0.0000, 1.0000, 160000.0000, 0.00, 160000.00, 103, 423, '2026-11-20T09:42:54.9960000'),
(424, 1, 156, 1, NULL, NULL, '2026-11-12T09:10:00.0000000', 0.0000, 2.0000, 105000.0000, 0.00, 210000.00, 104, 424, '2026-11-20T09:42:54.9960000'),
(425, 1, 130, 1, NULL, NULL, '2026-11-12T10:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 105, 425, '2026-11-20T09:42:54.9970000'),
(426, 1, 46, 1, NULL, NULL, '2026-11-12T12:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 106, 426, '2026-11-20T09:42:54.9980000'),
(427, 1, 94, 1, NULL, NULL, '2026-11-13T02:10:00.0000000', 0.0000, 1.0000, 160000.0000, 0.00, 160000.00, 107, 427, '2026-11-20T09:42:54.9980000'),
(428, 1, 163, 1, NULL, NULL, '2026-11-13T04:10:00.0000000', 0.0000, 1.0000, 185000.0000, 0.00, 185000.00, 108, 428, '2026-11-20T09:42:54.9990000'),
(429, 1, 68, 1, NULL, NULL, '2026-11-13T04:10:00.0000000', 0.0000, 2.0000, 70000.0000, 0.00, 140000.00, 108, 429, '2026-11-20T09:42:54.9990000'),
(430, 1, 78, 1, NULL, NULL, '2026-11-13T06:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 109, 430, '2026-11-20T09:42:55.0000000'),
(431, 1, 135, 1, NULL, NULL, '2026-11-13T06:10:00.0000000', 0.0000, 1.0000, 70000.0000, 0.00, 70000.00, 109, 431, '2026-11-20T09:42:55.0000000'),
(432, 1, 34, 1, NULL, NULL, '2026-11-13T06:10:00.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 109, 432, '2026-11-20T09:42:55.0000000'),
(433, 1, 50, 1, NULL, NULL, '2026-11-13T07:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 110, 433, '2026-11-20T09:42:55.0000000'),
(434, 1, 110, 1, NULL, NULL, '2026-11-13T07:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 110, 434, '2026-11-20T09:42:55.0000000'),
(435, 1, 120, 1, NULL, NULL, '2026-11-13T13:10:00.0000000', 0.0000, 2.0000, 140000.0000, 0.00, 280000.00, 111, 435, '2026-11-20T09:42:55.0010000'),
(436, 1, 12, 1, NULL, NULL, '2026-11-13T13:10:00.0000000', 0.0000, 1.0000, 110000.0000, 0.00, 110000.00, 111, 436, '2026-11-20T09:42:55.0010000'),
(437, 1, 39, 1, NULL, NULL, '2026-11-14T02:10:00.0000000', 0.0000, 1.0000, 190000.0000, 0.00, 190000.00, 112, 437, '2026-11-20T09:42:55.0010000'),
(438, 1, 2, 1, NULL, NULL, '2026-11-14T03:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 113, 438, '2026-11-20T09:42:55.0020000'),
(439, 1, 73, 1, NULL, NULL, '2026-11-14T03:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 113, 439, '2026-11-20T09:42:55.0020000'),
(440, 1, 129, 1, NULL, NULL, '2026-11-14T03:10:00.0000000', 0.0000, 2.0000, 150000.0000, 0.00, 300000.00, 113, 440, '2026-11-20T09:42:55.0020000'),
(441, 1, 84, 1, NULL, NULL, '2026-11-14T05:10:00.0000000', 0.0000, 2.0000, 80000.0000, 0.00, 160000.00, 114, 441, '2026-11-20T09:42:55.0020000'),
(442, 1, 127, 1, NULL, NULL, '2026-11-14T08:10:00.0000000', 0.0000, 1.0000, 150000.0000, 0.00, 150000.00, 115, 442, '2026-11-20T09:42:55.0030000'),
(443, 1, 159, 1, NULL, NULL, '2026-11-15T06:10:00.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 116, 443, '2026-11-20T09:42:55.0030000'),
(444, 1, 64, 1, NULL, NULL, '2026-11-15T06:10:00.0000000', 0.0000, 1.0000, 185000.0000, 0.00, 185000.00, 116, 444, '2026-11-20T09:42:55.0030000'),
(445, 1, 133, 1, NULL, NULL, '2026-11-15T07:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 117, 445, '2026-11-20T09:42:55.0040000'),
(446, 1, 48, 1, NULL, NULL, '2026-11-15T09:10:00.0000000', 0.0000, 2.0000, 310000.0000, 0.00, 620000.00, 118, 446, '2026-11-20T09:42:55.0050000'),
(447, 1, 107, 1, NULL, NULL, '2026-11-15T09:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 118, 447, '2026-11-20T09:42:55.0050000'),
(448, 1, 117, 1, NULL, NULL, '2026-11-15T11:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 119, 448, '2026-11-20T09:42:55.0050000'),
(449, 1, 8, 1, NULL, NULL, '2026-11-15T11:10:00.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 119, 449, '2026-11-20T09:42:55.0050000'),
(450, 1, 77, 1, NULL, NULL, '2026-11-15T11:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 119, 450, '2026-11-20T09:42:55.0050000'),
(451, 1, 91, 1, NULL, NULL, '2026-11-15T12:10:00.0000000', 0.0000, 1.0000, 120000.0000, 0.00, 120000.00, 120, 451, '2026-11-20T09:42:55.0060000'),
(452, 1, 82, 1, NULL, NULL, '2026-11-16T03:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 121, 452, '2026-11-20T09:42:55.0060000'),
(453, 1, 138, 1, NULL, NULL, '2026-11-16T03:10:00.0000000', 0.0000, 1.0000, 160000.0000, 0.00, 160000.00, 121, 453, '2026-11-20T09:42:55.0060000'),
(454, 1, 53, 1, NULL, NULL, '2026-11-16T04:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 122, 454, '2026-11-20T09:42:55.0070000'),
(455, 1, 112, 1, NULL, NULL, '2026-11-16T04:10:00.0000000', 0.0000, 2.0000, 80000.0000, 0.00, 160000.00, 122, 455, '2026-11-20T09:42:55.0070000'),
(456, 1, 1, 1, NULL, NULL, '2026-11-16T04:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 122, 456, '2026-11-20T09:42:55.0070000'),
(457, 1, 124, 1, NULL, NULL, '2026-11-16T10:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 123, 457, '2026-11-20T09:42:55.0080000'),
(458, 1, 99, 1, NULL, NULL, '2026-11-16T11:10:00.0000000', 0.0000, 1.0000, 450000.0000, 0.00, 450000.00, 124, 458, '2026-11-20T09:42:55.0080000'),
(459, 1, 152, 1, NULL, NULL, '2026-11-16T11:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 124, 459, '2026-11-20T09:42:55.0080000'),
(460, 1, 167, 1, NULL, NULL, '2026-11-16T13:10:00.0000000', 0.0000, 2.0000, 260000.0000, 0.00, 520000.00, 125, 460, '2026-11-20T09:42:55.0090000'),
(461, 1, 70, 1, NULL, NULL, '2026-11-16T13:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 125, 461, '2026-11-20T09:42:55.0090000'),
(462, 1, 125, 1, NULL, NULL, '2026-11-16T13:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 125, 462, '2026-11-20T09:42:55.0090000'),
(463, 1, 87, 1, NULL, NULL, '2026-11-17T02:10:00.0000000', 0.0000, 1.0000, 160000.0000, 0.00, 160000.00, 126, 463, '2026-11-20T09:42:55.0090000'),
(464, 1, 163, 1, NULL, NULL, '2026-11-17T03:10:00.0000000', 0.0000, 1.0000, 185000.0000, 0.00, 185000.00, 127, 464, '2026-11-20T09:42:55.0100000'),
(465, 1, 68, 1, NULL, NULL, '2026-11-17T03:10:00.0000000', 0.0000, 1.0000, 70000.0000, 0.00, 70000.00, 127, 465, '2026-11-20T09:42:55.0100000'),
(466, 1, 122, 1, NULL, NULL, '2026-11-17T03:10:00.0000000', 0.0000, 1.0000, 140000.0000, 0.00, 140000.00, 127, 466, '2026-11-20T09:42:55.0100000'),
(467, 1, 130, 1, NULL, NULL, '2026-11-17T05:10:00.0000000', 0.0000, 2.0000, 65000.0000, 0.00, 130000.00, 128, 467, '2026-11-20T09:42:55.0100000'),
(468, 1, 46, 1, NULL, NULL, '2026-11-17T07:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 129, 468, '2026-11-20T09:42:55.0110000'),
(469, 1, 5, 1, NULL, NULL, '2026-11-17T08:10:00.0000000', 0.0000, 1.0000, 150000.0000, 0.00, 150000.00, 130, 469, '2026-11-20T09:42:55.0110000'),
(470, 1, 120, 1, NULL, NULL, '2026-11-17T08:10:00.0000000', 0.0000, 1.0000, 140000.0000, 0.00, 140000.00, 131, 470, '2026-11-20T09:42:55.0120000'),
(471, 1, 12, 1, NULL, NULL, '2026-11-17T08:10:00.0000000', 0.0000, 1.0000, 110000.0000, 0.00, 110000.00, 131, 471, '2026-11-20T09:42:55.0120000'),
(472, 1, 136, 1, NULL, NULL, '2026-11-18T04:10:00.0000000', 0.0000, 1.0000, 70000.0000, 0.00, 70000.00, 132, 472, '2026-11-20T09:42:55.0130000'),
(473, 1, 35, 1, NULL, NULL, '2026-11-18T04:10:00.0000000', 0.0000, 2.0000, 95000.0000, 0.00, 190000.00, 132, 473, '2026-11-20T09:42:55.0130000'),
(474, 1, 50, 1, NULL, NULL, '2026-11-18T06:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 133, 474, '2026-11-20T09:42:55.0130000'),
(475, 1, 110, 1, NULL, NULL, '2026-11-18T06:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 133, 475, '2026-11-20T09:42:55.0130000'),
(476, 1, 164, 1, NULL, NULL, '2026-11-18T06:10:00.0000000', 0.0000, 1.0000, 185000.0000, 0.00, 185000.00, 133, 476, '2026-11-20T09:42:55.0130000'),
(477, 1, 127, 1, NULL, NULL, '2026-11-18T07:10:00.0000000', 0.0000, 1.0000, 150000.0000, 0.00, 150000.00, 134, 477, '2026-11-20T09:42:55.0140000'),
(478, 1, 2, 1, NULL, NULL, '2026-11-18T10:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 135, 478, '2026-11-20T09:42:55.0150000'),
(479, 1, 84, 1, NULL, NULL, '2026-11-18T12:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 136, 479, '2026-11-20T09:42:55.0150000'),
(480, 1, 133, 1, NULL, NULL, '2026-11-19T02:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 137, 480, '2026-11-20T09:42:55.0160000'),
(481, 1, 31, 1, NULL, NULL, '2026-11-19T02:10:00.0000000', 0.0000, 1.0000, 450000.0000, 0.00, 450000.00, 137, 481, '2026-11-20T09:42:55.0160000'),
(482, 1, 48, 1, NULL, NULL, '2026-11-19T04:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 138, 482, '2026-11-20T09:42:55.0170000'),
(483, 1, 107, 1, NULL, NULL, '2026-11-19T04:10:00.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 138, 483, '2026-11-20T09:42:55.0170000'),
(484, 1, 161, 1, NULL, NULL, '2026-11-19T04:10:00.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 138, 484, '2026-11-20T09:42:55.0170000'),
(485, 1, 9, 1, NULL, NULL, '2026-11-19T05:10:00.0000000', 0.0000, 2.0000, 165000.0000, 0.00, 330000.00, 139, 485, '2026-11-20T09:42:55.0170000'),
(486, 1, 77, 1, NULL, NULL, '2026-11-19T05:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 139, 486, '2026-11-20T09:42:55.0170000'),
(487, 1, 167, 1, NULL, NULL, '2026-11-19T08:10:00.0000000', 0.0000, 1.0000, 260000.0000, 0.00, 260000.00, 140, 487, '2026-11-20T09:42:55.0180000'),
(488, 1, 139, 1, NULL, NULL, '2026-11-19T09:10:00.0000000', 0.0000, 2.0000, 160000.0000, 0.00, 320000.00, 141, 488, '2026-11-20T09:42:55.0190000'),
(489, 1, 38, 1, NULL, NULL, '2026-11-19T09:10:00.0000000', 0.0000, 1.0000, 45000.0000, 0.00, 45000.00, 141, 489, '2026-11-20T09:42:55.0190000'),
(490, 1, 102, 1, NULL, NULL, '2026-11-19T09:10:00.0000000', 0.0000, 1.0000, 28000.0000, 0.00, 28000.00, 141, 490, '2026-11-20T09:42:55.0190000'),
(491, 1, 14, 1, NULL, NULL, '2026-11-20T02:10:00.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 142, 491, '2026-11-20T09:42:55.0200000'),
(492, 1, 81, 1, NULL, NULL, '2026-11-20T02:10:00.0000000', 0.0000, 1.0000, 105000.0000, 0.00, 105000.00, 142, 492, '2026-11-20T09:42:55.0200000'),
(493, 1, 137, 1, NULL, NULL, '2026-11-20T02:10:00.0000000', 0.0000, 1.0000, 160000.0000, 0.00, 160000.00, 142, 493, '2026-11-20T09:42:55.0200000'),
(494, 1, 103, 1, NULL, NULL, '2026-11-20T03:10:00.0000000', 0.0000, 1.0000, 120000.0000, 0.00, 120000.00, 143, 494, '2026-11-20T09:42:55.0200000'),
(495, 1, 9, 1, NULL, NULL, '2026-11-20T04:10:00.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 144, 495, '2026-11-20T09:42:55.0210000'),
(496, 1, 77, 1, NULL, NULL, '2026-11-20T04:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 144, 496, '2026-11-20T09:42:55.0210000'),
(497, 1, 134, 1, NULL, NULL, '2026-11-20T04:10:00.0000000', 0.0000, 1.0000, 70000.0000, 0.00, 70000.00, 144, 497, '2026-11-20T09:42:55.0210000'),
(498, 1, 130, 1, NULL, NULL, '2026-11-20T04:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 145, 498, '2026-11-20T09:42:55.0210000'),
(499, 1, 26, 1, NULL, NULL, '2026-11-20T04:10:00.0000000', 0.0000, 1.0000, 28000.0000, 0.00, 28000.00, 145, 499, '2026-11-20T09:42:55.0210000'),
(500, 1, 106, 1, NULL, NULL, '2026-11-20T05:10:00.0000000', 0.0000, 2.0000, 310000.0000, 0.00, 620000.00, 146, 500, '2026-11-20T09:42:55.0210000')
;
INSERT INTO [inv].[StockLedger] ([Id], [CompanyId], [ProductId], [WarehouseId], [LocationId], [LotId], [MoveDate], [QtyIn], [QtyOut], [UnitCost], [ValueIn], [ValueOut], [StockDocumentId], [StockDocumentLineId], [CreatedAt]) VALUES
(501, 1, 99, 1, NULL, NULL, '2026-11-20T05:10:00.0000000', 0.0000, 1.0000, 450000.0000, 0.00, 450000.00, 147, 501, '2026-11-20T09:42:55.0220000'),
(502, 1, 2, 1, NULL, NULL, '2026-11-20T05:10:00.0000000', 0.0000, 1.0000, 80000.0000, 0.00, 80000.00, 148, 502, '2026-11-20T09:42:55.0220000'),
(503, 1, 73, 1, NULL, NULL, '2026-11-20T05:10:00.0000000', 0.0000, 1.0000, 200000.0000, 0.00, 200000.00, 148, 503, '2026-11-20T09:42:55.0220000'),
(504, 1, 143, 1, NULL, NULL, '2026-11-20T06:10:00.0000000', 0.0000, 1.0000, 140000.0000, 0.00, 140000.00, 149, 504, '2026-11-20T09:42:55.0230000'),
(505, 1, 5, 1, NULL, NULL, '2026-11-20T07:10:00.0000000', 0.0000, 1.0000, 150000.0000, 0.00, 150000.00, 150, 505, '2026-11-20T09:42:55.0240000'),
(506, 1, 75, 1, NULL, NULL, '2026-11-20T07:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 150, 506, '2026-11-20T09:42:55.0240000'),
(507, 1, 139, 1, NULL, NULL, '2026-11-20T08:10:00.0000000', 0.0000, 1.0000, 160000.0000, 0.00, 160000.00, 151, 507, '2026-11-20T09:42:55.0240000'),
(508, 1, 133, 1, NULL, NULL, '2026-11-20T09:10:00.0000000', 0.0000, 1.0000, 65000.0000, 0.00, 65000.00, 152, 508, '2026-11-20T09:42:55.0250000'),
(509, 1, 31, 1, NULL, NULL, '2026-11-20T09:10:00.0000000', 0.0000, 1.0000, 450000.0000, 0.00, 450000.00, 152, 509, '2026-11-20T09:42:55.0250000'),
(510, 1, 92, 1, NULL, NULL, '2026-11-20T09:10:00.0000000', 0.0000, 2.0000, 160000.0000, 0.00, 320000.00, 152, 510, '2026-11-20T09:42:55.0250000'),
(511, 1, 108, 1, NULL, NULL, '2026-11-20T08:47:33.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 153, 511, '2026-11-20T09:42:55.0260000'),
(512, 1, 162, 1, NULL, NULL, '2026-11-20T08:47:33.0000000', 0.0000, 1.0000, 45000.0000, 0.00, 45000.00, 153, 512, '2026-11-20T09:42:55.0260000'),
(513, 1, 62, 1, NULL, NULL, '2026-11-20T08:10:33.0000000', 0.0000, 1.0000, 165000.0000, 0.00, 165000.00, 154, 513, '2026-11-20T09:42:55.0260000'),
(514, 1, 53, 1, NULL, NULL, '2026-11-20T07:33:33.0000000', 0.0000, 1.0000, 310000.0000, 0.00, 310000.00, 155, 514, '2026-11-20T09:42:55.0270000'),
(515, 1, 136, 1, NULL, NULL, '2026-11-20T06:19:33.0000000', 0.0000, 1.0000, 70000.0000, 0.00, 70000.00, 156, 515, '2026-11-20T09:42:55.0280000'),
(516, 1, 35, 1, NULL, NULL, '2026-11-20T06:19:33.0000000', 0.0000, 1.0000, 95000.0000, 0.00, 95000.00, 156, 516, '2026-11-20T09:42:55.0280000'),
(517, 1, 96, 1, NULL, NULL, '2026-11-20T06:19:33.0000000', 0.0000, 1.0000, 190000.0000, 0.00, 190000.00, 156, 517, '2026-11-20T09:42:55.0280000'),
(518, 1, 58, 1, NULL, NULL, '2026-11-20T09:42:33.0000000', 0.0000, 1.0000, 220000.0000, 0.00, 220000.00, 157, 518, '2026-11-20T09:42:55.0280000'),
(519, 1, 5, 1, NULL, NULL, '2026-11-18T08:00:00.0000000', 1.0000, 0.0000, 150000.0000, 150000.00, 0.00, 158, 519, '2026-11-20T15:17:41.3410000'),
(520, 1, 91, 1, NULL, NULL, '2026-11-16T12:00:00.0000000', 1.0000, 0.0000, 120000.0000, 120000.00, 0.00, 159, 520, '2026-11-20T15:17:41.3550000')
;
SET IDENTITY_INSERT [inv].[StockLedger] OFF;
GO

-- inv.Warehouses (1 dòng)
SET IDENTITY_INSERT [inv].[Warehouses] ON;
INSERT INTO [inv].[Warehouses] ([Id], [CompanyId], [BranchId], [Code], [Name], [Street], [WardCode], [ProvinceCode], [ManagerUserId], [AllowNegativeStock], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 1, 'KHO01', N'Kho tổng', NULL, NULL, NULL, NULL, 0, 1, '2026-11-19T02:33:24.4070000', NULL, NULL, NULL, 0)
;
SET IDENTITY_INSERT [inv].[Warehouses] OFF;
GO

-- lgs.Carriers (6 dòng)
SET IDENTITY_INSERT [lgs].[Carriers] ON;
INSERT INTO [lgs].[Carriers] ([Id], [CompanyId], [Code], [Name], [CarrierType], [PartnerId], [ApiProvider], [ApiConfig], [IsActive]) VALUES
(1, 1, 'GHN', N'Giao Hàng Nhanh', 'third_party', NULL, 'ghn', NULL, 1),
(2, 1, 'GHTK', N'Giao Hàng Tiết Kiệm', 'third_party', NULL, 'ghtk', NULL, 1),
(3, 1, 'VTP', N'Viettel Post', 'third_party', NULL, 'viettelpost', NULL, 1),
(4, 1, 'JT', N'J&T Express', 'third_party', NULL, 'jt', NULL, 1),
(5, 1, 'SPX', N'SPX Express (Shopee)', 'third_party', NULL, NULL, NULL, 1),
(6, 1, 'NOIBO', N'Shop tự giao', 'internal', NULL, NULL, NULL, 1)
;
SET IDENTITY_INSERT [lgs].[Carriers] OFF;
GO

-- lgs.Shipments (100 dòng)
SET IDENTITY_INSERT [lgs].[Shipments] ON;
INSERT INTO [lgs].[Shipments] ([Id], [CompanyId], [DocNo], [SalesOrderId], [StockDocumentId], [CarrierId], [TrackingNo], [ServiceType], [VehicleId], [DriverEmployeeId], [FromWarehouseId], [ReceiverName], [ReceiverPhone], [Street], [WardCode], [ProvinceCode], [PackageCount], [WeightGram], [CodAmount], [InsuranceValue], [ShippingFee], [FeePayer], [Status], [CodStatus], [PickedUpAt], [DeliveredAt], [FailedReason], [Note], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'VD2609-00001', 3, NULL, 4, 'JT000023757', 'Tiêu chu?n', NULL, NULL, 1, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-09-25T14:00:00.0000000', '2026-09-27T09:00:00.0000000', NULL, NULL, '2026-09-25T09:30:00.0000000', 1, NULL, NULL, 0),
(2, 1, 'VD2609-00002', 4, NULL, 1, 'GHN000031676', 'Tiêu chu?n', NULL, NULL, 1, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 1, 500.00, 1040000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-09-25T17:00:00.0000000', '2026-09-27T12:00:00.0000000', NULL, NULL, '2026-09-25T12:30:00.0000000', 1, NULL, NULL, 0),
(3, 1, 'VD2609-00003', 5, NULL, 5, 'SPX000039595', 'Tiêu chu?n', NULL, NULL, 1, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-09-27T08:00:00.0000000', '2026-09-29T03:00:00.0000000', NULL, NULL, '2026-09-27T03:30:00.0000000', 1, NULL, NULL, 0),
(4, 1, 'VD2609-00004', 6, NULL, 5, 'SPX000047514', 'Tiêu chu?n', NULL, NULL, 1, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-09-28T09:00:00.0000000', '2026-09-30T04:00:00.0000000', NULL, NULL, '2026-09-28T04:30:00.0000000', 1, NULL, NULL, 0),
(5, 1, 'VD2609-00005', 7, NULL, 2, 'GHTK000055433', 'Tiêu chu?n', NULL, NULL, 1, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 1, 500.00, 209000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-09-28T11:00:00.0000000', '2026-09-30T06:00:00.0000000', NULL, NULL, '2026-09-28T06:30:00.0000000', 1, NULL, NULL, 0),
(6, 1, 'VD2609-00006', 9, NULL, 2, 'GHTK000071271', 'Tiêu chu?n', NULL, NULL, 1, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 1, 500.00, 1588000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-09-29T12:00:00.0000000', '2026-10-01T07:00:00.0000000', NULL, NULL, '2026-09-29T07:30:00.0000000', 1, NULL, NULL, 0),
(7, 1, 'VD2610-00001', 11, NULL, 2, 'GHTK000087109', 'Tiêu chu?n', NULL, NULL, 1, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 1, 500.00, 638000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-10-01T10:00:00.0000000', '2026-10-03T05:00:00.0000000', NULL, NULL, '2026-10-01T05:30:00.0000000', 1, NULL, NULL, 0),
(8, 1, 'VD2610-00002', 14, NULL, 5, 'SPX000110866', 'Tiêu chu?n', NULL, NULL, 1, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-10-02T16:00:00.0000000', '2026-10-04T11:00:00.0000000', NULL, NULL, '2026-10-02T11:30:00.0000000', 1, NULL, NULL, 0),
(9, 1, 'VD2610-00003', 15, NULL, 4, 'JT000118785', 'Tiêu chu?n', NULL, NULL, 1, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-10-03T16:00:00.0000000', '2026-10-05T11:00:00.0000000', NULL, NULL, '2026-10-03T11:30:00.0000000', 1, NULL, NULL, 0),
(10, 1, 'VD2610-00004', 17, NULL, 5, 'SPX000134623', 'Tiêu chu?n', NULL, NULL, 1, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-10-04T14:00:00.0000000', '2026-10-06T09:00:00.0000000', NULL, NULL, '2026-10-04T09:30:00.0000000', 1, NULL, NULL, 0),
(11, 1, 'VD2610-00005', 18, NULL, 1, 'GHN000142542', 'Tiêu chu?n', NULL, NULL, 1, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 1, 500.00, 1803100.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-10-04T17:00:00.0000000', '2026-10-06T12:00:00.0000000', NULL, NULL, '2026-10-04T12:30:00.0000000', 1, NULL, NULL, 0),
(12, 1, 'VD2610-00006', 20, NULL, 1, 'GHN000158380', 'Tiêu chu?n', NULL, NULL, 1, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 1, 500.00, 1020000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-10-06T17:00:00.0000000', '2026-10-08T12:00:00.0000000', NULL, NULL, '2026-10-06T12:30:00.0000000', 1, NULL, NULL, 0),
(13, 1, 'VD2610-00007', 22, NULL, 4, 'JT000174218', 'Tiêu chu?n', NULL, NULL, 1, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-10-07T15:00:00.0000000', '2026-10-09T10:00:00.0000000', NULL, NULL, '2026-10-07T10:30:00.0000000', 1, NULL, NULL, 0),
(14, 1, 'VD2610-00008', 23, NULL, 2, 'GHTK000182137', 'Tiêu chu?n', NULL, NULL, 1, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 1, 500.00, 469000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-10-07T18:00:00.0000000', '2026-10-09T13:00:00.0000000', NULL, NULL, '2026-10-07T13:30:00.0000000', 1, NULL, NULL, 0),
(15, 1, 'VD2610-00009', 25, NULL, 5, 'SPX000197975', 'Tiêu chu?n', NULL, NULL, 1, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-10-09T09:00:00.0000000', '2026-10-11T04:00:00.0000000', NULL, NULL, '2026-10-09T04:30:00.0000000', 1, NULL, NULL, 0),
(16, 1, 'VD2610-00010', 26, NULL, 1, 'GHN000205894', 'Tiêu chu?n', NULL, NULL, 1, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 1, 500.00, 2208000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-10-09T12:00:00.0000000', '2026-10-11T07:00:00.0000000', NULL, NULL, '2026-10-09T07:30:00.0000000', 1, NULL, NULL, 0),
(17, 1, 'VD2610-00011', 27, NULL, 4, 'JT000213813', 'Tiêu chu?n', NULL, NULL, 1, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-10-10T10:00:00.0000000', '2026-10-12T05:00:00.0000000', NULL, NULL, '2026-10-10T05:30:00.0000000', 1, NULL, NULL, 0),
(18, 1, 'VD2610-00012', 28, NULL, 1, 'GHN000221732', 'Tiêu chu?n', NULL, NULL, 1, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 1, 500.00, 348000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-10-10T13:00:00.0000000', '2026-10-12T08:00:00.0000000', NULL, NULL, '2026-10-10T08:30:00.0000000', 1, NULL, NULL, 0),
(19, 1, 'VD2610-00013', 29, NULL, 2, 'GHTK000229651', 'Tiêu chu?n', NULL, NULL, 1, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 1, 500.00, 700000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-10-12T11:00:00.0000000', '2026-10-14T06:00:00.0000000', NULL, NULL, '2026-10-12T06:30:00.0000000', 1, NULL, NULL, 0),
(20, 1, 'VD2610-00014', 31, NULL, 5, 'SPX000245489', 'Tiêu chu?n', NULL, NULL, 1, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-10-12T16:00:00.0000000', '2026-10-14T11:00:00.0000000', NULL, NULL, '2026-10-12T11:30:00.0000000', 1, NULL, NULL, 0),
(21, 1, 'VD2610-00015', 33, NULL, 5, 'SPX000261327', 'Tiêu chu?n', NULL, NULL, 1, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-10-14T14:00:00.0000000', '2026-10-16T09:00:00.0000000', NULL, NULL, '2026-10-14T09:30:00.0000000', 1, NULL, NULL, 0),
(22, 1, 'VD2610-00016', 34, NULL, 1, 'GHN000269246', 'Tiêu chu?n', NULL, NULL, 1, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 1, 500.00, 1328000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-10-14T17:00:00.0000000', '2026-10-16T12:00:00.0000000', NULL, NULL, '2026-10-14T12:30:00.0000000', 1, NULL, NULL, 0),
(23, 1, 'VD2610-00017', 36, NULL, 5, 'SPX000285084', 'Tiêu chu?n', NULL, NULL, 1, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-10-15T15:00:00.0000000', '2026-10-17T10:00:00.0000000', NULL, NULL, '2026-10-15T10:30:00.0000000', 1, NULL, NULL, 0),
(24, 1, 'VD2610-00018', 37, NULL, 2, 'GHTK000293003', 'Tiêu chu?n', NULL, NULL, 1, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 1, 500.00, 548000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-10-15T18:00:00.0000000', '2026-10-17T13:00:00.0000000', NULL, NULL, '2026-10-15T13:30:00.0000000', 1, NULL, NULL, 0),
(25, 1, 'VD2610-00019', 40, NULL, 4, 'JT000316760', 'Tiêu chu?n', NULL, NULL, 1, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-10-17T16:00:00.0000000', '2026-10-19T11:00:00.0000000', NULL, NULL, '2026-10-17T11:30:00.0000000', 1, NULL, NULL, 0),
(26, 1, 'VD2610-00020', 41, NULL, 2, 'GHTK000324679', 'Tiêu chu?n', NULL, NULL, 1, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 500.00, 439000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-10-17T18:00:00.0000000', '2026-10-19T13:00:00.0000000', NULL, NULL, '2026-10-17T13:30:00.0000000', 1, NULL, NULL, 0),
(27, 1, 'VD2610-00021', 42, NULL, 5, 'SPX000332598', 'Tiêu chu?n', NULL, NULL, 1, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-10-18T10:00:00.0000000', '2026-10-20T05:00:00.0000000', NULL, NULL, '2026-10-18T05:30:00.0000000', 1, NULL, NULL, 0),
(28, 1, 'VD2610-00022', 43, NULL, 4, 'JT000340517', 'Tiêu chu?n', NULL, NULL, 1, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-10-19T10:00:00.0000000', '2026-10-21T05:00:00.0000000', NULL, NULL, '2026-10-19T05:30:00.0000000', 1, NULL, NULL, 0),
(29, 1, 'VD2610-00023', 44, NULL, 1, 'GHN000348436', 'Tiêu chu?n', NULL, NULL, 1, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 1, 500.00, 738000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-10-19T13:00:00.0000000', '2026-10-21T08:00:00.0000000', NULL, NULL, '2026-10-19T08:30:00.0000000', 1, NULL, NULL, 0),
(30, 1, 'VD2610-00024', 46, NULL, 4, 'JT000364274', 'Tiêu chu?n', NULL, NULL, 1, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-10-20T11:00:00.0000000', '2026-10-22T06:00:00.0000000', NULL, NULL, '2026-10-20T06:30:00.0000000', 1, NULL, NULL, 0),
(31, 1, 'VD2610-00025', 47, NULL, 2, 'GHTK000372193', 'Tiêu chu?n', NULL, NULL, 1, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 1, 500.00, 720000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-10-21T11:00:00.0000000', '2026-10-23T06:00:00.0000000', NULL, NULL, '2026-10-21T06:30:00.0000000', 1, NULL, NULL, 0),
(32, 1, 'VD2610-00026', 51, NULL, 5, 'SPX000403869', 'Tiêu chu?n', NULL, NULL, 1, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-10-22T17:00:00.0000000', '2026-10-24T12:00:00.0000000', NULL, NULL, '2026-10-22T12:30:00.0000000', 1, NULL, NULL, 0),
(33, 1, 'VD2610-00027', 53, NULL, 5, 'SPX000419707', 'Tiêu chu?n', NULL, NULL, 1, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-10-24T15:00:00.0000000', '2026-10-26T10:00:00.0000000', NULL, NULL, '2026-10-24T10:30:00.0000000', 1, NULL, NULL, 0),
(34, 1, 'VD2610-00028', 54, NULL, 5, 'SPX000427626', 'Tiêu chu?n', NULL, NULL, 1, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-10-24T16:00:00.0000000', '2026-10-26T11:00:00.0000000', NULL, NULL, '2026-10-24T11:30:00.0000000', 1, NULL, NULL, 0),
(35, 1, 'VD2610-00029', 55, NULL, 2, 'GHTK000435545', 'Tiêu chu?n', NULL, NULL, 1, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 500.00, 1106100.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-10-24T18:00:00.0000000', '2026-10-26T13:00:00.0000000', NULL, NULL, '2026-10-24T13:30:00.0000000', 1, NULL, NULL, 0),
(36, 1, 'VD2610-00030', 56, NULL, 1, 'GHN000443464', 'Tiêu chu?n', NULL, NULL, 1, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 1, 500.00, 229000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-10-25T07:00:00.0000000', '2026-10-27T02:00:00.0000000', NULL, NULL, '2026-10-25T02:30:00.0000000', 1, NULL, NULL, 0),
(37, 1, 'VD2610-00031', 59, NULL, 5, 'SPX000467221', 'Tiêu chu?n', NULL, NULL, 1, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-10-26T10:00:00.0000000', '2026-10-28T05:00:00.0000000', NULL, NULL, '2026-10-26T05:30:00.0000000', 1, NULL, NULL, 0),
(38, 1, 'VD2610-00032', 60, NULL, 1, 'GHN000475140', 'Tiêu chu?n', NULL, NULL, 1, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 1, 500.00, 707000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-10-26T17:00:00.0000000', '2026-10-28T12:00:00.0000000', NULL, NULL, '2026-10-26T12:30:00.0000000', 1, NULL, NULL, 0),
(39, 1, 'VD2610-00033', 63, NULL, 4, 'JT000498897', 'Tiêu chu?n', NULL, NULL, 1, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-10-28T11:00:00.0000000', '2026-10-30T06:00:00.0000000', NULL, NULL, '2026-10-28T06:30:00.0000000', 1, NULL, NULL, 0),
(40, 1, 'VD2610-00034', 64, NULL, 1, 'GHN000506816', 'Tiêu chu?n', NULL, NULL, 1, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 500.00, 279000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-10-28T14:00:00.0000000', '2026-10-30T09:00:00.0000000', NULL, NULL, '2026-10-28T09:30:00.0000000', 1, NULL, NULL, 0),
(41, 1, 'VD2610-00035', 65, NULL, 4, 'JT000514735', 'Tiêu chu?n', NULL, NULL, 1, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-10-29T12:00:00.0000000', '2026-10-31T07:00:00.0000000', NULL, NULL, '2026-10-29T07:30:00.0000000', 1, NULL, NULL, 0),
(42, 1, 'VD2610-00036', 67, NULL, 2, 'GHTK000530573', 'Tiêu chu?n', NULL, NULL, 1, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 1, 500.00, 568000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-10-30T13:00:00.0000000', '2026-11-01T08:00:00.0000000', NULL, NULL, '2026-10-30T08:30:00.0000000', 1, NULL, NULL, 0),
(43, 1, 'VD2610-00037', 69, NULL, 4, 'JT000546411', 'Tiêu chu?n', NULL, NULL, 1, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-10-30T18:00:00.0000000', '2026-11-01T13:00:00.0000000', NULL, NULL, '2026-10-30T13:30:00.0000000', 1, NULL, NULL, 0),
(44, 1, 'VD2611-00001', 71, NULL, 2, 'GHTK000562249', 'Tiêu chu?n', NULL, NULL, 1, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 1, 500.00, 189000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-11-01T07:00:00.0000000', '2026-11-03T02:00:00.0000000', NULL, NULL, '2026-11-01T02:30:00.0000000', 1, NULL, NULL, 0),
(45, 1, 'VD2611-00002', 73, NULL, 5, 'SPX000578087', 'Tiêu chu?n', NULL, NULL, 1, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-01T16:00:00.0000000', '2026-11-03T11:00:00.0000000', NULL, NULL, '2026-11-01T11:30:00.0000000', 1, NULL, NULL, 0),
(46, 1, 'VD2611-00003', 74, NULL, 5, 'SPX000586006', 'Tiêu chu?n', NULL, NULL, 1, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-01T17:00:00.0000000', '2026-11-03T12:00:00.0000000', NULL, NULL, '2026-11-01T12:30:00.0000000', 1, NULL, NULL, 0),
(47, 1, 'VD2611-00004', 75, NULL, 2, 'GHTK000593925', 'Tiêu chu?n', NULL, NULL, 1, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 1, 500.00, 2037000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-11-02T17:00:00.0000000', '2026-11-04T12:00:00.0000000', NULL, NULL, '2026-11-02T12:30:00.0000000', 1, NULL, NULL, 0),
(48, 1, 'VD2611-00005', 78, NULL, 5, 'SPX000617682', 'Tiêu chu?n', NULL, NULL, 1, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-03T11:00:00.0000000', '2026-11-05T06:00:00.0000000', NULL, NULL, '2026-11-03T06:30:00.0000000', 1, NULL, NULL, 0),
(49, 1, 'VD2611-00006', 79, NULL, 2, 'GHTK000625601', 'Tiêu chu?n', NULL, NULL, 1, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 500.00, 628000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-11-03T18:00:00.0000000', '2026-11-05T13:00:00.0000000', NULL, NULL, '2026-11-03T13:30:00.0000000', 1, NULL, NULL, 0),
(50, 1, 'VD2611-00007', 81, NULL, 4, 'JT000641439', 'Tiêu chu?n', NULL, NULL, 1, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-11-04T12:00:00.0000000', '2026-11-06T07:00:00.0000000', NULL, NULL, '2026-11-04T07:30:00.0000000', 1, NULL, NULL, 0),
(51, 1, 'VD2611-00008', 82, NULL, 5, 'SPX000649358', 'Tiêu chu?n', NULL, NULL, 1, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-05T10:00:00.0000000', '2026-11-07T05:00:00.0000000', NULL, NULL, '2026-11-05T05:30:00.0000000', 1, NULL, NULL, 0),
(52, 1, 'VD2611-00009', 85, NULL, 4, 'JT000673115', 'Tiêu chu?n', NULL, NULL, 1, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-11-06T07:00:00.0000000', '2026-11-08T02:00:00.0000000', NULL, NULL, '2026-11-06T02:30:00.0000000', 1, NULL, NULL, 0),
(53, 1, 'VD2611-00010', 86, NULL, 1, 'GHN000681034', 'Tiêu chu?n', NULL, NULL, 1, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 1, 500.00, 279000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-11-06T13:00:00.0000000', '2026-11-08T08:00:00.0000000', NULL, NULL, '2026-11-06T08:30:00.0000000', 1, NULL, NULL, 0),
(54, 1, 'VD2611-00011', 87, NULL, 2, 'GHTK000688953', 'Tiêu chu?n', NULL, NULL, 1, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 500.00, 459000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-11-06T14:00:00.0000000', '2026-11-08T09:00:00.0000000', NULL, NULL, '2026-11-06T09:30:00.0000000', 1, NULL, NULL, 0),
(55, 1, 'VD2611-00012', 90, NULL, 5, 'SPX000712710', 'Tiêu chu?n', NULL, NULL, 1, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-07T17:00:00.0000000', '2026-11-09T12:00:00.0000000', NULL, NULL, '2026-11-07T12:30:00.0000000', 1, NULL, NULL, 0),
(56, 1, 'VD2611-00013', 91, NULL, 2, 'GHTK000720629', 'Tiêu chu?n', NULL, NULL, 1, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 1, 500.00, 1066000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-11-08T08:00:00.0000000', '2026-11-10T03:00:00.0000000', NULL, NULL, '2026-11-08T03:30:00.0000000', 1, NULL, NULL, 0),
(57, 1, 'VD2611-00014', 93, NULL, 4, 'JT000736467', 'Tiêu chu?n', NULL, NULL, 1, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-11-08T18:00:00.0000000', '2026-11-10T13:00:00.0000000', NULL, NULL, '2026-11-08T13:30:00.0000000', 1, NULL, NULL, 0),
(58, 1, 'VD2611-00015', 94, NULL, 1, 'GHN000744386', 'Tiêu chu?n', NULL, NULL, 1, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 1, 500.00, 651000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-11-09T07:00:00.0000000', '2026-11-11T02:00:00.0000000', NULL, NULL, '2026-11-09T02:30:00.0000000', 1, NULL, NULL, 0),
(59, 1, 'VD2611-00016', 97, NULL, 5, 'SPX000768143', 'Tiêu chu?n', NULL, NULL, 1, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-09T12:00:00.0000000', '2026-11-11T07:00:00.0000000', NULL, NULL, '2026-11-09T07:30:00.0000000', 1, NULL, NULL, 0),
(60, 1, 'VD2611-00017', 98, NULL, 1, 'GHN000776062', 'Tiêu chu?n', NULL, NULL, 1, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 1, 500.00, 348000.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-11-09T18:00:00.0000000', '2026-11-11T13:00:00.0000000', NULL, NULL, '2026-11-09T13:30:00.0000000', 1, NULL, NULL, 0),
(61, 1, 'VD2611-00018', 99, NULL, 5, 'SPX000783981', 'Tiêu chu?n', NULL, NULL, 1, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-10T10:00:00.0000000', '2026-11-12T05:00:00.0000000', NULL, NULL, '2026-11-10T05:30:00.0000000', 1, NULL, NULL, 0),
(62, 1, 'VD2611-00019', 101, NULL, 4, 'JT000799819', 'Tiêu chu?n', NULL, NULL, 1, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-11-11T07:00:00.0000000', '2026-11-13T02:00:00.0000000', NULL, NULL, '2026-11-11T02:30:00.0000000', 1, NULL, NULL, 0),
(63, 1, 'VD2611-00020', 102, NULL, 5, 'SPX000807738', 'Tiêu chu?n', NULL, NULL, 1, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-11T11:00:00.0000000', '2026-11-13T06:00:00.0000000', NULL, NULL, '2026-11-11T06:30:00.0000000', 1, NULL, NULL, 0),
(64, 1, 'VD2611-00021', 104, NULL, 4, 'JT000823576', 'Tiêu chu?n', NULL, NULL, 1, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-11-12T08:00:00.0000000', '2026-11-14T03:00:00.0000000', NULL, NULL, '2026-11-12T03:30:00.0000000', 1, NULL, NULL, 0),
(65, 1, 'VD2611-00022', 105, NULL, 2, 'GHTK000831495', 'Tiêu chu?n', NULL, NULL, 1, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 1, 500.00, 528000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-11-12T14:00:00.0000000', '2026-11-14T09:00:00.0000000', NULL, NULL, '2026-11-12T09:30:00.0000000', 1, NULL, NULL, 0),
(66, 1, 'VD2611-00023', 108, NULL, 4, 'JT000855252', 'Tiêu chu?n', NULL, NULL, 1, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-11-13T07:00:00.0000000', '2026-11-15T02:00:00.0000000', NULL, NULL, '2026-11-13T02:30:00.0000000', 1, NULL, NULL, 0),
(67, 1, 'VD2611-00024', 109, NULL, 2, 'GHTK000863171', 'Tiêu chu?n', NULL, NULL, 1, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 1, 500.00, 817000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-11-13T09:00:00.0000000', '2026-11-15T04:00:00.0000000', NULL, NULL, '2026-11-13T04:30:00.0000000', 1, NULL, NULL, 0),
(68, 1, 'VD2611-00025', 112, NULL, 4, 'JT000886928', 'Tiêu chu?n', NULL, NULL, 1, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-11-13T18:00:00.0000000', '2026-11-15T13:00:00.0000000', NULL, NULL, '2026-11-13T13:30:00.0000000', 1, NULL, NULL, 0),
(69, 1, 'VD2611-00026', 113, NULL, 2, 'GHTK000894847', 'Tiêu chu?n', NULL, NULL, 1, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 1, 500.00, 469000.00, 0.00, 25000.00, 'sender', 'delivered', 'reconciled', '2026-11-14T07:00:00.0000000', '2026-11-16T02:00:00.0000000', NULL, NULL, '2026-11-14T02:30:00.0000000', 1, NULL, NULL, 0),
(70, 1, 'VD2611-00027', 114, NULL, 1, 'GHN000902766', 'Tiêu chu?n', NULL, NULL, 1, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 1, 500.00, 1334200.00, 0.00, 28000.00, 'sender', 'delivered', 'reconciled', '2026-11-14T08:00:00.0000000', '2026-11-16T03:00:00.0000000', NULL, NULL, '2026-11-14T03:30:00.0000000', 1, NULL, NULL, 0),
(71, 1, 'VD2611-00028', 116, NULL, 5, 'SPX000918604', 'Tiêu chu?n', NULL, NULL, 1, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-14T13:00:00.0000000', '2026-11-16T08:00:00.0000000', NULL, NULL, '2026-11-14T08:30:00.0000000', 1, NULL, NULL, 0),
(72, 1, 'VD2611-00029', 117, NULL, 5, 'SPX000926523', 'Tiêu chu?n', NULL, NULL, 1, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-15T11:00:00.0000000', '2026-11-17T06:00:00.0000000', NULL, NULL, '2026-11-15T06:30:00.0000000', 1, NULL, NULL, 0),
(73, 1, 'VD2611-00030', 118, NULL, 5, 'SPX000934442', 'Tiêu chu?n', NULL, NULL, 1, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-15T12:00:00.0000000', '2026-11-17T07:00:00.0000000', NULL, NULL, '2026-11-15T07:30:00.0000000', 1, NULL, NULL, 0),
(74, 1, 'VD2611-00031', 119, NULL, 2, 'GHTK000942361', 'Tiêu chu?n', NULL, NULL, 1, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 1, 500.00, 2100000.00, 0.00, 25000.00, 'sender', 'delivered', 'collected', '2026-11-15T14:00:00.0000000', '2026-11-17T09:00:00.0000000', NULL, NULL, '2026-11-15T09:30:00.0000000', 1, NULL, NULL, 0),
(75, 1, 'VD2611-00032', 122, NULL, 4, 'JT000966118', 'Tiêu chu?n', NULL, NULL, 1, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-11-16T08:00:00.0000000', '2026-11-18T03:00:00.0000000', NULL, NULL, '2026-11-16T03:30:00.0000000', 1, NULL, NULL, 0),
(76, 1, 'VD2611-00033', 123, NULL, 2, 'GHTK000974037', 'Tiêu chu?n', NULL, NULL, 1, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 1, 500.00, 1317000.00, 0.00, 25000.00, 'sender', 'delivered', 'collected', '2026-11-16T09:00:00.0000000', '2026-11-18T04:00:00.0000000', NULL, NULL, '2026-11-16T04:30:00.0000000', 1, NULL, NULL, 0),
(77, 1, 'VD2611-00034', 126, NULL, 5, 'SPX000997794', 'Tiêu chu?n', NULL, NULL, 1, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-16T18:00:00.0000000', '2026-11-18T13:00:00.0000000', NULL, NULL, '2026-11-16T13:30:00.0000000', 1, NULL, NULL, 0),
(78, 1, 'VD2611-00035', 127, NULL, 4, 'JT001005713', 'Tiêu chu?n', NULL, NULL, 1, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-11-17T07:00:00.0000000', '2026-11-19T02:00:00.0000000', NULL, NULL, '2026-11-17T02:30:00.0000000', 1, NULL, NULL, 0),
(79, 1, 'VD2611-00036', 128, NULL, 1, 'GHN001013632', 'Tiêu chu?n', NULL, NULL, 1, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 1, 500.00, 949100.00, 0.00, 28000.00, 'sender', 'delivered', 'collected', '2026-11-17T08:00:00.0000000', '2026-11-19T03:00:00.0000000', NULL, NULL, '2026-11-17T03:30:00.0000000', 1, NULL, NULL, 0),
(80, 1, 'VD2611-00037', 129, NULL, 2, 'GHTK001021551', 'Tiêu chu?n', NULL, NULL, 1, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 1, 500.00, 316200.00, 0.00, 25000.00, 'sender', 'delivered', 'collected', '2026-11-17T10:00:00.0000000', '2026-11-19T05:00:00.0000000', NULL, NULL, '2026-11-17T05:30:00.0000000', 1, NULL, NULL, 0),
(81, 1, 'VD2611-00038', 132, NULL, 5, 'SPX001045308', 'Tiêu chu?n', NULL, NULL, 1, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'delivered', 'none', '2026-11-17T13:00:00.0000000', '2026-11-19T08:00:00.0000000', NULL, NULL, '2026-11-17T08:30:00.0000000', 1, NULL, NULL, 0),
(82, 1, 'VD2611-00039', 133, NULL, 2, 'GHTK001053227', 'Tiêu chu?n', NULL, NULL, 1, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 1, 500.00, 707000.00, 0.00, 25000.00, 'sender', 'in_transit', 'pending', '2026-11-18T09:00:00.0000000', NULL, NULL, NULL, '2026-11-18T04:30:00.0000000', 1, NULL, NULL, 0),
(83, 1, 'VD2611-00040', 135, NULL, 5, NULL, 'Tiêu chu?n', NULL, NULL, 1, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'ready', 'none', NULL, NULL, NULL, NULL, '2026-11-18T07:30:00.0000000', 1, NULL, NULL, 0),
(84, 1, 'VD2611-00041', 138, NULL, 1, 'GHN001092822', 'Tiêu chu?n', NULL, NULL, 1, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 1, 500.00, 229000.00, 0.00, 28000.00, 'sender', 'in_transit', 'pending', '2026-11-18T15:00:00.0000000', NULL, NULL, NULL, '2026-11-18T10:30:00.0000000', 1, NULL, NULL, 0),
(85, 1, 'VD2611-00042', 141, NULL, 5, 'SPX001116579', 'Tiêu chu?n', NULL, NULL, 1, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'picked_up', 'none', '2026-11-19T07:00:00.0000000', NULL, NULL, NULL, '2026-11-19T02:30:00.0000000', 1, NULL, NULL, 0),
(86, 1, 'VD2611-00043', 143, NULL, 2, 'GHTK001132417', 'Tiêu chu?n', NULL, NULL, 1, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 1, 500.00, 1799000.00, 0.00, 25000.00, 'sender', 'failed', 'pending', '2026-11-19T09:00:00.0000000', NULL, N'Khách không nghe máy, hẹn giao lại', NULL, '2026-11-19T04:30:00.0000000', 1, NULL, NULL, 0),
(87, 1, 'VD2611-00044', 144, NULL, 1, 'GHN001140336', 'Tiêu chu?n', NULL, NULL, 1, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 1, 500.00, 889200.00, 0.00, 28000.00, 'sender', 'in_transit', 'pending', '2026-11-19T10:00:00.0000000', NULL, NULL, NULL, '2026-11-19T05:30:00.0000000', 1, NULL, NULL, 0),
(88, 1, 'VD2611-00045', 147, NULL, 5, 'SPX001164093', 'Tiêu chu?n', NULL, NULL, 1, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'in_transit', 'none', '2026-11-19T14:00:00.0000000', NULL, NULL, NULL, '2026-11-19T09:30:00.0000000', 1, NULL, NULL, 0),
(89, 1, 'VD2611-00046', 150, NULL, 5, NULL, 'Tiêu chu?n', NULL, NULL, 1, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'ready', 'none', NULL, NULL, NULL, NULL, '2026-11-20T03:30:00.0000000', 1, NULL, NULL, 0),
(90, 1, 'VD2611-00047', 151, NULL, 2, 'GHTK001195769', 'Tiêu chu?n', NULL, NULL, 1, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 1, 500.00, 757000.00, 0.00, 25000.00, 'sender', 'picked_up', 'pending', '2026-11-20T09:00:00.0000000', NULL, NULL, NULL, '2026-11-20T04:30:00.0000000', 1, NULL, NULL, 0),
(91, 1, 'VD2611-00048', 152, NULL, 1, 'GHN001203688', 'Tiêu chu?n', NULL, NULL, 1, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 1, 500.00, 268000.00, 0.00, 28000.00, 'sender', 'in_transit', 'pending', '2026-11-20T09:00:00.0000000', NULL, NULL, NULL, '2026-11-20T04:30:00.0000000', 1, NULL, NULL, 0),
(92, 1, 'VD2611-00049', 153, NULL, 2, 'GHTK001211607', 'Tiêu chu?n', NULL, NULL, 1, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 1, 500.00, 1410000.00, 0.00, 25000.00, 'sender', 'in_transit', 'pending', '2026-11-20T10:00:00.0000000', NULL, NULL, NULL, '2026-11-20T05:30:00.0000000', 1, NULL, NULL, 0),
(93, 1, 'VD2611-00050', 154, NULL, 1, 'GHN001219526', 'Tiêu chu?n', NULL, NULL, 1, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 1, 500.00, 1020000.00, 0.00, 28000.00, 'sender', 'in_transit', 'pending', '2026-11-20T10:00:00.0000000', NULL, NULL, NULL, '2026-11-20T05:30:00.0000000', 1, NULL, NULL, 0),
(94, 1, 'VD2611-00051', 155, NULL, 2, NULL, 'Tiêu chu?n', NULL, NULL, 1, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 1, 500.00, 688000.00, 0.00, 25000.00, 'sender', 'ready', 'pending', NULL, NULL, NULL, NULL, '2026-11-20T05:30:00.0000000', 1, NULL, NULL, 0),
(95, 1, 'VD2611-00052', 156, NULL, 1, 'GHN001235364', 'Tiêu chu?n', NULL, NULL, 1, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 1, 500.00, 359000.00, 0.00, 28000.00, 'sender', 'picked_up', 'pending', '2026-11-20T11:00:00.0000000', NULL, NULL, NULL, '2026-11-20T06:30:00.0000000', 1, NULL, NULL, 0),
(96, 1, 'VD2611-00053', 168, NULL, 1, 'GHN001330392', 'Tiêu chu?n', NULL, NULL, 1, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 1, 500.00, 917000.00, 0.00, 28000.00, 'sender', 'in_transit', 'pending', '2026-11-20T11:09:33.0000000', NULL, NULL, NULL, '2026-11-20T06:39:33.0000000', 1, NULL, NULL, 0),
(97, 1, 'VD2611-00054', 166, NULL, 4, 'JT001314554', 'Tiêu chu?n', NULL, NULL, 1, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-11-20T12:23:33.0000000', '2026-11-20T14:17:41.0000000', NULL, NULL, '2026-11-20T07:53:33.0000000', 1, NULL, NULL, 0),
(98, 1, 'VD2611-00055', 165, NULL, 4, 'JT001306635', 'Tiêu chu?n', NULL, NULL, 1, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 22000.00, 'sender', 'delivered', 'none', '2026-11-20T13:00:33.0000000', '2026-11-20T14:17:41.0000000', NULL, NULL, '2026-11-20T08:30:33.0000000', 1, NULL, NULL, 0),
(99, 1, 'VD2611-00056', 164, NULL, 5, 'SPX001298716', 'Tiêu chu?n', NULL, NULL, 1, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'failed', 'none', '2026-11-20T13:37:33.0000000', NULL, N'Khách không nghe máy, hẹn giao lại', NULL, '2026-11-20T09:07:33.0000000', 1, NULL, NULL, 0),
(100, 1, 'VD2611-00057', 162, NULL, 5, 'SPX001282878', 'Tiêu chu?n', NULL, NULL, 1, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 1, 500.00, 0.00, 0.00, 18000.00, 'sender', 'in_transit', 'none', '2026-11-20T14:00:00.0000000', NULL, NULL, NULL, '2026-11-20T09:30:00.0000000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [lgs].[Shipments] OFF;
GO

-- lgs.ShipmentTrackingEvents (368 dòng)
SET IDENTITY_INSERT [lgs].[ShipmentTrackingEvents] ON;
INSERT INTO [lgs].[ShipmentTrackingEvents] ([Id], [ShipmentId], [EventAt], [StatusCode], [Description], [Location], [RawPayload], [ReceivedAt]) VALUES
(1, 1, '2026-09-25T09:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(2, 2, '2026-09-25T12:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(3, 3, '2026-09-27T03:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(4, 4, '2026-09-28T04:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(5, 5, '2026-09-28T06:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(6, 6, '2026-09-29T07:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(7, 7, '2026-10-01T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(8, 8, '2026-10-02T11:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(9, 9, '2026-10-03T11:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(10, 10, '2026-10-04T09:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(11, 11, '2026-10-04T12:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(12, 12, '2026-10-06T12:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(13, 13, '2026-10-07T10:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(14, 14, '2026-10-07T13:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(15, 15, '2026-10-09T04:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(16, 16, '2026-10-09T07:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(17, 17, '2026-10-10T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(18, 18, '2026-10-10T08:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(19, 19, '2026-10-12T06:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(20, 20, '2026-10-12T11:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(21, 21, '2026-10-14T09:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(22, 22, '2026-10-14T12:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(23, 23, '2026-10-15T10:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(24, 24, '2026-10-15T13:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(25, 25, '2026-10-17T11:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(26, 26, '2026-10-17T13:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(27, 27, '2026-10-18T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(28, 28, '2026-10-19T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(29, 29, '2026-10-19T08:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(30, 30, '2026-10-20T06:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(31, 31, '2026-10-21T06:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(32, 32, '2026-10-22T12:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(33, 33, '2026-10-24T10:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(34, 34, '2026-10-24T11:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(35, 35, '2026-10-24T13:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(36, 36, '2026-10-25T02:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(37, 37, '2026-10-26T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(38, 38, '2026-10-26T12:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(39, 39, '2026-10-28T06:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(40, 40, '2026-10-28T09:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(41, 41, '2026-10-29T07:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(42, 42, '2026-10-30T08:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(43, 43, '2026-10-30T13:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(44, 44, '2026-11-01T02:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(45, 45, '2026-11-01T11:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(46, 46, '2026-11-01T12:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(47, 47, '2026-11-02T12:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(48, 48, '2026-11-03T06:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(49, 49, '2026-11-03T13:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(50, 50, '2026-11-04T07:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(51, 51, '2026-11-05T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(52, 52, '2026-11-06T02:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(53, 53, '2026-11-06T08:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(54, 54, '2026-11-06T09:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(55, 55, '2026-11-07T12:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(56, 56, '2026-11-08T03:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(57, 57, '2026-11-08T13:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(58, 58, '2026-11-09T02:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(59, 59, '2026-11-09T07:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(60, 60, '2026-11-09T13:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(61, 61, '2026-11-10T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(62, 62, '2026-11-11T02:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(63, 63, '2026-11-11T06:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(64, 64, '2026-11-12T03:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(65, 65, '2026-11-12T09:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(66, 66, '2026-11-13T02:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(67, 67, '2026-11-13T04:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(68, 68, '2026-11-13T13:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(69, 69, '2026-11-14T02:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(70, 70, '2026-11-14T03:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(71, 71, '2026-11-14T08:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(72, 72, '2026-11-15T06:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(73, 73, '2026-11-15T07:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(74, 74, '2026-11-15T09:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(75, 75, '2026-11-16T03:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(76, 76, '2026-11-16T04:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(77, 77, '2026-11-16T13:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(78, 78, '2026-11-17T02:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(79, 79, '2026-11-17T03:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(80, 80, '2026-11-17T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(81, 81, '2026-11-17T08:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(82, 82, '2026-11-18T04:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(83, 83, '2026-11-18T07:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(84, 84, '2026-11-18T10:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(85, 85, '2026-11-19T02:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(86, 86, '2026-11-19T04:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(87, 87, '2026-11-19T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(88, 88, '2026-11-19T09:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(89, 89, '2026-11-20T03:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(90, 90, '2026-11-20T04:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(91, 91, '2026-11-20T04:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(92, 92, '2026-11-20T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(93, 93, '2026-11-20T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(94, 94, '2026-11-20T05:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(95, 95, '2026-11-20T06:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(96, 96, '2026-11-20T06:39:33.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(97, 97, '2026-11-20T07:53:33.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(98, 98, '2026-11-20T08:30:33.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(99, 99, '2026-11-20T09:07:33.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(100, 100, '2026-11-20T09:30:00.0000000', 'ready', N'Tạo vận đơn, chờ hãng lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(101, 1, '2026-09-25T14:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(102, 2, '2026-09-25T17:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(103, 3, '2026-09-27T08:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(104, 4, '2026-09-28T09:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(105, 5, '2026-09-28T11:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(106, 6, '2026-09-29T12:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(107, 7, '2026-10-01T10:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(108, 8, '2026-10-02T16:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(109, 9, '2026-10-03T16:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(110, 10, '2026-10-04T14:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(111, 11, '2026-10-04T17:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(112, 12, '2026-10-06T17:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(113, 13, '2026-10-07T15:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(114, 14, '2026-10-07T18:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(115, 15, '2026-10-09T09:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(116, 16, '2026-10-09T12:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(117, 17, '2026-10-10T10:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(118, 18, '2026-10-10T13:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(119, 19, '2026-10-12T11:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(120, 20, '2026-10-12T16:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(121, 21, '2026-10-14T14:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(122, 22, '2026-10-14T17:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(123, 23, '2026-10-15T15:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(124, 24, '2026-10-15T18:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(125, 25, '2026-10-17T16:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(126, 26, '2026-10-17T18:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(127, 27, '2026-10-18T10:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(128, 28, '2026-10-19T10:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(129, 29, '2026-10-19T13:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(130, 30, '2026-10-20T11:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(131, 31, '2026-10-21T11:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(132, 32, '2026-10-22T17:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(133, 33, '2026-10-24T15:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(134, 34, '2026-10-24T16:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(135, 35, '2026-10-24T18:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(136, 36, '2026-10-25T07:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(137, 37, '2026-10-26T10:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(138, 38, '2026-10-26T17:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(139, 39, '2026-10-28T11:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(140, 40, '2026-10-28T14:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(141, 41, '2026-10-29T12:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(142, 42, '2026-10-30T13:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(143, 43, '2026-10-30T18:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(144, 44, '2026-11-01T07:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(145, 45, '2026-11-01T16:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(146, 46, '2026-11-01T17:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(147, 47, '2026-11-02T17:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(148, 48, '2026-11-03T11:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(149, 49, '2026-11-03T18:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(150, 50, '2026-11-04T12:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(151, 51, '2026-11-05T10:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(152, 52, '2026-11-06T07:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(153, 53, '2026-11-06T13:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(154, 54, '2026-11-06T14:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(155, 55, '2026-11-07T17:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(156, 56, '2026-11-08T08:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(157, 57, '2026-11-08T18:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(158, 58, '2026-11-09T07:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(159, 59, '2026-11-09T12:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(160, 60, '2026-11-09T18:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(161, 61, '2026-11-10T10:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(162, 62, '2026-11-11T07:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(163, 63, '2026-11-11T11:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(164, 64, '2026-11-12T08:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(165, 65, '2026-11-12T14:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(166, 66, '2026-11-13T07:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(167, 67, '2026-11-13T09:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(168, 68, '2026-11-13T18:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(169, 69, '2026-11-14T07:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(170, 70, '2026-11-14T08:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(171, 71, '2026-11-14T13:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(172, 72, '2026-11-15T11:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(173, 73, '2026-11-15T12:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(174, 74, '2026-11-15T14:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(175, 75, '2026-11-16T08:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(176, 76, '2026-11-16T09:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(177, 77, '2026-11-16T18:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(178, 78, '2026-11-17T07:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(179, 79, '2026-11-17T08:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(180, 80, '2026-11-17T10:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(181, 81, '2026-11-17T13:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(182, 82, '2026-11-18T09:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(183, 84, '2026-11-18T15:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(184, 85, '2026-11-19T07:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(185, 86, '2026-11-19T09:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(186, 87, '2026-11-19T10:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(187, 88, '2026-11-19T14:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(188, 90, '2026-11-20T09:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(189, 91, '2026-11-20T09:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(190, 92, '2026-11-20T10:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(191, 93, '2026-11-20T10:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(192, 95, '2026-11-20T11:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(193, 96, '2026-11-20T11:09:33.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(194, 97, '2026-11-20T12:23:33.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(195, 98, '2026-11-20T13:00:33.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(196, 99, '2026-11-20T13:37:33.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(197, 100, '2026-11-20T14:00:00.0000000', 'picked_up', N'Hãng đã lấy hàng', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(198, 1, '2026-09-26T02:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(199, 2, '2026-09-26T05:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(200, 3, '2026-09-27T20:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(201, 4, '2026-09-28T21:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(202, 5, '2026-09-28T23:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(203, 6, '2026-09-30T00:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(204, 7, '2026-10-01T22:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(205, 8, '2026-10-03T04:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(206, 9, '2026-10-04T04:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(207, 10, '2026-10-05T02:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(208, 11, '2026-10-05T05:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(209, 12, '2026-10-07T05:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(210, 13, '2026-10-08T03:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(211, 14, '2026-10-08T06:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(212, 15, '2026-10-09T21:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(213, 16, '2026-10-10T00:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(214, 17, '2026-10-10T22:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(215, 18, '2026-10-11T01:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(216, 19, '2026-10-12T23:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(217, 20, '2026-10-13T04:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(218, 21, '2026-10-15T02:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(219, 22, '2026-10-15T05:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(220, 23, '2026-10-16T03:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(221, 24, '2026-10-16T06:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(222, 25, '2026-10-18T04:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(223, 26, '2026-10-18T06:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(224, 27, '2026-10-18T22:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(225, 28, '2026-10-19T22:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(226, 29, '2026-10-20T01:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(227, 30, '2026-10-20T23:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(228, 31, '2026-10-21T23:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(229, 32, '2026-10-23T05:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(230, 33, '2026-10-25T03:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(231, 34, '2026-10-25T04:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(232, 35, '2026-10-25T06:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(233, 36, '2026-10-25T19:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(234, 37, '2026-10-26T22:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(235, 38, '2026-10-27T05:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(236, 39, '2026-10-28T23:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(237, 40, '2026-10-29T02:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(238, 41, '2026-10-30T00:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(239, 42, '2026-10-31T01:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(240, 43, '2026-10-31T06:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(241, 44, '2026-11-01T19:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(242, 45, '2026-11-02T04:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(243, 46, '2026-11-02T05:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(244, 47, '2026-11-03T05:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(245, 48, '2026-11-03T23:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(246, 49, '2026-11-04T06:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(247, 50, '2026-11-05T00:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(248, 51, '2026-11-05T22:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(249, 52, '2026-11-06T19:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(250, 53, '2026-11-07T01:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(251, 54, '2026-11-07T02:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(252, 55, '2026-11-08T05:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(253, 56, '2026-11-08T20:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(254, 57, '2026-11-09T06:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(255, 58, '2026-11-09T19:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(256, 59, '2026-11-10T00:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(257, 60, '2026-11-10T06:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(258, 61, '2026-11-10T22:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(259, 62, '2026-11-11T19:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(260, 63, '2026-11-11T23:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(261, 64, '2026-11-12T20:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(262, 65, '2026-11-13T02:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(263, 66, '2026-11-13T19:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(264, 67, '2026-11-13T21:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(265, 68, '2026-11-14T06:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(266, 69, '2026-11-14T19:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(267, 70, '2026-11-14T20:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(268, 71, '2026-11-15T01:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(269, 72, '2026-11-15T23:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(270, 73, '2026-11-16T00:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(271, 74, '2026-11-16T02:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(272, 75, '2026-11-16T20:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(273, 76, '2026-11-16T21:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(274, 77, '2026-11-17T06:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(275, 78, '2026-11-17T19:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(276, 79, '2026-11-17T20:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(277, 80, '2026-11-17T22:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(278, 81, '2026-11-18T01:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(279, 82, '2026-11-18T21:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(280, 84, '2026-11-19T03:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(281, 86, '2026-11-19T21:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(282, 87, '2026-11-19T22:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(283, 88, '2026-11-20T02:00:00.0000000', 'in_transit', N'Đang giao đến người nhận', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(284, 1, '2026-09-27T09:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(285, 2, '2026-09-27T12:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(286, 3, '2026-09-29T03:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(287, 4, '2026-09-30T04:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(288, 5, '2026-09-30T06:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(289, 6, '2026-10-01T07:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(290, 7, '2026-10-03T05:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(291, 8, '2026-10-04T11:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(292, 9, '2026-10-05T11:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(293, 10, '2026-10-06T09:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(294, 11, '2026-10-06T12:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(295, 12, '2026-10-08T12:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(296, 13, '2026-10-09T10:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(297, 14, '2026-10-09T13:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(298, 15, '2026-10-11T04:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(299, 16, '2026-10-11T07:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(300, 17, '2026-10-12T05:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(301, 18, '2026-10-12T08:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(302, 19, '2026-10-14T06:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(303, 20, '2026-10-14T11:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(304, 21, '2026-10-16T09:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(305, 22, '2026-10-16T12:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(306, 23, '2026-10-17T10:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(307, 24, '2026-10-17T13:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(308, 25, '2026-10-19T11:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(309, 26, '2026-10-19T13:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(310, 27, '2026-10-20T05:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(311, 28, '2026-10-21T05:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(312, 29, '2026-10-21T08:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(313, 30, '2026-10-22T06:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(314, 31, '2026-10-23T06:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(315, 32, '2026-10-24T12:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(316, 33, '2026-10-26T10:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(317, 34, '2026-10-26T11:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(318, 35, '2026-10-26T13:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(319, 36, '2026-10-27T02:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(320, 37, '2026-10-28T05:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(321, 38, '2026-10-28T12:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(322, 39, '2026-10-30T06:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(323, 40, '2026-10-30T09:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(324, 41, '2026-10-31T07:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(325, 42, '2026-11-01T08:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(326, 43, '2026-11-01T13:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(327, 44, '2026-11-03T02:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(328, 45, '2026-11-03T11:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(329, 46, '2026-11-03T12:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(330, 47, '2026-11-04T12:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(331, 48, '2026-11-05T06:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(332, 49, '2026-11-05T13:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(333, 50, '2026-11-06T07:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(334, 51, '2026-11-07T05:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(335, 52, '2026-11-08T02:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(336, 53, '2026-11-08T08:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(337, 54, '2026-11-08T09:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(338, 55, '2026-11-09T12:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(339, 56, '2026-11-10T03:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(340, 57, '2026-11-10T13:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(341, 58, '2026-11-11T02:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(342, 59, '2026-11-11T07:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(343, 60, '2026-11-11T13:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(344, 61, '2026-11-12T05:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(345, 62, '2026-11-13T02:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(346, 63, '2026-11-13T06:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(347, 64, '2026-11-14T03:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(348, 65, '2026-11-14T09:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(349, 66, '2026-11-15T02:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(350, 67, '2026-11-15T04:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(351, 68, '2026-11-15T13:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(352, 69, '2026-11-16T02:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(353, 70, '2026-11-16T03:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(354, 71, '2026-11-16T08:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(355, 72, '2026-11-17T06:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(356, 73, '2026-11-17T07:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(357, 74, '2026-11-17T09:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(358, 75, '2026-11-18T03:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(359, 76, '2026-11-18T04:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(360, 77, '2026-11-18T13:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(361, 78, '2026-11-19T02:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(362, 79, '2026-11-19T03:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(363, 80, '2026-11-19T05:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(364, 81, '2026-11-19T08:00:00.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(365, 97, '2026-11-20T14:17:41.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(366, 98, '2026-11-20T14:17:41.0000000', 'delivered', N'Giao hàng thành công', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(367, 86, '2026-11-20T14:17:41.0000000', 'failed', N'Khách không nghe máy, hẹn giao lại', NULL, NULL, '2026-11-20T15:17:41.1480000'),
(368, 99, '2026-11-20T14:17:41.0000000', 'failed', N'Khách không nghe máy, hẹn giao lại', NULL, NULL, '2026-11-20T15:17:41.1480000')
;
SET IDENTITY_INSERT [lgs].[ShipmentTrackingEvents] OFF;
GO

-- md.Brands (5 dòng)
SET IDENTITY_INSERT [md].[Brands] ON;
INSERT INTO [md].[Brands] ([Id], [CompanyId], [Name]) VALUES
(4, 1, N'Denim Co'),
(3, 1, N'Elegant'),
(1, 1, N'MyStyle'),
(5, 1, N'Stepup'),
(2, 1, N'Urban')
;
SET IDENTITY_INSERT [md].[Brands] OFF;
GO

-- md.Currencies (4 dòng)
INSERT INTO [md].[Currencies] ([Code], [Name], [Symbol], [DecimalPlaces], [IsActive]) VALUES
('CNY', N'Nhân dân tệ', N'¥', 2, 1),
('EUR', N'Euro', N'€', 2, 1),
('USD', N'Đô la Mỹ', N'$', 2, 1),
('VND', N'Việt Nam đồng', N'₫', 0, 1)
;
GO

-- md.PartnerContacts (11 dòng)
SET IDENTITY_INSERT [md].[PartnerContacts] ON;
INSERT INTO [md].[PartnerContacts] ([Id], [PartnerId], [FullName], [Position], [Department], [Phone], [Email], [Birthday], [IsPrimary], [Note], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(15, 17, N'Trần Thị Bình', N'Giám đốc mua hàng', NULL, '0912345678', 'binh.tran@hungthinh.vn', NULL, 1, NULL, '2026-10-11T08:54:25.7940000', 1, NULL, NULL, 0),
(16, 18, N'Lê Văn Cường', N'CTO', NULL, '0903111222', 'cuong@daiviet.tech', NULL, 1, NULL, '2026-10-15T08:54:25.7940000', 1, NULL, NULL, 0),
(17, 19, N'Nguyễn Thu Hà', N'Kế toán trưởng', NULL, '0977222333', 'ha.nguyen@ankhang.vn', NULL, 1, NULL, '2026-10-22T08:54:25.7940000', 1, NULL, NULL, 0),
(18, 20, N'Đặng Văn Long', N'Giám đốc', NULL, '0947111000', 'long.dang@longphat.vn', NULL, 1, NULL, '2026-11-13T08:54:25.7940000', 1, NULL, NULL, 0),
(19, 21, N'Hồ Văn Nam', N'Trưởng phòng mua hàng', NULL, '0915666777', 'nam.ho@thepvietnhat.vn', NULL, 1, NULL, '2026-10-26T08:54:25.7940000', 1, NULL, NULL, 0),
(20, 22, N'Kim Thị Oanh', N'Quản lý chuỗi', NULL, '0938777888', 'oanh@minimart24h.vn', NULL, 1, NULL, '2026-10-18T08:54:25.7940000', 1, NULL, NULL, 0),
(21, 24, N'Trương Văn Sơn', N'Chủ nhà hàng', NULL, '0904555666', NULL, NULL, 1, NULL, '2026-11-02T08:54:25.7940000', 1, NULL, NULL, 0),
(22, 25, N'Lê Thị Thu', NULL, NULL, '0908111222', NULL, NULL, 1, NULL, '2026-09-16T09:42:54.7200000', 1, NULL, NULL, 0),
(23, 26, N'Trần Văn Hậu', NULL, NULL, '0909222333', NULL, NULL, 1, NULL, '2026-09-16T09:42:54.7200000', 1, NULL, NULL, 0),
(24, 27, N'Phạm Quốc Vũ', NULL, NULL, '0918333444', NULL, NULL, 1, NULL, '2026-09-16T09:42:54.7200000', 1, NULL, NULL, 0),
(25, 28, N'Ngô Mỹ Dung', NULL, NULL, '0937444555', NULL, NULL, 1, NULL, '2026-09-16T09:42:54.7200000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [md].[PartnerContacts] OFF;
GO

-- md.PartnerGroups (6 dòng)
SET IDENTITY_INSERT [md].[PartnerGroups] ON;
INSERT INTO [md].[PartnerGroups] ([Id], [CompanyId], [Code], [Name], [GroupType]) VALUES
(1, 1, 'RETAIL', N'Khách lẻ', 'customer'),
(2, 1, 'B2B', N'Khách doanh nghiệp', 'customer'),
(3, 1, 'DEALER', N'Đại lý', 'customer'),
(4, 1, 'VIP', N'Khách VIP', 'customer'),
(5, 1, 'SUP_DOM', N'Nhà cung cấp trong nước', 'supplier'),
(6, 1, 'SUP_IMP', N'Nhà cung cấp nhập khẩu', 'supplier')
;
SET IDENTITY_INSERT [md].[PartnerGroups] OFF;
GO

-- md.Partners (25 dòng)
SET IDENTITY_INSERT [md].[Partners] ON;
INSERT INTO [md].[Partners] ([Id], [CompanyId], [Code], [PartnerType], [Name], [ShortName], [TaxCode], [Phone], [Email], [Website], [Industry], [Street], [WardCode], [ProvinceCode], [IsCustomer], [IsSupplier], [IsCarrier], [CustomerGroupId], [SupplierGroupId], [PaymentTermId], [PriceListId], [CreditLimit], [CurrencyCode], [OwnerUserId], [DepartmentId], [Source], [Note], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(17, 1, 'KH-000001', 'company', N'Công ty Cổ phần Hưng Thịnh', N'Hưng Thịnh', '0101234567', '02438251111', 'info@hungthinh.vn', NULL, N'Phân phối', N'25 Lý Thường Kiệt, Hà Nội', NULL, NULL, 1, 0, 0, 2, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-11T08:54:25.7940000', 1, NULL, NULL, 0),
(18, 1, 'KH-000002', 'company', N'Công ty TNHH Đại Việt Tech', N'Đại Việt', '0108765432', '02437772222', 'contact@daiviet.tech', NULL, N'Công nghệ', N'Tòa Keangnam, Phạm Hùng, Hà Nội', NULL, NULL, 1, 0, 0, 4, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-15T08:54:25.7940000', 1, NULL, NULL, 0),
(19, 1, 'KH-000003', 'company', N'Công ty CP Dược phẩm An Khang', N'An Khang', '0312345678', '02838223333', 'info@ankhang.vn', NULL, N'Dược phẩm', N'120 Nguyễn Trãi, Q.5, TP.HCM', NULL, NULL, 1, 0, 0, 2, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-22T08:54:25.7940000', 1, NULL, NULL, 0),
(20, 1, 'KH-000004', 'company', N'Công ty TNHH Xây dựng Long Phát', N'Long Phát', '0109876543', '02436664444', 'info@longphat.vn', NULL, N'Xây dựng', N'88 Giải Phóng, Hà Nội', NULL, NULL, 1, 0, 0, 4, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-11-13T08:54:25.7940000', 1, NULL, NULL, 0),
(21, 1, 'KH-000005', 'company', N'Công ty TNHH Thép Việt Nhật', N'Thép Việt Nhật', '0201112223', '02253885555', 'sales@thepvietnhat.vn', NULL, N'Sản xuất', N'KCN Đình Vũ, Hải Phòng', NULL, NULL, 1, 0, 0, 2, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-26T08:54:25.7940000', 1, NULL, NULL, 0),
(22, 1, 'KH-000006', 'company', N'Chuỗi Mini Mart 24h', N'Mini Mart 24h', NULL, '02866667777', 'cskh@minimart24h.vn', NULL, N'Bán lẻ', N'45 Cộng Hòa, Tân Bình, TP.HCM', NULL, NULL, 1, 0, 0, 3, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-18T08:54:25.7940000', 1, NULL, NULL, 0),
(23, 1, 'KH-000007', 'individual', N'Nguyễn Hoàng Phúc', NULL, NULL, '0986123456', 'phuc.nh@gmail.com', NULL, NULL, N'Cầu Giấy, Hà Nội', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-23T08:54:25.7940000', 1, NULL, NULL, 0),
(24, 1, 'KH-000008', 'company', N'Nhà hàng Hương Quê', N'Hương Quê', '0107778889', '02439998888', 'huongque@gmail.com', NULL, N'Nhà hàng', N'12 Trần Duy Hưng, Hà Nội', NULL, NULL, 1, 0, 0, 2, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-11-02T08:54:25.7940000', 1, NULL, NULL, 0),
(25, 1, 'NCC-0001', 'company', N'Xưởng may Thành Công', NULL, '0312223334', '02838110001', 'order@maythanhcong.vn', NULL, NULL, N'KCN Tân Bình, TP.HCM', NULL, NULL, 0, 1, 0, NULL, NULL, NULL, NULL, 0.00, 'VND', NULL, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-09-16T09:42:54.7200000', 1, NULL, NULL, 0),
(26, 1, 'NCC-0002', 'company', N'Công ty TNHH Dệt may Phương Nam', NULL, '0313334445', '02838220002', 'sales@detmaypn.vn', NULL, NULL, N'Q.12, TP.HCM', NULL, NULL, 0, 1, 0, NULL, NULL, NULL, NULL, 0.00, 'VND', NULL, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-09-16T09:42:54.7200000', 1, NULL, NULL, 0),
(27, 1, 'NCC-0003', 'company', N'Denim Việt', NULL, '0314445556', '02838330003', 'b2b@denimviet.vn', NULL, NULL, N'Thủ Đức, TP.HCM', NULL, NULL, 0, 1, 0, NULL, NULL, NULL, NULL, 0.00, 'VND', NULL, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-09-16T09:42:54.7200000', 1, NULL, NULL, 0),
(28, 1, 'NCC-0004', 'company', N'Giày da Bình Tiên Supply', NULL, '0315556667', '02838440004', 'wholesale@btsupply.vn', NULL, NULL, N'Q.6, TP.HCM', NULL, NULL, 0, 1, 0, NULL, NULL, NULL, NULL, 0.00, 'VND', NULL, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-09-16T09:42:54.7200000', 1, NULL, NULL, 0),
(29, 1, 'KHACHLE', 'individual', N'Khách lẻ', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1, 0, 0, NULL, NULL, NULL, NULL, 0.00, 'VND', NULL, NULL, NULL, N'Khách mua tại quầy không để lại thông tin', 1, '2026-09-16T09:42:54.7200000', 1, NULL, NULL, 0),
(30, 1, 'KH-000009', 'individual', N'Nguyễn Minh Anh', NULL, NULL, '0912001001', NULL, NULL, NULL, N'Đống Đa, Hà Nội', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-09-23T09:42:54.7200000', 1, NULL, NULL, 0),
(31, 1, 'KH-000010', 'individual', N'Trần Thu Trang', NULL, NULL, '0913002002', NULL, NULL, NULL, N'Q.3, TP.HCM', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-09-25T09:42:54.7200000', 1, NULL, NULL, 0),
(32, 1, 'KH-000011', 'individual', N'Lê Hoàng Nam', NULL, NULL, '0914003003', NULL, NULL, NULL, N'Hải Châu, Đà Nẵng', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-09-27T09:42:54.7200000', 1, NULL, NULL, 0),
(33, 1, 'KH-000012', 'individual', N'Phạm Ngọc Hân', NULL, NULL, '0915004004', NULL, NULL, NULL, N'Cầu Giấy, Hà Nội', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-09-29T09:42:54.7200000', 1, NULL, NULL, 0),
(34, 1, 'KH-000013', 'individual', N'Vũ Đức Thắng', NULL, NULL, '0916005005', NULL, NULL, NULL, N'Bình Thạnh, TP.HCM', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-01T09:42:54.7200000', 1, NULL, NULL, 0),
(35, 1, 'KH-000014', 'individual', N'Đỗ Thị Mai', NULL, NULL, '0917006006', NULL, NULL, NULL, N'Ninh Kiều, Cần Thơ', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-03T09:42:54.7200000', 1, NULL, NULL, 0),
(36, 1, 'KH-000015', 'individual', N'Hoàng Gia Bảo', NULL, NULL, '0918007007', NULL, NULL, NULL, N'Lê Chân, Hải Phòng', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-05T09:42:54.7200000', 1, NULL, NULL, 0),
(37, 1, 'KH-000016', 'individual', N'Bùi Khánh Linh', NULL, NULL, '0919008008', NULL, NULL, NULL, N'Q.7, TP.HCM', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-07T09:42:54.7200000', 1, NULL, NULL, 0),
(38, 1, 'KH-000017', 'individual', N'Đặng Quang Huy', NULL, NULL, '0981009009', NULL, NULL, NULL, N'Thanh Xuân, Hà Nội', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-09T09:42:54.7200000', 1, NULL, NULL, 0),
(39, 1, 'KH-000018', 'individual', N'Ngô Phương Thảo', NULL, NULL, '0982010010', NULL, NULL, NULL, N'Thủ Đức, TP.HCM', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-11T09:42:54.7200000', 1, NULL, NULL, 0),
(40, 1, 'KH-000019', 'individual', N'Dương Tuấn Kiệt', NULL, NULL, '0983011011', NULL, NULL, NULL, N'TP. Vinh, Nghệ An', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-13T09:42:54.7200000', 1, NULL, NULL, 0),
(41, 1, 'KH-000020', 'individual', N'Lý Bảo Ngọc', NULL, NULL, '0984012012', NULL, NULL, NULL, N'Biên Hòa, Đồng Nai', NULL, NULL, 1, 0, 0, 1, NULL, NULL, NULL, 0.00, 'VND', 1, NULL, N'Dữ liệu mẫu', NULL, 1, '2026-10-15T09:42:54.7200000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [md].[Partners] OFF;
GO

-- md.PaymentMethods (6 dòng)
INSERT INTO [md].[PaymentMethods] ([Code], [Name], [IsActive]) VALUES
('bank_transfer', N'Chuyển khoản', 1),
('card', N'Thẻ', 1),
('cash', N'Tiền mặt', 1),
('cod', N'Thu hộ (COD)', 1),
('ewallet', N'Ví điện tử', 1),
('offset', N'Bù trừ công nợ', 1)
;
GO

-- md.PaymentTerms (6 dòng)
SET IDENTITY_INSERT [md].[PaymentTerms] ON;
INSERT INTO [md].[PaymentTerms] ([Id], [CompanyId], [Code], [Name], [DueDays], [IsActive]) VALUES
(1, 1, 'NOW', N'Thanh toán ngay', 0, 1),
(2, 1, 'NET7', N'Công nợ 7 ngày', 7, 1),
(3, 1, 'NET15', N'Công nợ 15 ngày', 15, 1),
(4, 1, 'NET30', N'Công nợ 30 ngày', 30, 1),
(5, 1, 'NET45', N'Công nợ 45 ngày', 45, 1),
(6, 1, 'NET60', N'Công nợ 60 ngày', 60, 1)
;
SET IDENTITY_INSERT [md].[PaymentTerms] OFF;
GO

-- md.PriceLists (3 dòng)
SET IDENTITY_INSERT [md].[PriceLists] ON;
INSERT INTO [md].[PriceLists] ([Id], [CompanyId], [Code], [Name], [CurrencyCode], [ValidFrom], [ValidTo], [IsDefault], [IsActive]) VALUES
(1, 1, 'RETAIL', N'Giá bán lẻ', 'VND', NULL, NULL, 1, 1),
(2, 1, 'WHOLESALE', N'Giá bán buôn', 'VND', NULL, NULL, 0, 1),
(3, 1, 'DEALER', N'Giá đại lý', 'VND', NULL, NULL, 0, 1)
;
SET IDENTITY_INSERT [md].[PriceLists] OFF;
GO

-- md.ProductCategories (13 dòng)
SET IDENTITY_INSERT [md].[ProductCategories] ON;
INSERT INTO [md].[ProductCategories] ([Id], [CompanyId], [ParentId], [Code], [Name], [Path], [SortOrder], [IsActive], [RevenueAccountId], [CogsAccountId], [InventoryAccountId]) VALUES
(1, 1, NULL, 'AOTHUN', N'Áo thun', NULL, 10, 1, NULL, NULL, NULL),
(2, 1, NULL, 'SOMI', N'Áo sơ mi', NULL, 20, 1, NULL, NULL, NULL),
(3, 1, NULL, 'JEANS', N'Quần jeans', NULL, 30, 1, NULL, NULL, NULL),
(4, 1, NULL, 'KAKI', N'Quần kaki', NULL, 40, 1, NULL, NULL, NULL),
(5, 1, NULL, 'SHORT', N'Quần short', NULL, 50, 1, NULL, NULL, NULL),
(6, 1, NULL, 'VAY', N'Váy đầm', NULL, 60, 1, NULL, NULL, NULL),
(7, 1, NULL, 'KHOAC', N'Áo khoác', NULL, 70, 1, NULL, NULL, NULL),
(8, 1, NULL, 'SNEAKER', N'Giày sneaker', NULL, 80, 1, NULL, NULL, NULL),
(9, 1, NULL, 'GIAYNU', N'Giày nữ', NULL, 90, 1, NULL, NULL, NULL),
(10, 1, NULL, 'GIAYNAM', N'Giày nam', NULL, 100, 1, NULL, NULL, NULL),
(11, 1, NULL, 'DEP', N'Dép sandal', NULL, 110, 1, NULL, NULL, NULL),
(12, 1, NULL, 'TUI', N'Túi xách', NULL, 120, 1, NULL, NULL, NULL),
(13, 1, NULL, 'PHUKIEN', N'Phụ kiện', NULL, 130, 1, NULL, NULL, NULL)
;
SET IDENTITY_INSERT [md].[ProductCategories] OFF;
GO

-- md.ProductModels (20 dòng)
SET IDENTITY_INSERT [md].[ProductModels] ON;
INSERT INTO [md].[ProductModels] ([Id], [CompanyId], [Code], [Name], [CategoryId], [BrandId], [UomId], [SalePrice], [CostPrice], [Gender], [Material], [Season], [Description], [ImageUrl], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'ATB01', N'Áo thun basic cổ tròn', 1, 1, 1, 159000.0000, 65000.0000, 'unisex', N'Cotton 100%', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(2, 1, 'ATP02', N'Áo polo pique', 1, 1, 1, 249000.0000, 105000.0000, 'men', N'Cotton pique', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(3, 1, 'ATO03', N'Áo thun oversize in chữ', 1, 2, 1, 199000.0000, 80000.0000, 'unisex', N'Cotton 2 chiều', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(4, 1, 'ASM04', N'Áo sơ mi trắng công sở', 2, 3, 1, 329000.0000, 140000.0000, 'men', N'Kate lụa', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(5, 1, 'ASN05', N'Áo sơ mi nữ lụa', 2, 3, 1, 359000.0000, 150000.0000, 'women', N'Lụa tơ tằm', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(6, 1, 'QJS06', N'Quần jeans slim fit', 3, 4, 1, 459000.0000, 200000.0000, 'men', N'Denim co giãn', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(7, 1, 'QJN07', N'Quần jeans nữ ống rộng', 3, 4, 1, 429000.0000, 185000.0000, 'women', N'Denim', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(8, 1, 'QKK08', N'Quần kaki chinos', 4, 1, 1, 389000.0000, 165000.0000, 'men', N'Kaki co giãn', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(9, 1, 'QSO09', N'Quần short thể thao', 5, 2, 1, 179000.0000, 70000.0000, 'unisex', N'Thun lạnh', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(10, 1, 'VDM10', N'Váy đầm hoa nhí', 6, 3, 1, 399000.0000, 160000.0000, 'women', N'Voan 2 lớp', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(11, 1, 'VCS11', N'Chân váy chữ A', 6, 3, 1, 279000.0000, 110000.0000, 'women', N'Tuyết mưa', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(12, 1, 'AKB12', N'Áo khoác bomber', 7, 2, 1, 599000.0000, 260000.0000, 'unisex', N'Dù 2 lớp', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(13, 1, 'AKG13', N'Áo khoác gió chống nắng', 7, 1, 1, 299000.0000, 120000.0000, 'women', N'Vải dù chống UV', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(14, 1, 'GSN14', N'Giày sneaker trắng', 8, 5, 21, 690000.0000, 310000.0000, 'unisex', N'Da tổng hợp', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(15, 1, 'GCG15', N'Giày cao gót mũi nhọn', 9, 5, 21, 520000.0000, 220000.0000, 'women', N'Da PU', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(16, 1, 'GTL16', N'Giày tây da bò', 10, 5, 21, 990000.0000, 450000.0000, 'men', N'Da bò thật', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(17, 1, 'DSD17', N'Dép sandal quai ngang', 11, 5, 21, 249000.0000, 95000.0000, 'unisex', N'Cao su EVA', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(18, 1, 'TXK18', N'Túi xách nữ đeo chéo', 12, 3, 1, 459000.0000, 190000.0000, 'women', N'Da PU cao cấp', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(19, 1, 'MLT19', N'Mũ lưỡi trai', 13, 2, 1, 129000.0000, 45000.0000, 'unisex', N'Kaki', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0),
(20, 1, 'TAT20', N'Tất cổ ngắn (combo 3 đôi)', 13, 1, 12, 79000.0000, 28000.0000, 'unisex', N'Cotton', N'Thu đông 2026', NULL, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [md].[ProductModels] OFF;
GO

-- md.Products (168 dòng)
SET IDENTITY_INSERT [md].[Products] ON;
INSERT INTO [md].[Products] ([Id], [CompanyId], [Code], [Barcode], [Name], [ProductType], [CategoryId], [BrandId], [UomId], [PurchaseUomId], [SalePrice], [CostPrice], [CostMethod], [SaleTaxId], [PurchaseTaxId], [IsSellable], [IsPurchasable], [IsStockTracked], [TrackingType], [MinStock], [MaxStock], [WarrantyMonths], [WeightGram], [LengthCm], [WidthCm], [HeightCm], [ImageUrl], [Description], [IsPublishedWeb], [WebSlug], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted], [ModelId], [Color], [Size]) VALUES
(1, 1, 'ATO03-BE-M', NULL, N'Áo thun oversize in chữ - Be - M', 'goods', 1, 2, 1, NULL, 199000.0000, 80000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'ato03-be-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 3, N'Be', 'M'),
(2, 1, 'ATO03-BE-L', NULL, N'Áo thun oversize in chữ - Be - L', 'goods', 1, 2, 1, NULL, 199000.0000, 80000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'ato03-be-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 3, N'Be', 'L'),
(3, 1, 'ATO03-BE-XL', NULL, N'Áo thun oversize in chữ - Be - XL', 'goods', 1, 2, 1, NULL, 199000.0000, 80000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'ato03-be-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 3, N'Be', 'XL'),
(4, 1, 'ASN05-BE-S', NULL, N'Áo sơ mi nữ lụa - Be - S', 'goods', 2, 3, 1, NULL, 359000.0000, 150000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asn05-be-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 5, N'Be', 'S'),
(5, 1, 'ASN05-BE-M', NULL, N'Áo sơ mi nữ lụa - Be - M', 'goods', 2, 3, 1, NULL, 359000.0000, 150000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asn05-be-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 5, N'Be', 'M'),
(6, 1, 'ASN05-BE-L', NULL, N'Áo sơ mi nữ lụa - Be - L', 'goods', 2, 3, 1, NULL, 359000.0000, 150000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asn05-be-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 5, N'Be', 'L'),
(7, 1, 'QKK08-BE-29', NULL, N'Quần kaki chinos - Be - 29', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Be', '29'),
(8, 1, 'QKK08-BE-30', NULL, N'Quần kaki chinos - Be - 30', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Be', '30'),
(9, 1, 'QKK08-BE-31', NULL, N'Quần kaki chinos - Be - 31', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Be', '31'),
(10, 1, 'QKK08-BE-32', NULL, N'Quần kaki chinos - Be - 32', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Be', '32'),
(11, 1, 'VCS11-BE-S', NULL, N'Chân váy chữ A - Be - S', 'goods', 6, 3, 1, NULL, 279000.0000, 110000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vcs11-be-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 11, N'Be', 'S'),
(12, 1, 'VCS11-BE-M', NULL, N'Chân váy chữ A - Be - M', 'goods', 6, 3, 1, NULL, 279000.0000, 110000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vcs11-be-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 11, N'Be', 'M'),
(13, 1, 'VCS11-BE-L', NULL, N'Chân váy chữ A - Be - L', 'goods', 6, 3, 1, NULL, 279000.0000, 110000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vcs11-be-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 11, N'Be', 'L'),
(14, 1, 'DSD17-BE-37', NULL, N'Dép sandal quai ngang - Be - 37', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-be-37', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Be', '37'),
(15, 1, 'DSD17-BE-38', NULL, N'Dép sandal quai ngang - Be - 38', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-be-38', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Be', '38'),
(16, 1, 'DSD17-BE-39', NULL, N'Dép sandal quai ngang - Be - 39', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-be-39', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Be', '39'),
(17, 1, 'DSD17-BE-40', NULL, N'Dép sandal quai ngang - Be - 40', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-be-40', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Be', '40'),
(18, 1, 'DSD17-BE-41', NULL, N'Dép sandal quai ngang - Be - 41', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-be-41', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Be', '41'),
(19, 1, 'DSD17-BE-42', NULL, N'Dép sandal quai ngang - Be - 42', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-be-42', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Be', '42'),
(20, 1, 'GCG15-BE-35', NULL, N'Giày cao gót mũi nhọn - Be - 35', 'goods', 9, 5, 21, NULL, 520000.0000, 220000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gcg15-be-35', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 15, N'Be', '35'),
(21, 1, 'GCG15-BE-36', NULL, N'Giày cao gót mũi nhọn - Be - 36', 'goods', 9, 5, 21, NULL, 520000.0000, 220000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gcg15-be-36', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 15, N'Be', '36'),
(22, 1, 'GCG15-BE-37', NULL, N'Giày cao gót mũi nhọn - Be - 37', 'goods', 9, 5, 21, NULL, 520000.0000, 220000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gcg15-be-37', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 15, N'Be', '37'),
(23, 1, 'GCG15-BE-38', NULL, N'Giày cao gót mũi nhọn - Be - 38', 'goods', 9, 5, 21, NULL, 520000.0000, 220000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gcg15-be-38', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 15, N'Be', '38'),
(24, 1, 'GCG15-BE-39', NULL, N'Giày cao gót mũi nhọn - Be - 39', 'goods', 9, 5, 21, NULL, 520000.0000, 220000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gcg15-be-39', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 15, N'Be', '39'),
(25, 1, 'MLT19-BE-FREESIZE', NULL, N'Mũ lưỡi trai - Be - Free size', 'goods', 13, 2, 1, NULL, 129000.0000, 45000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 19, N'Be', 'Free size'),
(26, 1, 'TAT20-DEN-FREESIZE', NULL, N'Tất cổ ngắn (combo 3 đôi) - Đen - Free size', 'goods', 13, 1, 12, NULL, 79000.0000, 28000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 20, N'Đen', 'Free size'),
(27, 1, 'GTL16-DEN-39', NULL, N'Giày tây da bò - Đen - 39', 'goods', 10, 5, 21, NULL, 990000.0000, 450000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 16, N'Đen', '39'),
(28, 1, 'GTL16-DEN-40', NULL, N'Giày tây da bò - Đen - 40', 'goods', 10, 5, 21, NULL, 990000.0000, 450000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 16, N'Đen', '40'),
(29, 1, 'GTL16-DEN-41', NULL, N'Giày tây da bò - Đen - 41', 'goods', 10, 5, 21, NULL, 990000.0000, 450000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 16, N'Đen', '41'),
(30, 1, 'GTL16-DEN-42', NULL, N'Giày tây da bò - Đen - 42', 'goods', 10, 5, 21, NULL, 990000.0000, 450000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 16, N'Đen', '42'),
(31, 1, 'GTL16-DEN-43', NULL, N'Giày tây da bò - Đen - 43', 'goods', 10, 5, 21, NULL, 990000.0000, 450000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 16, N'Đen', '43'),
(32, 1, 'DSD17-DEN-37', NULL, N'Dép sandal quai ngang - Đen - 37', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-den-37', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Đen', '37'),
(33, 1, 'DSD17-DEN-38', NULL, N'Dép sandal quai ngang - Đen - 38', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-den-38', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Đen', '38'),
(34, 1, 'DSD17-DEN-39', NULL, N'Dép sandal quai ngang - Đen - 39', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-den-39', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Đen', '39'),
(35, 1, 'DSD17-DEN-40', NULL, N'Dép sandal quai ngang - Đen - 40', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-den-40', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Đen', '40'),
(36, 1, 'DSD17-DEN-41', NULL, N'Dép sandal quai ngang - Đen - 41', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-den-41', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Đen', '41'),
(37, 1, 'DSD17-DEN-42', NULL, N'Dép sandal quai ngang - Đen - 42', 'goods', 11, 5, 21, NULL, 249000.0000, 95000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'dsd17-den-42', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 17, N'Đen', '42'),
(38, 1, 'MLT19-DEN-FREESIZE', NULL, N'Mũ lưỡi trai - Đen - Free size', 'goods', 13, 2, 1, NULL, 129000.0000, 45000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 19, N'Đen', 'Free size'),
(39, 1, 'TXK18-DEN', NULL, N'Túi xách nữ đeo chéo - Đen', 'goods', 12, 3, 1, NULL, 459000.0000, 190000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'txk18-den', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 18, N'Đen', NULL),
(40, 1, 'AKB12-DEN-M', NULL, N'Áo khoác bomber - Đen - M', 'goods', 7, 2, 1, NULL, 599000.0000, 260000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'akb12-den-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 12, N'Đen', 'M'),
(41, 1, 'AKB12-DEN-L', NULL, N'Áo khoác bomber - Đen - L', 'goods', 7, 2, 1, NULL, 599000.0000, 260000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'akb12-den-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 12, N'Đen', 'L'),
(42, 1, 'AKB12-DEN-XL', NULL, N'Áo khoác bomber - Đen - XL', 'goods', 7, 2, 1, NULL, 599000.0000, 260000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'akb12-den-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 12, N'Đen', 'XL'),
(43, 1, 'VCS11-DEN-S', NULL, N'Chân váy chữ A - Đen - S', 'goods', 6, 3, 1, NULL, 279000.0000, 110000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vcs11-den-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 11, N'Đen', 'S'),
(44, 1, 'VCS11-DEN-M', NULL, N'Chân váy chữ A - Đen - M', 'goods', 6, 3, 1, NULL, 279000.0000, 110000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vcs11-den-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 11, N'Đen', 'M'),
(45, 1, 'VCS11-DEN-L', NULL, N'Chân váy chữ A - Đen - L', 'goods', 6, 3, 1, NULL, 279000.0000, 110000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vcs11-den-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 11, N'Đen', 'L'),
(46, 1, 'GSN14-DEN-36', NULL, N'Giày sneaker trắng - Đen - 36', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-den-36', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Đen', '36'),
(47, 1, 'GSN14-DEN-37', NULL, N'Giày sneaker trắng - Đen - 37', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-den-37', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Đen', '37'),
(48, 1, 'GSN14-DEN-38', NULL, N'Giày sneaker trắng - Đen - 38', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-den-38', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Đen', '38'),
(49, 1, 'GSN14-DEN-39', NULL, N'Giày sneaker trắng - Đen - 39', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-den-39', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Đen', '39'),
(50, 1, 'GSN14-DEN-40', NULL, N'Giày sneaker trắng - Đen - 40', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-den-40', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Đen', '40'),
(51, 1, 'GSN14-DEN-41', NULL, N'Giày sneaker trắng - Đen - 41', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-den-41', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Đen', '41'),
(52, 1, 'GSN14-DEN-42', NULL, N'Giày sneaker trắng - Đen - 42', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-den-42', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Đen', '42'),
(53, 1, 'GSN14-DEN-43', NULL, N'Giày sneaker trắng - Đen - 43', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-den-43', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Đen', '43'),
(54, 1, 'GCG15-DEN-35', NULL, N'Giày cao gót mũi nhọn - Đen - 35', 'goods', 9, 5, 21, NULL, 520000.0000, 220000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gcg15-den-35', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 15, N'Đen', '35'),
(55, 1, 'GCG15-DEN-36', NULL, N'Giày cao gót mũi nhọn - Đen - 36', 'goods', 9, 5, 21, NULL, 520000.0000, 220000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gcg15-den-36', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 15, N'Đen', '36'),
(56, 1, 'GCG15-DEN-37', NULL, N'Giày cao gót mũi nhọn - Đen - 37', 'goods', 9, 5, 21, NULL, 520000.0000, 220000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gcg15-den-37', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 15, N'Đen', '37'),
(57, 1, 'GCG15-DEN-38', NULL, N'Giày cao gót mũi nhọn - Đen - 38', 'goods', 9, 5, 21, NULL, 520000.0000, 220000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gcg15-den-38', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 15, N'Đen', '38'),
(58, 1, 'GCG15-DEN-39', NULL, N'Giày cao gót mũi nhọn - Đen - 39', 'goods', 9, 5, 21, NULL, 520000.0000, 220000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gcg15-den-39', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 15, N'Đen', '39'),
(59, 1, 'QKK08-DEN-29', NULL, N'Quần kaki chinos - Đen - 29', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Đen', '29'),
(60, 1, 'QKK08-DEN-30', NULL, N'Quần kaki chinos - Đen - 30', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Đen', '30'),
(61, 1, 'QKK08-DEN-31', NULL, N'Quần kaki chinos - Đen - 31', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Đen', '31'),
(62, 1, 'QKK08-DEN-32', NULL, N'Quần kaki chinos - Đen - 32', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Đen', '32'),
(63, 1, 'QJN07-DEN-S', NULL, N'Quần jeans nữ ống rộng - Đen - S', 'goods', 3, 4, 1, NULL, 429000.0000, 185000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjn07-den-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 7, N'Đen', 'S'),
(64, 1, 'QJN07-DEN-M', NULL, N'Quần jeans nữ ống rộng - Đen - M', 'goods', 3, 4, 1, NULL, 429000.0000, 185000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjn07-den-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 7, N'Đen', 'M'),
(65, 1, 'QJN07-DEN-L', NULL, N'Quần jeans nữ ống rộng - Đen - L', 'goods', 3, 4, 1, NULL, 429000.0000, 185000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjn07-den-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 7, N'Đen', 'L'),
(66, 1, 'QSO09-DEN-M', NULL, N'Quần short thể thao - Đen - M', 'goods', 5, 2, 1, NULL, 179000.0000, 70000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 9, N'Đen', 'M'),
(67, 1, 'QSO09-DEN-L', NULL, N'Quần short thể thao - Đen - L', 'goods', 5, 2, 1, NULL, 179000.0000, 70000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 9, N'Đen', 'L'),
(68, 1, 'QSO09-DEN-XL', NULL, N'Quần short thể thao - Đen - XL', 'goods', 5, 2, 1, NULL, 179000.0000, 70000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 9, N'Đen', 'XL'),
(69, 1, 'QJS06-DEN-29', NULL, N'Quần jeans slim fit - Đen - 29', 'goods', 3, 4, 1, NULL, 459000.0000, 200000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjs06-den-29', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 6, N'Đen', '29'),
(70, 1, 'QJS06-DEN-30', NULL, N'Quần jeans slim fit - Đen - 30', 'goods', 3, 4, 1, NULL, 459000.0000, 200000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjs06-den-30', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 6, N'Đen', '30'),
(71, 1, 'QJS06-DEN-31', NULL, N'Quần jeans slim fit - Đen - 31', 'goods', 3, 4, 1, NULL, 459000.0000, 200000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjs06-den-31', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 6, N'Đen', '31'),
(72, 1, 'QJS06-DEN-32', NULL, N'Quần jeans slim fit - Đen - 32', 'goods', 3, 4, 1, NULL, 459000.0000, 200000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjs06-den-32', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 6, N'Đen', '32'),
(73, 1, 'QJS06-DEN-34', NULL, N'Quần jeans slim fit - Đen - 34', 'goods', 3, 4, 1, NULL, 459000.0000, 200000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjs06-den-34', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 6, N'Đen', '34'),
(74, 1, 'ATB01-DEN-S', NULL, N'Áo thun basic cổ tròn - Đen - S', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-den-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Đen', 'S'),
(75, 1, 'ATB01-DEN-M', NULL, N'Áo thun basic cổ tròn - Đen - M', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-den-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Đen', 'M'),
(76, 1, 'ATB01-DEN-L', NULL, N'Áo thun basic cổ tròn - Đen - L', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-den-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Đen', 'L'),
(77, 1, 'ATB01-DEN-XL', NULL, N'Áo thun basic cổ tròn - Đen - XL', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-den-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Đen', 'XL'),
(78, 1, 'ATP02-DEN-M', NULL, N'Áo polo pique - Đen - M', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-den-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Đen', 'M'),
(79, 1, 'ATP02-DEN-L', NULL, N'Áo polo pique - Đen - L', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-den-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Đen', 'L'),
(80, 1, 'ATP02-DEN-XL', NULL, N'Áo polo pique - Đen - XL', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-den-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Đen', 'XL'),
(81, 1, 'ATP02-DEN-XXL', NULL, N'Áo polo pique - Đen - XXL', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-den-xxl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Đen', 'XXL'),
(82, 1, 'ATO03-DEN-M', NULL, N'Áo thun oversize in chữ - Đen - M', 'goods', 1, 2, 1, NULL, 199000.0000, 80000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'ato03-den-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 3, N'Đen', 'M'),
(83, 1, 'ATO03-DEN-L', NULL, N'Áo thun oversize in chữ - Đen - L', 'goods', 1, 2, 1, NULL, 199000.0000, 80000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'ato03-den-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 3, N'Đen', 'L'),
(84, 1, 'ATO03-DEN-XL', NULL, N'Áo thun oversize in chữ - Đen - XL', 'goods', 1, 2, 1, NULL, 199000.0000, 80000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'ato03-den-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 3, N'Đen', 'XL'),
(85, 1, 'VDM10-HONG-S', NULL, N'Váy đầm hoa nhí - Hồng - S', 'goods', 6, 3, 1, NULL, 399000.0000, 160000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vdm10-hong-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 10, N'Hồng', 'S'),
(86, 1, 'VDM10-HONG-M', NULL, N'Váy đầm hoa nhí - Hồng - M', 'goods', 6, 3, 1, NULL, 399000.0000, 160000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vdm10-hong-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 10, N'Hồng', 'M'),
(87, 1, 'VDM10-HONG-L', NULL, N'Váy đầm hoa nhí - Hồng - L', 'goods', 6, 3, 1, NULL, 399000.0000, 160000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vdm10-hong-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 10, N'Hồng', 'L'),
(88, 1, 'ASN05-HONG-S', NULL, N'Áo sơ mi nữ lụa - Hồng - S', 'goods', 2, 3, 1, NULL, 359000.0000, 150000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asn05-hong-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 5, N'Hồng', 'S'),
(89, 1, 'ASN05-HONG-M', NULL, N'Áo sơ mi nữ lụa - Hồng - M', 'goods', 2, 3, 1, NULL, 359000.0000, 150000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asn05-hong-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 5, N'Hồng', 'M'),
(90, 1, 'ASN05-HONG-L', NULL, N'Áo sơ mi nữ lụa - Hồng - L', 'goods', 2, 3, 1, NULL, 359000.0000, 150000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asn05-hong-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 5, N'Hồng', 'L'),
(91, 1, 'AKG13-HONG-FREESIZE', NULL, N'Áo khoác gió chống nắng - Hồng - Free size', 'goods', 7, 1, 1, NULL, 299000.0000, 120000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'akg13-hong-freesize', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 13, N'Hồng', 'Free size'),
(92, 1, 'VDM10-KEM-S', NULL, N'Váy đầm hoa nhí - Kem - S', 'goods', 6, 3, 1, NULL, 399000.0000, 160000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vdm10-kem-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 10, N'Kem', 'S'),
(93, 1, 'VDM10-KEM-M', NULL, N'Váy đầm hoa nhí - Kem - M', 'goods', 6, 3, 1, NULL, 399000.0000, 160000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vdm10-kem-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 10, N'Kem', 'M'),
(94, 1, 'VDM10-KEM-L', NULL, N'Váy đầm hoa nhí - Kem - L', 'goods', 6, 3, 1, NULL, 399000.0000, 160000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vdm10-kem-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 10, N'Kem', 'L'),
(95, 1, 'TXK18-KEM', NULL, N'Túi xách nữ đeo chéo - Kem', 'goods', 12, 3, 1, NULL, 459000.0000, 190000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'txk18-kem', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 18, N'Kem', NULL),
(96, 1, 'TXK18-NAU', NULL, N'Túi xách nữ đeo chéo - Nâu', 'goods', 12, 3, 1, NULL, 459000.0000, 190000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'txk18-nau', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 18, N'Nâu', NULL),
(97, 1, 'GTL16-NAU-39', NULL, N'Giày tây da bò - Nâu - 39', 'goods', 10, 5, 21, NULL, 990000.0000, 450000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 16, N'Nâu', '39'),
(98, 1, 'GTL16-NAU-40', NULL, N'Giày tây da bò - Nâu - 40', 'goods', 10, 5, 21, NULL, 990000.0000, 450000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 16, N'Nâu', '40'),
(99, 1, 'GTL16-NAU-41', NULL, N'Giày tây da bò - Nâu - 41', 'goods', 10, 5, 21, NULL, 990000.0000, 450000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 16, N'Nâu', '41'),
(100, 1, 'GTL16-NAU-42', NULL, N'Giày tây da bò - Nâu - 42', 'goods', 10, 5, 21, NULL, 990000.0000, 450000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 16, N'Nâu', '42'),
(101, 1, 'GTL16-NAU-43', NULL, N'Giày tây da bò - Nâu - 43', 'goods', 10, 5, 21, NULL, 990000.0000, 450000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 16, N'Nâu', '43'),
(102, 1, 'TAT20-TRANG-FREESIZE', NULL, N'Tất cổ ngắn (combo 3 đôi) - Trắng - Free size', 'goods', 13, 1, 12, NULL, 79000.0000, 28000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 20, N'Trắng', 'Free size'),
(103, 1, 'AKG13-TRANG-FREESIZE', NULL, N'Áo khoác gió chống nắng - Trắng - Free size', 'goods', 7, 1, 1, NULL, 299000.0000, 120000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'akg13-trang-freesize', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 13, N'Trắng', 'Free size'),
(104, 1, 'GSN14-TRANG-36', NULL, N'Giày sneaker trắng - Trắng - 36', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-trang-36', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Trắng', '36'),
(105, 1, 'GSN14-TRANG-37', NULL, N'Giày sneaker trắng - Trắng - 37', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-trang-37', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Trắng', '37'),
(106, 1, 'GSN14-TRANG-38', NULL, N'Giày sneaker trắng - Trắng - 38', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-trang-38', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Trắng', '38'),
(107, 1, 'GSN14-TRANG-39', NULL, N'Giày sneaker trắng - Trắng - 39', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-trang-39', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Trắng', '39'),
(108, 1, 'GSN14-TRANG-40', NULL, N'Giày sneaker trắng - Trắng - 40', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-trang-40', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Trắng', '40'),
(109, 1, 'GSN14-TRANG-41', NULL, N'Giày sneaker trắng - Trắng - 41', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-trang-41', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Trắng', '41'),
(110, 1, 'GSN14-TRANG-42', NULL, N'Giày sneaker trắng - Trắng - 42', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-trang-42', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Trắng', '42'),
(111, 1, 'GSN14-TRANG-43', NULL, N'Giày sneaker trắng - Trắng - 43', 'goods', 8, 5, 21, NULL, 690000.0000, 310000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'gsn14-trang-43', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 14, N'Trắng', '43'),
(112, 1, 'ATO03-TRANG-M', NULL, N'Áo thun oversize in chữ - Trắng - M', 'goods', 1, 2, 1, NULL, 199000.0000, 80000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'ato03-trang-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 3, N'Trắng', 'M'),
(113, 1, 'ATO03-TRANG-L', NULL, N'Áo thun oversize in chữ - Trắng - L', 'goods', 1, 2, 1, NULL, 199000.0000, 80000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'ato03-trang-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 3, N'Trắng', 'L'),
(114, 1, 'ATO03-TRANG-XL', NULL, N'Áo thun oversize in chữ - Trắng - XL', 'goods', 1, 2, 1, NULL, 199000.0000, 80000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'ato03-trang-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 3, N'Trắng', 'XL'),
(115, 1, 'ATB01-TRANG-S', NULL, N'Áo thun basic cổ tròn - Trắng - S', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-trang-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Trắng', 'S'),
(116, 1, 'ATB01-TRANG-M', NULL, N'Áo thun basic cổ tròn - Trắng - M', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-trang-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Trắng', 'M'),
(117, 1, 'ATB01-TRANG-L', NULL, N'Áo thun basic cổ tròn - Trắng - L', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-trang-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Trắng', 'L'),
(118, 1, 'ATB01-TRANG-XL', NULL, N'Áo thun basic cổ tròn - Trắng - XL', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-trang-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Trắng', 'XL'),
(119, 1, 'ASM04-TRANG-S', NULL, N'Áo sơ mi trắng công sở - Trắng - S', 'goods', 2, 3, 1, NULL, 329000.0000, 140000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asm04-trang-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 4, N'Trắng', 'S'),
(120, 1, 'ASM04-TRANG-M', NULL, N'Áo sơ mi trắng công sở - Trắng - M', 'goods', 2, 3, 1, NULL, 329000.0000, 140000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asm04-trang-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 4, N'Trắng', 'M'),
(121, 1, 'ASM04-TRANG-L', NULL, N'Áo sơ mi trắng công sở - Trắng - L', 'goods', 2, 3, 1, NULL, 329000.0000, 140000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asm04-trang-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 4, N'Trắng', 'L'),
(122, 1, 'ASM04-TRANG-XL', NULL, N'Áo sơ mi trắng công sở - Trắng - XL', 'goods', 2, 3, 1, NULL, 329000.0000, 140000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asm04-trang-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 4, N'Trắng', 'XL'),
(123, 1, 'ATP02-TRANG-M', NULL, N'Áo polo pique - Trắng - M', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-trang-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Trắng', 'M'),
(124, 1, 'ATP02-TRANG-L', NULL, N'Áo polo pique - Trắng - L', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-trang-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Trắng', 'L'),
(125, 1, 'ATP02-TRANG-XL', NULL, N'Áo polo pique - Trắng - XL', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-trang-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Trắng', 'XL'),
(126, 1, 'ATP02-TRANG-XXL', NULL, N'Áo polo pique - Trắng - XXL', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-trang-xxl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Trắng', 'XXL'),
(127, 1, 'ASN05-TRANG-S', NULL, N'Áo sơ mi nữ lụa - Trắng - S', 'goods', 2, 3, 1, NULL, 359000.0000, 150000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asn05-trang-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 5, N'Trắng', 'S'),
(128, 1, 'ASN05-TRANG-M', NULL, N'Áo sơ mi nữ lụa - Trắng - M', 'goods', 2, 3, 1, NULL, 359000.0000, 150000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asn05-trang-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 5, N'Trắng', 'M'),
(129, 1, 'ASN05-TRANG-L', NULL, N'Áo sơ mi nữ lụa - Trắng - L', 'goods', 2, 3, 1, NULL, 359000.0000, 150000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asn05-trang-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 5, N'Trắng', 'L'),
(130, 1, 'ATB01-XAM-S', NULL, N'Áo thun basic cổ tròn - Xám - S', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-xam-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Xám', 'S'),
(131, 1, 'ATB01-XAM-M', NULL, N'Áo thun basic cổ tròn - Xám - M', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-xam-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Xám', 'M'),
(132, 1, 'ATB01-XAM-L', NULL, N'Áo thun basic cổ tròn - Xám - L', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-xam-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Xám', 'L'),
(133, 1, 'ATB01-XAM-XL', NULL, N'Áo thun basic cổ tròn - Xám - XL', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-xam-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Xám', 'XL'),
(134, 1, 'QSO09-XAM-M', NULL, N'Quần short thể thao - Xám - M', 'goods', 5, 2, 1, NULL, 179000.0000, 70000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 9, N'Xám', 'M'),
(135, 1, 'QSO09-XAM-L', NULL, N'Quần short thể thao - Xám - L', 'goods', 5, 2, 1, NULL, 179000.0000, 70000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 9, N'Xám', 'L'),
(136, 1, 'QSO09-XAM-XL', NULL, N'Quần short thể thao - Xám - XL', 'goods', 5, 2, 1, NULL, 179000.0000, 70000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 9, N'Xám', 'XL'),
(137, 1, 'VDM10-XANHDUON-S', NULL, N'Váy đầm hoa nhí - Xanh dương - S', 'goods', 6, 3, 1, NULL, 399000.0000, 160000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vdm10-xanhduon-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 10, N'Xanh dương', 'S'),
(138, 1, 'VDM10-XANHDUON-M', NULL, N'Váy đầm hoa nhí - Xanh dương - M', 'goods', 6, 3, 1, NULL, 399000.0000, 160000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vdm10-xanhduon-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 10, N'Xanh dương', 'M'),
(139, 1, 'VDM10-XANHDUON-L', NULL, N'Váy đầm hoa nhí - Xanh dương - L', 'goods', 6, 3, 1, NULL, 399000.0000, 160000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'vdm10-xanhduon-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 10, N'Xanh dương', 'L'),
(140, 1, 'AKG13-XANHDUON-FREESIZE', NULL, N'Áo khoác gió chống nắng - Xanh dương - Free size', 'goods', 7, 1, 1, NULL, 299000.0000, 120000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'akg13-xanhduon-freesize', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 13, N'Xanh dương', 'Free size'),
(141, 1, 'ASM04-XANHDUON-S', NULL, N'Áo sơ mi trắng công sở - Xanh dương - S', 'goods', 2, 3, 1, NULL, 329000.0000, 140000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asm04-xanhduon-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 4, N'Xanh dương', 'S'),
(142, 1, 'ASM04-XANHDUON-M', NULL, N'Áo sơ mi trắng công sở - Xanh dương - M', 'goods', 2, 3, 1, NULL, 329000.0000, 140000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asm04-xanhduon-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 4, N'Xanh dương', 'M'),
(143, 1, 'ASM04-XANHDUON-L', NULL, N'Áo sơ mi trắng công sở - Xanh dương - L', 'goods', 2, 3, 1, NULL, 329000.0000, 140000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asm04-xanhduon-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 4, N'Xanh dương', 'L'),
(144, 1, 'ASM04-XANHDUON-XL', NULL, N'Áo sơ mi trắng công sở - Xanh dương - XL', 'goods', 2, 3, 1, NULL, 329000.0000, 140000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'asm04-xanhduon-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 4, N'Xanh dương', 'XL'),
(145, 1, 'QJS06-XANHJEAN-29', NULL, N'Quần jeans slim fit - Xanh jean - 29', 'goods', 3, 4, 1, NULL, 459000.0000, 200000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjs06-xanhjean-29', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 6, N'Xanh jean', '29'),
(146, 1, 'QJS06-XANHJEAN-30', NULL, N'Quần jeans slim fit - Xanh jean - 30', 'goods', 3, 4, 1, NULL, 459000.0000, 200000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjs06-xanhjean-30', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 6, N'Xanh jean', '30'),
(147, 1, 'QJS06-XANHJEAN-31', NULL, N'Quần jeans slim fit - Xanh jean - 31', 'goods', 3, 4, 1, NULL, 459000.0000, 200000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjs06-xanhjean-31', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 6, N'Xanh jean', '31'),
(148, 1, 'QJS06-XANHJEAN-32', NULL, N'Quần jeans slim fit - Xanh jean - 32', 'goods', 3, 4, 1, NULL, 459000.0000, 200000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjs06-xanhjean-32', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 6, N'Xanh jean', '32'),
(149, 1, 'QJS06-XANHJEAN-34', NULL, N'Quần jeans slim fit - Xanh jean - 34', 'goods', 3, 4, 1, NULL, 459000.0000, 200000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjs06-xanhjean-34', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 6, N'Xanh jean', '34'),
(150, 1, 'ATB01-XANHNAVY-S', NULL, N'Áo thun basic cổ tròn - Xanh navy - S', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-xanhnavy-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Xanh navy', 'S'),
(151, 1, 'ATB01-XANHNAVY-M', NULL, N'Áo thun basic cổ tròn - Xanh navy - M', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-xanhnavy-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Xanh navy', 'M'),
(152, 1, 'ATB01-XANHNAVY-L', NULL, N'Áo thun basic cổ tròn - Xanh navy - L', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-xanhnavy-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Xanh navy', 'L'),
(153, 1, 'ATB01-XANHNAVY-XL', NULL, N'Áo thun basic cổ tròn - Xanh navy - XL', 'goods', 1, 1, 1, NULL, 159000.0000, 65000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atb01-xanhnavy-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 1, N'Xanh navy', 'XL'),
(154, 1, 'ATP02-XANHNAVY-M', NULL, N'Áo polo pique - Xanh navy - M', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-xanhnavy-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Xanh navy', 'M'),
(155, 1, 'ATP02-XANHNAVY-L', NULL, N'Áo polo pique - Xanh navy - L', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-xanhnavy-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Xanh navy', 'L'),
(156, 1, 'ATP02-XANHNAVY-XL', NULL, N'Áo polo pique - Xanh navy - XL', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-xanhnavy-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Xanh navy', 'XL'),
(157, 1, 'ATP02-XANHNAVY-XXL', NULL, N'Áo polo pique - Xanh navy - XXL', 'goods', 1, 1, 1, NULL, 249000.0000, 105000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'atp02-xanhnavy-xxl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 2, N'Xanh navy', 'XXL'),
(158, 1, 'QKK08-XANHNAVY-29', NULL, N'Quần kaki chinos - Xanh navy - 29', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Xanh navy', '29'),
(159, 1, 'QKK08-XANHNAVY-30', NULL, N'Quần kaki chinos - Xanh navy - 30', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Xanh navy', '30'),
(160, 1, 'QKK08-XANHNAVY-31', NULL, N'Quần kaki chinos - Xanh navy - 31', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Xanh navy', '31'),
(161, 1, 'QKK08-XANHNAVY-32', NULL, N'Quần kaki chinos - Xanh navy - 32', 'goods', 4, 1, 1, NULL, 389000.0000, 165000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 8, N'Xanh navy', '32'),
(162, 1, 'MLT19-XANHNAVY-FREESIZE', NULL, N'Mũ lưỡi trai - Xanh navy - Free size', 'goods', 13, 2, 1, NULL, 129000.0000, 45000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 19, N'Xanh navy', 'Free size'),
(163, 1, 'QJN07-XANHNHAT-S', NULL, N'Quần jeans nữ ống rộng - Xanh nhạt - S', 'goods', 3, 4, 1, NULL, 429000.0000, 185000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjn07-xanhnhat-s', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 7, N'Xanh nhạt', 'S'),
(164, 1, 'QJN07-XANHNHAT-M', NULL, N'Quần jeans nữ ống rộng - Xanh nhạt - M', 'goods', 3, 4, 1, NULL, 429000.0000, 185000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjn07-xanhnhat-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 7, N'Xanh nhạt', 'M'),
(165, 1, 'QJN07-XANHNHAT-L', NULL, N'Quần jeans nữ ống rộng - Xanh nhạt - L', 'goods', 3, 4, 1, NULL, 429000.0000, 185000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'qjn07-xanhnhat-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 7, N'Xanh nhạt', 'L'),
(166, 1, 'AKB12-XANHREU-M', NULL, N'Áo khoác bomber - Xanh rêu - M', 'goods', 7, 2, 1, NULL, 599000.0000, 260000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'akb12-xanhreu-m', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 12, N'Xanh rêu', 'M'),
(167, 1, 'AKB12-XANHREU-L', NULL, N'Áo khoác bomber - Xanh rêu - L', 'goods', 7, 2, 1, NULL, 599000.0000, 260000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'akb12-xanhreu-l', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 12, N'Xanh rêu', 'L'),
(168, 1, 'AKB12-XANHREU-XL', NULL, N'Áo khoác bomber - Xanh rêu - XL', 'goods', 7, 2, 1, NULL, 599000.0000, 260000.0000, 'average', NULL, NULL, 1, 1, 1, 'none', 3.0000, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 1, 'akb12-xanhreu-xl', 1, '2026-09-19T09:42:54.7200000', 1, NULL, NULL, 0, 12, N'Xanh rêu', 'XL')
;
SET IDENTITY_INSERT [md].[Products] OFF;
GO

-- md.Taxes (6 dòng)
SET IDENTITY_INSERT [md].[Taxes] ON;
INSERT INTO [md].[Taxes] ([Id], [CompanyId], [Code], [Name], [TaxScope], [Rate], [IsActive], [SaleAccountId], [PurchaseAccountId]) VALUES
(1, 1, 'VAT10', N'Thuế GTGT 10%', 'both', 10.0000, 1, 32, 9),
(2, 1, 'VAT8', N'Thuế GTGT 8% (giảm thuế)', 'both', 8.0000, 1, 32, 9),
(3, 1, 'VAT5', N'Thuế GTGT 5%', 'both', 5.0000, 1, 32, 9),
(4, 1, 'VAT0', N'Thuế GTGT 0%', 'both', 0.0000, 1, 32, 9),
(5, 1, 'KCT', N'Không chịu thuế', 'both', 0.0000, 1, 32, 9),
(6, 1, 'KKKNT', N'Không kê khai, nộp thuế', 'both', 0.0000, 1, 32, 9)
;
SET IDENTITY_INSERT [md].[Taxes] OFF;
GO

-- md.UnitsOfMeasure (21 dòng)
SET IDENTITY_INSERT [md].[UnitsOfMeasure] ON;
INSERT INTO [md].[UnitsOfMeasure] ([Id], [CompanyId], [Code], [Name], [IsActive]) VALUES
(1, NULL, 'CAI', N'Cái', 1),
(2, NULL, 'CHIEC', N'Chiếc', 1),
(3, NULL, 'HOP', N'Hộp', 1),
(4, NULL, 'THUNG', N'Thùng', 1),
(5, NULL, 'KG', N'Kg', 1),
(6, NULL, 'GAM', N'Gam', 1),
(7, NULL, 'TAN', N'Tấn', 1),
(8, NULL, 'M', N'Mét', 1),
(9, NULL, 'M2', N'Mét vuông', 1),
(10, NULL, 'M3', N'Mét khối', 1),
(11, NULL, 'LIT', N'Lít', 1),
(12, NULL, 'BO', N'Bộ', 1),
(13, NULL, 'GOI', N'Gói', 1),
(14, NULL, 'CHAI', N'Chai', 1),
(15, NULL, 'LON', N'Lon', 1),
(16, NULL, 'CUON', N'Cuộn', 1),
(17, NULL, 'GIO', N'Giờ', 1),
(18, NULL, 'NGAY', N'Ngày', 1),
(19, NULL, 'THANG', N'Tháng', 1),
(20, NULL, 'LAN', N'Lần', 1),
(21, NULL, 'DOI', N'Đôi', 1)
;
SET IDENTITY_INSERT [md].[UnitsOfMeasure] OFF;
GO

-- mkt.CampaignDailyStats (96 dòng)
INSERT INTO [mkt].[CampaignDailyStats] ([CampaignId], [StatDate], [Impressions], [Clicks], [Spend], [Leads]) VALUES
(1, '2026-10-27', 13650, 245, 343000.00, 7),
(1, '2026-10-28', 14000, 224, 347000.00, 1),
(1, '2026-10-29', 14350, 200, 350000.00, 4),
(1, '2026-10-30', 14700, 176, 354000.00, 7),
(1, '2026-10-31', 15050, 376, 357000.00, 1),
(1, '2026-11-01', 15050, 376, 392000.00, 1),
(1, '2026-11-02', 15400, 354, 396000.00, 4),
(1, '2026-11-03', 15750, 330, 399000.00, 7),
(1, '2026-11-04', 16100, 305, 403000.00, 1),
(1, '2026-11-05', 16450, 279, 406000.00, 4),
(1, '2026-11-06', 16800, 252, 410000.00, 7),
(1, '2026-11-07', 17150, 222, 413000.00, 1),
(1, '2026-11-08', 17500, 455, 417000.00, 4),
(1, '2026-11-09', 17850, 428, 280000.00, 7),
(1, '2026-11-10', 18200, 400, 284000.00, 1),
(1, '2026-11-11', 18550, 371, 287000.00, 4),
(1, '2026-11-12', 18900, 340, 291000.00, 7),
(1, '2026-11-13', 19250, 308, 294000.00, 1),
(1, '2026-11-14', 19600, 274, 298000.00, 4),
(1, '2026-11-15', 19950, 239, 301000.00, 7),
(1, '2026-11-16', 20300, 507, 305000.00, 1),
(2, '2026-10-22', 12300, 159, 252000.00, 8),
(2, '2026-10-23', 12600, 327, 255000.00, 2),
(2, '2026-10-24', 12900, 309, 258000.00, 5),
(2, '2026-10-25', 13200, 290, 261000.00, 8),
(2, '2026-10-26', 13500, 270, 264000.00, 2),
(2, '2026-10-27', 13800, 248, 267000.00, 5),
(2, '2026-10-28', 14100, 225, 270000.00, 8),
(2, '2026-10-29', 14400, 201, 273000.00, 2),
(2, '2026-10-30', 14700, 176, 276000.00, 5),
(2, '2026-10-31', 15000, 375, 279000.00, 8),
(2, '2026-11-01', 15000, 375, 309000.00, 8),
(2, '2026-11-02', 15300, 351, 312000.00, 2),
(2, '2026-11-03', 15600, 327, 315000.00, 5),
(2, '2026-11-04', 15900, 302, 318000.00, 8),
(2, '2026-11-05', 16200, 275, 321000.00, 2),
(2, '2026-11-06', 16500, 247, 324000.00, 5),
(2, '2026-11-07', 16800, 218, 327000.00, 8),
(2, '2026-11-08', 17100, 444, 330000.00, 2),
(2, '2026-11-09', 17400, 417, 333000.00, 5),
(2, '2026-11-10', 17700, 389, 336000.00, 8),
(2, '2026-11-11', 18000, 360, 339000.00, 2),
(2, '2026-11-12', 18300, 329, 342000.00, 5),
(2, '2026-11-13', 18600, 297, 345000.00, 8),
(2, '2026-11-14', 18900, 264, 348000.00, 2),
(2, '2026-11-15', 19200, 230, 351000.00, 5),
(2, '2026-11-16', 10500, 262, 354000.00, 8),
(2, '2026-11-17', 10800, 248, 357000.00, 2),
(2, '2026-11-18', 11100, 233, 240000.00, 5),
(2, '2026-11-19', 11400, 216, 243000.00, 8),
(2, '2026-11-20', 11700, 198, 246000.00, 2),
(3, '2026-10-07', 3780, 49, 60000.00, 0),
(3, '2026-10-08', 3840, 99, 61000.00, 2),
(3, '2026-10-09', 2100, 50, 61000.00, 1),
(3, '2026-10-10', 2160, 47, 62000.00, 0),
(3, '2026-10-11', 2220, 44, 62000.00, 2),
(3, '2026-10-12', 2280, 41, 63000.00, 1),
(3, '2026-10-13', 2340, 37, 64000.00, 0),
(3, '2026-10-14', 2400, 33, 64000.00, 2),
(3, '2026-10-15', 2460, 29, 65000.00, 1),
(3, '2026-10-16', 2520, 63, 65000.00, 0),
(3, '2026-10-17', 2580, 59, 66000.00, 2),
(3, '2026-10-18', 2640, 55, 67000.00, 1),
(3, '2026-10-19', 2700, 51, 67000.00, 0),
(3, '2026-10-20', 2760, 46, 68000.00, 2),
(3, '2026-10-21', 2820, 42, 68000.00, 1),
(3, '2026-10-22', 2880, 37, 69000.00, 0),
(3, '2026-10-23', 2940, 76, 70000.00, 2),
(3, '2026-10-24', 3000, 72, 70000.00, 1),
(3, '2026-10-25', 3060, 67, 71000.00, 0),
(3, '2026-10-26', 3120, 62, 71000.00, 2),
(3, '2026-10-27', 3180, 57, 48000.00, 1),
(3, '2026-10-28', 3240, 51, 49000.00, 0),
(3, '2026-10-29', 3300, 46, 49000.00, 2),
(3, '2026-10-30', 3360, 40, 50000.00, 1),
(3, '2026-10-31', 3420, 85, 50000.00, 0),
(3, '2026-11-01', 3420, 85, 56000.00, 1),
(3, '2026-11-02', 3480, 80, 57000.00, 0),
(3, '2026-11-03', 3540, 74, 58000.00, 2),
(3, '2026-11-04', 3600, 68, 58000.00, 1),
(3, '2026-11-05', 3660, 62, 59000.00, 0),
(3, '2026-11-06', 3720, 55, 59000.00, 2),
(3, '2026-11-07', 3780, 49, 60000.00, 1),
(3, '2026-11-08', 3840, 99, 61000.00, 0),
(3, '2026-11-09', 2100, 50, 61000.00, 2),
(3, '2026-11-10', 2160, 47, 62000.00, 1),
(3, '2026-11-11', 2220, 44, 62000.00, 0),
(3, '2026-11-12', 2280, 41, 63000.00, 2),
(3, '2026-11-13', 2340, 37, 64000.00, 1),
(3, '2026-11-14', 2400, 33, 64000.00, 0),
(3, '2026-11-15', 2460, 29, 65000.00, 2),
(3, '2026-11-16', 2520, 63, 65000.00, 1),
(3, '2026-11-17', 2580, 59, 66000.00, 0),
(3, '2026-11-18', 2640, 55, 67000.00, 2),
(3, '2026-11-19', 2700, 51, 67000.00, 1),
(3, '2026-11-20', 2760, 46, 68000.00, 0)
;
GO

-- mkt.Campaigns (4 dòng)
SET IDENTITY_INSERT [mkt].[Campaigns] ON;
INSERT INTO [mkt].[Campaigns] ([Id], [CompanyId], [Code], [Name], [Channel], [StartDate], [EndDate], [Budget], [ActualCost], [TargetLeads], [UtmSource], [UtmMedium], [UtmCampaign], [Status], [OwnerUserId], [Description], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'CD2026-001', N'Sale 11.11 - Facebook Ads', 'facebook', '2026-10-27', '2026-11-16', 8000000.00, 7327000.00, 120, NULL, NULL, NULL, 'completed', 1, N'Chạy quảng cáo bài đăng giảm giá, mã GIAM20K', '2026-10-26T00:00:00.0000000', 1, NULL, NULL, 0),
(2, 1, 'CD2026-002', N'TikTok Thu Đông 2026', 'tiktok', '2026-10-22', NULL, 12000000.00, 9045000.00, 200, NULL, NULL, NULL, 'running', 1, N'Video thử đồ, livestream tối thứ 6', '2026-10-21T00:00:00.0000000', 1, NULL, NULL, 0),
(3, 1, 'CD2026-003', N'Google tìm kiếm thương hiệu', 'google', '2026-10-07', NULL, 3000000.00, 2802000.00, 40, NULL, NULL, NULL, 'running', 1, N'Từ khóa: mystyle, áo thun basic, giày sneaker trắng', '2026-10-06T00:00:00.0000000', 1, NULL, NULL, 0),
(4, 1, 'CD2026-004', N'Black Friday 2026', 'facebook', '2026-11-27', '2026-11-30', 10000000.00, 0.00, 150, NULL, NULL, NULL, 'draft', 1, N'Giảm 20% toàn bộ, tối đa 200k', '2026-11-26T00:00:00.0000000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [mkt].[Campaigns] OFF;
GO

-- prj.ProjectMembers (16 dòng)
INSERT INTO [prj].[ProjectMembers] ([ProjectId], [UserId], [MemberRole], [JoinedAt]) VALUES
(1, 1, 'member', '2026-11-21T03:09:29.4210000'),
(1, 2, 'manager', '2026-11-21T03:09:29.4210000'),
(1, 3, 'member', '2026-11-21T03:09:29.4210000'),
(1, 4, 'member', '2026-11-21T03:09:29.4210000'),
(1, 6, 'member', '2026-11-21T03:09:29.4210000'),
(1, 7, 'member', '2026-11-21T03:09:29.4210000'),
(2, 1, 'member', '2026-11-21T03:09:29.4210000'),
(2, 3, 'member', '2026-11-21T03:09:29.4210000'),
(2, 5, 'member', '2026-11-21T03:09:29.4210000'),
(2, 7, 'manager', '2026-11-21T03:09:29.4210000'),
(3, 1, 'member', '2026-11-21T03:09:29.4210000'),
(3, 4, 'member', '2026-11-21T03:09:29.4210000'),
(3, 6, 'manager', '2026-11-21T03:09:29.4210000'),
(4, 1, 'member', '2026-11-21T03:09:29.4210000'),
(4, 5, 'manager', '2026-11-21T03:09:29.4210000'),
(4, 7, 'member', '2026-11-21T03:09:29.4210000')
;
GO

-- prj.Projects (4 dòng)
SET IDENTITY_INSERT [prj].[Projects] ON;
INSERT INTO [prj].[Projects] ([Id], [CompanyId], [Code], [Name], [PartnerId], [SalesOrderId], [ManagerUserId], [DepartmentId], [StartDate], [EndDate], [Budget], [Status], [ProgressPercent], [Description], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'DA2026-001', N'Khai trương chi nhánh Quận 7', NULL, NULL, 2, 10, '2026-11-01', '2026-12-16', 150000000.00, 'active', 45.00, N'Mặt bằng 45 Nguyễn Thị Thập, Q.7. Mục tiêu khai trương trước 20/12 để kịp mùa Tết.', '2026-10-29T03:09:29.2720000', 1, NULL, NULL, 0),
(2, 1, 'DA2026-002', N'Chụp lookbook Tết 2027', NULL, NULL, 7, 3, '2026-11-11', '2026-12-03', 35000000.00, 'active', 41.67, N'40 outfit BST Tết, ảnh dùng cho website, Facebook, TikTok và in standee.', '2026-11-08T03:09:29.2720000', 1, NULL, NULL, 0),
(3, 1, 'DA2026-003', N'Kiểm kê kho cuối năm 2026', NULL, NULL, 6, 5, '2026-12-16', '2026-12-21', 0.00, 'planning', 0.00, N'Kiểm kê toàn bộ kho KHO01, đối chiếu sổ sách trước khi khóa sổ năm.', '2026-12-13T03:09:29.2720000', 1, NULL, NULL, 0),
(4, 1, 'DA2026-004', N'Ra mắt website mystyle.vn', NULL, NULL, 5, 2, '2026-09-22', '2026-11-01', 25000000.00, 'completed', 100.00, N'Website bán hàng kết nối kho, đơn online đổ thẳng về app Đơn hàng.', '2026-09-19T03:09:29.2720000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [prj].[Projects] OFF;
GO

-- prj.TaskChecklistItems (16 dòng)
SET IDENTITY_INSERT [prj].[TaskChecklistItems] ON;
INSERT INTO [prj].[TaskChecklistItems] ([Id], [TaskId], [Title], [IsDone], [SortOrder]) VALUES
(1, 3, N'Vẽ layout cửa hàng', 1, 10),
(2, 3, N'Chốt báo giá thi công', 1, 20),
(3, 3, N'Lắp kệ, móc treo', 0, 30),
(4, 3, N'Lắp đèn, gương phòng thử', 0, 40),
(5, 3, N'Nghiệm thu', 0, 50),
(6, 11, N'Nam: 15 outfit', 1, 10),
(7, 11, N'Nữ: 20 outfit', 0, 20),
(8, 11, N'Phụ kiện, giày đi kèm', 1, 30),
(9, 11, N'Chốt danh sách với Mai', 0, 40),
(10, 12, N'Chuẩn bị đồ, là ủi', 0, 10),
(11, 12, N'Shotlist từng outfit', 0, 20),
(12, 23, N'Chị Hoa - 0901***', 1, 10),
(13, 23, N'Anh Long', 1, 20),
(14, 23, N'Chị Trang', 0, 30),
(15, 23, N'Anh Phúc', 0, 40),
(16, 23, N'Chị Ngọc', 0, 50)
;
SET IDENTITY_INSERT [prj].[TaskChecklistItems] OFF;
GO

-- prj.Tasks (26 dòng)
SET IDENTITY_INSERT [prj].[Tasks] ON;
INSERT INTO [prj].[Tasks] ([Id], [CompanyId], [Code], [ProjectId], [ParentTaskId], [Title], [Description], [StageId], [Priority], [AssigneeUserId], [ReporterUserId], [DepartmentId], [EntityName], [EntityId], [StartDate], [DueDate], [CompletedAt], [EstimatedHours], [ProgressPercent], [SortOrder], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'CV-000001', 1, NULL, N'Ký hợp đồng thuê mặt bằng 45 Nguyễn Thị Thập', N'Thuê 3 năm, cọc 3 tháng. Hợp đồng lưu ở app Tài liệu.', 4, 'high', 2, 2, 10, NULL, NULL, '2026-10-30', '2026-11-06T00:00:00.0000000', '2026-11-05T03:09:29.2720000', 4.00, 100.00, 0, '2026-10-27T03:09:29.2720000', 2, NULL, NULL, 0),
(2, 1, 'CV-000002', 1, NULL, N'Đăng ký hộ kinh doanh chi nhánh', NULL, 4, 'normal', 2, 2, 10, NULL, NULL, '2026-11-04', '2026-11-11T00:00:00.0000000', '2026-11-12T03:09:29.2720000', 3.00, 100.00, 0, '2026-11-01T03:09:29.2720000', 2, NULL, NULL, 0),
(3, 1, 'CV-000003', 1, NULL, N'Thi công nội thất, kệ trưng bày', N'Đơn vị thi công: Nội thất Hòa Phát Decor. Nghiệm thu trước khi nhập hàng.', 2, 'high', 2, 2, 10, NULL, NULL, '2026-11-21', '2026-11-28T00:00:00.0000000', NULL, 40.00, 40.00, 0, '2026-11-18T03:09:29.2720000', 2, NULL, NULL, 0),
(4, 1, 'CV-000004', 1, NULL, N'Tuyển 3 nhân viên bán hàng ca xoay', N'Đăng tin Facebook group việc làm Q7, phỏng vấn tại cửa hàng Lê Lợi.', 2, 'normal', 2, 2, 10, NULL, NULL, '2026-11-24', '2026-12-01T00:00:00.0000000', NULL, 12.00, 30.00, 0, '2026-11-21T03:09:29.2720000', 2, NULL, NULL, 0),
(5, 1, 'CV-000005', 1, NULL, N'Thiết kế standee, banner khai trương', N'Đã gửi bản thiết kế, chờ chị Nhung duyệt.', 3, 'high', 7, 2, 3, NULL, NULL, '2026-11-12', '2026-11-19T00:00:00.0000000', NULL, 10.00, 90.00, 0, '2026-11-09T03:09:29.2720000', 2, NULL, NULL, 0),
(6, 1, 'CV-000006', 1, NULL, N'Lắp đặt máy POS, camera, wifi', NULL, 1, 'normal', 4, 2, 10, NULL, NULL, '2026-11-29', '2026-12-06T00:00:00.0000000', NULL, 6.00, 0.00, 0, '2026-11-26T03:09:29.2720000', 2, NULL, NULL, 0),
(7, 1, 'CV-000007', 1, NULL, N'Nhập hàng trưng bày khai trương (300 SKU)', N'Lấy danh sách SKU bán chạy 60 ngày ở app Báo cáo.', 1, 'normal', 6, 2, 5, NULL, NULL, '2026-12-02', '2026-12-09T00:00:00.0000000', NULL, 16.00, 0.00, 0, '2026-11-29T03:09:29.2720000', 2, NULL, NULL, 0),
(8, 1, 'CV-000008', 1, NULL, N'Chạy quảng cáo Facebook bán kính 3km quanh Q7', N'Gắn mã giảm giá KHAITRUONG cho chiến dịch để đo doanh thu.', 1, 'high', 7, 2, 3, NULL, NULL, '2026-12-04', '2026-12-11T00:00:00.0000000', NULL, 8.00, 0.00, 0, '2026-12-01T03:09:29.2720000', 2, NULL, NULL, 0),
(9, 1, 'CV-000009', 2, NULL, N'Chốt concept & moodboard', NULL, 4, 'normal', 7, 7, 3, NULL, NULL, '2026-11-08', '2026-11-15T00:00:00.0000000', '2026-11-14T03:09:29.2720000', 6.00, 100.00, 0, '2026-11-05T03:09:29.2720000', 7, NULL, NULL, 0),
(10, 1, 'CV-000010', 2, NULL, N'Book studio và người mẫu', NULL, 4, 'normal', 7, 7, 3, NULL, NULL, '2026-11-11', '2026-11-18T00:00:00.0000000', '2026-11-17T03:09:29.2720000', 3.00, 100.00, 0, '2026-11-08T03:09:29.2720000', 7, NULL, NULL, 0),
(11, 1, 'CV-000011', 2, NULL, N'Chọn 40 outfit từ BST Tết', NULL, 2, 'high', 5, 7, 2, NULL, NULL, '2026-11-16', '2026-11-23T00:00:00.0000000', NULL, 8.00, 50.00, 0, '2026-11-13T03:09:29.2720000', 7, NULL, NULL, 0),
(12, 1, 'CV-000012', 2, NULL, N'Chụp ảnh 2 ngày tại studio', NULL, 1, 'urgent', 7, 7, 3, NULL, NULL, '2026-11-19', '2026-11-26T00:00:00.0000000', NULL, 16.00, 0.00, 0, '2026-11-16T03:09:29.2720000', 7, NULL, NULL, 0),
(13, 1, 'CV-000013', 2, NULL, N'Retouch & xuất ảnh cho website / social', NULL, 1, 'normal', 5, 7, 2, NULL, NULL, '2026-11-23', '2026-11-30T00:00:00.0000000', NULL, 12.00, 0.00, 0, '2026-11-20T03:09:29.2720000', 7, NULL, NULL, 0),
(14, 1, 'CV-000014', 2, NULL, N'Đăng lookbook lên website và Facebook', NULL, 1, 'normal', 5, 7, 2, NULL, NULL, '2026-11-26', '2026-12-03T00:00:00.0000000', NULL, 3.00, 0.00, 0, '2026-11-23T03:09:29.2720000', 7, NULL, NULL, 0),
(15, 1, 'CV-000015', 3, NULL, N'Lập kế hoạch kiểm kê, chia khu vực kệ', NULL, 1, 'normal', 6, 6, 5, NULL, NULL, '2026-12-04', '2026-12-11T00:00:00.0000000', NULL, 4.00, 0.00, 0, '2026-12-01T03:09:29.2720000', 6, NULL, NULL, 0),
(16, 1, 'CV-000016', 3, NULL, N'In phiếu kiểm kê theo kệ', NULL, 1, 'low', 4, 6, 5, NULL, NULL, '2026-12-08', '2026-12-15T00:00:00.0000000', NULL, 2.00, 0.00, 0, '2026-12-05T03:09:29.2720000', 6, NULL, NULL, 0),
(17, 1, 'CV-000017', 3, NULL, N'Đối chiếu chênh lệch, lập biên bản kiểm kê', NULL, 1, 'normal', 6, 6, 5, NULL, NULL, '2026-12-14', '2026-12-21T00:00:00.0000000', NULL, 6.00, 0.00, 0, '2026-12-11T03:09:29.2720000', 6, NULL, NULL, 0),
(18, 1, 'CV-000018', 4, NULL, N'Chọn giao diện, cấu hình tên miền', NULL, 4, 'normal', 5, 5, 2, NULL, NULL, '2026-09-25', '2026-10-02T00:00:00.0000000', '2026-09-30T03:09:29.2720000', 8.00, 100.00, 0, '2026-09-22T03:09:29.2720000', 5, NULL, NULL, 0),
(19, 1, 'CV-000019', 4, NULL, N'Chụp ảnh sản phẩm, viết mô tả 20 mẫu', NULL, 4, 'normal', 7, 5, 3, NULL, NULL, '2026-10-10', '2026-10-17T00:00:00.0000000', '2026-10-16T03:09:29.2720000', 24.00, 100.00, 0, '2026-10-07T03:09:29.2720000', 5, NULL, NULL, 0),
(20, 1, 'CV-000020', 4, NULL, N'Kết nối đơn online về app Đơn hàng', NULL, 4, 'high', 1, 5, NULL, NULL, NULL, '2026-10-17', '2026-10-24T00:00:00.0000000', '2026-10-23T03:09:29.2720000', 6.00, 100.00, 0, '2026-10-14T03:09:29.2720000', 5, NULL, NULL, 0),
(21, 1, 'CV-000021', 4, NULL, N'Chạy thử, sửa lỗi và mở bán', NULL, 4, 'high', 5, 5, 2, NULL, NULL, '2026-10-25', '2026-11-01T00:00:00.0000000', '2026-11-01T03:09:29.2720000', 6.00, 100.00, 0, '2026-10-22T03:09:29.2720000', 5, NULL, NULL, 0),
(22, 1, 'CV-000022', NULL, NULL, N'Xuất hóa đơn VAT tháng 11 cho khách sỉ', N'Giao cho phòng Kế toán. Danh sách khách cần hóa đơn: xem đơn có ghi chú "lấy VAT".', 1, 'normal', NULL, 1, 4, NULL, NULL, '2026-11-17', '2026-11-24T00:00:00.0000000', NULL, 2.00, 0.00, 0, '2026-11-14T03:09:29.2720000', 1, NULL, NULL, 0),
(23, 1, 'CV-000023', NULL, NULL, N'Gọi lại 5 khách VIP lâu chưa mua', N'Danh sách ở app Marketing > Nhóm khách hàng > Sắp mất.', 2, 'high', 3, 1, 10, NULL, NULL, '2026-11-13', '2026-11-20T00:00:00.0000000', NULL, 2.00, 40.00, 0, '2026-11-10T03:09:29.2720000', 1, NULL, NULL, 0),
(24, 1, 'CV-000024', NULL, NULL, N'Kiểm tra hàng lỗi đổi trả tuần này', NULL, 1, 'normal', 6, 1, 5, NULL, NULL, '2026-11-16', '2026-11-23T00:00:00.0000000', NULL, 2.00, 0.00, 0, '2026-11-13T03:09:29.2720000', 1, NULL, NULL, 0),
(25, 1, 'CV-000025', NULL, NULL, N'Cập nhật giá Shopee sau đợt sale 11.11', NULL, 4, 'normal', 5, 1, 2, NULL, NULL, '2026-11-08', '2026-11-15T00:00:00.0000000', '2026-11-14T03:09:29.2720000', 2.00, 100.00, 0, '2026-11-05T03:09:29.2720000', 1, NULL, NULL, 0),
(26, 1, 'CV-000026', NULL, NULL, N'Duyệt kế hoạch marketing tháng 12', N'Mai gửi kế hoạch: ngân sách 30 triệu, 3 chiến dịch.', 3, 'high', 1, 1, NULL, NULL, NULL, '2026-11-18', '2026-11-25T00:00:00.0000000', NULL, 1.00, 80.00, 0, '2026-11-15T03:09:29.2720000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [prj].[Tasks] OFF;
GO

-- prj.TaskStages (4 dòng)
SET IDENTITY_INSERT [prj].[TaskStages] ON;
INSERT INTO [prj].[TaskStages] ([Id], [CompanyId], [ProjectId], [Name], [SortOrder], [IsDone]) VALUES
(1, 1, NULL, N'Cần làm', 10, 0),
(2, 1, NULL, N'Đang làm', 20, 0),
(3, 1, NULL, N'Chờ duyệt', 30, 0),
(4, 1, NULL, N'Hoàn thành', 40, 1)
;
SET IDENTITY_INSERT [prj].[TaskStages] OFF;
GO

-- prj.Timesheets (12 dòng)
SET IDENTITY_INSERT [prj].[Timesheets] ON;
INSERT INTO [prj].[Timesheets] ([Id], [TaskId], [ProjectId], [UserId], [WorkDate], [Hours], [Note], [IsBillable], [CreatedAt]) VALUES
(1, 1, 1, 2, '2026-11-04', 3.00, N'Đàm phán với chủ nhà', 0, '2026-11-04T03:09:29.2720000'),
(2, 1, 1, 2, '2026-11-05', 1.50, N'Ký hợp đồng', 0, '2026-11-05T03:09:29.2720000'),
(3, 3, 1, 2, '2026-11-15', 4.00, N'Làm việc với đơn vị thi công', 0, '2026-11-15T03:09:29.2720000'),
(4, 3, 1, 2, '2026-11-19', 3.50, N'Giám sát lắp kệ', 0, '2026-11-19T03:09:29.2720000'),
(5, 5, 1, 7, '2026-11-17', 5.00, N'Thiết kế bản 1', 0, '2026-11-17T03:09:29.2720000'),
(6, 5, 1, 7, '2026-11-18', 3.00, N'Sửa theo góp ý', 0, '2026-11-18T03:09:29.2720000'),
(7, 9, 2, 7, '2026-11-13', 4.00, NULL, 0, '2026-11-13T03:09:29.2720000'),
(8, 11, 2, 5, '2026-11-20', 4.00, N'Chọn đồ nam + phụ kiện', 0, '2026-11-20T03:09:29.2720000'),
(9, 19, 4, 7, '2026-10-12', 8.00, NULL, 0, '2026-10-12T03:09:29.2720000'),
(10, 19, 4, 7, '2026-10-14', 8.00, NULL, 0, '2026-10-14T03:09:29.2720000'),
(11, 20, 4, 1, '2026-10-22', 6.00, NULL, 0, '2026-10-22T03:09:29.2720000'),
(12, 23, NULL, 3, '2026-11-20', 1.00, N'Gọi được 2/5 khách', 0, '2026-11-20T03:09:29.2720000')
;
SET IDENTITY_INSERT [prj].[Timesheets] OFF;
GO

-- pur.PurchaseOrderLines (320 dòng)
SET IDENTITY_INSERT [pur].[PurchaseOrderLines] ON;
INSERT INTO [pur].[PurchaseOrderLines] ([Id], [PurchaseOrderId], [LineNumber], [ProductId], [Description], [UomId], [Quantity], [UnitPrice], [DiscountPercent], [TaxId], [TaxRate], [LineSubTotal], [LineTax], [LineTotal], [QtyReceived], [QtyBilled], [PurchaseRequestLineId]) VALUES
(1, 1, 1, 1, N'Áo thun oversize in chữ - Be - M', 1, 3.0000, 80000.0000, 0.0000, NULL, 0.0000, 240000.00, 0.00, 240000.00, 3.0000, 0.0000, NULL),
(2, 1, 2, 2, N'Áo thun oversize in chữ - Be - L', 1, 4.0000, 80000.0000, 0.0000, NULL, 0.0000, 320000.00, 0.00, 320000.00, 4.0000, 0.0000, NULL),
(3, 1, 3, 3, N'Áo thun oversize in chữ - Be - XL', 1, 4.0000, 80000.0000, 0.0000, NULL, 0.0000, 320000.00, 0.00, 320000.00, 4.0000, 0.0000, NULL),
(4, 1, 4, 25, N'Mũ lưỡi trai - Be - Free size', 1, 4.0000, 45000.0000, 0.0000, NULL, 0.0000, 180000.00, 0.00, 180000.00, 4.0000, 0.0000, NULL),
(5, 1, 5, 26, N'Tất cổ ngắn (combo 3 đôi) - Đen - Free size', 12, 5.0000, 28000.0000, 0.0000, NULL, 0.0000, 140000.00, 0.00, 140000.00, 5.0000, 0.0000, NULL),
(6, 1, 6, 38, N'Mũ lưỡi trai - Đen - Free size', 1, 4.0000, 45000.0000, 0.0000, NULL, 0.0000, 180000.00, 0.00, 180000.00, 4.0000, 0.0000, NULL),
(7, 1, 7, 40, N'Áo khoác bomber - Đen - M', 1, 1.0000, 260000.0000, 0.0000, NULL, 0.0000, 260000.00, 0.00, 260000.00, 1.0000, 0.0000, NULL),
(8, 1, 8, 41, N'Áo khoác bomber - Đen - L', 1, 5.0000, 260000.0000, 0.0000, NULL, 0.0000, 1300000.00, 0.00, 1300000.00, 5.0000, 0.0000, NULL),
(9, 1, 9, 42, N'Áo khoác bomber - Đen - XL', 1, 5.0000, 260000.0000, 0.0000, NULL, 0.0000, 1300000.00, 0.00, 1300000.00, 5.0000, 0.0000, NULL),
(10, 1, 10, 66, N'Quần short thể thao - Đen - M', 1, 3.0000, 70000.0000, 0.0000, NULL, 0.0000, 210000.00, 0.00, 210000.00, 3.0000, 0.0000, NULL),
(11, 1, 11, 67, N'Quần short thể thao - Đen - L', 1, 5.0000, 70000.0000, 0.0000, NULL, 0.0000, 350000.00, 0.00, 350000.00, 5.0000, 0.0000, NULL),
(12, 1, 12, 68, N'Quần short thể thao - Đen - XL', 1, 3.0000, 70000.0000, 0.0000, NULL, 0.0000, 210000.00, 0.00, 210000.00, 3.0000, 0.0000, NULL),
(13, 1, 13, 74, N'Áo thun basic cổ tròn - Đen - S', 1, 4.0000, 65000.0000, 0.0000, NULL, 0.0000, 260000.00, 0.00, 260000.00, 4.0000, 0.0000, NULL),
(14, 1, 14, 75, N'Áo thun basic cổ tròn - Đen - M', 1, 5.0000, 65000.0000, 0.0000, NULL, 0.0000, 325000.00, 0.00, 325000.00, 5.0000, 0.0000, NULL),
(15, 1, 15, 76, N'Áo thun basic cổ tròn - Đen - L', 1, 4.0000, 65000.0000, 0.0000, NULL, 0.0000, 260000.00, 0.00, 260000.00, 4.0000, 0.0000, NULL),
(16, 1, 16, 77, N'Áo thun basic cổ tròn - Đen - XL', 1, 4.0000, 65000.0000, 0.0000, NULL, 0.0000, 260000.00, 0.00, 260000.00, 4.0000, 0.0000, NULL),
(17, 1, 17, 78, N'Áo polo pique - Đen - M', 1, 5.0000, 105000.0000, 0.0000, NULL, 0.0000, 525000.00, 0.00, 525000.00, 5.0000, 0.0000, NULL),
(18, 1, 18, 79, N'Áo polo pique - Đen - L', 1, 3.0000, 105000.0000, 0.0000, NULL, 0.0000, 315000.00, 0.00, 315000.00, 3.0000, 0.0000, NULL),
(19, 1, 19, 80, N'Áo polo pique - Đen - XL', 1, 3.0000, 105000.0000, 0.0000, NULL, 0.0000, 315000.00, 0.00, 315000.00, 3.0000, 0.0000, NULL),
(20, 1, 20, 81, N'Áo polo pique - Đen - XXL', 1, 3.0000, 105000.0000, 0.0000, NULL, 0.0000, 315000.00, 0.00, 315000.00, 3.0000, 0.0000, NULL),
(21, 1, 21, 82, N'Áo thun oversize in chữ - Đen - M', 1, 4.0000, 80000.0000, 0.0000, NULL, 0.0000, 320000.00, 0.00, 320000.00, 4.0000, 0.0000, NULL),
(22, 1, 22, 83, N'Áo thun oversize in chữ - Đen - L', 1, 4.0000, 80000.0000, 0.0000, NULL, 0.0000, 320000.00, 0.00, 320000.00, 4.0000, 0.0000, NULL),
(23, 1, 23, 84, N'Áo thun oversize in chữ - Đen - XL', 1, 5.0000, 80000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 5.0000, 0.0000, NULL),
(24, 1, 24, 91, N'Áo khoác gió chống nắng - Hồng - Free size', 1, 3.0000, 120000.0000, 0.0000, NULL, 0.0000, 360000.00, 0.00, 360000.00, 3.0000, 0.0000, NULL),
(25, 1, 25, 102, N'Tất cổ ngắn (combo 3 đôi) - Trắng - Free size', 12, 4.0000, 28000.0000, 0.0000, NULL, 0.0000, 112000.00, 0.00, 112000.00, 4.0000, 0.0000, NULL),
(26, 1, 26, 103, N'Áo khoác gió chống nắng - Trắng - Free size', 1, 4.0000, 120000.0000, 0.0000, NULL, 0.0000, 480000.00, 0.00, 480000.00, 4.0000, 0.0000, NULL),
(27, 1, 27, 112, N'Áo thun oversize in chữ - Trắng - M', 1, 3.0000, 80000.0000, 0.0000, NULL, 0.0000, 240000.00, 0.00, 240000.00, 3.0000, 0.0000, NULL),
(28, 1, 28, 113, N'Áo thun oversize in chữ - Trắng - L', 1, 5.0000, 80000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 5.0000, 0.0000, NULL),
(29, 1, 29, 114, N'Áo thun oversize in chữ - Trắng - XL', 1, 4.0000, 80000.0000, 0.0000, NULL, 0.0000, 320000.00, 0.00, 320000.00, 4.0000, 0.0000, NULL),
(30, 1, 30, 115, N'Áo thun basic cổ tròn - Trắng - S', 1, 5.0000, 65000.0000, 0.0000, NULL, 0.0000, 325000.00, 0.00, 325000.00, 5.0000, 0.0000, NULL),
(31, 1, 31, 116, N'Áo thun basic cổ tròn - Trắng - M', 1, 3.0000, 65000.0000, 0.0000, NULL, 0.0000, 195000.00, 0.00, 195000.00, 3.0000, 0.0000, NULL),
(32, 1, 32, 117, N'Áo thun basic cổ tròn - Trắng - L', 1, 6.0000, 65000.0000, 0.0000, NULL, 0.0000, 390000.00, 0.00, 390000.00, 6.0000, 0.0000, NULL),
(33, 1, 33, 118, N'Áo thun basic cổ tròn - Trắng - XL', 1, 3.0000, 65000.0000, 0.0000, NULL, 0.0000, 195000.00, 0.00, 195000.00, 3.0000, 0.0000, NULL),
(34, 1, 34, 123, N'Áo polo pique - Trắng - M', 1, 3.0000, 105000.0000, 0.0000, NULL, 0.0000, 315000.00, 0.00, 315000.00, 3.0000, 0.0000, NULL),
(35, 1, 35, 124, N'Áo polo pique - Trắng - L', 1, 3.0000, 105000.0000, 0.0000, NULL, 0.0000, 315000.00, 0.00, 315000.00, 3.0000, 0.0000, NULL),
(36, 1, 36, 125, N'Áo polo pique - Trắng - XL', 1, 3.0000, 105000.0000, 0.0000, NULL, 0.0000, 315000.00, 0.00, 315000.00, 3.0000, 0.0000, NULL),
(37, 1, 37, 126, N'Áo polo pique - Trắng - XXL', 1, 4.0000, 105000.0000, 0.0000, NULL, 0.0000, 420000.00, 0.00, 420000.00, 4.0000, 0.0000, NULL),
(38, 1, 38, 130, N'Áo thun basic cổ tròn - Xám - S', 1, 6.0000, 65000.0000, 0.0000, NULL, 0.0000, 390000.00, 0.00, 390000.00, 6.0000, 0.0000, NULL),
(39, 1, 39, 131, N'Áo thun basic cổ tròn - Xám - M', 1, 4.0000, 65000.0000, 0.0000, NULL, 0.0000, 260000.00, 0.00, 260000.00, 4.0000, 0.0000, NULL),
(40, 1, 40, 132, N'Áo thun basic cổ tròn - Xám - L', 1, 4.0000, 65000.0000, 0.0000, NULL, 0.0000, 260000.00, 0.00, 260000.00, 4.0000, 0.0000, NULL),
(41, 1, 41, 133, N'Áo thun basic cổ tròn - Xám - XL', 1, 3.0000, 65000.0000, 0.0000, NULL, 0.0000, 195000.00, 0.00, 195000.00, 3.0000, 0.0000, NULL),
(42, 1, 42, 134, N'Quần short thể thao - Xám - M', 1, 3.0000, 70000.0000, 0.0000, NULL, 0.0000, 210000.00, 0.00, 210000.00, 3.0000, 0.0000, NULL),
(43, 1, 43, 135, N'Quần short thể thao - Xám - L', 1, 4.0000, 70000.0000, 0.0000, NULL, 0.0000, 280000.00, 0.00, 280000.00, 4.0000, 0.0000, NULL),
(44, 1, 44, 136, N'Quần short thể thao - Xám - XL', 1, 4.0000, 70000.0000, 0.0000, NULL, 0.0000, 280000.00, 0.00, 280000.00, 4.0000, 0.0000, NULL),
(45, 1, 45, 140, N'Áo khoác gió chống nắng - Xanh dương - Free size', 1, 3.0000, 120000.0000, 0.0000, NULL, 0.0000, 360000.00, 0.00, 360000.00, 3.0000, 0.0000, NULL),
(46, 1, 46, 150, N'Áo thun basic cổ tròn - Xanh navy - S', 1, 5.0000, 65000.0000, 0.0000, NULL, 0.0000, 325000.00, 0.00, 325000.00, 5.0000, 0.0000, NULL),
(47, 1, 47, 151, N'Áo thun basic cổ tròn - Xanh navy - M', 1, 3.0000, 65000.0000, 0.0000, NULL, 0.0000, 195000.00, 0.00, 195000.00, 3.0000, 0.0000, NULL),
(48, 1, 48, 152, N'Áo thun basic cổ tròn - Xanh navy - L', 1, 3.0000, 65000.0000, 0.0000, NULL, 0.0000, 195000.00, 0.00, 195000.00, 3.0000, 0.0000, NULL),
(49, 1, 49, 153, N'Áo thun basic cổ tròn - Xanh navy - XL', 1, 5.0000, 65000.0000, 0.0000, NULL, 0.0000, 325000.00, 0.00, 325000.00, 5.0000, 0.0000, NULL),
(50, 1, 50, 154, N'Áo polo pique - Xanh navy - M', 1, 3.0000, 105000.0000, 0.0000, NULL, 0.0000, 315000.00, 0.00, 315000.00, 3.0000, 0.0000, NULL),
(51, 1, 51, 155, N'Áo polo pique - Xanh navy - L', 1, 4.0000, 105000.0000, 0.0000, NULL, 0.0000, 420000.00, 0.00, 420000.00, 4.0000, 0.0000, NULL),
(52, 1, 52, 156, N'Áo polo pique - Xanh navy - XL', 1, 5.0000, 105000.0000, 0.0000, NULL, 0.0000, 525000.00, 0.00, 525000.00, 5.0000, 0.0000, NULL),
(53, 1, 53, 157, N'Áo polo pique - Xanh navy - XXL', 1, 3.0000, 105000.0000, 0.0000, NULL, 0.0000, 315000.00, 0.00, 315000.00, 3.0000, 0.0000, NULL),
(54, 1, 54, 162, N'Mũ lưỡi trai - Xanh navy - Free size', 1, 4.0000, 45000.0000, 0.0000, NULL, 0.0000, 180000.00, 0.00, 180000.00, 4.0000, 0.0000, NULL),
(55, 1, 55, 166, N'Áo khoác bomber - Xanh rêu - M', 1, 6.0000, 260000.0000, 0.0000, NULL, 0.0000, 1560000.00, 0.00, 1560000.00, 6.0000, 0.0000, NULL),
(56, 1, 56, 167, N'Áo khoác bomber - Xanh rêu - L', 1, 9.0000, 260000.0000, 0.0000, NULL, 0.0000, 2340000.00, 0.00, 2340000.00, 9.0000, 0.0000, NULL),
(57, 1, 57, 168, N'Áo khoác bomber - Xanh rêu - XL', 1, 4.0000, 260000.0000, 0.0000, NULL, 0.0000, 1040000.00, 0.00, 1040000.00, 4.0000, 0.0000, NULL),
(58, 2, 1, 4, N'Áo sơ mi nữ lụa - Be - S', 1, 8.0000, 150000.0000, 0.0000, NULL, 0.0000, 1200000.00, 0.00, 1200000.00, 8.0000, 0.0000, NULL),
(59, 2, 2, 5, N'Áo sơ mi nữ lụa - Be - M', 1, 12.0000, 150000.0000, 0.0000, NULL, 0.0000, 1800000.00, 0.00, 1800000.00, 12.0000, 0.0000, NULL),
(60, 2, 3, 6, N'Áo sơ mi nữ lụa - Be - L', 1, 12.0000, 150000.0000, 0.0000, NULL, 0.0000, 1800000.00, 0.00, 1800000.00, 12.0000, 0.0000, NULL),
(61, 2, 4, 7, N'Quần kaki chinos - Be - 29', 1, 5.0000, 165000.0000, 0.0000, NULL, 0.0000, 825000.00, 0.00, 825000.00, 5.0000, 0.0000, NULL),
(62, 2, 5, 8, N'Quần kaki chinos - Be - 30', 1, 11.0000, 165000.0000, 0.0000, NULL, 0.0000, 1815000.00, 0.00, 1815000.00, 11.0000, 0.0000, NULL),
(63, 2, 6, 9, N'Quần kaki chinos - Be - 31', 1, 16.0000, 165000.0000, 0.0000, NULL, 0.0000, 2640000.00, 0.00, 2640000.00, 16.0000, 0.0000, NULL),
(64, 2, 7, 10, N'Quần kaki chinos - Be - 32', 1, 1.0000, 165000.0000, 0.0000, NULL, 0.0000, 165000.00, 0.00, 165000.00, 1.0000, 0.0000, NULL),
(65, 2, 8, 11, N'Chân váy chữ A - Be - S', 1, 7.0000, 110000.0000, 0.0000, NULL, 0.0000, 770000.00, 0.00, 770000.00, 7.0000, 0.0000, NULL),
(66, 2, 9, 12, N'Chân váy chữ A - Be - M', 1, 8.0000, 110000.0000, 0.0000, NULL, 0.0000, 880000.00, 0.00, 880000.00, 8.0000, 0.0000, NULL),
(67, 2, 10, 13, N'Chân váy chữ A - Be - L', 1, 2.0000, 110000.0000, 0.0000, NULL, 0.0000, 220000.00, 0.00, 220000.00, 2.0000, 0.0000, NULL),
(68, 2, 11, 39, N'Túi xách nữ đeo chéo - Đen', 1, 14.0000, 190000.0000, 0.0000, NULL, 0.0000, 2660000.00, 0.00, 2660000.00, 14.0000, 0.0000, NULL),
(69, 2, 12, 43, N'Chân váy chữ A - Đen - S', 1, 2.0000, 110000.0000, 0.0000, NULL, 0.0000, 220000.00, 0.00, 220000.00, 2.0000, 0.0000, NULL),
(70, 2, 13, 44, N'Chân váy chữ A - Đen - M', 1, 11.0000, 110000.0000, 0.0000, NULL, 0.0000, 1210000.00, 0.00, 1210000.00, 11.0000, 0.0000, NULL),
(71, 2, 14, 45, N'Chân váy chữ A - Đen - L', 1, 8.0000, 110000.0000, 0.0000, NULL, 0.0000, 880000.00, 0.00, 880000.00, 8.0000, 0.0000, NULL),
(72, 2, 15, 59, N'Quần kaki chinos - Đen - 29', 1, 11.0000, 165000.0000, 0.0000, NULL, 0.0000, 1815000.00, 0.00, 1815000.00, 11.0000, 0.0000, NULL),
(73, 2, 16, 60, N'Quần kaki chinos - Đen - 30', 1, 1.0000, 165000.0000, 0.0000, NULL, 0.0000, 165000.00, 0.00, 165000.00, 1.0000, 0.0000, NULL),
(74, 2, 17, 61, N'Quần kaki chinos - Đen - 31', 1, 8.0000, 165000.0000, 0.0000, NULL, 0.0000, 1320000.00, 0.00, 1320000.00, 8.0000, 0.0000, NULL),
(75, 2, 18, 62, N'Quần kaki chinos - Đen - 32', 1, 13.0000, 165000.0000, 0.0000, NULL, 0.0000, 2145000.00, 0.00, 2145000.00, 13.0000, 0.0000, NULL),
(76, 2, 19, 85, N'Váy đầm hoa nhí - Hồng - S', 1, 9.0000, 160000.0000, 0.0000, NULL, 0.0000, 1440000.00, 0.00, 1440000.00, 9.0000, 0.0000, NULL),
(77, 2, 20, 86, N'Váy đầm hoa nhí - Hồng - M', 1, 14.0000, 160000.0000, 0.0000, NULL, 0.0000, 2240000.00, 0.00, 2240000.00, 14.0000, 0.0000, NULL),
(78, 2, 21, 87, N'Váy đầm hoa nhí - Hồng - L', 1, 7.0000, 160000.0000, 0.0000, NULL, 0.0000, 1120000.00, 0.00, 1120000.00, 7.0000, 0.0000, NULL),
(79, 2, 22, 88, N'Áo sơ mi nữ lụa - Hồng - S', 1, 8.0000, 150000.0000, 0.0000, NULL, 0.0000, 1200000.00, 0.00, 1200000.00, 8.0000, 0.0000, NULL),
(80, 2, 23, 89, N'Áo sơ mi nữ lụa - Hồng - M', 1, 11.0000, 150000.0000, 0.0000, NULL, 0.0000, 1650000.00, 0.00, 1650000.00, 11.0000, 0.0000, NULL),
(81, 2, 24, 90, N'Áo sơ mi nữ lụa - Hồng - L', 1, 2.0000, 150000.0000, 0.0000, NULL, 0.0000, 300000.00, 0.00, 300000.00, 2.0000, 0.0000, NULL),
(82, 2, 25, 92, N'Váy đầm hoa nhí - Kem - S', 1, 12.0000, 160000.0000, 0.0000, NULL, 0.0000, 1920000.00, 0.00, 1920000.00, 12.0000, 0.0000, NULL),
(83, 2, 26, 93, N'Váy đầm hoa nhí - Kem - M', 1, 2.0000, 160000.0000, 0.0000, NULL, 0.0000, 320000.00, 0.00, 320000.00, 2.0000, 0.0000, NULL),
(84, 2, 27, 94, N'Váy đầm hoa nhí - Kem - L', 1, 9.0000, 160000.0000, 0.0000, NULL, 0.0000, 1440000.00, 0.00, 1440000.00, 9.0000, 0.0000, NULL),
(85, 2, 28, 95, N'Túi xách nữ đeo chéo - Kem', 1, 9.0000, 190000.0000, 0.0000, NULL, 0.0000, 1710000.00, 0.00, 1710000.00, 9.0000, 0.0000, NULL),
(86, 2, 29, 96, N'Túi xách nữ đeo chéo - Nâu', 1, 13.0000, 190000.0000, 0.0000, NULL, 0.0000, 2470000.00, 0.00, 2470000.00, 13.0000, 0.0000, NULL),
(87, 2, 30, 119, N'Áo sơ mi trắng công sở - Trắng - S', 1, 11.0000, 140000.0000, 0.0000, NULL, 0.0000, 1540000.00, 0.00, 1540000.00, 11.0000, 0.0000, NULL),
(88, 2, 31, 120, N'Áo sơ mi trắng công sở - Trắng - M', 1, 7.0000, 140000.0000, 0.0000, NULL, 0.0000, 980000.00, 0.00, 980000.00, 7.0000, 0.0000, NULL),
(89, 2, 32, 121, N'Áo sơ mi trắng công sở - Trắng - L', 1, 7.0000, 140000.0000, 0.0000, NULL, 0.0000, 980000.00, 0.00, 980000.00, 7.0000, 0.0000, NULL),
(90, 2, 33, 122, N'Áo sơ mi trắng công sở - Trắng - XL', 1, 11.0000, 140000.0000, 0.0000, NULL, 0.0000, 1540000.00, 0.00, 1540000.00, 11.0000, 0.0000, NULL),
(91, 2, 34, 127, N'Áo sơ mi nữ lụa - Trắng - S', 1, 8.0000, 150000.0000, 0.0000, NULL, 0.0000, 1200000.00, 0.00, 1200000.00, 8.0000, 0.0000, NULL),
(92, 2, 35, 128, N'Áo sơ mi nữ lụa - Trắng - M', 1, 8.0000, 150000.0000, 0.0000, NULL, 0.0000, 1200000.00, 0.00, 1200000.00, 8.0000, 0.0000, NULL),
(93, 2, 36, 129, N'Áo sơ mi nữ lụa - Trắng - L', 1, 13.0000, 150000.0000, 0.0000, NULL, 0.0000, 1950000.00, 0.00, 1950000.00, 13.0000, 0.0000, NULL),
(94, 2, 37, 137, N'Váy đầm hoa nhí - Xanh dương - S', 1, 6.0000, 160000.0000, 0.0000, NULL, 0.0000, 960000.00, 0.00, 960000.00, 6.0000, 0.0000, NULL),
(95, 2, 38, 138, N'Váy đầm hoa nhí - Xanh dương - M', 1, 10.0000, 160000.0000, 0.0000, NULL, 0.0000, 1600000.00, 0.00, 1600000.00, 10.0000, 0.0000, NULL),
(96, 2, 39, 139, N'Váy đầm hoa nhí - Xanh dương - L', 1, 16.0000, 160000.0000, 0.0000, NULL, 0.0000, 2560000.00, 0.00, 2560000.00, 16.0000, 0.0000, NULL),
(97, 2, 40, 141, N'Áo sơ mi trắng công sở - Xanh dương - S', 1, 8.0000, 140000.0000, 0.0000, NULL, 0.0000, 1120000.00, 0.00, 1120000.00, 8.0000, 0.0000, NULL),
(98, 2, 41, 142, N'Áo sơ mi trắng công sở - Xanh dương - M', 1, 12.0000, 140000.0000, 0.0000, NULL, 0.0000, 1680000.00, 0.00, 1680000.00, 12.0000, 0.0000, NULL),
(99, 2, 42, 143, N'Áo sơ mi trắng công sở - Xanh dương - L', 1, 5.0000, 140000.0000, 0.0000, NULL, 0.0000, 700000.00, 0.00, 700000.00, 5.0000, 0.0000, NULL),
(100, 2, 43, 144, N'Áo sơ mi trắng công sở - Xanh dương - XL', 1, 6.0000, 140000.0000, 0.0000, NULL, 0.0000, 840000.00, 0.00, 840000.00, 6.0000, 0.0000, NULL),
(101, 2, 44, 158, N'Quần kaki chinos - Xanh navy - 29', 1, 10.0000, 165000.0000, 0.0000, NULL, 0.0000, 1650000.00, 0.00, 1650000.00, 10.0000, 0.0000, NULL),
(102, 2, 45, 159, N'Quần kaki chinos - Xanh navy - 30', 1, 14.0000, 165000.0000, 0.0000, NULL, 0.0000, 2310000.00, 0.00, 2310000.00, 14.0000, 0.0000, NULL),
(103, 2, 46, 160, N'Quần kaki chinos - Xanh navy - 31', 1, 1.0000, 165000.0000, 0.0000, NULL, 0.0000, 165000.00, 0.00, 165000.00, 1.0000, 0.0000, NULL),
(104, 2, 47, 161, N'Quần kaki chinos - Xanh navy - 32', 1, 8.0000, 165000.0000, 0.0000, NULL, 0.0000, 1320000.00, 0.00, 1320000.00, 8.0000, 0.0000, NULL),
(105, 3, 1, 63, N'Quần jeans nữ ống rộng - Đen - S', 1, 4.0000, 185000.0000, 0.0000, NULL, 0.0000, 740000.00, 0.00, 740000.00, 4.0000, 0.0000, NULL),
(106, 3, 2, 64, N'Quần jeans nữ ống rộng - Đen - M', 1, 3.0000, 185000.0000, 0.0000, NULL, 0.0000, 555000.00, 0.00, 555000.00, 3.0000, 0.0000, NULL),
(107, 3, 3, 65, N'Quần jeans nữ ống rộng - Đen - L', 1, 4.0000, 185000.0000, 0.0000, NULL, 0.0000, 740000.00, 0.00, 740000.00, 4.0000, 0.0000, NULL),
(108, 3, 4, 69, N'Quần jeans slim fit - Đen - 29', 1, 7.0000, 200000.0000, 0.0000, NULL, 0.0000, 1400000.00, 0.00, 1400000.00, 7.0000, 0.0000, NULL),
(109, 3, 5, 70, N'Quần jeans slim fit - Đen - 30', 1, 4.0000, 200000.0000, 0.0000, NULL, 0.0000, 800000.00, 0.00, 800000.00, 4.0000, 0.0000, NULL),
(110, 3, 6, 71, N'Quần jeans slim fit - Đen - 31', 1, 5.0000, 200000.0000, 0.0000, NULL, 0.0000, 1000000.00, 0.00, 1000000.00, 5.0000, 0.0000, NULL),
(111, 3, 7, 72, N'Quần jeans slim fit - Đen - 32', 1, 4.0000, 200000.0000, 0.0000, NULL, 0.0000, 800000.00, 0.00, 800000.00, 4.0000, 0.0000, NULL),
(112, 3, 8, 73, N'Quần jeans slim fit - Đen - 34', 1, 6.0000, 200000.0000, 0.0000, NULL, 0.0000, 1200000.00, 0.00, 1200000.00, 6.0000, 0.0000, NULL),
(113, 3, 9, 145, N'Quần jeans slim fit - Xanh jean - 29', 1, 3.0000, 200000.0000, 0.0000, NULL, 0.0000, 600000.00, 0.00, 600000.00, 3.0000, 0.0000, NULL),
(114, 3, 10, 146, N'Quần jeans slim fit - Xanh jean - 30', 1, 6.0000, 200000.0000, 0.0000, NULL, 0.0000, 1200000.00, 0.00, 1200000.00, 6.0000, 0.0000, NULL),
(115, 3, 11, 147, N'Quần jeans slim fit - Xanh jean - 31', 1, 3.0000, 200000.0000, 0.0000, NULL, 0.0000, 600000.00, 0.00, 600000.00, 3.0000, 0.0000, NULL),
(116, 3, 12, 148, N'Quần jeans slim fit - Xanh jean - 32', 1, 7.0000, 200000.0000, 0.0000, NULL, 0.0000, 1400000.00, 0.00, 1400000.00, 7.0000, 0.0000, NULL),
(117, 3, 13, 149, N'Quần jeans slim fit - Xanh jean - 34', 1, 3.0000, 200000.0000, 0.0000, NULL, 0.0000, 600000.00, 0.00, 600000.00, 3.0000, 0.0000, NULL),
(118, 3, 14, 163, N'Quần jeans nữ ống rộng - Xanh nhạt - S', 1, 3.0000, 185000.0000, 0.0000, NULL, 0.0000, 555000.00, 0.00, 555000.00, 3.0000, 0.0000, NULL),
(119, 3, 15, 164, N'Quần jeans nữ ống rộng - Xanh nhạt - M', 1, 3.0000, 185000.0000, 0.0000, NULL, 0.0000, 555000.00, 0.00, 555000.00, 3.0000, 0.0000, NULL),
(120, 3, 16, 165, N'Quần jeans nữ ống rộng - Xanh nhạt - L', 1, 5.0000, 185000.0000, 0.0000, NULL, 0.0000, 925000.00, 0.00, 925000.00, 5.0000, 0.0000, NULL),
(121, 4, 1, 14, N'Dép sandal quai ngang - Be - 37', 21, 5.0000, 95000.0000, 0.0000, NULL, 0.0000, 475000.00, 0.00, 475000.00, 5.0000, 0.0000, NULL),
(122, 4, 2, 15, N'Dép sandal quai ngang - Be - 38', 21, 3.0000, 95000.0000, 0.0000, NULL, 0.0000, 285000.00, 0.00, 285000.00, 3.0000, 0.0000, NULL),
(123, 4, 3, 16, N'Dép sandal quai ngang - Be - 39', 21, 3.0000, 95000.0000, 0.0000, NULL, 0.0000, 285000.00, 0.00, 285000.00, 3.0000, 0.0000, NULL),
(124, 4, 4, 17, N'Dép sandal quai ngang - Be - 40', 21, 5.0000, 95000.0000, 0.0000, NULL, 0.0000, 475000.00, 0.00, 475000.00, 5.0000, 0.0000, NULL),
(125, 4, 5, 18, N'Dép sandal quai ngang - Be - 41', 21, 3.0000, 95000.0000, 0.0000, NULL, 0.0000, 285000.00, 0.00, 285000.00, 3.0000, 0.0000, NULL),
(126, 4, 6, 19, N'Dép sandal quai ngang - Be - 42', 21, 3.0000, 95000.0000, 0.0000, NULL, 0.0000, 285000.00, 0.00, 285000.00, 3.0000, 0.0000, NULL),
(127, 4, 7, 20, N'Giày cao gót mũi nhọn - Be - 35', 21, 2.0000, 220000.0000, 0.0000, NULL, 0.0000, 440000.00, 0.00, 440000.00, 2.0000, 0.0000, NULL),
(128, 4, 8, 21, N'Giày cao gót mũi nhọn - Be - 36', 21, 4.0000, 220000.0000, 0.0000, NULL, 0.0000, 880000.00, 0.00, 880000.00, 4.0000, 0.0000, NULL),
(129, 4, 9, 22, N'Giày cao gót mũi nhọn - Be - 37', 21, 14.0000, 220000.0000, 0.0000, NULL, 0.0000, 3080000.00, 0.00, 3080000.00, 14.0000, 0.0000, NULL),
(130, 4, 10, 23, N'Giày cao gót mũi nhọn - Be - 38', 21, 2.0000, 220000.0000, 0.0000, NULL, 0.0000, 440000.00, 0.00, 440000.00, 2.0000, 0.0000, NULL),
(131, 4, 11, 24, N'Giày cao gót mũi nhọn - Be - 39', 21, 8.0000, 220000.0000, 0.0000, NULL, 0.0000, 1760000.00, 0.00, 1760000.00, 8.0000, 0.0000, NULL),
(132, 4, 12, 27, N'Giày tây da bò - Đen - 39', 21, 5.0000, 450000.0000, 0.0000, NULL, 0.0000, 2250000.00, 0.00, 2250000.00, 5.0000, 0.0000, NULL),
(133, 4, 13, 28, N'Giày tây da bò - Đen - 40', 21, 4.0000, 450000.0000, 0.0000, NULL, 0.0000, 1800000.00, 0.00, 1800000.00, 4.0000, 0.0000, NULL),
(134, 4, 14, 29, N'Giày tây da bò - Đen - 41', 21, 10.0000, 450000.0000, 0.0000, NULL, 0.0000, 4500000.00, 0.00, 4500000.00, 10.0000, 0.0000, NULL),
(135, 4, 15, 30, N'Giày tây da bò - Đen - 42', 21, 1.0000, 450000.0000, 0.0000, NULL, 0.0000, 450000.00, 0.00, 450000.00, 1.0000, 0.0000, NULL),
(136, 4, 16, 31, N'Giày tây da bò - Đen - 43', 21, 10.0000, 450000.0000, 0.0000, NULL, 0.0000, 4500000.00, 0.00, 4500000.00, 10.0000, 0.0000, NULL),
(137, 4, 17, 32, N'Dép sandal quai ngang - Đen - 37', 21, 5.0000, 95000.0000, 0.0000, NULL, 0.0000, 475000.00, 0.00, 475000.00, 5.0000, 0.0000, NULL),
(138, 4, 18, 33, N'Dép sandal quai ngang - Đen - 38', 21, 3.0000, 95000.0000, 0.0000, NULL, 0.0000, 285000.00, 0.00, 285000.00, 3.0000, 0.0000, NULL),
(139, 4, 19, 34, N'Dép sandal quai ngang - Đen - 39', 21, 5.0000, 95000.0000, 0.0000, NULL, 0.0000, 475000.00, 0.00, 475000.00, 5.0000, 0.0000, NULL),
(140, 4, 20, 35, N'Dép sandal quai ngang - Đen - 40', 21, 3.0000, 95000.0000, 0.0000, NULL, 0.0000, 285000.00, 0.00, 285000.00, 3.0000, 0.0000, NULL),
(141, 4, 21, 36, N'Dép sandal quai ngang - Đen - 41', 21, 5.0000, 95000.0000, 0.0000, NULL, 0.0000, 475000.00, 0.00, 475000.00, 5.0000, 0.0000, NULL),
(142, 4, 22, 37, N'Dép sandal quai ngang - Đen - 42', 21, 3.0000, 95000.0000, 0.0000, NULL, 0.0000, 285000.00, 0.00, 285000.00, 3.0000, 0.0000, NULL),
(143, 4, 23, 46, N'Giày sneaker trắng - Đen - 36', 21, 3.0000, 310000.0000, 0.0000, NULL, 0.0000, 930000.00, 0.00, 930000.00, 3.0000, 0.0000, NULL),
(144, 4, 24, 47, N'Giày sneaker trắng - Đen - 37', 21, 6.0000, 310000.0000, 0.0000, NULL, 0.0000, 1860000.00, 0.00, 1860000.00, 6.0000, 0.0000, NULL),
(145, 4, 25, 48, N'Giày sneaker trắng - Đen - 38', 21, 3.0000, 310000.0000, 0.0000, NULL, 0.0000, 930000.00, 0.00, 930000.00, 3.0000, 0.0000, NULL),
(146, 4, 26, 49, N'Giày sneaker trắng - Đen - 39', 21, 3.0000, 310000.0000, 0.0000, NULL, 0.0000, 930000.00, 0.00, 930000.00, 3.0000, 0.0000, NULL),
(147, 4, 27, 50, N'Giày sneaker trắng - Đen - 40', 21, 4.0000, 310000.0000, 0.0000, NULL, 0.0000, 1240000.00, 0.00, 1240000.00, 4.0000, 0.0000, NULL),
(148, 4, 28, 51, N'Giày sneaker trắng - Đen - 41', 21, 3.0000, 310000.0000, 0.0000, NULL, 0.0000, 930000.00, 0.00, 930000.00, 3.0000, 0.0000, NULL),
(149, 4, 29, 52, N'Giày sneaker trắng - Đen - 42', 21, 3.0000, 310000.0000, 0.0000, NULL, 0.0000, 930000.00, 0.00, 930000.00, 3.0000, 0.0000, NULL),
(150, 4, 30, 53, N'Giày sneaker trắng - Đen - 43', 21, 3.0000, 310000.0000, 0.0000, NULL, 0.0000, 930000.00, 0.00, 930000.00, 3.0000, 0.0000, NULL),
(151, 4, 31, 54, N'Giày cao gót mũi nhọn - Đen - 35', 21, 6.0000, 220000.0000, 0.0000, NULL, 0.0000, 1320000.00, 0.00, 1320000.00, 6.0000, 0.0000, NULL),
(152, 4, 32, 55, N'Giày cao gót mũi nhọn - Đen - 36', 21, 5.0000, 220000.0000, 0.0000, NULL, 0.0000, 1100000.00, 0.00, 1100000.00, 5.0000, 0.0000, NULL),
(153, 4, 33, 56, N'Giày cao gót mũi nhọn - Đen - 37', 21, 5.0000, 220000.0000, 0.0000, NULL, 0.0000, 1100000.00, 0.00, 1100000.00, 5.0000, 0.0000, NULL),
(154, 4, 34, 57, N'Giày cao gót mũi nhọn - Đen - 38', 21, 10.0000, 220000.0000, 0.0000, NULL, 0.0000, 2200000.00, 0.00, 2200000.00, 10.0000, 0.0000, NULL),
(155, 4, 35, 58, N'Giày cao gót mũi nhọn - Đen - 39', 21, 12.0000, 220000.0000, 0.0000, NULL, 0.0000, 2640000.00, 0.00, 2640000.00, 12.0000, 0.0000, NULL),
(156, 4, 36, 97, N'Giày tây da bò - Nâu - 39', 21, 7.0000, 450000.0000, 0.0000, NULL, 0.0000, 3150000.00, 0.00, 3150000.00, 7.0000, 0.0000, NULL),
(157, 4, 37, 98, N'Giày tây da bò - Nâu - 40', 21, 4.0000, 450000.0000, 0.0000, NULL, 0.0000, 1800000.00, 0.00, 1800000.00, 4.0000, 0.0000, NULL),
(158, 4, 38, 99, N'Giày tây da bò - Nâu - 41', 21, 13.0000, 450000.0000, 0.0000, NULL, 0.0000, 5850000.00, 0.00, 5850000.00, 13.0000, 0.0000, NULL),
(159, 4, 39, 100, N'Giày tây da bò - Nâu - 42', 21, 1.0000, 450000.0000, 0.0000, NULL, 0.0000, 450000.00, 0.00, 450000.00, 1.0000, 0.0000, NULL),
(160, 4, 40, 101, N'Giày tây da bò - Nâu - 43', 21, 8.0000, 450000.0000, 0.0000, NULL, 0.0000, 3600000.00, 0.00, 3600000.00, 8.0000, 0.0000, NULL),
(161, 4, 41, 104, N'Giày sneaker trắng - Trắng - 36', 21, 4.0000, 310000.0000, 0.0000, NULL, 0.0000, 1240000.00, 0.00, 1240000.00, 4.0000, 0.0000, NULL),
(162, 4, 42, 105, N'Giày sneaker trắng - Trắng - 37', 21, 3.0000, 310000.0000, 0.0000, NULL, 0.0000, 930000.00, 0.00, 930000.00, 3.0000, 0.0000, NULL),
(163, 4, 43, 106, N'Giày sneaker trắng - Trắng - 38', 21, 7.0000, 310000.0000, 0.0000, NULL, 0.0000, 2170000.00, 0.00, 2170000.00, 7.0000, 0.0000, NULL),
(164, 4, 44, 107, N'Giày sneaker trắng - Trắng - 39', 21, 4.0000, 310000.0000, 0.0000, NULL, 0.0000, 1240000.00, 0.00, 1240000.00, 4.0000, 0.0000, NULL),
(165, 4, 45, 108, N'Giày sneaker trắng - Trắng - 40', 21, 5.0000, 310000.0000, 0.0000, NULL, 0.0000, 1550000.00, 0.00, 1550000.00, 5.0000, 0.0000, NULL),
(166, 4, 46, 109, N'Giày sneaker trắng - Trắng - 41', 21, 4.0000, 310000.0000, 0.0000, NULL, 0.0000, 1240000.00, 0.00, 1240000.00, 4.0000, 0.0000, NULL),
(167, 4, 47, 110, N'Giày sneaker trắng - Trắng - 42', 21, 6.0000, 310000.0000, 0.0000, NULL, 0.0000, 1860000.00, 0.00, 1860000.00, 6.0000, 0.0000, NULL),
(168, 4, 48, 111, N'Giày sneaker trắng - Trắng - 43', 21, 3.0000, 310000.0000, 0.0000, NULL, 0.0000, 930000.00, 0.00, 930000.00, 3.0000, 0.0000, NULL),
(169, 5, 1, 1, N'Áo thun oversize in chữ - Be - M', 1, 2.0000, 80000.0000, 0.0000, NULL, 0.0000, 160000.00, 0.00, 160000.00, 2.0000, 0.0000, NULL),
(170, 5, 2, 2, N'Áo thun oversize in chữ - Be - L', 1, 5.0000, 80000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 5.0000, 0.0000, NULL),
(171, 5, 3, 3, N'Áo thun oversize in chữ - Be - XL', 1, 2.0000, 80000.0000, 0.0000, NULL, 0.0000, 160000.00, 0.00, 160000.00, 2.0000, 0.0000, NULL),
(172, 5, 4, 25, N'Mũ lưỡi trai - Be - Free size', 1, 6.0000, 45000.0000, 0.0000, NULL, 0.0000, 270000.00, 0.00, 270000.00, 6.0000, 0.0000, NULL),
(173, 5, 5, 26, N'Tất cổ ngắn (combo 3 đôi) - Đen - Free size', 12, 3.0000, 28000.0000, 0.0000, NULL, 0.0000, 84000.00, 0.00, 84000.00, 3.0000, 0.0000, NULL),
(174, 5, 6, 38, N'Mũ lưỡi trai - Đen - Free size', 1, 6.0000, 45000.0000, 0.0000, NULL, 0.0000, 270000.00, 0.00, 270000.00, 6.0000, 0.0000, NULL),
(175, 5, 7, 66, N'Quần short thể thao - Đen - M', 1, 9.0000, 70000.0000, 0.0000, NULL, 0.0000, 630000.00, 0.00, 630000.00, 9.0000, 0.0000, NULL),
(176, 5, 8, 67, N'Quần short thể thao - Đen - L', 1, 2.0000, 70000.0000, 0.0000, NULL, 0.0000, 140000.00, 0.00, 140000.00, 2.0000, 0.0000, NULL),
(177, 5, 9, 68, N'Quần short thể thao - Đen - XL', 1, 8.0000, 70000.0000, 0.0000, NULL, 0.0000, 560000.00, 0.00, 560000.00, 8.0000, 0.0000, NULL),
(178, 5, 10, 74, N'Áo thun basic cổ tròn - Đen - S', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(179, 5, 11, 75, N'Áo thun basic cổ tròn - Đen - M', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(180, 5, 12, 76, N'Áo thun basic cổ tròn - Đen - L', 1, 4.0000, 65000.0000, 0.0000, NULL, 0.0000, 260000.00, 0.00, 260000.00, 4.0000, 0.0000, NULL),
(181, 5, 13, 77, N'Áo thun basic cổ tròn - Đen - XL', 1, 4.0000, 65000.0000, 0.0000, NULL, 0.0000, 260000.00, 0.00, 260000.00, 4.0000, 0.0000, NULL),
(182, 5, 14, 78, N'Áo polo pique - Đen - M', 1, 7.0000, 105000.0000, 0.0000, NULL, 0.0000, 735000.00, 0.00, 735000.00, 7.0000, 0.0000, NULL),
(183, 5, 15, 79, N'Áo polo pique - Đen - L', 1, 8.0000, 105000.0000, 0.0000, NULL, 0.0000, 840000.00, 0.00, 840000.00, 8.0000, 0.0000, NULL),
(184, 5, 16, 80, N'Áo polo pique - Đen - XL', 1, 2.0000, 105000.0000, 0.0000, NULL, 0.0000, 210000.00, 0.00, 210000.00, 2.0000, 0.0000, NULL),
(185, 5, 17, 81, N'Áo polo pique - Đen - XXL', 1, 5.0000, 105000.0000, 0.0000, NULL, 0.0000, 525000.00, 0.00, 525000.00, 5.0000, 0.0000, NULL),
(186, 5, 18, 82, N'Áo thun oversize in chữ - Đen - M', 1, 3.0000, 80000.0000, 0.0000, NULL, 0.0000, 240000.00, 0.00, 240000.00, 3.0000, 0.0000, NULL),
(187, 5, 19, 83, N'Áo thun oversize in chữ - Đen - L', 1, 2.0000, 80000.0000, 0.0000, NULL, 0.0000, 160000.00, 0.00, 160000.00, 2.0000, 0.0000, NULL),
(188, 5, 20, 84, N'Áo thun oversize in chữ - Đen - XL', 1, 5.0000, 80000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 5.0000, 0.0000, NULL),
(189, 5, 21, 91, N'Áo khoác gió chống nắng - Hồng - Free size', 1, 6.0000, 120000.0000, 0.0000, NULL, 0.0000, 720000.00, 0.00, 720000.00, 6.0000, 0.0000, NULL),
(190, 5, 22, 102, N'Tất cổ ngắn (combo 3 đôi) - Trắng - Free size', 12, 3.0000, 28000.0000, 0.0000, NULL, 0.0000, 84000.00, 0.00, 84000.00, 3.0000, 0.0000, NULL),
(191, 5, 23, 103, N'Áo khoác gió chống nắng - Trắng - Free size', 1, 2.0000, 120000.0000, 0.0000, NULL, 0.0000, 240000.00, 0.00, 240000.00, 2.0000, 0.0000, NULL),
(192, 5, 24, 112, N'Áo thun oversize in chữ - Trắng - M', 1, 3.0000, 80000.0000, 0.0000, NULL, 0.0000, 240000.00, 0.00, 240000.00, 3.0000, 0.0000, NULL),
(193, 5, 25, 113, N'Áo thun oversize in chữ - Trắng - L', 1, 2.0000, 80000.0000, 0.0000, NULL, 0.0000, 160000.00, 0.00, 160000.00, 2.0000, 0.0000, NULL),
(194, 5, 26, 114, N'Áo thun oversize in chữ - Trắng - XL', 1, 2.0000, 80000.0000, 0.0000, NULL, 0.0000, 160000.00, 0.00, 160000.00, 2.0000, 0.0000, NULL),
(195, 5, 27, 115, N'Áo thun basic cổ tròn - Trắng - S', 1, 3.0000, 65000.0000, 0.0000, NULL, 0.0000, 195000.00, 0.00, 195000.00, 3.0000, 0.0000, NULL),
(196, 5, 28, 116, N'Áo thun basic cổ tròn - Trắng - M', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(197, 5, 29, 117, N'Áo thun basic cổ tròn - Trắng - L', 1, 4.0000, 65000.0000, 0.0000, NULL, 0.0000, 260000.00, 0.00, 260000.00, 4.0000, 0.0000, NULL),
(198, 5, 30, 118, N'Áo thun basic cổ tròn - Trắng - XL', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(199, 5, 31, 123, N'Áo polo pique - Trắng - M', 1, 2.0000, 105000.0000, 0.0000, NULL, 0.0000, 210000.00, 0.00, 210000.00, 2.0000, 0.0000, NULL),
(200, 5, 32, 124, N'Áo polo pique - Trắng - L', 1, 6.0000, 105000.0000, 0.0000, NULL, 0.0000, 630000.00, 0.00, 630000.00, 6.0000, 0.0000, NULL),
(201, 5, 33, 125, N'Áo polo pique - Trắng - XL', 1, 7.0000, 105000.0000, 0.0000, NULL, 0.0000, 735000.00, 0.00, 735000.00, 7.0000, 0.0000, NULL),
(202, 5, 34, 126, N'Áo polo pique - Trắng - XXL', 1, 9.0000, 105000.0000, 0.0000, NULL, 0.0000, 945000.00, 0.00, 945000.00, 9.0000, 0.0000, NULL),
(203, 5, 35, 130, N'Áo thun basic cổ tròn - Xám - S', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(204, 5, 36, 131, N'Áo thun basic cổ tròn - Xám - M', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(205, 5, 37, 132, N'Áo thun basic cổ tròn - Xám - L', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(206, 5, 38, 133, N'Áo thun basic cổ tròn - Xám - XL', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(207, 5, 39, 134, N'Quần short thể thao - Xám - M', 1, 4.0000, 70000.0000, 0.0000, NULL, 0.0000, 280000.00, 0.00, 280000.00, 4.0000, 0.0000, NULL),
(208, 5, 40, 135, N'Quần short thể thao - Xám - L', 1, 8.0000, 70000.0000, 0.0000, NULL, 0.0000, 560000.00, 0.00, 560000.00, 8.0000, 0.0000, NULL),
(209, 5, 41, 136, N'Quần short thể thao - Xám - XL', 1, 11.0000, 70000.0000, 0.0000, NULL, 0.0000, 770000.00, 0.00, 770000.00, 11.0000, 0.0000, NULL),
(210, 5, 42, 140, N'Áo khoác gió chống nắng - Xanh dương - Free size', 1, 2.0000, 120000.0000, 0.0000, NULL, 0.0000, 240000.00, 0.00, 240000.00, 2.0000, 0.0000, NULL),
(211, 5, 43, 150, N'Áo thun basic cổ tròn - Xanh navy - S', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(212, 5, 44, 151, N'Áo thun basic cổ tròn - Xanh navy - M', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(213, 5, 45, 152, N'Áo thun basic cổ tròn - Xanh navy - L', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(214, 5, 46, 153, N'Áo thun basic cổ tròn - Xanh navy - XL', 1, 2.0000, 65000.0000, 0.0000, NULL, 0.0000, 130000.00, 0.00, 130000.00, 2.0000, 0.0000, NULL),
(215, 5, 47, 154, N'Áo polo pique - Xanh navy - M', 1, 5.0000, 105000.0000, 0.0000, NULL, 0.0000, 525000.00, 0.00, 525000.00, 5.0000, 0.0000, NULL),
(216, 5, 48, 155, N'Áo polo pique - Xanh navy - L', 1, 6.0000, 105000.0000, 0.0000, NULL, 0.0000, 630000.00, 0.00, 630000.00, 6.0000, 0.0000, NULL),
(217, 5, 49, 156, N'Áo polo pique - Xanh navy - XL', 1, 12.0000, 105000.0000, 0.0000, NULL, 0.0000, 1260000.00, 0.00, 1260000.00, 12.0000, 0.0000, NULL),
(218, 5, 50, 157, N'Áo polo pique - Xanh navy - XXL', 1, 3.0000, 105000.0000, 0.0000, NULL, 0.0000, 315000.00, 0.00, 315000.00, 3.0000, 0.0000, NULL),
(219, 5, 51, 162, N'Mũ lưỡi trai - Xanh navy - Free size', 1, 8.0000, 45000.0000, 0.0000, NULL, 0.0000, 360000.00, 0.00, 360000.00, 8.0000, 0.0000, NULL),
(220, 6, 1, 63, N'Quần jeans nữ ống rộng - Đen - S', 1, 2.0000, 185000.0000, 0.0000, NULL, 0.0000, 370000.00, 0.00, 370000.00, 2.0000, 0.0000, NULL),
(221, 6, 2, 64, N'Quần jeans nữ ống rộng - Đen - M', 1, 4.0000, 185000.0000, 0.0000, NULL, 0.0000, 740000.00, 0.00, 740000.00, 4.0000, 0.0000, NULL),
(222, 6, 3, 65, N'Quần jeans nữ ống rộng - Đen - L', 1, 6.0000, 185000.0000, 0.0000, NULL, 0.0000, 1110000.00, 0.00, 1110000.00, 6.0000, 0.0000, NULL),
(223, 6, 4, 69, N'Quần jeans slim fit - Đen - 29', 1, 2.0000, 200000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 2.0000, 0.0000, NULL),
(224, 6, 5, 70, N'Quần jeans slim fit - Đen - 30', 1, 2.0000, 200000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 2.0000, 0.0000, NULL),
(225, 6, 6, 71, N'Quần jeans slim fit - Đen - 31', 1, 2.0000, 200000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 2.0000, 0.0000, NULL),
(226, 6, 7, 72, N'Quần jeans slim fit - Đen - 32', 1, 2.0000, 200000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 2.0000, 0.0000, NULL),
(227, 6, 8, 73, N'Quần jeans slim fit - Đen - 34', 1, 2.0000, 200000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 2.0000, 0.0000, NULL),
(228, 6, 9, 145, N'Quần jeans slim fit - Xanh jean - 29', 1, 2.0000, 200000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 2.0000, 0.0000, NULL),
(229, 6, 10, 146, N'Quần jeans slim fit - Xanh jean - 30', 1, 2.0000, 200000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 2.0000, 0.0000, NULL),
(230, 6, 11, 147, N'Quần jeans slim fit - Xanh jean - 31', 1, 2.0000, 200000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 2.0000, 0.0000, NULL),
(231, 6, 12, 148, N'Quần jeans slim fit - Xanh jean - 32', 1, 2.0000, 200000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 2.0000, 0.0000, NULL),
(232, 6, 13, 149, N'Quần jeans slim fit - Xanh jean - 34', 1, 2.0000, 200000.0000, 0.0000, NULL, 0.0000, 400000.00, 0.00, 400000.00, 2.0000, 0.0000, NULL),
(233, 6, 14, 163, N'Quần jeans nữ ống rộng - Xanh nhạt - S', 1, 2.0000, 185000.0000, 0.0000, NULL, 0.0000, 370000.00, 0.00, 370000.00, 2.0000, 0.0000, NULL),
(234, 6, 15, 164, N'Quần jeans nữ ống rộng - Xanh nhạt - M', 1, 4.0000, 185000.0000, 0.0000, NULL, 0.0000, 740000.00, 0.00, 740000.00, 4.0000, 0.0000, NULL),
(235, 6, 16, 165, N'Quần jeans nữ ống rộng - Xanh nhạt - L', 1, 8.0000, 185000.0000, 0.0000, NULL, 0.0000, 1480000.00, 0.00, 1480000.00, 8.0000, 0.0000, NULL),
(236, 7, 1, 14, N'Dép sandal quai ngang - Be - 37', 21, 4.0000, 95000.0000, 0.0000, NULL, 0.0000, 380000.00, 0.00, 380000.00, 4.0000, 0.0000, NULL),
(237, 7, 2, 15, N'Dép sandal quai ngang - Be - 38', 21, 6.0000, 95000.0000, 0.0000, NULL, 0.0000, 570000.00, 0.00, 570000.00, 6.0000, 0.0000, NULL),
(238, 7, 3, 16, N'Dép sandal quai ngang - Be - 39', 21, 10.0000, 95000.0000, 0.0000, NULL, 0.0000, 950000.00, 0.00, 950000.00, 10.0000, 0.0000, NULL),
(239, 7, 4, 17, N'Dép sandal quai ngang - Be - 40', 21, 2.0000, 95000.0000, 0.0000, NULL, 0.0000, 190000.00, 0.00, 190000.00, 2.0000, 0.0000, NULL),
(240, 7, 5, 18, N'Dép sandal quai ngang - Be - 41', 21, 5.0000, 95000.0000, 0.0000, NULL, 0.0000, 475000.00, 0.00, 475000.00, 5.0000, 0.0000, NULL),
(241, 7, 6, 19, N'Dép sandal quai ngang - Be - 42', 21, 8.0000, 95000.0000, 0.0000, NULL, 0.0000, 760000.00, 0.00, 760000.00, 8.0000, 0.0000, NULL),
(242, 7, 7, 32, N'Dép sandal quai ngang - Đen - 37', 21, 8.0000, 95000.0000, 0.0000, NULL, 0.0000, 760000.00, 0.00, 760000.00, 8.0000, 0.0000, NULL),
(243, 7, 8, 33, N'Dép sandal quai ngang - Đen - 38', 21, 2.0000, 95000.0000, 0.0000, NULL, 0.0000, 190000.00, 0.00, 190000.00, 2.0000, 0.0000, NULL),
(244, 7, 9, 34, N'Dép sandal quai ngang - Đen - 39', 21, 4.0000, 95000.0000, 0.0000, NULL, 0.0000, 380000.00, 0.00, 380000.00, 4.0000, 0.0000, NULL),
(245, 7, 10, 35, N'Dép sandal quai ngang - Đen - 40', 21, 9.0000, 95000.0000, 0.0000, NULL, 0.0000, 855000.00, 0.00, 855000.00, 9.0000, 0.0000, NULL),
(246, 7, 11, 36, N'Dép sandal quai ngang - Đen - 41', 21, 12.0000, 95000.0000, 0.0000, NULL, 0.0000, 1140000.00, 0.00, 1140000.00, 12.0000, 0.0000, NULL),
(247, 7, 12, 37, N'Dép sandal quai ngang - Đen - 42', 21, 2.0000, 95000.0000, 0.0000, NULL, 0.0000, 190000.00, 0.00, 190000.00, 2.0000, 0.0000, NULL),
(248, 7, 13, 46, N'Giày sneaker trắng - Đen - 36', 21, 4.0000, 310000.0000, 0.0000, NULL, 0.0000, 1240000.00, 0.00, 1240000.00, 4.0000, 0.0000, NULL),
(249, 7, 14, 47, N'Giày sneaker trắng - Đen - 37', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(250, 7, 15, 48, N'Giày sneaker trắng - Đen - 38', 21, 5.0000, 310000.0000, 0.0000, NULL, 0.0000, 1550000.00, 0.00, 1550000.00, 5.0000, 0.0000, NULL),
(251, 7, 16, 49, N'Giày sneaker trắng - Đen - 39', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(252, 7, 17, 50, N'Giày sneaker trắng - Đen - 40', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(253, 7, 18, 51, N'Giày sneaker trắng - Đen - 41', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(254, 7, 19, 52, N'Giày sneaker trắng - Đen - 42', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(255, 7, 20, 53, N'Giày sneaker trắng - Đen - 43', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(256, 7, 21, 104, N'Giày sneaker trắng - Trắng - 36', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(257, 7, 22, 105, N'Giày sneaker trắng - Trắng - 37', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(258, 7, 23, 106, N'Giày sneaker trắng - Trắng - 38', 21, 3.0000, 310000.0000, 0.0000, NULL, 0.0000, 930000.00, 0.00, 930000.00, 3.0000, 0.0000, NULL),
(259, 7, 24, 107, N'Giày sneaker trắng - Trắng - 39', 21, 3.0000, 310000.0000, 0.0000, NULL, 0.0000, 930000.00, 0.00, 930000.00, 3.0000, 0.0000, NULL),
(260, 7, 25, 108, N'Giày sneaker trắng - Trắng - 40', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(261, 7, 26, 109, N'Giày sneaker trắng - Trắng - 41', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(262, 7, 27, 110, N'Giày sneaker trắng - Trắng - 42', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(263, 7, 28, 111, N'Giày sneaker trắng - Trắng - 43', 21, 2.0000, 310000.0000, 0.0000, NULL, 0.0000, 620000.00, 0.00, 620000.00, 2.0000, 0.0000, NULL),
(264, 8, 1, 4, N'Áo sơ mi nữ lụa - Be - S', 1, 6.0000, 150000.0000, 0.0000, NULL, 0.0000, 900000.00, 0.00, 900000.00, 0.0000, 0.0000, NULL),
(265, 8, 2, 5, N'Áo sơ mi nữ lụa - Be - M', 1, 6.0000, 150000.0000, 0.0000, NULL, 0.0000, 900000.00, 0.00, 900000.00, 0.0000, 0.0000, NULL),
(266, 8, 3, 6, N'Áo sơ mi nữ lụa - Be - L', 1, 6.0000, 150000.0000, 0.0000, NULL, 0.0000, 900000.00, 0.00, 900000.00, 0.0000, 0.0000, NULL),
(267, 8, 4, 7, N'Quần kaki chinos - Be - 29', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(268, 8, 5, 8, N'Quần kaki chinos - Be - 30', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(269, 8, 6, 9, N'Quần kaki chinos - Be - 31', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(270, 8, 7, 10, N'Quần kaki chinos - Be - 32', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(271, 8, 8, 39, N'Túi xách nữ đeo chéo - Đen', 1, 6.0000, 190000.0000, 0.0000, NULL, 0.0000, 1140000.00, 0.00, 1140000.00, 0.0000, 0.0000, NULL),
(272, 8, 9, 59, N'Quần kaki chinos - Đen - 29', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(273, 8, 10, 60, N'Quần kaki chinos - Đen - 30', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(274, 8, 11, 61, N'Quần kaki chinos - Đen - 31', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(275, 8, 12, 62, N'Quần kaki chinos - Đen - 32', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(276, 8, 13, 85, N'Váy đầm hoa nhí - Hồng - S', 1, 6.0000, 160000.0000, 0.0000, NULL, 0.0000, 960000.00, 0.00, 960000.00, 0.0000, 0.0000, NULL),
(277, 8, 14, 86, N'Váy đầm hoa nhí - Hồng - M', 1, 6.0000, 160000.0000, 0.0000, NULL, 0.0000, 960000.00, 0.00, 960000.00, 0.0000, 0.0000, NULL),
(278, 8, 15, 87, N'Váy đầm hoa nhí - Hồng - L', 1, 6.0000, 160000.0000, 0.0000, NULL, 0.0000, 960000.00, 0.00, 960000.00, 0.0000, 0.0000, NULL),
(279, 8, 16, 88, N'Áo sơ mi nữ lụa - Hồng - S', 1, 6.0000, 150000.0000, 0.0000, NULL, 0.0000, 900000.00, 0.00, 900000.00, 0.0000, 0.0000, NULL),
(280, 8, 17, 89, N'Áo sơ mi nữ lụa - Hồng - M', 1, 6.0000, 150000.0000, 0.0000, NULL, 0.0000, 900000.00, 0.00, 900000.00, 0.0000, 0.0000, NULL),
(281, 8, 18, 90, N'Áo sơ mi nữ lụa - Hồng - L', 1, 6.0000, 150000.0000, 0.0000, NULL, 0.0000, 900000.00, 0.00, 900000.00, 0.0000, 0.0000, NULL),
(282, 8, 19, 92, N'Váy đầm hoa nhí - Kem - S', 1, 6.0000, 160000.0000, 0.0000, NULL, 0.0000, 960000.00, 0.00, 960000.00, 0.0000, 0.0000, NULL),
(283, 8, 20, 93, N'Váy đầm hoa nhí - Kem - M', 1, 6.0000, 160000.0000, 0.0000, NULL, 0.0000, 960000.00, 0.00, 960000.00, 0.0000, 0.0000, NULL),
(284, 8, 21, 94, N'Váy đầm hoa nhí - Kem - L', 1, 6.0000, 160000.0000, 0.0000, NULL, 0.0000, 960000.00, 0.00, 960000.00, 0.0000, 0.0000, NULL),
(285, 8, 22, 95, N'Túi xách nữ đeo chéo - Kem', 1, 6.0000, 190000.0000, 0.0000, NULL, 0.0000, 1140000.00, 0.00, 1140000.00, 0.0000, 0.0000, NULL),
(286, 8, 23, 96, N'Túi xách nữ đeo chéo - Nâu', 1, 6.0000, 190000.0000, 0.0000, NULL, 0.0000, 1140000.00, 0.00, 1140000.00, 0.0000, 0.0000, NULL),
(287, 8, 24, 119, N'Áo sơ mi trắng công sở - Trắng - S', 1, 6.0000, 140000.0000, 0.0000, NULL, 0.0000, 840000.00, 0.00, 840000.00, 0.0000, 0.0000, NULL),
(288, 8, 25, 120, N'Áo sơ mi trắng công sở - Trắng - M', 1, 6.0000, 140000.0000, 0.0000, NULL, 0.0000, 840000.00, 0.00, 840000.00, 0.0000, 0.0000, NULL),
(289, 8, 26, 121, N'Áo sơ mi trắng công sở - Trắng - L', 1, 6.0000, 140000.0000, 0.0000, NULL, 0.0000, 840000.00, 0.00, 840000.00, 0.0000, 0.0000, NULL),
(290, 8, 27, 122, N'Áo sơ mi trắng công sở - Trắng - XL', 1, 6.0000, 140000.0000, 0.0000, NULL, 0.0000, 840000.00, 0.00, 840000.00, 0.0000, 0.0000, NULL),
(291, 8, 28, 127, N'Áo sơ mi nữ lụa - Trắng - S', 1, 6.0000, 150000.0000, 0.0000, NULL, 0.0000, 900000.00, 0.00, 900000.00, 0.0000, 0.0000, NULL),
(292, 8, 29, 128, N'Áo sơ mi nữ lụa - Trắng - M', 1, 6.0000, 150000.0000, 0.0000, NULL, 0.0000, 900000.00, 0.00, 900000.00, 0.0000, 0.0000, NULL),
(293, 8, 30, 129, N'Áo sơ mi nữ lụa - Trắng - L', 1, 6.0000, 150000.0000, 0.0000, NULL, 0.0000, 900000.00, 0.00, 900000.00, 0.0000, 0.0000, NULL),
(294, 8, 31, 137, N'Váy đầm hoa nhí - Xanh dương - S', 1, 6.0000, 160000.0000, 0.0000, NULL, 0.0000, 960000.00, 0.00, 960000.00, 0.0000, 0.0000, NULL),
(295, 8, 32, 138, N'Váy đầm hoa nhí - Xanh dương - M', 1, 6.0000, 160000.0000, 0.0000, NULL, 0.0000, 960000.00, 0.00, 960000.00, 0.0000, 0.0000, NULL),
(296, 8, 33, 139, N'Váy đầm hoa nhí - Xanh dương - L', 1, 6.0000, 160000.0000, 0.0000, NULL, 0.0000, 960000.00, 0.00, 960000.00, 0.0000, 0.0000, NULL),
(297, 8, 34, 141, N'Áo sơ mi trắng công sở - Xanh dương - S', 1, 6.0000, 140000.0000, 0.0000, NULL, 0.0000, 840000.00, 0.00, 840000.00, 0.0000, 0.0000, NULL),
(298, 8, 35, 142, N'Áo sơ mi trắng công sở - Xanh dương - M', 1, 6.0000, 140000.0000, 0.0000, NULL, 0.0000, 840000.00, 0.00, 840000.00, 0.0000, 0.0000, NULL),
(299, 8, 36, 143, N'Áo sơ mi trắng công sở - Xanh dương - L', 1, 6.0000, 140000.0000, 0.0000, NULL, 0.0000, 840000.00, 0.00, 840000.00, 0.0000, 0.0000, NULL),
(300, 8, 37, 144, N'Áo sơ mi trắng công sở - Xanh dương - XL', 1, 6.0000, 140000.0000, 0.0000, NULL, 0.0000, 840000.00, 0.00, 840000.00, 0.0000, 0.0000, NULL),
(301, 8, 38, 158, N'Quần kaki chinos - Xanh navy - 29', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(302, 8, 39, 159, N'Quần kaki chinos - Xanh navy - 30', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(303, 8, 40, 160, N'Quần kaki chinos - Xanh navy - 31', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(304, 8, 41, 161, N'Quần kaki chinos - Xanh navy - 32', 1, 6.0000, 165000.0000, 0.0000, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, NULL),
(305, 9, 1, 63, N'Quần jeans nữ ống rộng - Đen - S', 1, 6.0000, 185000.0000, 0.0000, NULL, 0.0000, 1110000.00, 0.00, 1110000.00, 0.0000, 0.0000, NULL),
(306, 9, 2, 64, N'Quần jeans nữ ống rộng - Đen - M', 1, 6.0000, 185000.0000, 0.0000, NULL, 0.0000, 1110000.00, 0.00, 1110000.00, 0.0000, 0.0000, NULL),
(307, 9, 3, 65, N'Quần jeans nữ ống rộng - Đen - L', 1, 6.0000, 185000.0000, 0.0000, NULL, 0.0000, 1110000.00, 0.00, 1110000.00, 0.0000, 0.0000, NULL),
(308, 9, 4, 69, N'Quần jeans slim fit - Đen - 29', 1, 12.0000, 200000.0000, 0.0000, NULL, 0.0000, 2400000.00, 0.00, 2400000.00, 0.0000, 0.0000, NULL),
(309, 9, 5, 70, N'Quần jeans slim fit - Đen - 30', 1, 12.0000, 200000.0000, 0.0000, NULL, 0.0000, 2400000.00, 0.00, 2400000.00, 0.0000, 0.0000, NULL),
(310, 9, 6, 71, N'Quần jeans slim fit - Đen - 31', 1, 12.0000, 200000.0000, 0.0000, NULL, 0.0000, 2400000.00, 0.00, 2400000.00, 0.0000, 0.0000, NULL),
(311, 9, 7, 72, N'Quần jeans slim fit - Đen - 32', 1, 12.0000, 200000.0000, 0.0000, NULL, 0.0000, 2400000.00, 0.00, 2400000.00, 0.0000, 0.0000, NULL),
(312, 9, 8, 73, N'Quần jeans slim fit - Đen - 34', 1, 12.0000, 200000.0000, 0.0000, NULL, 0.0000, 2400000.00, 0.00, 2400000.00, 0.0000, 0.0000, NULL),
(313, 9, 9, 145, N'Quần jeans slim fit - Xanh jean - 29', 1, 12.0000, 200000.0000, 0.0000, NULL, 0.0000, 2400000.00, 0.00, 2400000.00, 0.0000, 0.0000, NULL),
(314, 9, 10, 146, N'Quần jeans slim fit - Xanh jean - 30', 1, 12.0000, 200000.0000, 0.0000, NULL, 0.0000, 2400000.00, 0.00, 2400000.00, 0.0000, 0.0000, NULL),
(315, 9, 11, 147, N'Quần jeans slim fit - Xanh jean - 31', 1, 12.0000, 200000.0000, 0.0000, NULL, 0.0000, 2400000.00, 0.00, 2400000.00, 0.0000, 0.0000, NULL),
(316, 9, 12, 148, N'Quần jeans slim fit - Xanh jean - 32', 1, 12.0000, 200000.0000, 0.0000, NULL, 0.0000, 2400000.00, 0.00, 2400000.00, 0.0000, 0.0000, NULL),
(317, 9, 13, 149, N'Quần jeans slim fit - Xanh jean - 34', 1, 12.0000, 200000.0000, 0.0000, NULL, 0.0000, 2400000.00, 0.00, 2400000.00, 0.0000, 0.0000, NULL),
(318, 9, 14, 163, N'Quần jeans nữ ống rộng - Xanh nhạt - S', 1, 6.0000, 185000.0000, 0.0000, NULL, 0.0000, 1110000.00, 0.00, 1110000.00, 0.0000, 0.0000, NULL),
(319, 9, 15, 164, N'Quần jeans nữ ống rộng - Xanh nhạt - M', 1, 6.0000, 185000.0000, 0.0000, NULL, 0.0000, 1110000.00, 0.00, 1110000.00, 0.0000, 0.0000, NULL),
(320, 9, 16, 165, N'Quần jeans nữ ống rộng - Xanh nhạt - L', 1, 6.0000, 185000.0000, 0.0000, NULL, 0.0000, 1110000.00, 0.00, 1110000.00, 0.0000, 0.0000, NULL)
;
SET IDENTITY_INSERT [pur].[PurchaseOrderLines] OFF;
GO

-- pur.PurchaseOrders (9 dòng)
SET IDENTITY_INSERT [pur].[PurchaseOrders] ON;
INSERT INTO [pur].[PurchaseOrders] ([Id], [CompanyId], [BranchId], [DocNo], [PartnerId], [ContactId], [PurchaseRequestId], [OrderDate], [ExpectedDate], [WarehouseId], [CurrencyCode], [ExchangeRate], [PaymentTermId], [BuyerUserId], [Status], [ReceiptStatus], [BillStatus], [SubTotal], [DiscountAmount], [TaxAmount], [OtherCost], [TotalAmount], [Terms], [Note], [ConfirmedAt], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted], [AmountPaid]) VALUES
(1, 1, NULL, 'DM2609-0001', 25, NULL, NULL, '2026-09-21', '2026-09-25', 1, 'VND', 1.000000, NULL, 1, 'completed', 'received', 'none', 22977000.00, 0.00, 0.00, 0.00, 22977000.00, NULL, NULL, '2026-09-21T09:42:54.7200000', '2026-09-21T09:42:54.7200000', 1, NULL, NULL, 0, 22977000.00),
(2, 1, NULL, 'DM2609-0002', 26, NULL, NULL, '2026-09-21', '2026-09-25', 1, 'VND', 1.000000, NULL, 1, 'completed', 'received', 'none', 62635000.00, 0.00, 0.00, 0.00, 62635000.00, NULL, NULL, '2026-09-21T09:42:54.7200000', '2026-09-21T09:42:54.7200000', 1, NULL, NULL, 0, 62635000.00),
(3, 1, NULL, 'DM2609-0003', 27, NULL, NULL, '2026-09-22', '2026-09-26', 1, 'VND', 1.000000, NULL, 1, 'completed', 'received', 'none', 13670000.00, 0.00, 0.00, 0.00, 13670000.00, NULL, NULL, '2026-09-22T09:42:54.7200000', '2026-09-22T09:42:54.7200000', 1, NULL, NULL, 0, 13670000.00),
(4, 1, NULL, 'DM2609-0004', 28, NULL, NULL, '2026-09-22', '2026-09-26', 1, 'VND', 1.000000, NULL, 1, 'completed', 'received', 'none', 67520000.00, 0.00, 0.00, 0.00, 67520000.00, NULL, NULL, '2026-09-22T09:42:54.7200000', '2026-09-22T09:42:54.7200000', 1, NULL, NULL, 0, 67520000.00),
(5, 1, NULL, 'DM2610-0001', 25, NULL, NULL, '2026-10-25', '2026-10-29', 1, 'VND', 1.000000, NULL, 1, 'completed', 'received', 'none', 17383000.00, 0.00, 0.00, 0.00, 17383000.00, NULL, NULL, '2026-10-25T09:42:54.7200000', '2026-10-25T09:42:54.7200000', 1, NULL, NULL, 0, 8692000.00),
(6, 1, NULL, 'DM2610-0002', 27, NULL, NULL, '2026-10-26', '2026-10-30', 1, 'VND', 1.000000, NULL, 1, 'completed', 'received', 'none', 8810000.00, 0.00, 0.00, 0.00, 8810000.00, NULL, NULL, '2026-10-26T09:42:54.7200000', '2026-10-26T09:42:54.7200000', 1, NULL, NULL, 0, 4405000.00),
(7, 1, NULL, 'DM2610-0003', 28, NULL, NULL, '2026-10-26', '2026-10-30', 1, 'VND', 1.000000, NULL, 1, 'completed', 'received', 'none', 18930000.00, 0.00, 0.00, 0.00, 18930000.00, NULL, NULL, '2026-10-26T09:42:54.7200000', '2026-10-26T09:42:54.7200000', 1, NULL, NULL, 0, 9465000.00),
(8, 1, NULL, 'DM2611-0001', 26, NULL, NULL, '2026-11-17', '2026-11-21', 1, 'VND', 1.000000, NULL, 1, 'confirmed', 'pending', 'none', 38760000.00, 0.00, 0.00, 0.00, 38760000.00, NULL, NULL, '2026-11-17T09:42:54.7200000', '2026-11-17T09:42:54.7200000', 1, NULL, NULL, 0, 11628000.00),
(9, 1, NULL, 'DM2611-0002', 27, NULL, NULL, '2026-11-19', '2026-11-23', 1, 'VND', 1.000000, NULL, 1, 'draft', 'pending', 'none', 30660000.00, 0.00, 0.00, 0.00, 30660000.00, NULL, N'Chờ chốt số lượng với nhà cung cấp', NULL, '2026-11-19T09:42:54.7200000', 1, NULL, NULL, 0, 0.00)
;
SET IDENTITY_INSERT [pur].[PurchaseOrders] OFF;
GO

-- sales.OrderPromotions (12 dòng)
INSERT INTO [sales].[OrderPromotions] ([SalesOrderId], [PromotionId], [DiscountAmount]) VALUES
(8, 1, 20000.00),
(9, 1, 20000.00),
(18, 1, 20000.00),
(23, 1, 20000.00),
(26, 1, 20000.00),
(27, 1, 20000.00),
(29, 1, 20000.00),
(40, 1, 20000.00),
(41, 1, 20000.00),
(100, 1, 20000.00),
(113, 1, 20000.00),
(132, 1, 20000.00)
;
GO

-- sales.Promotions (5 dòng)
SET IDENTITY_INSERT [sales].[Promotions] ON;
INSERT INTO [sales].[Promotions] ([Id], [CompanyId], [Code], [Name], [PromotionType], [Value], [MaxDiscount], [MinOrderAmount], [StartAt], [EndAt], [UsageLimit], [UsedCount], [Channels], [IsActive], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [CampaignId]) VALUES
(1, 1, 'GIAM20K', N'Giảm 20.000đ đơn từ 200k', 'fixed', 20000.0000, NULL, 200000.00, '2026-09-22T07:55:41.0000000', '2026-12-31T07:55:41.0000000', NULL, 11, NULL, 1, '2026-11-21T00:55:41.0730000', 1, NULL, NULL, 1),
(2, 1, 'TIKTOK50K', N'Giảm 50k cho đơn TikTok từ 500k', 'fixed', 50000.0000, NULL, 500000.00, '2026-10-22T07:55:41.0000000', '2026-12-21T07:55:41.0000000', 300, 0, 'tiktok', 1, '2026-11-21T00:55:41.0730000', 1, NULL, NULL, 2),
(3, 1, 'FREESHIP300', N'Miễn phí ship đơn online từ 300k', 'free_ship', 0.0000, NULL, 300000.00, '2026-11-01T07:55:41.0000000', '2027-01-20T07:55:41.0000000', NULL, 0, 'website,facebook,zalo', 1, '2026-11-21T00:55:41.0730000', 1, NULL, NULL, NULL),
(4, 1, 'KHMOI10', N'Khách mới giảm 10%', 'percent', 10.0000, 50000.00, 0.00, '2026-11-11T07:55:41.0000000', '2027-02-09T07:55:41.0000000', 100, 0, NULL, 1, '2026-11-21T00:55:41.0730000', 1, NULL, NULL, NULL),
(5, 1, 'BLACKFRIDAY', N'Black Friday giảm 20%', 'percent', 20.0000, 200000.00, 0.00, '2026-11-27T00:00:00.0000000', '2026-11-30T23:59:59.0000000', 500, 0, NULL, 1, '2026-11-21T00:55:41.0730000', 1, NULL, NULL, 4)
;
SET IDENTITY_INSERT [sales].[Promotions] OFF;
GO

-- sales.QuotationLines (14 dòng)
SET IDENTITY_INSERT [sales].[QuotationLines] ON;
INSERT INTO [sales].[QuotationLines] ([Id], [QuotationId], [LineNumber], [ProductId], [Description], [UomId], [Quantity], [UnitPrice], [DiscountPercent], [DiscountAmount], [TaxId], [TaxRate], [LineSubTotal], [LineTax], [LineTotal], [IsOptional]) VALUES
(1, 1, 1, 124, N'Áo polo pique - Trắng - L', 1, 40.0000, 249000.0000, 15.0000, 1494000.00, NULL, 0.0000, 8466000.00, 0.00, 8466000.00, 0),
(2, 1, 2, 154, N'Áo polo pique - Xanh navy - M', 1, 30.0000, 249000.0000, 15.0000, 1120500.00, NULL, 0.0000, 6349500.00, 0.00, 6349500.00, 0),
(3, 2, 1, 120, N'Áo sơ mi trắng công sở - Trắng - M', 1, 25.0000, 329000.0000, 10.0000, 822500.00, NULL, 0.0000, 7402500.00, 0.00, 7402500.00, 0),
(4, 2, 2, 121, N'Áo sơ mi trắng công sở - Trắng - L', 1, 25.0000, 329000.0000, 10.0000, 822500.00, NULL, 0.0000, 7402500.00, 0.00, 7402500.00, 0),
(5, 3, 1, 123, N'Áo polo pique - Trắng - M', 1, 60.0000, 249000.0000, 12.0000, 1792800.00, NULL, 0.0000, 13147200.00, 0.00, 13147200.00, 0),
(6, 4, 1, 91, N'Áo khoác gió chống nắng - Hồng - Free size', 1, 30.0000, 299000.0000, 10.0000, 897000.00, NULL, 0.0000, 8073000.00, 0.00, 8073000.00, 0),
(7, 4, 2, 38, N'Mũ lưỡi trai - Đen - Free size', 1, 30.0000, 129000.0000, 10.0000, 387000.00, NULL, 0.0000, 3483000.00, 0.00, 3483000.00, 0),
(8, 5, 1, 76, N'Áo thun basic cổ tròn - Đen - L', 1, 50.0000, 159000.0000, 15.0000, 1192500.00, NULL, 0.0000, 6757500.00, 0.00, 6757500.00, 0),
(9, 5, 2, 117, N'Áo thun basic cổ tròn - Trắng - L', 1, 50.0000, 159000.0000, 15.0000, 1192500.00, NULL, 0.0000, 6757500.00, 0.00, 6757500.00, 0),
(10, 6, 1, 79, N'Áo polo pique - Đen - L', 1, 20.0000, 249000.0000, 10.0000, 498000.00, NULL, 0.0000, 4482000.00, 0.00, 4482000.00, 0),
(11, 6, 2, 61, N'Quần kaki chinos - Đen - 31', 1, 20.0000, 389000.0000, 10.0000, 778000.00, NULL, 0.0000, 7002000.00, 0.00, 7002000.00, 0),
(12, 7, 1, 143, N'Áo sơ mi trắng công sở - Xanh dương - L', 1, 35.0000, 329000.0000, 12.0000, 1381800.00, NULL, 0.0000, 10133200.00, 0.00, 10133200.00, 0),
(13, 7, 2, 10, N'Quần kaki chinos - Be - 32', 1, 35.0000, 389000.0000, 12.0000, 1633800.00, NULL, 0.0000, 11981200.00, 0.00, 11981200.00, 0),
(14, 8, 1, 41, N'Áo khoác bomber - Đen - L', 1, 30.0000, 599000.0000, 10.0000, 1797000.00, NULL, 0.0000, 16173000.00, 0.00, 16173000.00, 0)
;
SET IDENTITY_INSERT [sales].[QuotationLines] OFF;
GO

-- sales.Quotations (8 dòng)
SET IDENTITY_INSERT [sales].[Quotations] ON;
INSERT INTO [sales].[Quotations] ([Id], [CompanyId], [BranchId], [DocNo], [RevisionNo], [PartnerId], [ContactId], [OpportunityId], [QuoteDate], [ValidUntil], [CurrencyCode], [ExchangeRate], [PriceListId], [PaymentTermId], [SalespersonUserId], [BillingAddressId], [ShippingAddressId], [Status], [SubTotal], [DiscountAmount], [TaxAmount], [ShippingFee], [TotalAmount], [Terms], [Note], [SentAt], [AcceptedAt], [RejectedReason], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, NULL, 'BG2610-00001', 0, 17, NULL, NULL, '2026-10-11', '2026-10-26', 'VND', 1.000000, NULL, NULL, 1, NULL, NULL, 'accepted', 14815500.00, 0.00, 0.00, 0.00, 14815500.00, N'Giá đã bao gồm VAT. In logo công ty miễn phí từ 30 áo.
Thanh toán: chuyển khoản 50% khi đặt, 50% khi nhận hàng.
Giao hàng trong 7 ngày làm việc.', N'Đồng phục nhân viên', '2026-10-11T02:00:00.0000000', '2026-10-13T00:00:00.0000000', NULL, '2026-10-11T00:00:00.0000000', 1, NULL, NULL, 0),
(2, 1, NULL, 'BG2610-00002', 0, 18, NULL, NULL, '2026-10-23', '2026-11-07', 'VND', 1.000000, NULL, NULL, 1, NULL, NULL, 'rejected', 14805000.00, 0.00, 0.00, 0.00, 14805000.00, N'Giá đã bao gồm VAT. In logo công ty miễn phí từ 30 áo.
Thanh toán: chuyển khoản 50% khi đặt, 50% khi nhận hàng.
Giao hàng trong 7 ngày làm việc.', N'Đồng phục nhân viên', '2026-10-23T02:00:00.0000000', NULL, N'Khách chọn đơn vị khác giá rẻ hơn', '2026-10-23T00:00:00.0000000', 1, NULL, NULL, 0),
(3, 1, NULL, 'BG2610-00003', 0, 19, NULL, NULL, '2026-10-31', '2026-11-10', 'VND', 1.000000, NULL, NULL, 1, NULL, NULL, 'sent', 13147200.00, 0.00, 0.00, 0.00, 13147200.00, N'Giá đã bao gồm VAT. In logo công ty miễn phí từ 30 áo.
Thanh toán: chuyển khoản 50% khi đặt, 50% khi nhận hàng.
Giao hàng trong 7 ngày làm việc.', N'Đồng phục nhân viên', '2026-10-31T02:00:00.0000000', NULL, NULL, '2026-10-31T00:00:00.0000000', 1, NULL, NULL, 0),
(4, 1, NULL, 'BG2611-00001', 0, 21, NULL, NULL, '2026-11-11', '2026-11-26', 'VND', 1.000000, NULL, NULL, 1, NULL, NULL, 'sent', 11556000.00, 0.00, 0.00, 0.00, 11556000.00, N'Giá đã bao gồm VAT. In logo công ty miễn phí từ 30 áo.
Thanh toán: chuyển khoản 50% khi đặt, 50% khi nhận hàng.
Giao hàng trong 7 ngày làm việc.', N'Đồng phục nhân viên', '2026-11-11T02:00:00.0000000', NULL, NULL, '2026-11-11T00:00:00.0000000', 1, NULL, NULL, 0),
(5, 1, NULL, 'BG2611-00002', 0, 22, NULL, NULL, '2026-11-14', '2026-11-29', 'VND', 1.000000, NULL, NULL, 1, NULL, NULL, 'sent', 13515000.00, 0.00, 0.00, 0.00, 13515000.00, N'Giá đã bao gồm VAT. In logo công ty miễn phí từ 30 áo.
Thanh toán: chuyển khoản 50% khi đặt, 50% khi nhận hàng.
Giao hàng trong 7 ngày làm việc.', N'Đồng phục nhân viên', '2026-11-14T02:00:00.0000000', NULL, NULL, '2026-11-14T00:00:00.0000000', 1, NULL, NULL, 0),
(6, 1, NULL, 'BG2611-00003', 0, 24, NULL, NULL, '2026-11-16', '2026-12-01', 'VND', 1.000000, NULL, NULL, 1, NULL, NULL, 'accepted', 11484000.00, 0.00, 0.00, 0.00, 11484000.00, N'Giá đã bao gồm VAT. In logo công ty miễn phí từ 30 áo.
Thanh toán: chuyển khoản 50% khi đặt, 50% khi nhận hàng.
Giao hàng trong 7 ngày làm việc.', N'Đồng phục nhân viên', '2026-11-16T02:00:00.0000000', '2026-11-18T00:00:00.0000000', NULL, '2026-11-16T00:00:00.0000000', 1, NULL, NULL, 0),
(7, 1, NULL, 'BG2611-00004', 0, 20, NULL, NULL, '2026-11-18', '2026-12-03', 'VND', 1.000000, NULL, NULL, 1, NULL, NULL, 'draft', 22114400.00, 0.00, 0.00, 0.00, 22114400.00, N'Giá đã bao gồm VAT. In logo công ty miễn phí từ 30 áo.
Thanh toán: chuyển khoản 50% khi đặt, 50% khi nhận hàng.
Giao hàng trong 7 ngày làm việc.', N'Đồng phục nhân viên', NULL, NULL, NULL, '2026-11-18T00:00:00.0000000', 1, NULL, NULL, 0),
(8, 1, NULL, 'BG2611-00005', 0, 17, NULL, NULL, '2026-11-19', '2026-12-09', 'VND', 1.000000, NULL, NULL, 1, NULL, NULL, 'draft', 16173000.00, 0.00, 0.00, 0.00, 16173000.00, N'Giá đã bao gồm VAT. In logo công ty miễn phí từ 30 áo.
Thanh toán: chuyển khoản 50% khi đặt, 50% khi nhận hàng.
Giao hàng trong 7 ngày làm việc.', N'Đồng phục nhân viên', NULL, NULL, NULL, '2026-11-19T00:00:00.0000000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [sales].[Quotations] OFF;
GO

-- sales.SalesOrderLines (295 dòng)
SET IDENTITY_INSERT [sales].[SalesOrderLines] ON;
INSERT INTO [sales].[SalesOrderLines] ([Id], [SalesOrderId], [LineNumber], [ProductId], [Description], [UomId], [Quantity], [UnitPrice], [DiscountPercent], [DiscountAmount], [TaxId], [TaxRate], [LineSubTotal], [LineTax], [LineTotal], [UnitCost], [QtyDelivered], [QtyInvoiced], [QtyReturned], [QuotationLineId]) VALUES
(1, 1, 1, 5, N'Áo sơ mi nữ lụa - Be - M', 1, 1.0000, 359000.0000, 0.0000, 0.00, NULL, 0.0000, 359000.00, 0.00, 359000.00, 150000.0000, 1.0000, 0.0000, 0.0000, NULL),
(2, 1, 2, 75, N'Áo thun basic cổ tròn - Đen - M', 1, 2.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 318000.00, 0.00, 318000.00, 65000.0000, 2.0000, 0.0000, 0.0000, NULL),
(3, 1, 3, 131, N'Áo thun basic cổ tròn - Xám - M', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(4, 2, 1, 146, N'Quần jeans slim fit - Xanh jean - 30', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(5, 2, 2, 47, N'Giày sneaker trắng - Đen - 37', 21, 1.0000, 690000.0000, 10.0000, 69000.00, NULL, 0.0000, 621000.00, 0.00, 621000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(6, 3, 1, 62, N'Quần kaki chinos - Đen - 32', 1, 1.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 389000.00, 0.00, 389000.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(7, 3, 2, 117, N'Áo thun basic cổ tròn - Trắng - L', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(8, 4, 1, 106, N'Giày sneaker trắng - Trắng - 38', 21, 1.0000, 690000.0000, 10.0000, 69000.00, NULL, 0.0000, 621000.00, 0.00, 621000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(9, 4, 2, 158, N'Quần kaki chinos - Xanh navy - 29', 1, 1.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 389000.00, 0.00, 389000.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(10, 5, 1, 94, N'Váy đầm hoa nhí - Kem - L', 1, 2.0000, 399000.0000, 10.0000, 79800.00, NULL, 0.0000, 718200.00, 0.00, 718200.00, 160000.0000, 2.0000, 0.0000, 0.0000, NULL),
(11, 6, 1, 69, N'Quần jeans slim fit - Đen - 29', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(12, 7, 1, 136, N'Quần short thể thao - Xám - XL', 1, 1.0000, 179000.0000, 0.0000, 0.00, NULL, 0.0000, 179000.00, 0.00, 179000.00, 70000.0000, 1.0000, 0.0000, 0.0000, NULL),
(13, 8, 1, 14, N'Dép sandal quai ngang - Be - 37', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(14, 9, 1, 110, N'Giày sneaker trắng - Trắng - 42', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(15, 9, 2, 165, N'Quần jeans nữ ống rộng - Xanh nhạt - L', 1, 1.0000, 429000.0000, 0.0000, 0.00, NULL, 0.0000, 429000.00, 0.00, 429000.00, 185000.0000, 1.0000, 0.0000, 0.0000, NULL),
(16, 9, 3, 70, N'Quần jeans slim fit - Đen - 30', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(17, 10, 1, 58, N'Giày cao gót mũi nhọn - Đen - 39', 21, 2.0000, 520000.0000, 0.0000, 0.00, NULL, 0.0000, 1040000.00, 0.00, 1040000.00, 220000.0000, 2.0000, 0.0000, 0.0000, NULL),
(18, 10, 2, 114, N'Áo thun oversize in chữ - Trắng - XL', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(19, 10, 3, 3, N'Áo thun oversize in chữ - Be - XL', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(20, 11, 1, 143, N'Áo sơ mi trắng công sở - Xanh dương - L', 1, 1.0000, 329000.0000, 0.0000, 0.00, NULL, 0.0000, 329000.00, 0.00, 329000.00, 140000.0000, 1.0000, 0.0000, 0.0000, NULL),
(21, 11, 2, 44, N'Chân váy chữ A - Đen - M', 1, 1.0000, 279000.0000, 0.0000, 0.00, NULL, 0.0000, 279000.00, 0.00, 279000.00, 110000.0000, 1.0000, 0.0000, 0.0000, NULL),
(22, 12, 1, 22, N'Giày cao gót mũi nhọn - Be - 37', 21, 1.0000, 520000.0000, 0.0000, 0.00, NULL, 0.0000, 520000.00, 0.00, 520000.00, 220000.0000, 1.0000, 0.0000, 0.0000, NULL),
(23, 13, 1, 103, N'Áo khoác gió chống nắng - Trắng - Free size', 1, 1.0000, 299000.0000, 0.0000, 0.00, NULL, 0.0000, 299000.00, 0.00, 299000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(24, 13, 2, 155, N'Áo polo pique - Xanh navy - L', 1, 2.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 498000.00, 0.00, 498000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(25, 14, 1, 73, N'Quần jeans slim fit - Đen - 34', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(26, 15, 1, 9, N'Quần kaki chinos - Be - 31', 1, 2.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 778000.00, 0.00, 778000.00, 165000.0000, 2.0000, 0.0000, 0.0000, NULL),
(27, 16, 1, 65, N'Quần jeans nữ ống rộng - Đen - L', 1, 1.0000, 429000.0000, 0.0000, 0.00, NULL, 0.0000, 429000.00, 0.00, 429000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(28, 17, 1, 108, N'Giày sneaker trắng - Trắng - 40', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(29, 17, 2, 162, N'Mũ lưỡi trai - Xanh navy - Free size', 1, 1.0000, 129000.0000, 0.0000, 0.00, NULL, 0.0000, 129000.00, 0.00, 129000.00, 45000.0000, 1.0000, 0.0000, 0.0000, NULL),
(30, 17, 3, 67, N'Quần short thể thao - Đen - L', 1, 2.0000, 179000.0000, 0.0000, 0.00, NULL, 0.0000, 358000.00, 0.00, 358000.00, 70000.0000, 2.0000, 0.0000, 0.0000, NULL),
(31, 18, 1, 148, N'Quần jeans slim fit - Xanh jean - 32', 1, 1.0000, 459000.0000, 10.0000, 45900.00, NULL, 0.0000, 413100.00, 0.00, 413100.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(32, 18, 2, 50, N'Giày sneaker trắng - Đen - 40', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(33, 18, 3, 109, N'Giày sneaker trắng - Trắng - 41', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(34, 19, 1, 139, N'Váy đầm hoa nhí - Xanh dương - L', 1, 2.0000, 399000.0000, 10.0000, 79800.00, NULL, 0.0000, 718200.00, 0.00, 718200.00, 160000.0000, 2.0000, 0.0000, 0.0000, NULL),
(35, 19, 2, 38, N'Mũ lưỡi trai - Đen - Free size', 1, 1.0000, 129000.0000, 0.0000, 0.00, NULL, 0.0000, 129000.00, 0.00, 129000.00, 45000.0000, 1.0000, 0.0000, 0.0000, NULL),
(36, 20, 1, 99, N'Giày tây da bò - Nâu - 41', 21, 1.0000, 990000.0000, 0.0000, 0.00, NULL, 0.0000, 990000.00, 0.00, 990000.00, 450000.0000, 1.0000, 0.0000, 0.0000, NULL),
(37, 21, 1, 113, N'Áo thun oversize in chữ - Trắng - L', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(38, 22, 1, 17, N'Dép sandal quai ngang - Be - 40', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(39, 23, 1, 71, N'Quần jeans slim fit - Đen - 31', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(40, 24, 1, 146, N'Quần jeans slim fit - Xanh jean - 30', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(41, 24, 2, 47, N'Giày sneaker trắng - Đen - 37', 21, 2.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 1380000.00, 0.00, 1380000.00, 310000.0000, 2.0000, 0.0000, 0.0000, NULL),
(42, 24, 3, 107, N'Giày sneaker trắng - Trắng - 39', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(43, 25, 1, 62, N'Quần kaki chinos - Đen - 32', 1, 1.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 389000.00, 0.00, 389000.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(44, 25, 2, 117, N'Áo thun basic cổ tròn - Trắng - L', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(45, 26, 1, 106, N'Giày sneaker trắng - Trắng - 38', 21, 2.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 1380000.00, 0.00, 1380000.00, 310000.0000, 2.0000, 0.0000, 0.0000, NULL),
(46, 26, 2, 158, N'Quần kaki chinos - Xanh navy - 29', 1, 1.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 389000.00, 0.00, 389000.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(47, 26, 3, 63, N'Quần jeans nữ ống rộng - Đen - S', 1, 1.0000, 429000.0000, 0.0000, 0.00, NULL, 0.0000, 429000.00, 0.00, 429000.00, 185000.0000, 1.0000, 0.0000, 0.0000, NULL),
(48, 27, 1, 26, N'Tất cổ ngắn (combo 3 đôi) - Đen - Free size', 12, 1.0000, 79000.0000, 0.0000, 0.00, NULL, 0.0000, 79000.00, 0.00, 79000.00, 28000.0000, 1.0000, 0.0000, 0.0000, NULL),
(49, 27, 2, 90, N'Áo sơ mi nữ lụa - Hồng - L', 1, 1.0000, 359000.0000, 0.0000, 0.00, NULL, 0.0000, 359000.00, 0.00, 359000.00, 150000.0000, 1.0000, 0.0000, 0.0000, NULL),
(50, 28, 1, 76, N'Áo thun basic cổ tròn - Đen - L', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(51, 28, 2, 132, N'Áo thun basic cổ tròn - Xám - L', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(52, 29, 1, 110, N'Giày sneaker trắng - Trắng - 42', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(53, 30, 1, 14, N'Dép sandal quai ngang - Be - 37', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(54, 31, 1, 69, N'Quần jeans slim fit - Đen - 29', 1, 2.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 918000.00, 0.00, 918000.00, 200000.0000, 2.0000, 0.0000, 0.0000, NULL),
(55, 32, 1, 150, N'Áo thun basic cổ tròn - Xanh navy - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(56, 33, 1, 103, N'Áo khoác gió chống nắng - Trắng - Free size', 1, 1.0000, 299000.0000, 0.0000, 0.00, NULL, 0.0000, 299000.00, 0.00, 299000.00, 120000.0000, 1.0000, 0.0000, 0.0000, NULL),
(57, 33, 2, 155, N'Áo polo pique - Xanh navy - L', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(58, 34, 1, 143, N'Áo sơ mi trắng công sở - Xanh dương - L', 1, 1.0000, 329000.0000, 0.0000, 0.00, NULL, 0.0000, 329000.00, 0.00, 329000.00, 140000.0000, 1.0000, 0.0000, 0.0000, NULL),
(59, 34, 2, 44, N'Chân váy chữ A - Đen - M', 1, 1.0000, 279000.0000, 0.0000, 0.00, NULL, 0.0000, 279000.00, 0.00, 279000.00, 110000.0000, 1.0000, 0.0000, 0.0000, NULL),
(60, 34, 3, 104, N'Giày sneaker trắng - Trắng - 36', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(61, 35, 1, 22, N'Giày cao gót mũi nhọn - Be - 37', 21, 2.0000, 520000.0000, 10.0000, 104000.00, NULL, 0.0000, 936000.00, 0.00, 936000.00, 220000.0000, 2.0000, 0.0000, 0.0000, NULL),
(62, 35, 2, 86, N'Váy đầm hoa nhí - Hồng - M', 1, 1.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 399000.00, 0.00, 399000.00, 160000.0000, 1.0000, 0.0000, 0.0000, NULL),
(63, 36, 1, 73, N'Quần jeans slim fit - Đen - 34', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(64, 36, 2, 130, N'Áo thun basic cổ tròn - Xám - S', 1, 2.0000, 159000.0000, 10.0000, 31800.00, NULL, 0.0000, 286200.00, 0.00, 286200.00, 65000.0000, 2.0000, 0.0000, 0.0000, NULL),
(65, 37, 1, 115, N'Áo thun basic cổ tròn - Trắng - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(66, 37, 2, 4, N'Áo sơ mi nữ lụa - Be - S', 1, 1.0000, 359000.0000, 0.0000, 0.00, NULL, 0.0000, 359000.00, 0.00, 359000.00, 150000.0000, 1.0000, 0.0000, 0.0000, NULL),
(67, 38, 1, 32, N'Dép sandal quai ngang - Đen - 37', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(68, 39, 1, 108, N'Giày sneaker trắng - Trắng - 40', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(69, 40, 1, 148, N'Quần jeans slim fit - Xanh jean - 32', 1, 2.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 918000.00, 0.00, 918000.00, 200000.0000, 2.0000, 0.0000, 0.0000, NULL),
(70, 41, 1, 65, N'Quần jeans nữ ống rộng - Đen - L', 1, 1.0000, 429000.0000, 0.0000, 0.00, NULL, 0.0000, 429000.00, 0.00, 429000.00, 185000.0000, 1.0000, 0.0000, 0.0000, NULL),
(71, 42, 1, 78, N'Áo polo pique - Đen - M', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(72, 42, 2, 135, N'Quần short thể thao - Xám - L', 1, 1.0000, 179000.0000, 0.0000, 0.00, NULL, 0.0000, 179000.00, 0.00, 179000.00, 70000.0000, 1.0000, 0.0000, 0.0000, NULL),
(73, 42, 3, 34, N'Dép sandal quai ngang - Đen - 39', 21, 2.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 498000.00, 0.00, 498000.00, 95000.0000, 2.0000, 0.0000, 0.0000, NULL),
(74, 43, 1, 17, N'Dép sandal quai ngang - Be - 40', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(75, 43, 2, 83, N'Áo thun oversize in chữ - Đen - L', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(76, 43, 3, 141, N'Áo sơ mi trắng công sở - Xanh dương - S', 1, 1.0000, 329000.0000, 0.0000, 0.00, NULL, 0.0000, 329000.00, 0.00, 329000.00, 140000.0000, 1.0000, 0.0000, 0.0000, NULL),
(77, 44, 1, 71, N'Quần jeans slim fit - Đen - 31', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(78, 44, 2, 126, N'Áo polo pique - Trắng - XXL', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(79, 45, 1, 113, N'Áo thun oversize in chữ - Trắng - L', 1, 2.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 398000.00, 0.00, 398000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(80, 45, 2, 2, N'Áo thun oversize in chữ - Be - L', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(81, 46, 1, 153, N'Áo thun basic cổ tròn - Xanh navy - XL', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(82, 47, 1, 106, N'Giày sneaker trắng - Trắng - 38', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(83, 48, 1, 76, N'Áo thun basic cổ tròn - Đen - L', 1, 2.0000, 159000.0000, 10.0000, 31800.00, NULL, 0.0000, 286200.00, 0.00, 286200.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(84, 48, 2, 132, N'Áo thun basic cổ tròn - Xám - L', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(85, 48, 3, 29, N'Giày tây da bò - Đen - 41', 21, 1.0000, 990000.0000, 0.0000, 0.00, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(86, 49, 1, 146, N'Quần jeans slim fit - Xanh jean - 30', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(87, 50, 1, 117, N'Áo thun basic cổ tròn - Trắng - L', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(88, 50, 2, 8, N'Quần kaki chinos - Be - 30', 1, 2.0000, 389000.0000, 10.0000, 77800.00, NULL, 0.0000, 700200.00, 0.00, 700200.00, 165000.0000, 2.0000, 0.0000, 0.0000, NULL),
(89, 50, 3, 77, N'Áo thun basic cổ tròn - Đen - XL', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(90, 51, 1, 26, N'Tất cổ ngắn (combo 3 đôi) - Đen - Free size', 12, 1.0000, 79000.0000, 0.0000, 0.00, NULL, 0.0000, 79000.00, 0.00, 79000.00, 28000.0000, 1.0000, 0.0000, 0.0000, NULL),
(91, 52, 1, 150, N'Áo thun basic cổ tròn - Xanh navy - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(92, 53, 1, 69, N'Quần jeans slim fit - Đen - 29', 1, 1.0000, 459000.0000, 10.0000, 45900.00, NULL, 0.0000, 413100.00, 0.00, 413100.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(93, 54, 1, 36, N'Dép sandal quai ngang - Đen - 41', 21, 2.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 498000.00, 0.00, 498000.00, 95000.0000, 2.0000, 0.0000, 0.0000, NULL),
(94, 55, 1, 110, N'Giày sneaker trắng - Trắng - 42', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(95, 55, 2, 165, N'Quần jeans nữ ống rộng - Xanh nhạt - L', 1, 1.0000, 429000.0000, 10.0000, 42900.00, NULL, 0.0000, 386100.00, 0.00, 386100.00, 185000.0000, 1.0000, 0.0000, 0.0000, NULL),
(96, 56, 1, 82, N'Áo thun oversize in chữ - Đen - M', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(97, 57, 1, 22, N'Giày cao gót mũi nhọn - Be - 37', 21, 1.0000, 520000.0000, 0.0000, 0.00, NULL, 0.0000, 520000.00, 0.00, 520000.00, 220000.0000, 1.0000, 0.0000, 0.0000, NULL),
(98, 57, 2, 86, N'Váy đầm hoa nhí - Hồng - M', 1, 1.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 399000.00, 0.00, 399000.00, 160000.0000, 1.0000, 0.0000, 0.0000, NULL),
(99, 58, 1, 156, N'Áo polo pique - Xanh navy - XL', 1, 2.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 498000.00, 0.00, 498000.00, 105000.0000, 2.0000, 0.0000, 0.0000, NULL),
(100, 58, 2, 61, N'Quần kaki chinos - Đen - 31', 1, 1.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 389000.00, 0.00, 389000.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(101, 59, 1, 73, N'Quần jeans slim fit - Đen - 34', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(102, 59, 2, 130, N'Áo thun basic cổ tròn - Xám - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(103, 59, 3, 25, N'Mũ lưỡi trai - Be - Free size', 1, 1.0000, 129000.0000, 0.0000, 0.00, NULL, 0.0000, 129000.00, 0.00, 129000.00, 45000.0000, 1.0000, 0.0000, 0.0000, NULL),
(104, 60, 1, 115, N'Áo thun basic cổ tròn - Trắng - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(105, 60, 2, 4, N'Áo sơ mi nữ lụa - Be - S', 1, 1.0000, 359000.0000, 0.0000, 0.00, NULL, 0.0000, 359000.00, 0.00, 359000.00, 150000.0000, 1.0000, 0.0000, 0.0000, NULL),
(106, 60, 3, 74, N'Áo thun basic cổ tròn - Đen - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(107, 61, 1, 108, N'Giày sneaker trắng - Trắng - 40', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(108, 62, 1, 78, N'Áo polo pique - Đen - M', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(109, 63, 1, 148, N'Quần jeans slim fit - Xanh jean - 32', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(110, 64, 1, 32, N'Dép sandal quai ngang - Đen - 37', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(111, 65, 1, 120, N'Áo sơ mi trắng công sở - Trắng - M', 1, 2.0000, 329000.0000, 10.0000, 65800.00, NULL, 0.0000, 592200.00, 0.00, 592200.00, 140000.0000, 2.0000, 0.0000, 0.0000, NULL),
(112, 66, 1, 71, N'Quần jeans slim fit - Đen - 31', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(113, 66, 2, 126, N'Áo polo pique - Trắng - XXL', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(114, 67, 1, 39, N'Túi xách nữ đeo chéo - Đen', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 190000.0000, 1.0000, 0.0000, 0.0000, NULL),
(115, 67, 2, 102, N'Tất cổ ngắn (combo 3 đôi) - Trắng - Free size', 12, 1.0000, 79000.0000, 0.0000, 0.00, NULL, 0.0000, 79000.00, 0.00, 79000.00, 28000.0000, 1.0000, 0.0000, 0.0000, NULL),
(116, 68, 1, 113, N'Áo thun oversize in chữ - Trắng - L', 1, 1.0000, 199000.0000, 10.0000, 19900.00, NULL, 0.0000, 179100.00, 0.00, 179100.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(117, 68, 2, 2, N'Áo thun oversize in chữ - Be - L', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(118, 68, 3, 72, N'Quần jeans slim fit - Đen - 32', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(119, 69, 1, 153, N'Áo thun basic cổ tròn - Xanh navy - XL', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(120, 69, 2, 56, N'Giày cao gót mũi nhọn - Đen - 37', 21, 1.0000, 520000.0000, 10.0000, 52000.00, NULL, 0.0000, 468000.00, 0.00, 468000.00, 220000.0000, 1.0000, 0.0000, 0.0000, NULL),
(121, 70, 1, 84, N'Áo thun oversize in chữ - Đen - XL', 1, 2.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 398000.00, 0.00, 398000.00, 80000.0000, 2.0000, 0.0000, 0.0000, NULL),
(122, 70, 2, 142, N'Áo sơ mi trắng công sở - Xanh dương - M', 1, 1.0000, 329000.0000, 0.0000, 0.00, NULL, 0.0000, 329000.00, 0.00, 329000.00, 140000.0000, 1.0000, 0.0000, 0.0000, NULL),
(123, 71, 1, 76, N'Áo thun basic cổ tròn - Đen - L', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(124, 72, 1, 117, N'Áo thun basic cổ tròn - Trắng - L', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(125, 73, 1, 26, N'Tất cổ ngắn (combo 3 đôi) - Đen - Free size', 12, 1.0000, 79000.0000, 0.0000, 0.00, NULL, 0.0000, 79000.00, 0.00, 79000.00, 28000.0000, 1.0000, 0.0000, 0.0000, NULL),
(126, 74, 1, 159, N'Quần kaki chinos - Xanh navy - 30', 1, 1.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 389000.00, 0.00, 389000.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(127, 75, 1, 110, N'Giày sneaker trắng - Trắng - 42', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(128, 75, 2, 165, N'Quần jeans nữ ống rộng - Xanh nhạt - L', 1, 2.0000, 429000.0000, 0.0000, 0.00, NULL, 0.0000, 858000.00, 0.00, 858000.00, 185000.0000, 2.0000, 0.0000, 0.0000, NULL),
(129, 75, 3, 70, N'Quần jeans slim fit - Đen - 30', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(130, 76, 1, 150, N'Áo thun basic cổ tròn - Xanh navy - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(131, 76, 2, 52, N'Giày sneaker trắng - Đen - 42', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(132, 77, 1, 124, N'Áo polo pique - Trắng - L', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(133, 78, 1, 36, N'Dép sandal quai ngang - Đen - 41', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(134, 78, 2, 97, N'Giày tây da bò - Nâu - 39', 21, 1.0000, 990000.0000, 0.0000, 0.00, NULL, 0.0000, 990000.00, 0.00, 990000.00, 450000.0000, 1.0000, 0.0000, 0.0000, NULL),
(135, 79, 1, 82, N'Áo thun oversize in chữ - Đen - M', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(136, 79, 2, 138, N'Váy đầm hoa nhí - Xanh dương - M', 1, 1.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 399000.00, 0.00, 399000.00, 160000.0000, 1.0000, 0.0000, 0.0000, NULL),
(137, 80, 1, 73, N'Quần jeans slim fit - Đen - 34', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(138, 81, 1, 115, N'Áo thun basic cổ tròn - Trắng - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(139, 82, 1, 46, N'Giày sneaker trắng - Đen - 36', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(140, 82, 2, 105, N'Giày sneaker trắng - Trắng - 37', 21, 1.0000, 690000.0000, 10.0000, 69000.00, NULL, 0.0000, 621000.00, 0.00, 621000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(141, 82, 3, 157, N'Áo polo pique - Xanh navy - XXL', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(142, 83, 1, 87, N'Váy đầm hoa nhí - Hồng - L', 1, 1.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 399000.00, 0.00, 399000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(143, 83, 2, 145, N'Quần jeans slim fit - Xanh jean - 29', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(144, 83, 3, 47, N'Giày sneaker trắng - Đen - 37', 21, 1.0000, 690000.0000, 10.0000, 69000.00, NULL, 0.0000, 621000.00, 0.00, 621000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(145, 84, 1, 156, N'Áo polo pique - Xanh navy - XL', 1, 1.0000, 249000.0000, 10.0000, 24900.00, NULL, 0.0000, 224100.00, 0.00, 224100.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(146, 85, 1, 120, N'Áo sơ mi trắng công sở - Trắng - M', 1, 1.0000, 329000.0000, 0.0000, 0.00, NULL, 0.0000, 329000.00, 0.00, 329000.00, 140000.0000, 1.0000, 0.0000, 0.0000, NULL),
(147, 86, 1, 32, N'Dép sandal quai ngang - Đen - 37', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(148, 87, 1, 163, N'Quần jeans nữ ống rộng - Xanh nhạt - S', 1, 1.0000, 429000.0000, 0.0000, 0.00, NULL, 0.0000, 429000.00, 0.00, 429000.00, 185000.0000, 1.0000, 0.0000, 0.0000, NULL),
(149, 88, 1, 78, N'Áo polo pique - Đen - M', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(150, 88, 2, 135, N'Quần short thể thao - Xám - L', 1, 1.0000, 179000.0000, 0.0000, 0.00, NULL, 0.0000, 179000.00, 0.00, 179000.00, 70000.0000, 1.0000, 0.0000, 0.0000, NULL),
(151, 89, 1, 113, N'Áo thun oversize in chữ - Trắng - L', 1, 2.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 398000.00, 0.00, 398000.00, 80000.0000, 2.0000, 0.0000, 0.0000, NULL),
(152, 89, 2, 2, N'Áo thun oversize in chữ - Be - L', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(153, 90, 1, 153, N'Áo thun basic cổ tròn - Xanh navy - XL', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(154, 91, 1, 39, N'Túi xách nữ đeo chéo - Đen', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 190000.0000, 1.0000, 0.0000, 0.0000, NULL),
(155, 91, 2, 102, N'Tất cổ ngắn (combo 3 đôi) - Trắng - Free size', 12, 1.0000, 79000.0000, 0.0000, 0.00, NULL, 0.0000, 79000.00, 0.00, 79000.00, 28000.0000, 1.0000, 0.0000, 0.0000, NULL),
(156, 91, 3, 154, N'Áo polo pique - Xanh navy - M', 1, 2.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 498000.00, 0.00, 498000.00, 105000.0000, 2.0000, 0.0000, 0.0000, NULL),
(157, 92, 1, 84, N'Áo thun oversize in chữ - Đen - XL', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(158, 92, 2, 142, N'Áo sơ mi trắng công sở - Xanh dương - M', 1, 1.0000, 329000.0000, 0.0000, 0.00, NULL, 0.0000, 329000.00, 0.00, 329000.00, 140000.0000, 1.0000, 0.0000, 0.0000, NULL),
(159, 92, 3, 42, N'Áo khoác bomber - Đen - XL', 1, 1.0000, 599000.0000, 0.0000, 0.00, NULL, 0.0000, 599000.00, 0.00, 599000.00, 260000.0000, 1.0000, 0.0000, 0.0000, NULL),
(160, 93, 1, 127, N'Áo sơ mi nữ lụa - Trắng - S', 1, 1.0000, 359000.0000, 0.0000, 0.00, NULL, 0.0000, 359000.00, 0.00, 359000.00, 150000.0000, 1.0000, 0.0000, 0.0000, NULL),
(161, 93, 2, 20, N'Giày cao gót mũi nhọn - Be - 35', 21, 1.0000, 520000.0000, 0.0000, 0.00, NULL, 0.0000, 520000.00, 0.00, 520000.00, 220000.0000, 1.0000, 0.0000, 0.0000, NULL),
(162, 94, 1, 48, N'Giày sneaker trắng - Đen - 38', 21, 1.0000, 690000.0000, 10.0000, 69000.00, NULL, 0.0000, 621000.00, 0.00, 621000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(163, 95, 1, 117, N'Áo thun basic cổ tròn - Trắng - L', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(164, 96, 1, 91, N'Áo khoác gió chống nắng - Hồng - Free size', 1, 1.0000, 299000.0000, 0.0000, 0.00, NULL, 0.0000, 299000.00, 0.00, 299000.00, 120000.0000, 1.0000, 0.0000, 0.0000, NULL),
(165, 97, 1, 159, N'Quần kaki chinos - Xanh navy - 30', 1, 1.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 389000.00, 0.00, 389000.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(166, 98, 1, 76, N'Áo thun basic cổ tròn - Đen - L', 1, 2.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 318000.00, 0.00, 318000.00, 65000.0000, 2.0000, 0.0000, 0.0000, NULL),
(167, 99, 1, 36, N'Dép sandal quai ngang - Đen - 41', 21, 2.0000, 249000.0000, 10.0000, 49800.00, NULL, 0.0000, 448200.00, 0.00, 448200.00, 95000.0000, 2.0000, 0.0000, 0.0000, NULL),
(168, 99, 2, 97, N'Giày tây da bò - Nâu - 39', 21, 1.0000, 990000.0000, 0.0000, 0.00, NULL, 0.0000, 990000.00, 0.00, 990000.00, 450000.0000, 1.0000, 0.0000, 0.0000, NULL),
(169, 100, 1, 82, N'Áo thun oversize in chữ - Đen - M', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(170, 100, 2, 138, N'Váy đầm hoa nhí - Xanh dương - M', 1, 2.0000, 399000.0000, 10.0000, 79800.00, NULL, 0.0000, 718200.00, 0.00, 718200.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(171, 100, 3, 37, N'Dép sandal quai ngang - Đen - 42', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(172, 101, 1, 115, N'Áo thun basic cổ tròn - Trắng - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(173, 102, 1, 167, N'Áo khoác bomber - Xanh rêu - L', 1, 1.0000, 599000.0000, 0.0000, 0.00, NULL, 0.0000, 599000.00, 0.00, 599000.00, 260000.0000, 1.0000, 0.0000, 0.0000, NULL),
(174, 102, 2, 70, N'Quần jeans slim fit - Đen - 30', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(175, 103, 1, 124, N'Áo polo pique - Trắng - L', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(176, 103, 2, 16, N'Dép sandal quai ngang - Be - 39', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(177, 104, 1, 87, N'Váy đầm hoa nhí - Hồng - L', 1, 1.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 399000.00, 0.00, 399000.00, 160000.0000, 1.0000, 0.0000, 0.0000, NULL),
(178, 105, 1, 156, N'Áo polo pique - Xanh navy - XL', 1, 2.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 498000.00, 0.00, 498000.00, 105000.0000, 2.0000, 0.0000, 0.0000, NULL),
(179, 106, 1, 130, N'Áo thun basic cổ tròn - Xám - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(180, 107, 1, 46, N'Giày sneaker trắng - Đen - 36', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(181, 108, 1, 94, N'Váy đầm hoa nhí - Kem - L', 1, 1.0000, 399000.0000, 10.0000, 39900.00, NULL, 0.0000, 359100.00, 0.00, 359100.00, 160000.0000, 1.0000, 0.0000, 0.0000, NULL),
(182, 109, 1, 163, N'Quần jeans nữ ống rộng - Xanh nhạt - S', 1, 1.0000, 429000.0000, 0.0000, 0.00, NULL, 0.0000, 429000.00, 0.00, 429000.00, 185000.0000, 1.0000, 0.0000, 0.0000, NULL),
(183, 109, 2, 68, N'Quần short thể thao - Đen - XL', 1, 2.0000, 179000.0000, 0.0000, 0.00, NULL, 0.0000, 358000.00, 0.00, 358000.00, 70000.0000, 2.0000, 0.0000, 0.0000, NULL),
(184, 110, 1, 78, N'Áo polo pique - Đen - M', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(185, 110, 2, 135, N'Quần short thể thao - Xám - L', 1, 1.0000, 179000.0000, 0.0000, 0.00, NULL, 0.0000, 179000.00, 0.00, 179000.00, 70000.0000, 1.0000, 0.0000, 0.0000, NULL),
(186, 110, 3, 34, N'Dép sandal quai ngang - Đen - 39', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(187, 111, 1, 50, N'Giày sneaker trắng - Đen - 40', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(188, 111, 2, 110, N'Giày sneaker trắng - Trắng - 42', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(189, 112, 1, 120, N'Áo sơ mi trắng công sở - Trắng - M', 1, 2.0000, 329000.0000, 0.0000, 0.00, NULL, 0.0000, 658000.00, 0.00, 658000.00, 140000.0000, 2.0000, 0.0000, 0.0000, NULL),
(190, 112, 2, 12, N'Chân váy chữ A - Be - M', 1, 1.0000, 279000.0000, 0.0000, 0.00, NULL, 0.0000, 279000.00, 0.00, 279000.00, 110000.0000, 1.0000, 0.0000, 0.0000, NULL),
(191, 113, 1, 39, N'Túi xách nữ đeo chéo - Đen', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 190000.0000, 1.0000, 0.0000, 0.0000, NULL),
(192, 114, 1, 2, N'Áo thun oversize in chữ - Be - L', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(193, 114, 2, 73, N'Quần jeans slim fit - Đen - 34', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(194, 114, 3, 129, N'Áo sơ mi nữ lụa - Trắng - L', 1, 2.0000, 359000.0000, 10.0000, 71800.00, NULL, 0.0000, 646200.00, 0.00, 646200.00, 150000.0000, 2.0000, 0.0000, 0.0000, NULL),
(195, 115, 1, 84, N'Áo thun oversize in chữ - Đen - XL', 1, 2.0000, 199000.0000, 10.0000, 39800.00, NULL, 0.0000, 358200.00, 0.00, 358200.00, 80000.0000, 2.0000, 0.0000, 0.0000, NULL),
(196, 116, 1, 127, N'Áo sơ mi nữ lụa - Trắng - S', 1, 1.0000, 359000.0000, 0.0000, 0.00, NULL, 0.0000, 359000.00, 0.00, 359000.00, 150000.0000, 1.0000, 0.0000, 0.0000, NULL),
(197, 117, 1, 159, N'Quần kaki chinos - Xanh navy - 30', 1, 1.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 389000.00, 0.00, 389000.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(198, 117, 2, 64, N'Quần jeans nữ ống rộng - Đen - M', 1, 1.0000, 429000.0000, 0.0000, 0.00, NULL, 0.0000, 429000.00, 0.00, 429000.00, 185000.0000, 1.0000, 0.0000, 0.0000, NULL),
(199, 118, 1, 133, N'Áo thun basic cổ tròn - Xám - XL', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(200, 119, 1, 48, N'Giày sneaker trắng - Đen - 38', 21, 2.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 1380000.00, 0.00, 1380000.00, 310000.0000, 2.0000, 0.0000, 0.0000, NULL),
(201, 119, 2, 107, N'Giày sneaker trắng - Trắng - 39', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(202, 120, 1, 117, N'Áo thun basic cổ tròn - Trắng - L', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(203, 120, 2, 8, N'Quần kaki chinos - Be - 30', 1, 1.0000, 389000.0000, 10.0000, 38900.00, NULL, 0.0000, 350100.00, 0.00, 350100.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(204, 120, 3, 77, N'Áo thun basic cổ tròn - Đen - XL', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(205, 121, 1, 91, N'Áo khoác gió chống nắng - Hồng - Free size', 1, 1.0000, 299000.0000, 0.0000, 0.00, NULL, 0.0000, 299000.00, 0.00, 299000.00, 120000.0000, 1.0000, 0.0000, 0.0000, NULL),
(206, 122, 1, 82, N'Áo thun oversize in chữ - Đen - M', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(207, 122, 2, 138, N'Váy đầm hoa nhí - Xanh dương - M', 1, 1.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 399000.00, 0.00, 399000.00, 160000.0000, 1.0000, 0.0000, 0.0000, NULL),
(208, 123, 1, 53, N'Giày sneaker trắng - Đen - 43', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(209, 123, 2, 112, N'Áo thun oversize in chữ - Trắng - M', 1, 2.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 398000.00, 0.00, 398000.00, 80000.0000, 2.0000, 0.0000, 0.0000, NULL),
(210, 123, 3, 1, N'Áo thun oversize in chữ - Be - M', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(211, 124, 1, 124, N'Áo polo pique - Trắng - L', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(212, 125, 1, 99, N'Giày tây da bò - Nâu - 41', 21, 1.0000, 990000.0000, 0.0000, 0.00, NULL, 0.0000, 990000.00, 0.00, 990000.00, 450000.0000, 1.0000, 0.0000, 0.0000, NULL),
(213, 125, 2, 152, N'Áo thun basic cổ tròn - Xanh navy - L', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(214, 126, 1, 167, N'Áo khoác bomber - Xanh rêu - L', 1, 2.0000, 599000.0000, 0.0000, 0.00, NULL, 0.0000, 1198000.00, 0.00, 1198000.00, 260000.0000, 2.0000, 0.0000, 0.0000, NULL),
(215, 126, 2, 70, N'Quần jeans slim fit - Đen - 30', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(216, 126, 3, 125, N'Áo polo pique - Trắng - XL', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(217, 127, 1, 87, N'Váy đầm hoa nhí - Hồng - L', 1, 1.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 399000.00, 0.00, 399000.00, 160000.0000, 1.0000, 0.0000, 0.0000, NULL),
(218, 128, 1, 163, N'Quần jeans nữ ống rộng - Xanh nhạt - S', 1, 1.0000, 429000.0000, 0.0000, 0.00, NULL, 0.0000, 429000.00, 0.00, 429000.00, 185000.0000, 1.0000, 0.0000, 0.0000, NULL),
(219, 128, 2, 68, N'Quần short thể thao - Đen - XL', 1, 1.0000, 179000.0000, 10.0000, 17900.00, NULL, 0.0000, 161100.00, 0.00, 161100.00, 70000.0000, 1.0000, 0.0000, 0.0000, NULL),
(220, 128, 3, 122, N'Áo sơ mi trắng công sở - Trắng - XL', 1, 1.0000, 329000.0000, 0.0000, 0.00, NULL, 0.0000, 329000.00, 0.00, 329000.00, 140000.0000, 1.0000, 0.0000, 0.0000, NULL),
(221, 129, 1, 130, N'Áo thun basic cổ tròn - Xám - S', 1, 2.0000, 159000.0000, 10.0000, 31800.00, NULL, 0.0000, 286200.00, 0.00, 286200.00, 65000.0000, 2.0000, 0.0000, 0.0000, NULL),
(222, 130, 1, 46, N'Giày sneaker trắng - Đen - 36', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(223, 131, 1, 5, N'Áo sơ mi nữ lụa - Be - M', 1, 1.0000, 359000.0000, 0.0000, 0.00, NULL, 0.0000, 359000.00, 0.00, 359000.00, 150000.0000, 1.0000, 0.0000, 0.0000, NULL),
(224, 132, 1, 120, N'Áo sơ mi trắng công sở - Trắng - M', 1, 1.0000, 329000.0000, 10.0000, 32900.00, NULL, 0.0000, 296100.00, 0.00, 296100.00, 140000.0000, 1.0000, 0.0000, 0.0000, NULL),
(225, 132, 2, 12, N'Chân váy chữ A - Be - M', 1, 1.0000, 279000.0000, 0.0000, 0.00, NULL, 0.0000, 279000.00, 0.00, 279000.00, 110000.0000, 1.0000, 0.0000, 0.0000, NULL),
(226, 133, 1, 136, N'Quần short thể thao - Xám - XL', 1, 1.0000, 179000.0000, 0.0000, 0.00, NULL, 0.0000, 179000.00, 0.00, 179000.00, 70000.0000, 1.0000, 0.0000, 0.0000, NULL),
(227, 133, 2, 35, N'Dép sandal quai ngang - Đen - 40', 21, 2.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 498000.00, 0.00, 498000.00, 95000.0000, 2.0000, 0.0000, 0.0000, NULL),
(228, 134, 1, 50, N'Giày sneaker trắng - Đen - 40', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(229, 134, 2, 110, N'Giày sneaker trắng - Trắng - 42', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(230, 134, 3, 164, N'Quần jeans nữ ống rộng - Xanh nhạt - M', 1, 1.0000, 429000.0000, 10.0000, 42900.00, NULL, 0.0000, 386100.00, 0.00, 386100.00, 185000.0000, 1.0000, 0.0000, 0.0000, NULL),
(231, 135, 1, 127, N'Áo sơ mi nữ lụa - Trắng - S', 1, 1.0000, 359000.0000, 0.0000, 0.00, NULL, 0.0000, 359000.00, 0.00, 359000.00, 150000.0000, 1.0000, 0.0000, 0.0000, NULL),
(232, 136, 1, 103, N'Áo khoác gió chống nắng - Trắng - Free size', 1, 1.0000, 299000.0000, 0.0000, 0.00, NULL, 0.0000, 299000.00, 0.00, 299000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(233, 137, 1, 94, N'Váy đầm hoa nhí - Kem - L', 1, 2.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 798000.00, 0.00, 798000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(234, 137, 2, 150, N'Áo thun basic cổ tròn - Xanh navy - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(235, 138, 1, 2, N'Áo thun oversize in chữ - Be - L', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(236, 139, 1, 84, N'Áo thun oversize in chữ - Đen - XL', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(237, 140, 1, 58, N'Giày cao gót mũi nhọn - Đen - 39', 21, 2.0000, 520000.0000, 0.0000, 0.00, NULL, 0.0000, 1040000.00, 0.00, 1040000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(238, 141, 1, 133, N'Áo thun basic cổ tròn - Xám - XL', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(239, 141, 2, 31, N'Giày tây da bò - Đen - 43', 21, 1.0000, 990000.0000, 0.0000, 0.00, NULL, 0.0000, 990000.00, 0.00, 990000.00, 450000.0000, 1.0000, 0.0000, 0.0000, NULL),
(240, 142, 1, 53, N'Giày sneaker trắng - Đen - 43', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(241, 143, 1, 48, N'Giày sneaker trắng - Đen - 38', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(242, 143, 2, 107, N'Giày sneaker trắng - Trắng - 39', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(243, 143, 3, 161, N'Quần kaki chinos - Xanh navy - 32', 1, 1.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 389000.00, 0.00, 389000.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(244, 144, 1, 9, N'Quần kaki chinos - Be - 31', 1, 2.0000, 389000.0000, 10.0000, 77800.00, NULL, 0.0000, 700200.00, 0.00, 700200.00, 165000.0000, 2.0000, 0.0000, 0.0000, NULL),
(245, 144, 2, 77, N'Áo thun basic cổ tròn - Đen - XL', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(246, 145, 1, 99, N'Giày tây da bò - Nâu - 41', 21, 1.0000, 990000.0000, 0.0000, 0.00, NULL, 0.0000, 990000.00, 0.00, 990000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(247, 146, 1, 167, N'Áo khoác bomber - Xanh rêu - L', 1, 1.0000, 599000.0000, 10.0000, 59900.00, NULL, 0.0000, 539100.00, 0.00, 539100.00, 260000.0000, 1.0000, 0.0000, 0.0000, NULL),
(248, 147, 1, 139, N'Váy đầm hoa nhí - Xanh dương - L', 1, 2.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 798000.00, 0.00, 798000.00, 160000.0000, 2.0000, 0.0000, 0.0000, NULL),
(249, 147, 2, 38, N'Mũ lưỡi trai - Đen - Free size', 1, 1.0000, 129000.0000, 0.0000, 0.00, NULL, 0.0000, 129000.00, 0.00, 129000.00, 45000.0000, 1.0000, 0.0000, 0.0000, NULL),
(250, 147, 3, 102, N'Tất cổ ngắn (combo 3 đôi) - Trắng - Free size', 12, 1.0000, 79000.0000, 0.0000, 0.00, NULL, 0.0000, 79000.00, 0.00, 79000.00, 28000.0000, 1.0000, 0.0000, 0.0000, NULL),
(251, 148, 1, 91, N'Áo khoác gió chống nắng - Hồng - Free size', 1, 1.0000, 299000.0000, 0.0000, 0.00, NULL, 0.0000, 299000.00, 0.00, 299000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(252, 148, 2, 147, N'Quần jeans slim fit - Xanh jean - 31', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(253, 149, 1, 14, N'Dép sandal quai ngang - Be - 37', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(254, 149, 2, 81, N'Áo polo pique - Đen - XXL', 1, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 105000.0000, 1.0000, 0.0000, 0.0000, NULL),
(255, 149, 3, 137, N'Váy đầm hoa nhí - Xanh dương - S', 1, 1.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 399000.00, 0.00, 399000.00, 160000.0000, 1.0000, 0.0000, 0.0000, NULL),
(256, 150, 1, 103, N'Áo khoác gió chống nắng - Trắng - Free size', 1, 1.0000, 299000.0000, 0.0000, 0.00, NULL, 0.0000, 299000.00, 0.00, 299000.00, 120000.0000, 1.0000, 0.0000, 0.0000, NULL),
(257, 151, 1, 9, N'Quần kaki chinos - Be - 31', 1, 1.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 389000.00, 0.00, 389000.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(258, 151, 2, 77, N'Áo thun basic cổ tròn - Đen - XL', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(259, 151, 3, 134, N'Quần short thể thao - Xám - M', 1, 1.0000, 179000.0000, 0.0000, 0.00, NULL, 0.0000, 179000.00, 0.00, 179000.00, 70000.0000, 1.0000, 0.0000, 0.0000, NULL),
(260, 152, 1, 130, N'Áo thun basic cổ tròn - Xám - S', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(261, 152, 2, 26, N'Tất cổ ngắn (combo 3 đôi) - Đen - Free size', 12, 1.0000, 79000.0000, 0.0000, 0.00, NULL, 0.0000, 79000.00, 0.00, 79000.00, 28000.0000, 1.0000, 0.0000, 0.0000, NULL),
(262, 153, 1, 106, N'Giày sneaker trắng - Trắng - 38', 21, 2.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 1380000.00, 0.00, 1380000.00, 310000.0000, 2.0000, 0.0000, 0.0000, NULL),
(263, 154, 1, 99, N'Giày tây da bò - Nâu - 41', 21, 1.0000, 990000.0000, 0.0000, 0.00, NULL, 0.0000, 990000.00, 0.00, 990000.00, 450000.0000, 1.0000, 0.0000, 0.0000, NULL),
(264, 155, 1, 2, N'Áo thun oversize in chữ - Be - L', 1, 1.0000, 199000.0000, 0.0000, 0.00, NULL, 0.0000, 199000.00, 0.00, 199000.00, 80000.0000, 1.0000, 0.0000, 0.0000, NULL),
(265, 155, 2, 73, N'Quần jeans slim fit - Đen - 34', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 200000.0000, 1.0000, 0.0000, 0.0000, NULL),
(266, 156, 1, 143, N'Áo sơ mi trắng công sở - Xanh dương - L', 1, 1.0000, 329000.0000, 0.0000, 0.00, NULL, 0.0000, 329000.00, 0.00, 329000.00, 140000.0000, 1.0000, 0.0000, 0.0000, NULL),
(267, 157, 1, 91, N'Áo khoác gió chống nắng - Hồng - Free size', 1, 1.0000, 299000.0000, 0.0000, 0.00, NULL, 0.0000, 299000.00, 0.00, 299000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(268, 157, 2, 147, N'Quần jeans slim fit - Xanh jean - 31', 1, 2.0000, 459000.0000, 10.0000, 91800.00, NULL, 0.0000, 826200.00, 0.00, 826200.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(269, 158, 1, 65, N'Quần jeans nữ ống rộng - Đen - L', 1, 1.0000, 429000.0000, 0.0000, 0.00, NULL, 0.0000, 429000.00, 0.00, 429000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(270, 158, 2, 119, N'Áo sơ mi trắng công sở - Trắng - S', 1, 1.0000, 329000.0000, 0.0000, 0.00, NULL, 0.0000, 329000.00, 0.00, 329000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(271, 159, 1, 5, N'Áo sơ mi nữ lụa - Be - M', 1, 1.0000, 359000.0000, 0.0000, 0.00, NULL, 0.0000, 359000.00, 0.00, 359000.00, 150000.0000, 1.0000, 0.0000, 0.0000, NULL),
(272, 159, 2, 75, N'Áo thun basic cổ tròn - Đen - M', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(273, 160, 1, 139, N'Váy đầm hoa nhí - Xanh dương - L', 1, 1.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 399000.00, 0.00, 399000.00, 160000.0000, 1.0000, 0.0000, 0.0000, NULL),
(274, 161, 1, 94, N'Váy đầm hoa nhí - Kem - L', 1, 1.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 399000.00, 0.00, 399000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(275, 162, 1, 133, N'Áo thun basic cổ tròn - Xám - XL', 1, 1.0000, 159000.0000, 0.0000, 0.00, NULL, 0.0000, 159000.00, 0.00, 159000.00, 65000.0000, 1.0000, 0.0000, 0.0000, NULL),
(276, 162, 2, 31, N'Giày tây da bò - Đen - 43', 21, 1.0000, 990000.0000, 0.0000, 0.00, NULL, 0.0000, 990000.00, 0.00, 990000.00, 450000.0000, 1.0000, 0.0000, 0.0000, NULL),
(277, 162, 3, 92, N'Váy đầm hoa nhí - Kem - S', 1, 2.0000, 399000.0000, 10.0000, 79800.00, NULL, 0.0000, 718200.00, 0.00, 718200.00, 160000.0000, 2.0000, 0.0000, 0.0000, NULL),
(278, 163, 1, 87, N'Váy đầm hoa nhí - Hồng - L', 1, 1.0000, 399000.0000, 0.0000, 0.00, NULL, 0.0000, 399000.00, 0.00, 399000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(279, 163, 2, 145, N'Quần jeans slim fit - Xanh jean - 29', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(280, 163, 3, 47, N'Giày sneaker trắng - Đen - 37', 21, 2.0000, 690000.0000, 10.0000, 138000.00, NULL, 0.0000, 1242000.00, 0.00, 1242000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(281, 164, 1, 108, N'Giày sneaker trắng - Trắng - 40', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(282, 164, 2, 162, N'Mũ lưỡi trai - Xanh navy - Free size', 1, 1.0000, 129000.0000, 0.0000, 0.00, NULL, 0.0000, 129000.00, 0.00, 129000.00, 45000.0000, 1.0000, 0.0000, 0.0000, NULL),
(283, 165, 1, 62, N'Quần kaki chinos - Đen - 32', 1, 1.0000, 389000.0000, 0.0000, 0.00, NULL, 0.0000, 389000.00, 0.00, 389000.00, 165000.0000, 1.0000, 0.0000, 0.0000, NULL),
(284, 166, 1, 53, N'Giày sneaker trắng - Đen - 43', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 310000.0000, 1.0000, 0.0000, 0.0000, NULL),
(285, 167, 1, 17, N'Dép sandal quai ngang - Be - 40', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(286, 168, 1, 136, N'Quần short thể thao - Xám - XL', 1, 1.0000, 179000.0000, 0.0000, 0.00, NULL, 0.0000, 179000.00, 0.00, 179000.00, 70000.0000, 1.0000, 0.0000, 0.0000, NULL),
(287, 168, 2, 35, N'Dép sandal quai ngang - Đen - 40', 21, 1.0000, 249000.0000, 0.0000, 0.00, NULL, 0.0000, 249000.00, 0.00, 249000.00, 95000.0000, 1.0000, 0.0000, 0.0000, NULL),
(288, 168, 3, 96, N'Túi xách nữ đeo chéo - Nâu', 1, 1.0000, 459000.0000, 0.0000, 0.00, NULL, 0.0000, 459000.00, 0.00, 459000.00, 190000.0000, 1.0000, 0.0000, 0.0000, NULL),
(289, 169, 1, 58, N'Giày cao gót mũi nhọn - Đen - 39', 21, 1.0000, 520000.0000, 10.0000, 52000.00, NULL, 0.0000, 468000.00, 0.00, 468000.00, 220000.0000, 1.0000, 0.0000, 0.0000, NULL),
(290, 170, 1, 50, N'Giày sneaker trắng - Đen - 40', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(291, 170, 2, 110, N'Giày sneaker trắng - Trắng - 42', 21, 1.0000, 690000.0000, 0.0000, 0.00, NULL, 0.0000, 690000.00, 0.00, 690000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(292, 171, 1, 124, N'Áo polo pique - Trắng - L', 1, 40.0000, 249000.0000, 15.0000, 1494000.00, NULL, 0.0000, 8466000.00, 0.00, 8466000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(293, 171, 2, 154, N'Áo polo pique - Xanh navy - M', 1, 30.0000, 249000.0000, 15.0000, 1120500.00, NULL, 0.0000, 6349500.00, 0.00, 6349500.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(294, 172, 1, 79, N'Áo polo pique - Đen - L', 1, 20.0000, 249000.0000, 10.0000, 498000.00, NULL, 0.0000, 4482000.00, 0.00, 4482000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL),
(295, 172, 2, 61, N'Quần kaki chinos - Đen - 31', 1, 20.0000, 389000.0000, 10.0000, 778000.00, NULL, 0.0000, 7002000.00, 0.00, 7002000.00, 0.0000, 0.0000, 0.0000, 0.0000, NULL)
;
SET IDENTITY_INSERT [sales].[SalesOrderLines] OFF;
GO

-- sales.SalesOrders (172 dòng)
SET IDENTITY_INSERT [sales].[SalesOrders] ON;
INSERT INTO [sales].[SalesOrders] ([Id], [CompanyId], [BranchId], [DocNo], [QuotationId], [PartnerId], [ContactId], [OrderDate], [ExpectedDeliveryDate], [Channel], [ExternalOrderNo], [CurrencyCode], [ExchangeRate], [PriceListId], [PaymentTermId], [PaymentMethodCode], [SalespersonUserId], [WarehouseId], [BillingAddressId], [ShippingAddressId], [ReceiverName], [ReceiverPhone], [ShippingStreet], [ShippingWardCode], [ShippingProvinceCode], [Status], [DeliveryStatus], [InvoiceStatus], [PaymentStatus], [SubTotal], [DiscountAmount], [TaxAmount], [ShippingFee], [TotalAmount], [AmountPaid], [Note], [InternalNote], [ConfirmedAt], [ConfirmedBy], [CancelledAt], [CancelReason], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted], [ReturnedAmount]) VALUES
(1, 1, NULL, 'DH2609-00001', NULL, 38, NULL, '2026-09-24T02:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 836000.00, 0.00, 0.00, 0.00, 836000.00, 836000.00, NULL, NULL, '2026-09-24T02:10:00.0000000', 1, NULL, NULL, '2026-09-24T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(2, 1, NULL, 'DH2609-00002', NULL, 29, NULL, '2026-09-25T03:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1080000.00, 0.00, 0.00, 0.00, 1080000.00, 1080000.00, NULL, NULL, '2026-09-25T03:10:00.0000000', 1, NULL, NULL, '2026-09-25T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(3, 1, NULL, 'DH2609-00003', NULL, 39, NULL, '2026-09-25T09:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 548000.00, 0.00, 0.00, 30000.00, 578000.00, 578000.00, NULL, NULL, '2026-09-25T09:10:00.0000000', 1, NULL, NULL, '2026-09-25T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(4, 1, NULL, 'DH2609-00004', NULL, 40, NULL, '2026-09-25T12:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1010000.00, 0.00, 0.00, 30000.00, 1040000.00, 1040000.00, NULL, NULL, '2026-09-25T12:10:00.0000000', 1, NULL, NULL, '2026-09-25T12:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(5, 1, NULL, 'DH2609-00005', NULL, 37, NULL, '2026-09-27T03:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 718200.00, 0.00, 0.00, 30000.00, 748200.00, 748200.00, NULL, NULL, '2026-09-27T03:10:00.0000000', 1, NULL, NULL, '2026-09-27T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(6, 1, NULL, 'DH2609-00006', NULL, 40, NULL, '2026-09-28T04:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 459000.00, 0.00, 0.00, 30000.00, 489000.00, 489000.00, NULL, NULL, '2026-09-28T04:10:00.0000000', 1, NULL, NULL, '2026-09-28T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(7, 1, NULL, 'DH2609-00007', NULL, 38, NULL, '2026-09-28T06:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 179000.00, 0.00, 0.00, 30000.00, 209000.00, 209000.00, NULL, NULL, '2026-09-28T06:10:00.0000000', 1, NULL, NULL, '2026-09-28T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(8, 1, NULL, 'DH2609-00008', NULL, 29, NULL, '2026-09-28T13:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 249000.00, 20000.00, 0.00, 0.00, 229000.00, 229000.00, NULL, NULL, '2026-09-28T13:10:00.0000000', 1, NULL, NULL, '2026-09-28T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(9, 1, NULL, 'DH2609-00009', NULL, 41, NULL, '2026-09-29T07:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1578000.00, 20000.00, 0.00, 30000.00, 1588000.00, 1588000.00, NULL, NULL, '2026-09-29T07:10:00.0000000', 1, NULL, NULL, '2026-09-29T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(10, 1, NULL, 'DH2609-00010', NULL, 37, NULL, '2026-09-30T07:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1438000.00, 0.00, 0.00, 0.00, 1438000.00, 1438000.00, NULL, NULL, '2026-09-30T07:10:00.0000000', 1, NULL, NULL, '2026-09-30T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(11, 1, NULL, 'DH2610-00001', NULL, 39, NULL, '2026-10-01T05:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 608000.00, 0.00, 0.00, 30000.00, 638000.00, 638000.00, NULL, NULL, '2026-10-01T05:10:00.0000000', 1, NULL, NULL, '2026-10-01T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(12, 1, NULL, 'DH2610-00002', NULL, 29, NULL, '2026-10-01T08:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 520000.00, 0.00, 0.00, 0.00, 520000.00, 520000.00, NULL, NULL, '2026-10-01T08:10:00.0000000', 1, NULL, NULL, '2026-10-01T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(13, 1, NULL, 'DH2610-00003', NULL, 38, NULL, '2026-10-01T10:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 797000.00, 0.00, 0.00, 30000.00, 827000.00, 0.00, NULL, NULL, NULL, NULL, '2026-10-01T12:00:00.0000000', N'Khách đổi ý, không mua nữa', '2026-10-01T10:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(14, 1, NULL, 'DH2610-00004', NULL, 41, NULL, '2026-10-02T11:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 459000.00, 0.00, 0.00, 30000.00, 489000.00, 489000.00, NULL, NULL, '2026-10-02T11:10:00.0000000', 1, NULL, NULL, '2026-10-02T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(15, 1, NULL, 'DH2610-00005', NULL, 37, NULL, '2026-10-03T11:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 778000.00, 0.00, 0.00, 30000.00, 808000.00, 808000.00, NULL, NULL, '2026-10-03T11:10:00.0000000', 1, NULL, NULL, '2026-10-03T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(16, 1, NULL, 'DH2610-00006', NULL, 29, NULL, '2026-10-04T02:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 429000.00, 0.00, 0.00, 0.00, 429000.00, 0.00, NULL, NULL, NULL, NULL, '2026-10-04T04:00:00.0000000', N'Khách đổi ý, không mua nữa', '2026-10-04T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(17, 1, NULL, 'DH2610-00007', NULL, 39, NULL, '2026-10-04T09:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1177000.00, 0.00, 0.00, 30000.00, 1207000.00, 1207000.00, NULL, NULL, '2026-10-04T09:10:00.0000000', 1, NULL, NULL, '2026-10-04T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(18, 1, NULL, 'DH2610-00008', NULL, 40, NULL, '2026-10-04T12:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1793100.00, 20000.00, 0.00, 30000.00, 1803100.00, 1803100.00, NULL, NULL, '2026-10-04T12:10:00.0000000', 1, NULL, NULL, '2026-10-04T12:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(19, 1, NULL, 'DH2610-00009', NULL, 29, NULL, '2026-10-06T03:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 847200.00, 0.00, 0.00, 0.00, 847200.00, 847200.00, NULL, NULL, '2026-10-06T03:10:00.0000000', 1, NULL, NULL, '2026-10-06T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(20, 1, NULL, 'DH2610-00010', NULL, 36, NULL, '2026-10-06T12:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 990000.00, 0.00, 0.00, 30000.00, 1020000.00, 1020000.00, NULL, NULL, '2026-10-06T12:10:00.0000000', 1, NULL, NULL, '2026-10-06T12:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(21, 1, NULL, 'DH2610-00011', NULL, 29, NULL, '2026-10-07T04:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 199000.00, 0.00, 0.00, 0.00, 199000.00, 199000.00, NULL, NULL, '2026-10-07T04:10:00.0000000', 1, NULL, NULL, '2026-10-07T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(22, 1, NULL, 'DH2610-00012', NULL, 38, NULL, '2026-10-07T10:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 249000.00, 0.00, 0.00, 30000.00, 279000.00, 279000.00, NULL, NULL, '2026-10-07T10:10:00.0000000', 1, NULL, NULL, '2026-10-07T10:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(23, 1, NULL, 'DH2610-00013', NULL, 39, NULL, '2026-10-07T13:00:00.0000000', NULL, 'zalo', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 459000.00, 20000.00, 0.00, 30000.00, 469000.00, 469000.00, NULL, NULL, '2026-10-07T13:10:00.0000000', 1, NULL, NULL, '2026-10-07T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(24, 1, NULL, 'DH2610-00014', NULL, 38, NULL, '2026-10-09T02:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 2529000.00, 0.00, 0.00, 0.00, 2529000.00, 2529000.00, NULL, NULL, '2026-10-09T02:10:00.0000000', 1, NULL, NULL, '2026-10-09T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(25, 1, NULL, 'DH2610-00015', NULL, 36, NULL, '2026-10-09T04:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 548000.00, 0.00, 0.00, 30000.00, 578000.00, 578000.00, NULL, NULL, '2026-10-09T04:10:00.0000000', 1, NULL, NULL, '2026-10-09T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(26, 1, NULL, 'DH2610-00016', NULL, 37, NULL, '2026-10-09T07:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 2198000.00, 20000.00, 0.00, 30000.00, 2208000.00, 2208000.00, NULL, NULL, '2026-10-09T07:10:00.0000000', 1, NULL, NULL, '2026-10-09T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(27, 1, NULL, 'DH2610-00017', NULL, 39, NULL, '2026-10-10T05:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 438000.00, 20000.00, 0.00, 30000.00, 448000.00, 448000.00, NULL, NULL, '2026-10-10T05:10:00.0000000', 1, NULL, NULL, '2026-10-10T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(28, 1, NULL, 'DH2610-00018', NULL, 40, NULL, '2026-10-10T08:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 318000.00, 0.00, 0.00, 30000.00, 348000.00, 348000.00, NULL, NULL, '2026-10-10T08:10:00.0000000', 1, NULL, NULL, '2026-10-10T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(29, 1, NULL, 'DH2610-00019', NULL, 38, NULL, '2026-10-12T06:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 690000.00, 20000.00, 0.00, 30000.00, 700000.00, 700000.00, NULL, NULL, '2026-10-12T06:10:00.0000000', 1, NULL, NULL, '2026-10-12T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(30, 1, NULL, 'DH2610-00020', NULL, 29, NULL, '2026-10-12T08:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 249000.00, 0.00, 0.00, 0.00, 249000.00, 249000.00, NULL, NULL, '2026-10-12T08:10:00.0000000', 1, NULL, NULL, '2026-10-12T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(31, 1, NULL, 'DH2610-00021', NULL, 37, NULL, '2026-10-12T11:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 918000.00, 0.00, 0.00, 30000.00, 948000.00, 948000.00, NULL, NULL, '2026-10-12T11:10:00.0000000', 1, NULL, NULL, '2026-10-12T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(32, 1, NULL, 'DH2610-00022', NULL, 29, NULL, '2026-10-13T09:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 159000.00, 0.00, 0.00, 0.00, 159000.00, 159000.00, NULL, NULL, '2026-10-13T09:10:00.0000000', 1, NULL, NULL, '2026-10-13T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(33, 1, NULL, 'DH2610-00023', NULL, 35, NULL, '2026-10-14T09:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 548000.00, 0.00, 0.00, 30000.00, 578000.00, 578000.00, NULL, NULL, '2026-10-14T09:10:00.0000000', 1, NULL, NULL, '2026-10-14T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(34, 1, NULL, 'DH2610-00024', NULL, 36, NULL, '2026-10-14T12:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1298000.00, 0.00, 0.00, 30000.00, 1328000.00, 1328000.00, NULL, NULL, '2026-10-14T12:10:00.0000000', 1, NULL, NULL, '2026-10-14T12:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(35, 1, NULL, 'DH2610-00025', NULL, 37, NULL, '2026-10-15T03:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1335000.00, 0.00, 0.00, 0.00, 1335000.00, 1335000.00, NULL, NULL, '2026-10-15T03:10:00.0000000', 1, NULL, NULL, '2026-10-15T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(36, 1, NULL, 'DH2610-00026', NULL, 38, NULL, '2026-10-15T10:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 745200.00, 0.00, 0.00, 30000.00, 775200.00, 775200.00, NULL, NULL, '2026-10-15T10:10:00.0000000', 1, NULL, NULL, '2026-10-15T10:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(37, 1, NULL, 'DH2610-00027', NULL, 39, NULL, '2026-10-15T13:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 518000.00, 0.00, 0.00, 30000.00, 548000.00, 548000.00, NULL, NULL, '2026-10-15T13:10:00.0000000', 1, NULL, NULL, '2026-10-15T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(38, 1, NULL, 'DH2610-00028', NULL, 29, NULL, '2026-10-17T02:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 249000.00, 0.00, 0.00, 0.00, 249000.00, 249000.00, NULL, NULL, '2026-10-17T02:10:00.0000000', 1, NULL, NULL, '2026-10-17T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(39, 1, NULL, 'DH2610-00029', NULL, 29, NULL, '2026-10-17T04:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 690000.00, 0.00, 0.00, 0.00, 690000.00, 690000.00, NULL, NULL, '2026-10-17T04:10:00.0000000', 1, NULL, NULL, '2026-10-17T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(40, 1, NULL, 'DH2610-00030', NULL, 37, NULL, '2026-10-17T11:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 918000.00, 20000.00, 0.00, 30000.00, 928000.00, 928000.00, NULL, NULL, '2026-10-17T11:10:00.0000000', 1, NULL, NULL, '2026-10-17T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(41, 1, NULL, 'DH2610-00031', NULL, 35, NULL, '2026-10-17T13:00:00.0000000', NULL, 'zalo', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 429000.00, 20000.00, 0.00, 30000.00, 439000.00, 439000.00, NULL, NULL, '2026-10-17T13:10:00.0000000', 1, NULL, NULL, '2026-10-17T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(42, 1, NULL, 'DH2610-00032', NULL, 39, NULL, '2026-10-18T05:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 926000.00, 0.00, 0.00, 30000.00, 956000.00, 956000.00, NULL, NULL, '2026-10-18T05:10:00.0000000', 1, NULL, NULL, '2026-10-18T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(43, 1, NULL, 'DH2610-00033', NULL, 35, NULL, '2026-10-19T05:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 777000.00, 0.00, 0.00, 30000.00, 807000.00, 807000.00, NULL, NULL, '2026-10-19T05:10:00.0000000', 1, NULL, NULL, '2026-10-19T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(44, 1, NULL, 'DH2610-00034', NULL, 36, NULL, '2026-10-19T08:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 708000.00, 0.00, 0.00, 30000.00, 738000.00, 738000.00, NULL, NULL, '2026-10-19T08:10:00.0000000', 1, NULL, NULL, '2026-10-19T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(45, 1, NULL, 'DH2610-00035', NULL, 29, NULL, '2026-10-20T03:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 597000.00, 0.00, 0.00, 0.00, 597000.00, 0.00, NULL, NULL, NULL, NULL, '2026-10-20T05:00:00.0000000', N'Khách đổi ý, không mua nữa', '2026-10-20T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(46, 1, NULL, 'DH2610-00036', NULL, 38, NULL, '2026-10-20T06:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 159000.00, 0.00, 0.00, 30000.00, 189000.00, 189000.00, NULL, NULL, '2026-10-20T06:10:00.0000000', 1, NULL, NULL, '2026-10-20T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(47, 1, NULL, 'DH2610-00037', NULL, 34, NULL, '2026-10-21T06:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 690000.00, 0.00, 0.00, 30000.00, 720000.00, 720000.00, NULL, NULL, '2026-10-21T06:10:00.0000000', 1, NULL, NULL, '2026-10-21T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(48, 1, NULL, 'DH2610-00038', NULL, 37, NULL, '2026-10-22T07:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 1435200.00, 0.00, 0.00, 30000.00, 1465200.00, 0.00, NULL, NULL, NULL, NULL, '2026-10-22T09:00:00.0000000', N'Khách đổi ý, không mua nữa', '2026-10-22T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(49, 1, NULL, 'DH2610-00039', NULL, 29, NULL, '2026-10-22T09:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 459000.00, 0.00, 0.00, 0.00, 459000.00, 459000.00, NULL, NULL, '2026-10-22T09:10:00.0000000', 1, NULL, NULL, '2026-10-22T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(50, 1, NULL, 'DH2610-00040', NULL, 38, NULL, '2026-10-22T10:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1018200.00, 0.00, 0.00, 0.00, 1018200.00, 1018200.00, NULL, NULL, '2026-10-22T10:10:00.0000000', 1, NULL, NULL, '2026-10-22T10:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(51, 1, NULL, 'DH2610-00041', NULL, 36, NULL, '2026-10-22T12:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 79000.00, 0.00, 0.00, 30000.00, 109000.00, 109000.00, NULL, NULL, '2026-10-22T12:10:00.0000000', 1, NULL, NULL, '2026-10-22T12:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(52, 1, NULL, 'DH2610-00042', NULL, 29, NULL, '2026-10-24T04:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 159000.00, 0.00, 0.00, 0.00, 159000.00, 159000.00, NULL, NULL, '2026-10-24T04:10:00.0000000', 1, NULL, NULL, '2026-10-24T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(53, 1, NULL, 'DH2610-00043', NULL, 34, NULL, '2026-10-24T10:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 413100.00, 0.00, 0.00, 30000.00, 443100.00, 443100.00, NULL, NULL, '2026-10-24T10:10:00.0000000', 1, NULL, NULL, '2026-10-24T10:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(54, 1, NULL, 'DH2610-00044', NULL, 37, NULL, '2026-10-24T11:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 498000.00, 0.00, 0.00, 30000.00, 528000.00, 528000.00, NULL, NULL, '2026-10-24T11:10:00.0000000', 1, NULL, NULL, '2026-10-24T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(55, 1, NULL, 'DH2610-00045', NULL, 35, NULL, '2026-10-24T13:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1076100.00, 0.00, 0.00, 30000.00, 1106100.00, 1106100.00, NULL, NULL, '2026-10-24T13:10:00.0000000', 1, NULL, NULL, '2026-10-24T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(56, 1, NULL, 'DH2610-00046', NULL, 38, NULL, '2026-10-25T02:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 199000.00, 0.00, 0.00, 30000.00, 229000.00, 229000.00, NULL, NULL, '2026-10-25T02:10:00.0000000', 1, NULL, NULL, '2026-10-25T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(57, 1, NULL, 'DH2610-00047', NULL, 29, NULL, '2026-10-26T02:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 919000.00, 0.00, 0.00, 0.00, 919000.00, 919000.00, NULL, NULL, '2026-10-26T02:10:00.0000000', 1, NULL, NULL, '2026-10-26T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(58, 1, NULL, 'DH2610-00048', NULL, 37, NULL, '2026-10-26T03:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 887000.00, 0.00, 0.00, 0.00, 887000.00, 887000.00, NULL, NULL, '2026-10-26T03:10:00.0000000', 1, NULL, NULL, '2026-10-26T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(59, 1, NULL, 'DH2610-00049', NULL, 35, NULL, '2026-10-26T05:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 747000.00, 0.00, 0.00, 30000.00, 777000.00, 777000.00, NULL, NULL, '2026-10-26T05:10:00.0000000', 1, NULL, NULL, '2026-10-26T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(60, 1, NULL, 'DH2610-00050', NULL, 36, NULL, '2026-10-26T12:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 677000.00, 0.00, 0.00, 30000.00, 707000.00, 707000.00, NULL, NULL, '2026-10-26T12:10:00.0000000', 1, NULL, NULL, '2026-10-26T12:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(61, 1, NULL, 'DH2610-00051', NULL, 29, NULL, '2026-10-28T03:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 690000.00, 0.00, 0.00, 0.00, 690000.00, 0.00, NULL, NULL, NULL, NULL, '2026-10-28T05:00:00.0000000', N'Khách đổi ý, không mua nữa', '2026-10-28T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(62, 1, NULL, 'DH2610-00052', NULL, 29, NULL, '2026-10-28T04:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 249000.00, 0.00, 0.00, 0.00, 249000.00, 249000.00, NULL, NULL, '2026-10-28T04:10:00.0000000', 1, NULL, NULL, '2026-10-28T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(63, 1, NULL, 'DH2610-00053', NULL, 34, NULL, '2026-10-28T06:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 459000.00, 0.00, 0.00, 30000.00, 489000.00, 489000.00, NULL, NULL, '2026-10-28T06:10:00.0000000', 1, NULL, NULL, '2026-10-28T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(64, 1, NULL, 'DH2610-00054', NULL, 35, NULL, '2026-10-28T09:00:00.0000000', NULL, 'zalo', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 249000.00, 0.00, 0.00, 30000.00, 279000.00, 279000.00, NULL, NULL, '2026-10-28T09:10:00.0000000', 1, NULL, NULL, '2026-10-28T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(65, 1, NULL, 'DH2610-00055', NULL, 37, NULL, '2026-10-29T07:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Bùi Khánh Linh', '0919008008', N'Q.7, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 592200.00, 0.00, 0.00, 30000.00, 622200.00, 622200.00, NULL, NULL, '2026-10-29T07:10:00.0000000', 1, NULL, NULL, '2026-10-29T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(66, 1, NULL, 'DH2610-00056', NULL, 33, NULL, '2026-10-30T07:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 708000.00, 0.00, 0.00, 30000.00, 738000.00, 0.00, NULL, NULL, NULL, NULL, '2026-10-30T09:00:00.0000000', N'Khách đổi ý, không mua nữa', '2026-10-30T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(67, 1, NULL, 'DH2610-00057', NULL, 36, NULL, '2026-10-30T08:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 538000.00, 0.00, 0.00, 30000.00, 568000.00, 568000.00, NULL, NULL, '2026-10-30T08:10:00.0000000', 1, NULL, NULL, '2026-10-30T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(68, 1, NULL, 'DH2610-00058', NULL, 34, NULL, '2026-10-30T10:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 837100.00, 0.00, 0.00, 0.00, 837100.00, 837100.00, NULL, NULL, '2026-10-30T10:10:00.0000000', 1, NULL, NULL, '2026-10-30T10:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(69, 1, NULL, 'DH2610-00059', NULL, 35, NULL, '2026-10-30T13:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 627000.00, 0.00, 0.00, 30000.00, 657000.00, 657000.00, NULL, NULL, '2026-10-30T13:10:00.0000000', 1, NULL, NULL, '2026-10-30T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(70, 1, NULL, 'DH2610-00060', NULL, 29, NULL, '2026-10-31T11:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 727000.00, 0.00, 0.00, 0.00, 727000.00, 727000.00, NULL, NULL, '2026-10-31T11:10:00.0000000', 1, NULL, NULL, '2026-10-31T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(71, 1, NULL, 'DH2611-00001', NULL, 34, NULL, '2026-11-01T02:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 159000.00, 0.00, 0.00, 30000.00, 189000.00, 189000.00, NULL, NULL, '2026-11-01T02:10:00.0000000', 1, NULL, NULL, '2026-11-01T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(72, 1, NULL, 'DH2611-00002', NULL, 29, NULL, '2026-11-01T05:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 159000.00, 0.00, 0.00, 0.00, 159000.00, 159000.00, NULL, NULL, '2026-11-01T05:10:00.0000000', 1, NULL, NULL, '2026-11-01T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(73, 1, NULL, 'DH2611-00003', NULL, 33, NULL, '2026-11-01T11:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 79000.00, 0.00, 0.00, 30000.00, 109000.00, 109000.00, NULL, NULL, '2026-11-01T11:10:00.0000000', 1, NULL, NULL, '2026-11-01T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(74, 1, NULL, 'DH2611-00004', NULL, 36, NULL, '2026-11-01T12:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 389000.00, 0.00, 0.00, 30000.00, 419000.00, 419000.00, NULL, NULL, '2026-11-01T12:10:00.0000000', 1, NULL, NULL, '2026-11-01T12:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(75, 1, NULL, 'DH2611-00005', NULL, 32, NULL, '2026-11-02T12:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 2007000.00, 0.00, 0.00, 30000.00, 2037000.00, 2037000.00, NULL, NULL, '2026-11-02T12:10:00.0000000', 1, NULL, NULL, '2026-11-02T12:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(76, 1, NULL, 'DH2611-00006', NULL, 33, NULL, '2026-11-03T03:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 849000.00, 0.00, 0.00, 0.00, 849000.00, 849000.00, NULL, NULL, '2026-11-03T03:10:00.0000000', 1, NULL, NULL, '2026-11-03T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(77, 1, NULL, 'DH2611-00007', NULL, 29, NULL, '2026-11-03T04:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 249000.00, 0.00, 0.00, 0.00, 249000.00, 249000.00, NULL, NULL, '2026-11-03T04:10:00.0000000', 1, NULL, NULL, '2026-11-03T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(78, 1, NULL, 'DH2611-00008', NULL, 34, NULL, '2026-11-03T06:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1239000.00, 0.00, 0.00, 30000.00, 1269000.00, 1269000.00, NULL, NULL, '2026-11-03T06:10:00.0000000', 1, NULL, NULL, '2026-11-03T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(79, 1, NULL, 'DH2611-00009', NULL, 35, NULL, '2026-11-03T13:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 598000.00, 0.00, 0.00, 30000.00, 628000.00, 628000.00, NULL, NULL, '2026-11-03T13:10:00.0000000', 1, NULL, NULL, '2026-11-03T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(80, 1, NULL, 'DH2611-00010', NULL, 29, NULL, '2026-11-04T04:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 459000.00, 0.00, 0.00, 0.00, 459000.00, 459000.00, NULL, NULL, '2026-11-04T04:10:00.0000000', 1, NULL, NULL, '2026-11-04T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(81, 1, NULL, 'DH2611-00011', NULL, 33, NULL, '2026-11-04T07:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 159000.00, 0.00, 0.00, 30000.00, 189000.00, 189000.00, NULL, NULL, '2026-11-04T07:10:00.0000000', 1, NULL, NULL, '2026-11-04T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(82, 1, NULL, 'DH2611-00012', NULL, 35, NULL, '2026-11-05T05:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1560000.00, 0.00, 0.00, 30000.00, 1590000.00, 1590000.00, NULL, NULL, '2026-11-05T05:10:00.0000000', 1, NULL, NULL, '2026-11-05T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(83, 1, NULL, 'DH2611-00013', NULL, 36, NULL, '2026-11-05T08:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Hoàng Gia Bảo', '0918007007', N'Lê Chân, Hải Phòng', NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 1479000.00, 0.00, 0.00, 30000.00, 1509000.00, 0.00, NULL, NULL, NULL, NULL, '2026-11-05T10:00:00.0000000', N'Khách đổi ý, không mua nữa', '2026-11-05T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(84, 1, NULL, 'DH2611-00014', NULL, 29, NULL, '2026-11-05T10:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 224100.00, 0.00, 0.00, 0.00, 224100.00, 224100.00, NULL, NULL, '2026-11-05T10:10:00.0000000', 1, NULL, NULL, '2026-11-05T10:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(85, 1, NULL, 'DH2611-00015', NULL, 34, NULL, '2026-11-06T02:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 329000.00, 0.00, 0.00, 30000.00, 359000.00, 359000.00, NULL, NULL, '2026-11-06T02:10:00.0000000', 1, NULL, NULL, '2026-11-06T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(86, 1, NULL, 'DH2611-00016', NULL, 32, NULL, '2026-11-06T08:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 249000.00, 0.00, 0.00, 30000.00, 279000.00, 279000.00, NULL, NULL, '2026-11-06T08:10:00.0000000', 1, NULL, NULL, '2026-11-06T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(87, 1, NULL, 'DH2611-00017', NULL, 35, NULL, '2026-11-06T09:00:00.0000000', NULL, 'zalo', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 429000.00, 0.00, 0.00, 30000.00, 459000.00, 459000.00, NULL, NULL, '2026-11-06T09:10:00.0000000', 1, NULL, NULL, '2026-11-06T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(88, 1, NULL, 'DH2611-00018', NULL, 29, NULL, '2026-11-06T11:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 428000.00, 0.00, 0.00, 0.00, 428000.00, 428000.00, NULL, NULL, '2026-11-06T11:10:00.0000000', 1, NULL, NULL, '2026-11-06T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(89, 1, NULL, 'DH2611-00019', NULL, 29, NULL, '2026-11-07T05:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 597000.00, 0.00, 0.00, 0.00, 597000.00, 597000.00, NULL, NULL, '2026-11-07T05:10:00.0000000', 1, NULL, NULL, '2026-11-07T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(90, 1, NULL, 'DH2611-00020', NULL, 32, NULL, '2026-11-07T12:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 159000.00, 0.00, 0.00, 30000.00, 189000.00, 189000.00, NULL, NULL, '2026-11-07T12:10:00.0000000', 1, NULL, NULL, '2026-11-07T12:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(91, 1, NULL, 'DH2611-00021', NULL, 33, NULL, '2026-11-08T03:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1036000.00, 0.00, 0.00, 30000.00, 1066000.00, 1066000.00, NULL, NULL, '2026-11-08T03:10:00.0000000', 1, NULL, NULL, '2026-11-08T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(92, 1, NULL, 'DH2611-00022', NULL, 34, NULL, '2026-11-08T06:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1127000.00, 0.00, 0.00, 0.00, 1127000.00, 1127000.00, NULL, NULL, '2026-11-08T06:10:00.0000000', 1, NULL, NULL, '2026-11-08T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(93, 1, NULL, 'DH2611-00023', NULL, 35, NULL, '2026-11-08T13:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Đỗ Thị Mai', '0917006006', N'Ninh Kiều, Cần Thơ', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 879000.00, 0.00, 0.00, 30000.00, 909000.00, 909000.00, NULL, NULL, '2026-11-08T13:10:00.0000000', 1, NULL, NULL, '2026-11-08T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(94, 1, NULL, 'DH2611-00024', NULL, 34, NULL, '2026-11-09T02:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 621000.00, 0.00, 0.00, 30000.00, 651000.00, 651000.00, NULL, NULL, '2026-11-09T02:10:00.0000000', 1, NULL, NULL, '2026-11-09T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(95, 1, NULL, 'DH2611-00025', NULL, 29, NULL, '2026-11-09T04:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 159000.00, 0.00, 0.00, 0.00, 159000.00, 159000.00, NULL, NULL, '2026-11-09T04:10:00.0000000', 1, NULL, NULL, '2026-11-09T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(96, 1, NULL, 'DH2611-00026', NULL, 29, NULL, '2026-11-09T05:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 299000.00, 0.00, 0.00, 0.00, 299000.00, 299000.00, NULL, NULL, '2026-11-09T05:10:00.0000000', 1, NULL, NULL, '2026-11-09T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(97, 1, NULL, 'DH2611-00027', NULL, 33, NULL, '2026-11-09T07:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 389000.00, 0.00, 0.00, 30000.00, 419000.00, 419000.00, NULL, NULL, '2026-11-09T07:10:00.0000000', 1, NULL, NULL, '2026-11-09T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(98, 1, NULL, 'DH2611-00028', NULL, 31, NULL, '2026-11-09T13:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 318000.00, 0.00, 0.00, 30000.00, 348000.00, 348000.00, NULL, NULL, '2026-11-09T13:10:00.0000000', 1, NULL, NULL, '2026-11-09T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(99, 1, NULL, 'DH2611-00029', NULL, 31, NULL, '2026-11-10T05:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1438200.00, 0.00, 0.00, 30000.00, 1468200.00, 1468200.00, NULL, NULL, '2026-11-10T05:10:00.0000000', 1, NULL, NULL, '2026-11-10T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(100, 1, NULL, 'DH2611-00030', NULL, 32, NULL, '2026-11-10T08:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 1166200.00, 20000.00, 0.00, 30000.00, 1176200.00, 0.00, NULL, NULL, NULL, NULL, '2026-11-10T10:00:00.0000000', N'Khách đổi ý, không mua nữa', '2026-11-10T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(101, 1, NULL, 'DH2611-00031', NULL, 30, NULL, '2026-11-11T02:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 159000.00, 0.00, 0.00, 30000.00, 189000.00, 189000.00, NULL, NULL, '2026-11-11T02:10:00.0000000', 1, NULL, NULL, '2026-11-11T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(102, 1, NULL, 'DH2611-00032', NULL, 34, NULL, '2026-11-11T06:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1058000.00, 0.00, 0.00, 30000.00, 1088000.00, 1088000.00, NULL, NULL, '2026-11-11T06:10:00.0000000', 1, NULL, NULL, '2026-11-11T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(103, 1, NULL, 'DH2611-00033', NULL, 33, NULL, '2026-11-11T11:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 498000.00, 0.00, 0.00, 0.00, 498000.00, 498000.00, NULL, NULL, '2026-11-11T11:10:00.0000000', 1, NULL, NULL, '2026-11-11T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(104, 1, NULL, 'DH2611-00034', NULL, 33, NULL, '2026-11-12T03:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 399000.00, 0.00, 0.00, 30000.00, 429000.00, 429000.00, NULL, NULL, '2026-11-12T03:10:00.0000000', 1, NULL, NULL, '2026-11-12T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(105, 1, NULL, 'DH2611-00035', NULL, 31, NULL, '2026-11-12T09:00:00.0000000', NULL, 'zalo', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 498000.00, 0.00, 0.00, 30000.00, 528000.00, 528000.00, NULL, NULL, '2026-11-12T09:10:00.0000000', 1, NULL, NULL, '2026-11-12T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(106, 1, NULL, 'DH2611-00036', NULL, 29, NULL, '2026-11-12T10:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 159000.00, 0.00, 0.00, 0.00, 159000.00, 159000.00, NULL, NULL, '2026-11-12T10:10:00.0000000', 1, NULL, NULL, '2026-11-12T10:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(107, 1, NULL, 'DH2611-00037', NULL, 29, NULL, '2026-11-12T12:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 690000.00, 0.00, 0.00, 0.00, 690000.00, 690000.00, NULL, NULL, '2026-11-12T12:10:00.0000000', 1, NULL, NULL, '2026-11-12T12:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(108, 1, NULL, 'DH2611-00038', NULL, 34, NULL, '2026-11-13T02:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Vũ Đức Thắng', '0916005005', N'Bình Thạnh, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 359100.00, 0.00, 0.00, 30000.00, 389100.00, 389100.00, NULL, NULL, '2026-11-13T02:10:00.0000000', 1, NULL, NULL, '2026-11-13T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(109, 1, NULL, 'DH2611-00039', NULL, 32, NULL, '2026-11-13T04:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 787000.00, 0.00, 0.00, 30000.00, 817000.00, 817000.00, NULL, NULL, '2026-11-13T04:10:00.0000000', 1, NULL, NULL, '2026-11-13T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(110, 1, NULL, 'DH2611-00040', NULL, 30, NULL, '2026-11-13T06:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 677000.00, 0.00, 0.00, 0.00, 677000.00, 677000.00, NULL, NULL, '2026-11-13T06:10:00.0000000', 1, NULL, NULL, '2026-11-13T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(111, 1, NULL, 'DH2611-00041', NULL, 29, NULL, '2026-11-13T07:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1380000.00, 0.00, 0.00, 0.00, 1380000.00, 1380000.00, NULL, NULL, '2026-11-13T07:10:00.0000000', 1, NULL, NULL, '2026-11-13T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(112, 1, NULL, 'DH2611-00042', NULL, 31, NULL, '2026-11-13T13:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 937000.00, 0.00, 0.00, 30000.00, 967000.00, 967000.00, NULL, NULL, '2026-11-13T13:10:00.0000000', 1, NULL, NULL, '2026-11-13T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(113, 1, NULL, 'DH2611-00043', NULL, 30, NULL, '2026-11-14T02:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 459000.00, 20000.00, 0.00, 30000.00, 469000.00, 469000.00, NULL, NULL, '2026-11-14T02:10:00.0000000', 1, NULL, NULL, '2026-11-14T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(114, 1, NULL, 'DH2611-00044', NULL, 33, NULL, '2026-11-14T03:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1304200.00, 0.00, 0.00, 30000.00, 1334200.00, 1334200.00, NULL, NULL, '2026-11-14T03:10:00.0000000', 1, NULL, NULL, '2026-11-14T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(115, 1, NULL, 'DH2611-00045', NULL, 29, NULL, '2026-11-14T05:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 358200.00, 0.00, 0.00, 0.00, 358200.00, 358200.00, NULL, NULL, '2026-11-14T05:10:00.0000000', 1, NULL, NULL, '2026-11-14T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(116, 1, NULL, 'DH2611-00046', NULL, 32, NULL, '2026-11-14T08:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 359000.00, 0.00, 0.00, 30000.00, 389000.00, 389000.00, NULL, NULL, '2026-11-14T08:10:00.0000000', 1, NULL, NULL, '2026-11-14T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(117, 1, NULL, 'DH2611-00047', NULL, 30, NULL, '2026-11-15T06:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 818000.00, 0.00, 0.00, 30000.00, 848000.00, 848000.00, NULL, NULL, '2026-11-15T06:10:00.0000000', 1, NULL, NULL, '2026-11-15T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(118, 1, NULL, 'DH2611-00048', NULL, 33, NULL, '2026-11-15T07:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Phạm Ngọc Hân', '0915004004', N'Cầu Giấy, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 159000.00, 0.00, 0.00, 30000.00, 189000.00, 189000.00, NULL, NULL, '2026-11-15T07:10:00.0000000', 1, NULL, NULL, '2026-11-15T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(119, 1, NULL, 'DH2611-00049', NULL, 31, NULL, '2026-11-15T09:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'unpaid', 2070000.00, 0.00, 0.00, 30000.00, 2100000.00, 0.00, NULL, NULL, '2026-11-15T09:10:00.0000000', 1, NULL, NULL, '2026-11-15T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(120, 1, NULL, 'DH2611-00050', NULL, 41, NULL, '2026-11-15T11:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 668100.00, 0.00, 0.00, 0.00, 668100.00, 668100.00, NULL, NULL, '2026-11-15T11:10:00.0000000', 1, NULL, NULL, '2026-11-15T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(121, 1, NULL, 'DH2611-00051', NULL, 29, NULL, '2026-11-15T12:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 299000.00, 0.00, 0.00, 0.00, 0.00, 0.00, NULL, NULL, '2026-11-15T12:10:00.0000000', 1, NULL, NULL, '2026-11-15T12:00:00.0000000', 1, NULL, NULL, 0, 299000.00),
(122, 1, NULL, 'DH2611-00052', NULL, 41, NULL, '2026-11-16T03:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 598000.00, 0.00, 0.00, 30000.00, 628000.00, 628000.00, NULL, NULL, '2026-11-16T03:10:00.0000000', 1, NULL, NULL, '2026-11-16T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(123, 1, NULL, 'DH2611-00053', NULL, 32, NULL, '2026-11-16T04:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 'completed', 'delivered', 'none', 'unpaid', 1287000.00, 0.00, 0.00, 30000.00, 1317000.00, 0.00, NULL, NULL, '2026-11-16T04:10:00.0000000', 1, NULL, NULL, '2026-11-16T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(124, 1, NULL, 'DH2611-00054', NULL, 29, NULL, '2026-11-16T10:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 249000.00, 0.00, 0.00, 0.00, 249000.00, 249000.00, NULL, NULL, '2026-11-16T10:10:00.0000000', 1, NULL, NULL, '2026-11-16T10:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(125, 1, NULL, 'DH2611-00055', NULL, 33, NULL, '2026-11-16T11:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1149000.00, 0.00, 0.00, 0.00, 1149000.00, 1149000.00, NULL, NULL, '2026-11-16T11:10:00.0000000', 1, NULL, NULL, '2026-11-16T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(126, 1, NULL, 'DH2611-00056', NULL, 31, NULL, '2026-11-16T13:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 1906000.00, 0.00, 0.00, 30000.00, 1936000.00, 1936000.00, NULL, NULL, '2026-11-16T13:10:00.0000000', 1, NULL, NULL, '2026-11-16T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(127, 1, NULL, 'DH2611-00057', NULL, 30, NULL, '2026-11-17T02:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 399000.00, 0.00, 0.00, 30000.00, 429000.00, 429000.00, NULL, NULL, '2026-11-17T02:10:00.0000000', 1, NULL, NULL, '2026-11-17T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(128, 1, NULL, 'DH2611-00058', NULL, 41, NULL, '2026-11-17T03:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 'completed', 'delivered', 'none', 'unpaid', 919100.00, 0.00, 0.00, 30000.00, 949100.00, 0.00, NULL, NULL, '2026-11-17T03:10:00.0000000', 1, NULL, NULL, '2026-11-17T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(129, 1, NULL, 'DH2611-00059', NULL, 31, NULL, '2026-11-17T05:00:00.0000000', NULL, 'zalo', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 'completed', 'delivered', 'none', 'unpaid', 286200.00, 0.00, 0.00, 30000.00, 316200.00, 0.00, NULL, NULL, '2026-11-17T05:10:00.0000000', 1, NULL, NULL, '2026-11-17T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(130, 1, NULL, 'DH2611-00060', NULL, 29, NULL, '2026-11-17T07:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 690000.00, 0.00, 0.00, 0.00, 0.00, 0.00, NULL, NULL, '2026-11-17T07:10:00.0000000', 1, NULL, NULL, '2026-11-17T07:00:00.0000000', 1, NULL, NULL, 0, 690000.00),
(131, 1, NULL, 'DH2611-00061', NULL, 29, NULL, '2026-11-17T08:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 359000.00, 0.00, 0.00, 0.00, 0.00, 0.00, NULL, NULL, '2026-11-17T08:10:00.0000000', 1, NULL, NULL, '2026-11-17T08:00:00.0000000', 1, NULL, NULL, 0, 359000.00),
(132, 1, NULL, 'DH2611-00062', NULL, 40, NULL, '2026-11-17T08:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 575100.00, 20000.00, 0.00, 30000.00, 585100.00, 585100.00, NULL, NULL, '2026-11-17T08:10:00.0000000', 1, NULL, NULL, '2026-11-17T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(133, 1, NULL, 'DH2611-00063', NULL, 32, NULL, '2026-11-18T04:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 677000.00, 0.00, 0.00, 30000.00, 707000.00, 0.00, NULL, NULL, '2026-11-18T04:10:00.0000000', 1, NULL, NULL, '2026-11-18T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(134, 1, NULL, 'DH2611-00064', NULL, 30, NULL, '2026-11-18T06:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'confirmed', 'pending', 'none', 'paid', 1766100.00, 0.00, 0.00, 0.00, 1766100.00, 1766100.00, NULL, NULL, '2026-11-18T06:10:00.0000000', 1, NULL, NULL, '2026-11-18T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(135, 1, NULL, 'DH2611-00065', NULL, 41, NULL, '2026-11-18T07:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 359000.00, 0.00, 0.00, 30000.00, 389000.00, 0.00, NULL, NULL, '2026-11-18T07:10:00.0000000', 1, NULL, NULL, '2026-11-18T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(136, 1, NULL, 'DH2611-00066', NULL, 32, NULL, '2026-11-18T08:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Lê Hoàng Nam', '0914003003', N'Hải Châu, Đà Nẵng', NULL, NULL, 'draft', 'pending', 'none', 'unpaid', 299000.00, 0.00, 0.00, 30000.00, 329000.00, 0.00, NULL, NULL, NULL, NULL, NULL, NULL, '2026-11-18T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(137, 1, NULL, 'DH2611-00067', NULL, 31, NULL, '2026-11-18T09:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 'draft', 'pending', 'none', 'unpaid', 957000.00, 0.00, 0.00, 30000.00, 987000.00, 0.00, NULL, NULL, NULL, NULL, NULL, NULL, '2026-11-18T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(138, 1, NULL, 'DH2611-00068', NULL, 30, NULL, '2026-11-18T10:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 199000.00, 0.00, 0.00, 30000.00, 229000.00, 0.00, NULL, NULL, '2026-11-18T10:10:00.0000000', 1, NULL, NULL, '2026-11-18T10:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(139, 1, NULL, 'DH2611-00069', NULL, 29, NULL, '2026-11-18T12:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 199000.00, 0.00, 0.00, 0.00, 199000.00, 199000.00, NULL, NULL, '2026-11-18T12:10:00.0000000', 1, NULL, NULL, '2026-11-18T12:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(140, 1, NULL, 'DH2611-00070', NULL, 29, NULL, '2026-11-18T13:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 1040000.00, 0.00, 0.00, 0.00, 1040000.00, 0.00, NULL, NULL, NULL, NULL, '2026-11-18T15:00:00.0000000', N'Khách đổi ý, không mua nữa', '2026-11-18T13:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(141, 1, NULL, 'DH2611-00071', NULL, 30, NULL, '2026-11-19T02:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 1149000.00, 0.00, 0.00, 30000.00, 1179000.00, 0.00, NULL, NULL, '2026-11-19T02:10:00.0000000', 1, NULL, NULL, '2026-11-19T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(142, 1, NULL, 'DH2611-00072', NULL, 41, NULL, '2026-11-19T03:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 690000.00, 0.00, 0.00, 30000.00, 720000.00, 0.00, NULL, NULL, NULL, NULL, '2026-11-19T05:00:00.0000000', N'Khách đổi ý, không mua nữa', '2026-11-19T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(143, 1, NULL, 'DH2611-00073', NULL, 40, NULL, '2026-11-19T04:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 1769000.00, 0.00, 0.00, 30000.00, 1799000.00, 0.00, NULL, NULL, '2026-11-19T04:10:00.0000000', 1, NULL, NULL, '2026-11-19T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(144, 1, NULL, 'DH2611-00074', NULL, 31, NULL, '2026-11-19T05:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 859200.00, 0.00, 0.00, 30000.00, 889200.00, 0.00, NULL, NULL, '2026-11-19T05:10:00.0000000', 1, NULL, NULL, '2026-11-19T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(145, 1, NULL, 'DH2611-00075', NULL, 29, NULL, '2026-11-19T06:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'draft', 'pending', 'none', 'unpaid', 990000.00, 0.00, 0.00, 0.00, 990000.00, 0.00, NULL, NULL, NULL, NULL, NULL, NULL, '2026-11-19T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(146, 1, NULL, 'DH2611-00076', NULL, 29, NULL, '2026-11-19T08:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'confirmed', 'pending', 'none', 'paid', 539100.00, 0.00, 0.00, 0.00, 539100.00, 539100.00, NULL, NULL, '2026-11-19T08:10:00.0000000', 1, NULL, NULL, '2026-11-19T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(147, 1, NULL, 'DH2611-00077', NULL, 31, NULL, '2026-11-19T09:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 1006000.00, 0.00, 0.00, 30000.00, 1036000.00, 0.00, NULL, NULL, '2026-11-19T09:10:00.0000000', 1, NULL, NULL, '2026-11-19T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(148, 1, NULL, 'DH2611-00078', NULL, 41, NULL, '2026-11-19T11:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'draft', 'pending', 'none', 'unpaid', 758000.00, 0.00, 0.00, 0.00, 758000.00, 0.00, NULL, NULL, NULL, NULL, NULL, NULL, '2026-11-19T11:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(149, 1, NULL, 'DH2611-00079', NULL, 30, NULL, '2026-11-20T02:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'confirmed', 'pending', 'none', 'paid', 897000.00, 0.00, 0.00, 0.00, 897000.00, 897000.00, NULL, NULL, '2026-11-20T02:10:00.0000000', 1, NULL, NULL, '2026-11-20T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(150, 1, NULL, 'DH2611-00080', NULL, 41, NULL, '2026-11-20T03:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 299000.00, 0.00, 0.00, 30000.00, 329000.00, 0.00, NULL, NULL, '2026-11-20T03:10:00.0000000', 1, NULL, NULL, '2026-11-20T03:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(151, 1, NULL, 'DH2611-00081', NULL, 40, NULL, '2026-11-20T04:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 727000.00, 0.00, 0.00, 30000.00, 757000.00, 0.00, NULL, NULL, '2026-11-20T04:10:00.0000000', 1, NULL, NULL, '2026-11-20T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(152, 1, NULL, 'DH2611-00082', NULL, 40, NULL, '2026-11-20T04:00:00.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 238000.00, 0.00, 0.00, 30000.00, 268000.00, 0.00, NULL, NULL, '2026-11-20T04:10:00.0000000', 1, NULL, NULL, '2026-11-20T04:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(153, 1, NULL, 'DH2611-00083', NULL, 31, NULL, '2026-11-20T05:00:00.0000000', NULL, 'zalo', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Trần Thu Trang', '0913002002', N'Q.3, TP.HCM', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 1380000.00, 0.00, 0.00, 30000.00, 1410000.00, 0.00, NULL, NULL, '2026-11-20T05:10:00.0000000', 1, NULL, NULL, '2026-11-20T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(154, 1, NULL, 'DH2611-00084', NULL, 39, NULL, '2026-11-20T05:00:00.0000000', NULL, 'zalo', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 990000.00, 0.00, 0.00, 30000.00, 1020000.00, 0.00, NULL, NULL, '2026-11-20T05:10:00.0000000', 1, NULL, NULL, '2026-11-20T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(155, 1, NULL, 'DH2611-00085', NULL, 39, NULL, '2026-11-20T05:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 658000.00, 0.00, 0.00, 30000.00, 688000.00, 0.00, NULL, NULL, '2026-11-20T05:10:00.0000000', 1, NULL, NULL, '2026-11-20T05:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(156, 1, NULL, 'DH2611-00086', NULL, 30, NULL, '2026-11-20T06:00:00.0000000', NULL, 'facebook', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 329000.00, 0.00, 0.00, 30000.00, 359000.00, 0.00, NULL, NULL, '2026-11-20T06:10:00.0000000', 1, NULL, NULL, '2026-11-20T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(157, 1, NULL, 'DH2611-00087', NULL, 29, NULL, '2026-11-20T06:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'draft', 'pending', 'none', 'unpaid', 1125200.00, 0.00, 0.00, 0.00, 1125200.00, 0.00, NULL, NULL, NULL, NULL, NULL, NULL, '2026-11-20T06:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(158, 1, NULL, 'DH2611-00088', NULL, 41, NULL, '2026-11-20T07:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'draft', 'pending', 'none', 'unpaid', 758000.00, 0.00, 0.00, 0.00, 758000.00, 0.00, NULL, NULL, NULL, NULL, NULL, NULL, '2026-11-20T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(159, 1, NULL, 'DH2611-00089', NULL, 29, NULL, '2026-11-20T07:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'confirmed', 'pending', 'none', 'paid', 518000.00, 0.00, 0.00, 0.00, 518000.00, 518000.00, NULL, NULL, '2026-11-20T07:10:00.0000000', 1, NULL, NULL, '2026-11-20T07:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(160, 1, NULL, 'DH2611-00090', NULL, 29, NULL, '2026-11-20T08:00:00.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'confirmed', 'pending', 'none', 'paid', 399000.00, 0.00, 0.00, 0.00, 399000.00, 399000.00, NULL, NULL, '2026-11-20T08:10:00.0000000', 1, NULL, NULL, '2026-11-20T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(161, 1, NULL, 'DH2611-00091', NULL, 40, NULL, '2026-11-20T08:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Dương Tuấn Kiệt', '0983011011', N'TP. Vinh, Nghệ An', NULL, NULL, 'draft', 'pending', 'none', 'unpaid', 399000.00, 0.00, 0.00, 30000.00, 429000.00, 0.00, NULL, NULL, NULL, NULL, NULL, NULL, '2026-11-20T08:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(162, 1, NULL, 'DH2611-00092', NULL, 39, NULL, '2026-11-20T09:00:00.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 1867200.00, 0.00, 0.00, 30000.00, 1897200.00, 0.00, NULL, NULL, '2026-11-20T09:10:00.0000000', 1, NULL, NULL, '2026-11-20T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(163, 1, NULL, 'DH2611-00093', NULL, 39, NULL, '2026-11-20T09:00:00.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Ngô Phương Thảo', '0982010010', N'Thủ Đức, TP.HCM', NULL, NULL, 'draft', 'pending', 'none', 'unpaid', 2100000.00, 0.00, 0.00, 30000.00, 2130000.00, 0.00, NULL, NULL, NULL, NULL, NULL, NULL, '2026-11-20T09:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(164, 1, NULL, 'DH2611-00094', NULL, 30, NULL, '2026-11-20T08:37:33.0000000', NULL, 'shopee', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 819000.00, 0.00, 0.00, 30000.00, 849000.00, 0.00, NULL, NULL, '2026-11-20T08:47:33.0000000', 1, NULL, NULL, '2026-11-20T08:37:33.0000000', 1, NULL, NULL, 0, 0.00),
(165, 1, NULL, 'DH2611-00095', NULL, 30, NULL, '2026-11-20T08:00:33.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Nguyễn Minh Anh', '0912001001', N'Đống Đa, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 389000.00, 0.00, 0.00, 30000.00, 419000.00, 419000.00, NULL, NULL, '2026-11-20T08:10:33.0000000', 1, NULL, NULL, '2026-11-20T08:00:33.0000000', 1, NULL, NULL, 0, 0.00),
(166, 1, NULL, 'DH2611-00096', NULL, 38, NULL, '2026-11-20T07:23:33.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Đặng Quang Huy', '0981009009', N'Thanh Xuân, Hà Nội', NULL, NULL, 'completed', 'delivered', 'none', 'paid', 690000.00, 0.00, 0.00, 30000.00, 720000.00, 720000.00, NULL, NULL, '2026-11-20T07:33:33.0000000', 1, NULL, NULL, '2026-11-20T07:23:33.0000000', 1, NULL, NULL, 0, 0.00),
(167, 1, NULL, 'DH2611-00097', NULL, 41, NULL, '2026-11-20T06:46:33.0000000', NULL, 'tiktok', NULL, 'VND', 1.000000, NULL, NULL, 'ewallet', 1, 1, NULL, NULL, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 249000.00, 0.00, 0.00, 30000.00, 279000.00, 0.00, NULL, NULL, NULL, NULL, '2026-11-20T06:58:33.0000000', N'Khách đổi ý, không mua nữa', '2026-11-20T06:46:33.0000000', 1, NULL, NULL, 0, 0.00),
(168, 1, NULL, 'DH2611-00098', NULL, 41, NULL, '2026-11-20T06:09:33.0000000', NULL, 'website', NULL, 'VND', 1.000000, NULL, NULL, 'cod', 1, 1, NULL, NULL, N'Lý Bảo Ngọc', '0984012012', N'Biên Hòa, Đồng Nai', NULL, NULL, 'confirmed', 'shipping', 'none', 'unpaid', 887000.00, 0.00, 0.00, 30000.00, 917000.00, 0.00, NULL, NULL, '2026-11-20T06:19:33.0000000', 1, NULL, NULL, '2026-11-20T06:09:33.0000000', 1, NULL, NULL, 0, 0.00),
(169, 1, NULL, 'DH2611-00099', NULL, 29, NULL, '2026-11-20T09:32:33.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'cash', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'completed', 'delivered', 'none', 'paid', 468000.00, 0.00, 0.00, 0.00, 468000.00, 468000.00, NULL, NULL, '2026-11-20T09:42:33.0000000', 1, NULL, NULL, '2026-11-20T09:32:33.0000000', 1, NULL, NULL, 0, 0.00),
(170, 1, NULL, 'DH2611-00100', NULL, 29, NULL, '2026-11-20T08:55:33.0000000', NULL, 'direct', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'cancelled', 'pending', 'none', 'unpaid', 1380000.00, 0.00, 0.00, 0.00, 1380000.00, 0.00, NULL, NULL, NULL, NULL, '2026-11-20T09:07:33.0000000', N'Khách đổi ý, không mua nữa', '2026-11-20T08:55:33.0000000', 1, NULL, NULL, 0, 0.00),
(171, 1, NULL, 'DH2610-00061', 1, 17, NULL, '2026-10-13T02:00:00.0000000', NULL, 'other', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, N'Công ty Cổ phần Hưng Thịnh', '02438251111', N'25 Lý Thường Kiệt, Hà Nội', NULL, NULL, 'draft', 'pending', 'none', 'unpaid', 14815500.00, 0.00, 0.00, 0.00, 14815500.00, 0.00, N'Tạo từ báo giá BG2610-00001', NULL, NULL, NULL, NULL, NULL, '2026-10-13T02:00:00.0000000', 1, NULL, NULL, 0, 0.00),
(172, 1, NULL, 'DH2611-00101', 6, 24, NULL, '2026-11-18T02:00:00.0000000', NULL, 'other', NULL, 'VND', 1.000000, NULL, NULL, 'bank_transfer', 1, 1, NULL, NULL, N'Nhà hàng Hương Quê', '02439998888', N'12 Trần Duy Hưng, Hà Nội', NULL, NULL, 'draft', 'pending', 'none', 'unpaid', 11484000.00, 0.00, 0.00, 0.00, 11484000.00, 0.00, N'Tạo từ báo giá BG2611-00003', NULL, NULL, NULL, NULL, NULL, '2026-11-18T02:00:00.0000000', 1, NULL, NULL, 0, 0.00)
;
SET IDENTITY_INSERT [sales].[SalesOrders] OFF;
GO

-- sales.SalesReturnLines (3 dòng)
SET IDENTITY_INSERT [sales].[SalesReturnLines] ON;
INSERT INTO [sales].[SalesReturnLines] ([Id], [SalesReturnId], [SalesOrderLineId], [ProductId], [LotId], [Quantity], [UnitPrice], [TaxRate], [LineTotal], [Condition]) VALUES
(1, 1, 223, 5, NULL, 1.0000, 359000.0000, 0.0000, 359000.00, 'good'),
(2, 2, 222, 46, NULL, 1.0000, 690000.0000, 0.0000, 690000.00, 'damaged'),
(3, 3, 205, 91, NULL, 1.0000, 299000.0000, 0.0000, 299000.00, 'good')
;
SET IDENTITY_INSERT [sales].[SalesReturnLines] OFF;
GO

-- sales.SalesReturns (3 dòng)
SET IDENTITY_INSERT [sales].[SalesReturns] ON;
INSERT INTO [sales].[SalesReturns] ([Id], [CompanyId], [DocNo], [SalesOrderId], [PartnerId], [WarehouseId], [ReturnDate], [Reason], [RefundMethod], [Status], [SubTotal], [TaxAmount], [TotalAmount], [StockDocumentId], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'TH2611-00001', 131, 29, 1, '2026-11-18T08:00:00.0000000', N'Không vừa size, khách lấy tiền lại', 'cash', 'refunded', 359000.00, 0.00, 359000.00, 158, '2026-11-18T08:00:00.0000000', 1, NULL, NULL, 0),
(2, 1, 'TH2611-00002', 130, 29, 1, '2026-11-18T07:00:00.0000000', N'Lỗi đường may ở tay áo', 'cash', 'refunded', 690000.00, 0.00, 690000.00, NULL, '2026-11-18T07:00:00.0000000', 1, NULL, NULL, 0),
(3, 1, 'TH2611-00003', 121, 29, 1, '2026-11-16T12:00:00.0000000', N'Khách đổi ý', 'cash', 'refunded', 299000.00, 0.00, 299000.00, 159, '2026-11-16T12:00:00.0000000', 1, NULL, NULL, 0)
;
SET IDENTITY_INSERT [sales].[SalesReturns] OFF;
GO

-- web.ContactSubmissions (8 dòng)
SET IDENTITY_INSERT [web].[ContactSubmissions] ON;
INSERT INTO [web].[ContactSubmissions] ([Id], [SiteId], [FormCode], [FullName], [Phone], [Email], [Message], [PageUrl], [UtmSource], [UtmMedium], [UtmCampaign], [IpAddress], [ConsentGiven], [LeadId], [CreatedAt]) VALUES
(1, 1, 'contact', N'Lý Thanh Tâm', '0763222111', NULL, N'Mình muốn đặt 30 áo polo in logo cho công ty, báo giá giúp mình.', '/lien-he', 'facebook', 'cpc', 'blackfriday', '113.161.10.20', 1, 12, '2026-11-09T03:09:29.2720000'),
(2, 1, 'contact', N'Tạ Minh Nhật', '0981555444', 'nhat.ta@nhatminh.com.vn', N'Cần đồng phục cho 50 nhân viên văn phòng.', '/lien-he', 'google', 'cpc', NULL, '27.72.101.5', 1, 15, '2026-11-12T03:09:29.2720000'),
(3, 1, 'contact', N'Nguyễn Thu Hà', '0912678345', 'thuha.ng@gmail.com', N'Váy đầm hoa nhí size M còn màu xanh không shop?', '/products/vay-dam-hoa-nhi-vdm10', 'tiktok', 'social', NULL, '171.244.5.9', 1, NULL, '2026-11-17T03:09:29.2720000'),
(4, 1, 'contact', N'Trần Quốc Bảo', '0938456123', NULL, N'Giày tây da bò có size 44 không? Mình ở Q7, đợi chi nhánh mới mở.', '/products', NULL, NULL, NULL, '14.161.22.8', 1, NULL, '2026-11-18T03:09:29.2720000'),
(5, 1, 'contact', N'Phạm Ngọc Ánh', NULL, 'anh.pham.ngoc@yahoo.com', N'Mình muốn hợp tác làm CTV bán hàng online.', '/lien-he', 'facebook', 'social', NULL, '42.116.7.77', 1, NULL, '2026-11-19T03:09:29.2720000'),
(6, 1, 'contact', N'Đỗ Hải Yến', '0909887766', NULL, N'Đơn hàng của mình giao chậm, nhờ shop kiểm tra giúp.', '/lien-he', NULL, NULL, NULL, '113.23.45.67', 1, NULL, '2026-11-20T07:09:29.2720000'),
(7, 1, 'contact', N'Võ Minh Khang', '0977112233', 'khang.vm@outlook.com', N'Có ship COD ra Đà Nẵng không ạ?', '/pages/chinh-sach-giao-hang', 'google', 'organic', NULL, '1.53.88.21', 1, NULL, '2026-11-20T21:09:29.2720000'),
(8, 1, 'contact', N'Lâm Gia Hân', '0868999000', NULL, N'Mã BLACKFRIDAY dùng cho đơn online được không shop?', '/blog/black-friday-giam-den-50', 'facebook', 'cpc', 'blackfriday', '116.110.4.3', 1, NULL, '2026-11-21T01:09:29.2720000')
;
SET IDENTITY_INSERT [web].[ContactSubmissions] OFF;
GO

-- web.MenuItems (14 dòng)
SET IDENTITY_INSERT [web].[MenuItems] ON;
INSERT INTO [web].[MenuItems] ([Id], [MenuId], [ParentId], [Label], [Url], [SortOrder], [OpenNewTab]) VALUES
(7, 2, NULL, N'Giới thiệu', '/pages/gioi-thieu', 10, 0),
(8, 2, NULL, N'Chính sách đổi trả', '/pages/chinh-sach-doi-tra', 20, 0),
(9, 2, NULL, N'Hướng dẫn chọn size', '/pages/huong-dan-chon-size', 30, 0),
(10, 2, NULL, N'Chính sách giao hàng', '/pages/chinh-sach-giao-hang', 40, 0),
(11, 1, NULL, N'Trang chủ', '/', 10, 0),
(12, 1, NULL, N'Sản phẩm', '/san-pham', 20, 0),
(13, 1, NULL, N'Áo thun', '/san-pham?category=ao-thun', 30, 0),
(14, 1, NULL, N'Giày sneaker', '/san-pham?category=giay-sneaker', 40, 0),
(15, 1, NULL, N'Blog', '/blog', 50, 0),
(16, 1, NULL, N'Liên hệ', '/lien-he', 60, 0),
(17, 3, NULL, N'Trang chủ', '/', 10, 0),
(18, 3, NULL, N'Tất cả giày', '/san-pham', 20, 0),
(19, 3, NULL, N'Liên hệ', '/lien-he', 30, 0),
(20, 4, NULL, N'Chính sách đổi trả', '/pages/chinh-sach-doi-tra', 10, 0)
;
SET IDENTITY_INSERT [web].[MenuItems] OFF;
GO

-- web.Menus (4 dòng)
SET IDENTITY_INSERT [web].[Menus] ON;
INSERT INTO [web].[Menus] ([Id], [SiteId], [Code]) VALUES
(2, 1, 'footer'),
(1, 1, 'header'),
(4, 2, 'footer'),
(3, 2, 'header')
;
SET IDENTITY_INSERT [web].[Menus] OFF;
GO

-- web.Pages (5 dòng)
SET IDENTITY_INSERT [web].[Pages] ON;
INSERT INTO [web].[Pages] ([Id], [SiteId], [Slug], [Title], [Content], [MetaTitle], [MetaDescription], [IsPublished], [PublishedAt], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 'gioi-thieu', N'Giới thiệu MyStyle', N'MyStyle là thương hiệu thời trang Việt dành cho người trẻ đi làm và đi chơi. Chúng tôi chọn chất liệu thoáng mát, phom dáng dễ mặc, giá hợp lý.

Cửa hàng: 123 Lê Lợi, Quận 1 - mở cửa 8:30 đến 22:00 hằng ngày. Sắp khai trương chi nhánh Quận 7.', NULL, N'MyStyle - thời trang nam nữ, giày dép, phụ kiện. Mặc đẹp mỗi ngày.', 1, '2026-10-27T03:09:29.2720000', '2026-10-22T03:09:29.2720000', 1, NULL, NULL, 0),
(2, 1, 'chinh-sach-doi-tra', N'Chính sách đổi trả', N'- Đổi size, đổi mẫu trong 7 ngày kể từ ngày nhận hàng, sản phẩm còn tem mác, chưa giặt.
- Hoàn tiền 100% nếu sản phẩm lỗi do nhà sản xuất.
- Sản phẩm giảm giá trên 50% không áp dụng đổi trả.
- Mang hóa đơn hoặc báo số điện thoại khi mua để tra đơn.', NULL, N'Đổi trả trong 7 ngày, hoàn tiền nếu lỗi sản xuất.', 1, '2026-10-27T03:09:29.2720000', '2026-10-22T03:09:29.2720000', 1, NULL, NULL, 0),
(3, 1, 'huong-dan-chon-size', N'Hướng dẫn chọn size', N'Áo: S (45-52kg), M (52-60kg), L (60-68kg), XL (68-76kg), XXL (76-85kg).
Quần jeans: chọn theo số đo vòng eo, size 28 tương đương eo 71cm, mỗi size tăng 2,5cm.
Giày: đo chiều dài bàn chân, cộng thêm 1cm rồi đối chiếu bảng size 36-44.', NULL, N'Bảng size áo, quần, giày MyStyle.', 1, '2026-10-27T03:09:29.2720000', '2026-10-22T03:09:29.2720000', 1, NULL, NULL, 0),
(4, 1, 'chinh-sach-giao-hang', N'Chính sách giao hàng', N'Giao toàn quốc qua GHN, GHTK, Viettel Post. Nội thành TP.HCM 1-2 ngày, tỉnh khác 2-4 ngày.
Miễn phí giao hàng cho đơn từ 300.000đ (mã FREESHIP300). Được kiểm tra hàng trước khi nhận.', NULL, N'Giao toàn quốc, miễn phí ship đơn từ 300k.', 0, NULL, '2026-11-16T03:09:29.2720000', 1, NULL, NULL, 0),
(5, 2, 'chinh-sach-doi-tra', N'Chính sách đổi trả giày', N'Đổi size miễn phí trong 7 ngày nếu giày chưa qua sử dụng, còn hộp và tem. Lỗi keo, lỗi đế: bảo hành 3 tháng.', NULL, NULL, 1, '2026-11-21T06:45:32.2340000', '2026-11-21T06:45:32.2340000', NULL, NULL, NULL, 0)
;
SET IDENTITY_INSERT [web].[Pages] OFF;
GO

-- web.PostCategories (3 dòng)
SET IDENTITY_INSERT [web].[PostCategories] ON;
INSERT INTO [web].[PostCategories] ([Id], [SiteId], [ParentId], [Slug], [Name]) VALUES
(1, 1, NULL, 'phoi-do', N'Phối đồ'),
(2, 1, NULL, 'xu-huong', N'Xu hướng'),
(3, 1, NULL, 'tin-cua-hang', N'Tin cửa hàng')
;
SET IDENTITY_INSERT [web].[PostCategories] OFF;
GO

-- web.Posts (6 dòng)
SET IDENTITY_INSERT [web].[Posts] ON;
INSERT INTO [web].[Posts] ([Id], [SiteId], [CategoryId], [Slug], [Title], [Summary], [Content], [ThumbnailUrl], [AuthorUserId], [MetaTitle], [MetaDescription], [IsPublished], [PublishedAt], [ViewCount], [CreatedAt], [CreatedBy], [UpdatedAt], [UpdatedBy], [IsDeleted]) VALUES
(1, 1, 1, '5-cach-phoi-ao-thun-basic-di-lam', N'5 cách phối áo thun basic đi làm vẫn lịch sự', N'Áo thun basic không chỉ để mặc ở nhà. Phối cùng blazer, quần kaki hay chân váy chữ A là đủ chỉn chu đi làm.', N'1. Áo thun trắng + blazer + quần kaki.
2. Áo thun đen + chân váy chữ A + giày cao gót.
3. Áo thun + sơ mi khoác ngoài.
4. Áo thun sơ vin + quần jeans slim fit + giày tây.
5. Áo thun + áo khoác bomber cho ngày se lạnh.', NULL, 7, NULL, NULL, 1, '2026-10-31T03:09:29.2720000', 1840, '2026-10-30T03:09:29.2720000', 7, NULL, NULL, 0),
(2, 1, 2, 'xu-huong-mau-sac-tet-2027', N'Xu hướng màu sắc Tết 2027: đỏ đô, kem và xanh rêu', N'Ba gam màu được dự báo lên ngôi mùa Tết năm nay và cách chọn đồ hợp tông da.', N'Đỏ đô sang trọng hơn đỏ tươi, dễ phối với kem và đen. Xanh rêu hợp với người da ngăm. Kem là màu nền an toàn cho mọi outfit.', NULL, 7, NULL, NULL, 1, '2026-11-12T03:09:29.2720000', 960, '2026-11-11T03:09:29.2720000', 7, NULL, NULL, 0),
(3, 1, 1, 'chon-giay-sneaker-trang', N'Chọn giày sneaker trắng sao cho bền đẹp', N'Mẹo chọn size, chất liệu và vệ sinh giày sneaker trắng luôn như mới.', N'Chọn da tổng hợp phủ PU dễ lau chùi. Vệ sinh bằng khăn ẩm sau mỗi lần đi, tránh phơi nắng gắt. Dùng giấy báo nhét giày để giữ form.', NULL, 5, NULL, NULL, 1, '2026-11-06T03:09:29.2720000', 1210, '2026-11-05T03:09:29.2720000', 5, NULL, NULL, 0),
(4, 1, 3, 'black-friday-giam-den-50', N'Black Friday: giảm đến 50% toàn bộ cửa hàng', N'Nhập mã BLACKFRIDAY giảm thêm khi mua online, áp dụng cả tại cửa hàng Lê Lợi.', N'Thời gian: từ thứ 6 đến hết chủ nhật. Áp dụng cho đơn từ 500.000đ. Mỗi khách dùng mã 1 lần.', NULL, 7, NULL, NULL, 1, '2026-11-17T03:09:29.2720000', 2350, '2026-11-16T03:09:29.2720000', 7, NULL, NULL, 0),
(5, 1, 3, 'sap-khai-truong-chi-nhanh-quan-7', N'Sắp khai trương chi nhánh Quận 7', N'MyStyle mở thêm cửa hàng tại 45 Nguyễn Thị Thập, Quận 7. Nhiều quà tặng dịp khai trương.', N'Ngày khai trương dự kiến giữa tháng 12. 100 khách đầu tiên nhận túi tote MyStyle. Theo dõi fanpage để cập nhật.', NULL, 2, NULL, NULL, 1, '2026-11-19T03:09:29.2720000', 430, '2026-11-18T03:09:29.2720000', 2, NULL, NULL, 0),
(6, 1, 1, 'lookbook-tet-2027', N'Lookbook Tết 2027 (bản nháp)', N'40 outfit cho Tết - đang chụp, sẽ đăng sau khi retouch xong.', NULL, NULL, 5, NULL, NULL, 0, NULL, 0, '2026-11-20T03:09:29.2720000', 5, NULL, NULL, 0)
;
SET IDENTITY_INSERT [web].[Posts] OFF;
GO

-- web.SiteProducts (19 dòng)
INSERT INTO [web].[SiteProducts] ([SiteId], [ModelId], [PriceOverride], [IsFeatured], [SortOrder], [AddedAt]) VALUES
(1, 1, NULL, 1, 1, '2026-11-21T06:31:24.0200000'),
(1, 2, NULL, 0, 0, '2026-11-21T06:31:24.0200000'),
(1, 3, NULL, 0, 0, '2026-11-21T06:31:24.0200000'),
(1, 4, NULL, 0, 0, '2026-11-21T06:31:24.0200000'),
(1, 5, NULL, 0, 0, '2026-11-21T06:31:24.0200000'),
(1, 6, NULL, 0, 0, '2026-11-21T06:31:24.0200000'),
(1, 7, NULL, 0, 0, '2026-11-21T06:31:24.0200000'),
(1, 10, NULL, 1, 3, '2026-11-21T06:31:24.0200000'),
(1, 11, NULL, 0, 0, '2026-11-21T06:31:24.0200000'),
(1, 12, NULL, 1, 4, '2026-11-21T06:31:24.0200000'),
(1, 13, NULL, 0, 0, '2026-11-21T06:31:24.0200000'),
(1, 14, NULL, 1, 2, '2026-11-21T06:31:24.0200000'),
(1, 15, NULL, 0, 0, '2026-11-21T06:31:24.0200000'),
(1, 17, NULL, 0, 0, '2026-11-21T06:31:24.0200000'),
(1, 18, NULL, 0, 0, '2026-11-21T06:31:24.0200000'),
(2, 14, 549000.00, 1, 0, '2026-11-21T06:45:32.2340000'),
(2, 15, NULL, 1, 0, '2026-11-21T06:45:32.2340000'),
(2, 16, NULL, 0, 0, '2026-11-21T06:45:32.2340000'),
(2, 17, NULL, 0, 0, '2026-11-21T06:45:32.2340000')
;
GO

-- web.Sites (2 dòng)
SET IDENTITY_INSERT [web].[Sites] ON;
INSERT INTO [web].[Sites] ([Id], [CompanyId], [Name], [Domain], [DefaultLanguage], [LogoUrl], [FaviconUrl], [PriceListId], [WarehouseId], [Settings], [IsActive], [ApiKeyHash], [ApiKeyPrefix], [ApiKeyCreatedAt], [RevalidateUrl], [RevalidateSecret], [LastSyncAt], [LastSyncStatus], [BotUserId]) VALUES
(1, 1, N'MyStyle Fashion', 'mystyle.vn', 'vi', NULL, NULL, NULL, 1, N'{"slogan":"Mặc đẹp mỗi ngày","hotline":"0909 123 456","email":"cskh@mystyle.vn","address":"123 Lê Lợi, Phường Bến Thành, Quận 1, TP.HCM","openingHours":"8:30 - 22:00 hằng ngày","facebook":"https://facebook.com/mystyle.vn","instagram":"https://instagram.com/mystyle.vn","tiktok":"https://tiktok.com/@mystyle.vn","zalo":"0909123456","primaryColor":"#D4537E","shippingFee":30000,"freeShippingFrom":500000}', 1, 'a1f92ca46fb5101f06c2043f288727b96484ceaa9d9cd7d594c1d711ee8c9bd0', 'mys_u832sH', '2026-11-21T07:06:58.4230000', 'http://localhost:3000/api/revalidate', 'yjDPnUiPCgWaiSYCpKEWTb8y7TkbUCZd', NULL, NULL, 10),
(2, 1, N'MyStyle Sneaker', 'sneaker.mystyle.vn', 'vi', NULL, NULL, NULL, 1, N'{"slogan":"Giày đẹp cho mọi bước chân","hotline":"0909 123 456","email":"sneaker@mystyle.vn","address":"123 Lê Lợi, Quận 1, TP.HCM","openingHours":"9:00 - 22:00","primaryColor":"#185FA5","shippingFee":25000,"freeShippingFrom":800000}', 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 10)
;
SET IDENTITY_INSERT [web].[Sites] OFF;
GO

EXEC sp_MSforeachtable N'ALTER TABLE ? WITH CHECK CHECK CONSTRAINT ALL; ALTER TABLE ? ENABLE TRIGGER ALL;';
GO
PRINT N'Xong: database MyERP đã sẵn sàng.';
GO
