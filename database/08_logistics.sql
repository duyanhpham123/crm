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
