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
    CONSTRAINT PK_Sites PRIMARY KEY (Id),
    CONSTRAINT FK_Sites_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Sites_PriceLists FOREIGN KEY (PriceListId) REFERENCES md.PriceLists(Id),
    CONSTRAINT FK_Sites_Warehouses FOREIGN KEY (WarehouseId) REFERENCES inv.Warehouses(Id),
    CONSTRAINT UQ_Sites_Domain UNIQUE (Domain)
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
