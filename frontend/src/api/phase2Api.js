import { api } from './client'

/**
 * API Báo giá, Vận chuyển, Kế toán, CSKH.
 * Khớp backend/MyERP.Api/Controllers/Phase2Controllers.cs
 */
const clean = (params = {}) => Object.fromEntries(Object.entries(params).filter(([, v]) => v !== '' && v !== null && v !== undefined && v !== false))
const data = (r) => r.data

export const quotationApi = {
  /** → { rows: PagedResult, summary: { openCount, openValue, acceptedCount, acceptedValue, conversionRate } } */
  list: (params) => api.get('/api/quotations', { params: clean(params) }).then(data),
  get: (id) => api.get(`/api/quotations/${id}`).then(data),
  create: (body) => api.post('/api/quotations', body).then(data),
  update: (id, body) => api.put(`/api/quotations/${id}`, body).then(data),
  send: (id) => api.post(`/api/quotations/${id}/send`).then(data),
  /** Khách đồng ý → tạo đơn hàng nháp, trả về báo giá có orderId */
  accept: (id) => api.post(`/api/quotations/${id}/accept`).then(data),
  reject: (id, reason) => api.post(`/api/quotations/${id}/reject`, { reason }).then(data),
  cancel: (id) => api.post(`/api/quotations/${id}/cancel`).then(data),
}

export const logisticsApi = {
  /** → { carriers, statuses, bankAccounts } */
  lookups: () => api.get('/api/logistics/lookups').then(data),
  list: (params) => api.get('/api/logistics/shipments', { params: clean(params) }).then(data),
  readyOrders: (search) => api.get('/api/logistics/ready-orders', { params: clean({ search }) }).then(data),
  get: (id) => api.get(`/api/logistics/shipments/${id}`).then(data),
  create: (body) => api.post('/api/logistics/shipments', body).then(data),
  update: (id, body) => api.put(`/api/logistics/shipments/${id}`, body).then(data),
  /** body: { status, note, location } */
  changeStatus: (id, body) => api.post(`/api/logistics/shipments/${id}/status`, body).then(data),
  /** body: { carrierId, shipmentIds, bankAccountId, reference } */
  reconcileCod: (body) => api.post('/api/logistics/cod/reconcile', body).then(data),
}

export const accountingApi = {
  /** → { bankAccounts, categories, paymentMethods } */
  lookups: () => api.get('/api/accounting/lookups').then(data),
  overview: (params) => api.get('/api/accounting/overview', { params: clean(params) }).then(data),
  vouchers: (params) => api.get('/api/accounting/vouchers', { params: clean(params) }).then(data),
  createVoucher: (body) => api.post('/api/accounting/vouchers', body).then(data),
  cancelVoucher: (id) => api.post(`/api/accounting/vouchers/${id}/cancel`).then(data),
  cashbook: (params) => api.get('/api/accounting/cashbook', { params: clean(params) }).then(data),
  receivables: (params) => api.get('/api/accounting/receivables', { params: clean(params) }).then(data),
  customerDocs: (partnerId) => api.get(`/api/accounting/receivables/${partnerId}`).then(data),
  payables: (params) => api.get('/api/accounting/payables', { params: clean(params) }).then(data),
  supplierDocs: (partnerId) => api.get(`/api/accounting/payables/${partnerId}`).then(data),
  /** kind: customer | supplier → [{ id, code, name, phone, due }] */
  partners: (kind, search) => api.get('/api/accounting/partners', { params: clean({ kind, search }) }).then(data),
  createBank: (body) => api.post('/api/accounting/bank-accounts', body).then(data),
  updateBank: (id, body) => api.put(`/api/accounting/bank-accounts/${id}`, body).then(data),
}

export const supportApi = {
  /** → { categories, agents, channels, priorities } */
  lookups: () => api.get('/api/support/lookups').then(data),
  list: (params) => api.get('/api/support/tickets', { params: clean(params) }).then(data),
  get: (id) => api.get(`/api/support/tickets/${id}`).then(data),
  create: (body) => api.post('/api/support/tickets', body).then(data),
  update: (id, body) => api.put(`/api/support/tickets/${id}`, body).then(data),
  message: (id, body, isInternal) => api.post(`/api/support/tickets/${id}/messages`, { body, isInternal }).then(data),
  changeStatus: (id, status, resolution) => api.post(`/api/support/tickets/${id}/status`, { status, resolution }).then(data),
  assign: (id, userId) => api.post(`/api/support/tickets/${id}/assign`, { userId }).then(data),
  rate: (id, score, note) => api.post(`/api/support/tickets/${id}/rate`, { score, note }).then(data),
}

/** Trả hàng cho đơn bán: body { lines: [{ salesOrderLineId, quantity, condition }], reason, refundMethod, refundAmount, bankAccountId } */
export const returnApi = {
  create: (orderId, body) => api.post(`/api/sales/orders/${orderId}/returns`, body).then(data),
}
