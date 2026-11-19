/* =====================================================================
   MyERP - 00. Tạo database
   - Collation Latin1_General_100_CI_AI: không phân biệt hoa thường và dấu
     khi so sánh/tìm kiếm ("nguyen" ra "Nguyễn", "do duc" ra "Đỗ Đức").
     Lưu ý: Vietnamese_100_CI_AI coi ê/ă/â/đ là chữ cái riêng nên gõ
     không dấu sẽ KHÔNG tìm ra - đã kiểm tra thực tế.
   - Bật READ_COMMITTED_SNAPSHOT để đọc không chặn ghi (quan trọng với ERP
     nhiều người dùng đồng thời).
   ===================================================================== */
IF DB_ID(N'MyERP') IS NULL
BEGIN
    CREATE DATABASE MyERP COLLATE Latin1_General_100_CI_AI;
END
GO

ALTER DATABASE MyERP SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE MyERP SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE MyERP SET RECOVERY FULL;
GO
