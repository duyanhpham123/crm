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
