import { useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { userApi } from '../../api/userApi'
import Modal from '../../components/Modal'
import PasswordInput from '../../components/PasswordInput'
import { PASSWORD_HINT } from '../../constants'

/** Quản trị viên đặt lại mật khẩu cho nhân viên (VD khi nhân viên quên mật khẩu). */
export default function ResetPasswordModal({ user, onClose, onDone }) {
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const submit = async (e) => {
    e.preventDefault()
    if (!password) return setError('Nhập mật khẩu mới.')
    setBusy(true)
    setError('')
    try {
      await userApi.resetPassword(user.id, password)
      onDone()
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title="Đặt lại mật khẩu" size="small" onClose={onClose}>
      <form onSubmit={submit}>
        <p>Đặt mật khẩu mới cho <b>{user.fullName}</b> ({user.userName}). Người này sẽ bị đăng xuất khỏi mọi thiết bị.</p>
        <label>Mật khẩu mới
          <PasswordInput value={password} onChange={(e) => setPassword(e.target.value)} allowGenerate autoFocus />
        </label>
        <p className="hint">{PASSWORD_HINT}</p>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Đặt lại'}</button>
        </div>
      </form>
    </Modal>
  )
}
