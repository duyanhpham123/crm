import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { logisticsApi } from '../../api/phase2Api'
import Pagination from '../../components/Pagination'
import { COD_STATUSES, PHASE2_PERMISSIONS, shipmentStatus } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateTime, formatMoney } from '../../utils/format'
import { CHANNEL_ICONS } from '../orders/OrdersLayout'
import { LogisticsLayout, ShipmentFormModal, ShipmentModal, useLogisticsLookups } from './LogisticsShared'

const TABS = [
  { value: '', label: 'Tất cả' }, { value: 'ready', label: 'Chờ lấy hàng' }, { value: 'in_transit', label: 'Đang giao' },
  { value: 'failed', label: 'Thất bại' }, { value: 'returning', label: 'Đang hoàn' }, { value: 'delivered', label: 'Đã giao' },
]

/** Danh sách vận đơn + số liệu nhanh. */
export function ShipmentsPage() {
  const lookups = useLogisticsLookups()
  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ search: '', status: '', carrierId: '' })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const [viewing, setViewing] = useState(null)

  const load = useCallback(async () => {
    try { setError(''); setData(await logisticsApi.list({ ...filters, page, pageSize: 20 })) } catch (err) { setError(getErrorMessage(err)) }
  }, [filters, page])

  useEffect(() => { const t = setTimeout(load, 250); return () => clearTimeout(t) }, [load])
  const setFilter = (f, v) => { setFilters({ ...filters, [f]: v }); setPage(1) }
  const s = data?.summary

  return (
    <LogisticsLayout>
      <div className="page-head">
        <h1>Vận đơn</h1>
        <Link className="btn primary" to="/logistics/ready"><i className="ti ti-package" aria-hidden="true" /> Đơn chờ giao</Link>
      </div>
      <div className="kpi-row">
        <button type="button" className="kpi clickable-kpi" onClick={() => setFilter('status', 'ready')}><span className="muted small">Chờ hãng lấy</span><b>{s?.ready ?? '…'}</b></button>
        <button type="button" className="kpi clickable-kpi" onClick={() => setFilter('status', 'in_transit')}><span className="muted small">Đang giao</span><b>{s?.inTransit ?? '…'}</b></button>
        <button type="button" className="kpi clickable-kpi" onClick={() => setFilter('status', 'failed')}><span className="muted small">Giao thất bại / đang hoàn</span><b className={s?.failed ? 'warn-text' : ''}>{s ? `${s.failed} / ${s.returning}` : '…'}</b></button>
        <Link className="kpi clickable-kpi" to="/logistics/cod"><span className="muted small">COD hãng đang giữ</span><b className="warn-text">{s ? formatMoney(s.codHolding) : '…'}</b><span className="small muted">Chờ giao: {s ? formatMoney(s.codPending) : ''}</span></Link>
      </div>

      <div className="toolbar">
        <div className="segmented no-margin" role="tablist" aria-label="Trạng thái">
          {TABS.map((t) => <button key={t.value} role="tab" aria-selected={filters.status === t.value} className={filters.status === t.value ? 'on' : ''} onClick={() => setFilter('status', t.value)}>{t.label}</button>)}
        </div>
      </div>
      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm mã vận đơn, mã hãng, mã đơn, người nhận, SĐT" value={filters.search} onChange={(e) => setFilter('search', e.target.value)} aria-label="Tìm vận đơn" />
        </div>
        <select value={filters.carrierId} onChange={(e) => setFilter('carrierId', e.target.value)} aria-label="Lọc hãng">
          <option value="">Mọi hãng vận chuyển</option>
          {lookups.carriers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
      </div>
      {error && <div className="alert error">{error}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Vận đơn</th><th>Người nhận</th><th className="hide-sm">Hãng</th><th className="num">COD</th><th>Trạng thái</th></tr></thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.rows.items.length === 0 && <tr><td colSpan={5} className="muted center">Chưa có vận đơn. Vào "Đơn chờ giao" để tạo.</td></tr>}
            {data?.rows.items.map((x) => (
              <tr key={x.id} className="clickable" onClick={() => setViewing(x.id)}>
                <td><button className="link" onClick={(e) => { e.stopPropagation(); setViewing(x.id) }}>{x.docNo}</button>
                  <div className="muted small">{x.orderDocNo} · {formatDateTime(x.createdAt)}</div></td>
                <td>{x.receiverName}<div className="muted small">{x.receiverPhone}</div></td>
                <td className="hide-sm">{x.carrierName}<div className="muted small">{x.trackingNo}</div></td>
                <td className="num">{x.codAmount ? formatMoney(x.codAmount) : '-'}<div className="muted small">{x.codAmount ? COD_STATUSES[x.codStatus] : ''}</div></td>
                <td><span className={`pill ${shipmentStatus(x.status).css}`}>{shipmentStatus(x.status).label}</span>
                  {x.failedReason && x.status === 'failed' && <div className="small warn-text">{x.failedReason}</div>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data?.rows} unit="vận đơn" onPageChange={setPage} />
      {viewing && <ShipmentModal id={viewing} carriers={lookups.carriers} onClose={() => setViewing(null)} onChanged={load} />}
    </LogisticsLayout>
  )
}

/** Đơn đã xác nhận (đã xuất kho) nhưng chưa có vận đơn. */
export function ReadyOrdersPage() {
  const { can } = useAuth()
  const lookups = useLogisticsLookups()
  const [orders, setOrders] = useState(null)
  const [search, setSearch] = useState('')
  const [error, setError] = useState('')
  const [creating, setCreating] = useState(null)
  const [message, setMessage] = useState('')

  const load = useCallback(() => logisticsApi.readyOrders(search).then(setOrders).catch((e) => setError(getErrorMessage(e))), [search])
  useEffect(() => { const t = setTimeout(load, 250); return () => clearTimeout(t) }, [load])

  return (
    <LogisticsLayout>
      <div className="page-head"><h1>Đơn chờ giao</h1></div>
      <p className="muted page-intro">Đơn đã xác nhận, hàng đã xuất kho, chưa giao cho hãng vận chuyển. Đơn bán tại quầy giao ngay thì vào đơn bấm "Hoàn thành".</p>
      {message && <div className="alert success">{message}</div>}
      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm mã đơn, người nhận, SĐT" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Tìm đơn" />
        </div>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Đơn hàng</th><th>Người nhận</th><th className="num">Còn phải thu</th><th className="actions" /></tr></thead>
          <tbody>
            {!orders && <tr><td colSpan={4} className="muted center">Đang tải...</td></tr>}
            {orders?.length === 0 && <tr><td colSpan={4} className="muted center">Không có đơn nào chờ giao.</td></tr>}
            {orders?.map((o) => (
              <tr key={o.id}>
                <td><Link to={`/orders/${o.id}`}>{o.docNo}</Link>
                  <div className="muted small"><i className={`ti ti-${CHANNEL_ICONS[o.channel] ?? 'dots'}`} aria-hidden="true" /> {formatDateTime(o.orderDate)}</div></td>
                <td>{o.receiverName ?? o.customerName}<div className="muted small">{o.receiverPhone} · {o.shippingAddress}</div></td>
                <td className="num"><b>{formatMoney(o.amountDue)}</b><div className="muted small">/ {formatMoney(o.totalAmount)}</div></td>
                <td className="actions">
                  {can(PHASE2_PERMISSIONS.LOGISTICS_CREATE) && <button className="btn primary" onClick={() => setCreating(o)}><i className="ti ti-truck" aria-hidden="true" /> Tạo vận đơn</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {creating && (
        <ShipmentFormModal order={creating} carriers={lookups.carriers} onClose={() => setCreating(null)}
          onSaved={(s) => { setCreating(null); setMessage(`Đã tạo vận đơn ${s.docNo} cho đơn ${s.orderDocNo}.`); load() }} />
      )}
    </LogisticsLayout>
  )
}

/** Đối soát COD: chọn các vận đơn hãng đã giao (đang giữ tiền) → ghi nhận hãng chuyển khoản. */
export function CodPage() {
  const { can } = useAuth()
  const lookups = useLogisticsLookups()
  const [carrierId, setCarrierId] = useState('')
  const [rows, setRows] = useState(null)
  const [selected, setSelected] = useState([])
  const [bankId, setBankId] = useState('')
  const [reference, setReference] = useState('')
  const [error, setError] = useState('')
  const [result, setResult] = useState(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => { if (!carrierId && lookups.carriers.length) setCarrierId(String(lookups.carriers[0].id)) }, [lookups.carriers, carrierId])
  useEffect(() => { if (!bankId && lookups.bankAccounts.length) setBankId(String(lookups.bankAccounts[0].id)) }, [lookups.bankAccounts, bankId])

  const load = useCallback(async () => {
    if (!carrierId) return
    try {
      const r = await logisticsApi.list({ carrierId, codStatus: 'collected', pageSize: 100 })
      setRows(r.rows.items); setSelected(r.rows.items.map((x) => x.id))
    } catch (e) { setError(getErrorMessage(e)) }
  }, [carrierId])
  useEffect(() => { load() }, [load])

  const chosen = (rows ?? []).filter((r) => selected.includes(r.id))
  const totalCod = chosen.reduce((s, r) => s + r.codAmount, 0)
  const totalFee = chosen.reduce((s, r) => s + r.shippingFee, 0)
  const toggle = (id) => setSelected(selected.includes(id) ? selected.filter((x) => x !== id) : [...selected, id])

  const reconcile = async () => {
    setError(''); setBusy(true)
    try {
      setResult(await logisticsApi.reconcileCod({ carrierId: Number(carrierId), shipmentIds: selected, bankAccountId: bankId ? Number(bankId) : null, reference: reference || null }))
      setReference('')
      await load()
    } catch (e) { setError(getErrorMessage(e)) } finally { setBusy(false) }
  }

  return (
    <LogisticsLayout>
      <div className="page-head"><h1>Đối soát COD</h1></div>
      <p className="muted page-intro">Vận đơn đã giao xong, hãng đang giữ tiền thu hộ. Khi hãng chuyển khoản, chọn các vận đơn trong bảng kê rồi bấm "Ghi nhận đã nhận tiền".</p>
      {result && (
        <div className="alert success">
          Đã đối soát {result.shipmentCount} vận đơn: COD {formatMoney(result.totalCod)} - phí ship {formatMoney(result.totalFee)} = thực nhận <b>{formatMoney(result.netAmount)}</b>.
          Phiếu báo có {result.receiptDocNo}{result.feeDocNo ? `, phiếu chi phí ship ${result.feeDocNo}` : ''}. <Link to="/accounting/vouchers">Xem sổ thu chi</Link>
        </div>
      )}
      {error && <div className="alert error">{error}</div>}
      <div className="toolbar">
        <select value={carrierId} onChange={(e) => { setCarrierId(e.target.value); setResult(null) }} aria-label="Hãng vận chuyển">
          {lookups.carriers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
      </div>
      <div className="order-grid">
        <div className="table-wrap">
          <table className="grid">
            <thead><tr><th className="check-cell"><input type="checkbox" aria-label="Chọn tất cả" checked={rows?.length > 0 && selected.length === rows.length}
              onChange={(e) => setSelected(e.target.checked ? rows.map((r) => r.id) : [])} /></th><th>Vận đơn</th><th className="num">COD</th><th className="num">Phí ship</th></tr></thead>
            <tbody>
              {!rows && <tr><td colSpan={4} className="muted center">Đang tải...</td></tr>}
              {rows?.length === 0 && <tr><td colSpan={4} className="muted center">Hãng này không còn giữ tiền COD nào.</td></tr>}
              {rows?.map((r) => (
                <tr key={r.id} className="clickable" onClick={() => toggle(r.id)}>
                  <td className="check-cell"><input type="checkbox" checked={selected.includes(r.id)} onChange={() => toggle(r.id)} onClick={(e) => e.stopPropagation()} aria-label={`Chọn ${r.docNo}`} /></td>
                  <td>{r.docNo} <span className="muted small">· {r.orderDocNo}</span><div className="muted small">{r.receiverName} · {r.trackingNo}</div></td>
                  <td className="num">{formatMoney(r.codAmount)}</td>
                  <td className="num muted">{formatMoney(r.shippingFee)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <aside className="card summary">
          <div className="sum-row"><span>Số vận đơn</span><b>{chosen.length}</b></div>
          <div className="sum-row"><span>Tổng COD</span><b>{formatMoney(totalCod)}</b></div>
          <div className="sum-row"><span>Phí ship (shop trả)</span><span className="money-out">-{formatMoney(totalFee)}</span></div>
          <div className="sum-row total"><span>Thực nhận</span><b>{formatMoney(totalCod - totalFee)}</b></div>
          <label className="top-gap">Tiền về tài khoản
            <select value={bankId} onChange={(e) => setBankId(e.target.value)}>
              {lookups.bankAccounts.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
          </label>
          <label>Mã giao dịch / bảng kê<input value={reference} onChange={(e) => setReference(e.target.value)} placeholder="FT26..." /></label>
          {can(PHASE2_PERMISSIONS.ACCOUNTING_CREATE) && can(PHASE2_PERMISSIONS.LOGISTICS_EDIT) && (
            <button className="btn primary block" disabled={busy || chosen.length === 0} onClick={reconcile}>
              <i className="ti ti-checks" aria-hidden="true" /> Ghi nhận đã nhận tiền
            </button>
          )}
        </aside>
      </div>
    </LogisticsLayout>
  )
}

