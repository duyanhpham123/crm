/* =====================================================================
   Nâng cấp database ĐÃ TẠO trước đợt 4 (Website, Dự án & công việc, Tài liệu, Chat nội bộ).
   DB mới tạo bằng run_all.ps1 đã có sẵn. Chạy lại nhiều lần không sao.
   Chạy:  sqlcmd -S localhost -E -d MyERP -I -f 65001 -i migrations\2026-11-24_phase4.sql
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

/* Mọi vai trò đều dùng được Chat, Tài liệu, Dự án & công việc với phạm vi "của mình" */
INSERT core.RolePermissions (RoleId, PermissionId, DataScope)
SELECT r.Id, p.Id, 'own'
FROM core.Roles r
CROSS JOIN core.Permissions p
WHERE r.Code IN ('director','sales','sales_lead','accountant','warehouse','purchaser','hr','marketing','support','employee')
  AND p.Code IN ('chat.view','chat.create','chat.edit','document.view','document.create','document.edit','project.view','project.create','project.edit')
  AND NOT EXISTS (SELECT 1 FROM core.RolePermissions x WHERE x.RoleId = r.Id AND x.PermissionId = p.Id);
GO

/* Cột Kanban mặc định cho công việc */
INSERT prj.TaskStages (CompanyId, ProjectId, Name, SortOrder, IsDone)
SELECT c.Id, NULL, v.Name, v.SortOrder, v.IsDone
FROM core.Companies c
CROSS JOIN (VALUES (N'Cần làm',10,0),(N'Đang làm',20,0),(N'Chờ duyệt',30,0),(N'Hoàn thành',40,1)) v(Name, SortOrder, IsDone)
WHERE NOT EXISTS (SELECT 1 FROM prj.TaskStages s WHERE s.CompanyId = c.Id AND s.ProjectId IS NULL);
GO
PRINT N'Đã nâng cấp database cho đợt 4.';
