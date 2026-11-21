import { useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { inventoryApi } from '../../api/retailApi'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import { GENDERS, SIZE_PRESETS } from '../../constants'
import { formatMoney } from '../../utils/format'

/** Ô nhập dạng chip: gõ rồi Enter / dấu phẩy để thêm. locked = chip đã có SKU, không bỏ được. */
function ChipInput({ values, onChange, locked = [], suggestions = [], placeholder, label }) {
  const [text, setText] = useState('')
  const has = (v) => values.some((x) => x.toLowerCase() === v.toLowerCase())
  const add = (raw) => {
    const items = raw.split(',').map((s) => s.trim()).filter(Boolean)
    const next = [...values]
    for (const it of items) if (!next.some((x) => x.toLowerCase() === it.toLowerCase())) next.push(it)
    onChange(next)
    setText('')
  }
  const remove = (v) => onChange(values.filter((x) => x !== v))
  const toggle = (v) => (has(v) ? !locked.includes(v) && remove(values.find((x) => x.toLowerCase() === v.toLowerCase())) : add(v))

  return (
    <div className="chip-field">
      <div className="chip-input" onClick={(e) => e.currentTarget.querySelector('input')?.focus()}>
        {values.map((v) => (
          <span key={v} className={`chip${locked.includes(v) ? ' locked' : ''}`}>
            {v}
            {!locked.includes(v) && (
              <button type="button" onClick={() => remove(v)} aria-label={`Bỏ ${v}`}><i className="ti ti-x" aria-hidden="true" /></button>
            )}
          </span>
        ))}
        <input value={text} placeholder={values.length ? '' : placeholder} aria-label={label}
          onChange={(e) => (e.target.value.endsWith(',') ? add(e.target.value) : setText(e.target.value))}
          onKeyDown={(e) => {
            if (e.key === 'Enter') { e.preventDefault(); if (text.trim()) add(text) }
            if (e.key === 'Backspace' && !text && values.length && !locked.includes(values.at(-1))) remove(values.at(-1))
          }}
          onBlur={() => text.trim() && add(text)} />
      </div>
      {suggestions.length > 0 && (
        <div className="chip-suggest">
          {suggestions.map((s) => (
            <button type="button" key={s} className={`chip-option${has(s) ? ' on' : ''}`} onClick={() => toggle(s)}>{s}</button>
          ))}
        </div>
      )}
    </div>
  )
}

/**
 * Tạo / sửa mẫu sản phẩm. Chọn màu × size → hệ thống sinh sẵn các SKU (VD ATB01-DEN-M).
 * Khi sửa: thêm được màu / size mới; màu / size đã có SKU thì giữ nguyên (khóa).
 */
export default function ProductFormModal({ model, lookups, onClose, onSaved }) {
  const isNew = !model
  const existingColors = [...new Set((model?.variants ?? []).map((v) => v.color).filter(Boolean))]
  const existingSizes = [...new Set((model?.variants ?? []).map((v) => v.size).filter(Boolean))]

  const [form, setForm] = useState({
    code: model?.code ?? '', name: model?.name ?? '', categoryId: model?.categoryId ?? '', brandId: model?.brandId ?? '',
    uomId: model?.uomId ?? '', salePrice: model?.salePrice ?? 0, costPrice: model?.costPrice ?? 0,
    gender: model?.gender ?? 'unisex', material: model?.material ?? '', season: model?.season ?? '',
    description: model?.description ?? '', isActive: model?.isActive ?? true,
  })
  const [colors, setColors] = useState(existingColors)
  const [sizes, setSizes] = useState(existingSizes)
  const [newCategory, setNewCategory] = useState(null)
  const [newBrand, setNewBrand] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })
  const uomId = form.uomId || lookups.units.find((u) => u.name === 'Cái')?.id || lookups.units[0]?.id || ''
  const skuCount = Math.max(colors.length, 1) * Math.max(sizes.length, 1)
  const newSkuCount = isNew ? skuCount : Math.max(skuCount - (model.variants?.length ?? 0), 0)
  const margin = form.salePrice > 0 ? Math.round(((form.salePrice - form.costPrice) / form.salePrice) * 100) : 0

  const addCategory = async () => {
    if (!newCategory?.trim()) return setNewCategory(null)
    try {
      const c = await inventoryApi.createCategory(newCategory.trim())
      await lookups.reload()
      setForm((f) => ({ ...f, categoryId: c.id }))
      setNewCategory(null)
    } catch (err) { setError(getErrorMessage(err)) }
  }
  const addBrand = async () => {
    if (!newBrand?.trim()) return setNewBrand(null)
    try {
      const b = await inventoryApi.createBrand(newBrand.trim())
      await lookups.reload()
      setForm((f) => ({ ...f, brandId: b.id }))
      setNewBrand(null)
    } catch (err) { setError(getErrorMessage(err)) }
  }

  const save = async (e) => {
    e.preventDefault()
    setError('')
    if (!form.name.trim()) return setError('Nhập tên sản phẩm.')
    if (!uomId) return setError('Chọn đơn vị tính.')
    if (form.salePrice <= 0) return setError('Nhập giá bán.')
    const body = {
      ...form,
      code: form.code.trim() || null,
      categoryId: form.categoryId ? Number(form.categoryId) : null,
      brandId: form.brandId ? Number(form.brandId) : null,
      uomId: Number(uomId),
      gender: form.gender || null,
      material: form.material || null, season: form.season || null, description: form.description || null,
      colors, sizes,
      rowVersion: model?.rowVersion ?? null,
    }
    setBusy(true)
    try {
      const saved = isNew ? await inventoryApi.createModel(body) : await inventoryApi.updateModel(model.id, body)
      onSaved(saved, isNew)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title={isNew ? 'Thêm sản phẩm' : `Sửa sản phẩm ${model.code}`} onClose={onClose} size="large">
      <form onSubmit={save}>
        <div className="form-grid">
          <label className="span2">Tên sản phẩm *
            <input value={form.name} onChange={update('name')} autoFocus placeholder="Áo thun basic cổ tròn" />
          </label>
          <label>Mã sản phẩm
            <input value={form.code} onChange={update('code')} disabled={!isNew} placeholder="Để trống để tự sinh (SP-00001)" />
          </label>
          <label>Đối tượng
            <select value={form.gender} onChange={update('gender')}>
              {GENDERS.map((g) => <option key={g.value} value={g.value}>{g.label}</option>)}
            </select>
          </label>
          <label>Nhóm hàng
            {newCategory === null ? (
              <div className="inline-add">
                <select value={form.categoryId} onChange={update('categoryId')}>
                  <option value="">Chưa phân nhóm</option>
                  {lookups.categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                </select>
                <button type="button" className="btn" onClick={() => setNewCategory('')} title="Thêm nhóm hàng mới" aria-label="Thêm nhóm hàng mới">
                  <i className="ti ti-plus" aria-hidden="true" />
                </button>
              </div>
            ) : (
              <div className="inline-add">
                <input autoFocus value={newCategory} onChange={(e) => setNewCategory(e.target.value)} placeholder="Tên nhóm mới"
                  onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addCategory() } }} />
                <button type="button" className="btn" onClick={addCategory}>Thêm</button>
              </div>
            )}
          </label>
          <label>Thương hiệu
            {newBrand === null ? (
              <div className="inline-add">
                <select value={form.brandId} onChange={update('brandId')}>
                  <option value="">Không có</option>
                  {lookups.brands.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                </select>
                <button type="button" className="btn" onClick={() => setNewBrand('')} title="Thêm thương hiệu mới" aria-label="Thêm thương hiệu mới">
                  <i className="ti ti-plus" aria-hidden="true" />
                </button>
              </div>
            ) : (
              <div className="inline-add">
                <input autoFocus value={newBrand} onChange={(e) => setNewBrand(e.target.value)} placeholder="Tên thương hiệu"
                  onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addBrand() } }} />
                <button type="button" className="btn" onClick={addBrand}>Thêm</button>
              </div>
            )}
          </label>
          <label>Giá bán * <span className="hint-inline">(đã gồm VAT)</span>
            <MoneyInput value={form.salePrice} onChange={(v) => setForm({ ...form, salePrice: v })} />
          </label>
          <label>Giá nhập dự kiến
            <MoneyInput value={form.costPrice} onChange={(v) => setForm({ ...form, costPrice: v })} />
            {form.salePrice > 0 && form.costPrice > 0 && <span className="hint-inline">Lãi {formatMoney(form.salePrice - form.costPrice)} / sp ({margin}%)</span>}
          </label>
          <label>Đơn vị tính
            <select value={uomId} onChange={update('uomId')}>
              {lookups.units.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
            </select>
          </label>
          <label>Chất liệu<input value={form.material} onChange={update('material')} placeholder="Cotton 100%" /></label>
          <label>Mùa / bộ sưu tập<input value={form.season} onChange={update('season')} placeholder="Thu đông 2026" /></label>
          {!isNew && (
            <label className="check">
              <input type="checkbox" checked={form.isActive} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} />
              Đang bán
            </label>
          )}
        </div>

        <div className="variant-box">
          <div className="field-label">Màu sắc</div>
          <ChipInput values={colors} onChange={setColors} locked={existingColors} suggestions={lookups.suggestedColors}
            label="Thêm màu" placeholder="Gõ màu rồi Enter, hoặc bấm màu gợi ý bên dưới" />
          <div className="field-label top-gap">Size</div>
          <div className="chip-suggest presets">
            {SIZE_PRESETS.map((p) => (
              <button type="button" key={p.label} className="chip-option preset"
                onClick={() => setSizes([...sizes, ...p.sizes.filter((s) => !sizes.includes(s))])}>
                + {p.label}
              </button>
            ))}
          </div>
          <ChipInput values={sizes} onChange={setSizes} locked={existingSizes} label="Thêm size" placeholder="Gõ size rồi Enter (S, M, 38...)" />
          <p className="hint-inline top-gap">
            {isNew
              ? <>Sẽ tạo <b>{skuCount}</b> mã SKU ({Math.max(colors.length, 1)} màu × {Math.max(sizes.length, 1)} size). Không chọn màu / size thì tạo 1 mã duy nhất.</>
              : newSkuCount > 0 ? <>Sẽ thêm <b>{newSkuCount}</b> mã SKU mới.</> : 'Thêm màu / size mới để sinh thêm SKU. Giá từng SKU sửa ở bảng biến thể.'}
          </p>
        </div>

        <label>Mô tả<textarea rows={2} value={form.description} onChange={update('description')} /></label>

        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Lưu'}</button>
        </div>
      </form>
    </Modal>
  )
}
