/* =====================================================================
   MyERP - 43. DỮ LIỆU MẪU ĐỢT 3: Cài đặt, Nhân sự, Marketing
   - Thông tin cửa hàng, phòng ban "Cửa hàng"
   - 6 nhân viên (1 thử việc mới vào, 1 đã nghỉ việc) kèm hợp đồng / lương
   - Chấm công tháng trước + tháng này (đi trễ, tăng ca ngày 11.11, nghỉ phép), đơn nghỉ phép
   - Bảng lương tháng trước đã duyệt và đã chi (thay phiếu chi lương mẫu của đợt 2)
   - 4 chiến dịch quảng cáo có số liệu theo ngày, 5 mã giảm giá (1 mã gắn với các đơn đã giảm 20.000đ)
   Chạy SAU 42_demo_phase2.sql. Chỉ nạp khi chưa có nhân viên nào.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS (SELECT 1 FROM hr.Employees) OR NOT EXISTS (SELECT 1 FROM sales.SalesOrders)
BEGIN
    PRINT N'Bỏ qua dữ liệu mẫu đợt 3 (đã có nhân viên hoặc chưa có dữ liệu bán hàng).';
    RETURN;
END

DECLARE @C BIGINT = (SELECT Id FROM core.Companies WHERE Code = 'ABC');
DECLARE @U BIGINT = (SELECT MIN(Id) FROM core.Users WHERE IsSystemAdmin = 1);
DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
DECLARE @Today DATE = CAST(DATEADD(HOUR, 7, @Now) AS DATE);
DECLARE @ThisMonth DATE = DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1);
DECLARE @LastMonth DATE = DATEADD(MONTH, -1, @ThisMonth);
DECLARE @Shift BIGINT = (SELECT MIN(Id) FROM hr.WorkShifts WHERE CompanyId = @C);
DECLARE @Annual BIGINT = (SELECT Id FROM hr.LeaveTypes WHERE CompanyId = @C AND Code = 'ANNUAL');
DECLARE @i INT, @n INT, @Code VARCHAR(30), @Id BIGINT, @D DATE;

BEGIN TRAN;

/* ---------- 1. Cài đặt: thông tin cửa hàng ---------- */
UPDATE core.Companies SET Name = N'Công ty TNHH Thời trang MyStyle', ShortName = N'MyStyle Fashion', TaxCode = '0109876543',
    Address = N'125 Nguyễn Trãi, Thanh Xuân, Hà Nội', Phone = '0901234567', Email = 'shop@mystyle.vn', Website = 'facebook.com/mystyle.vn',
    LegalRepresentative = N'Nguyễn Thu Hà'
WHERE Id = @C;
INSERT core.Settings (CompanyId, SettingKey, SettingValue, UpdatedAt, UpdatedBy)
SELECT @C, v.K, v.V, @Now, @U FROM (VALUES
 ('print.return_policy', N'Đổi size / màu trong 7 ngày, sản phẩm còn tem mác, chưa qua sử dụng. Hàng lỗi do sản xuất đổi mới miễn phí.'),
 ('print.footer', N'Cảm ơn quý khách đã tin tưởng MyStyle!')) v(K, V)
WHERE NOT EXISTS (SELECT 1 FROM core.Settings s WHERE s.CompanyId = @C AND s.SettingKey = v.K);

IF NOT EXISTS (SELECT 1 FROM core.Departments WHERE CompanyId = @C AND Code = 'CH')
    INSERT core.Departments (CompanyId, Code, Name, SortOrder) VALUES (@C, 'CH', N'Cửa hàng', 15);
DECLARE @DeptCH BIGINT = (SELECT Id FROM core.Departments WHERE CompanyId = @C AND Code = 'CH');
DECLARE @DeptKD BIGINT = (SELECT Id FROM core.Departments WHERE CompanyId = @C AND Code = 'KD');
DECLARE @DeptKHO BIGINT = (SELECT Id FROM core.Departments WHERE CompanyId = @C AND Code = 'KHO');
DECLARE @DeptMKT BIGINT = (SELECT Id FROM core.Departments WHERE CompanyId = @C AND Code = 'MKT');

/* ---------- 2. Nhân viên + hợp đồng ---------- */
DECLARE @E TABLE (Seq INT, FullName NVARCHAR(150), Gender CHAR(1), Dob DATE, Phone VARCHAR(20), Dept BIGINT, Pos VARCHAR(10), HireMonthsAgo INT, HireDay INT,
    Status VARCHAR(12), Salary DECIMAL(18,2), Allowance DECIMAL(18,2), CType VARCHAR(15), Dependents TINYINT, Bank VARCHAR(30), Id BIGINT NULL, Code VARCHAR(20) NULL);
INSERT @E VALUES
 (1, N'Trần Thị Hồng Nhung', 'F', '1992-04-12', '0912340001', @DeptCH,  'CHT',  20, 1,  'official',  10000000, 1000000, 'indefinite', 1, '0021000111001', NULL, NULL),
 (2, N'Lê Minh Châu',        'F', '1999-08-25', '0912340002', @DeptCH,  'NVBH', 14, 1,  'official',   6500000,  730000, 'fixed_term', 0, '0021000111002', NULL, NULL),
 (3, N'Phạm Đức Anh',        'M', '2000-01-30', '0912340003', @DeptCH,  'NVBH',  9, 15, 'official',   6500000,  730000, 'fixed_term', 0, '0021000111003', NULL, NULL),
 (4, N'Nguyễn Thảo Vy',      'F', '1998-11-05', '0912340004', @DeptKD,  'NVOL', 11, 1,  'official',   7500000,  730000, 'fixed_term', 0, '0021000111004', NULL, NULL),
 (5, N'Hoàng Văn Tùng',      'M', '2002-06-18', '0912340005', @DeptKHO, 'NVK',   0, 10, 'probation',  5800000,  730000, 'probation',  0, NULL,            NULL, NULL),
 (6, N'Vũ Thanh Mai',        'F', '1997-03-09', '0912340006', @DeptMKT, 'MKT',  12, 1,  'resigned',   8000000,  730000, 'fixed_term', 0, NULL,            NULL, NULL);

SET @i = 1;
WHILE @i <= 6
BEGIN
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'EMPLOYEE', @DocDate = @Today, @DocNo = @Code OUTPUT;
    INSERT hr.Employees (CompanyId, Code, FullName, Gender, DateOfBirth, Phone, DepartmentId, PositionId, HireDate, TerminationDate,
        EmploymentStatus, Dependents, BankName, BankAccountNo, CreatedAt, CreatedBy)
    SELECT @C, @Code, FullName, Gender, Dob, Phone, Dept, (SELECT Id FROM hr.Positions WHERE CompanyId = @C AND Code = e.Pos),
           CASE WHEN HireMonthsAgo = 0 THEN DATEFROMPARTS(YEAR(@ThisMonth), MONTH(@ThisMonth), HireDay)
                ELSE DATEADD(DAY, HireDay - 1, DATEADD(MONTH, -HireMonthsAgo, @ThisMonth)) END,
           CASE WHEN Status = 'resigned' THEN DATEADD(DAY, -1, @LastMonth) END,
           Status, Dependents, CASE WHEN Bank IS NOT NULL THEN N'Vietcombank' END, Bank, @Now, @U
    FROM @E e WHERE Seq = @i;
    SET @Id = SCOPE_IDENTITY();
    UPDATE @E SET Id = @Id, Code = @Code WHERE Seq = @i;
    INSERT hr.Contracts (EmployeeId, ContractNo, ContractType, StartDate, EndDate, BaseSalary, InsuranceSalary, Status, CreatedAt, CreatedBy)
    SELECT @Id, 'HD-' + @Code + '-01', CType, (SELECT HireDate FROM hr.Employees WHERE Id = @Id),
           CASE WHEN Status = 'resigned' THEN DATEADD(DAY, -1, @LastMonth) END, Salary, Salary,
           CASE WHEN Status = 'resigned' THEN 'expired' ELSE 'active' END, @Now, @U
    FROM @E WHERE Seq = @i;
    INSERT hr.ContractAllowances (ContractId, Name, Amount, IsTaxable)
    SELECT SCOPE_IDENTITY(), N'Phụ cấp ăn trưa, xăng xe', Allowance, 0 FROM @E WHERE Seq = @i;
    SET @i += 1;
END

/* ---------- 3. Chấm công tháng trước + tháng này (tới hôm qua) ---------- */
CREATE TABLE #A (EmployeeId BIGINT, Seq INT, WorkDate DATE, Status VARCHAR(12), Hours DECIMAL(5,2), OT DECIMAL(5,2), Late INT, Note NVARCHAR(200));
;WITH days AS (
    SELECT @LastMonth AS D UNION ALL SELECT DATEADD(DAY, 1, D) FROM days WHERE D < DATEADD(DAY, -1, @Today))
INSERT #A (EmployeeId, Seq, WorkDate, Status, Hours, OT, Late, Note)
SELECT e.Id, e.Seq, d.D, 'present', 8,
       CASE WHEN DAY(d.D) = 11 AND MONTH(d.D) = 11 THEN 3 WHEN e.Seq = 1 AND DATEPART(WEEKDAY, d.D) = 7 THEN 2 ELSE 0 END,
       CASE WHEN e.Seq = 3 AND ABS(CHECKSUM(DAY(d.D) * 31 + MONTH(d.D))) % 5 = 0 THEN 10 + ABS(CHECKSUM(DAY(d.D))) % 15 ELSE 0 END,
       CASE WHEN DAY(d.D) = 11 AND MONTH(d.D) = 11 THEN N'Tăng ca sale 11.11' END
FROM days d
JOIN @E e ON e.Status IN ('official', 'probation')
JOIN hr.Employees x ON x.Id = e.Id
WHERE DATEPART(WEEKDAY, d.D) <> 1 AND d.D >= x.HireDate      -- bỏ Chủ nhật (DATEFIRST mặc định 7)
OPTION (MAXRECURSION 100);

-- Nghỉ không phép 1 ngày, nghỉ nửa ngày
UPDATE #A SET Status = 'absent', Hours = 0, OT = 0, Late = 0, Note = N'Nghỉ không báo trước' WHERE Seq = 2 AND WorkDate = DATEADD(DAY, 13, @LastMonth);
UPDATE #A SET Hours = 4, Note = N'Xin về sớm (nửa ngày)' WHERE Seq = 4 AND WorkDate = DATEADD(DAY, 8, @ThisMonth) AND WorkDate < @Today;

-- Đơn nghỉ phép: 2 đã duyệt (chấm công "nghỉ phép"), 1 chờ duyệt, 1 bị từ chối
DECLARE @L TABLE (Seq INT, FromD DATE, ToD DATE, Days DECIMAL(5,2), Status VARCHAR(12), Reason NVARCHAR(200), Reject NVARCHAR(200));
INSERT @L VALUES
 (2, DATEADD(DAY, 19, @LastMonth), DATEADD(DAY, 20, @LastMonth), 0, 'approved', N'Về quê dự đám cưới', NULL),
 (1, DATEADD(DAY, 5, @ThisMonth), DATEADD(DAY, 5, @ThisMonth), 0, 'approved', N'Đi khám sức khỏe', NULL),
 (4, DATEADD(DAY, 4, @Today), DATEADD(DAY, 5, @Today), 0, 'submitted', N'Việc gia đình', NULL),
 (3, DATEADD(DAY, 10, @ThisMonth), DATEADD(DAY, 10, @ThisMonth), 0, 'rejected', N'Đi chơi', N'Trùng ngày sale 11.11, cửa hàng cần đủ người');
-- Số ngày nghỉ = số ngày không phải Chủ nhật
UPDATE l SET Days = (SELECT COUNT(*) FROM (SELECT TOP (DATEDIFF(DAY, l.FromD, l.ToD) + 1) DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, l.FromD) AS D FROM sys.all_objects) x
                  WHERE DATEPART(WEEKDAY, x.D) <> 1) FROM @L l;

INSERT hr.LeaveRequests (EmployeeId, LeaveTypeId, FromDate, ToDate, Days, Reason, Status, ApproverUserId, ApprovedAt, RejectReason, CreatedAt, CreatedBy)
SELECT e.Id, @Annual, CAST(l.FromD AS DATETIME2(0)), DATEADD(MINUTE, 1439, CAST(l.ToD AS DATETIME2(0))), l.Days, l.Reason, l.Status,
       CASE WHEN l.Status <> 'submitted' THEN @U END, CASE WHEN l.Status <> 'submitted' THEN DATEADD(DAY, -3, CAST(l.FromD AS DATETIME2)) END,
       l.Reject, DATEADD(DAY, -5, CAST(l.FromD AS DATETIME2)), @U
FROM @L l JOIN @E e ON e.Seq = l.Seq WHERE l.Days > 0;

UPDATE a SET Status = 'leave', Hours = 0, OT = 0, Late = 0, Note = N'Nghỉ phép năm'
FROM #A a JOIN @L l ON l.Seq = a.Seq AND l.Status = 'approved' AND a.WorkDate BETWEEN l.FromD AND l.ToD;

INSERT hr.LeaveBalances (EmployeeId, LeaveTypeId, LeaveYear, EntitledDays, CarriedDays, UsedDays)
SELECT e.Id, @Annual, YEAR(@Today), 12, 0, ISNULL((SELECT SUM(l.Days) FROM @L l WHERE l.Seq = e.Seq AND l.Status = 'approved' AND YEAR(l.FromD) = YEAR(@Today)), 0)
FROM @E e WHERE e.Status IN ('official', 'probation');

INSERT hr.Attendances (EmployeeId, WorkDate, ShiftId, CheckIn, CheckOut, WorkHours, OvertimeHours, LateMinutes, EarlyMinutes, Source, Status, Note)
SELECT EmployeeId, WorkDate, @Shift,
       CASE WHEN Status = 'present' THEN DATEADD(MINUTE, 480 + Late - (ABS(CHECKSUM(EmployeeId * 7 + DAY(WorkDate))) % 10) * CASE WHEN Late > 0 THEN 0 ELSE 1 END, CAST(WorkDate AS DATETIME2(0))) END,
       CASE WHEN Status = 'present' THEN DATEADD(MINUTE, CASE WHEN Hours = 4 THEN 720 ELSE 1020 END + CAST(OT * 60 AS INT), CAST(WorkDate AS DATETIME2(0))) END,
       Hours, OT, Late, 0, CASE WHEN Status = 'present' THEN 'web' ELSE 'manual' END, Status, Note
FROM #A;

/* ---------- 4. Bảng lương tháng trước: đã duyệt, đã chi ---------- */
INSERT hr.PayrollPeriods (CompanyId, PeriodYear, PeriodMonth, StandardDays, Status, ApprovedBy, ApprovedAt, CreatedAt, CreatedBy)
VALUES (@C, YEAR(@LastMonth), MONTH(@LastMonth), 26, 'paid', @U, DATEADD(DAY, 2, CAST(@ThisMonth AS DATETIME2)), CAST(@ThisMonth AS DATETIME2), @U);
DECLARE @Period BIGINT = SCOPE_IDENTITY();

-- Cùng công thức với PayrollRules / Payslip.Calculate ở backend
;WITH src AS (
    SELECT e.Id AS EmployeeId, c.Id AS ContractId, c.BaseSalary AS Salary, c.InsuranceSalary AS InsSalary,
           ISNULL((SELECT SUM(Amount) FROM hr.ContractAllowances WHERE ContractId = c.Id), 0) AS Allowance, x.Dependents,
           ISNULL((SELECT SUM(CASE WHEN a.Status = 'present' THEN CASE WHEN a.Hours >= 7 THEN 1 WHEN a.Hours > 0 THEN 0.5 ELSE 1 END
                                   WHEN a.Status IN ('holiday', 'business_trip') THEN 1 ELSE 0 END)
                   FROM #A a WHERE a.EmployeeId = e.Id AND a.WorkDate >= @LastMonth AND a.WorkDate < @ThisMonth), 0) AS Actual,
           ISNULL((SELECT COUNT(*) FROM #A a WHERE a.EmployeeId = e.Id AND a.Status = 'leave' AND a.WorkDate >= @LastMonth AND a.WorkDate < @ThisMonth), 0) AS PaidLeave,
           ISNULL((SELECT SUM(a.OT) FROM #A a WHERE a.EmployeeId = e.Id AND a.WorkDate >= @LastMonth AND a.WorkDate < @ThisMonth), 0) AS OT
    FROM @E e JOIN hr.Employees x ON x.Id = e.Id JOIN hr.Contracts c ON c.EmployeeId = e.Id AND c.Status = 'active'
    WHERE x.HireDate < @ThisMonth),
calc AS (
    SELECT *, CASE WHEN Actual + PaidLeave > 26 THEN 26 ELSE Actual + PaidLeave END / 26.0 AS Ratio FROM src),
pay AS (
    SELECT *, ROUND(Salary * Ratio, 0) AS BasePay, ROUND(Allowance * Ratio, 0) AS AllowPay, ROUND(OT * Salary / 26 / 8 * 1.5, 0) AS OtPay,
           ROUND(InsSalary * 0.08, 0) AS Si, ROUND(InsSalary * 0.015, 0) AS Hi, ROUND(InsSalary * 0.01, 0) AS Ui, ROUND(InsSalary * 0.215, 0) AS Er
    FROM calc),
tx AS (
    SELECT *, BasePay + AllowPay + OtPay AS Gross,
           CASE WHEN BasePay + AllowPay + OtPay - AllowPay - ROUND(OtPay / 3, 0) - (Si + Hi + Ui) - 15500000 - 6200000 * Dependents < 0 THEN 0
                ELSE BasePay + AllowPay + OtPay - AllowPay - ROUND(OtPay / 3, 0) - (Si + Hi + Ui) - 15500000 - 6200000 * Dependents END AS Taxable
    FROM pay)
INSERT hr.Payslips (PayrollPeriodId, EmployeeId, ContractId, ActualDays, PaidLeaveDays, OvertimeHours, BaseSalary, TotalAllowance, OvertimePay, Bonus,
    GrossIncome, SocialInsurance, HealthInsurance, UnemploymentInsurance, UnionFee, TaxableIncome, PersonalIncomeTax, Advance, OtherDeductions, NetPay,
    EmployerInsurance, Status, PaidAt)
SELECT @Period, EmployeeId, ContractId, Actual, PaidLeave, OT, BasePay, AllowPay, OtPay, 0, Gross, Si, Hi, Ui, 0, Taxable, t.Pit, 0, 0,
       Gross - (Si + Hi + Ui) - t.Pit, Er, 'paid', DATEADD(DAY, 4, CAST(@ThisMonth AS DATETIME2))
FROM tx
CROSS APPLY (SELECT ROUND(
      (CASE WHEN Taxable > 0 THEN (CASE WHEN Taxable < 5000000 THEN Taxable ELSE 5000000 END) * 0.05 ELSE 0 END)
    + (CASE WHEN Taxable > 5000000 THEN (CASE WHEN Taxable < 10000000 THEN Taxable ELSE 10000000 END - 5000000) * 0.10 ELSE 0 END)
    + (CASE WHEN Taxable > 10000000 THEN (CASE WHEN Taxable < 18000000 THEN Taxable ELSE 18000000 END - 10000000) * 0.15 ELSE 0 END)
    + (CASE WHEN Taxable > 18000000 THEN (CASE WHEN Taxable < 32000000 THEN Taxable ELSE 32000000 END - 18000000) * 0.20 ELSE 0 END)
    + (CASE WHEN Taxable > 32000000 THEN (Taxable - 32000000) * 0.25 ELSE 0 END), 0) AS Pit) t;

-- Thay 2 phiếu chi lương "ước tính" của dữ liệu mẫu đợt 2 bằng phiếu chi theo bảng lương thật
DECLARE @PayDate DATE = DATEADD(DAY, 4, @ThisMonth);
DECLARE @Net DECIMAL(18,2) = (SELECT SUM(NetPay) FROM hr.Payslips WHERE PayrollPeriodId = @Period);
DECLARE @Cnt INT = (SELECT COUNT(*) FROM hr.Payslips WHERE PayrollPeriodId = @Period);
UPDATE acc.Payments SET Reason = N'Lương tháng ' + CAST(MONTH(DATEADD(MONTH, -1, @LastMonth)) AS NVARCHAR) + N' (trước khi dùng phần mềm)'
WHERE CompanyId = @C AND Category = 'salary' AND PaymentDate < @ThisMonth AND Reason LIKE N'Lương tháng%nhân viên bán hàng)';
DELETE FROM acc.Payments WHERE CompanyId = @C AND Category = 'salary' AND PaymentDate >= @ThisMonth AND Reason LIKE N'Lương tháng%nhân viên bán hàng)';
IF @PayDate <= @Today AND @Net > 0
BEGIN
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'BANK_PAYMENT', @DocDate = @PayDate, @DocNo = @Code OUTPUT;
    INSERT acc.Payments (CompanyId, DocNo, PaymentType, PaymentMethodCode, PaymentDate, Amount, BankAccountId, Reason, PersonName, Status, Category, CreatedAt, CreatedBy)
    VALUES (@C, @Code, 'payment', 'bank_transfer', @PayDate, @Net, (SELECT MIN(Id) FROM acc.BankAccounts WHERE CompanyId = @C),
            N'Chi lương tháng ' + CAST(MONTH(@LastMonth) AS NVARCHAR) + '/' + CAST(YEAR(@LastMonth) AS NVARCHAR) + N' (' + CAST(@Cnt AS NVARCHAR) + N' nhân viên)',
            N'Nhân viên', 'posted', 'salary', CAST(@PayDate AS DATETIME2), @U);
END

/* ---------- 5. Marketing: chiến dịch + số liệu theo ngày ---------- */
DECLARE @Cp TABLE (Seq INT, Name NVARCHAR(200), Channel VARCHAR(12), StartD DATE, EndD DATE NULL, Budget DECIMAL(18,2), Target INT NULL, Status VARCHAR(10),
    DailySpend DECIMAL(18,2), Descr NVARCHAR(500), Id BIGINT NULL);
INSERT @Cp (Seq, Name, Channel, StartD, EndD, Budget, Target, Status, DailySpend, Descr) VALUES
 (1, N'Sale 11.11 - Facebook Ads', 'facebook', DATEADD(DAY, -25, @Today), DATEADD(DAY, -5, @Today), 8000000, 120, 'completed', 350000, N'Chạy quảng cáo bài đăng giảm giá, mã GIAM20K'),
 (2, N'TikTok Thu Đông 2026', 'tiktok', DATEADD(DAY, -30, @Today), NULL, 12000000, 200, 'running', 300000, N'Video thử đồ, livestream tối thứ 6'),
 (3, N'Google tìm kiếm thương hiệu', 'google', DATEADD(DAY, -45, @Today), NULL, 3000000, 40, 'running', 60000, N'Từ khóa: mystyle, áo thun basic, giày sneaker trắng'),
 (4, N'Black Friday 2026', 'facebook', DATEADD(DAY, 6, @Today), DATEADD(DAY, 9, @Today), 10000000, 150, 'draft', 0, N'Giảm 20% toàn bộ, tối đa 200k');

SET @i = 1;
WHILE @i <= 4
BEGIN
    SELECT @D = StartD FROM @Cp WHERE Seq = @i;
    EXEC core.usp_NextDocNo @CompanyId = @C, @Code = 'CAMPAIGN', @DocDate = @D, @DocNo = @Code OUTPUT;
    INSERT mkt.Campaigns (CompanyId, Code, Name, Channel, StartDate, EndDate, Budget, ActualCost, TargetLeads, Status, OwnerUserId, Description, CreatedAt, CreatedBy)
    SELECT @C, @Code, Name, Channel, StartD, EndD, Budget, 0, Target, Status, @U, Descr, DATEADD(DAY, -1, CAST(StartD AS DATETIME2)), @U FROM @Cp WHERE Seq = @i;
    UPDATE @Cp SET Id = SCOPE_IDENTITY() WHERE Seq = @i;
    SET @i += 1;
END

;WITH days AS (SELECT DATEADD(DAY, -45, @Today) AS D UNION ALL SELECT DATEADD(DAY, 1, D) FROM days WHERE D < DATEADD(DAY, -1, @Today))
INSERT mkt.CampaignDailyStats (CampaignId, StatDate, Impressions, Clicks, Spend, Leads)
SELECT c.Id, d.D,
       CAST(c.DailySpend / 1000 * (35 + ABS(CHECKSUM(c.Seq * 97 + DAY(d.D))) % 30) AS BIGINT),
       CAST(c.DailySpend / 1000 * (35 + ABS(CHECKSUM(c.Seq * 97 + DAY(d.D))) % 30) * (1.2 + (ABS(CHECKSUM(DAY(d.D) * 13)) % 15) / 10.0) / 100 AS BIGINT),
       ROUND(c.DailySpend * (0.8 + (ABS(CHECKSUM(c.Seq * 31 + DAY(d.D))) % 40) / 100.0), -3),
       ABS(CHECKSUM(c.Seq * 7 + DAY(d.D) * 5 + MONTH(d.D))) % CASE c.Channel WHEN 'google' THEN 3 ELSE 9 END
FROM days d JOIN @Cp c ON c.DailySpend > 0 AND d.D >= c.StartD AND (c.EndD IS NULL OR d.D <= c.EndD)
OPTION (MAXRECURSION 100);
UPDATE c SET ActualCost = ISNULL((SELECT SUM(Spend) FROM mkt.CampaignDailyStats s WHERE s.CampaignId = c.Id), 0)
FROM mkt.Campaigns c WHERE c.CompanyId = @C;

/* ---------- 6. Mã giảm giá (giờ Việt Nam) ---------- */
DECLARE @LocalNow DATETIME2(0) = DATEADD(HOUR, 7, @Now);
INSERT sales.Promotions (CompanyId, Code, Name, PromotionType, Value, MaxDiscount, MinOrderAmount, StartAt, EndAt, UsageLimit, UsedCount, Channels, CampaignId, IsActive, CreatedAt, CreatedBy)
SELECT @C, v.Code, v.Name, v.PType, v.Value, v.MaxD, v.MinO, v.StartAt, v.EndAt, v.Lim, 0, v.Chs, (SELECT Id FROM @Cp WHERE Seq = v.Cp), 1, @Now, @U
FROM (VALUES
 ('GIAM20K',      N'Giảm 20.000đ đơn từ 200k',          'fixed',     20000, NULL,   200000, DATEADD(DAY, -60, @LocalNow), DATEADD(DAY, 40, @LocalNow), NULL, NULL, 1),
 ('TIKTOK50K',    N'Giảm 50k cho đơn TikTok từ 500k',   'fixed',     50000, NULL,   500000, DATEADD(DAY, -30, @LocalNow), DATEADD(DAY, 30, @LocalNow), 300, 'tiktok', 2),
 ('FREESHIP300',  N'Miễn phí ship đơn online từ 300k',  'free_ship', 0,     NULL,   300000, DATEADD(DAY, -20, @LocalNow), DATEADD(DAY, 60, @LocalNow), NULL, 'website,facebook,zalo', NULL),
 ('KHMOI10',      N'Khách mới giảm 10%',                'percent',   10,    50000,  0,      DATEADD(DAY, -10, @LocalNow), DATEADD(DAY, 80, @LocalNow), 100, NULL, NULL),
 ('BLACKFRIDAY',  N'Black Friday giảm 20%',             'percent',   20,    200000, 0,      DATEADD(DAY, 6, CAST(@Today AS DATETIME2(0))), DATEADD(SECOND, -1, DATEADD(DAY, 10, CAST(@Today AS DATETIME2(0)))), 500, NULL, 4)
) v(Code, Name, PType, Value, MaxD, MinO, StartAt, EndAt, Lim, Chs, Cp);

-- Các đơn đã giảm 20.000đ trong dữ liệu mẫu -> coi như dùng mã GIAM20K (doanh thu tính cho chiến dịch Sale 11.11)
DECLARE @G20 BIGINT = (SELECT Id FROM sales.Promotions WHERE CompanyId = @C AND Code = 'GIAM20K');
INSERT sales.OrderPromotions (SalesOrderId, PromotionId, DiscountAmount)
SELECT o.Id, @G20, 20000 FROM sales.SalesOrders o WHERE o.CompanyId = @C AND o.DiscountAmount = 20000 AND o.SubTotal >= 200000;
UPDATE sales.Promotions SET UsedCount = (SELECT COUNT(*) FROM sales.OrderPromotions op JOIN sales.SalesOrders o ON o.Id = op.SalesOrderId
    WHERE op.PromotionId = @G20 AND o.Status IN ('confirmed', 'completed')) WHERE Id = @G20;

COMMIT;
DROP TABLE #A;

DECLARE @Emp INT = (SELECT COUNT(*) FROM hr.Employees), @Att INT = (SELECT COUNT(*) FROM hr.Attendances), @Camp INT = (SELECT COUNT(*) FROM mkt.Campaigns),
        @Promo INT = (SELECT COUNT(*) FROM sales.Promotions);
PRINT N'Đã thêm ' + CAST(@Emp AS NVARCHAR) + N' nhân viên, ' + CAST(@Att AS NVARCHAR) + N' ngày công, 1 bảng lương, '
    + CAST(@Camp AS NVARCHAR) + N' chiến dịch, ' + CAST(@Promo AS NVARCHAR) + N' mã giảm giá.';
GO
