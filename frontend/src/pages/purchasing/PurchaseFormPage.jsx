import { useCallback, useEffect, useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { purchasingApi } from '../../api/retailApi'
import LineItems, { linesSubTotal } from '../../components/LineItems'
import MoneyInput from '../../components/MoneyInput'
import { purchaseStatus, RETAIL_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateOnly, formatMoney, todayIso } from '../../utils/format'
import PurchasingLayout from './PurchasingLayout'
import { SupplierFormModal } from './SuppliersPage'

const blank = () => ({ supplierId: '', orderDate: todayIso(), expectedDate: '', otherCost: 0, note: '' })

/**
 * Tạo / xem / sửa đơn nhập hàng.
 * Nháp → Gửi đặt hàng (chờ hàng về) → Nhận hàng: tự tạo phiếu nhập kho, cập nhật tồn và giá vốn bình quân.
 * Chi phí khác (vận chuyển...) được phân bổ vào giá vốn theo giá trị từng dòng.
 */
export default function PurchaseFormPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const location = useLocation()
  const { can } = useAuth()
  const [suppliers, setSuppliers] = useState([])
  const [order, setOrder] = useState(null)
  const [form, setForm] = useState(blank())
  const [lines, setLines] = useState([])
  const [error, setError] = useState('')
  const [message, setMessage] = useState(location.state?.message ?? '')
  const [busy, setBusy] = useState(false)
  const [addingSupplier, setAddingSupplier] = useState(false)

  const isNew = !id
  const editable = isNew ? can(RETAIL_PERMISSIONS.PURCHASING_CREATE) : order?.status === 'draft' && can(RETAIL_PERMISSIONS.PURCHASING_EDIT)
  const canAct = can(RETAIL_PERMISSIONS.PURCHASING_EDIT)

  const loadSuppliers = useCallback(() => purchasingApi.listSuppliers({ pageSize: 100 }).then((r) => setSuppliers(r.items)).catch(() => {}), [])
  useEffect(() => { loadSuppliers() }, [loadSuppliers])

  const fill = useCallback((p) => {
    setOrder(p)
    setForm({ supplierId: p.supplierId, orderDate: p.orderDate, expectedDate: p.expectedDate ?? '', otherCost: p.otherCost, note: p.note ?? '' })
    setLines(p.lines.map((l) => ({ ...l })))
  }, [])

  useEffect(() => {
    setError('')
    if (isNew) { setOrder(null); setForm(blank()); setLines([]); return }
    purchasingApi.get(id).then(fill).catch((err) => setError(getErrorMessage(err)))
  }, [id, isNew, fill])

  useEffect(() => { if (location.state?.message) setMessage(location.state.message) }, [location.state])

  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })
  const subTotal = linesSubTotal(lines)
  const total = subTotal + (Number(form.otherCost) || 0)

  const save = async (confirm) => {
    setError(''); setMessage('')
    if (!form.supplierId) return setError('Chọn nhà cung cấp.')
    if (lines.length === 0) return setError('Thêm ít nhất 1 sản phẩm.')
    if (lines.some((l) => !(Number(l.quantity) > 0))) return setError('Số lượng phải lớn hơn 0.')
    const body = {
      supplierId: Number(form.supplierId), orderDate: form.orderDate, expectedDate: form.expectedDate || null, warehouseId: order?.warehouseId ?? null,
      otherCost: Number(form.otherCost) || 0, note: form.note || null,
      lines: lines.map((l) => ({ productId: l.productId, quantity: Number(l.quantity), unitPrice: Number(l.unitPrice), discountPercent: Number(l.discountPercent) || 0 })),
      rowVersion: order?.rowVersion ?? null,
    }
    setBusy(true)
    try {
      let saved = isNew ? await purchasingApi.create(body) : await purchasingApi.update(order.id, body)
      if (confirm) saved = await purchasingApi.confirm(saved.id)
      const msg = confirm ? 'Đã gửi đặt hàng. Khi hàng về bấm "Nhận hàng" để nhập kho.' : 'Đã lưu đơn nháp.'
      if (isNew) navigate(`/purchasing/orders/${saved.id}`, { replace: true, state: { message: msg } })
      else { fill(saved); setMessage(msg) }
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  const act = async (fn, msg) => {
    setError(''); setMessage('')
    setBusy(true)
    try { fill(await fn()); setMessage(msg) } catch (err) { setError(getErrorMessage(err)) } finally { setBusy(false) }
  }

  if (!isNew && !order) {
    return <PurchasingLayout>{error ? <><div className="alert error">{error}</div><Link to="/purchasing/orders">← Danh sách đơn nhập</Link></> : <p className="muted">Đang tải...</p>}</PurchasingLayout>
  }
  const st = order ? purchaseStatus(order.status) : null

  return (
    <PurchasingLayout>
      <div className="breadcrumb"><Link to="/purchasing/orders">Đơn nhập hàng</Link> / {order?.docNo ?? 'Tạo đơn nhập'}</div>
      <div className="page-head">
        <div>
          <h1>{order ? `Đơn nhập ${order.docNo}` : 'Tạo đơn nhập hàng'} {st && <span className={`pill ${st.css} small-pill`}>{st.label}</span>}</h1>
          {order?.receiptDocNo && <div className="muted small">Phiếu nhập kho: <Link to="/inventory/documents">{order.receiptDocNo}</Link></div>}
        </div>
        <div className="head-actions">
          {order && canAct && order.status === 'draft' && (
            <button className="btn primary" disabled={busy} onClick={() => save(true)}><i className="ti ti-send" aria-hidden="true" /> Gửi đặt hàng</button>
          )}
          {order && canAct && order.status === 'confirmed' && (
            <button className="btn primary" disabled={busy}
              onClick={() => act(() => purchasingApi.receive(order.id), 'Đã nhận hàng: tồn kho và giá vốn đã cập nhật.')}>
              <i className="ti ti-package-import" aria-hidden="true" /> Nhận hàng vào kho
            </button>
          )}
          {order && canAct && ['draft', 'confirmed'].includes(order.status) && (
            <button className="btn ghost danger" disabled={busy}
              onClick={() => window.confirm(`Hủy đơn nhập ${order.docNo}?`) && act(() => purchasingApi.cancel(order.id), 'Đã hủy đơn nhập.')}>Hủy đơn</button>
          )}
        </div>
      </div>

      {message && <div className="alert success">{message}</div>}
      {error && <div className="alert error">{error}</div>}

      <div className="order-grid">
        <div>
          <div className="card">
            <div className="form-grid">
              <label className="span2">Nhà cung cấp *
                <div className="inline-add">
                  <select value={form.supplierId} onChange={update('supplierId')} disabled={!editable}>
                    <option value="">Chọn nhà cung cấp</option>
                    {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name} ({s.code})</option>)}
                  </select>
                  {editable && can(RETAIL_PERMISSIONS.PURCHASING_CREATE) && (
                    <button type="button" className="btn" onClick={() => setAddingSupplier(true)} title="Thêm nhà cung cấp" aria-label="Thêm nhà cung cấp">
                      <i className="ti ti-plus" aria-hidden="true" />
                    </button>
                  )}
                </div>
              </label>
              <label>Ngày đặt
                {editable ? <input type="date" value={form.orderDate} onChange={update('orderDate')} /> : <input value={formatDateOnly(form.orderDate)} disabled />}
              </label>
              <label>Dự kiến hàng về
                {editable ? <input type="date" value={form.expectedDate} onChange={update('expectedDate')} /> : <input value={formatDateOnly(form.expectedDate)} disabled />}
              </label>
            </div>
          </div>

          <LineItems lines={lines} onChange={setLines} mode="purchase" readOnly={!editable} showReceived={order?.status === 'completed'} />

          <label className="top-gap">Ghi chú
            <textarea rows={2} value={form.note} onChange={update('note')} disabled={!editable} />
          </label>
        </div>

        <aside className="card summary">
          <div className="sum-row"><span>Tiền hàng</span><b>{formatMoney(subTotal)}</b></div>
          <div className="sum-row">
            <span>Chi phí khác <span className="hint-inline">(vận chuyển, bốc xếp)</span></span>
            {editable ? <MoneyInput className="sum-input" value={form.otherCost} onChange={(v) => setForm({ ...form, otherCost: v })} aria-label="Chi phí khác" />
              : <span>{formatMoney(form.otherCost)}</span>}
          </div>
          <div className="sum-row total"><span>Tổng tiền</span><b>{formatMoney(total)}</b></div>
          {editable && (
            <div className="summary-actions">
              <button className="btn primary block" disabled={busy} onClick={() => save(true)}>
                <i className="ti ti-send" aria-hidden="true" /> {isNew ? 'Tạo & gửi đặt hàng' : 'Lưu & gửi đặt hàng'}
              </button>
              <button className="btn block" disabled={busy} onClick={() => save(false)}>{isNew ? 'Lưu nháp' : 'Lưu thay đổi'}</button>
              <p className="hint-inline">Chi phí khác được cộng vào giá vốn từng sản phẩm theo tỷ lệ giá trị khi nhận hàng.</p>
            </div>
          )}
        </aside>
      </div>

      {addingSupplier && (
        <SupplierFormModal onClose={() => setAddingSupplier(false)}
          onSaved={async (s) => { setAddingSupplier(false); await loadSuppliers(); setForm((f) => ({ ...f, supplierId: s.id })) }} />
      )}
    </PurchasingLayout>
  )
}
