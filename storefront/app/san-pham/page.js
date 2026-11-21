import Link from 'next/link'
import ProductCard from '../../components/ProductCard'
import { getProducts, getSite } from '../../lib/erp'

export const metadata = { title: 'Sản phẩm' }

const SORTS = [['', 'Nổi bật'], ['newest', 'Mới nhất'], ['price_asc', 'Giá tăng dần'], ['price_desc', 'Giá giảm dần']]

export default async function ProductsPage({ searchParams }) {
  const { category = '', sort = '', q = '' } = await searchParams
  const [site, products] = await Promise.all([getSite(), getProducts({ category, sort, search: q })])
  const current = site.categories.find((c) => c.slug === category)
  const link = (patch) => {
    const p = new URLSearchParams(Object.entries({ category, sort, q, ...patch }).filter(([, v]) => v))
    return `/san-pham${p.toString() ? `?${p}` : ''}`
  }
  return (
    <>
      <h1>{current?.name ?? 'Tất cả sản phẩm'} <span className="muted small">({products.length})</span></h1>
      <div className="filters">
        <div className="chips">
          <Link href={link({ category: '' })} className={`chip${!category ? ' on' : ''}`}>Tất cả</Link>
          {site.categories.map((c) => <Link key={c.slug} href={link({ category: c.slug })} className={`chip${category === c.slug ? ' on' : ''}`}>{c.name}</Link>)}
        </div>
        <form action="/san-pham" className="search-form">
          {category && <input type="hidden" name="category" value={category} />}
          <input name="q" defaultValue={q} placeholder="Tìm sản phẩm..." aria-label="Tìm sản phẩm" />
          <select name="sort" defaultValue={sort} aria-label="Sắp xếp">{SORTS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>
          <button className="btn">Lọc</button>
        </form>
      </div>
      {products.length === 0 ? <p className="muted">Không có sản phẩm phù hợp.</p>
        : <div className="grid">{products.map((p) => <ProductCard key={p.slug} product={p} />)}</div>}
    </>
  )
}
