import { api } from './client'

/** API CRM - Khách hàng, Cơ hội, danh mục. Khớp với backend/MyERP.Api/Controllers/Crm/ */

export const crmLookupApi = {
  /** GET /api/crm/lookups → { sources, customerGroups, pipelines: [{ id, name, stages }], lostReasons, owners } */
  get: () => api.get('/api/crm/lookups').then((r) => r.data),
}

export const customerApi = {
  /** GET /api/crm/customers?search=&groupId=&ownerId=&page=&pageSize= */
  list: ({ search, groupId, ownerId, page = 1, pageSize = 20 }) =>
    api
      .get('/api/crm/customers', { params: { search: search || undefined, groupId: groupId || undefined, ownerId: ownerId || undefined, page, pageSize } })
      .then((r) => r.data),

  /** GET /api/crm/customers/{id} → thông tin + contacts + opportunities */
  get: (id) => api.get(`/api/crm/customers/${id}`).then((r) => r.data),

  /** POST /api/crm/customers  body: { partnerType, name, taxCode, phone, ..., primaryContact } */
  create: (body) => api.post('/api/crm/customers', body).then((r) => r.data),

  /** PUT /api/crm/customers/{id} */
  update: (id, body) => api.put(`/api/crm/customers/${id}`, body).then((r) => r.data),

  /** DELETE /api/crm/customers/{id} */
  remove: (id) => api.delete(`/api/crm/customers/${id}`),

  addContact: (id, body) => api.post(`/api/crm/customers/${id}/contacts`, body).then((r) => r.data),
  updateContact: (id, contactId, body) => api.put(`/api/crm/customers/${id}/contacts/${contactId}`, body).then((r) => r.data),
  removeContact: (id, contactId) => api.delete(`/api/crm/customers/${id}/contacts/${contactId}`),
}

export const opportunityApi = {
  /** GET /api/crm/opportunities/board?pipelineId=&search=&ownerId= → { pipelineId, pipelineName, columns: [{ stage, count, totalValue, items }] } */
  board: ({ pipelineId, search, ownerId } = {}) =>
    api
      .get('/api/crm/opportunities/board', { params: { pipelineId: pipelineId || undefined, search: search || undefined, ownerId: ownerId || undefined } })
      .then((r) => r.data),

  get: (id) => api.get(`/api/crm/opportunities/${id}`).then((r) => r.data),

  /** POST /api/crm/opportunities  body: { name, customerId, contactId, stageId, expectedRevenue, ... } */
  create: (body) => api.post('/api/crm/opportunities', body).then((r) => r.data),

  update: (id, body) => api.put(`/api/crm/opportunities/${id}`, body).then((r) => r.data),

  /** POST /api/crm/opportunities/{id}/stage  body: { stageId, lostReasonId, lostNote } */
  moveStage: (id, stageId, lostReasonId = null, lostNote = null) =>
    api.post(`/api/crm/opportunities/${id}/stage`, { stageId, lostReasonId, lostNote }).then((r) => r.data),

  remove: (id) => api.delete(`/api/crm/opportunities/${id}`),
}
