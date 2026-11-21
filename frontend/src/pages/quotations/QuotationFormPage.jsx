import { useCallback, useEffect, useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { quotationApi } from '../../api/phase2Api'
import { companyInfoApi } from '../../api/phase3Api'
import CustomerPicker from '../../components/CustomerPicker'
import LineItems, { lineTotal, linesSubTotal } from '../../components/LineItems'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import { PHASE2_PERMISSIONS, quotationStatus } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateOnly, formatDateTime, formatMoney, formatQty, todayIso } from '../../utils/format'
import { QuotationsLayout } from './QuotationsPage'

const plusDays = (iso, days) => { const d = new Date(iso); d.setDate(d.getDate() + days); return d.toISOString().slice(0, 10) }
const DEFAULT_TERMS = 'Giá đã bao gồm VAT.\nThanh toán: chuyển khoản 50% khi đặt hàng, 50% khi nhận hàng.\nGiao hàng trong 3-5 ngày làm việc.'
const blank = () => ({ customer: null, quoteDate: todayIso(), validUntil: plusDays(todayIso(), 15), discountAmount: 0, shippingFee: 0, terms: DEFAULT_TERMS, note: '' })

/** Bản in báo giá gửi khách (chỉ hiện khi in / lưu PDF). */
function QuotePaper({ q, company }) {
  return (
    <div className="quote-paper print-only">
      <div className="quote-head">
        <div><b>{company?.name ?? ''}</b>{company?.shortName && <><br />{company.shortName}</>}
          {company?.address && <><br />{company.address}</>}{company?.phone && <><br />Hotline: {company.phone}</>}{company?.taxCode && <><br />MST: {company.taxCode}</>}</div>
        <div style={{ textAlign: 'right' }}>Số: <b>{q.docNo}</b>{q.revisionNo ? ` (sửa lần ${q.revisionNo})` : ''}<br />Ngày: {formatDateOnly(q.quoteDate)}<br />Hiệu lực đến: {formatDateOnly(q.validUntil)}</div>
      </div>
      <h2>BẢNG BÁO GIÁ</h2>
      <p>Kính gửi: <b>{q.customerName}</b>{q.customerPhone ? ` · ĐT: ${q.customerPhone}` : ''}{q.customerAddress ? ` · ${q.customerAddress}` : ''}</p>
      <table>
        <thead><tr><th>#</th><th>Sản phẩm</th><th className="num">SL</th><th className="num">Đơn giá</th><th className="num">CK</th><th className="num">Thành tiền</th></tr></thead>
        <tbody>
          {q.lines.map((l, i) => (
            <tr key={l.id}><td>{i + 1}</td><td>{l.name}<br /><small>{l.code}</small></td><td className="num">{formatQty(l.quantity)}</td>
              <td className="num">{formatMoney(l.unitPrice)}</td><td className="num">{l.discountPercent ? `${formatQty(l.discountPercent)}%` : ''}</td><td className="num">{formatMoney(l.lineTotal)}</td></tr>
          ))}
          <tr><td colSpan={5} className="num">Tiền hàng</td><td className="num">{formatMoney(q.subTotal)}</td></tr>
          {q.discountAmount > 0 && <tr><td colSpan={5} className="num">Giảm giá</td><td className="num">-{formatMoney(q.discountAmount)}</td></tr>}
          {q.shippingFee > 0 && <tr><td colSpan={5} className="num">Phí giao hàng</td><td className="num">{formatMoney(q.shippingFee)}</td></tr>}
          <tr><td colSpan={5} className="num"><b>Tổng cộng</b></td><td className="num"><b>{formatMoney(q.totalAmount)}</b></td></tr>
        </tbody>
      </table>
      {q.terms && <><b>Điều khoản:</b><p style={{ whiteSpace: 'pre-wrap' }}>{q.terms}</p></>}
      {company?.returnPolicy && <><b>Chính sách đổi trả:</b><p style={{ whiteSpace: 'pre-wrap' }}>{company.returnPolicy}</p></>}
      {company?.printFooter && <p style={{ textAlign: 'center', fontStyle: 'italic' }}>{company.printFooter}</p>}
      <p style={{ textAlign: 'right', marginTop: 40 }}>Người lập báo giá<br /><br /><br /><b>{q.salespersonName}</b></p>
    </div>
  )
}

/** Tạo / xem / sửa báo giá. Gửi khách → khách đồng ý thì tạo đơn hàng nháp đúng giá. */
export default function QuotationFormPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const location = useLocation()
  const { can } = useAuth()
  const [quote, setQuote] = useState(null)
  const [form, setForm] = useState(blank())
  const [lines, setLines] = useState([])
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [rejecting, setRejecting] = useState(false)
  const [reason, setReason] = useState('')
  const [company, setCompany] = useState(null)
  useEffect(() => { companyInfoApi.get().then(setCompany).catch(() => {}) }, [])

  const isNew = !id
  const canEdit = can(PHASE2_PERMISSIONS.QUOTATION_EDIT)
  const editable = isNew ? can(PHASE2_PERMISSIONS.QUOTATION_CREATE) : ['draft', 'sent', 'expired'].includes(quote?.status) && canEdit

  const fill = useCallback((q) => {
    setQuote(q)
    setForm({ customer: { id: q.customerId, name: q.customerName }, quoteDate: q.quoteDate, validUntil: q.validUntil ?? '',
      discountAmount: q.discountAmount, shippingFee: q.shippingFee, terms: q.terms ?? '', note: q.note ?? '' })
    setLines(q.lines.map((l) => ({ ...l })))
  }, [])

  useEffect(() => {
    setError('')
    if (isNew) { setQuote(null); setForm(blank()); setLines([]); return }
    quotationApi.get(id).then(fill).catch((err) => setError(getErrorMessage(err)))
  }, [id, isNew, fill])

  useEffect(() => { if (location.state?.message) setMessage(location.state.message) }, [location.state])

  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })
  const subTotal = linesSubTotal(lines)
  const total = subTotal - (Number(form.discountAmount) || 0) + (Number(form.shippingFee) || 0)

  const save = async (send) => {
    setError(''); setMessage('')
    if (!form.customer) return setError('Chọn khách hàng.')
    if (lines.length === 0) return setError('Thêm ít nhất 1 sản phẩm.')
    const body = {
      customerId: form.customer.id, quoteDate: form.quoteDate, validUntil: form.validUntil || null,
      discountAmount: Number(form.discountAmount) || 0, shippingFee: Number(form.shippingFee) || 0, terms: form.terms || null, note: form.note || null,
      lines: lines.map((l) => ({ productId: l.productId, quantity: Number(l.quantity), unitPrice: Number(l.unitPrice), discountPercent: Number(l.discountPercent) || 0 })),
      rowVersion: quote?.rowVersion ?? null,
    }
    setBusy(true)
    try {
      let saved = isNew ? await quotationApi.create(body) : await quotationApi.update(quote.id, body)
      if (send) saved = await quotationApi.send(saved.id)
      const msg = send ? 'Đã đánh dấu gửi khách. Bấm "In / lưu PDF" để gửi bản báo giá.' : 'Đã lưu báo giá.'
      if (isNew) navigate(`/quotations/${saved.id}`, { replace: true, state: { message: msg } })
      else { fill(saved); setMessage(msg) }
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  const act = async (fn, msg) => {
    setError(''); setMessage(''); setBusy(true)
    try { fill(await fn()); setMessage(msg) } catch (err) { setError(getErrorMessage(err)) } finally { setBusy(false) }
  }

  if (!isNew && !quote) {
    return <QuotationsLayout>{error ? <><div className="alert error">{error}</div><Link to="/quotations">← Danh sách báo giá</Link></> : <p className="muted">Đang tải...</p>}</QuotationsLayout>
  }
  const st = quote ? quotationStatus(quote.status) : null

  return (
    <QuotationsLayout>
      <div className="breadcrumb"><Link to="/quotations">Báo giá</Link> / {quote?.docNo ?? 'Tạo báo giá'}</div>
      <div className="page-head no-print">
        <div>
          <h1>{quote ? `Báo giá ${quote.docNo}` : 'Tạo báo giá'} {st && <span className={`pill ${st.css} small-pill`}>{st.label}</span>}</h1>
          {quote && <div className="muted small">Lập {formatDateOnly(quote.quoteDate)}{quote.revisionNo ? ` · đã sửa ${quote.revisionNo} lần` : ''}{quote.sentAt ? ` · gửi ${formatDateTime(quote.sentAt)}` : ''}</div>}
        </div>
        <div className="head-actions">
          {quote && <button className="btn" onClick={() => window.print()}><i className="ti ti-printer" aria-hidden="true" /> In / lưu PDF</button>}
          {quote && canEdit && ['sent', 'draft'].includes(quote.status) && can('order.create') && (
            <button className="btn primary" disabled={busy}
              onClick={() => act(() => quotationApi.accept(quote.id), 'Khách đã đồng ý. Đơn hàng nháp đã được tạo.')}>
              <i className="ti ti-circle-check" aria-hidden="true" /> Khách đồng ý → tạo đơn
            </button>
          )}
          {quote && canEdit && ['sent', 'draft', 'expired'].includes(quote.status) && (
            <button className="btn ghost danger" disabled={busy} onClick={() => setRejecting(true)}>Khách từ chối</button>
          )}
          {quote && canEdit && quote.status === 'draft' && (
            <button className="btn ghost danger" disabled={busy} onClick={() => window.confirm('Hủy báo giá này?') && act(() => quotationApi.cancel(quote.id), 'Đã hủy báo giá.')}>Hủy</button>
          )}
        </div>
      </div>

      {message && <div className="alert success no-print">{message}</div>}
      {error && <div className="alert error no-print">{error}</div>}
      {quote?.orderId && (
        <div className="alert info no-print"><i className="ti ti-shopping-cart" aria-hidden="true" /> Đã tạo đơn hàng <Link to={`/orders/${quote.orderId}`}>{quote.orderDocNo}</Link> - vào đơn để xác nhận và xuất kho.</div>
      )}
      {quote?.status === 'expired' && <div className="alert error no-print">Báo giá đã hết hạn. Sửa ngày hiệu lực rồi bấm "Lưu & gửi lại khách".</div>}
      {quote?.status === 'rejected' && <div className="status-note lost no-print">Khách từ chối: {quote.rejectedReason}</div>}

      <div className="order-grid no-print">
        <div>
          <div className="card">
            <div className="form-grid">
              <label className="span2">Khách hàng *
                {editable && isNew ? <CustomerPicker value={form.customer} onChange={(c) => setForm({ ...form, customer: c })} />
                  : <input value={form.customer?.name ?? ''} disabled />}
              </label>
              <label>Ngày báo giá<input type="date" value={form.quoteDate} onChange={update('quoteDate')} disabled={!editable} /></label>
              <label>Hiệu lực đến<input type="date" value={form.validUntil} onChange={update('validUntil')} disabled={!editable} /></label>
            </div>
          </div>
          <LineItems lines={lines} onChange={setLines} mode="sale" readOnly={!editable} />
          <label className="top-gap">Điều khoản (in trên báo giá)
            <textarea rows={3} value={form.terms} onChange={update('terms')} disabled={!editable} />
          </label>
          <label>Ghi chú nội bộ<textarea rows={2} value={form.note} onChange={update('note')} disabled={!editable} /></label>
        </div>

        <aside className="card summary">
          <div className="sum-row"><span>Tiền hàng</span><b>{formatMoney(subTotal)}</b></div>
          <div className="sum-row"><span>Giảm giá</span>
            {editable ? <MoneyInput className="sum-input" value={form.discountAmount} onChange={(v) => setForm({ ...form, discountAmount: v })} aria-label="Giảm giá" /> : <span>{formatMoney(form.discountAmount)}</span>}
          </div>
          <div className="sum-row"><span>Phí giao hàng</span>
            {editable ? <MoneyInput className="sum-input" value={form.shippingFee} onChange={(v) => setForm({ ...form, shippingFee: v })} aria-label="Phí giao hàng" /> : <span>{formatMoney(form.shippingFee)}</span>}
          </div>
          <div className="sum-row total"><span>Tổng báo giá</span><b>{formatMoney(total)}</b></div>
          <p className="hint-inline">{lines.length} sản phẩm · {formatQty(lines.reduce((s, l) => s + Number(l.quantity || 0), 0))} cái{lines.length ? ` · TB ${formatMoney(Math.round(lines.reduce((s, l) => s + lineTotal(l), 0) / Math.max(1, lines.reduce((s, l) => s + Number(l.quantity || 0), 0))))}/cái` : ''}</p>
          {editable && (
            <div className="summary-actions">
              <button className="btn primary block" disabled={busy} onClick={() => save(true)}>
                <i className="ti ti-send" aria-hidden="true" /> {quote?.status === 'sent' || quote?.status === 'expired' ? 'Lưu & gửi lại khách' : 'Lưu & gửi khách'}
              </button>
              <button className="btn block" disabled={busy} onClick={() => save(false)}>{isNew ? 'Lưu nháp' : 'Lưu thay đổi'}</button>
            </div>
          )}
        </aside>
      </div>

      {quote && <QuotePaper q={quote} company={company} />}

      {rejecting && (
        <Modal title={`Khách từ chối ${quote.docNo}`} onClose={() => setRejecting(false)} size="small">
          <label>Lý do *<textarea rows={3} autoFocus value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Giá cao / chọn bên khác / chưa có nhu cầu..." /></label>
          <div className="modal-foot">
            <button className="btn" onClick={() => setRejecting(false)}>Đóng</button>
            <button className="btn danger-fill" disabled={!reason.trim() || busy}
              onClick={async () => { setRejecting(false); await act(() => quotationApi.reject(quote.id, reason.trim()), 'Đã ghi nhận khách từ chối.') }}>Xác nhận</button>
          </div>
        </Modal>
      )}
    </QuotationsLayout>
  )
}
