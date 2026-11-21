/**
 * Gọi API của MyERP - CHỈ dùng ở phía máy chủ (Server Component, Route Handler) vì kèm khóa website bí mật.
 * Mỗi lần fetch gắn tag: ERP thay đổi dữ liệu thì gọi /api/revalidate để làm mới đúng nhóm trang đó.
 * Webhook lỗi thì trang vẫn tự làm mới sau REVALIDATE_SECONDS giây.
 */
const BASE = process.env.ERP_API_URL || 'http://localhost:5121'
const KEY = process.env.ERP_SITE_KEY || ''
const REVALIDATE_SECONDS = 300

export class ErpError extends Error {
  constructor(status, message) {
    super(message)
    this.status = status
  }
}

async function erp(path, { tags = [], method = 'GET', body, clientIp, noStore = false } = {}) {
  if (!KEY) throw new ErpError(500, 'Chưa cấu hình ERP_SITE_KEY trong .env.local (tạo khóa ở ERP > Website > Kết nối website).')
  const headers = { 'X-Site-Key': KEY, Accept: 'application/json' }
  if (body) headers['Content-Type'] = 'application/json'
  if (clientIp) headers['X-Client-IP'] = clientIp
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
    ...(method === 'GET' && !noStore ? { next: { revalidate: REVALIDATE_SECONDS, tags } } : { cache: 'no-store' }),
  })
  const text = await res.text()
  const data = text ? JSON.parse(text) : null
  if (!res.ok) throw new ErpError(res.status, data?.title || `ERP trả lỗi ${res.status}`)
  return data
}

const qs = (params) => {
  const p = new URLSearchParams(Object.entries(params).filter(([, v]) => v !== undefined && v !== null && v !== '' && v !== false))
  const s = p.toString()
  return s ? `?${s}` : ''
}

/** Thông tin cửa hàng, menu, danh mục, phí ship. */
export const getSite = () => erp('/api/public/site', { tags: ['site', 'products'] })
/** params: { category, search, featured, sort: price_asc | price_desc | newest } */
export const getProducts = (params = {}) => erp(`/api/public/products${qs(params)}`, { tags: ['products'] })
export const getProduct = (slug) => erp(`/api/public/products/${encodeURIComponent(slug)}`, { tags: ['products'] })
export const getPosts = (category) => erp(`/api/public/posts${qs({ category })}`, { tags: ['posts'] })
export const getPost = (slug) => erp(`/api/public/posts/${encodeURIComponent(slug)}`, { tags: ['posts'] })
export const getPage = (slug) => erp(`/api/public/pages/${encodeURIComponent(slug)}`, { tags: ['pages'] })

export const checkPromotion = (code, subTotal) => erp(`/api/public/promotions/check${qs({ code, subTotal })}`, { noStore: true })
export const placeOrder = (body, clientIp) => erp('/api/public/orders', { method: 'POST', body, clientIp })
export const sendContact = (body, clientIp) => erp('/api/public/contact', { method: 'POST', body, clientIp })

/** Không tìm thấy (404) thì trả null để trang hiện notFound(). */
export async function orNull(promise) {
  try { return await promise } catch (e) { if (e instanceof ErpError && e.status === 404) return null; throw e }
}
