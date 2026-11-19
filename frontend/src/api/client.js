import axios from 'axios'

/**
 * Cấu hình gọi API dùng chung cho cả ứng dụng.
 *  - Tự gắn "Authorization: Bearer <token>" vào mọi request
 *  - Gặp 401 (token hết hạn) thì tự gọi /api/auth/refresh rồi gửi lại request
 *  - Refresh thất bại thì phát sự kiện "auth:logout" để AuthContext đưa về trang đăng nhập
 */

const BASE_URL = import.meta.env.VITE_API_URL || ''
const STORAGE_KEY = 'myerp.tokens'

// ---------- Lưu token trong localStorage ----------
export const tokenStorage = {
  get() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY))
    } catch {
      return null
    }
  },
  set(tokens) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(tokens))
  },
  clear() {
    localStorage.removeItem(STORAGE_KEY)
  },
}

// ---------- Client cho API công khai (đăng nhập, refresh): không gắn token ----------
export const publicApi = axios.create({ baseURL: BASE_URL })

// ---------- Client cho API cần đăng nhập ----------
export const api = axios.create({ baseURL: BASE_URL })

api.interceptors.request.use((config) => {
  const tokens = tokenStorage.get()
  if (tokens?.accessToken) config.headers.Authorization = `Bearer ${tokens.accessToken}`
  return config
})

let refreshing = null // nhiều request cùng hết hạn chỉ refresh 1 lần

async function refreshTokens() {
  const tokens = tokenStorage.get()
  if (!tokens?.refreshToken) throw new Error('Không có refresh token')
  const { data } = await publicApi.post('/api/auth/refresh', { refreshToken: tokens.refreshToken })
  tokenStorage.set(data)
  return data
}

api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const original = error.config
    if (error.response?.status === 401 && original && !original._retried && tokenStorage.get()) {
      original._retried = true
      try {
        refreshing ??= refreshTokens().finally(() => (refreshing = null))
        const fresh = await refreshing
        original.headers.Authorization = `Bearer ${fresh.accessToken}`
        return api(original)
      } catch {
        tokenStorage.clear()
        window.dispatchEvent(new Event('auth:logout'))
      }
    }
    return Promise.reject(error)
  },
)

/**
 * Đổi lỗi từ API thành câu thông báo cho người dùng.
 * Backend trả lỗi dạng ProblemDetails: { title, status, errors: { Field: ["..."] } }
 */
export function getErrorMessage(error) {
  if (!error?.response) return 'Không kết nối được máy chủ.'
  const { status, data } = error.response
  if (data?.errors) {
    const messages = Object.values(data.errors).flat()
    if (messages.length) return [...new Set(messages)].join(' ')
  }
  if (data?.title) return data.title
  if (status === 403) return 'Bạn không có quyền thực hiện thao tác này.'
  if (status === 429) return 'Bạn thao tác quá nhanh. Đợi một phút rồi thử lại.'
  return 'Có lỗi xảy ra. Vui lòng thử lại.'
}
