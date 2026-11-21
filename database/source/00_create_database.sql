/* =====================================================================
   MyERP - 00. Tạo database
   Tên database lấy từ biến sqlcmd $(DatabaseName) - run_all.ps1 tự truyền vào.
   Chạy tay:  sqlcmd -S localhost -E -v DatabaseName=MyERP -i 00_create_database.sql

   - Collation Latin1_General_100_CI_AI: không phân biệt hoa thường và dấu
     khi so sánh/tìm kiếm ("nguyen" ra "Nguyễn", "do duc" ra "Đỗ Đức").
     Lưu ý: Vietnamese_100_CI_AI coi ê/ă/â/đ là chữ cái riêng nên gõ
     không dấu sẽ KHÔNG tìm ra - đã kiểm tra thực tế.
   - Bật READ_COMMITTED_SNAPSHOT để đọc không chặn ghi (quan trọng với ERP
     nhiều người dùng đồng thời).
   ===================================================================== */
IF DB_ID(N'$(DatabaseName)') IS NULL
BEGIN
    CREATE DATABASE [$(DatabaseName)] COLLATE Latin1_General_100_CI_AI;
    -- Chỉ đặt cấu hình khi vừa tạo mới: tránh ngắt kết nối của DB đang chạy
    ALTER DATABASE [$(DatabaseName)] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
    ALTER DATABASE [$(DatabaseName)] SET ALLOW_SNAPSHOT_ISOLATION ON;
    ALTER DATABASE [$(DatabaseName)] SET RECOVERY FULL;
END
GO
