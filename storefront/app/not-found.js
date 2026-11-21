import Link from 'next/link'

export default function NotFound() {
  return (
    <div className="center">
      <h1>Không tìm thấy trang</h1>
      <p className="muted">Sản phẩm có thể đã ngừng bán hoặc đường dẫn đã thay đổi.</p>
      <Link href="/san-pham" className="btn primary">Xem sản phẩm</Link>
    </div>
  )
}
