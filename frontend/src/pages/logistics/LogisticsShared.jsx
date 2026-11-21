import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { logisticsApi } from '../../api/phase2Api'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import { COD_STATUSES, PHASE2_PERMISSIONS, shipmentStatus } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import ModuleLayout from '../../layouts/ModuleLayout'
import { formatDateTime, formatMoney } from '../../utils/format'

const MENU = [
  { to: '/logistics', icon: 'truck-delivery', label: 'Vận đơn', end: true },
  { to: '/logistics/ready', icon: 'package', label: 'Đơn chờ giao' },
  { to: '/logistics/cod', icon: 'cash', label: 'Đối soát COD' },
]

export function LogisticsLayout({ children }) {
  return <ModuleLayout title="Vận chuyển" icon="truck-delivery" color="#0F6E56" menu={MENU}>{children}</ModuleLayout>
}

export function useLogisticsLookups() {
  const [lookups, setLookups] = useState({ carriers: [], statuses: [], bankAccounts: [] })
  useEffect(() => { logisticsApi.lookups().then(setLookups).catch(() => {}) }, [])
  return lookups
}

/**
 * Tạo vận đơn cho 1 đơn đã xác nhận (hoặc sửa vận đơn chưa lấy hàng).
 * order: { id, docNo, receiverName, receiverPhone, shippingAddress, amountDue, paymentMethodCode }
 */
export function ShipmentFormModal({ order, shipment, carriers, onClose, onSaved }) {
  const isNew = !shipment
  const [form, setForm] = useState(() => ({
    carrierId: shipment?.carrierId ?? carriers[0]?.id ?? '',
    trackingNo: shipment?.trackingNo ?? '', serviceType: shipment?.serviceType ?? 'Tiêu chuẩn',
    receiverName: shipment?.receiverName ?? order?.receiverName ?? '', receiverPhone: shipment?.receiverPhone ?? order?.receiverPhone ?? '',
    street: shipment?.street ?? order?.shippingAddress ?? '', packageCount: shipment?.packageCount ?? 1, weightGram: shipment?.weightGram ?? 500,
    codAmount: shipment?.codAmount ?? (order?.paymentMethodCode === 'cod' || order?.amountDue > 0 ? order?.amountDue ?? 0 : 0),
    shippingFee: shipment?.shippingFee ?? 25000, feePayer: shipment?.feePayer ?? 'sender', note: shipment?.note ?? '',
  }))
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const update = (f) => (e) => setForm({ ...form, [f]: e.target.value })
  const maxCod = isNew ? order?.amountDue : shipment?.orderAmountDue

  const save = async (e) => {
    e.preventDefault()
    setError('')
    const body = { ...form, salesOrderId: order?.id ?? shipment?.orderId, carrierId: Number(form.carrierId), packageCount: Number(form.packageCount) || 1,
      weightGram: form.weightGram === '' ? null : Number(form.weightGram), trackingNo: form.trackingNo || null, note: form.note || null,
      rowVersion: shipment?.rowVersion ?? null }
    setBusy(true)
    try {
      onSaved(isNew ? await logisticsApi.create(body) : await logisticsApi.update(shipment.id, body))
    } catch (err) {
      setError(getErrorMessage(err))
      setBusy(false)
    }
  }

  return (
    <Modal title={isNew ? `Tạo vận đơn cho ${order.docNo}` : `Sửa vận đơn ${shipment.docNo}`} onClose={onClose}>
      <form onSubmit={save}>
        <div className="form-grid">
          <label>Hãng vận chuyển
            <select value={form.carrierId} onChange={update('carrierId')}>
              {carriers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </label>
          <label>Mã vận đơn của hãng<input value={form.trackingNo} onChange={update('trackingNo')} placeholder="Nhập sau khi hãng cấp" /></label>
          <label>Người nhận *<input value={form.receiverName} onChange={update('receiverName')} /></label>
          <label>SĐT người nhận *<input value={form.receiverPhone} onChange={update('receiverPhone')} /></label>
          <label className="span2">Địa chỉ giao *<input value={form.street} onChange={update('street')} /></label>
          <label>Tiền thu hộ (COD)
            <MoneyInput value={form.codAmount} onChange={(v) => setForm({ ...form, codAmount: v })} />
            <span className="hint-inline">Khách còn phải trả {formatMoney(maxCod ?? 0)}</span>
          </label>
          <label>Phí ship hãng tính<MoneyInput value={form.shippingFee} onChange={(v) => setForm({ ...form, shippingFee: v })} /></label>
          <label>Người trả phí ship
            <select value={form.feePayer} onChange={update('feePayer')}>
              <option value="sender">Shop trả (trừ vào COD)</option>
              <option value="receiver">Khách trả cho shipper</option>
            </select>
          </label>
          <label>Khối lượng (gram)<input type="number" min="0" value={form.weightGram} onChange={update('weightGram')} /></label>
          <label className="span2">Ghi chú cho shipper<input value={form.note} onChange={update('note')} placeholder="Cho xem hàng, không cho thử" /></label>
        </div>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : isNew ? 'Tạo vận đơn' : 'Lưu'}</button>
        </div>
      </form>
    </Modal>
  )
}

const ACTION_LABELS = {
  picked_up: { label: 'Hãng đã lấy hàng', icon: 'truck-loading', primary: true },
  in_transit: { label: 'Đang giao', icon: 'truck-delivery', primary: true },
  delivered: { label: 'Đã giao thành công', icon: 'circle-check', primary: true },
  failed: { label: 'Giao thất bại', icon: 'alert-triangle' },
  returning: { label: 'Hoàn hàng', icon: 'arrow-back-up' },
  returned: { label: 'Hàng đã về kho', icon: 'building-warehouse', primary: true },
  cancelled: { label: 'Hủy vận đơn', icon: 'x', danger: true },
}

/** Chi tiết vận đơn: hành trình + nút chuyển trạng thái. */
export function ShipmentModal({ id, carriers, onClose, onChanged }) {
  const { can } = useAuth()
  const [s, setS] = useState(null)
  const [error, setError] = useState('')
  const [note, setNote] = useState('')
  const [pending, setPending] = useState(null)
  const [editing, setEditing] = useState(false)
  const [busy, setBusy] = useState(false)
  const canEdit = can(PHASE2_PERMISSIONS.LOGISTICS_EDIT)

  useEffect(() => { logisticsApi.get(id).then(setS).catch((e) => setError(getErrorMessage(e))) }, [id])

  const change = async (status) => {
    if ((status === 'failed') && !note.trim()) { setPending(status); return setError('Nhập lý do giao thất bại.') }
    if (status === 'returned' && !window.confirm('Hàng đã về kho? Đơn hàng sẽ tự hủy và nhập lại kho.')) return
    if (status === 'cancelled' && !window.confirm('Hủy vận đơn này?')) return
    setBusy(true); setError('')
    try {
      const r = await logisticsApi.changeStatus(id, { status, note: note.trim() || null, location: null })
      setS(r); setNote(''); setPending(null); onChanged?.()
    } catch (err) { setError(getErrorMessage(err)) } finally { setBusy(false) }
  }

  if (editing) return <ShipmentFormModal shipment={s} carriers={carriers} onClose={() => setEditing(false)} onSaved={(r) => { setS(r); setEditing(false); onChanged?.() }} />

  return (
    <Modal title={s ? `Vận đơn ${s.docNo}` : 'Vận đơn'} onClose={onClose} size="large">
      {!s && !error && <p className="muted">Đang tải...</p>}
      {error && <div className="alert error">{error}</div>}
      {s && (
        <div className="detail-grid">
          <div>
            <dl className="info">
              <dt>Trạng thái</dt><dd><span className={`pill ${shipmentStatus(s.status).css}`}>{shipmentStatus(s.status).label}</span></dd>
              <dt>Đơn hàng</dt><dd>{s.orderId ? <Link to={`/orders/${s.orderId}`}>{s.orderDocNo}</Link> : '-'}</dd>
              <dt>Hãng</dt><dd>{s.carrierName}{s.trackingNo ? ` · ${s.trackingNo}` : ''}</dd>
              <dt>Người nhận</dt><dd>{s.receiverName} · {s.receiverPhone}<br /><span className="muted">{s.street}</span></dd>
              <dt>Thu hộ COD</dt><dd><b>{formatMoney(s.codAmount)}</b> <span className="muted small">({COD_STATUSES[s.codStatus]})</span></dd>
              <dt>Phí ship</dt><dd>{formatMoney(s.shippingFee)} <span className="muted small">({s.feePayer === 'sender' ? 'shop trả' : 'khách trả'})</span></dd>
              {s.failedReason && <><dt>Lý do lỗi</dt><dd className="error">{s.failedReason}</dd></>}
              {s.note && <><dt>Ghi chú</dt><dd>{s.note}</dd></>}
            </dl>
            {canEdit && s.nextStatuses.length > 0 && (
              <>
                <label>Ghi chú cập nhật {pending === 'failed' && '*'}<input value={note} onChange={(e) => setNote(e.target.value)} placeholder="VD: Khách hẹn giao lại chiều mai" /></label>
                <div className="status-actions">
                  {s.nextStatuses.map((st) => {
                    const a = ACTION_LABELS[st]
                    return (
                      <button key={st} disabled={busy} className={`btn${a.primary ? ' primary' : ''}${a.danger ? ' ghost danger' : ''}`} onClick={() => change(st)}>
                        <i className={`ti ti-${a.icon}`} aria-hidden="true" /> {a.label}
                      </button>
                    )
                  })}
                  {s.status === 'ready' && <button className="btn" onClick={() => setEditing(true)}><i className="ti ti-pencil" aria-hidden="true" /> Sửa</button>}
                </div>
              </>
            )}
          </div>
          <div>
            <h2>Hành trình</h2>
            <ul className="timeline">
              {s.events.map((e, i) => (
                <li key={i}>
                  <b>{shipmentStatus(e.status).label}</b>
                  <div className="small">{e.description}</div>
                  <div className="muted small">{formatDateTime(e.eventAt)}{e.location ? ` · ${e.location}` : ''}</div>
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </Modal>
  )
}
