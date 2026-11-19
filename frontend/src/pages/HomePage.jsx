import { Link } from 'react-router-dom'
import AppIcon from '../components/AppIcon'
import { useAuth } from '../context/AuthContext'

/** Màn hình lưới ứng dụng - chỉ hiện ứng dụng người dùng có quyền. */
export default function HomePage() {
  const { apps } = useAuth()

  return (
    <div className="launcher">
      {apps.length === 0 && (
        <p className="muted center">Tài khoản của bạn chưa được cấp quyền ứng dụng nào. Liên hệ quản trị viên.</p>
      )}
      <div className="app-grid">
        {apps.map((app) => (
          <Link key={app.code} className="app-tile" to={app.route || `/${app.code}`}>
            <AppIcon icon={app.icon} color={app.color} />
            <span>{app.name}</span>
          </Link>
        ))}
      </div>
    </div>
  )
}
