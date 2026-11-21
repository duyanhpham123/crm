import { useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { returnApi } from '../../api/phase2Api'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import { REFUND_METHODS } from '../../constants'
import { formatMoney, formatQty } from '../../utils/format'

/** Khách trả hàng: chọn sản phẩm + số lượng, tình trạng hàng, cách hoàn tiền. */
export default function ReturnModal({ order, onClose, onDone }) {
  const returnable = order.lines.filter((l) => l.quantity - (l.qtyReturned ?? 0) > 0)
  const [qty, setQty] = useState(() => Object.fromEntries(returnable.map((l) => [l.id, 0])))
  const [cond, setCond] = useState(() => Object.fromEntries(returnable.map((l) => [l.id, 'good'])))
  const [reason, setReason] = useState('')
  const [method, setMethod] = useState(order.amountPaid > 0 ? 'cash' : 'credit_note')
  const [refund, setRefund] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  // Giảm giá cấp đơn chia đều theo giá trị dòng (khớp backend)
  const factor = order.subTotal ? (order.subTotal - order.discountAmount) / order.subTotal : 0
  const unit = (l) => (l.lineTotal / l.quantity) * factor
  const value = Math.min(order.totalAmount - order.shippingFee, returnable.reduce((s, l) => s + Math.round((Number(qty[l.id]) || 0) * unit(l)), 0))
  const mustRefund = Math.max(0, order.amountPaid - (order.totalAmount - value))
  const suggested = method === 'credit_note' ? 0 : Math.min(value, order.amountPaid)
  const refundAmount = refund ?? suggested

  const submit = async () => {
    setError('')
    const lines = returnable.filter((l) => Number(qty[l.id]) > 0).map((l) => ({ salesOrderLineId: l.id, quantity: Number(qty[l.id]), condition: cond[l.id] }))
    if (lines.length === 0) return setError('Nhập số lượng khách trả.')
    setBusy(true)
    try {
      onDone(await returnApi.create(order.id, { lines, reason: reason || null, refundMethod: method, refundAmount: method === 'credit_note' ? 0 : refundAmount }))
    } catch (e) { setError(getErrorMessage(e)); setBusy(false) }
  }

  return (
    <Modal title={`Trả hàng - đơn ${order.docNo}`} onClose={onClose} size="large">
      <div className="table-wrap">
        <table className="grid lines-grid">
          <thead><tr><th>Sản phẩm</th><th className="num">Đã mua</th><th className="num qty-col">Trả</th><th>Tình trạng</th><th className="num">Giá trị</th></tr></thead>
          <tbody>
            {returnable.length === 0 && <tr><td colSpan={5} className="muted center">Khách đã trả hết hàng của đơn này.</td></tr>}
            {returnable.map((l) => (
              <tr key={l.id}>
                <td>{l.name}<div className="muted small">{l.code}</div></td>
                <td className="num">{formatQty(l.quantity)}{l.qtyReturned ? <div className="muted small">đã trả {formatQty(l.qtyReturned)}</div> : null}</td>
                <td className="num"><input type="number" className="qty-input" min="0" max={l.quantity - (l.qtyReturned ?? 0)} value={qty[l.id]}
                  onChange={(e) => { setQty({ ...qty, [l.id]: e.target.value }); setRefund(null) }} aria-label={`Số lượng trả ${l.code}`} /></td>
                <td><select value={cond[l.id]} onChange={(e) => setCond({ ...cond, [l.id]: e.target.value })} aria-label={`Tình trạng ${l.code}`}>
                  <option value="good">Còn bán được (nhập lại kho)</option><option value="damaged">Hỏng / lỗi (không nhập kho)</option></select></td>
                <td className="num">{formatMoney(Math.round((Number(qty[l.id]) || 0) * unit(l)))}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="form-grid top-gap">
        <label className="span2">Lý do trả<input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Không vừa size / lỗi đường may / giao nhầm màu" /></label>
        <label>Hoàn tiền
          <select value={method} onChange={(e) => { setMethod(e.target.value); setRefund(null) }}>
            {REFUND_METHODS.map((m) => <option key={m.value} value={m.value}>{m.label}</option>)}
          </select>
        </label>
        {method !== 'credit_note' && (
          <label>Số tiền hoàn<MoneyInput value={refundAmount} onChange={setRefund} />
            {mustRefund > 0 && <span className="hint-inline">Khách đã trả đủ, tối thiểu {formatMoney(mustRefund)}</span>}</label>
        )}
      </div>
      <div className="sum-row total"><span>Giá trị hàng trả</span><b>{formatMoney(value)}</b></div>
      {error && <p className="error">{error}</p>}
      <div className="modal-foot">
        <button className="btn" onClick={onClose}>Hủy</button>
        <button className="btn primary" disabled={busy || value <= 0} onClick={submit}>Ghi nhận trả hàng</button>
      </div>
    </Modal>
  )
}
