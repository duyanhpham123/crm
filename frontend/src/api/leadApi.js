import { api } from './client'

/** API CRM - Lead. Khớp với backend/MyERP.Api/Controllers/Crm/LeadsController.cs */
export const leadApi = {
  /** GET /api/crm/leads?search=&status=&page=&pageSize= → { items, page, pageSize, totalCount, totalPages } */
  list: ({ search, status, page = 1, pageSize = 20 }) =>
    api
      .get('/api/crm/leads', { params: { search: search || undefined, status: status || undefined, page, pageSize } })
      .then((r) => r.data),

  /** GET /api/crm/leads/{id} */
  get: (id) => api.get(`/api/crm/leads/${id}`).then((r) => r.data),

  /** POST /api/crm/leads */
  create: (body) => api.post('/api/crm/leads', body).then((r) => r.data),

  /** PUT /api/crm/leads/{id}  (gửi kèm rowVersion để phát hiện người khác đã sửa) */
  update: (id, body) => api.put(`/api/crm/leads/${id}`, body).then((r) => r.data),

  /** POST /api/crm/leads/{id}/status  body: { status, reason } */
  changeStatus: (id, status, reason) => api.post(`/api/crm/leads/${id}/status`, { status, reason }).then((r) => r.data),

  /** DELETE /api/crm/leads/{id} */
  remove: (id) => api.delete(`/api/crm/leads/${id}`),

  /** GET /api/crm/lead-sources */
  sources: () => api.get('/api/crm/lead-sources').then((r) => r.data),
}
