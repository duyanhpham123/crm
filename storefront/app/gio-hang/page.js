import Checkout from '../../components/Checkout'
import { getSite } from '../../lib/erp'

export const metadata = { title: 'Giỏ hàng' }

export default async function CartPage() {
  const site = await getSite()
  return (
    <>
      <h1>Giỏ hàng</h1>
      <Checkout shippingFee={site.settings.shippingFee ?? 30000} freeShippingFrom={site.settings.freeShippingFrom ?? null} />
    </>
  )
}
