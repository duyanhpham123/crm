import { Link } from 'react-router-dom'

export default function NotFoundPage() {
  return (
    <div className="center-screen">
      <h2>Không tìm thấy trang</h2>
      <Link className="btn" to="/">Về trang chủ</Link>
    </div>
  )
}
