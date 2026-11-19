import { useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { userApi } from '../../api/userApi'
import Modal from '../../components/Modal'
import PasswordInput from '../../components/PasswordInput'
import { PASSWORD_HINT } from '../../constants'

/**
 * Form tạo / sửa người dùng.
 * user = null: tạo mới (có ô tên đăng nhập + mật khẩu ban đầu). isSelf: đang sửa chính mình (khóa phần vai trò).
 */
export default function UserFormModal({ user, options, isSelf, canEdit, onClose, onSaved }) {
  const isNew = !user
  const [form, setForm] = useState({
    userName: '',
    password: '',
    fullName: user?.fullName ?? '',
    email: user?.email ?? '',
    phoneNumber: user?.phoneNumber ?? '',
    departmentId: user?.departmentId ?? '',
    roleIds: user?.roleIds ?? [],
  })
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })
  const toggleRole = (id) =>
    setForm({ ...form, roleIds: form.roleIds.includes(id) ? form.roleIds.filter((r) => r !== id) : [...form.roleIds, id] })

  const save = async (e) => {
    e.preventDefault()
    setError('')
    if (isNew && !form.userName.trim()) return setError('Nhập tên đăng nhập.')
    if (isNew && !form.password) return setError('Nhập mật khẩu ban đầu.')
    if (!form.fullName.trim()) return setError('Nhập họ tên.')
    if (form.roleIds.length === 0) return setError('Chọn ít nhất một vai trò.')

    const common = {
      fullName: form.fullName,
      email: form.email || null,
      phoneNumber: form.phoneNumber || null,
      departmentId: form.departmentId ? Number(form.departmentId) : null,
      roleIds: form.roleIds,
    }
    setBusy(true)
    try {
      const saved = isNew
        ? await userApi.create({ ...common, userName: form.userName, password: form.password })
        : await userApi.update(user.id, common)
      onSaved(saved, isNew)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title={isNew ? 'Thêm người dùng' : `Người dùng: ${user.userName}`} onClose={onClose}>
      <form onSubmit={save}>
        <fieldset disabled={!canEdit}>
          <div className="form-grid">
            {isNew && (
              <>
                <label>Tên đăng nhập *<input value={form.userName} onChange={update('userName')} placeholder="nguyen.van.an" autoComplete="off" autoFocus /></label>
                <label>Mật khẩu ban đầu *
                  <PasswordInput value={form.password} onChange={update('password')} allowGenerate />
                </label>
                <p className="hint span2">{PASSWORD_HINT} Gửi mật khẩu này cho nhân viên; họ nên tự đổi sau lần đăng nhập đầu.</p>
              </>
            )}
            <label className="span2">Họ tên *<input value={form.fullName} onChange={update('fullName')} autoComplete="off" /></label>
            <label>Email<input type="email" value={form.email} onChange={update('email')} placeholder="an@congty.vn" autoComplete="off" /></label>
            <label>Số điện thoại<input value={form.phoneNumber} onChange={update('phoneNumber')} placeholder="0912345678" autoComplete="off" /></label>
            <label className="span2">Phòng ban
              <select value={form.departmentId} onChange={update('departmentId')}>
                <option value="">Chưa chọn</option>
                {options.departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
              </select>
            </label>
          </div>

          <div className="field-label">
            Vai trò *
            {isSelf && <span className="muted small"> - không thể tự đổi vai trò của chính mình</span>}
          </div>
          <div className="role-list">
            {options.roles.map((r) => (
              <label key={r.id} className={`role-option${form.roleIds.includes(r.id) ? ' checked' : ''}`}>
                <input type="checkbox" checked={form.roleIds.includes(r.id)} onChange={() => toggleRole(r.id)} disabled={isSelf} />
                <span>
                  {r.name}
                  {r.description && <span className="muted small"> - {r.description}</span>}
                </span>
              </label>
            ))}
          </div>
        </fieldset>

        {!isNew && user.isSystemAdmin && (
          <p className="muted small">Đây là tài khoản quản trị hệ thống: luôn có toàn quyền, không phụ thuộc vai trò.</p>
        )}
        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Đóng</button>
          {canEdit && <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Lưu'}</button>}
        </div>
      </form>
    </Modal>
  )
}
