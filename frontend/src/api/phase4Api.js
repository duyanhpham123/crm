import { api } from './client'

/** API Dự án & công việc, Tài liệu, Chat nội bộ, Website - khớp backend/MyERP.Api/Controllers/Phase4Controllers.cs */
const clean = (params = {}) => Object.fromEntries(Object.entries(params).filter(([, v]) => v !== '' && v !== null && v !== undefined && v !== false))
const data = (r) => r.data

export const projectApi = {
  /** → { users, departments, stages, projects, currentUserId } */
  lookups: () => api.get('/api/projects/lookups').then(data),
  list: (params) => api.get('/api/projects', { params: clean(params) }).then(data),
  get: (id) => api.get(`/api/projects/${id}`).then(data),
  create: (body) => api.post('/api/projects', body).then(data),
  update: (id, body) => api.put(`/api/projects/${id}`, body).then(data),

  /** params: { projectId, assignee: 'me'|'none'|userId, status: 'open'|'overdue'|'done', priority, search } → { stages, tasks, total, truncated } */
  board: (params) => api.get('/api/projects/tasks', { params: clean(params) }).then(data),
  task: (id) => api.get(`/api/projects/tasks/${id}`).then(data),
  createTask: (body) => api.post('/api/projects/tasks', body).then(data),
  updateTask: (id, body) => api.put(`/api/projects/tasks/${id}`, body).then(data),
  moveTask: (id, stageId) => api.post(`/api/projects/tasks/${id}/move`, { stageId }).then(data),
  setProgress: (id, percent) => api.put(`/api/projects/tasks/${id}/progress`, { percent }).then(data),
  addChecklist: (id, title) => api.post(`/api/projects/tasks/${id}/checklist`, { title }).then(data),
  toggleChecklist: (id, itemId, isDone) => api.put(`/api/projects/tasks/${id}/checklist/${itemId}`, { isDone }).then(data),
  removeChecklist: (id, itemId) => api.delete(`/api/projects/tasks/${id}/checklist/${itemId}`).then(data),
  logTime: (id, body) => api.post(`/api/projects/tasks/${id}/timesheets`, body).then(data),
  deleteTask: (id) => api.delete(`/api/projects/tasks/${id}`),
}

export const documentApi = {
  lookups: () => api.get('/api/documents/lookups').then(data),
  list: (params) => api.get('/api/documents', { params: clean(params) }).then(data),
  get: (id) => api.get(`/api/documents/${id}`).then(data),
  create: (body) => api.post('/api/documents', body).then(data),
  update: (id, body) => api.put(`/api/documents/${id}`, body).then(data),
  remove: (id) => api.delete(`/api/documents/${id}`),
  upload: (id, file, note, onProgress) => {
    const form = new FormData()
    form.append('file', file)
    if (note) form.append('note', note)
    return api.post(`/api/documents/${id}/versions`, form, {
      onUploadProgress: (e) => onProgress?.(e.total ? Math.round((e.loaded * 100) / e.total) : 0),
    }).then(data)
  },
  /** Tải file về máy (kèm token đăng nhập nên không dùng link trực tiếp). */
  download: async (attachmentId, fileName) => {
    const r = await api.get(`/api/documents/files/${attachmentId}`, { responseType: 'blob' })
    const url = URL.createObjectURL(r.data)
    const a = document.createElement('a')
    a.href = url
    a.download = fileName
    document.body.appendChild(a)
    a.click()
    a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  },
  createFolder: (body) => api.post('/api/documents/folders', body).then(data),
  updateFolder: (id, body) => api.put(`/api/documents/folders/${id}`, body).then(data),
  deleteFolder: (id) => api.delete(`/api/documents/folders/${id}`),
}

export const chatApi = {
  channels: () => api.get('/api/chat/channels').then(data),
  unread: () => api.get('/api/chat/unread').then(data),
  users: () => api.get('/api/chat/users').then(data),
  channel: (id) => api.get(`/api/chat/channels/${id}`).then(data),
  older: (id, beforeId) => api.get(`/api/chat/channels/${id}/messages`, { params: { beforeId } }).then(data),
  createGroup: (name, memberIds) => api.post('/api/chat/channels', { name, memberIds }).then(data),
  direct: (userId) => api.post('/api/chat/direct', { userId }).then(data),
  post: (id, body, parentMessageId) => api.post(`/api/chat/channels/${id}/messages`, { body, parentMessageId: parentMessageId ?? null }).then(data),
  read: (id, messageId) => api.post(`/api/chat/channels/${id}/read`, { messageId }),
  addMembers: (id, userIds) => api.post(`/api/chat/channels/${id}/members`, { userIds }),
  leave: (id) => api.post(`/api/chat/channels/${id}/leave`),
  edit: (messageId, body) => api.put(`/api/chat/messages/${messageId}`, { body }).then(data),
  recall: (messageId) => api.delete(`/api/chat/messages/${messageId}`).then(data),
  react: (messageId, reaction) => api.post(`/api/chat/messages/${messageId}/reactions`, { reaction }).then(data),
}

/** Website: mọi hàm nhận siteId (null = website đầu tiên) - mỗi website có sản phẩm, bài viết, menu, liên hệ riêng. */
const sp = (siteId, params = {}) => ({ params: clean({ siteId, ...params }) })
export const websiteApi = {
  sites: () => api.get('/api/website/sites').then(data),
  createSite: (body) => api.post('/api/website/sites', body).then(data),
  /** → { key, prefix } - khóa gốc chỉ trả về 1 lần */
  issueKey: (id) => api.post(`/api/website/sites/${id}/api-key`).then(data),
  revokeKey: (id) => api.delete(`/api/website/sites/${id}/api-key`),
  webhook: (id) => api.get(`/api/website/sites/${id}/webhook`).then(data),
  saveWebhook: (id, url, newSecret = false) => api.put(`/api/website/sites/${id}/webhook`, { url, newSecret }).then(data),
  revalidate: (id) => api.post(`/api/website/sites/${id}/revalidate`).then(data),

  overview: (siteId) => api.get('/api/website/overview', sp(siteId)).then(data),
  site: (siteId) => api.get('/api/website/site', sp(siteId)).then(data),
  saveSite: (siteId, body) => api.put('/api/website/site', body, sp(siteId)).then(data),
  pages: (siteId) => api.get('/api/website/pages', sp(siteId)).then(data),
  createPage: (siteId, body) => api.post('/api/website/pages', body, sp(siteId)).then(data),
  updatePage: (siteId, id, body) => api.put(`/api/website/pages/${id}`, body, sp(siteId)).then(data),
  deletePage: (siteId, id) => api.delete(`/api/website/pages/${id}`, sp(siteId)),
  posts: (siteId, params) => api.get('/api/website/posts', sp(siteId, params)).then(data),
  post: (siteId, id) => api.get(`/api/website/posts/${id}`, sp(siteId)).then(data),
  createPost: (siteId, body) => api.post('/api/website/posts', body, sp(siteId)).then(data),
  updatePost: (siteId, id, body) => api.put(`/api/website/posts/${id}`, body, sp(siteId)).then(data),
  deletePost: (siteId, id) => api.delete(`/api/website/posts/${id}`, sp(siteId)),
  categories: (siteId) => api.get('/api/website/categories', sp(siteId)).then(data),
  createCategory: (siteId, name) => api.post('/api/website/categories', { name }, sp(siteId)).then(data),
  products: (siteId, params) => api.get('/api/website/products', sp(siteId, params)).then(data),
  /** body: { isPublished, priceOverride, isFeatured } */
  publish: (siteId, modelId, body) => api.put(`/api/website/products/${modelId}`, body, sp(siteId)).then(data),
  menu: (siteId, code) => api.get(`/api/website/menus/${code}`, sp(siteId)).then(data),
  saveMenu: (siteId, code, items) => api.put(`/api/website/menus/${code}`, { items }, sp(siteId)).then(data),
  contacts: (siteId, params) => api.get('/api/website/contacts', sp(siteId, params)).then(data),
  convertContact: (siteId, id) => api.post(`/api/website/contacts/${id}/convert`, null, sp(siteId)).then(data),
}
