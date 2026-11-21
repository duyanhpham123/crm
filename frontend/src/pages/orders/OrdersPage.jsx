import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { salesApi } from '../../api/retailApi'
import Pagination from '../../components/Pagination'
import { ORDER_STATUSES, orderStatus, PAYMENT_STATUSES, RETAIL_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateTime, formatMoney } from '../../utils/format'
import OrdersLayout, { CHANNEL_ICONS, useSalesLookups } from './OrdersLayout'

/** Danh sách đơn bán: lọc trạng thái, kênh, khoảng ngày; tổng tiền / đã thu / còn nợ theo bộ lọc. */
export default function OrdersPage() {
  const { can } = useAuth()
  const navigate = useNavigate()
  const lookups = useSalesLookups()
  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ search: '', status: '', channel: '', from: '', to: '' })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    try {
      setError('')
      setData(await salesApi.list({ ...filters, page, pageSize: 20 }))
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }, [filters, page])

  useEffect(() => {
    const timer = setTimeout(load, 250)
    return () => clearTimeout(timer)
  }, [load])

  const setFilter = (field, value) => { setFilters({ ...filters, [field]: value }); setPage(1) }
  const s = data?.summary
  const filtered = Object.values(filters).some(Boolean)

  return (
    <OrdersLayout>
      <div className="page-head">
        <h1>Đơn hàng</h1>
        {can(RETAIL_PERMISSIONS.ORDER_CREATE) && (
          <Link className="btn primary" to="/orders/new"><i className="ti ti-plus" aria-hidden="true" /> Tạo đơn</Link>
        )}
      </div>

      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Số đơn</span><b>{s?.count ?? '…'}</b></div>
        <div className="kpi"><span className="muted small">Tổng tiền</span><b>{s ? formatMoney(s.totalAmount) : '…'}</b></div>
        <div className="kpi"><span className="muted small">Đã thu</span><b className="ok-text">{s ? formatMoney(s.amountPaid) : '…'}</b></div>
        <div className="kpi"><span className="muted small">Còn phải thu</span><b className={s?.amountDue ? 'warn-text' : ''}>{s ? formatMoney(s.amountDue) : '…'}</b></div>
      </div>
      <p className="hint-inline kpi-note">Tổng tiền tính các đơn khớp bộ lọc, không gồm đơn đã hủy.</p>

      <div className="toolbar">
        <div className="segmented no-margin" role="tablist" aria-label="Trạng thái">
          {[{ value: '', label: 'Tất cả' }, ...ORDER_STATUSES].map((st) => (
            <button key={st.value} role="tab" aria-selected={filters.status === st.value} className={filters.status === st.value ? 'on' : ''}
              onClick={() => setFilter('status', st.value)}>{st.label}</button>
          ))}
        </div>
      </div>
      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm mã đơn, tên khách, SĐT" value={filters.search} onChange={(e) => setFilter('search', e.target.value)} aria-label="Tìm đơn hàng" />
        </div>
        <select value={filters.channel} onChange={(e) => setFilter('channel', e.target.value)} aria-label="Lọc kênh bán">
          <option value="">Mọi kênh bán</option>
          {lookups.channels.map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}
        </select>
        <input type="date" className="date-input" value={filters.from} onChange={(e) => setFilter('from', e.target.value)} aria-label="Từ ngày" title="Từ ngày" />
        <input type="date" className="date-input" value={filters.to} onChange={(e) => setFilter('to', e.target.value)} aria-label="Đến ngày" title="Đến ngày" />
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr>
              <th>Mã đơn</th><th>Khách hàng</th><th className="hide-sm">Kênh</th>
              <th className="num">Tổng tiền</th><th className="hide-sm">Thanh toán</th><th>Trạng thái</th>
            </tr>
          </thead>
          <tbody>
            {!data && <tr><td colSpan={6} className="muted center">Đang tải...</td></tr>}
            {data?.rows.items.length === 0 && (
              <tr><td colSpan={6} className="muted center">{filtered ? 'Không có đơn nào khớp bộ lọc.' : 'Chưa có đơn hàng. Bấm "Tạo đơn" để bán đơn đầu tiên.'}</td></tr>
            )}
            {data?.rows.items.map((o) => (
              <tr key={o.id} className="clickable" onClick={() => navigate(`/orders/${o.id}`)}>
                <td>
                  <Link to={`/orders/${o.id}`} onClick={(e) => e.stopPropagation()}>{o.docNo}</Link>
                  <div className="muted small">{formatDateTime(o.orderDate)}</div>
                </td>
                <td>
                  {o.customerName}
                  <div className="muted small">{o.customerPhone}{o.customerPhone ? ' · ' : ''}{o.itemCount} sản phẩm</div>
                </td>
                <td className="hide-sm">
                  <span className="channel"><i className={`ti ti-${CHANNEL_ICONS[o.channel] ?? 'dots'}`} aria-hidden="true" />{lookups.channelName(o.channel)}</span>
                </td>
                <td className="num"><b>{formatMoney(o.totalAmount)}</b></td>
                <td className="hide-sm">
                  {o.status !== 'cancelled' && <span className={`pay ${o.paymentStatus}`}>{PAYMENT_STATUSES[o.paymentStatus] ?? o.paymentStatus}</span>}
                </td>
                <td><span className={`pill ${orderStatus(o.status).css}`}>{orderStatus(o.status).label}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination data={data?.rows} unit="đơn" onPageChange={setPage} />
    </OrdersLayout>
  )
}
