/** Mã quyền - khớp backend/MyERP.Api/Models/Constants.cs và bảng core.Permissions */
export const PERMISSIONS = {
  CRM_VIEW: 'crm.view',
  CRM_CREATE: 'crm.create',
  CRM_EDIT: 'crm.edit',
  CRM_DELETE: 'crm.delete',
  USERS_VIEW: 'users.view',
  USERS_CREATE: 'users.create',
  USERS_EDIT: 'users.edit',
  USERS_DELETE: 'users.delete',
}

/** Cột của ma trận phân quyền - khớp Permissions.StandardActions ở backend */
export const PERMISSION_ACTIONS = [
  { action: 'view', label: 'Xem' },
  { action: 'create', label: 'Tạo' },
  { action: 'edit', label: 'Sửa' },
  { action: 'delete', label: 'Xóa' },
  { action: 'approve', label: 'Duyệt' },
  { action: 'export', label: 'Xuất' },
]

/** Phạm vi dữ liệu - khớp cột core.RolePermissions.DataScope */
export const DATA_SCOPES = [
  { value: 'own', label: 'Của tôi', hint: 'Chỉ dữ liệu do mình phụ trách / tạo' },
  { value: 'department', label: 'Phòng ban', hint: 'Dữ liệu của cả phòng ban' },
  { value: 'branch', label: 'Chi nhánh', hint: 'Dữ liệu của cả chi nhánh' },
  { value: 'company', label: 'Toàn công ty', hint: 'Mọi dữ liệu trong công ty' },
  { value: 'all', label: 'Mọi công ty', hint: 'Chỉ quản trị hệ thống cấp được', adminOnly: true },
]

/** Quy tắc mật khẩu - khớp backend/MyERP.Api/Validators/UserValidators.cs */
export const PASSWORD_HINT = 'Tối thiểu 10 ký tự, có chữ cái và chữ số.'

/** Trạng thái lead - khớp LeadStatuses ở backend */
export const LEAD_STATUSES = [
  { value: 'new', label: 'Mới' },
  { value: 'contacted', label: 'Đã liên hệ' },
  { value: 'qualified', label: 'Tiềm năng' },
  { value: 'unqualified', label: 'Không phù hợp' },
  { value: 'converted', label: 'Đã chuyển đổi' },
]

export const leadStatusLabel = (value) => LEAD_STATUSES.find((s) => s.value === value)?.label ?? value
