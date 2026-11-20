import { useState } from 'react'
import { customerApi } from '../../api/crmApi'
import { getErrorMessage } from '../../api/client'
import Modal from '../../components/Modal'

const FIELDS = ['partnerType', 'name', 'shortName', 'taxCode', 'phone', 'email', 'website', 'industry', 'street', 'customerGroupId', 'ownerUserId', 'note']

/** Tạo / sửa khách hàng. Khi tạo mới có thêm phần "Người liên hệ chính". */
export default function CustomerFormModal({ customer, lookups, onClose, onSaved }) {
  const isNew = !customer
  const [form, setForm] = useState(() => ({
    ...Object.fromEntries(FIELDS.map((f) => [f, customer?.[f] ?? ''])),
    partnerType: customer?.partnerType ?? 'company',
  }))
  const [contact, setContact] = useState({ fullName: '', position: '', phone: '', email: '' })
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })
  const updateContact = (field) => (e) => setContact({ ...contact, [field]: e.target.value })
  const isCompany = form.partnerType === 'company'

  const save = async (e) => {
    e.preventDefault()
    setError('')
    if (!form.name.trim()) return setError('Nhập tên khách hàng.')

    const body = {
      ...Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v === '' ? null : v])),
      customerGroupId: form.customerGroupId ? Number(form.customerGroupId) : null,
      ownerUserId: form.ownerUserId ? Number(form.ownerUserId) : null,
      primaryContact: isNew && isCompany && contact.fullName.trim()
        ? { ...Object.fromEntries(Object.entries(contact).map(([k, v]) => [k, v || null])), fullName: contact.fullName, isPrimary: true }
        : null,
      rowVersion: customer?.rowVersion ?? null,
    }
    setBusy(true)
    try {
      const saved = isNew ? await customerApi.create(body) : await customerApi.update(customer.id, body)
      onSaved(saved, isNew)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title={isNew ? 'Thêm khách hàng' : `Khách hàng ${customer.code}`} onClose={onClose}>
      <form onSubmit={save}>
        <div className="segmented" role="radiogroup" aria-label="Loại khách hàng">
          {[['company', 'Doanh nghiệp', 'building'], ['individual', 'Cá nhân', 'user']].map(([value, label, icon]) => (
            <button type="button" key={value} role="radio" aria-checked={form.partnerType === value}
              className={form.partnerType === value ? 'on' : ''} onClick={() => setForm({ ...form, partnerType: value })}>
              <i className={`ti ti-${icon}`} aria-hidden="true" /> {label}
            </button>
          ))}
        </div>

        <div className="form-grid">
          <label className="span2">{isCompany ? 'Tên công ty *' : 'Họ tên *'}
            <input value={form.name} onChange={update('name')} autoFocus placeholder={isCompany ? 'Công ty TNHH Hưng Thịnh' : 'Nguyễn Văn An'} />
          </label>
          {isCompany && <label>Tên viết tắt<input value={form.shortName} onChange={update('shortName')} placeholder="Hưng Thịnh" /></label>}
          {isCompany && <label>Mã số thuế<input value={form.taxCode} onChange={update('taxCode')} placeholder="0101234567" /></label>}
          <label>Số điện thoại<input value={form.phone} onChange={update('phone')} placeholder="0912345678" /></label>
          <label>Email<input type="email" value={form.email} onChange={update('email')} placeholder="lienhe@congty.vn" /></label>
          {isCompany && <label>Website<input value={form.website} onChange={update('website')} placeholder="congty.vn" /></label>}
          {isCompany && <label>Ngành nghề<input value={form.industry} onChange={update('industry')} placeholder="Xây dựng" /></label>}
          <label>Nhóm khách hàng
            <select value={form.customerGroupId} onChange={update('customerGroupId')}>
              <option value="">Chưa phân nhóm</option>
              {lookups.customerGroups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
            </select>
          </label>
          <label>Người phụ trách
            <select value={form.ownerUserId} onChange={update('ownerUserId')}>
              <option value="">{isNew ? 'Tôi' : 'Giữ nguyên'}</option>
              {lookups.owners.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
            </select>
          </label>
          <label className="span2">Địa chỉ<input value={form.street} onChange={update('street')} /></label>
          <label className="span2">Ghi chú<textarea rows={2} value={form.note} onChange={update('note')} /></label>
        </div>

        {isNew && isCompany && (
          <>
            <div className="field-label">Người liên hệ chính (không bắt buộc)</div>
            <div className="form-grid">
              <label>Họ tên<input value={contact.fullName} onChange={updateContact('fullName')} /></label>
              <label>Chức vụ<input value={contact.position} onChange={updateContact('position')} placeholder="Giám đốc" /></label>
              <label>Điện thoại<input value={contact.phone} onChange={updateContact('phone')} /></label>
              <label>Email<input type="email" value={contact.email} onChange={updateContact('email')} /></label>
            </div>
          </>
        )}

        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Lưu'}</button>
        </div>
      </form>
    </Modal>
  )
}
