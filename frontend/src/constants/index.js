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

// ===================== Bán lẻ: Kho, Đơn hàng, Mua hàng, Báo cáo =====================

/** Mã quyền bán lẻ - khớp Permissions.Inventory / Orders / Purchasing / Reports ở backend */
export const RETAIL_PERMISSIONS = {
  INVENTORY_VIEW: 'inventory.view',
  INVENTORY_CREATE: 'inventory.create',
  INVENTORY_EDIT: 'inventory.edit',
  ORDER_VIEW: 'order.view',
  ORDER_CREATE: 'order.create',
  ORDER_EDIT: 'order.edit',
  PURCHASING_VIEW: 'purchasing.view',
  PURCHASING_CREATE: 'purchasing.create',
  PURCHASING_EDIT: 'purchasing.edit',
  REPORT_VIEW: 'report.view',
}

/** Đối tượng của mẫu sản phẩm - khớp CK_ProductModels_Gender */
export const GENDERS = [
  { value: 'unisex', label: 'Unisex' },
  { value: 'men', label: 'Nam' },
  { value: 'women', label: 'Nữ' },
  { value: 'kids', label: 'Trẻ em' },
]
export const genderLabel = (v) => GENDERS.find((g) => g.value === v)?.label ?? ''

/** Bộ size gợi ý theo loại hàng: bấm 1 nút là thêm cả bộ */
export const SIZE_PRESETS = [
  { label: 'Áo S–XL', sizes: ['S', 'M', 'L', 'XL'] },
  { label: 'Áo S–XXL', sizes: ['S', 'M', 'L', 'XL', 'XXL'] },
  { label: 'Quần 28–34', sizes: ['28', '29', '30', '31', '32', '34'] },
  { label: 'Giày nữ 35–39', sizes: ['35', '36', '37', '38', '39'] },
  { label: 'Giày nam 39–43', sizes: ['39', '40', '41', '42', '43'] },
  { label: 'Free size', sizes: ['Free size'] },
]

/** Trạng thái đơn bán - khớp OrderStatuses */
export const ORDER_STATUSES = [
  { value: 'draft', label: 'Nháp', css: 'draft' },
  { value: 'confirmed', label: 'Đã xác nhận', css: 'confirmed' },
  { value: 'completed', label: 'Hoàn thành', css: 'completed' },
  { value: 'cancelled', label: 'Đã hủy', css: 'cancelled' },
]
export const orderStatus = (v) => ORDER_STATUSES.find((s) => s.value === v) ?? { value: v, label: v, css: '' }

export const PAYMENT_STATUSES = { unpaid: 'Chưa thanh toán', partial: 'Thanh toán một phần', paid: 'Đã thanh toán' }

/** Trạng thái đơn nhập - khớp PurchaseStatuses */
export const PURCHASE_STATUSES = [
  { value: 'draft', label: 'Nháp', css: 'draft' },
  { value: 'confirmed', label: 'Chờ hàng về', css: 'confirmed' },
  { value: 'completed', label: 'Đã nhận hàng', css: 'completed' },
  { value: 'cancelled', label: 'Đã hủy', css: 'cancelled' },
]
export const purchaseStatus = (v) => PURCHASE_STATUSES.find((s) => s.value === v) ?? { value: v, label: v, css: '' }

/** Loại phiếu kho và lý do - khớp InventoryService.CreateDocumentAsync */
export const STOCK_DOC_TYPES = [
  { value: 'receipt', label: 'Phiếu nhập', icon: 'arrow-down-to-arc', css: 'completed' },
  { value: 'issue', label: 'Phiếu xuất', icon: 'arrow-up-from-arc', css: 'confirmed' },
  { value: 'adjustment', label: 'Kiểm kê / điều chỉnh', icon: 'adjustments', css: 'draft' },
]
export const stockDocType = (v) => STOCK_DOC_TYPES.find((t) => t.value === v) ?? { value: v, label: v, css: '' }

export const STOCK_REASONS = {
  purchase: 'Nhập mua hàng',
  sale_return: 'Khách trả hàng',
  opening: 'Tồn đầu kỳ',
  sale: 'Xuất bán',
  internal_use: 'Dùng nội bộ',
  scrap: 'Hàng hỏng, hủy',
  purchase_return: 'Trả nhà cung cấp',
  count: 'Kiểm kê',
  other: 'Khác',
}
/** Lý do được chọn khi tạo phiếu thủ công (phiếu bán / mua do hệ thống tự tạo) */
export const MANUAL_REASONS = {
  receipt: ['opening', 'sale_return', 'other'],
  issue: ['internal_use', 'scrap', 'purchase_return', 'other'],
  adjustment: ['count', 'other'],
}

// ===================== Đợt 2: Báo giá, Vận chuyển, Kế toán, CSKH =====================

export const PHASE2_PERMISSIONS = {
  QUOTATION_VIEW: 'quotation.view',
  QUOTATION_CREATE: 'quotation.create',
  QUOTATION_EDIT: 'quotation.edit',
  LOGISTICS_VIEW: 'logistics.view',
  LOGISTICS_CREATE: 'logistics.create',
  LOGISTICS_EDIT: 'logistics.edit',
  ACCOUNTING_VIEW: 'accounting.view',
  ACCOUNTING_CREATE: 'accounting.create',
  ACCOUNTING_EDIT: 'accounting.edit',
  SUPPORT_VIEW: 'support.view',
  SUPPORT_CREATE: 'support.create',
  SUPPORT_EDIT: 'support.edit',
}

export const QUOTATION_STATUSES = [
  { value: 'draft', label: 'Nháp', css: 'draft' },
  { value: 'sent', label: 'Đã gửi khách', css: 'confirmed' },
  { value: 'accepted', label: 'Khách đồng ý', css: 'completed' },
  { value: 'rejected', label: 'Khách từ chối', css: 'cancelled' },
  { value: 'expired', label: 'Hết hạn', css: 'warn' },
  { value: 'cancelled', label: 'Đã hủy', css: 'cancelled' },
]
export const quotationStatus = (v) => QUOTATION_STATUSES.find((s) => s.value === v) ?? { value: v, label: v, css: '' }

export const SHIPMENT_STATUSES = [
  { value: 'ready', label: 'Chờ lấy hàng', css: 'draft', icon: 'package' },
  { value: 'picked_up', label: 'Đã lấy hàng', css: 'confirmed', icon: 'truck-loading' },
  { value: 'in_transit', label: 'Đang giao', css: 'confirmed', icon: 'truck-delivery' },
  { value: 'delivered', label: 'Đã giao', css: 'completed', icon: 'circle-check' },
  { value: 'failed', label: 'Giao thất bại', css: 'warn', icon: 'alert-triangle' },
  { value: 'returning', label: 'Đang hoàn', css: 'warn', icon: 'arrow-back-up' },
  { value: 'returned', label: 'Đã hoàn về kho', css: 'cancelled', icon: 'building-warehouse' },
  { value: 'cancelled', label: 'Đã hủy', css: 'cancelled', icon: 'x' },
]
export const shipmentStatus = (v) => SHIPMENT_STATUSES.find((s) => s.value === v) ?? { value: v, label: v, css: '', icon: 'circle' }

export const COD_STATUSES = { none: 'Không thu hộ', pending: 'Chờ giao', collected: 'Hãng đang giữ', reconciled: 'Đã đối soát' }

export const TICKET_STATUSES = [
  { value: 'new', label: 'Mới', css: 'confirmed' },
  { value: 'open', label: 'Đang xử lý', css: 'warn' },
  { value: 'pending', label: 'Chờ khách', css: 'draft' },
  { value: 'resolved', label: 'Đã xử lý', css: 'completed' },
  { value: 'closed', label: 'Đã đóng', css: 'draft' },
  { value: 'cancelled', label: 'Đã hủy', css: 'cancelled' },
]
export const ticketStatus = (v) => TICKET_STATUSES.find((s) => s.value === v) ?? { value: v, label: v, css: '' }

export const PRIORITIES = { low: 'Thấp', normal: 'Bình thường', high: 'Cao', urgent: 'Khẩn cấp' }

export const REFUND_METHODS = [
  { value: 'cash', label: 'Hoàn tiền mặt' },
  { value: 'bank', label: 'Hoàn chuyển khoản' },
  { value: 'credit_note', label: 'Không hoàn tiền (trừ vào số khách còn nợ)' },
]

// ===================== Đợt 3: Nhân sự, Marketing, Cài đặt =====================

export const PHASE3_PERMISSIONS = {
  HR_VIEW: 'hr.view', HR_CREATE: 'hr.create', HR_EDIT: 'hr.edit', HR_APPROVE: 'hr.approve',
  MARKETING_VIEW: 'marketing.view', MARKETING_CREATE: 'marketing.create', MARKETING_EDIT: 'marketing.edit',
  SETTINGS_VIEW: 'settings.view', SETTINGS_EDIT: 'settings.edit',
}

export const EMPLOYMENT_STATUSES = [
  { value: 'probation', label: 'Thử việc', css: 'warn' },
  { value: 'official', label: 'Chính thức', css: 'completed' },
  { value: 'maternity', label: 'Nghỉ thai sản', css: 'draft' },
  { value: 'suspended', label: 'Tạm nghỉ', css: 'draft' },
  { value: 'resigned', label: 'Đã nghỉ việc', css: 'cancelled' },
  { value: 'terminated', label: 'Chấm dứt HĐ', css: 'cancelled' },
]
export const employmentStatus = (v) => EMPLOYMENT_STATUSES.find((s) => s.value === v) ?? { value: v, label: v, css: '' }

export const CONTRACT_TYPES = { probation: 'Thử việc', fixed_term: 'Có thời hạn', indefinite: 'Không thời hạn', seasonal: 'Thời vụ', service: 'Dịch vụ / CTV' }

/** Ký hiệu ô chấm công */
export const ATTENDANCE_STATUSES = [
  { value: 'present', label: 'Đi làm', short: 'X', css: 'att-present' },
  { value: 'leave', label: 'Nghỉ phép', short: 'P', css: 'att-leave' },
  { value: 'absent', label: 'Nghỉ không phép', short: 'K', css: 'att-absent' },
  { value: 'holiday', label: 'Nghỉ lễ', short: 'L', css: 'att-holiday' },
  { value: 'business_trip', label: 'Công tác', short: 'CT', css: 'att-trip' },
]

export const LEAVE_STATUSES = { submitted: 'Chờ duyệt', approved: 'Đã duyệt', rejected: 'Từ chối', cancelled: 'Đã hủy', draft: 'Nháp' }
export const LEAVE_CSS = { submitted: 'warn', approved: 'completed', rejected: 'cancelled', cancelled: 'draft', draft: 'draft' }

export const PAYROLL_STATUSES = { draft: 'Nháp', calculated: 'Đã tính', approved: 'Đã duyệt', paid: 'Đã chi lương', closed: 'Đã khóa' }
export const PAYROLL_CSS = { draft: 'draft', calculated: 'confirmed', approved: 'warn', paid: 'completed', closed: 'draft' }

export const CAMPAIGN_STATUSES = [
  { value: 'draft', label: 'Lên kế hoạch', css: 'draft' },
  { value: 'running', label: 'Đang chạy', css: 'completed' },
  { value: 'paused', label: 'Tạm dừng', css: 'warn' },
  { value: 'completed', label: 'Đã kết thúc', css: 'confirmed' },
  { value: 'cancelled', label: 'Đã hủy', css: 'cancelled' },
]
export const campaignStatus = (v) => CAMPAIGN_STATUSES.find((s) => s.value === v) ?? { value: v, label: v, css: '' }

export const PROMOTION_TYPES = { percent: 'Giảm %', fixed: 'Giảm tiền', free_ship: 'Miễn phí ship' }
export const PROMOTION_STATES = { active: 'Đang áp dụng', scheduled: 'Sắp diễn ra', expired: 'Hết hạn', inactive: 'Tạm dừng', used_up: 'Hết lượt' }
export const PROMOTION_CSS = { active: 'completed', scheduled: 'confirmed', expired: 'draft', inactive: 'draft', used_up: 'warn' }

export const SEGMENTS = [
  { value: 'vip', label: 'Khách VIP', hint: 'Tổng mua từ 8 triệu', icon: 'crown' },
  { value: 'loyal', label: 'Thân thiết', hint: 'Mua từ 2 lần, còn quay lại', icon: 'heart' },
  { value: 'new', label: 'Khách mới', hint: 'Mua lần đầu trong 30 ngày', icon: 'sparkles' },
  { value: 'at_risk', label: 'Lâu không mua', hint: 'Mua từ 2 lần, hơn 15 ngày chưa quay lại', icon: 'alert-triangle' },
  { value: 'one_time', label: 'Mua 1 lần', hint: 'Mua 1 lần đã lâu', icon: 'user' },
]

// ===================== ĐỢT 4: Dự án, Tài liệu, Chat, Website =====================
export const PHASE4_PERMISSIONS = {
  PROJECT_VIEW: 'project.view', PROJECT_CREATE: 'project.create', PROJECT_EDIT: 'project.edit', PROJECT_DELETE: 'project.delete',
  DOCUMENT_VIEW: 'document.view', DOCUMENT_CREATE: 'document.create', DOCUMENT_EDIT: 'document.edit', DOCUMENT_DELETE: 'document.delete',
  CHAT_VIEW: 'chat.view', CHAT_CREATE: 'chat.create',
  WEBSITE_VIEW: 'website.view', WEBSITE_CREATE: 'website.create', WEBSITE_EDIT: 'website.edit', WEBSITE_DELETE: 'website.delete',
}

export const PROJECT_STATUSES = [
  { value: 'planning', label: 'Lên kế hoạch', css: 'draft' },
  { value: 'active', label: 'Đang thực hiện', css: 'confirmed' },
  { value: 'on_hold', label: 'Tạm dừng', css: 'warn' },
  { value: 'completed', label: 'Hoàn thành', css: 'completed' },
  { value: 'cancelled', label: 'Đã hủy', css: 'cancelled' },
]
export const projectStatus = (v) => PROJECT_STATUSES.find((s) => s.value === v) ?? { value: v, label: v, css: '' }

export const TASK_PRIORITIES = [
  { value: 'urgent', label: 'Khẩn cấp', css: 'cancelled', icon: 'flame' },
  { value: 'high', label: 'Cao', css: 'warn', icon: 'arrow-up' },
  { value: 'normal', label: 'Bình thường', css: 'draft', icon: 'minus' },
  { value: 'low', label: 'Thấp', css: 'draft', icon: 'arrow-down' },
]
export const taskPriority = (v) => TASK_PRIORITIES.find((p) => p.value === v) ?? TASK_PRIORITIES[2]

export const DOCUMENT_STATUS_CSS = { draft: 'draft', pending_signature: 'warn', signed: 'confirmed', active: 'completed', expired: 'cancelled', archived: 'draft' }
export const DOCUMENT_TYPE_ICONS = { contract: 'file-certificate', policy: 'gavel', process: 'route', form: 'forms', report: 'report-analytics', other: 'file' }
