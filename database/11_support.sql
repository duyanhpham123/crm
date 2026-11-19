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
