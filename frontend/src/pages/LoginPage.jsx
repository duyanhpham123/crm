import { useEffect, useState } from 'react'
import { Navigate, useNavigate, useSearchParams } from 'react-router-dom'
import { authApi } from '../api/authApi'
import { getErrorMessage } from '../api/client'
import { useAuth } from '../context/AuthContext'

/** Đăng nhập. Lần chạy đầu (admin chưa có mật khẩu) hiện form thiết lập. */
export default function LoginPage() {
  const { status, login } = useAuth()
  const navigate = useNavigate()
  const [params] = useSearchParams()

  const [needsSetup, setNeedsSetup] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [form, setForm] = useState({ userName: '', password: '', fullName: 'Quản trị hệ thống', email: '', confirm: '' })

  useEffect(() => {
    authApi
      .setupStatus()
      .then((r) => setNeedsSetup(r.needsSetup))
      .catch(() => {
        setNeedsSetup(false)
        setError('Không kết nối được máy chủ.')
      })
  }, [])

  // Đăng nhập xong quay lại trang đang xem dở. Chỉ chấp nhận đường dẫn nội bộ (chống chuyển hướng sang trang lạ).
  const returnUrl = params.get('returnUrl')
  const target = returnUrl?.startsWith('/') && !returnUrl.startsWith('//') ? returnUrl : '/'

  if (status === 'authenticated') return <Navigate to={target} replace />

  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })

  const goBack = () => navigate(target, { replace: true })

  const run = async (action) => {
    setError('')
    setBusy(true)
    try {
      await action()
      goBack()
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  const handleLogin = (e) => {
    e.preventDefault()
    if (!form.userName.trim() || !form.password) return setError('Nhập tên đăng nhập và mật khẩu.')
    run(() => login(form.userName, form.password))
  }

  const handleSetup = (e) => {
    e.preventDefault()
    if (form.password !== form.confirm) return setError('Mật khẩu nhập lại không khớp.')
    run(async () => {
      await authApi.setupAdmin({ password: form.password, fullName: form.fullName, email: form.email || null })
      await login('admin', form.password)
    })
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-brand">
          <i className="ti ti-grid-dots" aria-hidden="true" />
          <h1>MyERP</h1>
        </div>

        {needsSetup === null && <p className="muted">Đang kiểm tra hệ thống...</p>}

        {needsSetup === true && (
          <form onSubmit={handleSetup}>
            <h2>Thiết lập lần đầu</h2>
            <p className="muted">Đặt mật khẩu cho tài khoản quản trị <b>admin</b>.</p>
            <label>Họ tên<input value={form.fullName} onChange={update('fullName')} autoComplete="name" /></label>
            <label>Email (không bắt buộc)<input type="email" value={form.email} onChange={update('email')} autoComplete="email" /></label>
            <label>Mật khẩu<input type="password" value={form.password} onChange={update('password')} autoComplete="new-password" /></label>
            <label>Nhập lại mật khẩu<input type="password" value={form.confirm} onChange={update('confirm')} autoComplete="new-password" /></label>
            <p className="hint">Tối thiểu 10 ký tự, có chữ cái và chữ số.</p>
            {error && <p className="error">{error}</p>}
            <button className="btn primary block" disabled={busy}>Lưu và đăng nhập</button>
          </form>
        )}

        {needsSetup === false && (
          <form onSubmit={handleLogin}>
            <h2>Đăng nhập</h2>
            <label>Tên đăng nhập hoặc email<input value={form.userName} onChange={update('userName')} autoComplete="username" autoFocus /></label>
            <label>Mật khẩu<input type="password" value={form.password} onChange={update('password')} autoComplete="current-password" /></label>
            {error && <p className="error">{error}</p>}
            <button className="btn primary block" disabled={busy}>{busy ? 'Đang đăng nhập...' : 'Đăng nhập'}</button>
          </form>
        )}
      </div>
    </div>
  )
}
