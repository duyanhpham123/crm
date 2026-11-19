import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'

/** Chặn trang cần đăng nhập: chưa đăng nhập thì chuyển về /login, đăng nhập xong quay lại đúng trang. */
export default function ProtectedRoute() {
  const { status } = useAuth()
  const location = useLocation()

  if (status === 'loading') return <div className="center-screen muted">Đang tải...</div>
  if (status !== 'authenticated') {
    const returnUrl = location.pathname + location.search
    return <Navigate to={`/login?returnUrl=${encodeURIComponent(returnUrl)}`} replace />
  }
  return <Outlet />
}
