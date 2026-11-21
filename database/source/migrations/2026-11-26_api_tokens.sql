/* =====================================================================
   Nâng cấp: khóa truy cập cá nhân (core.ApiTokens) cho trợ lý AI / phần mềm khác gọi API thay mặt người dùng.
   DB mới tạo bằng run_all.ps1 đã có sẵn. Chạy lại nhiều lần không sao.
   Chạy:  sqlcmd -S localhost -E -d MyERP -I -f 65001 -i migrations\2026-11-26_api_tokens.sql
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF OBJECT_ID('core.ApiTokens') IS NULL
BEGIN
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
EXEC('CREATE INDEX IX_ApiTokens_User ON core.ApiTokens(UserId) WHERE RevokedAt IS NULL');
END
GO
PRINT N'Đã thêm bảng khóa truy cập cá nhân.';
