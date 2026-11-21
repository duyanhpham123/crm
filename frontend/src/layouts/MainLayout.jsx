import { useState } from 'react'
import { Link, Outlet, useNavigate } from 'react-router-dom'
import ChangePasswordModal from '../components/ChangePasswordModal'
import { useAuth } from '../context/AuthContext'
import { initials } from '../utils/format'

/** Khung chung sau khi đăng nhập: thanh trên cùng + nội dung trang. */
export default function MainLayout() {
  const { me, logout } = useAuth()
  const navigate = useNavigate()
  const [changingPassword, setChangingPassword] = useState(false)

  const handleLogout = async () => {
    await logout()
    navigate('/login', { replace: true })
  }

  return (
    <div className="shell">
      <header className="topbar">
        <Link className="brand" to="/">
          <i className="ti ti-grid-dots" aria-hidden="true" />
          <span>MyERP</span>
        </Link>
        <span className="spacer" />
        <span className="muted hide-sm">{me.companyName}</span>
        <div className="user-menu">
          <span className="avatar" title={me.fullName}>{initials(me.fullName)}</span>
          <span className="hide-sm">{me.fullName}</span>
          <Link className="btn ghost" to="/ai" title="Trợ lý AI - kết nối Claude với ERP" aria-label="Trợ lý AI">
            <i className="ti ti-robot" aria-hidden="true" />
          </Link>
          <button className="btn ghost" onClick={() => setChangingPassword(true)} title="Đổi mật khẩu" aria-label="Đổi mật khẩu">
            <i className="ti ti-key" aria-hidden="true" />
          </button>
          <button className="btn ghost" onClick={handleLogout} title="Đăng xuất" aria-label="Đăng xuất">
            <i className="ti ti-logout" aria-hidden="true" />
          </button>
        </div>
      </header>
      <main className="content">
        <Outlet />
      </main>
      {changingPassword && <ChangePasswordModal onClose={() => setChangingPassword(false)} />}
    </div>
  )
}
