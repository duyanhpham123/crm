import { useEffect, useState } from 'react'
import { salesApi } from '../../api/retailApi'
import ModuleLayout from '../../layouts/ModuleLayout'

const MENU = [
  { to: '/orders', icon: 'list-details', label: 'Đơn hàng', end: true },
  { to: '/orders/new', icon: 'shopping-cart-plus', label: 'Tạo đơn' },
]

export default function OrdersLayout({ children }) {
  return (
    <ModuleLayout title="Đơn hàng" icon="shopping-cart" color="#378ADD" menu={MENU}>
      {children}
    </ModuleLayout>
  )
}

const EMPTY = { warehouses: [], salespeople: [], channels: [], paymentMethods: [] }

/** Danh mục bán hàng: kho, nhân viên, kênh bán, hình thức thanh toán */
export function useSalesLookups() {
  const [lookups, setLookups] = useState(EMPTY)
  useEffect(() => { salesApi.lookups().then(setLookups).catch(() => {}) }, [])
  const channelName = (code) => lookups.channels.find((c) => c.code === code)?.name ?? code
  const paymentName = (code) => lookups.paymentMethods.find((c) => c.code === code)?.name ?? code
  return { ...lookups, channelName, paymentName }
}

/** Biểu tượng cho từng kênh bán */
export const CHANNEL_ICONS = {
  direct: 'building-store', facebook: 'brand-facebook', shopee: 'shopping-bag', tiktok: 'brand-tiktok',
  lazada: 'package', website: 'world', zalo: 'message-circle', phone: 'phone', other: 'dots',
}
