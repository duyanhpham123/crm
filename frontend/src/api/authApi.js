import { api, publicApi } from './client'

// Mỗi hàm = 1 endpoint của backend. Trả về phần "data" (JSON) của response.

export const authApi = {
  /** GET /api/auth/setup-status → { needsSetup } */
  setupStatus: () => publicApi.get('/api/auth/setup-status').then((r) => r.data),

  /** POST /api/auth/setup  body: { password, fullName, email } */
  setupAdmin: (body) => publicApi.post('/api/auth/setup', body),

  /** POST /api/auth/login  body: { userName, password } → { accessToken, accessTokenExpiresAt, refreshToken } */
  login: (userName, password) => publicApi.post('/api/auth/login', { userName, password }).then((r) => r.data),

  /** POST /api/auth/logout  body: { refreshToken } */
  logout: (refreshToken) => publicApi.post('/api/auth/logout', { refreshToken }),
}

export const accountApi = {
  /** GET /api/me → { userId, userName, fullName, companyId, companyName, permissions[] } */
  me: () => api.get('/api/me').then((r) => r.data),

  /** GET /api/apps → [{ code, name, icon, color, route }] */
  apps: () => api.get('/api/apps').then((r) => r.data),

  /** POST /api/me/change-password  body: { currentPassword, newPassword } → cặp token mới */
  changePassword: (currentPassword, newPassword) =>
    api.post('/api/me/change-password', { currentPassword, newPassword }).then((r) => r.data),
}
