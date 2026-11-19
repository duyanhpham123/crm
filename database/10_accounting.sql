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
