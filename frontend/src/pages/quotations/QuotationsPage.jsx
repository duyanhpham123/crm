import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { quotationApi } from '../../api/phase2Api'
import Pagination from '../../components/Pagination'
import { PHASE2_PERMISSIONS, QUOTATION_STATUSES, quotationStatus } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import ModuleLayout from '../../layouts/ModuleLayout'
import { formatDateOnly, formatMoney } from '../../utils/format'

const MENU = [
  { to: '/quotations', icon: 'file-dollar', label: 'Báo giá', end: true },
  { to: '/quotations/new', icon: 'file-plus', label: 'Tạo báo giá' },
]

export function QuotationsLayout({ children }) {
  return <ModuleLayout title="Báo giá" icon="file-dollar" color="#D85A30" menu={MENU}>{children}</ModuleLayout>
}

/** Danh sách báo giá: đang chờ khách, đã chốt, tỷ lệ chốt. */
export default function QuotationsPage() {
  const { can } = useAuth()
  const navigate = useNavigate()
  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ search: '', status: '' })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    try {
      setError('')
      setData(await quotationApi.list({ ...filters, page, pageSize: 20 }))
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

  return (
    <QuotationsLayout>
      <div className="page-head">
        <h1>Báo giá</h1>
        {can(PHASE2_PERMISSIONS.QUOTATION_CREATE) && (
          <Link className="btn primary" to="/quotations/new"><i className="ti ti-plus" aria-hidden="true" /> Tạo báo giá</Link>
        )}
      </div>

      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Đang chờ khách</span><b>{s ? `${s.openCount} báo giá` : '…'}</b><span className="small muted">{s && formatMoney(s.openValue)}</span></div>
        <div className="kpi"><span className="muted small">Khách đã đồng ý</span><b className="ok-text">{s ? `${s.acceptedCount} báo giá` : '…'}</b><span className="small muted">{s && formatMoney(s.acceptedValue)}</span></div>
        <div className="kpi"><span className="muted small">Tỷ lệ chốt</span><b>{s ? `${s.conversionRate}%` : '…'}</b><span className="small muted">trên báo giá đã có kết quả</span></div>
      </div>

      <div className="toolbar">
        <div className="segmented no-margin" role="tablist" aria-label="Trạng thái">
          {[{ value: '', label: 'Tất cả' }, ...QUOTATION_STATUSES].map((st) => (
            <button key={st.value} role="tab" aria-selected={filters.status === st.value} className={filters.status === st.value ? 'on' : ''}
              onClick={() => setFilter('status', st.value)}>{st.label}</button>
          ))}
        </div>
      </div>
      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm số báo giá, tên khách, SĐT" value={filters.search} onChange={(e) => setFilter('search', e.target.value)} aria-label="Tìm báo giá" />
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr><th>Số báo giá</th><th>Khách hàng</th><th className="hide-sm">Hiệu lực đến</th><th className="num">Tổng tiền</th><th>Trạng thái</th></tr>
          </thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.rows.items.length === 0 && <tr><td colSpan={5} className="muted center">Chưa có báo giá nào.</td></tr>}
            {data?.rows.items.map((q) => (
              <tr key={q.id} className="clickable" onClick={() => navigate(`/quotations/${q.id}`)}>
                <td>
                  <Link to={`/quotations/${q.id}`} onClick={(e) => e.stopPropagation()}>{q.docNo}</Link>
                  <div className="muted small">Ngày {formatDateOnly(q.quoteDate)}{q.salespersonName ? ` · ${q.salespersonName}` : ''}</div>
                </td>
                <td>{q.customerName}<div className="muted small">{q.itemCount} sản phẩm</div></td>
                <td className="hide-sm">{formatDateOnly(q.validUntil)}</td>
                <td className="num"><b>{formatMoney(q.totalAmount)}</b></td>
                <td>
                  <span className={`pill ${quotationStatus(q.status).css}`}>{quotationStatus(q.status).label}</span>
                  {q.orderDocNo && <div className="small"><Link to={`/orders/${q.orderId}`} onClick={(e) => e.stopPropagation()}>→ {q.orderDocNo}</Link></div>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data?.rows} unit="báo giá" onPageChange={setPage} />
    </QuotationsLayout>
  )
}
