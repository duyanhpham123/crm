import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { inventoryApi } from '../../api/retailApi'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import Pagination from '../../components/Pagination'
import SkuPicker from '../../components/SkuPicker'
import { MANUAL_REASONS, RETAIL_PERMISSIONS, STOCK_DOC_TYPES, STOCK_REASONS, stockDocType } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateTime, formatMoney, formatQty } from '../../utils/format'
import InventoryLayout, { useInventoryLookups } from './InventoryLayout'

/** Link tới chứng từ gốc (đơn bán / đơn nhập) đã sinh ra phiếu kho */
function SourceLink({ type, id, docNo }) {
  if (!docNo) return null
  if (type === 'sales.SalesOrders' && id) return <Link to={`/orders/${id}`}>{docNo}</Link>
  if (type === 'pur.PurchaseOrders' && id) return <Link to={`/purchasing/orders/${id}`}>{docNo}</Link>
  return <span>{docNo}</span>
}

function DocumentModal({ id, onClose }) {
  const [doc, setDoc] = useState(null)
  const [error, setError] = useState('')
  useEffect(() => { inventoryApi.getDocument(id).then(setDoc).catch((e) => setError(getErrorMessage(e))) }, [id])

  return (
    <Modal title={doc ? `${stockDocType(doc.docType).label} ${doc.docNo}` : 'Phiếu kho'} onClose={onClose} size="large">
      {error && <div className="alert error">{error}</div>}
      {!doc && !error && <p className="muted">Đang tải...</p>}
      {doc && (
        <>
          <dl className="info">
            <dt>Lý do</dt><dd>{STOCK_REASONS[doc.reason] ?? doc.reason}</dd>
            <dt>Kho</dt><dd>{doc.warehouseName}</dd>
            <dt>Ngày</dt><dd>{formatDateTime(doc.docDate)}</dd>
            {doc.partnerName && <><dt>Đối tác</dt><dd>{doc.partnerName}</dd></>}
            {doc.sourceDocNo && <><dt>Chứng từ gốc</dt><dd><SourceLink type={doc.sourceType} id={doc.sourceId} docNo={doc.sourceDocNo} /></dd></>}
            {doc.note && <><dt>Ghi chú</dt><dd>{doc.note}</dd></>}
          </dl>
          <div className="table-wrap">
            <table className="grid">
              <thead><tr><th>Sản phẩm</th><th className="num">Số lượng</th><th className="num">Đơn giá vốn</th><th className="num">Giá trị</th></tr></thead>
              <tbody>
                {doc.lines.map((l) => (
                  <tr key={l.productId}>
                    <td>{l.name}<div className="muted small">{l.code}</div></td>
                    <td className="num">{formatQty(l.quantity)}</td>
                    <td className="num">{formatMoney(Math.round(l.unitCost))}</td>
                    <td className="num">{formatMoney(Math.round(l.lineValue))}</td>
                  </tr>
                ))}
                <tr className="total-row">
                  <td><b>Cộng</b></td><td className="num"><b>{formatQty(doc.totalQuantity)}</b></td><td />
                  <td className="num"><b>{formatMoney(Math.round(doc.totalValue))}</b></td>
                </tr>
              </tbody>
            </table>
          </div>
        </>
      )}
    </Modal>
  )
}

/** Tạo phiếu nhập / xuất / kiểm kê thủ công. Phiếu ghi sổ ngay, tồn kho cập nhật lập tức. */
function CreateDocumentModal({ warehouses, onClose, onSaved }) {
  const [docType, setDocType] = useState('receipt')
  const [reason, setReason] = useState('opening')
  const [warehouseId, setWarehouseId] = useState(warehouses[0]?.id ?? '')
  const [note, setNote] = useState('')
  const [lines, setLines] = useState([])
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const changeType = (t) => { setDocType(t); setReason(MANUAL_REASONS[t][0]) }
  const add = (sku) => setLines((ls) => ls.some((l) => l.productId === sku.id)
    ? ls.map((l) => (l.productId === sku.id ? { ...l, quantity: Number(l.quantity) + 1 } : l))
    : [...ls, { productId: sku.id, code: sku.code, name: sku.name, available: sku.available, quantity: docType === 'adjustment' ? -1 : 1, unitCost: Math.round(sku.costPrice) }])
  const set = (i, field, value) => setLines(lines.map((l, x) => (x === i ? { ...l, [field]: value } : l)))

  const save = async (e) => {
    e.preventDefault()
    setError('')
    if (lines.length === 0) return setError('Chọn ít nhất 1 sản phẩm.')
    if (lines.some((l) => !Number(l.quantity))) return setError('Số lượng phải khác 0.')
    setBusy(true)
    try {
      const saved = await inventoryApi.createDocument({
        docType, reason, warehouseId: Number(warehouseId), note: note || null,
        lines: lines.map((l) => ({ productId: l.productId, quantity: Number(l.quantity), unitCost: docType === 'receipt' ? Number(l.unitCost) : null })),
      })
      onSaved(saved)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title="Tạo phiếu kho" onClose={onClose} size="large">
      <form onSubmit={save}>
        <div className="segmented" role="radiogroup" aria-label="Loại phiếu">
          {STOCK_DOC_TYPES.map((t) => (
            <button type="button" key={t.value} role="radio" aria-checked={docType === t.value}
              className={docType === t.value ? 'on' : ''} onClick={() => changeType(t.value)} disabled={lines.length > 0 && docType !== t.value && (t.value === 'adjustment' || docType === 'adjustment')}>
              <i className={`ti ti-${t.icon}`} aria-hidden="true" /> {t.label}
            </button>
          ))}
        </div>
        <div className="form-grid">
          <label>Lý do
            <select value={reason} onChange={(e) => setReason(e.target.value)}>
              {MANUAL_REASONS[docType].map((r) => <option key={r} value={r}>{STOCK_REASONS[r]}</option>)}
            </select>
          </label>
          <label>Kho
            <select value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
              {warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </label>
          <label className="span2">Ghi chú<input value={note} onChange={(e) => setNote(e.target.value)} placeholder={docType === 'adjustment' ? 'Kiểm kê cuối tháng' : ''} /></label>
        </div>
        {docType === 'adjustment' && <p className="hint">Nhập số <b>âm</b> để giảm tồn (thiếu, mất), số <b>dương</b> để tăng tồn (thừa).</p>}

        <SkuPicker warehouseId={warehouseId} priceField="costPrice" onPick={add} />
        <div className="table-wrap">
          <table className="grid lines-grid">
            <thead>
              <tr>
                <th>Sản phẩm</th><th className="num">Tồn hiện tại</th><th className="num qty-col">{docType === 'adjustment' ? 'Chênh lệch' : 'Số lượng'}</th>
                {docType === 'receipt' && <th className="num price-col">Giá vốn</th>}
                <th className="actions" />
              </tr>
            </thead>
            <tbody>
              {lines.length === 0 && <tr><td colSpan={5} className="muted center">Chưa có sản phẩm. Tìm và chọn ở ô phía trên.</td></tr>}
              {lines.map((l, i) => (
                <tr key={l.productId}>
                  <td>{l.name}<div className="muted small">{l.code}</div></td>
                  <td className="num">{formatQty(l.available)}</td>
                  <td className="num">
                    <input type="number" className="qty-input" value={l.quantity} min={docType === 'adjustment' ? undefined : 1}
                      onChange={(e) => set(i, 'quantity', e.target.value)} aria-label={`Số lượng ${l.code}`} />
                  </td>
                  {docType === 'receipt' && (
                    <td className="num"><MoneyInput className="price-input" value={l.unitCost} onChange={(v) => set(i, 'unitCost', v)} aria-label={`Giá vốn ${l.code}`} /></td>
                  )}
                  <td className="actions">
                    <button type="button" className="btn ghost danger" onClick={() => setLines(lines.filter((_, x) => x !== i))} aria-label={`Bỏ ${l.code}`}>
                      <i className="ti ti-trash" aria-hidden="true" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy}>{busy ? 'Đang ghi sổ...' : 'Ghi sổ phiếu'}</button>
        </div>
      </form>
    </Modal>
  )
}

/** Danh sách phiếu kho: phiếu từ đơn bán / đơn nhập (tự động) và phiếu thủ công. */
export default function StockDocumentsPage() {
  const { can } = useAuth()
  const lookups = useInventoryLookups()
  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ docType: '', search: '' })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const [viewing, setViewing] = useState(null)
  const [creating, setCreating] = useState(false)
  const [message, setMessage] = useState('')

  const load = useCallback(async () => {
    try {
      setError('')
      setData(await inventoryApi.listDocuments({ ...filters, page, pageSize: 20 }))
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }, [filters, page])

  useEffect(() => {
    const timer = setTimeout(load, 250)
    return () => clearTimeout(timer)
  }, [load])

  return (
    <InventoryLayout>
      <div className="page-head">
        <h1>Phiếu kho</h1>
        {can(RETAIL_PERMISSIONS.INVENTORY_CREATE) && (
          <button className="btn primary" onClick={() => setCreating(true)}><i className="ti ti-plus" aria-hidden="true" /> Tạo phiếu</button>
        )}
      </div>

      {message && <div className="alert success">{message}</div>}

      <div className="toolbar">
        <div className="segmented no-margin" role="tablist" aria-label="Loại phiếu">
          {[{ value: '', label: 'Tất cả' }, ...STOCK_DOC_TYPES].map((t) => (
            <button key={t.value} role="tab" aria-selected={filters.docType === t.value} className={filters.docType === t.value ? 'on' : ''}
              onClick={() => { setFilters({ ...filters, docType: t.value }); setPage(1) }}>{t.label}</button>
          ))}
        </div>
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm số phiếu, chứng từ gốc, ghi chú" value={filters.search}
            onChange={(e) => { setFilters({ ...filters, search: e.target.value }); setPage(1) }} aria-label="Tìm phiếu kho" />
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr>
              <th>Số phiếu</th><th>Loại</th><th className="hide-sm">Lý do</th><th className="hide-sm">Chứng từ gốc</th>
              <th className="hide-sm">Ngày</th><th className="num">SL</th><th className="num">Giá trị</th>
            </tr>
          </thead>
          <tbody>
            {!data && <tr><td colSpan={7} className="muted center">Đang tải...</td></tr>}
            {data?.items.length === 0 && <tr><td colSpan={7} className="muted center">Chưa có phiếu kho.</td></tr>}
            {data?.items.map((d) => (
              <tr key={d.id} className="clickable" onClick={() => setViewing(d.id)}>
                <td><button className="link" onClick={(e) => { e.stopPropagation(); setViewing(d.id) }}>{d.docNo}</button>
                  {d.partnerName && <div className="muted small">{d.partnerName}</div>}
                </td>
                <td><span className={`pill ${stockDocType(d.docType).css}`}>{stockDocType(d.docType).label}</span></td>
                <td className="hide-sm">{STOCK_REASONS[d.reason] ?? d.reason}</td>
                <td className="hide-sm" onClick={(e) => e.stopPropagation()}>{d.sourceDocNo ?? <span className="muted">Thủ công</span>}</td>
                <td className="hide-sm">{formatDateTime(d.docDate)}</td>
                <td className="num">{formatQty(d.totalQuantity)}</td>
                <td className="num">{formatMoney(Math.round(d.totalValue))}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination data={data} unit="phiếu" onPageChange={setPage} />

      {viewing && <DocumentModal id={viewing} onClose={() => setViewing(null)} />}
      {creating && (
        <CreateDocumentModal warehouses={lookups.warehouses} onClose={() => setCreating(false)}
          onSaved={(doc) => { setCreating(false); setMessage(`Đã ghi sổ phiếu ${doc.docNo}. Tồn kho đã cập nhật.`); load() }} />
      )}
    </InventoryLayout>
  )
}
