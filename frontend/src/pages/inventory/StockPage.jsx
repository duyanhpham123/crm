import { useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { inventoryApi } from '../../api/retailApi'
import Pagination from '../../components/Pagination'
import { formatMoney, formatQty } from '../../utils/format'
import InventoryLayout, { useInventoryLookups } from './InventoryLayout'

/** Tồn kho theo từng SKU, lọc nhóm hàng / kho / chỉ hàng sắp hết. */
export default function StockPage() {
  const lookups = useInventoryLookups()
  const [params] = useSearchParams()
  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ search: '', categoryId: '', warehouseId: '', lowOnly: params.get('low') === '1' })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    try {
      setError('')
      setData(await inventoryApi.stock({ ...filters, page, pageSize: 50 }))
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }, [filters, page])

  useEffect(() => {
    const timer = setTimeout(load, 250)
    return () => clearTimeout(timer)
  }, [load])

  const setFilter = (field) => (e) => {
    setFilters({ ...filters, [field]: e.target.type === 'checkbox' ? e.target.checked : e.target.value })
    setPage(1)
  }
  const s = data?.summary

  return (
    <InventoryLayout>
      <div className="page-head"><h1>Tồn kho</h1></div>

      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Tổng số lượng</span><b>{s ? formatQty(s.totalQuantity) : '…'}</b></div>
        <div className="kpi"><span className="muted small">Giá trị tồn (giá vốn)</span><b>{s ? formatMoney(Math.round(s.totalValue)) : '…'}</b></div>
        <div className="kpi"><span className="muted small">Số mã SKU</span><b>{s?.skuCount ?? '…'}</b></div>
        <button type="button" className={`kpi clickable-kpi${filters.lowOnly ? ' on' : ''}`}
          onClick={() => { setFilters({ ...filters, lowOnly: !filters.lowOnly }); setPage(1) }}>
          <span className="muted small">Sắp hết / hết hàng</span>
          <b className="warn-text">{s ? `${s.lowStockCount} / ${s.outOfStockCount}` : '…'}</b>
        </button>
      </div>

      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm tên, mã SKU, màu, size" value={filters.search} onChange={setFilter('search')} aria-label="Tìm trong tồn kho" />
        </div>
        <select value={filters.categoryId} onChange={setFilter('categoryId')} aria-label="Lọc nhóm hàng">
          <option value="">Mọi nhóm hàng</option>
          {lookups.categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        {lookups.warehouses.length > 1 && (
          <select value={filters.warehouseId} onChange={setFilter('warehouseId')} aria-label="Lọc kho">
            <option value="">Mọi kho</option>
            {lookups.warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
          </select>
        )}
        <label className="check toolbar-check">
          <input type="checkbox" checked={filters.lowOnly} onChange={setFilter('lowOnly')} /> Chỉ hàng sắp hết
        </label>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr>
              <th>Sản phẩm</th>
              <th className="hide-sm">Nhóm</th>
              <th className="num">Tồn</th>
              <th className="num hide-sm">Tối thiểu</th>
              <th className="num hide-sm">Giá vốn TB</th>
              <th className="num">Giá trị</th>
            </tr>
          </thead>
          <tbody>
            {!data && <tr><td colSpan={6} className="muted center">Đang tải...</td></tr>}
            {data?.rows.items.length === 0 && <tr><td colSpan={6} className="muted center">Không có mặt hàng nào.</td></tr>}
            {data?.rows.items.map((r) => (
              <tr key={`${r.productId}-${r.warehouseName}`}>
                <td>
                  <div>{r.name}</div>
                  <div className="muted small code-inline">{r.code}</div>
                </td>
                <td className="hide-sm">{r.categoryName}</td>
                <td className="num">
                  <b className={r.onHand <= 0 ? 'error' : r.isLow ? 'warn-text' : ''}>{formatQty(r.onHand)}</b>
                  {r.onHand <= 0 ? <div className="small error">Hết hàng</div> : r.isLow && <div className="small warn-text">Sắp hết</div>}
                </td>
                <td className="num hide-sm muted">{formatQty(r.minStock)}</td>
                <td className="num hide-sm">{formatMoney(Math.round(r.avgCost))}</td>
                <td className="num">{formatMoney(Math.round(r.stockValue))}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination data={data?.rows} unit="mã SKU" onPageChange={setPage} />
    </InventoryLayout>
  )
}
