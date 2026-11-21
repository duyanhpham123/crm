import ModuleLayout from '../../layouts/ModuleLayout'

const MENU = [
  { to: '/purchasing/orders', icon: 'file-invoice', label: 'Đơn nhập hàng' },
  { to: '/purchasing/suppliers', icon: 'building-factory-2', label: 'Nhà cung cấp' },
]

export default function PurchasingLayout({ children }) {
  return (
    <ModuleLayout title="Mua hàng" icon="basket-down" color="#639922" menu={MENU}>
      {children}
    </ModuleLayout>
  )
}
