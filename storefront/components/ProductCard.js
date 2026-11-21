import Link from 'next/link'
import { initials, priceText } from '../lib/format'

export function ProductImage({ product, large = false }) {
  return product.imageUrl
    ? <img className={`p-img${large ? ' large' : ''}`} src={product.imageUrl} alt={product.name} />
    : <div className={`p-img placeholder${large ? ' large' : ''}`} aria-hidden="true">{initials(product.name)}</div>
}

export default function ProductCard({ product }) {
  return (
    <Link href={`/san-pham/${product.slug}`} className="p-card">
      <ProductImage product={product} />
      <div className="p-body">
        {product.category && <span className="muted small">{product.category}</span>}
        <b className="p-name">{product.name}</b>
        <span className="p-price">{priceText(product)}</span>
        {product.colors.length > 0 && <span className="muted small">{product.colors.length} màu · {product.sizes.join(', ')}</span>}
        {!product.inStock && <span className="tag out">Hết hàng</span>}
      </div>
    </Link>
  )
}
