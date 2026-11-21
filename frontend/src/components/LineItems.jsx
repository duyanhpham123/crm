import { formatMoney, formatQty } from '../utils/format'
import MoneyInput from './MoneyInput'
import SkuPicker from './SkuPicker'

/** Thành tiền 1 dòng sau chiết khấu % (làm tròn đồng như backend) */
export const lineTotal = (l) => Math.round((Number(l.quantity) || 0) * (Number(l.unitPrice) || 0) * (1 - (Number(l.discountPercent) || 0) / 100))
export const linesSubTotal = (lines) => lines.reduce((s, l) => s + lineTotal(l), 0)

/** SkuOption từ API → dòng hàng. Đã có SKU trong đơn thì chỉ tăng số lượng. */
export function addSku(lines, sku, priceField) {
  const existing = lines.find((l) => l.productId === sku.id)
  if (existing) return lines.map((l) => (l === existing ? { ...l, quantity: Number(l.quantity) + 1 } : l))
  return [...lines, {
    productId: sku.id, code: sku.code, name: sku.name, color: sku.color, size: sku.size,
    quantity: 1, unitPrice: sku[priceField], discountPercent: 0, available: sku.available,
  }]
}

/**
 * Bảng dòng hàng dùng chung cho Đơn bán và Đơn nhập.
 * mode: 'sale' (giá bán, cảnh báo vượt tồn) | 'purchase' (giá nhập)
 * readOnly: chỉ xem (đơn đã xác nhận)
 */
export default function LineItems({ lines, onChange, mode = 'sale', readOnly = false, warehouseId, showReceived = false }) {
  const priceField = mode === 'sale' ? 'salePrice' : 'costPrice'
  const set = (index, field, value) => onChange(lines.map((l, i) => (i === index ? { ...l, [field]: value } : l)))
  const remove = (index) => onChange(lines.filter((_, i) => i !== index))

  return (
    <div className="lines">
      {!readOnly && (
        <SkuPicker warehouseId={warehouseId} priceField={priceField} forPurchase={mode === 'purchase'}
          onPick={(sku) => onChange(addSku(lines, sku, priceField))} />
      )}
      <div className="table-wrap">
        <table className="grid lines-grid">
          <thead>
            <tr>
              <th>Sản phẩm</th>
              <th className="num qty-col">SL</th>
              <th className="num price-col">{mode === 'sale' ? 'Đơn giá' : 'Giá nhập'}</th>
              <th className="num disc-col">CK %</th>
              <th className="num">Thành tiền</th>
              {showReceived && <th className="num">Đã nhận</th>}
              {!readOnly && <th className="actions" />}
            </tr>
          </thead>
          <tbody>
            {lines.length === 0 && (
              <tr><td colSpan={7} className="muted center">{readOnly ? 'Không có sản phẩm.' : 'Chưa có sản phẩm. Tìm và chọn ở ô phía trên.'}</td></tr>
            )}
            {lines.map((l, i) => {
              const short = mode === 'sale' && !readOnly && l.available !== undefined && Number(l.quantity) > l.available
              return (
                <tr key={l.productId}>
                  <td>
                    <div>{l.name}</div>
                    <div className="muted small">
                      {l.code}
                      {mode === 'sale' && !readOnly && l.available !== undefined && (
                        <span className={short ? 'error' : ''}> · tồn {formatQty(l.available)}{short ? ' - không đủ hàng' : ''}</span>
                      )}
                    </div>
                  </td>
                  <td className="num">
                    {readOnly ? formatQty(l.quantity) : (
                      <input type="number" min="1" step="1" className={`qty-input${short ? ' invalid' : ''}`} value={l.quantity}
                        onChange={(e) => set(i, 'quantity', e.target.value)} aria-label={`Số lượng ${l.code}`} />
                    )}
                  </td>
                  <td className="num">
                    {readOnly ? formatMoney(l.unitPrice) : (
                      <MoneyInput className="price-input" value={l.unitPrice} onChange={(v) => set(i, 'unitPrice', v)} aria-label={`Đơn giá ${l.code}`} />
                    )}
                  </td>
                  <td className="num">
                    {readOnly ? (Number(l.discountPercent) ? `${formatQty(l.discountPercent)}%` : '') : (
                      <input type="number" min="0" max="100" className="disc-input" value={l.discountPercent}
                        onChange={(e) => set(i, 'discountPercent', e.target.value)} aria-label={`Chiết khấu ${l.code}`} />
                    )}
                  </td>
                  <td className="num"><b>{formatMoney(lineTotal(l))}</b></td>
                  {showReceived && <td className="num">{formatQty(l.qtyReceived ?? 0)}</td>}
                  {!readOnly && (
                    <td className="actions">
                      <button type="button" className="btn ghost danger" onClick={() => remove(i)} aria-label={`Bỏ ${l.code}`}>
                        <i className="ti ti-trash" aria-hidden="true" />
                      </button>
                    </td>
                  )}
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}
