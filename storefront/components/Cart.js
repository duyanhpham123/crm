'use client'

import Link from 'next/link'
import { createContext, useContext, useEffect, useMemo, useState } from 'react'

/**
 * Giỏ hàng lưu ở trình duyệt khách (localStorage). Giá ở đây chỉ để hiển thị -
 * lúc đặt hàng ERP tính lại giá, tồn kho, phí ship, mã giảm giá.
 */
const CartContext = createContext(null)
const KEY = 'storefront.cart'

export function CartProvider({ children }) {
  const [items, setItems] = useState([])
  const [ready, setReady] = useState(false)
  useEffect(() => {
    try { setItems(JSON.parse(localStorage.getItem(KEY)) || []) } catch { setItems([]) }
    setReady(true)
  }, [])
  useEffect(() => {
    if (ready) try { localStorage.setItem(KEY, JSON.stringify(items)) } catch { /* trình duyệt chặn lưu */ }
  }, [items, ready])

  const value = useMemo(() => ({
    items,
    ready,
    count: items.reduce((t, i) => t + i.qty, 0),
    subTotal: items.reduce((t, i) => t + i.qty * i.price, 0),
    add: (item, qty) => setItems((list) => {
      const found = list.find((i) => i.sku === item.sku)
      const max = Math.min(20, item.available ?? 20)
      if (found) return list.map((i) => (i.sku === item.sku ? { ...i, qty: Math.min(max, i.qty + qty) } : i))
      return [...list, { ...item, qty: Math.min(max, qty) }]
    }),
    setQty: (sku, qty) => setItems((list) => list.map((i) => (i.sku === sku ? { ...i, qty: Math.max(1, Math.min(20, i.available ?? 20, qty)) } : i))),
    remove: (sku) => setItems((list) => list.filter((i) => i.sku !== sku)),
    clear: () => setItems([]),
  }), [items, ready])
  return <CartContext.Provider value={value}>{children}</CartContext.Provider>
}

export const useCart = () => useContext(CartContext)

export function CartButton() {
  const { count } = useCart()
  return (
    <Link href="/gio-hang" className="cart-btn" aria-label={`Giỏ hàng: ${count} sản phẩm`}>
      Giỏ hàng {count > 0 && <span className="badge">{count}</span>}
    </Link>
  )
}
