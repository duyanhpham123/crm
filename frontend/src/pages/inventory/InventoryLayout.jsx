import { useCallback, useEffect, useState } from 'react'
import { inventoryApi } from '../../api/retailApi'
import ModuleLayout from '../../layouts/ModuleLayout'

const MENU = [
  { to: '/inventory/products', icon: 'shirt', label: 'Sản phẩm' },
  { to: '/inventory/stock', icon: 'packages', label: 'Tồn kho' },
  { to: '/inventory/documents', icon: 'file-invoice', label: 'Phiếu kho' },
]

export default function InventoryLayout({ children }) {
  return (
    <ModuleLayout title="Kho" icon="building-warehouse" color="#BA7517" menu={MENU}>
      {children}
    </ModuleLayout>
  )
}

const EMPTY = { categories: [], brands: [], units: [], warehouses: [], suggestedColors: [], suggestedSizes: [] }

/** Danh mục của Kho (nhóm hàng, thương hiệu, đơn vị, kho, màu/size gợi ý). reload() sau khi thêm nhóm / thương hiệu. */
export function useInventoryLookups() {
  const [lookups, setLookups] = useState(EMPTY)
  const reload = useCallback(() => inventoryApi.lookups().then(setLookups).catch(() => {}), [])
  useEffect(() => { reload() }, [reload])
  return { ...lookups, reload }
}
