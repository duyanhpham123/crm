import { revalidateTag } from 'next/cache'

const ALLOWED = new Set(['site', 'products', 'posts', 'pages'])

/**
 * ERP gọi khi dữ liệu thay đổi: POST header "x-revalidate-secret", body { "tags": ["products", ...] }.
 * Làm mới các trang đã fetch với tag đó → khách tải lại trang là thấy dữ liệu mới ngay.
 */
export async function POST(request) {
  const secret = process.env.REVALIDATE_SECRET
  if (!secret || request.headers.get('x-revalidate-secret') !== secret) {
    return Response.json({ error: 'Sai mật khẩu webhook.' }, { status: 401 })
  }
  let tags = []
  try { tags = (await request.json()).tags ?? [] } catch { /* body rỗng */ }
  const done = tags.filter((t) => ALLOWED.has(t))
  done.forEach((t) => revalidateTag(t))
  return Response.json({ revalidated: done, at: new Date().toISOString() })
}
