/* =====================================================================
   Nâng cấp database ĐÃ TẠO trước ngày 21/11/2026 (DB mới tạo bằng run_all.ps1 không cần chạy).
   Thêm mẫu sản phẩm + biến thể màu/size (dùng cho shop thời trang) và đơn vị "Đôi".
   Chạy:  sqlcmd -S localhost -E -d MyERP -I -f 65001 -i migrations\2026-11-21_product_variants.sql
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('md.ProductModels') IS NULL
BEGIN
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
        Gender       VARCHAR(10)    NULL,
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
END
GO

IF COL_LENGTH('md.Products', 'ModelId') IS NULL
BEGIN
    ALTER TABLE md.Products ADD
        ModelId BIGINT NULL CONSTRAINT FK_Products_Models REFERENCES md.ProductModels(Id),
        Color   NVARCHAR(50) NULL,
        Size    VARCHAR(20)  NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Products_Model')
    CREATE INDEX IX_Products_Model ON md.Products(ModelId) WHERE ModelId IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Products_Model_Variant')
    CREATE UNIQUE INDEX UX_Products_Model_Variant ON md.Products(ModelId, Color, Size) WHERE ModelId IS NOT NULL AND IsDeleted = 0;
IF NOT EXISTS (SELECT 1 FROM md.UnitsOfMeasure WHERE CompanyId IS NULL AND Code = 'DOI')
    INSERT md.UnitsOfMeasure (CompanyId, Code, Name) VALUES (NULL, 'DOI', N'Đôi');
-- Dãy số mã nhà cung cấp NCC-0001
INSERT core.Sequences (CompanyId, Code, Prefix, DatePattern, Padding, ResetPolicy)
SELECT c.Id, 'SUPPLIER', 'NCC', NULL, 4, 'never' FROM core.Companies c
WHERE NOT EXISTS (SELECT 1 FROM core.Sequences s WHERE s.CompanyId = c.Id AND s.Code = 'SUPPLIER');
GO
PRINT N'Đã thêm mẫu sản phẩm và biến thể.';
