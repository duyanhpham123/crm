/* =====================================================================
   MyERP - 30. DỮ LIỆU KHỞI TẠO
   - Danh mục hệ thống: tiền tệ, đơn vị tính, phương thức thanh toán
   - 17 ứng dụng + quyền + vai trò mẫu
   - 1 công ty demo, phòng ban, dãy số chứng từ
   - Hệ thống tài khoản TT200 (rút gọn các TK hay dùng), sổ nhật ký, thuế
   - Pipeline CRM, loại nghỉ phép, ca làm việc, năm tài chính
   Địa giới hành chính (34 tỉnh/thành và phường/xã) nên import từ danh mục
   chính thức của Tổng cục Thống kê, không seed tay ở đây.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRAN;

/* ---------- Danh mục hệ thống ---------- */
INSERT md.Currencies (Code, Name, Symbol, DecimalPlaces) VALUES
 ('VND', N'Việt Nam đồng', N'₫', 0),
 ('USD', N'Đô la Mỹ', N'$', 2),
 ('EUR', N'Euro', N'€', 2),
 ('CNY', N'Nhân dân tệ', N'¥', 2);

INSERT md.PaymentMethods (Code, Name) VALUES
 ('cash', N'Tiền mặt'), ('bank_transfer', N'Chuyển khoản'), ('cod', N'Thu hộ (COD)'),
 ('card', N'Thẻ'), ('ewallet', N'Ví điện tử'), ('offset', N'Bù trừ công nợ');

INSERT md.UnitsOfMeasure (CompanyId, Code, Name) VALUES
 (NULL,'CAI',N'Cái'), (NULL,'CHIEC',N'Chiếc'), (NULL,'HOP',N'Hộp'), (NULL,'THUNG',N'Thùng'),
 (NULL,'KG',N'Kg'), (NULL,'GAM',N'Gam'), (NULL,'TAN',N'Tấn'), (NULL,'M',N'Mét'),
 (NULL,'M2',N'Mét vuông'), (NULL,'M3',N'Mét khối'), (NULL,'LIT',N'Lít'), (NULL,'BO',N'Bộ'),
 (NULL,'GOI',N'Gói'), (NULL,'CHAI',N'Chai'), (NULL,'LON',N'Lon'), (NULL,'CUON',N'Cuộn'),
 (NULL,'GIO',N'Giờ'), (NULL,'NGAY',N'Ngày'), (NULL,'THANG',N'Tháng'), (NULL,'LAN',N'Lần');

/* ---------- Ứng dụng (khớp màn hình lưới) ---------- */
INSERT core.Apps (Code, Name, Icon, Color, Route, SortOrder) VALUES
 ('crm',        N'CRM',          'heart-handshake',    '#D4537E', '/crm',        10),
 ('quotation',  N'Báo giá',      'file-dollar',        '#D85A30', '/quotations', 20),
 ('order',      N'Đơn hàng',     'shopping-cart',      '#378ADD', '/orders',     30),
 ('inventory',  N'Kho',          'building-warehouse', '#BA7517', '/inventory',  40),
 ('logistics',  N'Vận chuyển',   'truck-delivery',     '#0F6E56', '/logistics',  50),
 ('purchasing', N'Mua hàng',     'basket-down',        '#639922', '/purchasing', 60),
 ('accounting', N'Kế toán',      'calculator',         '#534AB7', '/accounting', 70),
 ('hr',         N'Nhân sự',      'users',              '#7F77DD', '/hr',         80),
 ('marketing',  N'Marketing',    'speakerphone',       '#D85A30', '/marketing',  90),
 ('website',    N'Website',      'world',              '#185FA5', '/website',   100),
 ('support',    N'CSKH',         'headset',            '#1D9E75', '/support',   110),
 ('project',    N'Dự án, việc',  'checklist',          '#993556', '/projects',  120),
 ('document',   N'Tài liệu',     'folder',             '#888780', '/documents', 130),
 ('chat',       N'Chat nội bộ',  'messages',           '#378ADD', '/chat',      140),
 ('report',     N'Báo cáo',      'chart-pie',          '#0F6E56', '/reports',   150),
 ('users',      N'Người dùng',   'user-shield',        '#5F5E5A', '/users',     160),
 ('settings',   N'Cài đặt',      'settings',           '#444441', '/settings',  170);

/* Quyền chuẩn cho mỗi ứng dụng: view / create / edit / delete / approve / export */
INSERT core.Permissions (AppId, Code, Name)
SELECT a.Id, a.Code + '.' + x.Act, x.Label + N' - ' + a.Name
FROM core.Apps a
CROSS JOIN (VALUES ('view',N'Xem'),('create',N'Tạo'),('edit',N'Sửa'),
                   ('delete',N'Xóa'),('approve',N'Duyệt'),('export',N'Xuất dữ liệu')) x(Act, Label);

/* Quyền nghiệp vụ đặc thù */
INSERT core.Permissions (AppId, Code, Name)
SELECT a.Id, v.Code, v.Name
FROM (VALUES
  ('accounting','accounting.entry.post',      N'Ghi sổ bút toán'),
  ('accounting','accounting.period.close',    N'Khóa sổ kỳ kế toán'),
  ('accounting','accounting.einvoice.issue',  N'Phát hành hóa đơn điện tử'),
  ('order',     'order.price.override',       N'Sửa giá bán dưới bảng giá'),
  ('order',     'order.credit.override',      N'Bán vượt hạn mức công nợ'),
  ('inventory', 'inventory.negative.allow',   N'Xuất kho âm'),
  ('hr',        'hr.payroll.view',            N'Xem bảng lương'),
  ('users',     'users.impersonate',          N'Đăng nhập thay người dùng')
) v(AppCode, Code, Name)
JOIN core.Apps a ON a.Code = v.AppCode;

/* ---------- Công ty demo ---------- */
DECLARE @C BIGINT;
INSERT core.Companies (Code, Name, ShortName, TaxCode, Address, Phone, CurrencyCode)
VALUES ('ABC', N'Công ty TNHH ABC', N'ABC', '0100000000', N'Hà Nội', '02400000000', 'VND');
SET @C = SCOPE_IDENTITY();

INSERT core.CompanyApps (CompanyId, AppId) SELECT @C, Id FROM core.Apps;

INSERT core.Branches (CompanyId, Code, Name, IsHeadOffice) VALUES (@C, 'HO', N'Trụ sở chính', 1);
DECLARE @HO BIGINT = SCOPE_IDENTITY();

INSERT core.Departments (CompanyId, BranchId, Code, Name, SortOrder) VALUES
 (@C,@HO,'BGD', N'Ban giám đốc', 1), (@C,@HO,'KD', N'Phòng Kinh doanh', 2),
 (@C,@HO,'MKT', N'Phòng Marketing', 3), (@C,@HO,'KT', N'Phòng Kế toán', 4),
 (@C,@HO,'KHO', N'Kho vận', 5), (@C,@HO,'MH', N'Phòng Mua hàng', 6),
 (@C,@HO,'NS', N'Phòng Nhân sự', 7), (@C,@HO,'CSKH', N'Chăm sóc khách hàng', 8),
 (@C,@HO,'IT', N'Phòng IT', 9);
UPDATE core.Departments SET Path = '/' + CAST(Id AS VARCHAR(20)) + '/' WHERE CompanyId = @C;

/* ---------- Vai trò mẫu ---------- */
INSERT core.Roles (CompanyId, Code, Name, NormalizedName, IsSystem) VALUES
 (NULL, 'admin',      N'Quản trị hệ thống', N'QUẢN TRỊ HỆ THỐNG', 1),
 (@C,   'director',   N'Ban giám đốc',      N'BAN GIÁM ĐỐC', 0),
 (@C,   'sales',      N'Nhân viên kinh doanh', N'NHÂN VIÊN KINH DOANH', 0),
 (@C,   'sales_lead', N'Trưởng phòng kinh doanh', N'TRƯỞNG PHÒNG KINH DOANH', 0),
 (@C,   'accountant', N'Kế toán',           N'KẾ TOÁN', 0),
 (@C,   'warehouse',  N'Thủ kho',           N'THỦ KHO', 0),
 (@C,   'purchaser',  N'Nhân viên mua hàng', N'NHÂN VIÊN MUA HÀNG', 0),
 (@C,   'hr',         N'Nhân sự',           N'NHÂN SỰ', 0),
 (@C,   'marketing',  N'Marketing',         N'MARKETING', 0),
 (@C,   'support',    N'Chăm sóc khách hàng', N'CHĂM SÓC KHÁCH HÀNG', 0),
 (@C,   'employee',   N'Nhân viên',         N'NHÂN VIÊN', 0);

/* Hàm gán quyền: vai trò - danh sách app - danh sách hành động - phạm vi */
DECLARE @Grants TABLE (RoleCode VARCHAR(50), AppCode VARCHAR(30), Acts VARCHAR(100), Scope VARCHAR(20));
INSERT @Grants VALUES
 ('director',  '*',          'view,approve,export',            'company'),
 ('sales',     'crm',        'view,create,edit,export',        'own'),
 ('sales',     'quotation',  'view,create,edit',               'own'),
 ('sales',     'order',      'view,create,edit',               'own'),
 ('sales_lead','crm',        'view,create,edit,delete,approve,export', 'department'),
 ('sales_lead','quotation',  'view,create,edit,delete,approve,export', 'department'),
 ('sales_lead','order',      'view,create,edit,delete,approve,export', 'department'),
 ('sales_lead','report',     'view,export',                    'department'),
 ('accountant','accounting', 'view,create,edit,delete,approve,export', 'company'),
 ('accountant','order',      'view',                           'company'),
 ('accountant','purchasing', 'view',                           'company'),
 ('accountant','logistics',  'view',                           'company'),
 ('accountant','report',     'view,export',                    'company'),
 ('warehouse', 'inventory',  'view,create,edit,approve,export','company'),
 ('warehouse', 'logistics',  'view,create,edit,export',        'company'),
 ('warehouse', 'order',      'view',                           'company'),
 ('warehouse', 'purchasing', 'view',                           'company'),
 ('purchaser', 'purchasing', 'view,create,edit,export',        'company'),
 ('purchaser', 'inventory',  'view',                           'company'),
 ('hr',        'hr',         'view,create,edit,delete,approve,export', 'company'),
 ('marketing', 'marketing',  'view,create,edit,delete,export', 'company'),
 ('marketing', 'website',    'view,create,edit,delete',        'company'),
 ('marketing', 'crm',        'view',                           'company'),
 ('support',   'support',    'view,create,edit,export',        'department'),
 ('support',   'crm',        'view',                           'company'),
 ('support',   'order',      'view',                           'company'),
 ('employee',  'chat',       'view,create,edit',               'own'),
 ('employee',  'document',   'view,create,edit',               'own'),
 ('employee',  'project',    'view,create,edit',               'own');

INSERT core.RolePermissions (RoleId, PermissionId, DataScope)
SELECT DISTINCT r.Id, p.Id, g.Scope
FROM @Grants g
JOIN core.Roles r       ON r.Code = g.RoleCode AND r.CompanyId = @C
JOIN core.Apps a        ON g.AppCode = '*' OR a.Code = g.AppCode
CROSS APPLY STRING_SPLIT(g.Acts, ',') s
JOIN core.Permissions p ON p.Code = a.Code + '.' + s.value;

/* Admin: toàn quyền */
INSERT core.RolePermissions (RoleId, PermissionId, DataScope)
SELECT r.Id, p.Id, 'all' FROM core.Roles r CROSS JOIN core.Permissions p WHERE r.Code = 'admin' AND r.CompanyId IS NULL;

/* Tài khoản quản trị: KHÔNG có mật khẩu - ứng dụng bắt đặt mật khẩu ở lần chạy đầu */
INSERT core.Users (UserName, NormalizedUserName, FullName, DefaultCompanyId, IsSystemAdmin, SecurityStamp, ConcurrencyStamp)
VALUES ('admin', 'ADMIN', N'Quản trị hệ thống', @C, 1, CONVERT(VARCHAR(36), NEWID()), CONVERT(VARCHAR(36), NEWID()));
DECLARE @Admin BIGINT = SCOPE_IDENTITY();
INSERT core.UserCompanies (UserId, CompanyId, BranchId, DepartmentId, IsDefault)
SELECT @Admin, @C, @HO, Id, 1 FROM core.Departments WHERE CompanyId = @C AND Code = 'IT';
INSERT core.UserRoles (UserId, RoleId, CompanyId)
SELECT @Admin, Id, @C FROM core.Roles WHERE Code = 'admin' AND CompanyId IS NULL;

/* ---------- Dãy số chứng từ ---------- */
INSERT core.Sequences (CompanyId, Code, Prefix, DatePattern, Padding, ResetPolicy) VALUES
 (@C,'PARTNER','KH',NULL,6,'never'),      (@C,'PRODUCT','SP',NULL,6,'never'),
 (@C,'EMPLOYEE','NV',NULL,5,'never'),     (@C,'LEAD','LD','yyMM',5,'monthly'),
 (@C,'OPPORTUNITY','CH','yyMM',5,'monthly'),
 (@C,'QUOTATION','BG','yyMM',5,'monthly'),(@C,'SALES_ORDER','DH','yyMM',5,'monthly'),
 (@C,'SALES_RETURN','TH','yyMM',5,'monthly'),
 (@C,'PURCHASE_REQUEST','YCM','yyMM',4,'monthly'),(@C,'PURCHASE_ORDER','DM','yyMM',4,'monthly'),
 (@C,'STOCK_RECEIPT','PN','yyMM',5,'monthly'),(@C,'STOCK_ISSUE','PX','yyMM',5,'monthly'),
 (@C,'STOCK_TRANSFER','PCK','yyMM',4,'monthly'),(@C,'STOCK_ADJUST','PDC','yyMM',4,'monthly'),
 (@C,'INVENTORY_COUNT','KK','yyMM',3,'monthly'),
 (@C,'SHIPMENT','VD','yyMM',5,'monthly'), (@C,'COD_RECON','DS','yyMM',3,'monthly'),
 (@C,'INVOICE_OUT','HDB','yyMM',5,'monthly'),(@C,'INVOICE_IN','HDM','yyMM',5,'monthly'),
 (@C,'CASH_RECEIPT','PT','yyMM',5,'monthly'),(@C,'CASH_PAYMENT','PC','yyMM',5,'monthly'),
 (@C,'BANK_RECEIPT','BC','yyMM',5,'monthly'),(@C,'BANK_PAYMENT','BN','yyMM',5,'monthly'),
 (@C,'JOURNAL_ENTRY','BT','yyMM',5,'monthly'),
 (@C,'TICKET','TK','yyMM',5,'monthly'),   (@C,'WARRANTY','BH','yyyy',6,'yearly'),
 (@C,'PROJECT','DA','yyyy',3,'yearly'),   (@C,'TASK','CV',NULL,6,'never'),
 (@C,'CAMPAIGN','CD','yyyy',3,'yearly'),  (@C,'FIXED_ASSET','TS',NULL,5,'never');

/* ---------- Hệ thống tài khoản TT200 (các TK thường dùng) ---------- */
DECLARE @Coa TABLE (Code VARCHAR(20), Name NVARCHAR(255), ParentCode VARCHAR(20), AType VARCHAR(15), Bal VARCHAR(6), ReqPartner BIT);
INSERT @Coa VALUES
 ('111', N'Tiền mặt', NULL,'asset','debit',0),
 ('1111',N'Tiền Việt Nam','111','asset','debit',0),
 ('1112',N'Ngoại tệ','111','asset','debit',0),
 ('112', N'Tiền gửi ngân hàng', NULL,'asset','debit',0),
 ('1121',N'Tiền Việt Nam','112','asset','debit',0),
 ('1122',N'Ngoại tệ','112','asset','debit',0),
 ('131', N'Phải thu của khách hàng', NULL,'asset','both',1),
 ('133', N'Thuế GTGT được khấu trừ', NULL,'asset','debit',0),
 ('1331',N'Thuế GTGT được khấu trừ của hàng hóa, dịch vụ','133','asset','debit',0),
 ('1332',N'Thuế GTGT được khấu trừ của TSCĐ','133','asset','debit',0),
 ('138', N'Phải thu khác', NULL,'asset','debit',0),
 ('1388',N'Phải thu khác','138','asset','debit',1),
 ('141', N'Tạm ứng', NULL,'asset','debit',0),
 ('151', N'Hàng mua đang đi đường', NULL,'asset','debit',0),
 ('152', N'Nguyên liệu, vật liệu', NULL,'asset','debit',0),
 ('153', N'Công cụ, dụng cụ', NULL,'asset','debit',0),
 ('154', N'Chi phí sản xuất, kinh doanh dở dang', NULL,'asset','debit',0),
 ('155', N'Thành phẩm', NULL,'asset','debit',0),
 ('156', N'Hàng hóa', NULL,'asset','debit',0),
 ('1561',N'Giá mua hàng hóa','156','asset','debit',0),
 ('1562',N'Chi phí thu mua hàng hóa','156','asset','debit',0),
 ('157', N'Hàng gửi đi bán', NULL,'asset','debit',0),
 ('211', N'Tài sản cố định hữu hình', NULL,'asset','debit',0),
 ('213', N'Tài sản cố định vô hình', NULL,'asset','debit',0),
 ('214', N'Hao mòn tài sản cố định', NULL,'asset','credit',0),
 ('2141',N'Hao mòn TSCĐ hữu hình','214','asset','credit',0),
 ('2143',N'Hao mòn TSCĐ vô hình','214','asset','credit',0),
 ('242', N'Chi phí trả trước', NULL,'asset','debit',0),
 ('331', N'Phải trả cho người bán', NULL,'liability','both',1),
 ('333', N'Thuế và các khoản phải nộp Nhà nước', NULL,'liability','credit',0),
 ('3331',N'Thuế giá trị gia tăng phải nộp','333','liability','credit',0),
 ('33311',N'Thuế GTGT đầu ra','3331','liability','credit',0),
 ('33312',N'Thuế GTGT hàng nhập khẩu','3331','liability','credit',0),
 ('3334',N'Thuế thu nhập doanh nghiệp','333','liability','credit',0),
 ('3335',N'Thuế thu nhập cá nhân','333','liability','credit',0),
 ('3338',N'Thuế khác','333','liability','credit',0),
 ('334', N'Phải trả người lao động', NULL,'liability','credit',0),
 ('3341',N'Phải trả công nhân viên','334','liability','credit',0),
 ('335', N'Chi phí phải trả', NULL,'liability','credit',0),
 ('338', N'Phải trả, phải nộp khác', NULL,'liability','credit',0),
 ('3382',N'Kinh phí công đoàn','338','liability','credit',0),
 ('3383',N'Bảo hiểm xã hội','338','liability','credit',0),
 ('3384',N'Bảo hiểm y tế','338','liability','credit',0),
 ('3386',N'Bảo hiểm thất nghiệp','338','liability','credit',0),
 ('3387',N'Doanh thu chưa thực hiện','338','liability','credit',0),
 ('3388',N'Phải trả, phải nộp khác','338','liability','credit',1),
 ('341', N'Vay và nợ thuê tài chính', NULL,'liability','credit',1),
 ('411', N'Vốn đầu tư của chủ sở hữu', NULL,'equity','credit',0),
 ('4111',N'Vốn góp của chủ sở hữu','411','equity','credit',0),
 ('421', N'Lợi nhuận sau thuế chưa phân phối', NULL,'equity','both',0),
 ('4211',N'LNST chưa phân phối năm trước','421','equity','both',0),
 ('4212',N'LNST chưa phân phối năm nay','421','equity','both',0),
 ('511', N'Doanh thu bán hàng và cung cấp dịch vụ', NULL,'revenue','credit',0),
 ('5111',N'Doanh thu bán hàng hóa','511','revenue','credit',0),
 ('5112',N'Doanh thu bán thành phẩm','511','revenue','credit',0),
 ('5113',N'Doanh thu cung cấp dịch vụ','511','revenue','credit',0),
 ('515', N'Doanh thu hoạt động tài chính', NULL,'revenue','credit',0),
 ('521', N'Các khoản giảm trừ doanh thu', NULL,'revenue','debit',0),
 ('5211',N'Chiết khấu thương mại','521','revenue','debit',0),
 ('5212',N'Hàng bán bị trả lại','521','revenue','debit',0),
 ('5213',N'Giảm giá hàng bán','521','revenue','debit',0),
 ('632', N'Giá vốn hàng bán', NULL,'cogs','debit',0),
 ('635', N'Chi phí tài chính', NULL,'expense','debit',0),
 ('641', N'Chi phí bán hàng', NULL,'expense','debit',0),
 ('6411',N'Chi phí nhân viên','641','expense','debit',0),
 ('6414',N'Chi phí khấu hao TSCĐ','641','expense','debit',0),
 ('6417',N'Chi phí dịch vụ mua ngoài','641','expense','debit',0),
 ('6418',N'Chi phí bằng tiền khác','641','expense','debit',0),
 ('642', N'Chi phí quản lý doanh nghiệp', NULL,'expense','debit',0),
 ('6421',N'Chi phí nhân viên quản lý','642','expense','debit',0),
 ('6424',N'Chi phí khấu hao TSCĐ','642','expense','debit',0),
 ('6425',N'Thuế, phí và lệ phí','642','expense','debit',0),
 ('6427',N'Chi phí dịch vụ mua ngoài','642','expense','debit',0),
 ('6428',N'Chi phí bằng tiền khác','642','expense','debit',0),
 ('711', N'Thu nhập khác', NULL,'other_income','credit',0),
 ('811', N'Chi phí khác', NULL,'other_expense','debit',0),
 ('821', N'Chi phí thuế thu nhập doanh nghiệp', NULL,'expense','debit',0),
 ('8211',N'Chi phí thuế TNDN hiện hành','821','expense','debit',0),
 ('911', N'Xác định kết quả kinh doanh', NULL,'equity','both',0);

INSERT acc.Accounts (CompanyId, Code, Name, AccountType, NormalBalance, AccountLevel, RequiresPartner)
SELECT @C, Code, Name, AType, Bal, LEN(Code) - 2, ReqPartner FROM @Coa;

UPDATE a SET ParentId = p.Id
FROM acc.Accounts a
JOIN @Coa c ON c.Code = a.Code
JOIN acc.Accounts p ON p.CompanyId = a.CompanyId AND p.Code = c.ParentCode
WHERE a.CompanyId = @C;

UPDATE a SET IsPostable = 0
FROM acc.Accounts a
WHERE a.CompanyId = @C AND EXISTS (SELECT 1 FROM acc.Accounts c WHERE c.ParentId = a.Id);

/* Tài khoản mặc định cho hạch toán tự động */
INSERT acc.DefaultAccounts (CompanyId, MappingKey, AccountId)
SELECT @C, m.KeyName, a.Id
FROM (VALUES ('cash','1111'),('bank','1121'),('receivable','131'),('payable','331'),
             ('advance','141'),('inventory','1561'),('purchase_cost','1562'),
             ('revenue_goods','5111'),('revenue_service','5113'),('sales_discount','5211'),
             ('sales_return','5212'),('cogs','632'),('vat_in','1331'),('vat_out','33311'),
             ('salary_payable','3341'),('social_insurance','3383'),('health_insurance','3384'),
             ('unemployment_insurance','3386'),('union_fee','3382'),('pit_payable','3335'),
             ('selling_expense','6417'),('admin_expense','6428'),('shipping_expense','6417'),
             ('fx_gain','515'),('fx_loss','635'),('retained_earnings','4212'),('pnl','911')) m(KeyName, Code)
JOIN acc.Accounts a ON a.CompanyId = @C AND a.Code = m.Code;

/* Sổ nhật ký */
INSERT acc.Journals (CompanyId, Code, Name, JournalType, DefaultAccountId, SequenceCode)
SELECT @C, j.Code, j.Name, j.JType, a.Id, j.Seq
FROM (VALUES ('BH',N'Nhật ký bán hàng','sale','5111','INVOICE_OUT'),
             ('MH',N'Nhật ký mua hàng','purchase','1561','INVOICE_IN'),
             ('PT',N'Phiếu thu tiền mặt','cash','1111','CASH_RECEIPT'),
             ('PC',N'Phiếu chi tiền mặt','cash','1111','CASH_PAYMENT'),
             ('BC',N'Báo có ngân hàng','bank','1121','BANK_RECEIPT'),
             ('BN',N'Báo nợ ngân hàng','bank','1121','BANK_PAYMENT'),
             ('KHO',N'Nhật ký kho','stock','1561','JOURNAL_ENTRY'),
             ('LUONG',N'Nhật ký lương','payroll','3341','JOURNAL_ENTRY'),
             ('TH',N'Nhật ký chung','general',NULL,'JOURNAL_ENTRY')) j(Code, Name, JType, AccCode, Seq)
LEFT JOIN acc.Accounts a ON a.CompanyId = @C AND a.Code = j.AccCode;

/* Thuế GTGT */
INSERT md.Taxes (CompanyId, Code, Name, TaxScope, Rate, SaleAccountId, PurchaseAccountId)
SELECT @C, t.Code, t.Name, 'both', t.Rate,
       (SELECT Id FROM acc.Accounts WHERE CompanyId = @C AND Code = '33311'),
       (SELECT Id FROM acc.Accounts WHERE CompanyId = @C AND Code = '1331')
FROM (VALUES ('VAT10',N'Thuế GTGT 10%',10),('VAT8',N'Thuế GTGT 8% (giảm thuế)',8),
             ('VAT5',N'Thuế GTGT 5%',5),('VAT0',N'Thuế GTGT 0%',0),
             ('KCT',N'Không chịu thuế',0),('KKKNT',N'Không kê khai, nộp thuế',0)) t(Code, Name, Rate);

INSERT md.PaymentTerms (CompanyId, Code, Name, DueDays) VALUES
 (@C,'NOW',N'Thanh toán ngay',0),(@C,'NET7',N'Công nợ 7 ngày',7),(@C,'NET15',N'Công nợ 15 ngày',15),
 (@C,'NET30',N'Công nợ 30 ngày',30),(@C,'NET45',N'Công nợ 45 ngày',45),(@C,'NET60',N'Công nợ 60 ngày',60);

INSERT md.PriceLists (CompanyId, Code, Name, IsDefault) VALUES
 (@C,'RETAIL',N'Giá bán lẻ',1),(@C,'WHOLESALE',N'Giá bán buôn',0),(@C,'DEALER',N'Giá đại lý',0);

INSERT md.PartnerGroups (CompanyId, Code, Name, GroupType) VALUES
 (@C,'RETAIL',N'Khách lẻ','customer'),(@C,'B2B',N'Khách doanh nghiệp','customer'),
 (@C,'DEALER',N'Đại lý','customer'),(@C,'VIP',N'Khách VIP','customer'),
 (@C,'SUP_DOM',N'Nhà cung cấp trong nước','supplier'),(@C,'SUP_IMP',N'Nhà cung cấp nhập khẩu','supplier');

/* ---------- Kho ---------- */
INSERT inv.Warehouses (CompanyId, BranchId, Code, Name) VALUES (@C, @HO, 'KHO01', N'Kho tổng');

/* ---------- CRM ---------- */
INSERT crm.LeadSources (CompanyId, Code, Name) VALUES
 (@C,'WEBSITE',N'Website'),(@C,'FACEBOOK',N'Facebook'),(@C,'ZALO',N'Zalo'),(@C,'GOOGLE',N'Google Ads'),
 (@C,'TIKTOK',N'TikTok'),(@C,'REFERRAL',N'Giới thiệu'),(@C,'EVENT',N'Sự kiện, hội chợ'),
 (@C,'COLD_CALL',N'Gọi điện chủ động'),(@C,'OTHER',N'Khác');

INSERT crm.Pipelines (CompanyId, Name, IsDefault) VALUES (@C, N'Quy trình bán hàng', 1);
DECLARE @Pipe BIGINT = SCOPE_IDENTITY();
INSERT crm.Stages (PipelineId, Name, SortOrder, Probability, StageType) VALUES
 (@Pipe,N'Mới',10,10,'open'),(@Pipe,N'Đã liên hệ',20,20,'open'),(@Pipe,N'Khảo sát nhu cầu',30,40,'open'),
 (@Pipe,N'Đã gửi báo giá',40,60,'open'),(@Pipe,N'Đàm phán',50,80,'open'),
 (@Pipe,N'Thành công',60,100,'won'),(@Pipe,N'Thất bại',70,0,'lost');

INSERT crm.LostReasons (CompanyId, Name) VALUES
 (@C,N'Giá cao'),(@C,N'Chọn đối thủ'),(@C,N'Không có ngân sách'),
 (@C,N'Không còn nhu cầu'),(@C,N'Không liên lạc được'),(@C,N'Sản phẩm không phù hợp');

/* ---------- Nhân sự ---------- */
INSERT hr.WorkShifts (CompanyId, Code, Name, StartTime, EndTime, BreakMinutes) VALUES
 (@C,'HC',N'Hành chính','08:00','17:00',60);
INSERT hr.LeaveTypes (CompanyId, Code, Name, IsPaid, DefaultDaysPerYear) VALUES
 (@C,'ANNUAL',N'Nghỉ phép năm',1,12),(@C,'SICK',N'Nghỉ ốm',1,0),
 (@C,'MATERNITY',N'Nghỉ thai sản',1,0),(@C,'WEDDING',N'Nghỉ kết hôn',1,3),
 (@C,'FUNERAL',N'Nghỉ tang',1,3),(@C,'UNPAID',N'Nghỉ không lương',0,0);

/* ---------- CSKH ---------- */
INSERT cs.TicketCategories (CompanyId, Name) VALUES
 (@C,N'Hỗ trợ sử dụng'),(@C,N'Khiếu nại'),(@C,N'Bảo hành'),(@C,N'Đổi trả'),(@C,N'Góp ý');
INSERT cs.SlaPolicies (CompanyId, Name, Priority, FirstResponseMinutes, ResolutionMinutes) VALUES
 (@C,N'Khẩn cấp','urgent',30,240),(@C,N'Cao','high',60,480),
 (@C,N'Bình thường','normal',240,1440),(@C,N'Thấp','low',480,4320);

/* ---------- Dự án: cột Kanban mặc định ---------- */
INSERT prj.TaskStages (CompanyId, ProjectId, Name, SortOrder, IsDone) VALUES
 (@C,NULL,N'Cần làm',10,0),(@C,NULL,N'Đang làm',20,0),(@C,NULL,N'Chờ duyệt',30,0),(@C,NULL,N'Hoàn thành',40,1);

/* ---------- Năm tài chính 2026, 12 kỳ ---------- */
INSERT acc.FiscalYears (CompanyId, Code, StartDate, EndDate) VALUES (@C, '2026', '2026-01-01', '2026-12-31');
DECLARE @FY BIGINT = SCOPE_IDENTITY();
INSERT acc.FiscalPeriods (FiscalYearId, PeriodNo, StartDate, EndDate)
SELECT @FY, m, DATEFROMPARTS(2026, m, 1), EOMONTH(DATEFROMPARTS(2026, m, 1))
FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) v(m);

/* ---------- Quy tắc duyệt mẫu ---------- */
INSERT core.ApprovalRules (CompanyId, EntityName, ApprovalLevel, MinAmount, ApproverRoleId)
SELECT @C, 'sales.Quotations', 1, 100000000, Id FROM core.Roles WHERE CompanyId = @C AND Code = 'sales_lead'
UNION ALL
SELECT @C, 'sales.Quotations', 2, 500000000, Id FROM core.Roles WHERE CompanyId = @C AND Code = 'director'
UNION ALL
SELECT @C, 'pur.PurchaseOrders', 1, 50000000, Id FROM core.Roles WHERE CompanyId = @C AND Code = 'director';

INSERT core.Settings (CompanyId, SettingKey, SettingValue) VALUES
 (@C,'sales.quotation.require_approval','true'),
 (@C,'sales.order.check_credit_limit','true'),
 (@C,'inventory.cost_method','average'),
 (@C,'inventory.allow_negative','false'),
 (@C,'accounting.auto_post_invoice','false'),
 (@C,'hr.payroll.standard_days','26');

COMMIT;
PRINT N'Seed dữ liệu khởi tạo hoàn tất.';
GO
