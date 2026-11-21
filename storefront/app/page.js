import Link from 'next/link'
import ProductCard from '../components/ProductCard'
import { getPosts, getProducts, getSite } from '../lib/erp'
import { dateVi } from '../lib/format'

export default async function HomePage() {
  const [site, featured, all, posts] = await Promise.all([getSite(), getProducts({ featured: true }), getProducts({ sort: 'newest' }), getPosts()])
  const highlight = featured.length > 0 ? featured : all.slice(0, 8)
  return (
    <>
      <section className="hero">
        <h1>{site.name}</h1>
        {site.settings.slogan && <p>{site.settings.slogan}</p>}
        <Link href="/san-pham" className="btn primary">Xem tất cả sản phẩm</Link>
        {site.settings.freeShippingFrom && <p className="small">Miễn phí giao hàng cho đơn từ {Number(site.settings.freeShippingFrom).toLocaleString('vi-VN')} đ</p>}
      </section>

      {site.categories.length > 0 && (
        <section>
          <h2>Danh mục</h2>
          <div className="chips">
            {site.categories.map((c) => <Link key={c.slug} href={`/san-pham?category=${c.slug}`} className="chip">{c.name} <span className="muted">({c.count})</span></Link>)}
          </div>
        </section>
      )}

      <section>
        <h2>{featured.length > 0 ? 'Sản phẩm nổi bật' : 'Sản phẩm mới'}</h2>
        <div className="grid">{highlight.map((p) => <ProductCard key={p.slug} product={p} />)}</div>
      </section>

      {posts.length > 0 && (
        <section>
          <h2>Bài viết mới</h2>
          <div className="post-list">
            {posts.slice(0, 3).map((p) => (
              <Link key={p.slug} href={`/blog/${p.slug}`} className="post-card">
                <span className="muted small">{p.category} · {dateVi(p.publishedAt)}</span>
                <b>{p.title}</b>
                {p.summary && <span className="muted">{p.summary}</span>}
              </Link>
            ))}
          </div>
        </section>
      )}
    </>
  )
}
