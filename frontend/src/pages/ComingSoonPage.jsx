import { Link, useParams } from 'react-router-dom'
import AppIcon from '../components/AppIcon'
import { useAuth } from '../context/AuthContext'
import NotFoundPage from './NotFoundPage'

/** Trang tạm cho ứng dụng chưa làm (Kho, Kế toán...). */
export default function ComingSoonPage() {
  const { slug } = useParams()
  const { apps } = useAuth()
  const app = apps.find((a) => a.route?.replace(/^\//, '') === slug)

  if (!app) return <NotFoundPage />

  return (
    <div className="center-screen">
      <AppIcon icon={app.icon} color={app.color} />
      <h2>{app.name}</h2>
      <p className="muted">Ứng dụng này đang được phát triển.</p>
      <Link className="btn" to="/">
        <i className="ti ti-arrow-left" aria-hidden="true" /> Về màn hình ứng dụng
      </Link>
    </div>
  )
}
