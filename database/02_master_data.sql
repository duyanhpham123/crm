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

CREATE TABLE md.Products (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT         NOT NULL,
    Code            VARCHAR(50)    NOT NULL,            -- SKU
    Barcode         VARCHAR(50)    NULL,
    Name            NVARCHAR(255)  NOT NULL,
    ProductType     VARCHAR(12)    NOT NULL DEFAULT 'goods',
    CategoryId      BIGINT         NULL,
    BrandId         BIGINT         NULL,
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
