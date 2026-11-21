import { useEffect, useRef, useState } from 'react'
import { catalogApi } from '../api/retailApi'
import { formatMoney, formatQty } from '../utils/format'

/**
 * Ô tìm sản phẩm (SKU) để thêm vào đơn: gõ "thun den m" hoặc mã / mã vạch.
 * Chọn xong gọi onPick(sku) rồi xóa ô để chọn tiếp. Enter = chọn kết quả đang sáng.
 * priceField: 'salePrice' (đơn bán) hoặc 'costPrice' (đơn nhập, phiếu kho)
 */
export default function SkuPicker({ onPick, warehouseId, priceField = 'salePrice', forPurchase = false, placeholder }) {
  const [text, setText] = useState('')
  const [results, setResults] = useState([])
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(0)
  const boxRef = useRef(null)
  const inputRef = useRef(null)

  useEffect(() => {
    if (!open) return
    const timer = setTimeout(() => {
      catalogApi.searchSkus(text, warehouseId, forPurchase)
        .then((r) => { setResults(r); setActive(0) })
        .catch(() => setResults([]))
    }, 200)
    return () => clearTimeout(timer)
  }, [text, open, warehouseId, forPurchase])

  useEffect(() => {
    const onClick = (e) => boxRef.current && !boxRef.current.contains(e.target) && setOpen(false)
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [])

  const pick = (sku) => {
    onPick(sku)
    setText('')
    setOpen(true)
    inputRef.current?.focus()
  }

  const onKeyDown = (e) => {
    if (!open || results.length === 0) return
    if (e.key === 'ArrowDown') { e.preventDefault(); setActive((a) => Math.min(a + 1, results.length - 1)) }
    if (e.key === 'ArrowUp') { e.preventDefault(); setActive((a) => Math.max(a - 1, 0)) }
    if (e.key === 'Enter') { e.preventDefault(); pick(results[active]) }
    if (e.key === 'Escape') setOpen(false)
  }

  return (
    <div className="picker sku-picker" ref={boxRef}>
      <i className="ti ti-barcode" aria-hidden="true" />
      <input
        ref={inputRef}
        value={text}
        placeholder={placeholder ?? 'Thêm sản phẩm: gõ tên, màu, size hoặc mã (VD: thun đen M)'}
        onFocus={() => setOpen(true)}
        onChange={(e) => { setText(e.target.value); setOpen(true) }}
        onKeyDown={onKeyDown}
        aria-label="Tìm sản phẩm"
        role="combobox"
        aria-expanded={open}
      />
      {open && (
        <ul className="picker-list" role="listbox">
          {results.length === 0 && <li className="muted">Không tìm thấy sản phẩm</li>}
          {results.map((s, i) => (
            <li key={s.id} role="option" aria-selected={i === active} className={i === active ? 'active' : ''}
              onMouseEnter={() => setActive(i)} onMouseDown={(e) => { e.preventDefault(); pick(s) }}>
              <div className="sku-row">
                <div>
                  <b>{s.name}</b>
                  <div className="muted small">{s.code}</div>
                </div>
                <div className="sku-meta">
                  <span>{formatMoney(s[priceField])}</span>
                  <span className={`small ${s.available <= 0 ? 'error' : 'muted'}`}>Tồn {formatQty(s.available)}</span>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
