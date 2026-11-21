/* =====================================================================
   MyERP - 03. NHÂN SỰ (hr): hồ sơ, hợp đồng, chấm công, nghỉ phép,
   tính lương (BHXH/BHYT/BHTN, thuế TNCN), tuyển dụng.
   Đặt trước các module khác vì Vận chuyển (tài xế), Dự án... tham chiếu nhân viên.
   ===================================================================== */
CREATE SCHEMA hr;
GO

CREATE TABLE hr.Positions (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    Code         VARCHAR(20)   NOT NULL,
    Name         NVARCHAR(150) NOT NULL,     -- 'Nhân viên kinh doanh', 'Kế toán trưởng'
    DepartmentId BIGINT        NULL,
    IsActive     BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_Positions PRIMARY KEY (Id),
    CONSTRAINT FK_Positions_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Positions_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT UQ_Positions UNIQUE (CompanyId, Code)
);

CREATE TABLE hr.Employees (
    Id                BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId         BIGINT         NOT NULL,
    Code              VARCHAR(20)    NOT NULL,
    UserId            BIGINT         NULL,          -- tài khoản đăng nhập (nếu có)
    FullName          NVARCHAR(150)  NOT NULL,
    Gender            CHAR(1)        NULL,          -- M | F | O
    DateOfBirth       DATE           NULL,
    IdNumber          VARCHAR(20)    NULL,          -- CCCD: dữ liệu cá nhân nhạy cảm, mã hóa ở tầng ứng dụng
    IdIssuedDate      DATE           NULL,
    IdIssuedPlace     NVARCHAR(150)  NULL,
    Phone             VARCHAR(20)    NULL,
    PersonalEmail     VARCHAR(255)   NULL,
    WorkEmail         VARCHAR(255)   NULL,
    PermanentAddress  NVARCHAR(500)  NULL,
    CurrentAddress    NVARCHAR(500)  NULL,
    BranchId          BIGINT         NULL,
    DepartmentId      BIGINT         NULL,
    PositionId        BIGINT         NULL,
    ManagerId         BIGINT         NULL,
    HireDate          DATE           NULL,
    OfficialDate      DATE           NULL,
    TerminationDate   DATE           NULL,
    EmploymentStatus  VARCHAR(12)    NOT NULL DEFAULT 'probation',
    PersonalTaxCode   VARCHAR(20)    NULL,
    SocialInsuranceNo VARCHAR(20)    NULL,
    Dependents        TINYINT        NOT NULL DEFAULT 0,   -- người phụ thuộc (giảm trừ gia cảnh)
    BankName          NVARCHAR(150)  NULL,
    BankAccountNo     VARCHAR(30)    NULL,
    AvatarUrl         VARCHAR(500)   NULL,
    CreatedAt         DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted         BIT NOT NULL DEFAULT 0,
    RowVersion        ROWVERSION NOT NULL,
    CONSTRAINT PK_Employees PRIMARY KEY (Id),
    CONSTRAINT FK_Employees_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Employees_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Employees_Branches FOREIGN KEY (BranchId) REFERENCES core.Branches(Id),
    CONSTRAINT FK_Employees_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT FK_Employees_Positions FOREIGN KEY (PositionId) REFERENCES hr.Positions(Id),
    CONSTRAINT FK_Employees_Manager FOREIGN KEY (ManagerId) REFERENCES hr.Employees(Id),
    CONSTRAINT UQ_Employees_Company_Code UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Employees_Gender CHECK (Gender IS NULL OR Gender IN ('M','F','O')),
    CONSTRAINT CK_Employees_Status CHECK (EmploymentStatus IN ('probation','official','maternity','suspended','resigned','terminated'))
);
CREATE UNIQUE INDEX UX_Employees_User ON hr.Employees(UserId) WHERE UserId IS NOT NULL;
CREATE INDEX IX_Employees_Department ON hr.Employees(DepartmentId) WHERE IsDeleted = 0;

CREATE TABLE hr.Contracts (
    Id               BIGINT IDENTITY(1,1) NOT NULL,
    EmployeeId       BIGINT        NOT NULL,
    ContractNo       VARCHAR(30)   NOT NULL,
    ContractType     VARCHAR(15)   NOT NULL,
    StartDate        DATE          NOT NULL,
    EndDate          DATE          NULL,
    BaseSalary       DECIMAL(18,2) NOT NULL,
    InsuranceSalary  DECIMAL(18,2) NOT NULL,    -- lương đóng bảo hiểm
    Status           VARCHAR(12)   NOT NULL DEFAULT 'draft',
    SignedAt         DATE          NULL,
    AttachmentId     BIGINT        NULL,
    Note             NVARCHAR(1000) NULL,
    CreatedAt        DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_Contracts PRIMARY KEY (Id),
    CONSTRAINT FK_Contracts_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_Contracts_Attachments FOREIGN KEY (AttachmentId) REFERENCES core.Attachments(Id),
    CONSTRAINT CK_Contracts_Type CHECK (ContractType IN ('probation','fixed_term','indefinite','seasonal','service')),
    CONSTRAINT CK_Contracts_Status CHECK (Status IN ('draft','active','expired','terminated')),
    CONSTRAINT CK_Contracts_Dates CHECK (EndDate IS NULL OR EndDate >= StartDate)
);
CREATE INDEX IX_Contracts_Employee ON hr.Contracts(EmployeeId);

CREATE TABLE hr.ContractAllowances (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    ContractId  BIGINT        NOT NULL,
    Name        NVARCHAR(100) NOT NULL,         -- 'Phụ cấp ăn trưa', 'Xăng xe'
    Amount      DECIMAL(18,2) NOT NULL,
    IsTaxable   BIT           NOT NULL DEFAULT 1,
    IsInsurable BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_ContractAllowances PRIMARY KEY (Id),
    CONSTRAINT FK_ContractAllowances_Contracts FOREIGN KEY (ContractId) REFERENCES hr.Contracts(Id) ON DELETE CASCADE
);

/* ---------- Chấm công ---------- */
CREATE TABLE hr.WorkShifts (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    Code         VARCHAR(20)   NOT NULL,
    Name         NVARCHAR(100) NOT NULL,
    StartTime    TIME(0)       NOT NULL,
    EndTime      TIME(0)       NOT NULL,
    BreakMinutes INT           NOT NULL DEFAULT 60,
    WorkDayValue DECIMAL(4,2)  NOT NULL DEFAULT 1,   -- 1 ca = 1 công
    CONSTRAINT PK_WorkShifts PRIMARY KEY (Id),
    CONSTRAINT FK_WorkShifts_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_WorkShifts UNIQUE (CompanyId, Code)
);

CREATE TABLE hr.Holidays (
    Id          BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId   BIGINT        NOT NULL,
    HolidayDate DATE          NOT NULL,
    Name        NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_Holidays PRIMARY KEY (Id),
    CONSTRAINT FK_Holidays_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_Holidays UNIQUE (CompanyId, HolidayDate)
);

CREATE TABLE hr.Attendances (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    EmployeeId    BIGINT        NOT NULL,
    WorkDate      DATE          NOT NULL,
    ShiftId       BIGINT        NULL,
    CheckIn       DATETIME2(0)  NULL,
    CheckOut      DATETIME2(0)  NULL,
    WorkHours     DECIMAL(5,2)  NOT NULL DEFAULT 0,
    OvertimeHours DECIMAL(5,2)  NOT NULL DEFAULT 0,
    LateMinutes   INT           NOT NULL DEFAULT 0,
    EarlyMinutes  INT           NOT NULL DEFAULT 0,
    Source        VARCHAR(10)   NOT NULL DEFAULT 'device',
    Latitude      DECIMAL(9,6)  NULL,
    Longitude     DECIMAL(9,6)  NULL,
    Status        VARCHAR(12)   NOT NULL DEFAULT 'present',
    Note          NVARCHAR(500) NULL,
    CONSTRAINT PK_Attendances PRIMARY KEY (Id),
    CONSTRAINT FK_Attendances_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_Attendances_Shifts FOREIGN KEY (ShiftId) REFERENCES hr.WorkShifts(Id),
    CONSTRAINT UQ_Attendances UNIQUE (EmployeeId, WorkDate, ShiftId),
    CONSTRAINT CK_Attendances_Source CHECK (Source IN ('device','mobile','web','manual')),
    CONSTRAINT CK_Attendances_Status CHECK (Status IN ('present','absent','leave','holiday','business_trip')),
    CONSTRAINT CK_Attendances_Time CHECK (CheckOut IS NULL OR CheckIn IS NULL OR CheckOut >= CheckIn)
);
CREATE INDEX IX_Attendances_Date ON hr.Attendances(WorkDate);

/* ---------- Nghỉ phép ---------- */
CREATE TABLE hr.LeaveTypes (
    Id                 BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId          BIGINT        NOT NULL,
    Code               VARCHAR(20)   NOT NULL,
    Name               NVARCHAR(100) NOT NULL,   -- 'Phép năm', 'Ốm', 'Thai sản', 'Không lương'
    IsPaid             BIT           NOT NULL DEFAULT 1,
    DefaultDaysPerYear DECIMAL(5,2)  NOT NULL DEFAULT 0,
    CONSTRAINT PK_LeaveTypes PRIMARY KEY (Id),
    CONSTRAINT FK_LeaveTypes_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_LeaveTypes UNIQUE (CompanyId, Code)
);
CREATE TABLE hr.LeaveBalances (
    EmployeeId   BIGINT       NOT NULL,
    LeaveTypeId  BIGINT       NOT NULL,
    LeaveYear    SMALLINT     NOT NULL,
    EntitledDays DECIMAL(5,2) NOT NULL DEFAULT 0,
    CarriedDays  DECIMAL(5,2) NOT NULL DEFAULT 0,
    UsedDays     DECIMAL(5,2) NOT NULL DEFAULT 0,
    RemainingDays AS (EntitledDays + CarriedDays - UsedDays) PERSISTED,
    CONSTRAINT PK_LeaveBalances PRIMARY KEY (EmployeeId, LeaveTypeId, LeaveYear),
    CONSTRAINT FK_LeaveBalances_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_LeaveBalances_Types FOREIGN KEY (LeaveTypeId) REFERENCES hr.LeaveTypes(Id)
);
CREATE TABLE hr.LeaveRequests (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    EmployeeId   BIGINT        NOT NULL,
    LeaveTypeId  BIGINT        NOT NULL,
    FromDate     DATETIME2(0)  NOT NULL,
    ToDate       DATETIME2(0)  NOT NULL,
    Days         DECIMAL(5,2)  NOT NULL,
    Reason       NVARCHAR(1000) NULL,
    Status       VARCHAR(12)   NOT NULL DEFAULT 'draft',
    ApproverUserId BIGINT      NULL,
    ApprovedAt   DATETIME2(3)  NULL,
    RejectReason NVARCHAR(500) NULL,
    CreatedAt    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_LeaveRequests PRIMARY KEY (Id),
    CONSTRAINT FK_LeaveRequests_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_LeaveRequests_Types FOREIGN KEY (LeaveTypeId) REFERENCES hr.LeaveTypes(Id),
    CONSTRAINT FK_LeaveRequests_Approver FOREIGN KEY (ApproverUserId) REFERENCES core.Users(Id),
    CONSTRAINT CK_LeaveRequests_Status CHECK (Status IN ('draft','submitted','approved','rejected','cancelled')),
    CONSTRAINT CK_LeaveRequests_Dates CHECK (ToDate >= FromDate AND Days > 0)
);
CREATE INDEX IX_LeaveRequests_Employee ON hr.LeaveRequests(EmployeeId, FromDate);

/* ---------- Tính lương ---------- */
CREATE TABLE hr.PayrollPeriods (
    Id             BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId      BIGINT       NOT NULL,
    PeriodYear     SMALLINT     NOT NULL,
    PeriodMonth    TINYINT      NOT NULL,
    StandardDays   DECIMAL(5,2) NOT NULL DEFAULT 26,   -- công chuẩn
    Status         VARCHAR(12)  NOT NULL DEFAULT 'draft',
    JournalEntryId BIGINT       NULL,                   -- bút toán hạch toán lương (FK ở 10_accounting)
    ApprovedBy     BIGINT       NULL,
    ApprovedAt     DATETIME2(3) NULL,
    CreatedAt      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_PayrollPeriods PRIMARY KEY (Id),
    CONSTRAINT FK_PayrollPeriods_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT UQ_PayrollPeriods UNIQUE (CompanyId, PeriodYear, PeriodMonth),
    CONSTRAINT CK_PayrollPeriods_Month CHECK (PeriodMonth BETWEEN 1 AND 12),
    CONSTRAINT CK_PayrollPeriods_Status CHECK (Status IN ('draft','calculated','approved','paid','closed'))
);

CREATE TABLE hr.Payslips (
    Id                 BIGINT IDENTITY(1,1) NOT NULL,
    PayrollPeriodId    BIGINT        NOT NULL,
    EmployeeId         BIGINT        NOT NULL,
    ContractId         BIGINT        NULL,
    ActualDays         DECIMAL(5,2)  NOT NULL DEFAULT 0,
    PaidLeaveDays      DECIMAL(5,2)  NOT NULL DEFAULT 0,
    OvertimeHours      DECIMAL(6,2)  NOT NULL DEFAULT 0,
    BaseSalary         DECIMAL(18,2) NOT NULL DEFAULT 0,
    TotalAllowance     DECIMAL(18,2) NOT NULL DEFAULT 0,
    OvertimePay        DECIMAL(18,2) NOT NULL DEFAULT 0,
    Bonus              DECIMAL(18,2) NOT NULL DEFAULT 0,
    GrossIncome        DECIMAL(18,2) NOT NULL DEFAULT 0,
    SocialInsurance    DECIMAL(18,2) NOT NULL DEFAULT 0,   -- NLĐ 8%
    HealthInsurance    DECIMAL(18,2) NOT NULL DEFAULT 0,   -- NLĐ 1,5%
    UnemploymentInsurance DECIMAL(18,2) NOT NULL DEFAULT 0,-- NLĐ 1%
    UnionFee           DECIMAL(18,2) NOT NULL DEFAULT 0,
    TaxableIncome      DECIMAL(18,2) NOT NULL DEFAULT 0,
    PersonalIncomeTax  DECIMAL(18,2) NOT NULL DEFAULT 0,
    Advance            DECIMAL(18,2) NOT NULL DEFAULT 0,   -- tạm ứng
    OtherDeductions    DECIMAL(18,2) NOT NULL DEFAULT 0,
    NetPay             DECIMAL(18,2) NOT NULL DEFAULT 0,
    EmployerInsurance  DECIMAL(18,2) NOT NULL DEFAULT 0,   -- DN đóng (21,5%)
    Status             VARCHAR(12)   NOT NULL DEFAULT 'draft',
    PaidAt             DATETIME2(3)  NULL,
    CONSTRAINT PK_Payslips PRIMARY KEY (Id),
    CONSTRAINT FK_Payslips_Periods FOREIGN KEY (PayrollPeriodId) REFERENCES hr.PayrollPeriods(Id),
    CONSTRAINT FK_Payslips_Employees FOREIGN KEY (EmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT FK_Payslips_Contracts FOREIGN KEY (ContractId) REFERENCES hr.Contracts(Id),
    CONSTRAINT UQ_Payslips UNIQUE (PayrollPeriodId, EmployeeId),
    CONSTRAINT CK_Payslips_Status CHECK (Status IN ('draft','confirmed','paid'))
);

/* Chi tiết từng khoản trên phiếu lương - linh hoạt khi công thức lương thay đổi */
CREATE TABLE hr.PayslipLines (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    PayslipId  BIGINT        NOT NULL,
    Code       VARCHAR(30)   NOT NULL,
    Name       NVARCHAR(150) NOT NULL,
    Category   VARCHAR(12)   NOT NULL,
    Amount     DECIMAL(18,2) NOT NULL,
    SortOrder  INT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_PayslipLines PRIMARY KEY (Id),
    CONSTRAINT FK_PayslipLines_Payslips FOREIGN KEY (PayslipId) REFERENCES hr.Payslips(Id) ON DELETE CASCADE,
    CONSTRAINT CK_PayslipLines_Category CHECK (Category IN ('earning','deduction','employer','info'))
);

/* ---------- Tuyển dụng ---------- */
CREATE TABLE hr.JobOpenings (
    Id           BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId    BIGINT        NOT NULL,
    Title        NVARCHAR(200) NOT NULL,
    DepartmentId BIGINT        NULL,
    PositionId   BIGINT        NULL,
    Quantity     INT           NOT NULL DEFAULT 1,
    Description  NVARCHAR(MAX) NULL,
    SalaryFrom   DECIMAL(18,2) NULL,
    SalaryTo     DECIMAL(18,2) NULL,
    Deadline     DATE          NULL,
    Status       VARCHAR(10)   NOT NULL DEFAULT 'open',
    IsPublishedWeb BIT         NOT NULL DEFAULT 0,
    CreatedAt    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_JobOpenings PRIMARY KEY (Id),
    CONSTRAINT FK_JobOpenings_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_JobOpenings_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT FK_JobOpenings_Positions FOREIGN KEY (PositionId) REFERENCES hr.Positions(Id),
    CONSTRAINT CK_JobOpenings_Status CHECK (Status IN ('draft','open','paused','closed'))
);
CREATE TABLE hr.Candidates (
    Id            BIGINT IDENTITY(1,1) NOT NULL,
    JobOpeningId  BIGINT        NOT NULL,
    FullName      NVARCHAR(150) NOT NULL,
    Phone         VARCHAR(20)   NULL,
    Email         VARCHAR(255)  NULL,
    CvAttachmentId BIGINT       NULL,
    Source        NVARCHAR(100) NULL,
    Stage         VARCHAR(15)   NOT NULL DEFAULT 'new',
    Rating        TINYINT       NULL,
    ExpectedSalary DECIMAL(18,2) NULL,
    InterviewAt   DATETIME2(0)  NULL,
    Note          NVARCHAR(MAX) NULL,
    HiredEmployeeId BIGINT      NULL,
    CreatedAt     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    CONSTRAINT PK_Candidates PRIMARY KEY (Id),
    CONSTRAINT FK_Candidates_JobOpenings FOREIGN KEY (JobOpeningId) REFERENCES hr.JobOpenings(Id),
    CONSTRAINT FK_Candidates_Attachments FOREIGN KEY (CvAttachmentId) REFERENCES core.Attachments(Id),
    CONSTRAINT FK_Candidates_Employees FOREIGN KEY (HiredEmployeeId) REFERENCES hr.Employees(Id),
    CONSTRAINT CK_Candidates_Stage CHECK (Stage IN ('new','screening','interview','offer','hired','rejected')),
    CONSTRAINT CK_Candidates_Rating CHECK (Rating IS NULL OR Rating BETWEEN 1 AND 5)
);
GO
