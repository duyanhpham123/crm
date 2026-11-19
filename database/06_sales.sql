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
    CONSTRAINT CK_SalesOrders_Delivery CHECK (DeliveryStatus IN ('pending','partial','delivered','returned')),
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
