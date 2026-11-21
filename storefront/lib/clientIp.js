/** IP thật của khách (qua proxy / CDN) - gửi sang ERP để giới hạn số lần đặt hàng / gửi form theo từng khách. */
export function clientIp(request) {
  const fwd = request.headers.get('x-forwarded-for')
  return (fwd ? fwd.split(',')[0] : request.headers.get('x-real-ip') || '').trim().slice(0, 45) || undefined
}

/** Lỗi từ ERP → JSON { error } cho trình duyệt (không để lộ chi tiết máy chủ). */
export function errorResponse(e) {
  const status = e?.status && e.status < 500 ? e.status : 502
  const error = status === 502 ? 'Hệ thống đang bận, vui lòng thử lại sau ít phút.' : e.message
  return Response.json({ error }, { status })
}
