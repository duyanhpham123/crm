'use client'

import Link from 'next/link'
import { useState } from 'react'
import { money } from '../lib/format'
import { useCart } from './Cart'

/** Giỏ hàng + form đặt hàng. Số tiền ở đây là tạm tính - ERP tính lại khi đặt và trả về tổng chính xác. */
export default function Checkout({ shippingFee, freeShippingFrom }) {
  const cart = useCart()
  const [form, setForm] = useState({ customerName: '', phone: '', email: '', address: '', note: '', paymentMethod: 'cod' })
  const [promo, setPromo] = useState({ code: '', applied: null, error: '' })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [result, setResult] = useState(null)
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })

  if (result) {
    return (
      <div className="card success">
        <h2>🎉 {result.message}</h2>
        <p>Mã đơn hàng: <b>{result.orderNo}</b></p>
        <table className="lines"><tbody>
          {result.lines.map((l) => <tr key={l.sku}><td>{l.name} × {l.quantity}</td><td className="num">{money(l.amount)}</td></tr>)}
          <tr><td>Tiền hàng</td><td className="num">{money(result.subTotal)}</td></tr>
          {result.discount > 0 && <tr><td>Giảm giá</td><td className="num">-{money(result.discount)}</td></tr>}
          <tr><td>Phí giao hàng</td><td className="num">{result.shippingFee ? money(result.shippingFee) : 'Miễn phí'}</td></tr>
          <tr className="total"><td>Tổng thanh toán</td><td className="num">{money(result.total)}</td></tr>
        </tbody></table>
        <Link href="/san-pham" className="btn">Tiếp tục mua sắm</Link>
      </div>
    )
  }
  if (!cart.ready) return <p className="muted">Đang tải giỏ hàng...</p>
  if (cart.items.length === 0) return <p>Giỏ hàng đang trống. <Link href="/san-pham">Xem sản phẩm →</Link></p>

  const ship = freeShippingFrom && cart.subTotal >= freeShippingFrom ? 0 : shippingFee
  const discount = promo.applied?.discount ?? 0

  const applyPromo = async () => {
    setPromo({ ...promo, error: '', applied: null })
    const res = await fetch(`/api/promo?code=${encodeURIComponent(promo.code)}&subTotal=${cart.subTotal}`)
    const data = await res.json()
    setPromo({ ...promo, applied: res.ok ? data : null, error: res.ok ? '' : data.error })
  }

  const submit = async (e) => {
    e.preventDefault()
    setBusy(true); setError('')
    try {
      const res = await fetch('/api/order', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...form, email: form.email || null, note: form.note || null, promotionCode: promo.applied?.code ?? null,
          items: cart.items.map((i) => ({ sku: i.sku, quantity: i.qty })) }),
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error)
      setResult(data)
      cart.clear()
    } catch (err) { setError(err.message) } finally { setBusy(false) }
  }

  return (
    <div className="checkout">
      <div>
        <table className="lines">
          <tbody>
            {cart.items.map((i) => (
              <tr key={i.sku}>
                <td><Link href={`/san-pham/${i.slug}`}><b>{i.name}</b></Link><div className="muted small">{[i.color, i.size].filter(Boolean).join(' / ')} · {money(i.price)}</div></td>
                <td><input type="number" min="1" max={Math.min(20, i.available ?? 20)} value={i.qty} onChange={(e) => cart.setQty(i.sku, Number(e.target.value) || 1)} aria-label={`Số lượng ${i.name}`} className="qty" /></td>
                <td className="num">{money(i.qty * i.price)}</td>
                <td><button type="button" className="link" onClick={() => cart.remove(i.sku)} aria-label={`Bỏ ${i.name}`}>✕</button></td>
              </tr>
            ))}
          </tbody>
        </table>
        <div className="promo">
          <input value={promo.code} onChange={(e) => setPromo({ ...promo, code: e.target.value.toUpperCase(), applied: null })} placeholder="Mã giảm giá" aria-label="Mã giảm giá" />
          <button type="button" className="btn" disabled={!promo.code} onClick={applyPromo}>Áp dụng</button>
        </div>
        {promo.error && <p className="error">{promo.error}</p>}
        {promo.applied && <p className="ok">Mã {promo.applied.code}: {promo.applied.name} (-{money(promo.applied.discount)})</p>}
        <table className="lines summary"><tbody>
          <tr><td>Tạm tính</td><td className="num">{money(cart.subTotal)}</td></tr>
          {discount > 0 && <tr><td>Giảm giá</td><td className="num">-{money(discount)}</td></tr>}
          <tr><td>Phí giao hàng</td><td className="num">{ship ? money(ship) : 'Miễn phí'}</td></tr>
          <tr className="total"><td>Tổng (tạm tính)</td><td className="num">{money(Math.max(0, cart.subTotal - discount) + ship)}</td></tr>
        </tbody></table>
        {freeShippingFrom && ship > 0 && <p className="muted small">Mua thêm {money(freeShippingFrom - cart.subTotal)} để được miễn phí giao hàng.</p>}
      </div>
      <form className="card" onSubmit={submit}>
        <h2>Thông tin giao hàng</h2>
        <label>Họ tên *<input value={form.customerName} onChange={u('customerName')} required minLength={2} maxLength={150} autoComplete="name" /></label>
        <label>Số điện thoại *<input value={form.phone} onChange={u('phone')} required type="tel" autoComplete="tel" placeholder="09xx xxx xxx" /></label>
        <label>Email<input value={form.email} onChange={u('email')} type="email" autoComplete="email" /></label>
        <label>Địa chỉ giao hàng *<textarea value={form.address} onChange={u('address')} required minLength={10} rows={2} placeholder="Số nhà, đường, phường/xã, quận/huyện, tỉnh/thành" autoComplete="street-address" /></label>
        <label>Ghi chú<textarea value={form.note} onChange={u('note')} rows={2} maxLength={500} /></label>
        <fieldset>
          <legend>Thanh toán</legend>
          <label className="radio"><input type="radio" name="pay" checked={form.paymentMethod === 'cod'} onChange={() => setForm({ ...form, paymentMethod: 'cod' })} /> Thanh toán khi nhận hàng (COD)</label>
          <label className="radio"><input type="radio" name="pay" checked={form.paymentMethod === 'bank_transfer'} onChange={() => setForm({ ...form, paymentMethod: 'bank_transfer' })} /> Chuyển khoản ngân hàng</label>
        </fieldset>
        {error && <p className="error">{error}</p>}
        <button className="btn primary block" disabled={busy}>{busy ? 'Đang đặt hàng...' : 'Đặt hàng'}</button>
      </form>
    </div>
  )
}
