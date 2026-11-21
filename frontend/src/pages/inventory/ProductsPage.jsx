import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { inventoryApi } from '../../api/retailApi'
import Pagination from '../../components/Pagination'
import { genderLabel, RETAIL_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatMoney, formatQty } from '../../utils/format'
import InventoryLayout, { useInventoryLookups } from './InventoryLayout'
import ProductFormModal from './ProductFormModal'

/** Danh sách mẫu sản phẩm. Mỗi mẫu gồm nhiều SKU theo màu × size. */
export default function ProductsPage() {
  const { can } = useAuth()
  const navigate = useNavigate()
  const lookups = useInventoryLookups()
  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ search: '', categoryId: '' })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const [creating, setCreating] = useState(false)

  const load = useCallback(async () => {
    try {
      setError('')
      setData(await inventoryApi.listModels({ ...filters, page, pageSize: 20 }))
    } catch (err) {
      setError(getErrorMessage(err))
      setData((d) => d ?? { items: [], page: 1, totalPages: 0, totalCount: 0 })
    }
  }, [filters, page])

  useEffect(() => {
    const timer = setTimeout(load, 250)
    return () => clearTimeout(timer)
  }, [load])

  const setFilter = (field) => (e) => { setFilters({ ...filters, [field]: e.target.value }); setPage(1) }

  return (
    <InventoryLayout>
      <div className="page-head">
        <h1>Sản phẩm</h1>
        {can(RETAIL_PERMISSIONS.INVENTORY_CREATE) && (
          <button className="btn primary" onClick={() => setCreating(true)}>
            <i className="ti ti-plus" aria-hidden="true" /> Thêm sản phẩm
          </button>
        )}
      </div>

      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm tên, mã sản phẩm, mã SKU, mã vạch" value={filters.search} onChange={setFilter('search')} aria-label="Tìm sản phẩm" />
        </div>
        <select value={filters.categoryId} onChange={setFilter('categoryId')} aria-label="Lọc theo nhóm hàng">
          <option value="">Mọi nhóm hàng</option>
          {lookups.categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr>
              <th>Sản phẩm</th>
              <th className="hide-sm">Nhóm hàng</th>
              <th className="num">Giá bán</th>
              <th className="num hide-sm">Biến thể</th>
              <th className="num">Tồn kho</th>
            </tr>
          </thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.items.length === 0 && (
              <tr><td colSpan={5} className="muted center">
                {filters.search || filters.categoryId ? 'Không có sản phẩm nào khớp bộ lọc.' : 'Chưa có sản phẩm. Bấm "Thêm sản phẩm" để tạo mẫu đầu tiên.'}
              </td></tr>
            )}
            {data?.items.map((m) => (
              <tr key={m.id} className={`clickable${m.isActive ? '' : ' inactive'}`} onClick={() => navigate(`/inventory/products/${m.id}`)}>
                <td>
                  <div className="user-cell">
                    <span className="avatar square"><i className="ti ti-shirt" aria-hidden="true" /></span>
                    <div>
                      <Link to={`/inventory/products/${m.id}`} onClick={(e) => e.stopPropagation()}>{m.name}</Link>
                      <div className="muted small">
                        {m.code}{m.brandName ? ` · ${m.brandName}` : ''}{m.gender ? ` · ${genderLabel(m.gender)}` : ''}
                        {!m.isActive && ' · Ngừng bán'}
                      </div>
                    </div>
                  </div>
                </td>
                <td className="hide-sm">{m.categoryName}</td>
                <td className="num">
                  {m.minPrice === m.maxPrice ? formatMoney(m.minPrice) : `${formatMoney(m.minPrice)} – ${formatMoney(m.maxPrice)}`}
                </td>
                <td className="num hide-sm">{m.variantCount}</td>
                <td className="num">
                  <b>{formatQty(m.totalStock)}</b>
                  {m.lowStockVariants > 0 && <div className="small warn-text">{m.lowStockVariants} mã sắp hết</div>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination data={data} unit="mẫu sản phẩm" onPageChange={setPage} />

      {creating && (
        <ProductFormModal lookups={lookups} onClose={() => setCreating(false)}
          onSaved={(saved) => navigate(`/inventory/products/${saved.id}`)} />
      )}
    </InventoryLayout>
  )
}
