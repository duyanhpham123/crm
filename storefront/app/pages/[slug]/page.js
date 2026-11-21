import { notFound } from 'next/navigation'
import { getPage, orNull } from '../../../lib/erp'

/** Trang tĩnh soạn ở ERP > Website > Bài viết & trang (Giới thiệu, Chính sách đổi trả...). */
export async function generateMetadata({ params }) {
  const { slug } = await params
  const p = await orNull(getPage(slug))
  return p ? { title: p.metaTitle ?? p.title, description: p.metaDescription } : { title: 'Không tìm thấy trang' }
}

export default async function StaticPage({ params }) {
  const { slug } = await params
  const p = await orNull(getPage(slug))
  if (!p) notFound()
  return (
    <article className="article">
      <h1>{p.title}</h1>
      <div className="pre">{p.content}</div>
    </article>
  )
}
