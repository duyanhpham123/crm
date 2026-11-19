/** 120000000 → "120.000.000 ₫" */
export function formatMoney(value) {
  if (value === null || value === undefined || value === '') return ''
  return new Intl.NumberFormat('vi-VN').format(value) + ' ₫'
}

/** Ngày giờ UTC từ API → "19/11/2026" theo giờ máy người dùng */
export function formatDate(value) {
  if (!value) return ''
  const iso = /[zZ]|[+-]\d\d:\d\d$/.test(value) ? value : value + 'Z' // API trả UTC không kèm "Z"
  return new Date(iso).toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' })
}

/** Ngày giờ: "19/11/2026 08:30" */
export function formatDateTime(value) {
  if (!value) return ''
  const iso = /[zZ]|[+-]\d\d:\d\d$/.test(value) ? value : value + 'Z'
  return new Date(iso).toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}

/** Sinh mật khẩu ngẫu nhiên an toàn (dùng crypto của trình duyệt), luôn có chữ hoa, chữ thường và số. */
export function generatePassword(length = 14) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'   // bỏ ký tự dễ nhầm: I l 1 O 0
  const bytes = crypto.getRandomValues(new Uint32Array(length))
  const pick = (set, n) => set[n % set.length]
  const body = Array.from(bytes, (b) => pick(chars, b))
  body[0] = pick('ABCDEFGHJKLMNPQRSTUVWXYZ', bytes[0])
  body[1] = pick('abcdefghijkmnpqrstuvwxyz', bytes[1])
  body[2] = pick('23456789', bytes[2])
  return body.sort(() => (crypto.getRandomValues(new Uint8Array(1))[0] & 1 ? 1 : -1)).join('')
}

/** "Nguyễn Văn An" → "VA" */
export function initials(name = '') {
  const parts = name.trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return '?'
  if (parts.length === 1) return parts[0][0].toUpperCase()
  return (parts.at(-2)[0] + parts.at(-1)[0]).toUpperCase()
}
