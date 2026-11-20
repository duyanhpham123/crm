/* =====================================================================
   Nâng cấp database ĐÃ TẠO trước ngày 20/11/2026 (DB mới tạo bằng run_all.ps1 không cần chạy).
   Sửa 2 lỗi của core.usp_NextDocNo:
     1. Dãy số không có mẫu ngày (KH, NV, CV...) sinh mã sai "KH11/20/2026 12:00:00 AM-000001"
     2. Nhập chứng từ lùi ngày (tháng trước) làm bộ đếm reset -> trùng số
   Cách sửa: bộ đếm riêng cho từng kỳ (core.SequenceCounters), khởi tạo từ số lớn nhất đang có.

   Chạy:  sqlcmd -S localhost -E -d MyERP -I -f 65001 -i migrations\2026-11-20_sequence_counters.sql
          rồi chạy lại 01_core.sql? KHÔNG - script này đã tự cập nhật procedure.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('core.SequenceCounters') IS NULL
BEGIN
    CREATE TABLE core.SequenceCounters (
        SequenceId  BIGINT      NOT NULL,
        Period      VARCHAR(10) NOT NULL,
        NextNumber  BIGINT      NOT NULL,
        CONSTRAINT PK_SequenceCounters PRIMARY KEY (SequenceId, Period),
        CONSTRAINT FK_SequenceCounters_Sequences FOREIGN KEY (SequenceId) REFERENCES core.Sequences(Id) ON DELETE CASCADE
    );
END
GO

/* Khởi tạo bộ đếm từ các mã đã phát hành trong từng bảng chứng từ đã có dữ liệu.
   Mã có dạng <Prefix><yyMM|yyyy|rỗng>-<số>. Lấy số lớn nhất của mỗi kỳ + 1. */
DECLARE @Issued TABLE (CompanyId BIGINT, Code VARCHAR(50));
INSERT @Issued SELECT CompanyId, Code FROM crm.Leads;
INSERT @Issued SELECT CompanyId, Code FROM crm.Opportunities;
INSERT @Issued SELECT CompanyId, Code FROM md.Partners;

;WITH parsed AS (
    SELECT s.Id AS SequenceId, s.ResetPolicy, s.DatePattern,
           SUBSTRING(i.Code, LEN(s.Prefix) + 1, CHARINDEX('-', i.Code) - LEN(s.Prefix) - 1) AS DatePart,
           TRY_CAST(SUBSTRING(i.Code, CHARINDEX('-', i.Code) + 1, 20) AS BIGINT) AS Num
    FROM @Issued i
    JOIN core.Sequences s ON s.CompanyId = i.CompanyId AND i.Code LIKE s.Prefix + '%-%'
    WHERE CHARINDEX('-', i.Code) > LEN(s.Prefix)
      -- chỉ nhận mã đúng định dạng của dãy (tránh tiền tố trùng nhau như 'PC' và 'PCK')
      AND LEN(SUBSTRING(i.Code, LEN(s.Prefix) + 1, CHARINDEX('-', i.Code) - LEN(s.Prefix) - 1)) = ISNULL(LEN(s.DatePattern), 0)
)
MERGE core.SequenceCounters AS t
USING (
    SELECT SequenceId,
           CASE ResetPolicy
               WHEN 'monthly' THEN CASE WHEN DatePattern = 'yyMM' THEN '20' + DatePart ELSE DatePart END
               WHEN 'yearly'  THEN CASE WHEN DatePattern = 'yy' THEN '20' + DatePart ELSE DatePart END
               ELSE 'ALL' END AS Period,
           MAX(Num) + 1 AS NextNumber
    FROM parsed WHERE Num IS NOT NULL
    GROUP BY SequenceId, ResetPolicy, DatePattern, DatePart
) AS s ON t.SequenceId = s.SequenceId AND t.Period = s.Period
WHEN MATCHED AND t.NextNumber < s.NextNumber THEN UPDATE SET NextNumber = s.NextNumber
WHEN NOT MATCHED THEN INSERT (SequenceId, Period, NextNumber) VALUES (s.SequenceId, s.Period, s.NextNumber);
GO

/* Bỏ 2 cột cũ không còn dùng (kèm ràng buộc DEFAULT tự đặt tên) */
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'ALTER TABLE core.Sequences DROP CONSTRAINT ' + QUOTENAME(dc.name) + N';'
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('core.Sequences') AND c.name IN ('NextNumber', 'CurrentPeriod');
EXEC sp_executesql @sql;
IF COL_LENGTH('core.Sequences', 'NextNumber') IS NOT NULL ALTER TABLE core.Sequences DROP COLUMN NextNumber;
IF COL_LENGTH('core.Sequences', 'CurrentPeriod') IS NOT NULL ALTER TABLE core.Sequences DROP COLUMN CurrentPeriod;
GO

CREATE OR ALTER PROCEDURE core.usp_NextDocNo
    @CompanyId BIGINT,
    @Code      VARCHAR(30),
    @DocDate   DATE = NULL,
    @DocNo     VARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @d DATE = ISNULL(@DocDate, CAST(SYSDATETIME() AS DATE));
    DECLARE @SeqId BIGINT, @Prefix VARCHAR(20), @Pattern VARCHAR(10), @Padding TINYINT,
            @Reset VARCHAR(10), @Period VARCHAR(10), @Num BIGINT;

    BEGIN TRAN;
        SELECT @SeqId = Id, @Prefix = Prefix, @Pattern = DatePattern, @Padding = Padding, @Reset = ResetPolicy
        FROM core.Sequences WITH (UPDLOCK, HOLDLOCK)
        WHERE CompanyId = @CompanyId AND Code = @Code;

        IF @SeqId IS NULL
        BEGIN
            ROLLBACK;
            THROW 50001, N'Chưa cấu hình dãy số chứng từ cho mã này.', 1;
        END

        SET @Period = CASE @Reset WHEN 'yearly'  THEN FORMAT(@d, 'yyyy')
                                  WHEN 'monthly' THEN FORMAT(@d, 'yyyyMM')
                                  ELSE 'ALL' END;

        UPDATE core.SequenceCounters
        SET @Num = NextNumber, NextNumber = NextNumber + 1
        WHERE SequenceId = @SeqId AND Period = @Period;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @Num = 1;
            INSERT core.SequenceCounters (SequenceId, Period, NextNumber) VALUES (@SeqId, @Period, 2);
        END
    COMMIT;

    SET @DocNo = @Prefix
               + CASE WHEN @Pattern IS NULL OR @Pattern = '' THEN '' ELSE FORMAT(@d, @Pattern) END
               + '-' + RIGHT(REPLICATE('0', @Padding) + CAST(@Num AS VARCHAR(20)), @Padding);
END
GO

PRINT N'Đã nâng cấp đánh số chứng từ.';
