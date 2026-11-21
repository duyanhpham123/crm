/** 120000000 → "120.000.000 ₫" */
export function formatMoney(value) {
  if (value === null || value === undefined || value === '') return ''
  return new Intl.NumberFormat('vi-VN').format(value) + ' ₫'
}

/** Rút gọn số tiền cho chỗ hẹp: 1250000000 → "1,25 tỷ", 350000000 → "350 tr" */
export function formatMoneyShort(value) {
  if (!value) return '0'
  const fmt = (n) => new Intl.NumberFormat('vi-VN', { maximumFractionDigits: 2 }).format(n)
  if (value >= 1e9) return `${fmt(value / 1e9)} tỷ`
  if (value >= 1e6) return `${fmt(value / 1e6)} tr`
  return new Intl.NumberFormat('vi-VN').format(value)
}

/** Ngày dạng "2026-12-31" (DateOnly từ API) → "31/12/2026" */
export function formatDateOnly(value) {
  if (!value) return ''
  const [y, m, d] = value.split('-')
  return `${d}/${m}/${y}`
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

/** Số lượng: 12.0000 → "12", 1.5 → "1,5" */
export function formatQty(value) {
  return new Intl.NumberFormat('vi-VN', { maximumFractionDigits: 2 }).format(value ?? 0)
}

/** Ngày hôm nay theo giờ máy dạng "2026-11-20" (cho <input type="date"> và API DateOnly) */
export function todayIso() {
  const d = new Date()
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10)
}

/** Nhập tiền: "1.250.000" → 1250000 */
export function parseMoney(text) {
  const n = Number(String(text ?? '').replace(/[^\d]/g, ''))
  return Number.isFinite(n) ? n : 0
}
