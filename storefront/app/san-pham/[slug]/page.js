import Link from 'next/link'
import { notFound } from 'next/navigation'
import AddToCart from '../../../components/AddToCart'
import ProductCard, { ProductImage } from '../../../components/ProductCard'
import { getProduct, orNull } from '../../../lib/erp'
import { priceText } from '../../../lib/format'

export async function generateMetadata({ params }) {
  const { slug } = await params
  const p = await orNull(getProduct(slug))
  return p ? { title: p.name, description: p.description ?? `${p.name} - ${priceText(p)}` } : { title: 'Không tìm thấy sản phẩm' }
}

export default async function ProductPage({ params }) {
  const { slug } = await params
  const p = await orNull(getProduct(slug))
  if (!p) notFound()
  return (
    <>
      <nav className="crumbs"><Link href="/san-pham">Sản phẩm</Link>{p.category && <> / <Link href={`/san-pham?category=${p.categorySlug}`}>{p.category}</Link></>} / {p.name}</nav>
      <div className="product-detail">
        <ProductImage product={p} large />
        <div>
          <h1>{p.name}</h1>
          <p className="muted small">Mã: {p.code}{p.material ? ` · Chất liệu: ${p.material}` : ''}</p>
          <p className="p-price big">{priceText(p)}</p>
          <AddToCart product={{ slug: p.slug, name: p.name, imageUrl: p.imageUrl }} variants={p.variants} colors={p.colors} sizes={p.sizes} />
          {p.description && <div className="description"><h2>Mô tả</h2><p className="pre">{p.description}</p></div>}
        </div>
      </div>
      {p.related.length > 0 && (
        <section>
          <h2>Có thể bạn thích</h2>
          <div className="grid">{p.related.map((r) => <ProductCard key={r.slug} product={r} />)}</div>
        </section>
      )}
    </>
  )
}
