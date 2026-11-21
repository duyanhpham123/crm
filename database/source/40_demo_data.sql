/* =====================================================================
   MyERP - 40. DỮ LIỆU MẪU (chỉ dùng để dùng thử / demo, KHÔNG chạy trên production)
   - 15 lead với đủ trạng thái, nguồn, giá trị, rải trong ~6 tuần gần đây
   - Mã lead sinh qua core.usp_NextDocNo như khi tạo từ ứng dụng
   - Chạy nhiều lần không bị nhân đôi (đánh dấu UtmCampaign = 'demo-data')

   Chạy:  .\run_all.ps1 -Demo      (tạo DB mới kèm dữ liệu mẫu)
     hoặc sqlcmd -S localhost -E -d MyERP -I -f 65001 -i 40_demo_data.sql
   Xóa dữ liệu mẫu:
          DELETE FROM crm.Leads WHERE UtmCampaign = 'demo-data';
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS (SELECT 1 FROM crm.Leads WHERE UtmCampaign = 'demo-data')
BEGIN
    PRINT N'Dữ liệu mẫu đã có, bỏ qua.';
    RETURN;
END

DECLARE @C BIGINT = (SELECT Id FROM core.Companies WHERE Code = 'ABC');
DECLARE @Owner BIGINT = (SELECT MIN(Id) FROM core.Users WHERE IsSystemAdmin = 1);

DECLARE @Demo TABLE (
    Seq INT IDENTITY(1,1), DaysAgo INT, FullName NVARCHAR(150), Org NVARCHAR(255), Position NVARCHAR(100),
    Phone VARCHAR(20), Email VARCHAR(255), Source VARCHAR(30), Status VARCHAR(12), Reason NVARCHAR(500),
    Value DECIMAL(18,2), Note NVARCHAR(1000));

-- Sắp theo ngày tạo cũ -> mới để số chứng từ tăng dần theo thời gian
INSERT @Demo (DaysAgo, FullName, Org, Position, Phone, Email, Source, Status, Reason, Value, Note) VALUES
 (42, N'Trần Thị Bình',     N'Công ty CP Hưng Thịnh',      N'Giám đốc mua hàng', '0912345678', 'binh.tran@hungthinh.vn',   'FACEBOOK',  'qualified',   NULL, 350000000, N'Cần phần mềm quản lý kho cho 3 chi nhánh'),
 (38, N'Lê Văn Cường',      N'Đại Việt Tech',              N'CTO',               '0903111222', 'cuong@daiviet.tech',       'WEBSITE',   'qualified',   NULL, 480000000, N'Triển khai ERP toàn công ty, 120 người dùng'),
 (35, N'Phạm Minh Đức',     N'Nhựa Tân Tiến',              N'Trưởng phòng KD',   '0389999000', 'duc.pm@tantien.com.vn',    'REFERRAL',  'contacted',   NULL, 120000000, N'Được anh Cường giới thiệu, quan tâm module bán hàng'),
 (31, N'Nguyễn Thu Hà',     N'Dược phẩm An Khang',         N'Kế toán trưởng',    '0977222333', 'ha.nguyen@ankhang.vn',     'GOOGLE',    'qualified',   NULL, 210000000, N'Cần hóa đơn điện tử + kế toán TT200'),
 (27, N'Đỗ Quang Huy',      N'Gạch men Đồng Tâm Việt',     N'Giám đốc',          '0868333444', 'huy.do@dongtamviet.vn',    'EVENT',     'unqualified', N'Không có ngân sách năm nay', 95000000, N'Gặp tại hội chợ Vietbuild'),
 (24, N'Vũ Thị Lan',        N'Logistic Sài Gòn Xanh',      N'COO',               '0934555666', 'lan.vu@sgxanh.vn',         'ZALO',      'contacted',   NULL, 160000000, N'Quan tâm module vận chuyển, đối soát COD'),
 (20, N'Hoàng Anh Tuấn',    N'Thời trang Mộc Lan',         N'Chủ cửa hàng',      '0395666777', 'tuan@moclan.shop',         'TIKTOK',    'new',         NULL,  45000000, N'Bán online, cần đồng bộ đơn Shopee / TikTok Shop'),
 (17, N'Bùi Ngọc Mai',      N'Trường mầm non Hoa Sen',     N'Hiệu trưởng',       '0789777888', 'mai.bui@hoasen.edu.vn',    'FACEBOOK',  'unqualified', N'Nhu cầu không phù hợp, chỉ cần phần mềm học phí', 30000000, N''),
 (14, N'Ngô Đình Khoa',     N'Cơ khí Chính xác Miền Bắc',  N'Phó giám đốc',      '0916888999', 'khoa.ngo@ckmb.vn',         'COLD_CALL', 'contacted',   NULL, 270000000, N'Đang dùng Excel, muốn quản lý sản xuất + kho'),
 (11, N'Trịnh Thị Thảo',    N'Mỹ phẩm Thảo Mộc',           N'Marketing Manager', '0329000111', 'thao@thaomoc.vn',          'FACEBOOK',  'new',         NULL,  80000000, N'Hỏi về CRM + chăm sóc khách hàng qua Zalo'),
 ( 8, N'Đặng Văn Long',     N'Xây dựng Long Phát',         N'Giám đốc',          '0947111000', 'long.dang@longphat.vn',    'REFERRAL',  'qualified',   NULL, 520000000, N'Quản lý dự án công trình, vật tư, công nợ nhà thầu'),
 ( 6, N'Lý Thanh Tâm',      NULL,                          NULL,                 '0763222111', NULL,                       'WEBSITE',   'new',         NULL,  NULL,      N'Để lại số qua form liên hệ, chưa rõ nhu cầu'),
 ( 4, N'Phan Quốc Bảo',     N'Nội thất Bảo An',            N'Chủ doanh nghiệp',  '0858333222', 'bao@noithatbaoan.vn',      'GOOGLE',    'new',         NULL, 150000000, N'Cần báo giá gói Bán hàng + Kho'),
 ( 2, N'Châu Mỹ Linh',      N'Spa Linh Châu',              N'Chủ spa',           '0707444333', 'linh@linhchauspa.vn',      'ZALO',      'new',         NULL,  25000000, N'Quản lý lịch hẹn và khách hàng thân thiết'),
 ( 0, N'Tạ Minh Nhật',      N'Điện máy Nhật Minh',         N'Trưởng phòng IT',   '0981555444', 'nhat.ta@nhatminh.com.vn',  'WEBSITE',   'new',         NULL, 300000000, N'Hẹn demo tuần sau');

DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @Demo), @Code VARCHAR(50), @Created DATETIME2(3), @Date DATE;

BEGIN TRAN;
WHILE @i <= @n
BEGIN
    SELECT @Created = DATEADD(MINUTE, -(@i * 37), DATEADD(DAY, -DaysAgo, SYSUTCDATETIME())) FROM @Demo WHERE Seq = @i;
    SET @Date = CAST(DATEADD(HOUR, 7, @Created) AS DATE);   -- ngày theo giờ Việt Nam
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'LEAD', @DocDate = @Date, @DocNo = @Code OUTPUT;

    INSERT crm.Leads (CompanyId, Code, FullName, OrganizationName, Position, Phone, Email, SourceId, Status,
                      DisqualifyReason, EstimatedValue, InterestNote, OwnerUserId, UtmCampaign, CreatedAt, CreatedBy)
    SELECT @C, @Code, d.FullName, d.Org, d.Position, d.Phone, d.Email, s.Id, d.Status,
           d.Reason, d.Value, NULLIF(d.Note, N''), @Owner, 'demo-data', @Created, @Owner
    FROM @Demo d
    LEFT JOIN crm.LeadSources s ON s.CompanyId = @C AND s.Code = d.Source
    WHERE d.Seq = @i;

    SET @i += 1;
END
COMMIT;

PRINT N'Đã thêm ' + CAST(@n AS NVARCHAR(10)) + N' lead mẫu.';
GO

/* ---------------------------------------------------------------------
   Khách hàng + người liên hệ + cơ hội mẫu
   - 4 lead "Tiềm năng" được chuyển đổi thành khách hàng (như thao tác thật)
   - 10 cơ hội rải đủ giai đoạn: đang mở, quá hạn, đã thắng, thất bại có lý do
   Đánh dấu: md.Partners.Source = N'Dữ liệu mẫu'
   Xóa:  DELETE o FROM crm.Opportunities o JOIN md.Partners p ON p.Id = o.PartnerId WHERE p.Source = N'Dữ liệu mẫu';
         DELETE c FROM md.PartnerContacts c JOIN md.Partners p ON p.Id = c.PartnerId WHERE p.Source = N'Dữ liệu mẫu';
         DELETE FROM md.Partners WHERE Source = N'Dữ liệu mẫu';
   --------------------------------------------------------------------- */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS (SELECT 1 FROM md.Partners WHERE Source = N'Dữ liệu mẫu')
BEGIN
    PRINT N'Khách hàng mẫu đã có, bỏ qua.';
    RETURN;
END

DECLARE @C BIGINT = (SELECT Id FROM core.Companies WHERE Code = 'ABC');
DECLARE @Owner BIGINT = (SELECT MIN(Id) FROM core.Users WHERE IsSystemAdmin = 1);
DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
DECLARE @Today DATE = CAST(DATEADD(HOUR, 7, @Now) AS DATE);
DECLARE @Pipe BIGINT = (SELECT TOP 1 Id FROM crm.Pipelines WHERE CompanyId = @C ORDER BY IsDefault DESC, Id);

DECLARE @Cust TABLE (
    Seq INT IDENTITY(1,1), PartnerId BIGINT NULL, PartnerType VARCHAR(10), Name NVARCHAR(255), ShortName NVARCHAR(100),
    TaxCode VARCHAR(20), Phone VARCHAR(20), Email VARCHAR(255), Industry NVARCHAR(100), Street NVARCHAR(255), GroupCode VARCHAR(20),
    ContactName NVARCHAR(150), ContactPosition NVARCHAR(100), ContactPhone VARCHAR(20), ContactEmail VARCHAR(255), LeadPhone VARCHAR(20), DaysAgo INT);

INSERT @Cust (PartnerType, Name, ShortName, TaxCode, Phone, Email, Industry, Street, GroupCode, ContactName, ContactPosition, ContactPhone, ContactEmail, LeadPhone, DaysAgo) VALUES
 ('company',    N'Công ty Cổ phần Hưng Thịnh',      N'Hưng Thịnh',   '0101234567', '02438251111', 'info@hungthinh.vn',   N'Phân phối',     N'25 Lý Thường Kiệt, Hà Nội',      'B2B',    N'Trần Thị Bình',  N'Giám đốc mua hàng', '0912345678', 'binh.tran@hungthinh.vn',  '0912345678', 40),
 ('company',    N'Công ty TNHH Đại Việt Tech',      N'Đại Việt',     '0108765432', '02437772222', 'contact@daiviet.tech', N'Công nghệ',     N'Tòa Keangnam, Phạm Hùng, Hà Nội', 'VIP',    N'Lê Văn Cường',   N'CTO',               '0903111222', 'cuong@daiviet.tech',      '0903111222', 36),
 ('company',    N'Công ty CP Dược phẩm An Khang',   N'An Khang',     '0312345678', '02838223333', 'info@ankhang.vn',     N'Dược phẩm',     N'120 Nguyễn Trãi, Q.5, TP.HCM',    'B2B',    N'Nguyễn Thu Hà',  N'Kế toán trưởng',    '0977222333', 'ha.nguyen@ankhang.vn',    '0977222333', 29),
 ('company',    N'Công ty TNHH Xây dựng Long Phát', N'Long Phát',    '0109876543', '02436664444', 'info@longphat.vn',    N'Xây dựng',      N'88 Giải Phóng, Hà Nội',           'VIP',    N'Đặng Văn Long',  N'Giám đốc',          '0947111000', 'long.dang@longphat.vn',   '0947111000',  7),
 ('company',    N'Công ty TNHH Thép Việt Nhật',     N'Thép Việt Nhật','0201112223', '02253885555', 'sales@thepvietnhat.vn', N'Sản xuất',    N'KCN Đình Vũ, Hải Phòng',          'B2B',    N'Hồ Văn Nam',     N'Trưởng phòng mua hàng', '0915666777', 'nam.ho@thepvietnhat.vn', NULL, 25),
 ('company',    N'Chuỗi Mini Mart 24h',             N'Mini Mart 24h', NULL,        '02866667777', 'cskh@minimart24h.vn', N'Bán lẻ',        N'45 Cộng Hòa, Tân Bình, TP.HCM',   'DEALER', N'Kim Thị Oanh',   N'Quản lý chuỗi',     '0938777888', 'oanh@minimart24h.vn',     NULL, 33),
 ('individual', N'Nguyễn Hoàng Phúc',               NULL,            NULL,         '0986123456', 'phuc.nh@gmail.com',   NULL,             N'Cầu Giấy, Hà Nội',                'RETAIL', NULL, NULL, NULL, NULL, NULL, 28),
 ('company',    N'Nhà hàng Hương Quê',              N'Hương Quê',    '0107778889', '02439998888', 'huongque@gmail.com',  N'Nhà hàng',      N'12 Trần Duy Hưng, Hà Nội',        'B2B',    N'Trương Văn Sơn', N'Chủ nhà hàng',      '0904555666', NULL,                      NULL, 18);

DECLARE @Opp TABLE (
    Seq INT IDENTITY(1,1), CustSeq INT, Name NVARCHAR(255), StageOrder INT, Value DECIMAL(18,2), CloseInDays INT NULL,
    Priority TINYINT, LostReason NVARCHAR(150) NULL, LostNote NVARCHAR(500) NULL, ClosedDaysAgo INT NULL, CreatedDaysAgo INT, Description NVARCHAR(500));

INSERT @Opp (CustSeq, Name, StageOrder, Value, CloseInDays, Priority, LostReason, LostNote, ClosedDaysAgo, CreatedDaysAgo, Description) VALUES
 (1, N'Phần mềm quản lý kho 3 chi nhánh',          40, 350000000,  20, 2, NULL, NULL, NULL, 38, N'Đã gửi báo giá gói Kho + Bán hàng, chờ phản hồi'),
 (2, N'Triển khai ERP toàn công ty - 120 người dùng', 50, 480000000, 10, 3, NULL, NULL, NULL, 34, N'Đang đàm phán chiết khấu 8%'),
 (2, N'Gói bảo trì & hỗ trợ năm 2027',             60,  60000000, NULL, 1, NULL, NULL,    5, 30, N'Đã ký hợp đồng'),
 (3, N'Kế toán TT200 + hóa đơn điện tử',           30, 210000000,  30, 1, NULL, NULL, NULL, 27, N'Khảo sát quy trình kế toán 2 chi nhánh'),
 (4, N'Quản lý dự án công trình & vật tư',         20, 520000000,  45, 2, NULL, NULL, NULL,  6, N'Hẹn demo với ban giám đốc'),
 (5, N'Module mua hàng + kho nguyên vật liệu',     10, 180000000,  60, 0, NULL, NULL, NULL, 22, NULL),
 (6, N'Phần mềm bán lẻ cho 5 cửa hàng',            70,  95000000, NULL, 1, N'Giá cao', N'Đối thủ báo giá thấp hơn 20%', 12, 31, NULL),
 (8, N'CRM chăm sóc khách hàng thân thiết',        40,  40000000,  -3, 1, NULL, NULL, NULL, 16, N'Đã quá ngày dự kiến chốt, cần gọi lại'),
 (7, N'Gói phần mềm cá nhân',                      60,  15000000, NULL, 0, NULL, NULL,   20, 26, NULL),
 (1, N'Mở rộng hệ thống cho chi nhánh thứ 4',      10, 120000000,  90, 1, NULL, NULL, NULL,  3, N'Phát sinh từ dự án kho');

DECLARE @i INT = 1, @n INT, @Code VARCHAR(50), @Date DATE, @Id BIGINT;

BEGIN TRAN;

-- 1. Khách hàng
SET @n = (SELECT COUNT(*) FROM @Cust);
WHILE @i <= @n
BEGIN
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'PARTNER', @DocDate = @Today, @DocNo = @Code OUTPUT;
    INSERT md.Partners (CompanyId, Code, PartnerType, Name, ShortName, TaxCode, Phone, Email, Industry, Street, IsCustomer,
                        CustomerGroupId, OwnerUserId, Source, CreatedAt, CreatedBy)
    SELECT @C, @Code, c.PartnerType, c.Name, c.ShortName, c.TaxCode, c.Phone, c.Email, c.Industry, c.Street, 1,
           (SELECT Id FROM md.PartnerGroups WHERE CompanyId = @C AND Code = c.GroupCode), @Owner, N'Dữ liệu mẫu',
           DATEADD(DAY, -c.DaysAgo, @Now), @Owner
    FROM @Cust c WHERE c.Seq = @i;
    UPDATE @Cust SET PartnerId = SCOPE_IDENTITY() WHERE Seq = @i;
    SET @i += 1;
END

-- 2. Người liên hệ chính
INSERT md.PartnerContacts (PartnerId, FullName, Position, Phone, Email, IsPrimary, CreatedAt, CreatedBy)
SELECT PartnerId, ContactName, ContactPosition, ContactPhone, ContactEmail, 1, DATEADD(DAY, -DaysAgo, @Now), @Owner
FROM @Cust WHERE ContactName IS NOT NULL;

-- 3. Cơ hội
SET @i = 1; SET @n = (SELECT COUNT(*) FROM @Opp);
WHILE @i <= @n
BEGIN
    SELECT @Date = CAST(DATEADD(DAY, -CreatedDaysAgo, @Today) AS DATE) FROM @Opp WHERE Seq = @i;
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'OPPORTUNITY', @DocDate = @Date, @DocNo = @Code OUTPUT;

    INSERT crm.Opportunities (CompanyId, Code, Name, PartnerId, ContactId, LeadId, PipelineId, StageId, ExpectedRevenue, Probability,
                              ExpectedCloseDate, Priority, OwnerUserId, Status, LostReasonId, LostNote, ClosedAt, Description,
                              StageChangedAt, CreatedAt, CreatedBy)
    SELECT @C, @Code, o.Name, c.PartnerId,
           (SELECT TOP 1 Id FROM md.PartnerContacts WHERE PartnerId = c.PartnerId),
           (SELECT TOP 1 Id FROM crm.Leads WHERE Phone = c.LeadPhone AND UtmCampaign = 'demo-data'),
           @Pipe, s.Id, o.Value, s.Probability,
           CASE WHEN o.CloseInDays IS NULL THEN NULL ELSE DATEADD(DAY, o.CloseInDays, @Today) END,
           o.Priority, @Owner, s.StageType,
           (SELECT Id FROM crm.LostReasons WHERE CompanyId = @C AND Name = o.LostReason), o.LostNote,
           CASE WHEN o.ClosedDaysAgo IS NULL THEN NULL ELSE DATEADD(DAY, -o.ClosedDaysAgo, @Now) END,
           o.Description, DATEADD(DAY, -ISNULL(o.ClosedDaysAgo, o.CreatedDaysAgo / 2), @Now),
           DATEADD(DAY, -o.CreatedDaysAgo, @Now), @Owner
    FROM @Opp o
    JOIN @Cust c ON c.Seq = o.CustSeq
    JOIN crm.Stages s ON s.PipelineId = @Pipe AND s.SortOrder = o.StageOrder
    WHERE o.Seq = @i;
    SET @i += 1;
END

-- 4. Lead tiềm năng -> đã chuyển đổi thành khách hàng tương ứng
UPDATE l SET
    Status = 'converted',
    ConvertedPartnerId = c.PartnerId,
    ConvertedOpportunityId = (SELECT MIN(o.Id) FROM crm.Opportunities o WHERE o.LeadId = l.Id),
    ConvertedAt = DATEADD(DAY, -c.DaysAgo, @Now)
FROM crm.Leads l
JOIN @Cust c ON c.LeadPhone = l.Phone
WHERE l.UtmCampaign = 'demo-data';

COMMIT;
DECLARE @CustCount INT = (SELECT COUNT(*) FROM @Cust), @OppCount INT = (SELECT COUNT(*) FROM @Opp);
PRINT N'Đã thêm ' + CAST(@CustCount AS NVARCHAR(10)) + N' khách hàng và ' + CAST(@OppCount AS NVARCHAR(10)) + N' cơ hội mẫu.';
GO
