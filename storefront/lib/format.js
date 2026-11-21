export const money = (v) => `${Math.round(Number(v) || 0).toLocaleString('vi-VN')} đ`

export const dateVi = (iso) => {
  if (!iso) return ''
  const d = new Date(/[zZ]|[+-]\d\d:\d\d$/.test(iso) ? iso : `${iso}Z`)
  return d.toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export const initials = (name = '') => name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase()

export const priceText = (p) => (p.maxPrice ? `${money(p.price)} - ${money(p.maxPrice)}` : money(p.price))
