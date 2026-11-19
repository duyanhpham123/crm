import { useState } from 'react'
import { accountApi } from '../api/authApi'
import { getErrorMessage, tokenStorage } from '../api/client'
import { PASSWORD_HINT } from '../constants'
import Modal from './Modal'
import PasswordInput from './PasswordInput'

/** Người dùng tự đổi mật khẩu. Các thiết bị khác bị đăng xuất, thiết bị này nhận token mới và tiếp tục dùng. */
export default function ChangePasswordModal({ onClose }) {
  const [form, setForm] = useState({ current: '', next: '', confirm: '' })
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(false)

  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })

  const submit = async (e) => {
    e.preventDefault()
    setError('')
    if (!form.current || !form.next) return setError('Nhập đủ mật khẩu hiện tại và mật khẩu mới.')
    if (form.next !== form.confirm) return setError('Mật khẩu nhập lại không khớp.')
    setBusy(true)
    try {
      tokenStorage.set(await accountApi.changePassword(form.current, form.next))
      setDone(true)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  if (done) {
    return (
      <Modal title="Đổi mật khẩu" size="small" onClose={onClose} footer={<button className="btn primary" onClick={onClose}>Đóng</button>}>
        <p>Đã đổi mật khẩu. Các thiết bị khác đang đăng nhập tài khoản này đã bị đăng xuất.</p>
      </Modal>
    )
  }

  return (
    <Modal title="Đổi mật khẩu" size="small" onClose={onClose}>
      <form onSubmit={submit}>
        <label>Mật khẩu hiện tại<PasswordInput value={form.current} onChange={update('current')} autoComplete="current-password" autoFocus /></label>
        <label>Mật khẩu mới<PasswordInput value={form.next} onChange={update('next')} /></label>
        <label>Nhập lại mật khẩu mới<PasswordInput value={form.confirm} onChange={update('confirm')} /></label>
        <p className="hint">{PASSWORD_HINT}</p>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Đổi mật khẩu'}</button>
        </div>
      </form>
    </Modal>
  )
}
