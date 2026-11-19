import { api } from './client'

/** API vai trò & quyền. Khớp với backend/MyERP.Api/Controllers/RolesController.cs */
export const roleApi = {
  /** GET /api/roles → [{ id, code, name, description, isSystem, userCount, permissionCount }] */
  list: () => api.get('/api/roles').then((r) => r.data),

  /** GET /api/roles/permission-catalog → { groups: [{ appCode, appName, icon, color, permissions: [...] }], canGrantAllCompanies } */
  catalog: () => api.get('/api/roles/permission-catalog').then((r) => r.data),

  /** GET /api/roles/{id} → { ..., isReadOnly, readOnlyReason, permissions: [{ permissionId, dataScope }], rowVersion } */
  get: (id) => api.get(`/api/roles/${id}`).then((r) => r.data),

  /** POST /api/roles  body: { code, name, description, permissions } */
  create: (body) => api.post('/api/roles', body).then((r) => r.data),

  /** PUT /api/roles/{id}  body: { name, description, permissions, rowVersion } */
  update: (id, body) => api.put(`/api/roles/${id}`, body).then((r) => r.data),

  /** DELETE /api/roles/{id} */
  remove: (id) => api.delete(`/api/roles/${id}`),
}
