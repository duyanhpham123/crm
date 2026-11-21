'use client'

import Link from 'next/link'
import { useState } from 'react'
import { money } from '../lib/format'
import { useCart } from './Cart'

/** Chọn màu → size → số lượng. Màu / size hết hàng bị làm mờ. */
export default function AddToCart({ product, variants, colors, sizes }) {
  const { add } = useCart()
  const [color, setColor] = useState(colors.length === 1 ? colors[0] : null)
  const [size, setSize] = useState(sizes.length === 1 ? sizes[0] : null)
  const [qty, setQty] = useState(1)
  const [added, setAdded] = useState(false)
  const match = (c, s) => variants.find((v) => (colors.length === 0 || v.color === c) && (sizes.length === 0 || v.size === s))
  const variant = match(color, size)
  const sizeAvailable = (s) => variants.some((v) => v.size === s && (color === null || v.color === color) && v.inStock)
  const colorAvailable = (c) => variants.some((v) => v.color === c && v.inStock)
  const needColor = colors.length > 0 && !color
  const needSize = sizes.length > 0 && !size

  const onAdd = () => {
    if (!variant?.inStock) return
    add({ sku: variant.sku, slug: product.slug, name: product.name, imageUrl: product.imageUrl, color: variant.color, size: variant.size, price: variant.price, available: variant.available }, qty)
    setAdded(true)
  }

  return (
    <div className="buy-box">
      {colors.length > 0 && (
        <div className="opt"><span>Màu: <b>{color ?? 'chọn màu'}</b></span>
          <div className="chips">{colors.map((c) => (
            <button key={c} type="button" className={`chip${color === c ? ' on' : ''}${colorAvailable(c) ? '' : ' disabled'}`} onClick={() => { setColor(c); setAdded(false) }}>{c}</button>
          ))}</div>
        </div>
      )}
      {sizes.length > 0 && (
        <div className="opt"><span>Size: <b>{size ?? 'chọn size'}</b></span>
          <div className="chips">{sizes.map((s) => (
            <button key={s} type="button" className={`chip${size === s ? ' on' : ''}${sizeAvailable(s) ? '' : ' disabled'}`} onClick={() => { setSize(s); setAdded(false) }}>{s}</button>
          ))}</div>
        </div>
      )}
      {variant && (
        <p className={variant.inStock ? 'ok' : 'out'}>
          {variant.inStock ? `Còn hàng${variant.available < 10 ? ` (còn ${variant.available})` : ''} · ${money(variant.price)}` : 'Màu / size này đã hết hàng'}
        </p>
      )}
      <div className="qty-row">
        <label>Số lượng <input type="number" min="1" max={Math.min(20, variant?.available ?? 20)} value={qty} onChange={(e) => setQty(Math.max(1, Number(e.target.value) || 1))} /></label>
        <button type="button" className="btn primary" disabled={needColor || needSize || !variant?.inStock} onClick={onAdd}>
          {needColor ? 'Chọn màu' : needSize ? 'Chọn size' : 'Thêm vào giỏ'}
        </button>
      </div>
      {added && <p className="ok">Đã thêm vào giỏ. <Link href="/gio-hang">Xem giỏ hàng →</Link></p>}
    </div>
  )
}
