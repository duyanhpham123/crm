/* =====================================================================
   MyERP - 12. DỰ ÁN & CÔNG VIỆC (prj): dự án, giao việc liên phòng ban,
   Kanban, chấm giờ (timesheet).
   ===================================================================== */
CREATE SCHEMA prj;
GO

CREATE TABLE prj.Projects (
    Id             BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId      BIGINT        NOT NULL,
    Code           VARCHAR(30)   NOT NULL,
    Name           NVARCHAR(255) NOT NULL,
    PartnerId      BIGINT        NULL,
    SalesOrderId   BIGINT        NULL,
    ManagerUserId  BIGINT        NULL,
    DepartmentId   BIGINT        NULL,
    StartDate      DATE          NULL,
    EndDate        DATE          NULL,
    Budget         DECIMAL(18,2) NOT NULL DEFAULT 0,
    Status         VARCHAR(10)   NOT NULL DEFAULT 'planning',
    ProgressPercent DECIMAL(5,2) NOT NULL DEFAULT 0,
    Description    NVARCHAR(MAX) NULL,
    CreatedAt      DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted      BIT NOT NULL DEFAULT 0,
    RowVersion     ROWVERSION NOT NULL,
    CONSTRAINT PK_Projects PRIMARY KEY (Id),
    CONSTRAINT FK_Projects_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Projects_Partners FOREIGN KEY (PartnerId) REFERENCES md.Partners(Id),
    CONSTRAINT FK_Projects_SalesOrders FOREIGN KEY (SalesOrderId) REFERENCES sales.SalesOrders(Id),
    CONSTRAINT FK_Projects_Manager FOREIGN KEY (ManagerUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Projects_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT UQ_Projects UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Projects_Status CHECK (Status IN ('planning','active','on_hold','completed','cancelled')),
    CONSTRAINT CK_Projects_Progress CHECK (ProgressPercent BETWEEN 0 AND 100)
);

CREATE TABLE prj.ProjectMembers (
    ProjectId  BIGINT       NOT NULL,
    UserId     BIGINT       NOT NULL,
    MemberRole VARCHAR(10)  NOT NULL DEFAULT 'member',
    JoinedAt   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ProjectMembers PRIMARY KEY (ProjectId, UserId),
    CONSTRAINT FK_ProjectMembers_Projects FOREIGN KEY (ProjectId) REFERENCES prj.Projects(Id) ON DELETE CASCADE,
    CONSTRAINT FK_ProjectMembers_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id),
    CONSTRAINT CK_ProjectMembers_Role CHECK (MemberRole IN ('manager','member','viewer'))
);

/* Cột Kanban: ProjectId NULL = cột mặc định cho việc không thuộc dự án */
CREATE TABLE prj.TaskStages (
    Id         BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId  BIGINT        NOT NULL,
    ProjectId  BIGINT        NULL,
    Name       NVARCHAR(100) NOT NULL,
    SortOrder  INT           NOT NULL DEFAULT 0,
    IsDone     BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_TaskStages PRIMARY KEY (Id),
    CONSTRAINT FK_TaskStages_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_TaskStages_Projects FOREIGN KEY (ProjectId) REFERENCES prj.Projects(Id)
);

CREATE TABLE prj.Tasks (
    Id              BIGINT IDENTITY(1,1) NOT NULL,
    CompanyId       BIGINT         NOT NULL,
    Code            VARCHAR(30)    NOT NULL,
    ProjectId       BIGINT         NULL,
    ParentTaskId    BIGINT         NULL,
    Title           NVARCHAR(255)  NOT NULL,
    Description     NVARCHAR(MAX)  NULL,
    StageId         BIGINT         NULL,
    Priority        VARCHAR(8)     NOT NULL DEFAULT 'normal',
    AssigneeUserId  BIGINT         NULL,
    ReporterUserId  BIGINT         NULL,
    DepartmentId    BIGINT         NULL,      -- giao cho phòng ban (VD: Kế toán xuất hóa đơn)
    EntityName      VARCHAR(100)   NULL,      -- việc phát sinh từ chứng từ nào
    EntityId        BIGINT         NULL,
    StartDate       DATE           NULL,
    DueDate         DATETIME2(0)   NULL,
    CompletedAt     DATETIME2(3)   NULL,
    EstimatedHours  DECIMAL(8,2)   NULL,
    ProgressPercent DECIMAL(5,2)   NOT NULL DEFAULT 0,
    SortOrder       INT            NOT NULL DEFAULT 0,
    CreatedAt       DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy BIGINT NULL, UpdatedAt DATETIME2(3) NULL, UpdatedBy BIGINT NULL,
    IsDeleted       BIT NOT NULL DEFAULT 0,
    RowVersion      ROWVERSION NOT NULL,
    CONSTRAINT PK_Tasks PRIMARY KEY (Id),
    CONSTRAINT FK_Tasks_Companies FOREIGN KEY (CompanyId) REFERENCES core.Companies(Id),
    CONSTRAINT FK_Tasks_Projects FOREIGN KEY (ProjectId) REFERENCES prj.Projects(Id),
    CONSTRAINT FK_Tasks_Parent FOREIGN KEY (ParentTaskId) REFERENCES prj.Tasks(Id),
    CONSTRAINT FK_Tasks_Stages FOREIGN KEY (StageId) REFERENCES prj.TaskStages(Id),
    CONSTRAINT FK_Tasks_Assignee FOREIGN KEY (AssigneeUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Tasks_Reporter FOREIGN KEY (ReporterUserId) REFERENCES core.Users(Id),
    CONSTRAINT FK_Tasks_Departments FOREIGN KEY (DepartmentId) REFERENCES core.Departments(Id),
    CONSTRAINT UQ_Tasks UNIQUE (CompanyId, Code),
    CONSTRAINT CK_Tasks_Priority CHECK (Priority IN ('low','normal','high','urgent')),
    CONSTRAINT CK_Tasks_Progress CHECK (ProgressPercent BETWEEN 0 AND 100)
);
CREATE INDEX IX_Tasks_Assignee ON prj.Tasks(AssigneeUserId, DueDate) WHERE CompletedAt IS NULL AND IsDeleted = 0;
CREATE INDEX IX_Tasks_Project ON prj.Tasks(ProjectId, StageId) WHERE IsDeleted = 0;
CREATE INDEX IX_Tasks_Entity ON prj.Tasks(EntityName, EntityId) WHERE EntityName IS NOT NULL;

CREATE TABLE prj.TaskWatchers (
    TaskId BIGINT NOT NULL,
    UserId BIGINT NOT NULL,
    CONSTRAINT PK_TaskWatchers PRIMARY KEY (TaskId, UserId),
    CONSTRAINT FK_TaskWatchers_Tasks FOREIGN KEY (TaskId) REFERENCES prj.Tasks(Id) ON DELETE CASCADE,
    CONSTRAINT FK_TaskWatchers_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id)
);

CREATE TABLE prj.TaskChecklistItems (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    TaskId    BIGINT        NOT NULL,
    Title     NVARCHAR(255) NOT NULL,
    IsDone    BIT           NOT NULL DEFAULT 0,
    SortOrder INT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_TaskChecklistItems PRIMARY KEY (Id),
    CONSTRAINT FK_TaskChecklistItems_Tasks FOREIGN KEY (TaskId) REFERENCES prj.Tasks(Id) ON DELETE CASCADE
);

CREATE TABLE prj.Timesheets (
    Id        BIGINT IDENTITY(1,1) NOT NULL,
    TaskId    BIGINT        NULL,
    ProjectId BIGINT        NULL,
    UserId    BIGINT        NOT NULL,
    WorkDate  DATE          NOT NULL,
    Hours     DECIMAL(5,2)  NOT NULL,
    Note      NVARCHAR(500) NULL,
    IsBillable BIT          NOT NULL DEFAULT 0,
    CreatedAt DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Timesheets PRIMARY KEY (Id),
    CONSTRAINT FK_Timesheets_Tasks FOREIGN KEY (TaskId) REFERENCES prj.Tasks(Id),
    CONSTRAINT FK_Timesheets_Projects FOREIGN KEY (ProjectId) REFERENCES prj.Projects(Id),
    CONSTRAINT FK_Timesheets_Users FOREIGN KEY (UserId) REFERENCES core.Users(Id),
    CONSTRAINT CK_Timesheets_Hours CHECK (Hours > 0 AND Hours <= 24)
);
CREATE INDEX IX_Timesheets_User_Date ON prj.Timesheets(UserId, WorkDate);
GO
