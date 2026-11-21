import Link from 'next/link'
import { notFound } from 'next/navigation'
import { getPost, orNull } from '../../../lib/erp'
import { dateVi } from '../../../lib/format'

export async function generateMetadata({ params }) {
  const { slug } = await params
  const p = await orNull(getPost(slug))
  return p ? { title: p.title, description: p.summary } : { title: 'Không tìm thấy bài viết' }
}

export default async function PostPage({ params }) {
  const { slug } = await params
  const p = await orNull(getPost(slug))
  if (!p) notFound()
  return (
    <article className="article">
      <nav className="crumbs"><Link href="/blog">Blog</Link> / {p.category}</nav>
      <h1>{p.title}</h1>
      <p className="muted small">{dateVi(p.publishedAt)}</p>
      {p.thumbnailUrl && <img src={p.thumbnailUrl} alt="" className="cover" />}
      {p.summary && <p className="lead">{p.summary}</p>}
      <div className="pre">{p.content}</div>
    </article>
  )
}
