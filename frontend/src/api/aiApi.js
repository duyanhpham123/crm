import { api } from './client'

/** Khóa truy cập cá nhân cho trợ lý AI - khớp AccountController (api/me/api-tokens). */
const data = (r) => r.data

export const aiApi = {
  tokens: () => api.get('/api/me/api-tokens').then(data),
  /** → { info, token } - token gốc chỉ trả về 1 lần */
  createToken: (name, expiresInDays) => api.post('/api/me/api-tokens', { name, expiresInDays }).then(data),
  revokeToken: (id) => api.delete(`/api/me/api-tokens/${id}`),
  /** → { mcpDir, apiUrl } */
  setup: () => api.get('/api/me/ai-setup').then(data),
}
