import { useCallback, useEffect, useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { supportApi } from '../../api/phase2Api'
import { salesApi } from '../../api/retailApi'
import CustomerPicker from '../../components/CustomerPicker'
import Modal from '../../components/Modal'
import Pagination from '../../components/Pagination'
import { PHASE2_PERMISSIONS, PRIORITIES, TICKET_STATUSES, ticketStatus } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import ModuleLayout from '../../layouts/ModuleLayout'
import { formatDateTime, initials } from '../../utils/format'

const MENU = [{ to: '/support', icon: 'headset', label: 'Phiếu hỗ trợ', end: true }]

export function SupportLayout({ children }) {
  return <ModuleLayout title="CSKH" icon="headset" color="#1D9E75" menu={MENU}>{children}</ModuleLayout>
}

function useSupportLookups() {
  const [l, setL] = useState({ categories: [], agents: [], channels: [], priorities: [] })
  useEffect(() => { supportApi.lookups().then(setL).catch(() => {}) }, [])
  return l
}

/** "còn 2 giờ" / "quá hạn 3 giờ" */
function dueText(iso) {
  if (!iso) return ''
  const due = new Date(/[zZ]$/.test(iso) ? iso : iso + 'Z')
  const mins = Math.round((due - new Date()) / 60000)
  const abs = Math.abs(mins)
  const t = abs < 60 ? `${abs} phút` : abs < 1440 ? `${Math.round(abs / 60)} giờ` : `${Math.round(abs / 1440)} ngày`
  return mins < 0 ? `quá hạn ${t}` : `còn ${t}`
}

/**
 * Tạo / sửa phiếu hỗ trợ. preset: { customer: { id, name }, salesOrderId, orderDocNo, subject, categoryName }
 */
export function TicketFormModal({ lookups, ticket, preset, onClose, onSaved }) {
  const isNew = !ticket
  const [form, setForm] = useState(() => ({
    subject: ticket?.subject ?? preset?.subject ?? '', description: ticket?.description ?? '',
    customer: ticket?.customerId ? { id: ticket.customerId, name: ticket.customerName } : preset?.customer ?? null,
    reporterName: ticket?.reporterName ?? '', reporterPhone: ticket?.reporterPhone ?? '',
    salesOrderId: ticket?.salesOrderId ?? preset?.salesOrderId ?? '',
    categoryId: ticket?.categoryId ?? lookups.categories.find((c) => c.name === preset?.categoryName)?.id ?? '',
    channel: ticket?.channel ?? 'phone', priority: ticket?.priority ?? 'normal', assignedUserId: ticket?.assignedUserId ?? '',
  }))
  const [orders, setOrders] = useState([])
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })

  useEffect(() => {
    if (!form.customer) { setOrders([]); return }
    salesApi.list({ search: form.customer.name, pageSize: 20 }).then((r) => setOrders(r.rows.items)).catch(() => setOrders([]))
  }, [form.customer])

  const save = async (e) => {
    e.preventDefault()
    setError('')
    const body = {
      subject: form.subject, description: form.description || null, customerId: form.customer?.id ?? null,
      reporterName: form.reporterName || null, reporterPhone: form.reporterPhone || null,
      salesOrderId: form.salesOrderId ? Number(form.salesOrderId) : null, categoryId: form.categoryId ? Number(form.categoryId) : null,
      channel: form.channel, priority: form.priority, assignedUserId: form.assignedUserId ? Number(form.assignedUserId) : null,
      rowVersion: ticket?.rowVersion ?? null,
    }
    setBusy(true)
    try { onSaved(isNew ? await supportApi.create(body) : await supportApi.update(ticket.id, body)) } catch (err) { setError(getErrorMessage(err)); setBusy(false) }
  }

  return (
    <Modal title={isNew ? 'Tạo phiếu hỗ trợ' : `Sửa ${ticket.code}`} onClose={onClose}>
      <form onSubmit={save}>
        <div className="form-grid">
          <label className="span2">Tiêu đề *<input value={form.subject} onChange={u('subject')} autoFocus placeholder="Khách muốn đổi size áo / giao thiếu hàng..." /></label>
          <label>Khách hàng<CustomerPicker value={form.customer} onChange={(c) => setForm({ ...form, customer: c, salesOrderId: preset?.salesOrderId ?? '' })} /></label>
          <label>Đơn hàng liên quan
            <select value={form.salesOrderId} onChange={u('salesOrderId')}>
              <option value="">Không có</option>
              {preset?.salesOrderId && !orders.some((o) => o.id === preset.salesOrderId) && <option value={preset.salesOrderId}>{preset.orderDocNo}</option>}
              {orders.map((o) => <option key={o.id} value={o.id}>{o.docNo} · {formatDateTime(o.orderDate)}</option>)}
            </select>
          </label>
          {!form.customer && (
            <>
              <label>Tên người báo<input value={form.reporterName} onChange={u('reporterName')} /></label>
              <label>SĐT người báo<input value={form.reporterPhone} onChange={u('reporterPhone')} /></label>
            </>
          )}
          <label>Loại<select value={form.categoryId} onChange={u('categoryId')}><option value="">Chưa phân loại</option>{lookups.categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
          <label>Kênh tiếp nhận<select value={form.channel} onChange={u('channel')}>{lookups.channels.map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}</select></label>
          <label>Mức ưu tiên<select value={form.priority} onChange={u('priority')}>{lookups.priorities.map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}</select></label>
          <label>Người xử lý<select value={form.assignedUserId} onChange={u('assignedUserId')}><option value="">Chưa giao</option>{lookups.agents.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select></label>
          <label className="span2">Nội dung khách phản ánh<textarea rows={4} value={form.description} onChange={u('description')} /></label>
        </div>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot"><button type="button" className="btn" onClick={onClose}>Hủy</button><button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Lưu'}</button></div>
      </form>
    </Modal>
  )
}

const TABS = [{ value: 'active', label: 'Đang mở' }, ...TICKET_STATUSES.filter((s) => s.value !== 'cancelled'), { value: 'all', label: 'Tất cả' }]

export function TicketsPage() {
  const { can } = useAuth()
  const navigate = useNavigate()
  const lookups = useSupportLookups()
  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ status: 'active', search: '', priority: '', mine: false, overdueOnly: false })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const location = useLocation()
  const [creating, setCreating] = useState(() => location.state?.preset ?? false)

  const load = useCallback(async () => {
    try { setError(''); setData(await supportApi.list({ ...filters, page, pageSize: 20 })) } catch (e) { setError(getErrorMessage(e)) }
  }, [filters, page])
  useEffect(() => { const t = setTimeout(load, 250); return () => clearTimeout(t) }, [load])
  const setFilter = (f, v) => { setFilters({ ...filters, [f]: v }); setPage(1) }
  const s = data?.summary

  return (
    <SupportLayout>
      <div className="page-head">
        <h1>Chăm sóc khách hàng</h1>
        {can(PHASE2_PERMISSIONS.SUPPORT_CREATE) && <button className="btn primary" onClick={() => setCreating(true)}><i className="ti ti-plus" aria-hidden="true" /> Tạo phiếu</button>}
      </div>
      <div className="kpi-row">
        <button type="button" className="kpi clickable-kpi" onClick={() => setFilter('status', 'new')}><span className="muted small">Mới, chưa xử lý</span><b>{s?.new ?? '…'}</b></button>
        <button type="button" className="kpi clickable-kpi" onClick={() => setFilter('status', 'open')}><span className="muted small">Đang xử lý / chờ khách</span><b>{s ? `${s.open} / ${s.pending}` : '…'}</b></button>
        <button type="button" className={`kpi clickable-kpi${filters.overdueOnly ? ' on' : ''}`} onClick={() => setFilters({ ...filters, status: 'active', overdueOnly: !filters.overdueOnly })}>
          <span className="muted small">Quá hạn xử lý</span><b className={s?.overdue ? 'money-out' : ''}>{s?.overdue ?? '…'}</b></button>
        <div className="kpi"><span className="muted small">Đã xử lý tháng này · hài lòng TB</span><b>{s ? `${s.resolvedThisMonth} · ${s.avgSatisfaction ?? '-'}★` : '…'}</b></div>
      </div>
      <div className="toolbar">
        <div className="segmented no-margin">
          {TABS.map((t) => <button key={t.value} className={filters.status === t.value ? 'on' : ''} onClick={() => setFilter('status', t.value)}>{t.label}</button>)}
        </div>
      </div>
      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm mã phiếu, tiêu đề, khách hàng, SĐT" value={filters.search} onChange={(e) => setFilter('search', e.target.value)} aria-label="Tìm phiếu" />
        </div>
        <select value={filters.priority} onChange={(e) => setFilter('priority', e.target.value)} aria-label="Mức ưu tiên">
          <option value="">Mọi mức ưu tiên</option>
          {Object.entries(PRIORITIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <label className="check toolbar-check"><input type="checkbox" checked={filters.mine} onChange={(e) => setFilter('mine', e.target.checked)} /> Việc của tôi</label>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Phiếu</th><th>Khách hàng</th><th className="hide-sm">Người xử lý</th><th>Hạn xử lý</th><th>Trạng thái</th></tr></thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.rows.items.length === 0 && <tr><td colSpan={5} className="muted center">Không có phiếu nào.</td></tr>}
            {data?.rows.items.map((t) => (
              <tr key={t.id} className="clickable" onClick={() => navigate(`/support/${t.id}`)}>
                <td><Link to={`/support/${t.id}`} onClick={(e) => e.stopPropagation()}>{t.subject}</Link>
                  <div className="muted small">{t.code} · {t.categoryName ?? 'Chưa phân loại'} · <span className={`pill ${t.priority} small-pill`}>{PRIORITIES[t.priority]}</span></div></td>
                <td>{t.customerName}<div className="muted small">{t.reporterPhone}</div></td>
                <td className="hide-sm">{t.assigneeName ? <span className="owner"><span className="avatar tiny">{initials(t.assigneeName)}</span>{t.assigneeName}</span> : <span className="warn-text small">Chưa giao</span>}</td>
                <td className={t.isOverdue ? 'money-out small' : 'small muted'}>{['new', 'open', 'pending'].includes(t.status) ? dueText(t.resolutionDueAt) : ''}</td>
                <td><span className={`pill ${ticketStatus(t.status).css}`}>{ticketStatus(t.status).label}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data?.rows} unit="phiếu" onPageChange={setPage} />
      {creating && lookups.channels.length > 0 && <TicketFormModal lookups={lookups} preset={creating === true ? null : creating} onClose={() => setCreating(false)} onSaved={(t) => navigate(`/support/${t.id}`)} />}
    </SupportLayout>
  )
}

/** Chi tiết phiếu: hội thoại (trả lời khách / ghi chú nội bộ) + thông tin, trạng thái, người xử lý, đánh giá. */
export function TicketDetailPage() {
  const { id } = useParams()
  const { can } = useAuth()
  const lookups = useSupportLookups()
  const [t, setT] = useState(null)
  const [error, setError] = useState('')
  const [reply, setReply] = useState('')
  const [internal, setInternal] = useState(false)
  const [resolving, setResolving] = useState(false)
  const [resolution, setResolution] = useState('')
  const [editing, setEditing] = useState(false)
  const [busy, setBusy] = useState(false)
  const canEdit = can(PHASE2_PERMISSIONS.SUPPORT_EDIT)

  useEffect(() => { supportApi.get(id).then(setT).catch((e) => setError(getErrorMessage(e))) }, [id])
  const run = async (fn) => { setBusy(true); setError(''); try { setT(await fn()); return true } catch (e) { setError(getErrorMessage(e)); return false } finally { setBusy(false) } }

  if (!t) return <SupportLayout>{error ? <div className="alert error">{error}</div> : <p className="muted">Đang tải...</p>}</SupportLayout>
  const active = ['new', 'open', 'pending'].includes(t.status)
  const st = ticketStatus(t.status)

  return (
    <SupportLayout>
      <div className="breadcrumb"><Link to="/support">CSKH</Link> / {t.code}</div>
      <div className="page-head">
        <div>
          <h1>{t.subject} <span className={`pill ${st.css} small-pill`}>{st.label}</span></h1>
          <div className="muted small">{t.code} · tạo {formatDateTime(t.createdAt)} · <span className={`pill ${t.priority} small-pill`}>{PRIORITIES[t.priority]}</span>
            {active && t.resolutionDueAt && <span className={t.isOverdue ? 'money-out' : ''}> · hạn xử lý {formatDateTime(t.resolutionDueAt)} ({dueText(t.resolutionDueAt)})</span>}</div>
        </div>
        {canEdit && (
          <div className="head-actions">
            {active && <button className="btn primary" disabled={busy} onClick={() => { setResolution(t.resolution ?? ''); setResolving(true) }}><i className="ti ti-circle-check" aria-hidden="true" /> Đã xử lý xong</button>}
            {t.status === 'open' && <button className="btn" disabled={busy} onClick={() => run(() => supportApi.changeStatus(t.id, 'pending'))}>Chờ khách phản hồi</button>}
            {t.status === 'resolved' && <button className="btn" disabled={busy} onClick={() => run(() => supportApi.changeStatus(t.id, 'closed'))}>Đóng phiếu</button>}
            {['resolved', 'pending'].includes(t.status) && <button className="btn" disabled={busy} onClick={() => run(() => supportApi.changeStatus(t.id, 'open'))}>Mở lại</button>}
            {active && <button className="btn ghost" onClick={() => setEditing(true)}><i className="ti ti-pencil" aria-hidden="true" /> Sửa</button>}
          </div>
        )}
      </div>
      {error && <div className="alert error">{error}</div>}

      <div className="detail-grid">
        <div>
          {t.description && <div className="card"><div className="muted small">Khách phản ánh ({t.channel})</div><p className="note">{t.description}</p></div>}
          <div className="chat">
            {t.messages.length === 0 && <p className="muted">Chưa có trao đổi nào.</p>}
            {t.messages.map((m) => (
              <div key={m.id} className={`msg${m.isInternal ? ' internal' : ''}`}>
                <div className="meta"><b>{m.authorName}</b> · {formatDateTime(m.createdAt)}{m.isInternal && ' · ghi chú nội bộ'}</div>
                <div className="body">{m.body}</div>
              </div>
            ))}
          </div>
          {canEdit && t.status !== 'closed' && t.status !== 'cancelled' && (
            <div className="composer">
              <textarea rows={3} value={reply} onChange={(e) => setReply(e.target.value)} placeholder={internal ? 'Ghi chú nội bộ (khách không thấy)' : 'Nội dung đã trả lời / hướng dẫn khách'} aria-label="Nội dung trao đổi" />
              <div className="composer-foot">
                <label className="check"><input type="checkbox" checked={internal} onChange={(e) => setInternal(e.target.checked)} /> Ghi chú nội bộ</label>
                <button className="btn primary" disabled={busy || !reply.trim()} onClick={async () => { if (await run(() => supportApi.message(t.id, reply.trim(), internal))) setReply('') }}>
                  <i className="ti ti-send" aria-hidden="true" /> {internal ? 'Lưu ghi chú' : 'Gửi trả lời'}
                </button>
              </div>
            </div>
          )}
          {t.resolution && <div className="status-note won top-gap"><b>Cách xử lý:</b> {t.resolution}</div>}
        </div>

        <aside>
          <div className="card">
            <dl className="info">
              <dt>Khách hàng</dt><dd>{t.customerId ? <Link to={`/crm/customers/${t.customerId}`}>{t.customerName}</Link> : t.reporterName}<div className="muted small">{t.customerPhone ?? t.reporterPhone}</div></dd>
              <dt>Đơn hàng</dt><dd>{t.salesOrderId ? <Link to={`/orders/${t.salesOrderId}`}>{t.orderDocNo}</Link> : '-'}</dd>
              <dt>Loại</dt><dd>{t.categoryName ?? '-'}</dd>
              <dt>Phản hồi đầu</dt><dd>{t.firstRespondedAt ? formatDateTime(t.firstRespondedAt) : <span className="warn-text">Chưa phản hồi</span>}</dd>
            </dl>
            <label>Người xử lý
              <select value={t.assignedUserId ?? ''} disabled={!canEdit || !active || busy} onChange={(e) => run(() => supportApi.assign(t.id, e.target.value ? Number(e.target.value) : null))}>
                <option value="">Chưa giao</option>
                {lookups.agents.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
              </select>
            </label>
          </div>
          {['resolved', 'closed'].includes(t.status) && (
            <div className="card">
              <div className="field-label">Khách đánh giá</div>
              <div className="stars" role="radiogroup" aria-label="Đánh giá">
                {[1, 2, 3, 4, 5].map((n) => (
                  <button key={n} type="button" role="radio" aria-checked={t.satisfactionScore === n} className={n <= (t.satisfactionScore ?? 0) ? 'on' : ''}
                    disabled={!canEdit || busy} onClick={() => run(() => supportApi.rate(t.id, n, t.satisfactionNote))} aria-label={`${n} sao`}>★</button>
                ))}
              </div>
              <p />
            </div>
          )}
        </aside>
      </div>

      {resolving && (
        <Modal title="Đã xử lý xong" onClose={() => setResolving(false)} size="small">
          <label>Cách đã xử lý cho khách *<textarea rows={4} autoFocus value={resolution} onChange={(e) => setResolution(e.target.value)} placeholder="Đã đổi size M, khách nhận hàng ngày 22/11" /></label>
          <div className="modal-foot">
            <button className="btn" onClick={() => setResolving(false)}>Hủy</button>
            <button className="btn primary" disabled={!resolution.trim() || busy} onClick={async () => { if (await run(() => supportApi.changeStatus(t.id, 'resolved', resolution.trim()))) setResolving(false) }}>Lưu</button>
          </div>
        </Modal>
      )}
      {editing && <TicketFormModal lookups={lookups} ticket={t} onClose={() => setEditing(false)} onSaved={(r) => { setT(r); setEditing(false) }} />}
    </SupportLayout>
  )
}
