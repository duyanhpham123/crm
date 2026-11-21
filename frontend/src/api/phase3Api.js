import { api } from './client'

/** API Nhân sự, Marketing, Cài đặt - khớp backend/MyERP.Api/Controllers/Phase3Controllers.cs */
const clean = (params = {}) => Object.fromEntries(Object.entries(params).filter(([, v]) => v !== '' && v !== null && v !== undefined && v !== false))
const data = (r) => r.data

export const hrApi = {
  /** → { departments, positions, users, leaveTypes, employees } */
  lookups: () => api.get('/api/hr/lookups').then(data),
  employees: (params) => api.get('/api/hr/employees', { params: clean(params) }).then(data),
  employee: (id) => api.get(`/api/hr/employees/${id}`).then(data),
  createEmployee: (body) => api.post('/api/hr/employees', body).then(data),
  updateEmployee: (id, body) => api.put(`/api/hr/employees/${id}`, body).then(data),
  createPosition: (name) => api.post('/api/hr/positions', { name }).then(data),

  attendance: (params) => api.get('/api/hr/attendance', { params: clean(params) }).then(data),
  /** body: { employeeId, date, status, workHours, overtimeHours, note } */
  setAttendance: (body) => api.put('/api/hr/attendance', body),
  fillAttendance: (year, month) => api.post('/api/hr/attendance/fill', { year, month, employeeIds: null }).then(data),
  check: (employeeId, action) => api.post('/api/hr/attendance/check', { employeeId, action }).then(data),

  leaves: (params) => api.get('/api/hr/leaves', { params: clean(params) }).then(data),
  createLeave: (body) => api.post('/api/hr/leaves', body).then(data),
  approveLeave: (id) => api.post(`/api/hr/leaves/${id}/approve`).then(data),
  rejectLeave: (id, reason) => api.post(`/api/hr/leaves/${id}/reject`, { reason }).then(data),
  cancelLeave: (id) => api.post(`/api/hr/leaves/${id}/cancel`).then(data),

  payrolls: () => api.get('/api/hr/payroll').then(data),
  payroll: (id) => api.get(`/api/hr/payroll/${id}`).then(data),
  createPayroll: (year, month, standardDays) => api.post('/api/hr/payroll', { year, month, standardDays }).then(data),
  recalculate: (id, standardDays) => api.post(`/api/hr/payroll/${id}/recalculate`, null, { params: clean({ standardDays }) }).then(data),
  updatePayslip: (id, payslipId, body) => api.put(`/api/hr/payroll/${id}/payslips/${payslipId}`, body).then(data),
  approvePayroll: (id) => api.post(`/api/hr/payroll/${id}/approve`).then(data),
  reopenPayroll: (id) => api.post(`/api/hr/payroll/${id}/reopen`).then(data),
  payPayroll: (id, bankAccountId) => api.post(`/api/hr/payroll/${id}/pay`, { bankAccountId, date: null }).then(data),
}

export const marketingApi = {
  lookups: () => api.get('/api/marketing/lookups').then(data),
  campaigns: (params) => api.get('/api/marketing/campaigns', { params: clean(params) }).then(data),
  campaign: (id) => api.get(`/api/marketing/campaigns/${id}`).then(data),
  createCampaign: (body) => api.post('/api/marketing/campaigns', body).then(data),
  updateCampaign: (id, body) => api.put(`/api/marketing/campaigns/${id}`, body).then(data),
  /** body: { date, impressions, clicks, spend, leads } */
  setStat: (id, body) => api.put(`/api/marketing/campaigns/${id}/stats`, body).then(data),
  promotions: (params) => api.get('/api/marketing/promotions', { params: clean(params) }).then(data),
  createPromotion: (body) => api.post('/api/marketing/promotions', body).then(data),
  updatePromotion: (id, body) => api.put(`/api/marketing/promotions/${id}`, body).then(data),
  segments: (params) => api.get('/api/marketing/segments', { params: clean(params) }).then(data),
}

/** Kiểm tra mã giảm giá khi tạo đơn: → { id, code, name, discount } */
export const promotionCheck = (code, subTotal, shippingFee, channel) =>
  api.get('/api/sales/promotions/check', { params: { code, subTotal, shippingFee, channel } }).then(data)

export const settingsApi = {
  company: () => api.get('/api/settings/company').then(data),
  updateCompany: (body) => api.put('/api/settings/company', body).then(data),
  departments: () => api.get('/api/settings/departments').then(data),
  createDepartment: (body) => api.post('/api/settings/departments', body).then(data),
  updateDepartment: (id, body) => api.put(`/api/settings/departments/${id}`, body).then(data),
  warehouses: () => api.get('/api/settings/warehouses').then(data),
  createWarehouse: (body) => api.post('/api/settings/warehouses', body).then(data),
  updateWarehouse: (id, body) => api.put(`/api/settings/warehouses/${id}`, body).then(data),
  apps: () => api.get('/api/settings/apps').then(data),
  toggleApp: (id, isEnabled) => api.put(`/api/settings/apps/${id}`, { isEnabled }).then(data),
  sequences: () => api.get('/api/settings/sequences').then(data),
  updateSequence: (id, body) => api.put(`/api/settings/sequences/${id}`, body).then(data),
}

/** Thông tin công ty để in chứng từ (mọi người đăng nhập đều đọc được) */
export const companyInfoApi = { get: () => api.get('/api/company-info').then(data) }
