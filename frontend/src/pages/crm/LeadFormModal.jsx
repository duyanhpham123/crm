import { useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { leadApi } from '../../api/leadApi'
import Modal from '../../components/Modal'
import { LEAD_STATUSES } from '../../constants'

const EMPTY = {
  fullName: '', phone: '', email: '', organizationName: '', position: '',
  sourceId: '', estimatedValue: '', street: '', interestNote: '',
}

const toForm = (lead) => (lead
  ? Object.fromEntries(Object.keys(EMPTY).map((k) => [k, lead[k] ?? '']))
  : EMPTY)

/** Chuỗi rỗng thành null, số thành Number trước khi gửi lên API */
const toRequest = (form, rowVersion) => ({
  ...Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v === '' ? null : v])),
  sourceId: form.sourceId ? Number(form.sourceId) : null,
  estimatedValue: form.estimatedValue === '' ? null : Number(form.estimatedValue),
  rowVersion: rowVersion ?? null,
})

/**
 * Form tạo / sửa lead + thanh đổi trạng thái.
 * lead = null: tạo mới. onSaved(isNew) gọi sau khi lưu. onChanged gọi khi đổi trạng thái.
 */
export default function LeadFormModal({ lead: initialLead, sources, canEdit, onClose, onSaved, onChanged }) {
  const [lead, setLead] = useState(initialLead)
  const [form, setForm] = useState(() => toForm(initialLead))
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [askReason, setAskReason] = useState(false)
  const [reason, setReason] = useState('')

  const isNew = !lead
  const editable = canEdit && lead?.status !== 'converted'
  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })

  const save = async (e) => {
    e.preventDefault()
    setError('')
    if (!form.fullName.trim()) return setError('Nhập họ tên.')
    if (!form.phone.trim() && !form.email.trim()) return setError('Cần ít nhất số điện thoại hoặc email.')

    setBusy(true)
    try {
      if (isNew) await leadApi.create(toRequest(form))
      else await leadApi.update(lead.id, toRequest(form, lead.rowVersion))
      onSaved(isNew)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  const changeStatus = async (status, why = null) => {
    if (status === 'unqualified' && !why) {
      setAskReason(true)
      return
    }
    setBusy(true)
    setError('')
    try {
      const updated = await leadApi.changeStatus(lead.id, status, why)
      setLead(updated)
      setForm(toForm(updated))
      setAskReason(false)
      setReason('')
      onChanged()
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title={isNew ? 'Tạo lead' : `Lead ${lead.code}`} onClose={onClose}>
      {!isNew && (
        <>
          <div className="status-bar">
            {LEAD_STATUSES.filter((s) => s.value !== 'converted').map((s) => (
              <button
                key={s.value}
                className={`step${s.value === lead.status ? ' current' : ''}`}
                disabled={!editable || busy || s.value === lead.status}
                onClick={() => changeStatus(s.value)}
              >
                {s.label}
              </button>
            ))}
          </div>
          {askReason && (
            <div className="reason">
              <label>Lý do không phù hợp<input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Không có ngân sách" autoFocus /></label>
              <button className="btn primary" disabled={busy || !reason.trim()} onClick={() => changeStatus('unqualified', reason)}>Xác nhận</button>
              <button className="btn" onClick={() => setAskReason(false)}>Hủy</button>
            </div>
          )}
          {lead.status === 'unqualified' && lead.disqualifyReason && (
            <p className="muted small">Lý do: {lead.disqualifyReason}</p>
          )}
        </>
      )}

      <form onSubmit={save}>
        <fieldset disabled={!isNew && !editable}>
          <div className="form-grid">
            <label className="span2">Họ tên *<input value={form.fullName} onChange={update('fullName')} autoFocus={isNew} /></label>
            <label>Số điện thoại<input value={form.phone} onChange={update('phone')} placeholder="0912345678" /></label>
            <label>Email<input type="email" value={form.email} onChange={update('email')} placeholder="ten@congty.vn" /></label>
            <label>Công ty<input value={form.organizationName} onChange={update('organizationName')} /></label>
            <label>Chức vụ<input value={form.position} onChange={update('position')} /></label>
            <label>Nguồn
              <select value={form.sourceId} onChange={update('sourceId')}>
                <option value="">Chọn nguồn</option>
                {sources.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </label>
            <label>Giá trị dự kiến (₫)<input type="number" min="0" step="1000000" value={form.estimatedValue} onChange={update('estimatedValue')} /></label>
            <label className="span2">Địa chỉ<input value={form.street} onChange={update('street')} /></label>
            <label className="span2">Nhu cầu<textarea rows={3} value={form.interestNote} onChange={update('interestNote')} /></label>
          </div>
        </fieldset>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Đóng</button>
          {(isNew || editable) && <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Lưu'}</button>}
        </div>
      </form>
    </Modal>
  )
}
