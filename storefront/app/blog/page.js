import Link from 'next/link'
import { getPosts } from '../../lib/erp'
import { dateVi } from '../../lib/format'

export const metadata = { title: 'Blog' }

export default async function BlogPage({ searchParams }) {
  const { category = '' } = await searchParams
  const posts = await getPosts(category || undefined)
  return (
    <>
      <h1>Blog</h1>
      {posts.length === 0 && <p className="muted">Chưa có bài viết.</p>}
      <div className="post-list">
        {posts.map((p) => (
          <Link key={p.slug} href={`/blog/${p.slug}`} className="post-card">
            {p.thumbnailUrl && <img src={p.thumbnailUrl} alt="" />}
            <span className="muted small">{p.category} · {dateVi(p.publishedAt)}</span>
            <b>{p.title}</b>
            {p.summary && <span className="muted">{p.summary}</span>}
          </Link>
        ))}
      </div>
    </>
  )
}
