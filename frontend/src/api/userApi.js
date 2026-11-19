import { api } from './client'

/** API quản lý người dùng. Khớp với backend/MyERP.Api/Controllers/UsersController.cs */
export const userApi = {
  /** GET /api/users?search=&departmentId=&roleId=&isActive=&page=&pageSize= */
  list: ({ search, departmentId, roleId, isActive, page = 1, pageSize = 20 }) =>
    api
      .get('/api/users', {
        params: {
          search: search || undefined,
          departmentId: departmentId || undefined,
          roleId: roleId || undefined,
          isActive: isActive === '' ? undefined : isActive,
          page,
          pageSize,
        },
      })
      .then((r) => r.data),

  /** GET /api/users/form-options → { departments: [{id, name}], roles: [{id, name, description}] } */
  formOptions: () => api.get('/api/users/form-options').then((r) => r.data),

  /** GET /api/users/{id} */
  get: (id) => api.get(`/api/users/${id}`).then((r) => r.data),

  /** POST /api/users  body: { userName, fullName, email, phoneNumber, departmentId, roleIds, password } */
  create: (body) => api.post('/api/users', body).then((r) => r.data),

  /** PUT /api/users/{id}  body: { fullName, email, phoneNumber, departmentId, roleIds } */
  update: (id, body) => api.put(`/api/users/${id}`, body).then((r) => r.data),

  /** POST /api/users/{id}/reset-password  body: { newPassword } */
  resetPassword: (id, newPassword) => api.post(`/api/users/${id}/reset-password`, { newPassword }),

  /** POST /api/users/{id}/status  body: { isActive } */
  setStatus: (id, isActive) => api.post(`/api/users/${id}/status`, { isActive }).then((r) => r.data),
}
