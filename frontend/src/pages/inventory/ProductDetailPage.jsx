import { useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { inventoryApi } from '../../api/retailApi'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import { genderLabel, RETAIL_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatMoney, formatQty } from '../../utils/format'
import InventoryLayout, { useInventoryLookups } from './InventoryLayout'
import ProductFormModal from './ProductFormModal'

/** Sửa 1 SKU: giá riêng, mã vạch, tồn tối thiểu (cảnh báo sắp hết), ngừng bán */
function VariantModal({ variant, onClose, onSaved }) {
  const [form, setForm] = useState({
    salePrice: variant.salePrice, barcode: variant.barcode ?? '', minStock: variant.minStock, isActive: variant.isActive,
  })
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const save = async (e) => {
    e.preventDefault()
    setBusy(true)
    try {
      await inventoryApi.updateVariant(variant.id, { ...form, barcode: form.barcode || null, minStock: Number(form.minStock) || 0 })
      onSaved()
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title={`SKU ${variant.code}`} onClose={onClose} size="small">
      <form onSubmit={save}>
        <label>Giá bán<MoneyInput value={form.salePrice} onChange={(v) => setForm({ ...form, salePrice: v })} autoFocus /></label>
        <label>Mã vạch<input value={form.barcode} onChange={(e) => setForm({ ...form, barcode: e.target.value })} placeholder="8934567890123" /></label>
        <label>Tồn tối thiểu <span className="hint-inline">(còn ít hơn hoặc bằng thì báo sắp hết)</span>
          <input type="number" min="0" value={form.minStock} onChange={(e) => setForm({ ...form, minStock: e.target.value })} />
        </label>
        <label className="check">
          <input type="checkbox" checked={form.isActive} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} /> Đang bán
        </label>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Lưu'}</button>
        </div>
      </form>
    </Modal>
  )
}

/** Chi tiết mẫu sản phẩm: bảng tồn theo màu × size và danh sách SKU. */
export default function ProductDetailPage() {
  const { id } = useParams()
  const { can } = useAuth()
  const lookups = useInventoryLookups()
  const [model, setModel] = useState(null)
  const [error, setError] = useState('')
  const [editing, setEditing] = useState(false)
  const [variant, setVariant] = useState(null)
  const [message, setMessage] = useState('')
  const canEdit = can(RETAIL_PERMISSIONS.INVENTORY_EDIT)

  const load = useCallback(async () => {
    try {
      setModel(await inventoryApi.getModel(id))
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }, [id])

  useEffect(() => { load() }, [load])

  if (error && !model) return <InventoryLayout><div className="alert error">{error}</div><Link to="/inventory/products">← Danh sách sản phẩm</Link></InventoryLayout>
  if (!model) return <InventoryLayout><p className="muted">Đang tải...</p></InventoryLayout>

  const colors = [...new Set(model.variants.map((v) => v.color ?? ''))]
  const sizes = [...new Set(model.variants.map((v) => v.size ?? ''))]
  const cell = (c, s) => model.variants.find((v) => (v.color ?? '') === c && (v.size ?? '') === s)
  const totalStock = model.variants.reduce((s, v) => s + v.onHand, 0)
  const stockValue = model.variants.reduce((s, v) => s + v.onHand * v.costPrice, 0)
  const lowCount = model.variants.filter((v) => v.isActive && v.onHand <= v.minStock).length

  return (
    <InventoryLayout>
      <div className="breadcrumb"><Link to="/inventory/products">Sản phẩm</Link> / {model.code}</div>
      <div className="page-head">
        <div>
          <h1>{model.name}</h1>
          <div className="muted">
            {model.code}{model.categoryName ? ` · ${model.categoryName}` : ''}{model.brandName ? ` · ${model.brandName}` : ''}
            {model.gender ? ` · ${genderLabel(model.gender)}` : ''}
            {!model.isActive && <span className="pill cancelled small-pill">Ngừng bán</span>}
          </div>
        </div>
        {canEdit && (
          <button className="btn" onClick={() => setEditing(true)}><i className="ti ti-pencil" aria-hidden="true" /> Sửa / thêm màu, size</button>
        )}
      </div>

      {message && <div className="alert success">{message}</div>}

      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Giá bán</span><b>{formatMoney(model.salePrice)}</b></div>
        <div className="kpi"><span className="muted small">Số SKU</span><b>{model.variants.length}</b></div>
        <div className="kpi"><span className="muted small">Tồn kho</span><b>{formatQty(totalStock)}</b></div>
        <div className="kpi"><span className="muted small">Giá trị tồn (giá vốn)</span><b>{formatMoney(Math.round(stockValue))}</b></div>
        <div className="kpi"><span className="muted small">Sắp hết hàng</span><b className={lowCount ? 'warn-text' : ''}>{lowCount} mã</b></div>
      </div>

      {colors.length * sizes.length > 1 && (
        <>
          <div className="section-head"><h2>Tồn kho theo màu × size</h2></div>
          <div className="table-wrap">
            <table className="grid stock-matrix">
              <thead>
                <tr><th>Màu \ Size</th>{sizes.map((s) => <th key={s} className="center">{s || '-'}</th>)}<th className="num">Cộng</th></tr>
              </thead>
              <tbody>
                {colors.map((c) => (
                  <tr key={c}>
                    <td><b>{c || '-'}</b></td>
                    {sizes.map((s) => {
                      const v = cell(c, s)
                      if (!v) return <td key={s} className="center muted">·</td>
                      const cls = v.onHand <= 0 ? 'out' : v.onHand <= v.minStock ? 'low' : ''
                      return <td key={s} className={`center ${cls}`} title={v.code}>{formatQty(v.onHand)}</td>
                    })}
                    <td className="num"><b>{formatQty(model.variants.filter((v) => (v.color ?? '') === c).reduce((t, v) => t + v.onHand, 0))}</b></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="hint-inline top-gap"><span className="legend low" /> sắp hết <span className="legend out" /> hết hàng</p>
        </>
      )}

      <div className="section-head"><h2>Danh sách SKU</h2></div>
      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr>
              <th>Mã SKU</th><th>Màu</th><th>Size</th><th className="hide-sm">Mã vạch</th>
              <th className="num">Giá bán</th><th className="num hide-sm">Giá vốn</th><th className="num">Tồn</th>
              {canEdit && <th className="actions" />}
            </tr>
          </thead>
          <tbody>
            {model.variants.map((v) => (
              <tr key={v.id} className={v.isActive ? '' : 'inactive'}>
                <td className="code">{v.code}</td>
                <td>{v.color}</td>
                <td>{v.size}</td>
                <td className="hide-sm code">{v.barcode}</td>
                <td className="num">{formatMoney(v.salePrice)}</td>
                <td className="num hide-sm muted">{formatMoney(Math.round(v.costPrice))}</td>
                <td className="num">
                  <span className={v.onHand <= 0 ? 'error' : v.onHand <= v.minStock ? 'warn-text' : ''}>{formatQty(v.onHand)}</span>
                </td>
                {canEdit && (
                  <td className="actions">
                    <button className="btn ghost" onClick={() => setVariant(v)} aria-label={`Sửa ${v.code}`}><i className="ti ti-pencil" aria-hidden="true" /></button>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {model.description && <><div className="section-head"><h2>Mô tả</h2></div><div className="note">{model.description}</div></>}

      {editing && (
        <ProductFormModal model={model} lookups={lookups} onClose={() => setEditing(false)}
          onSaved={(saved) => { setModel(saved); setEditing(false); setMessage('Đã lưu sản phẩm.') }} />
      )}
      {variant && (
        <VariantModal variant={variant} onClose={() => setVariant(null)}
          onSaved={() => { setVariant(null); setMessage(`Đã lưu SKU ${variant.code}.`); load() }} />
      )}
    </InventoryLayout>
  )
}
