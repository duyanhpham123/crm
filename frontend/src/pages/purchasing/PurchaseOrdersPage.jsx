import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { purchasingApi } from '../../api/retailApi'
import Pagination from '../../components/Pagination'
import { PURCHASE_STATUSES, purchaseStatus, RETAIL_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateOnly, formatMoney, formatQty } from '../../utils/format'
import PurchasingLayout from './PurchasingLayout'

/** Danh sách đơn nhập hàng từ nhà cung cấp */
export default function PurchaseOrdersPage() {
  const { can } = useAuth()
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const [suppliers, setSuppliers] = useState([])
  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ search: '', status: '', supplierId: params.get('supplierId') ?? '' })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')

  useEffect(() => { purchasingApi.listSuppliers({ pageSize: 100 }).then((r) => setSuppliers(r.items)).catch(() => {}) }, [])

  const load = useCallback(async () => {
    try {
      setError('')
      setData(await purchasingApi.list({ ...filters, page, pageSize: 20 }))
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }, [filters, page])

  useEffect(() => {
    const timer = setTimeout(load, 250)
    return () => clearTimeout(timer)
  }, [load])

  const setFilter = (field, value) => { setFilters({ ...filters, [field]: value }); setPage(1) }

  return (
    <PurchasingLayout>
      <div className="page-head">
        <h1>Đơn nhập hàng</h1>
        {can(RETAIL_PERMISSIONS.PURCHASING_CREATE) && (
          <Link className="btn primary" to="/purchasing/orders/new"><i className="ti ti-plus" aria-hidden="true" /> Tạo đơn nhập</Link>
        )}
      </div>

      <div className="toolbar">
        <div className="segmented no-margin" role="tablist" aria-label="Trạng thái">
          {[{ value: '', label: 'Tất cả' }, ...PURCHASE_STATUSES].map((st) => (
            <button key={st.value} role="tab" aria-selected={filters.status === st.value} className={filters.status === st.value ? 'on' : ''}
              onClick={() => setFilter('status', st.value)}>{st.label}</button>
          ))}
        </div>
      </div>
      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm số đơn, nhà cung cấp" value={filters.search} onChange={(e) => setFilter('search', e.target.value)} aria-label="Tìm đơn nhập" />
        </div>
        <select value={filters.supplierId} onChange={(e) => setFilter('supplierId', e.target.value)} aria-label="Lọc nhà cung cấp">
          <option value="">Mọi nhà cung cấp</option>
          {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
        </select>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr><th>Số đơn</th><th>Nhà cung cấp</th><th className="num hide-sm">Số lượng</th><th className="num">Tổng tiền</th><th>Trạng thái</th></tr>
          </thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.items.length === 0 && <tr><td colSpan={5} className="muted center">Chưa có đơn nhập nào.</td></tr>}
            {data?.items.map((p) => (
              <tr key={p.id} className="clickable" onClick={() => navigate(`/purchasing/orders/${p.id}`)}>
                <td>
                  <Link to={`/purchasing/orders/${p.id}`} onClick={(e) => e.stopPropagation()}>{p.docNo}</Link>
                  <div className="muted small">Ngày {formatDateOnly(p.orderDate)}{p.expectedDate && p.status === 'confirmed' ? ` · dự kiến về ${formatDateOnly(p.expectedDate)}` : ''}</div>
                </td>
                <td>{p.supplierName}<div className="muted small">{p.itemCount} mã hàng</div></td>
                <td className="num hide-sm">{formatQty(p.totalQuantity)}</td>
                <td className="num"><b>{formatMoney(p.totalAmount)}</b></td>
                <td><span className={`pill ${purchaseStatus(p.status).css}`}>{purchaseStatus(p.status).label}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data} unit="đơn nhập" onPageChange={setPage} />
    </PurchasingLayout>
  )
}
