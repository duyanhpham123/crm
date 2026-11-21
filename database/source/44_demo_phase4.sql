/* =====================================================================
   MyERP - 44. DỮ LIỆU MẪU ĐỢT 4: tài khoản nhân viên (chưa có mật khẩu), Dự án & công việc,
   Tài liệu, Chat nội bộ, Website. Chạy sau 43_demo_phase3.sql. Chạy lại không nhân đôi dữ liệu.
   Chạy:  sqlcmd -S localhost -E -d MyERP -I -f 65001 -i 44_demo_phase4.sql

   Tài khoản nhân viên tạo ở đây KHÔNG có mật khẩu nên chưa đăng nhập được: vào app Người dùng
   bấm "Đặt lại mật khẩu" cho từng người khi cần dùng thật.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @C BIGINT = (SELECT TOP 1 Id FROM core.Companies ORDER BY Id);
DECLARE @B BIGINT = (SELECT TOP 1 Id FROM core.Branches WHERE CompanyId = @C ORDER BY Id);
DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
DECLARE @Today DATE = CAST(DATEADD(HOUR, 7, @Now) AS DATE);
DECLARE @Admin BIGINT = (SELECT TOP 1 Id FROM core.Users WHERE IsSystemAdmin = 1 ORDER BY Id);

/* ---------- 1. Tài khoản cho nhân viên (liên kết hồ sơ Nhân sự) ---------- */
IF NOT EXISTS (SELECT 1 FROM core.Users WHERE NormalizedUserName = 'NHUNG')
BEGIN
    DECLARE @U TABLE (UserName VARCHAR(50), EmpCode VARCHAR(20), RoleCode VARCHAR(30));
    INSERT @U VALUES ('nhung','NV-00001','director'), ('chau','NV-00002','sales'), ('ducanh','NV-00003','sales'),
                     ('thaovy','NV-00004','sales'), ('tung','NV-00005','warehouse'), ('mai','NV-00006','marketing');

    INSERT core.Users (UserName, NormalizedUserName, Email, NormalizedEmail, FullName, PhoneNumber, DefaultCompanyId, SecurityStamp, ConcurrencyStamp)
    SELECT u.UserName, UPPER(u.UserName), u.UserName + '@mystyle.vn', UPPER(u.UserName + '@mystyle.vn'), e.FullName, LEFT(e.Phone, 20), @C,
           CONVERT(NVARCHAR(36), NEWID()), CONVERT(NVARCHAR(36), NEWID())
    FROM @U u JOIN hr.Employees e ON e.CompanyId = @C AND e.Code = u.EmpCode;

    INSERT core.UserCompanies (UserId, CompanyId, BranchId, DepartmentId, IsDefault)
    SELECT us.Id, @C, @B, e.DepartmentId, 1
    FROM @U u JOIN core.Users us ON us.NormalizedUserName = UPPER(u.UserName)
    JOIN hr.Employees e ON e.CompanyId = @C AND e.Code = u.EmpCode;

    INSERT core.UserRoles (UserId, RoleId, CompanyId)
    SELECT us.Id, r.Id, @C
    FROM @U u JOIN core.Users us ON us.NormalizedUserName = UPPER(u.UserName)
    JOIN core.Roles r ON r.CompanyId = @C AND r.Code IN (u.RoleCode, 'employee');

    UPDATE e SET UserId = us.Id
    FROM hr.Employees e JOIN @U u ON u.EmpCode = e.Code JOIN core.Users us ON us.NormalizedUserName = UPPER(u.UserName)
    WHERE e.CompanyId = @C AND e.UserId IS NULL;
    PRINT N'Đã tạo 6 tài khoản nhân viên (chưa có mật khẩu).';
END

DECLARE @Nhung BIGINT = (SELECT Id FROM core.Users WHERE NormalizedUserName = 'NHUNG');
DECLARE @Chau BIGINT = (SELECT Id FROM core.Users WHERE NormalizedUserName = 'CHAU');
DECLARE @DucAnh BIGINT = (SELECT Id FROM core.Users WHERE NormalizedUserName = 'DUCANH');
DECLARE @Vy BIGINT = (SELECT Id FROM core.Users WHERE NormalizedUserName = 'THAOVY');
DECLARE @Tung BIGINT = (SELECT Id FROM core.Users WHERE NormalizedUserName = 'TUNG');
DECLARE @Mai BIGINT = (SELECT Id FROM core.Users WHERE NormalizedUserName = 'MAI');
DECLARE @DeptCH BIGINT = (SELECT Id FROM core.Departments WHERE CompanyId = @C AND Code = 'CH');
DECLARE @DeptKT BIGINT = (SELECT Id FROM core.Departments WHERE CompanyId = @C AND Code = 'KT');
DECLARE @DeptKHO BIGINT = (SELECT Id FROM core.Departments WHERE CompanyId = @C AND Code = 'KHO');
DECLARE @DeptMKT BIGINT = (SELECT Id FROM core.Departments WHERE CompanyId = @C AND Code = 'MKT');
DECLARE @DeptKD BIGINT = (SELECT Id FROM core.Departments WHERE CompanyId = @C AND Code = 'KD');

/* ---------- 2. Dự án & công việc ---------- */
IF NOT EXISTS (SELECT 1 FROM prj.TaskStages WHERE CompanyId = @C AND ProjectId IS NULL)
    INSERT prj.TaskStages (CompanyId, ProjectId, Name, SortOrder, IsDone)
    VALUES (@C, NULL, N'Cần làm', 10, 0), (@C, NULL, N'Đang làm', 20, 0), (@C, NULL, N'Chờ duyệt', 30, 0), (@C, NULL, N'Hoàn thành', 40, 1);

IF NOT EXISTS (SELECT 1 FROM prj.Projects WHERE CompanyId = @C)
BEGIN
    DECLARE @S1 BIGINT = (SELECT Id FROM prj.TaskStages WHERE CompanyId = @C AND ProjectId IS NULL AND SortOrder = 10);
    DECLARE @S2 BIGINT = (SELECT Id FROM prj.TaskStages WHERE CompanyId = @C AND ProjectId IS NULL AND SortOrder = 20);
    DECLARE @S3 BIGINT = (SELECT Id FROM prj.TaskStages WHERE CompanyId = @C AND ProjectId IS NULL AND SortOrder = 30);
    DECLARE @S4 BIGINT = (SELECT Id FROM prj.TaskStages WHERE CompanyId = @C AND ProjectId IS NULL AND SortOrder = 40);

    DECLARE @P TABLE (K INT, Name NVARCHAR(255), Manager BIGINT, Dept BIGINT, StartOff INT, EndOff INT, Budget DECIMAL(18,2), Status VARCHAR(10), Descr NVARCHAR(500));
    INSERT @P VALUES
     (1, N'Khai trương chi nhánh Quận 7', @Nhung, @DeptCH, -20, 25, 150000000, 'active', N'Mặt bằng 45 Nguyễn Thị Thập, Q.7. Mục tiêu khai trương trước 20/12 để kịp mùa Tết.'),
     (2, N'Chụp lookbook Tết 2027', @Mai, @DeptMKT, -10, 12, 35000000, 'active', N'40 outfit BST Tết, ảnh dùng cho website, Facebook, TikTok và in standee.'),
     (3, N'Kiểm kê kho cuối năm 2026', @Tung, @DeptKHO, 25, 30, 0, 'planning', N'Kiểm kê toàn bộ kho KHO01, đối chiếu sổ sách trước khi khóa sổ năm.'),
     (4, N'Ra mắt website mystyle.vn', @Vy, @DeptKD, -60, -20, 25000000, 'completed', N'Website bán hàng kết nối kho, đơn online đổ thẳng về app Đơn hàng.');

    DECLARE @PId TABLE (K INT, Id BIGINT);
    DECLARE @k INT = 1, @no VARCHAR(50), @d DATE;
    WHILE @k <= 4
    BEGIN
        SELECT @d = DATEADD(DAY, StartOff, @Today) FROM @P WHERE K = @k;
        EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'PROJECT', @DocDate = @d, @DocNo = @no OUTPUT;
        INSERT prj.Projects (CompanyId, Code, Name, ManagerUserId, DepartmentId, StartDate, EndDate, Budget, Status, Description, CreatedAt, CreatedBy)
        SELECT @C, @no, Name, Manager, Dept, DATEADD(DAY, StartOff, @Today), DATEADD(DAY, EndOff, @Today), Budget, Status, Descr,
               DATEADD(DAY, StartOff - 3, @Now), @Admin
        FROM @P WHERE K = @k;
        INSERT @PId VALUES (@k, SCOPE_IDENTITY());
        SET @k += 1;
    END

    INSERT prj.ProjectMembers (ProjectId, UserId, MemberRole)
    SELECT p.Id, m.UserId, CASE WHEN m.UserId = pp.Manager THEN 'manager' ELSE 'member' END
    FROM @PId p JOIN @P pp ON pp.K = p.K
    JOIN (VALUES (1, @Nhung), (1, @Chau), (1, @DucAnh), (1, @Tung), (1, @Mai), (1, @Admin),
                 (2, @Mai), (2, @Vy), (2, @Chau), (2, @Admin),
                 (3, @Tung), (3, @DucAnh), (3, @Admin),
                 (4, @Vy), (4, @Mai), (4, @Admin)) m(K, UserId) ON m.K = p.K;

    /* Stage: 1 Cần làm, 2 Đang làm, 3 Chờ duyệt, 4 Hoàn thành. DoneOff: số ngày trước hôm nay đã xong. */
    DECLARE @T TABLE (Ln INT IDENTITY, PK INT NULL, Title NVARCHAR(255), Stage INT, Priority VARCHAR(8), Assignee BIGINT NULL, Dept BIGINT NULL,
                      DueOff INT NULL, Progress DECIMAL(5,2), Est DECIMAL(8,2) NULL, DoneOff INT NULL, Descr NVARCHAR(500) NULL);
    INSERT @T (PK, Title, Stage, Priority, Assignee, Dept, DueOff, Progress, Est, DoneOff, Descr) VALUES
     (1, N'Ký hợp đồng thuê mặt bằng 45 Nguyễn Thị Thập', 4, 'high', @Nhung, @DeptCH, -15, 100, 4, 16, N'Thuê 3 năm, cọc 3 tháng. Hợp đồng lưu ở app Tài liệu.'),
     (1, N'Đăng ký hộ kinh doanh chi nhánh', 4, 'normal', @Nhung, @DeptCH, -10, 100, 3, 9, NULL),
     (1, N'Thi công nội thất, kệ trưng bày', 2, 'high', @Nhung, @DeptCH, 7, 40, 40, NULL, N'Đơn vị thi công: Nội thất Hòa Phát Decor. Nghiệm thu trước khi nhập hàng.'),
     (1, N'Tuyển 3 nhân viên bán hàng ca xoay', 2, 'normal', @Nhung, @DeptCH, 10, 30, 12, NULL, N'Đăng tin Facebook group việc làm Q7, phỏng vấn tại cửa hàng Lê Lợi.'),
     (1, N'Thiết kế standee, banner khai trương', 3, 'high', @Mai, @DeptMKT, -2, 90, 10, NULL, N'Đã gửi bản thiết kế, chờ chị Nhung duyệt.'),
     (1, N'Lắp đặt máy POS, camera, wifi', 1, 'normal', @DucAnh, @DeptCH, 15, 0, 6, NULL, NULL),
     (1, N'Nhập hàng trưng bày khai trương (300 SKU)', 1, 'normal', @Tung, @DeptKHO, 18, 0, 16, NULL, N'Lấy danh sách SKU bán chạy 60 ngày ở app Báo cáo.'),
     (1, N'Chạy quảng cáo Facebook bán kính 3km quanh Q7', 1, 'high', @Mai, @DeptMKT, 20, 0, 8, NULL, N'Gắn mã giảm giá KHAITRUONG cho chiến dịch để đo doanh thu.'),
     (2, N'Chốt concept & moodboard', 4, 'normal', @Mai, @DeptMKT, -6, 100, 6, 7, NULL),
     (2, N'Book studio và người mẫu', 4, 'normal', @Mai, @DeptMKT, -3, 100, 3, 4, NULL),
     (2, N'Chọn 40 outfit từ BST Tết', 2, 'high', @Vy, @DeptKD, 2, 50, 8, NULL, NULL),
     (2, N'Chụp ảnh 2 ngày tại studio', 1, 'urgent', @Mai, @DeptMKT, 5, 0, 16, NULL, NULL),
     (2, N'Retouch & xuất ảnh cho website / social', 1, 'normal', @Vy, @DeptKD, 9, 0, 12, NULL, NULL),
     (2, N'Đăng lookbook lên website và Facebook', 1, 'normal', @Vy, @DeptKD, 12, 0, 3, NULL, NULL),
     (3, N'Lập kế hoạch kiểm kê, chia khu vực kệ', 1, 'normal', @Tung, @DeptKHO, 20, 0, 4, NULL, NULL),
     (3, N'In phiếu kiểm kê theo kệ', 1, 'low', @DucAnh, @DeptKHO, 24, 0, 2, NULL, NULL),
     (3, N'Đối chiếu chênh lệch, lập biên bản kiểm kê', 1, 'normal', @Tung, @DeptKHO, 30, 0, 6, NULL, NULL),
     (4, N'Chọn giao diện, cấu hình tên miền', 4, 'normal', @Vy, @DeptKD, -50, 100, 8, 52, NULL),
     (4, N'Chụp ảnh sản phẩm, viết mô tả 20 mẫu', 4, 'normal', @Mai, @DeptMKT, -35, 100, 24, 36, NULL),
     (4, N'Kết nối đơn online về app Đơn hàng', 4, 'high', @Admin, NULL, -28, 100, 6, 29, NULL),
     (4, N'Chạy thử, sửa lỗi và mở bán', 4, 'high', @Vy, @DeptKD, -20, 100, 6, 20, NULL),
     (NULL, N'Xuất hóa đơn VAT tháng 11 cho khách sỉ', 1, 'normal', NULL, @DeptKT, 3, 0, 2, NULL, N'Giao cho phòng Kế toán. Danh sách khách cần hóa đơn: xem đơn có ghi chú "lấy VAT".'),
     (NULL, N'Gọi lại 5 khách VIP lâu chưa mua', 2, 'high', @Chau, @DeptCH, -1, 40, 2, NULL, N'Danh sách ở app Marketing > Nhóm khách hàng > Sắp mất.'),
     (NULL, N'Kiểm tra hàng lỗi đổi trả tuần này', 1, 'normal', @Tung, @DeptKHO, 2, 0, 2, NULL, NULL),
     (NULL, N'Cập nhật giá Shopee sau đợt sale 11.11', 4, 'normal', @Vy, @DeptKD, -6, 100, 2, 7, NULL),
     (NULL, N'Duyệt kế hoạch marketing tháng 12', 3, 'high', @Admin, NULL, 4, 80, 1, NULL, N'Mai gửi kế hoạch: ngân sách 30 triệu, 3 chiến dịch.');

    DECLARE @TId TABLE (Ln INT, Id BIGINT);
    DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @T);
    WHILE @i <= @n
    BEGIN
        EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'TASK', @DocDate = @Today, @DocNo = @no OUTPUT;
        INSERT prj.Tasks (CompanyId, Code, ProjectId, Title, Description, StageId, Priority, AssigneeUserId, ReporterUserId, DepartmentId,
                          StartDate, DueDate, CompletedAt, EstimatedHours, ProgressPercent, CreatedAt, CreatedBy)
        SELECT @C, @no, p.Id, t.Title, t.Descr, CASE t.Stage WHEN 1 THEN @S1 WHEN 2 THEN @S2 WHEN 3 THEN @S3 ELSE @S4 END, t.Priority, t.Assignee,
               COALESCE(pp.Manager, @Admin), t.Dept, DATEADD(DAY, ISNULL(t.DueOff, 0) - 7, @Today),
               CASE WHEN t.DueOff IS NULL THEN NULL ELSE CAST(DATEADD(DAY, t.DueOff, @Today) AS DATETIME2(0)) END,
               CASE WHEN t.Stage = 4 THEN DATEADD(DAY, -ISNULL(t.DoneOff, 1), @Now) END, t.Est, t.Progress,
               DATEADD(DAY, ISNULL(t.DueOff, 0) - 10, @Now), COALESCE(pp.Manager, @Admin)
        FROM @T t LEFT JOIN @PId p ON p.K = t.PK LEFT JOIN @P pp ON pp.K = t.PK
        WHERE t.Ln = @i;
        INSERT @TId VALUES (@i, SCOPE_IDENTITY());
        SET @i += 1;
    END

    /* Checklist: tiến độ việc = tỷ lệ mục đã xong */
    INSERT prj.TaskChecklistItems (TaskId, Title, IsDone, SortOrder)
    SELECT ti.Id, c.Title, c.IsDone, c.SortOrder
    FROM @TId ti JOIN @T t ON t.Ln = ti.Ln
    JOIN (VALUES (N'Thi công nội thất, kệ trưng bày', N'Vẽ layout cửa hàng', 1, 10), (N'Thi công nội thất, kệ trưng bày', N'Chốt báo giá thi công', 1, 20),
                 (N'Thi công nội thất, kệ trưng bày', N'Lắp kệ, móc treo', 0, 30), (N'Thi công nội thất, kệ trưng bày', N'Lắp đèn, gương phòng thử', 0, 40),
                 (N'Thi công nội thất, kệ trưng bày', N'Nghiệm thu', 0, 50),
                 (N'Chọn 40 outfit từ BST Tết', N'Nam: 15 outfit', 1, 10), (N'Chọn 40 outfit từ BST Tết', N'Nữ: 20 outfit', 0, 20),
                 (N'Chọn 40 outfit từ BST Tết', N'Phụ kiện, giày đi kèm', 1, 30), (N'Chọn 40 outfit từ BST Tết', N'Chốt danh sách với Mai', 0, 40),
                 (N'Chụp ảnh 2 ngày tại studio', N'Chuẩn bị đồ, là ủi', 0, 10), (N'Chụp ảnh 2 ngày tại studio', N'Shotlist từng outfit', 0, 20),
                 (N'Gọi lại 5 khách VIP lâu chưa mua', N'Chị Hoa - 0901***', 1, 10), (N'Gọi lại 5 khách VIP lâu chưa mua', N'Anh Long', 1, 20),
                 (N'Gọi lại 5 khách VIP lâu chưa mua', N'Chị Trang', 0, 30), (N'Gọi lại 5 khách VIP lâu chưa mua', N'Anh Phúc', 0, 40),
                 (N'Gọi lại 5 khách VIP lâu chưa mua', N'Chị Ngọc', 0, 50)) c(TaskTitle, Title, IsDone, SortOrder) ON c.TaskTitle = t.Title;

    /* Giờ làm */
    INSERT prj.Timesheets (TaskId, ProjectId, UserId, WorkDate, Hours, Note, CreatedAt)
    SELECT ti.Id, p.Id, h.UserId, DATEADD(DAY, h.DayOff, @Today), h.Hours, h.Note, DATEADD(DAY, h.DayOff, @Now)
    FROM @TId ti JOIN @T t ON t.Ln = ti.Ln LEFT JOIN @PId p ON p.K = t.PK
    JOIN (VALUES (N'Ký hợp đồng thuê mặt bằng 45 Nguyễn Thị Thập', @Nhung, -17, 3.0, N'Đàm phán với chủ nhà'),
                 (N'Ký hợp đồng thuê mặt bằng 45 Nguyễn Thị Thập', @Nhung, -16, 1.5, N'Ký hợp đồng'),
                 (N'Thi công nội thất, kệ trưng bày', @Nhung, -6, 4.0, N'Làm việc với đơn vị thi công'),
                 (N'Thi công nội thất, kệ trưng bày', @Nhung, -2, 3.5, N'Giám sát lắp kệ'),
                 (N'Thiết kế standee, banner khai trương', @Mai, -4, 5.0, N'Thiết kế bản 1'),
                 (N'Thiết kế standee, banner khai trương', @Mai, -3, 3.0, N'Sửa theo góp ý'),
                 (N'Chốt concept & moodboard', @Mai, -8, 4.0, NULL),
                 (N'Chọn 40 outfit từ BST Tết', @Vy, -1, 4.0, N'Chọn đồ nam + phụ kiện'),
                 (N'Chụp ảnh sản phẩm, viết mô tả 20 mẫu', @Mai, -40, 8.0, NULL),
                 (N'Chụp ảnh sản phẩm, viết mô tả 20 mẫu', @Mai, -38, 8.0, NULL),
                 (N'Kết nối đơn online về app Đơn hàng', @Admin, -30, 6.0, NULL),
                 (N'Gọi lại 5 khách VIP lâu chưa mua', @Chau, -1, 1.0, N'Gọi được 2/5 khách')) h(TaskTitle, UserId, DayOff, Hours, Note) ON h.TaskTitle = t.Title;

    /* Tiến độ dự án = trung bình tiến độ công việc */
    UPDATE p SET ProgressPercent = CASE WHEN p.Status = 'completed' THEN 100 ELSE ISNULL(x.Avg, 0) END
    FROM prj.Projects p
    OUTER APPLY (SELECT CAST(AVG(t.ProgressPercent) AS DECIMAL(5,2)) Avg FROM prj.Tasks t WHERE t.ProjectId = p.Id AND t.IsDeleted = 0) x
    WHERE p.CompanyId = @C;
    PRINT N'Đã tạo 4 dự án, ' + CAST(@n AS NVARCHAR(10)) + N' công việc.';
END

/* ---------- 3. Tài liệu ---------- */
IF NOT EXISTS (SELECT 1 FROM doc.Folders WHERE CompanyId = @C)
BEGIN
    INSERT doc.Folders (CompanyId, Name, OwnerUserId, DepartmentId, CreatedAt, CreatedBy) VALUES
     (@C, N'Hợp đồng', @Admin, NULL, DATEADD(DAY, -90, @Now), @Admin),
     (@C, N'Quy trình - Quy định', @Admin, NULL, DATEADD(DAY, -90, @Now), @Admin),
     (@C, N'Biểu mẫu', @Admin, NULL, DATEADD(DAY, -90, @Now), @Admin),
     (@C, N'Kho vận', @Tung, @DeptKHO, DATEADD(DAY, -60, @Now), @Admin),
     (@C, N'Marketing', @Mai, @DeptMKT, DATEADD(DAY, -60, @Now), @Admin);
    DECLARE @FHD BIGINT = (SELECT Id FROM doc.Folders WHERE CompanyId = @C AND Name = N'Hợp đồng');
    DECLARE @FQT BIGINT = (SELECT Id FROM doc.Folders WHERE CompanyId = @C AND Name = N'Quy trình - Quy định');
    DECLARE @FBM BIGINT = (SELECT Id FROM doc.Folders WHERE CompanyId = @C AND Name = N'Biểu mẫu');
    DECLARE @FKHO BIGINT = (SELECT Id FROM doc.Folders WHERE CompanyId = @C AND Name = N'Kho vận');
    DECLARE @FMKT BIGINT = (SELECT Id FROM doc.Folders WHERE CompanyId = @C AND Name = N'Marketing');

    /* Chưa có file đính kèm (CurrentVersionNo = 0): bấm vào tài liệu để tải file lên. */
    INSERT doc.Documents (CompanyId, FolderId, Code, Title, DocumentType, PartnerId, CurrentVersionNo, OwnerUserId, Status, EffectiveDate, ExpiryDate,
                          ContractValue, CreatedAt, CreatedBy)
    VALUES
     (@C, @FHD, 'HD-TMB-01', N'Hợp đồng thuê mặt bằng cửa hàng 123 Lê Lợi', 'contract', NULL, 0, @Admin, 'active',
        DATEADD(DAY, -709, @Today), DATEADD(DAY, 21, @Today), 960000000, DATEADD(DAY, -710, @Now), @Admin),
     (@C, @FHD, 'HD-TMB-02', N'Hợp đồng thuê mặt bằng chi nhánh Q7 (45 Nguyễn Thị Thập)', 'contract', NULL, 0, @Nhung, 'signed',
        DATEADD(DAY, -16, @Today), DATEADD(DAY, 1079, @Today), 1620000000, DATEADD(DAY, -17, @Now), @Admin),
     (@C, @FHD, 'HD-NCC-01', N'Hợp đồng nguyên tắc cung cấp hàng may mặc 2026', 'contract',
        (SELECT Id FROM md.Partners WHERE CompanyId = @C AND Code = 'NCC-0001'), 0, @Admin, 'active',
        DATEADD(DAY, -300, @Today), DATEADD(DAY, 65, @Today), 500000000, DATEADD(DAY, -301, @Now), @Admin),
     (@C, @FHD, 'HD-NCC-03', N'Hợp đồng cung cấp vải và quần jeans', 'contract',
        (SELECT Id FROM md.Partners WHERE CompanyId = @C AND Code = 'NCC-0003'), 0, @Admin, 'active',
        DATEADD(DAY, -200, @Today), DATEADD(DAY, 165, @Today), 300000000, DATEADD(DAY, -201, @Now), @Admin),
     (@C, @FHD, 'HD-NCC-04', N'Hợp đồng phân phối giày da 2025', 'contract',
        (SELECT Id FROM md.Partners WHERE CompanyId = @C AND Code = 'NCC-0004'), 0, @Admin, 'active',
        DATEADD(DAY, -400, @Today), DATEADD(DAY, -35, @Today), 180000000, DATEADD(DAY, -401, @Now), @Admin),
     (@C, @FHD, 'HD-VC-01', N'Hợp đồng dịch vụ giao hàng GHN', 'contract', NULL, 0, @Tung, 'pending_signature',
        NULL, NULL, NULL, DATEADD(DAY, -3, @Now), @Admin),
     (@C, @FQT, NULL, N'Chính sách đổi trả hàng (áp dụng 2026)', 'policy', NULL, 0, @Admin, 'active',
        DATEADD(DAY, -320, @Today), NULL, NULL, DATEADD(DAY, -321, @Now), @Admin),
     (@C, @FQT, NULL, N'Quy định chấm công, nghỉ phép', 'policy', NULL, 0, @Admin, 'active',
        DATEADD(DAY, -320, @Today), NULL, NULL, DATEADD(DAY, -321, @Now), @Admin),
     (@C, @FKHO, NULL, N'Quy trình nhập kho và kiểm hàng', 'process', NULL, 0, @Tung, 'active',
        DATEADD(DAY, -150, @Today), NULL, NULL, DATEADD(DAY, -151, @Now), @Tung),
     (@C, @FBM, NULL, N'Mẫu phiếu bảo hành giày', 'form', NULL, 0, @Admin, 'active',
        NULL, NULL, NULL, DATEADD(DAY, -120, @Now), @Admin),
     (@C, @FBM, NULL, N'Mẫu biên bản bàn giao ca', 'form', NULL, 0, @Nhung, 'draft',
        NULL, NULL, NULL, DATEADD(DAY, -2, @Now), @Nhung),
     (@C, @FMKT, NULL, N'Báo cáo hiệu quả quảng cáo tháng 10', 'report', NULL, 0, @Mai, 'active',
        NULL, NULL, NULL, DATEADD(DAY, -20, @Now), @Mai);
    PRINT N'Đã tạo 5 thư mục, 12 tài liệu.';
END

/* ---------- 4. Chat nội bộ ---------- */
IF NOT EXISTS (SELECT 1 FROM chat.Messages m JOIN chat.Channels c ON c.Id = m.ChannelId WHERE c.CompanyId = @C)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM chat.Channels WHERE CompanyId = @C AND ChannelType = 'company')
        INSERT chat.Channels (CompanyId, Name, ChannelType, IsPrivate, CreatedAt) VALUES (@C, N'Toàn công ty', 'company', 0, DATEADD(DAY, -30, @Now));
    INSERT chat.Channels (CompanyId, Name, ChannelType, IsPrivate, CreatedAt, CreatedBy) VALUES
     (@C, N'Cửa hàng Lê Lợi', 'group', 1, DATEADD(DAY, -30, @Now), @Nhung),
     (@C, N'Marketing & Online', 'group', 1, DATEADD(DAY, -30, @Now), @Mai);
    INSERT chat.Channels (CompanyId, Name, ChannelType, IsPrivate, CreatedAt, CreatedBy) VALUES (@C, NULL, 'direct', 1, DATEADD(DAY, -5, @Now), @Nhung);

    DECLARE @ChCo BIGINT = (SELECT TOP 1 Id FROM chat.Channels WHERE CompanyId = @C AND ChannelType = 'company' ORDER BY Id);
    DECLARE @ChStore BIGINT = (SELECT Id FROM chat.Channels WHERE CompanyId = @C AND Name = N'Cửa hàng Lê Lợi');
    DECLARE @ChMkt BIGINT = (SELECT Id FROM chat.Channels WHERE CompanyId = @C AND Name = N'Marketing & Online');
    DECLARE @ChDm BIGINT = (SELECT TOP 1 Id FROM chat.Channels WHERE CompanyId = @C AND ChannelType = 'direct' ORDER BY Id DESC);

    INSERT chat.ChannelMembers (ChannelId, UserId, MemberRole, JoinedAt)
    SELECT m.Ch, m.U, m.R, DATEADD(DAY, -30, @Now)
    FROM (VALUES (@ChStore, @Nhung, 'owner'), (@ChStore, @Chau, 'member'), (@ChStore, @DucAnh, 'member'), (@ChStore, @Tung, 'member'), (@ChStore, @Admin, 'member'),
                 (@ChMkt, @Mai, 'owner'), (@ChMkt, @Vy, 'member'), (@ChMkt, @Admin, 'member'),
                 (@ChDm, @Nhung, 'member'), (@ChDm, @Admin, 'member'),
                 (@ChCo, @Admin, 'member'), (@ChCo, @Nhung, 'member'), (@ChCo, @Mai, 'member')) m(Ch, U, R);

    /* MinAgo: số phút trước hiện tại. Thêm theo thứ tự thời gian để Id tăng dần. */
    DECLARE @M TABLE (Ln INT IDENTITY, Ch BIGINT, Sender BIGINT, MinAgo INT, Body NVARCHAR(1000));
    INSERT @M (Ch, Sender, MinAgo, Body) VALUES
     (@ChCo, @Admin, 2900, N'Chào cả nhà! Từ tuần này mình dùng chat nội bộ trên MyERP thay cho nhóm Zalo nhé, có gì trao đổi việc ở đây cho dễ tìm lại.'),
     (@ChCo, @Nhung, 2880, N'Ok anh, em đã nhắc các bạn ở cửa hàng rồi ạ.'),
     (@ChCo, @Mai, 2860, N'Marketing đã tạo mã giảm giá BLACKFRIDAY, áp dụng từ thứ 6 tuần này. Mọi người tư vấn khách giúp em nhé 🙌'),
     (@ChStore, @Nhung, 1500, N'Sáng mai 8h họp nhanh ca sáng 10 phút nha các em.'),
     (@ChStore, @Chau, 1490, N'Dạ chị.'),
     (@ChStore, @Tung, 1450, N'Hàng áo khoác bomber về chiều nay, ca chiều ai rảnh phụ anh kiểm hàng với.'),
     (@ChStore, @DucAnh, 1440, N'Em phụ anh Tùng được ạ.'),
     (@ChMkt, @Mai, 1300, N'Vy ơi, lookbook Tết em chọn outfit tới đâu rồi?'),
     (@ChMkt, @Vy, 1280, N'Em chọn xong đồ nam rồi chị, đồ nữ chiều nay em gửi danh sách ạ.'),
     (@ChMkt, @Mai, 1270, N'Ok em, nhớ chọn thêm giày sneaker trắng phối cùng nhé, đang bán chạy.'),
     (@ChDm, @Nhung, 600, N'Anh ơi, bản thiết kế standee khai trương Q7 Mai gửi rồi, anh xem giúp em trong hôm nay được không ạ?'),
     (@ChDm, @Admin, 590, N'Ok em, chiều anh xem rồi duyệt trên app Dự án luôn.'),
     (@ChCo, @Nhung, 300, N'Doanh thu hôm qua cửa hàng Lê Lợi vượt chỉ tiêu 15% 🎉 Cảm ơn cả team!'),
     (@ChStore, @Chau, 120, N'Chị ơi khách hỏi áo polo pique size XL màu navy còn không ạ? Em check kho thấy còn 2 cái.'),
     (@ChDm, @Nhung, 45, N'À anh ơi, hợp đồng thuê mặt bằng Lê Lợi còn khoảng 3 tuần là hết hạn, mình gia hạn luôn nha anh?'),
     (@ChCo, @Mai, 30, N'Nhắc mọi người: tối nay 20h livestream TikTok, ai rảnh vào thả tim giúp em với ạ ❤️');

    INSERT chat.Messages (ChannelId, SenderUserId, Body, CreatedAt)
    SELECT Ch, Sender, Body, DATEADD(MINUTE, -MinAgo, @Now) FROM @M ORDER BY Ln;

    UPDATE c SET LastMessageAt = x.LastAt
    FROM chat.Channels c CROSS APPLY (SELECT MAX(m.CreatedAt) LastAt FROM chat.Messages m WHERE m.ChannelId = c.Id) x
    WHERE c.CompanyId = @C AND x.LastAt IS NOT NULL;

    /* Mọi người đã đọc hết, riêng admin còn vài tin mới chưa đọc (để thấy số tin chưa đọc). */
    UPDATE cm SET LastReadMessageId = (SELECT MAX(m.Id) FROM chat.Messages m WHERE m.ChannelId = cm.ChannelId)
    FROM chat.ChannelMembers cm WHERE cm.ChannelId IN (@ChCo, @ChStore, @ChMkt, @ChDm);
    UPDATE cm SET LastReadMessageId = (SELECT MAX(m.Id) FROM chat.Messages m WHERE m.ChannelId = cm.ChannelId AND m.CreatedAt < DATEADD(MINUTE, -400, @Now))
    FROM chat.ChannelMembers cm WHERE cm.UserId = @Admin AND cm.ChannelId IN (@ChCo, @ChStore);
    UPDATE cm SET LastReadMessageId = (SELECT MAX(m.Id) FROM chat.Messages m WHERE m.ChannelId = cm.ChannelId AND m.CreatedAt < DATEADD(MINUTE, -100, @Now))
    FROM chat.ChannelMembers cm WHERE cm.UserId = @Admin AND cm.ChannelId = @ChDm;

    INSERT chat.MessageReactions (MessageId, UserId, Reaction, CreatedAt)
    SELECT m.Id, r.U, r.R, DATEADD(MINUTE, 5, m.CreatedAt)
    FROM chat.Messages m
    JOIN (VALUES (N'Doanh thu hôm qua%', @Admin, N'🎉'), (N'Doanh thu hôm qua%', @Mai, N'❤️'), (N'Doanh thu hôm qua%', @Chau, N'👍'),
                 (N'Chào cả nhà!%', @Nhung, N'👍'), (N'Chào cả nhà!%', @Mai, N'👍'),
                 (N'Marketing đã tạo mã%', @Nhung, N'✅')) r(Pat, U, R) ON m.Body LIKE r.Pat
    WHERE m.ChannelId IN (@ChCo, @ChStore, @ChMkt, @ChDm);
    PRINT N'Đã tạo 4 kênh chat và tin nhắn mẫu.';
END

/* ---------- 5. Website ---------- */
IF NOT EXISTS (SELECT 1 FROM web.Sites WHERE CompanyId = @C)
BEGIN
    INSERT web.Sites (CompanyId, Name, Domain, WarehouseId, Settings, IsActive)
    VALUES (@C, N'MyStyle Fashion', 'mystyle.vn', (SELECT TOP 1 Id FROM inv.Warehouses WHERE CompanyId = @C ORDER BY Id),
            N'{"slogan":"Mặc đẹp mỗi ngày","hotline":"0909 123 456","email":"cskh@mystyle.vn","address":"123 Lê Lợi, Phường Bến Thành, Quận 1, TP.HCM","openingHours":"8:30 - 22:00 hằng ngày","facebook":"https://facebook.com/mystyle.vn","instagram":"https://instagram.com/mystyle.vn","tiktok":"https://tiktok.com/@mystyle.vn","zalo":"0909123456","primaryColor":"#D4537E"}', 1);
    DECLARE @Site BIGINT = SCOPE_IDENTITY();

    INSERT web.Menus (SiteId, Code) VALUES (@Site, 'header'), (@Site, 'footer');
    INSERT web.MenuItems (MenuId, Label, Url, SortOrder)
    SELECT m.Id, i.Label, i.Url, i.SortOrder
    FROM web.Menus m
    JOIN (VALUES ('header', N'Trang chủ', '/', 10), ('header', N'Nam', '/collections/nam', 20), ('header', N'Nữ', '/collections/nu', 30),
                 ('header', N'Giày dép', '/collections/giay-dep', 40), ('header', N'Lookbook', '/blog/phoi-do', 50), ('header', N'Liên hệ', '/lien-he', 60),
                 ('footer', N'Giới thiệu', '/pages/gioi-thieu', 10), ('footer', N'Chính sách đổi trả', '/pages/chinh-sach-doi-tra', 20),
                 ('footer', N'Hướng dẫn chọn size', '/pages/huong-dan-chon-size', 30), ('footer', N'Chính sách giao hàng', '/pages/chinh-sach-giao-hang', 40)) i(Code, Label, Url, SortOrder)
      ON i.Code = m.Code
    WHERE m.SiteId = @Site;

    INSERT web.Pages (SiteId, Slug, Title, Content, MetaDescription, IsPublished, PublishedAt, CreatedAt, CreatedBy) VALUES
     (@Site, 'gioi-thieu', N'Giới thiệu MyStyle',
      N'MyStyle là thương hiệu thời trang Việt dành cho người trẻ đi làm và đi chơi. Chúng tôi chọn chất liệu thoáng mát, phom dáng dễ mặc, giá hợp lý.' + CHAR(10) + CHAR(10) +
      N'Cửa hàng: 123 Lê Lợi, Quận 1 - mở cửa 8:30 đến 22:00 hằng ngày. Sắp khai trương chi nhánh Quận 7.',
      N'MyStyle - thời trang nam nữ, giày dép, phụ kiện. Mặc đẹp mỗi ngày.', 1, DATEADD(DAY, -25, @Now), DATEADD(DAY, -30, @Now), @Admin),
     (@Site, 'chinh-sach-doi-tra', N'Chính sách đổi trả',
      N'- Đổi size, đổi mẫu trong 7 ngày kể từ ngày nhận hàng, sản phẩm còn tem mác, chưa giặt.' + CHAR(10) +
      N'- Hoàn tiền 100% nếu sản phẩm lỗi do nhà sản xuất.' + CHAR(10) +
      N'- Sản phẩm giảm giá trên 50% không áp dụng đổi trả.' + CHAR(10) +
      N'- Mang hóa đơn hoặc báo số điện thoại khi mua để tra đơn.',
      N'Đổi trả trong 7 ngày, hoàn tiền nếu lỗi sản xuất.', 1, DATEADD(DAY, -25, @Now), DATEADD(DAY, -30, @Now), @Admin),
     (@Site, 'huong-dan-chon-size', N'Hướng dẫn chọn size',
      N'Áo: S (45-52kg), M (52-60kg), L (60-68kg), XL (68-76kg), XXL (76-85kg).' + CHAR(10) +
      N'Quần jeans: chọn theo số đo vòng eo, size 28 tương đương eo 71cm, mỗi size tăng 2,5cm.' + CHAR(10) +
      N'Giày: đo chiều dài bàn chân, cộng thêm 1cm rồi đối chiếu bảng size 36-44.',
      N'Bảng size áo, quần, giày MyStyle.', 1, DATEADD(DAY, -25, @Now), DATEADD(DAY, -30, @Now), @Admin),
     (@Site, 'chinh-sach-giao-hang', N'Chính sách giao hàng',
      N'Giao toàn quốc qua GHN, GHTK, Viettel Post. Nội thành TP.HCM 1-2 ngày, tỉnh khác 2-4 ngày.' + CHAR(10) +
      N'Miễn phí giao hàng cho đơn từ 300.000đ (mã FREESHIP300). Được kiểm tra hàng trước khi nhận.',
      N'Giao toàn quốc, miễn phí ship đơn từ 300k.', 0, NULL, DATEADD(DAY, -5, @Now), @Admin);

    INSERT web.PostCategories (SiteId, Slug, Name) VALUES (@Site, 'phoi-do', N'Phối đồ'), (@Site, 'xu-huong', N'Xu hướng'), (@Site, 'tin-cua-hang', N'Tin cửa hàng');
    DECLARE @CatPhoi BIGINT = (SELECT Id FROM web.PostCategories WHERE SiteId = @Site AND Slug = 'phoi-do');
    DECLARE @CatXH BIGINT = (SELECT Id FROM web.PostCategories WHERE SiteId = @Site AND Slug = 'xu-huong');
    DECLARE @CatTin BIGINT = (SELECT Id FROM web.PostCategories WHERE SiteId = @Site AND Slug = 'tin-cua-hang');

    INSERT web.Posts (SiteId, CategoryId, Slug, Title, Summary, Content, AuthorUserId, IsPublished, PublishedAt, ViewCount, CreatedAt, CreatedBy) VALUES
     (@Site, @CatPhoi, '5-cach-phoi-ao-thun-basic-di-lam', N'5 cách phối áo thun basic đi làm vẫn lịch sự',
      N'Áo thun basic không chỉ để mặc ở nhà. Phối cùng blazer, quần kaki hay chân váy chữ A là đủ chỉn chu đi làm.',
      N'1. Áo thun trắng + blazer + quần kaki.' + CHAR(10) + N'2. Áo thun đen + chân váy chữ A + giày cao gót.' + CHAR(10) + N'3. Áo thun + sơ mi khoác ngoài.' + CHAR(10) + N'4. Áo thun sơ vin + quần jeans slim fit + giày tây.' + CHAR(10) + N'5. Áo thun + áo khoác bomber cho ngày se lạnh.',
      @Mai, 1, DATEADD(DAY, -21, @Now), 1840, DATEADD(DAY, -22, @Now), @Mai),
     (@Site, @CatXH, 'xu-huong-mau-sac-tet-2027', N'Xu hướng màu sắc Tết 2027: đỏ đô, kem và xanh rêu',
      N'Ba gam màu được dự báo lên ngôi mùa Tết năm nay và cách chọn đồ hợp tông da.',
      N'Đỏ đô sang trọng hơn đỏ tươi, dễ phối với kem và đen. Xanh rêu hợp với người da ngăm. Kem là màu nền an toàn cho mọi outfit.',
      @Mai, 1, DATEADD(DAY, -9, @Now), 960, DATEADD(DAY, -10, @Now), @Mai),
     (@Site, @CatPhoi, 'chon-giay-sneaker-trang', N'Chọn giày sneaker trắng sao cho bền đẹp',
      N'Mẹo chọn size, chất liệu và vệ sinh giày sneaker trắng luôn như mới.',
      N'Chọn da tổng hợp phủ PU dễ lau chùi. Vệ sinh bằng khăn ẩm sau mỗi lần đi, tránh phơi nắng gắt. Dùng giấy báo nhét giày để giữ form.',
      @Vy, 1, DATEADD(DAY, -15, @Now), 1210, DATEADD(DAY, -16, @Now), @Vy),
     (@Site, @CatTin, 'black-friday-giam-den-50', N'Black Friday: giảm đến 50% toàn bộ cửa hàng',
      N'Nhập mã BLACKFRIDAY giảm thêm khi mua online, áp dụng cả tại cửa hàng Lê Lợi.',
      N'Thời gian: từ thứ 6 đến hết chủ nhật. Áp dụng cho đơn từ 500.000đ. Mỗi khách dùng mã 1 lần.',
      @Mai, 1, DATEADD(DAY, -4, @Now), 2350, DATEADD(DAY, -5, @Now), @Mai),
     (@Site, @CatTin, 'sap-khai-truong-chi-nhanh-quan-7', N'Sắp khai trương chi nhánh Quận 7',
      N'MyStyle mở thêm cửa hàng tại 45 Nguyễn Thị Thập, Quận 7. Nhiều quà tặng dịp khai trương.',
      N'Ngày khai trương dự kiến giữa tháng 12. 100 khách đầu tiên nhận túi tote MyStyle. Theo dõi fanpage để cập nhật.',
      @Nhung, 1, DATEADD(DAY, -2, @Now), 430, DATEADD(DAY, -3, @Now), @Nhung),
     (@Site, @CatPhoi, 'lookbook-tet-2027', N'Lookbook Tết 2027 (bản nháp)',
      N'40 outfit cho Tết - đang chụp, sẽ đăng sau khi retouch xong.', NULL,
      @Vy, 0, NULL, 0, DATEADD(DAY, -1, @Now), @Vy);

    /* Bật hiện trên web 15/20 mẫu đang kinh doanh */
    UPDATE p SET IsPublishedWeb = 1, WebSlug = LOWER(p.Code)
    FROM md.Products p JOIN md.ProductModels m ON m.Id = p.ModelId
    WHERE p.CompanyId = @C AND p.IsActive = 1 AND m.IsActive = 1 AND m.Code NOT IN ('QKK08', 'QSO09', 'GTL16', 'TAT20', 'MLT19');

    /* Liên hệ khách gửi từ website (2 liên hệ đã chuyển thành Lead) */
    INSERT web.ContactSubmissions (SiteId, FormCode, FullName, Phone, Email, Message, PageUrl, UtmSource, UtmMedium, UtmCampaign, IpAddress, ConsentGiven, LeadId, CreatedAt) VALUES
     (@Site, 'contact', N'Lý Thanh Tâm', '0763222111', NULL, N'Mình muốn đặt 30 áo polo in logo cho công ty, báo giá giúp mình.', '/lien-he', 'facebook', 'cpc', 'blackfriday', '113.161.10.20', 1,
        (SELECT Id FROM crm.Leads WHERE CompanyId = @C AND Phone = '0763222111'), DATEADD(DAY, -12, @Now)),
     (@Site, 'contact', N'Tạ Minh Nhật', '0981555444', 'nhat.ta@nhatminh.com.vn', N'Cần đồng phục cho 50 nhân viên văn phòng.', '/lien-he', 'google', 'cpc', NULL, '27.72.101.5', 1,
        (SELECT Id FROM crm.Leads WHERE CompanyId = @C AND Phone = '0981555444'), DATEADD(DAY, -9, @Now)),
     (@Site, 'contact', N'Nguyễn Thu Hà', '0912678345', 'thuha.ng@gmail.com', N'Váy đầm hoa nhí size M còn màu xanh không shop?', '/products/vay-dam-hoa-nhi-vdm10', 'tiktok', 'social', NULL, '171.244.5.9', 1, NULL, DATEADD(DAY, -4, @Now)),
     (@Site, 'contact', N'Trần Quốc Bảo', '0938456123', NULL, N'Giày tây da bò có size 44 không? Mình ở Q7, đợi chi nhánh mới mở.', '/products', NULL, NULL, NULL, '14.161.22.8', 1, NULL, DATEADD(DAY, -3, @Now)),
     (@Site, 'contact', N'Phạm Ngọc Ánh', NULL, 'anh.pham.ngoc@yahoo.com', N'Mình muốn hợp tác làm CTV bán hàng online.', '/lien-he', 'facebook', 'social', NULL, '42.116.7.77', 1, NULL, DATEADD(DAY, -2, @Now)),
     (@Site, 'contact', N'Đỗ Hải Yến', '0909887766', NULL, N'Đơn hàng của mình giao chậm, nhờ shop kiểm tra giúp.', '/lien-he', NULL, NULL, NULL, '113.23.45.67', 1, NULL, DATEADD(HOUR, -20, @Now)),
     (@Site, 'contact', N'Võ Minh Khang', '0977112233', 'khang.vm@outlook.com', N'Có ship COD ra Đà Nẵng không ạ?', '/pages/chinh-sach-giao-hang', 'google', 'organic', NULL, '1.53.88.21', 1, NULL, DATEADD(HOUR, -6, @Now)),
     (@Site, 'contact', N'Lâm Gia Hân', '0868999000', NULL, N'Mã BLACKFRIDAY dùng cho đơn online được không shop?', '/blog/black-friday-giam-den-50', 'facebook', 'cpc', 'blackfriday', '116.110.4.3', 1, NULL, DATEADD(HOUR, -2, @Now));
    PRINT N'Đã tạo website mẫu: 4 trang, 6 bài viết, 8 liên hệ, bật 15 mẫu sản phẩm.';
END
GO
