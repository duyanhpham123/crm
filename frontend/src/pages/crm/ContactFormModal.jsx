import { useState } from 'react'
import { customerApi } from '../../api/crmApi'
import { getErrorMessage } from '../../api/client'
import Modal from '../../components/Modal'

/** Thêm / sửa người liên hệ của khách hàng. */
export default function ContactFormModal({ customerId, contact, onClose, onSaved }) {
  const isNew = !contact
  const [form, setForm] = useState({
    fullName: contact?.fullName ?? '',
    position: contact?.position ?? '',
    phone: contact?.phone ?? '',
    email: contact?.email ?? '',
    birthday: contact?.birthday ?? '',
    isPrimary: contact?.isPrimary ?? false,
    note: contact?.note ?? '',
  })
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })

  const save = async (e) => {
    e.preventDefault()
    if (!form.fullName.trim()) return setError('Nhập họ tên.')
    const body = { ...Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v === '' ? null : v])), isPrimary: form.isPrimary }
    setBusy(true)
    setError('')
    try {
      if (isNew) await customerApi.addContact(customerId, body)
      else await customerApi.updateContact(customerId, contact.id, body)
      onSaved()
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title={isNew ? 'Thêm người liên hệ' : 'Sửa người liên hệ'} size="small" onClose={onClose}>
      <form onSubmit={save}>
        <label>Họ tên *<input value={form.fullName} onChange={update('fullName')} autoFocus /></label>
        <label>Chức vụ<input value={form.position} onChange={update('position')} placeholder="Kế toán trưởng" /></label>
        <label>Điện thoại<input value={form.phone} onChange={update('phone')} /></label>
        <label>Email<input type="email" value={form.email} onChange={update('email')} /></label>
        <label>Sinh nhật<input type="date" value={form.birthday} onChange={update('birthday')} /></label>
        <label>Ghi chú<textarea rows={2} value={form.note} onChange={update('note')} /></label>
        <label className="check">
          <input type="checkbox" checked={form.isPrimary} onChange={(e) => setForm({ ...form, isPrimary: e.target.checked })} />
          Liên hệ chính
        </label>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Lưu'}</button>
        </div>
      </form>
    </Modal>
  )
}
