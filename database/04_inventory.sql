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
