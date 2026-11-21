import { useCallback, useEffect, useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { salesApi } from '../../api/retailApi'
import CustomerPicker from '../../components/CustomerPicker'
import LineItems, { linesSubTotal } from '../../components/LineItems'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import { orderStatus, PAYMENT_STATUSES, RETAIL_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateTime, formatMoney, formatQty } from '../../utils/format'
import OrdersLayout, { useSalesLookups } from './OrdersLayout'
import ReturnModal from './ReturnModal'
import { ShipmentFormModal, useLogisticsLookups } from '../logistics/LogisticsShared'
import { shipmentStatus } from '../../constants'
import { promotionCheck } from '../../api/phase3Api'

const blankForm = (warehouseId) => ({
  customer: null, channel: 'direct', warehouseId: warehouseId ?? '', receiverName: '', receiverPhone: '', shippingAddress: '',
  shippingFee: 0, discountAmount: 0, paymentMethodCode: 'cash', note: '',
})

function PaymentModal({ order, methods, onClose, onDone }) {
  const [amount, setAmount] = useState(order.amountDue)
  const [method, setMethod] = useState(order.paymentMethodCode && order.paymentMethodCode !== 'cod' ? order.paymentMethodCode : 'cash')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const submit = async (e) => {
    e.preventDefault()
    setBusy(true)
    try { onDone(await salesApi.pay(order.id, amount, method), `Đã ghi nhận thu ${formatMoney(amount)}.`) } catch (err) { setError(getErrorMessage(err)); setBusy(false) }
  }
  return (
    <Modal title={`Thu tiền đơn ${order.docNo}`} onClose={onClose} size="small">
      <form onSubmit={submit}>
        <p className="muted">Còn phải thu: <b>{formatMoney(order.amountDue)}</b></p>
        <label>Số tiền<MoneyInput value={amount} onChange={setAmount} autoFocus /></label>
        <label>Hình thức
          <select value={method} onChange={(e) => setMethod(e.target.value)}>
            {methods.map((m) => <option key={m.code} value={m.code}>{m.name}</option>)}
          </select>
        </label>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy || amount <= 0}>Ghi nhận</button>
        </div>
      </form>
    </Modal>
  )
}

function CancelModal({ order, onClose, onDone }) {
  const [reason, setReason] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const submit = async (e) => {
    e.preventDefault()
    if (!reason.trim()) return setError('Nhập lý do hủy.')
    setBusy(true)
    try { onDone(await salesApi.cancel(order.id, reason.trim()), 'Đã hủy đơn.') } catch (err) { setError(getErrorMessage(err)); setBusy(false) }
  }
  return (
    <Modal title={`Hủy đơn ${order.docNo}`} onClose={onClose} size="small">
      <form onSubmit={submit}>
        {order.status === 'confirmed' && <p className="hint-inline">Đơn đã xuất kho: hủy sẽ tự tạo phiếu nhập trả hàng về kho.</p>}
        <label>Lý do hủy *<textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} autoFocus placeholder="Khách đổi ý / hết hàng / giao không thành công..." /></label>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Đóng</button>
          <button className="btn danger-fill" disabled={busy}>Hủy đơn</button>
        </div>
      </form>
    </Modal>
  )
}

/**
 * Tạo / xem / sửa đơn bán (cùng 1 trang).
 * Nháp: sửa thoải mái. Xác nhận = xuất kho (khóa sửa). Hoàn thành = đã giao xong. Hủy đơn đã xuất kho thì hàng về lại kho.
 */
export default function OrderFormPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const location = useLocation()
  const { can } = useAuth()
  const lookups = useSalesLookups()
  const logistics = useLogisticsLookups()
  const [order, setOrder] = useState(null)
  const [form, setForm] = useState(blankForm())
  const [lines, setLines] = useState([])
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [dialog, setDialog] = useState(null)
  const [promoCode, setPromoCode] = useState('')
  const [promo, setPromo] = useState(null)        // { code, name, discount } - mã đã áp dụng
  const [promoError, setPromoError] = useState('')

  const isNew = !id
  const editable = isNew ? can(RETAIL_PERMISSIONS.ORDER_CREATE) : order?.status === 'draft' && can(RETAIL_PERMISSIONS.ORDER_EDIT)
  const canAct = can(RETAIL_PERMISSIONS.ORDER_EDIT)

  const fill = useCallback((o) => {
    setOrder(o)
    setForm({
      customer: o.isWalkIn ? null : { id: o.customerId, name: o.customerName },
      channel: o.channel, warehouseId: o.warehouseId ?? '', receiverName: o.receiverName ?? '', receiverPhone: o.receiverPhone ?? '',
      shippingAddress: o.shippingAddress ?? '', shippingFee: o.shippingFee, discountAmount: o.discountAmount - (o.promotionDiscount ?? 0),
      paymentMethodCode: o.paymentMethodCode ?? '', note: o.note ?? '',
    })
    setLines(o.lines.map((l) => ({ ...l })))
    setPromoCode(o.promotionCode ?? '')
    setPromo(o.promotionCode ? { code: o.promotionCode, discount: o.promotionDiscount } : null)
    setPromoError('')
  }, [])

  useEffect(() => {
    setError(''); setMessage('')
    if (isNew) { setOrder(null); setForm(blankForm()); setLines([]); setPromo(null); setPromoCode(''); return }
    salesApi.get(id).then(fill).catch((err) => setError(getErrorMessage(err)))
  }, [id, isNew, fill])

  // Kho mặc định khi tạo mới
  useEffect(() => {
    if (isNew && !form.warehouseId && lookups.warehouses.length) setForm((f) => ({ ...f, warehouseId: lookups.warehouses[0].id }))
  }, [isNew, form.warehouseId, lookups.warehouses])

  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })
  const subTotal = linesSubTotal(lines)
  const promoDiscount = promo?.discount ?? 0
  const total = subTotal - (Number(form.discountAmount) || 0) - promoDiscount + (Number(form.shippingFee) || 0)

  /** Kiểm tra mã giảm giá trên tiền hàng hiện tại (sau giảm giá tay). Tiền hàng / kênh đổi thì bấm áp dụng lại. */
  const applyPromo = async () => {
    setPromoError('')
    if (!promoCode.trim()) { setPromo(null); return }
    try {
      setPromo(await promotionCheck(promoCode.trim(), subTotal - (Number(form.discountAmount) || 0), Number(form.shippingFee) || 0, form.channel))
    } catch (err) { setPromo(null); setPromoError(getErrorMessage(err)) }
  }
  const online = form.channel !== 'direct'

  const body = () => ({
    customerId: form.customer?.id ?? null,
    channel: form.channel,
    warehouseId: form.warehouseId ? Number(form.warehouseId) : null,
    receiverName: form.receiverName || null, receiverPhone: form.receiverPhone || null, shippingAddress: form.shippingAddress || null,
    shippingFee: Number(form.shippingFee) || 0, discountAmount: Number(form.discountAmount) || 0,
    paymentMethodCode: form.paymentMethodCode || null, note: form.note || null,
    lines: lines.map((l) => ({ productId: l.productId, quantity: Number(l.quantity), unitPrice: Number(l.unitPrice), discountPercent: Number(l.discountPercent) || 0 })),
    rowVersion: order?.rowVersion ?? null,
    promotionCode: promo?.code ?? null,
  })

  const validate = () => {
    if (lines.length === 0) return 'Thêm ít nhất 1 sản phẩm.'
    if (lines.some((l) => !(Number(l.quantity) > 0))) return 'Số lượng phải lớn hơn 0.'
    if (form.discountAmount > subTotal) return 'Giảm giá không được lớn hơn tiền hàng.'
    return null
  }

  /** Lưu (tạo hoặc sửa). confirm = true thì xác nhận luôn (xuất kho). */
  const save = async (confirm) => {
    setError(''); setMessage('')
    const problem = validate()
    if (problem) return setError(problem)
    setBusy(true)
    try {
      let saved = isNew ? await salesApi.create(body()) : await salesApi.update(order.id, body())
      if (confirm) {
        try {
          saved = await salesApi.confirm(saved.id)
        } catch (err) {
          // Đơn đã lưu nháp nhưng xác nhận lỗi (VD thiếu hàng): mở đơn nháp và báo lỗi
          if (isNew) navigate(`/orders/${saved.id}`, { replace: true })
          else fill(saved)
          setError(getErrorMessage(err))
          return
        }
      }
      if (isNew) navigate(`/orders/${saved.id}`, { replace: true, state: { message: confirm ? 'Đã tạo và xác nhận đơn, hàng đã xuất kho.' : 'Đã lưu đơn nháp.' } })
      else { fill(saved); setMessage(confirm ? 'Đã xác nhận đơn, hàng đã xuất kho.' : 'Đã lưu đơn.') }
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  const act = async (fn, okMessage) => {
    setError(''); setMessage('')
    setBusy(true)
    try { fill(await fn()); setMessage(okMessage) } catch (err) { setError(getErrorMessage(err)) } finally { setBusy(false) }
  }

  const done = (saved, msg) => { setDialog(null); fill(saved); setMessage(msg) }

  // Thông báo truyền qua navigate state (sau khi tạo đơn)
  useEffect(() => {
    if (location.state?.message) setMessage(location.state.message)
  }, [location.state])

  if (!isNew && !order) {
    return <OrdersLayout>{error ? <><div className="alert error">{error}</div><Link to="/orders">← Danh sách đơn</Link></> : <p className="muted">Đang tải...</p>}</OrdersLayout>
  }

  const st = order ? orderStatus(order.status) : null

  return (
    <OrdersLayout>
      <div className="breadcrumb"><Link to="/orders">Đơn hàng</Link> / {order?.docNo ?? 'Tạo đơn'}</div>
      <div className="page-head">
        <div>
          <h1>{order ? `Đơn ${order.docNo}` : 'Tạo đơn hàng'} {st && <span className={`pill ${st.css} small-pill`}>{st.label}</span>}</h1>
          {order && <div className="muted small">Ngày {formatDateTime(order.orderDate)}{order.confirmedAt ? ` · xác nhận ${formatDateTime(order.confirmedAt)}` : ''}</div>}
        </div>
        <div className="head-actions">
          {order && canAct && order.status === 'draft' && (
            <button className="btn primary" disabled={busy} onClick={() => save(true)}><i className="ti ti-check" aria-hidden="true" /> Xác nhận & xuất kho</button>
          )}
          {order && canAct && ['confirmed', 'completed'].includes(order.status) && order.amountDue > 0 && (
            <button className="btn primary" disabled={busy} onClick={() => setDialog('pay')}><i className="ti ti-cash" aria-hidden="true" /> Thu tiền</button>
          )}
          {order && canAct && order.status === 'confirmed' && (
            <button className="btn" disabled={busy} onClick={() => act(() => salesApi.complete(order.id), 'Đơn đã hoàn thành.')}><i className="ti ti-circle-check" aria-hidden="true" /> Hoàn thành</button>
          )}
          {order && canAct && order.status === 'confirmed' && order.channel !== 'direct' && !order.links?.shipmentId && can('logistics.create') && (
            <button className="btn" disabled={busy} onClick={() => setDialog('ship')}><i className="ti ti-truck" aria-hidden="true" /> Tạo vận đơn</button>
          )}
          {order && canAct && ['confirmed', 'completed'].includes(order.status) && order.lines.some((l) => l.quantity > (l.qtyReturned ?? 0)) && (
            <button className="btn" disabled={busy} onClick={() => setDialog('return')}><i className="ti ti-arrow-back-up" aria-hidden="true" /> Trả hàng</button>
          )}
          {order && can('support.create') && order.status !== 'draft' && (
            <button className="btn ghost" onClick={() => navigate('/support', { state: { preset: { customer: order.isWalkIn ? null : { id: order.customerId, name: order.customerName }, salesOrderId: order.id, orderDocNo: order.docNo, subject: `Hỗ trợ đơn ${order.docNo}` } } })}>
              <i className="ti ti-headset" aria-hidden="true" /> Tạo phiếu CSKH
            </button>
          )}
          {order && canAct && ['draft', 'confirmed'].includes(order.status) && (
            <button className="btn ghost danger" disabled={busy} onClick={() => setDialog('cancel')}>Hủy đơn</button>
          )}
        </div>
      </div>

      {message && <div className="alert success">{message}</div>}
      {error && <div className="alert error">{error}</div>}
      {order?.status === 'cancelled' && <div className="status-note lost">Đơn đã hủy{order.cancelReason ? `: ${order.cancelReason}` : ''}</div>}
      {order?.links && (order.links.quotationId || order.links.shipmentId || order.links.ticketCount > 0) && (
        <div className="link-chips">
          {order.links.quotationId && <Link className="link-chip" to={`/quotations/${order.links.quotationId}`}><i className="ti ti-file-dollar" aria-hidden="true" /> Từ báo giá {order.links.quotationDocNo}</Link>}
          {order.links.shipmentId && <Link className="link-chip" to="/logistics"><i className="ti ti-truck-delivery" aria-hidden="true" /> Vận đơn {order.links.shipmentDocNo} · {shipmentStatus(order.links.shipmentStatus).label}</Link>}
          {order.links.ticketCount > 0 && <Link className="link-chip" to="/support"><i className="ti ti-headset" aria-hidden="true" /> {order.links.ticketCount} phiếu CSKH</Link>}
        </div>
      )}

      <div className="order-grid">
        <div>
          <div className="card">
            <div className="form-grid">
              <label>Khách hàng
                {editable
                  ? <CustomerPicker value={form.customer} onChange={(c) => setForm({ ...form, customer: c })} />
                  : <input value={order.customerName} disabled />}
                {editable && !form.customer && <span className="hint-inline">Để trống = Khách lẻ</span>}
              </label>
              <label>Kênh bán
                <select value={form.channel} onChange={update('channel')} disabled={!editable}>
                  {lookups.channels.map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}
                </select>
              </label>
              {online && (
                <>
                  <label>Người nhận<input value={form.receiverName} onChange={update('receiverName')} disabled={!editable} placeholder="Tên người nhận hàng" /></label>
                  <label>SĐT người nhận<input value={form.receiverPhone} onChange={update('receiverPhone')} disabled={!editable} placeholder="0912345678" /></label>
                  <label className="span2">Địa chỉ giao hàng<input value={form.shippingAddress} onChange={update('shippingAddress')} disabled={!editable} /></label>
                </>
              )}
              {lookups.warehouses.length > 1 && (
                <label>Xuất từ kho
                  <select value={form.warehouseId} onChange={update('warehouseId')} disabled={!editable}>
                    {lookups.warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
                  </select>
                </label>
              )}
            </div>
          </div>

          <LineItems lines={lines} onChange={setLines} mode="sale" readOnly={!editable} warehouseId={form.warehouseId} />

          <label className="top-gap">Ghi chú
            <textarea rows={2} value={form.note} onChange={update('note')} disabled={!editable} placeholder="Giao giờ hành chính, gói quà..." />
          </label>
          {order?.returns?.length > 0 && (
            <>
              <div className="section-head"><h2>Khách đã trả hàng</h2></div>
              <div className="table-wrap">
                <table className="grid">
                  <thead><tr><th>Phiếu trả</th><th>Sản phẩm</th><th className="num">Giá trị</th></tr></thead>
                  <tbody>
                    {order.returns.map((r) => (
                      <tr key={r.id}>
                        <td><b>{r.docNo}</b><div className="muted small">{formatDateTime(r.returnDate)}{r.reason ? ` · ${r.reason}` : ''}</div></td>
                        <td>{r.lines.map((l) => <div key={l.productId} className="small">{formatQty(l.quantity)} × {l.name}{l.condition === 'damaged' ? ' (hỏng)' : ''}</div>)}</td>
                        <td className="num">{formatMoney(r.totalAmount)}<div className="muted small">{r.refundMethod === 'credit_note' ? 'trừ công nợ' : r.refundMethod === 'cash' ? 'hoàn tiền mặt' : 'hoàn chuyển khoản'}</div></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </div>

        <aside className="card summary">
          <div className="sum-row"><span>Tiền hàng</span><b>{formatMoney(subTotal)}</b></div>
          <div className="sum-row">
            <span>Giảm giá đơn</span>
            {editable ? <MoneyInput className="sum-input" value={form.discountAmount} onChange={(v) => setForm({ ...form, discountAmount: v })} aria-label="Giảm giá" />
              : <span>{formatMoney(form.discountAmount)}</span>}
          </div>
          <div className="sum-row">
            <span>Phí giao hàng</span>
            {editable ? <MoneyInput className="sum-input" value={form.shippingFee} onChange={(v) => setForm({ ...form, shippingFee: v })} aria-label="Phí giao hàng" />
              : <span>{formatMoney(form.shippingFee)}</span>}
          </div>
          {editable && (
            <div className="promo-row top-gap">
              <input value={promoCode} onChange={(e) => { setPromoCode(e.target.value); if (promo) setPromo(null) }} placeholder="Mã giảm giá"
                onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); applyPromo() } }} aria-label="Mã giảm giá" />
              <button type="button" className="btn" onClick={applyPromo}>Áp dụng</button>
            </div>
          )}
          {promoError && <p className="error small">{promoError}</p>}
          {promo && (
            <div className="sum-row"><span><i className="ti ti-ticket" aria-hidden="true" /> Mã {promo.code}</span>
              <span className="money-out">-{formatMoney(promo.discount)}
                {editable && <button type="button" className="btn ghost" onClick={() => { setPromo(null); setPromoCode('') }} aria-label="Bỏ mã"><i className="ti ti-x" aria-hidden="true" /></button>}</span></div>
          )}
          <div className="sum-row total"><span>Khách phải trả</span><b>{formatMoney(order && !editable ? order.totalAmount + (order.returnedAmount ?? 0) : total)}</b></div>
          {order?.returnedAmount > 0 && <div className="sum-row"><span>Hàng trả lại</span><span className="money-out">-{formatMoney(order.returnedAmount)}</span></div>}
          {order && order.status !== 'draft' && order.status !== 'cancelled' && (
            <>
              <div className="sum-row"><span>Đã thu</span><span className="ok-text">{formatMoney(order.amountPaid)}</span></div>
              <div className="sum-row"><span>Còn phải thu</span><b className={order.amountDue > 0 ? 'warn-text' : ''}>{formatMoney(order.amountDue)}</b></div>
              <div className="sum-row muted"><span>{PAYMENT_STATUSES[order.paymentStatus]}</span></div>
              <div className="sum-row profit"><span>Lãi gộp</span><span>{formatMoney(Math.round(order.grossProfit))}</span></div>
            </>
          )}
          <label className="top-gap">Hình thức thanh toán
            <select value={form.paymentMethodCode} onChange={update('paymentMethodCode')} disabled={!editable}>
              <option value="">Chưa chọn</option>
              {lookups.paymentMethods.map((m) => <option key={m.code} value={m.code}>{m.name}</option>)}
            </select>
          </label>

          {editable && (
            <div className="summary-actions">
              <button className="btn primary block" disabled={busy} onClick={() => save(true)}>
                <i className="ti ti-check" aria-hidden="true" /> {isNew ? 'Tạo & xác nhận đơn' : 'Lưu & xác nhận'}
              </button>
              <button className="btn block" disabled={busy} onClick={() => save(false)}>{isNew ? 'Lưu nháp' : 'Lưu thay đổi'}</button>
              <p className="hint-inline">Xác nhận = trừ tồn kho. Đơn nháp chưa trừ kho, sửa thoải mái.</p>
            </div>
          )}
        </aside>
      </div>

      {dialog === 'pay' && <PaymentModal order={order} methods={lookups.paymentMethods} onClose={() => setDialog(null)} onDone={done} />}
      {dialog === 'cancel' && <CancelModal order={order} onClose={() => setDialog(null)} onDone={done} />}
      {dialog === 'return' && <ReturnModal order={order} onClose={() => setDialog(null)} onDone={(o) => done(o, 'Đã ghi nhận trả hàng: hàng tốt đã nhập lại kho, tiền hoàn đã ghi phiếu chi.')} />}
      {dialog === 'ship' && (
        <ShipmentFormModal order={{ ...order, shippingAddress: order.shippingAddress }} carriers={logistics.carriers} onClose={() => setDialog(null)}
          onSaved={async (s) => { setDialog(null); fill(await salesApi.get(order.id)); setMessage(`Đã tạo vận đơn ${s.docNo}.`) }} />
      )}
    </OrdersLayout>
  )
}
