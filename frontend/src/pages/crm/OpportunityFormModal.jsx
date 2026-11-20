import { useEffect, useState } from 'react'
import { customerApi, opportunityApi } from '../../api/crmApi'
import { getErrorMessage } from '../../api/client'
import CustomerPicker from '../../components/CustomerPicker'
import Modal from '../../components/Modal'
import { PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatMoney } from '../../utils/format'

/**
 * Tạo / sửa cơ hội.
 * opportunityId = null: tạo mới (presetCustomer = khách hàng chọn sẵn khi tạo từ trang khách hàng).
 * Đổi giai đoạn thì kéo thả trên Kanban; trong form chỉ chọn giai đoạn khi tạo mới.
 */
export default function OpportunityFormModal({ opportunityId, presetCustomer, lookups, onClose, onSaved, onStageChanged }) {
  const { can } = useAuth()
  const isNew = !opportunityId
  const pipeline = lookups.pipelines[0]
  const openStages = pipeline?.stages.filter((s) => s.stageType === 'open') ?? []

  const [loaded, setLoaded] = useState(isNew)
  const [detail, setDetail] = useState(null)
  const [customer, setCustomer] = useState(presetCustomer ?? null)
  const [contacts, setContacts] = useState([])
  const [form, setForm] = useState({
    name: '', contactId: '', stageId: '', expectedRevenue: '', probability: '', expectedCloseDate: '', priority: 1, ownerUserId: '', description: '',
  })
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [confirmDelete, setConfirmDelete] = useState(false)

  // Sửa: tải chi tiết cơ hội
  useEffect(() => {
    if (isNew) return
    opportunityApi.get(opportunityId).then((d) => {
      setDetail(d)
      setCustomer({ id: d.customerId, name: d.customerName })
      setForm({
        name: d.name, contactId: d.contactId ?? '', stageId: d.stageId, expectedRevenue: d.expectedRevenue,
        probability: d.probability, expectedCloseDate: d.expectedCloseDate ?? '', priority: d.priority,
        ownerUserId: d.ownerUserId ?? '', description: d.description ?? '',
      })
      setLoaded(true)
    }).catch((err) => setError(getErrorMessage(err)))
  }, [isNew, opportunityId])

  // Đổi khách hàng thì tải danh sách người liên hệ của khách đó
  useEffect(() => {
    if (!customer) return setContacts([])
    customerApi.get(customer.id).then((c) => setContacts(c.contacts)).catch(() => setContacts([]))
  }, [customer])

  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })
  const stageName = pipeline?.stages.find((s) => s.id === detail?.stageId)?.name

  // ----- Chuyển giai đoạn từ trong form -----
  const [move, setMove] = useState({ stageId: '', reasonId: '' })
  const lostStageSelected = pipeline?.stages.find((s) => s.id === Number(move.stageId))?.stageType === 'lost'

  const pickStage = (value) => {
    setMove({ stageId: value, reasonId: '' })
    const target = pipeline?.stages.find((s) => s.id === Number(value))
    if (target && target.stageType !== 'lost') moveStage(target.id, null)   // giai đoạn thường: chuyển ngay
  }

  const moveStage = async (stageId, reasonId) => {
    setBusy(true)
    setError('')
    try {
      const updated = await opportunityApi.moveStage(opportunityId, stageId, reasonId)
      setDetail(updated)
      setForm((f) => ({ ...f, probability: updated.probability }))
      setMove({ stageId: '', reasonId: '' })
      onStageChanged?.()
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }
  const lostReason = lookups.lostReasons.find((r) => r.id === detail?.lostReasonId)?.name

  const save = async (e) => {
    e.preventDefault()
    setError('')
    if (!customer) return setError('Chọn khách hàng.')
    if (!form.name.trim()) return setError('Nhập tên cơ hội.')

    const body = {
      name: form.name,
      customerId: customer.id,
      contactId: form.contactId ? Number(form.contactId) : null,
      stageId: form.stageId ? Number(form.stageId) : null,
      expectedRevenue: Number(form.expectedRevenue || 0),
      probability: form.probability === '' ? null : Number(form.probability),
      expectedCloseDate: form.expectedCloseDate || null,
      priority: Number(form.priority),
      ownerUserId: form.ownerUserId ? Number(form.ownerUserId) : null,
      description: form.description || null,
      rowVersion: detail?.rowVersion ?? null,
    }
    setBusy(true)
    try {
      const saved = isNew ? await opportunityApi.create(body) : await opportunityApi.update(opportunityId, body)
      onSaved(saved, isNew)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  const remove = async () => {
    try {
      await opportunityApi.remove(opportunityId)
      onSaved(null, false)
    } catch (err) {
      setError(getErrorMessage(err))
      setConfirmDelete(false)
    }
  }

  const canEdit = isNew ? can(PERMISSIONS.CRM_CREATE) : can(PERMISSIONS.CRM_EDIT)

  return (
    <Modal title={isNew ? 'Tạo cơ hội' : `Cơ hội ${detail?.code ?? ''}`} onClose={onClose}>
      {!loaded && !error && <p className="muted">Đang tải...</p>}
      {loaded && (
        <form onSubmit={save}>
          {detail && (
            <div className={`status-note ${detail.status}`}>
              Giai đoạn: <b>{stageName}</b> · Xác suất {detail.probability}%
              {detail.status === 'won' && ' · Đã thắng'}
              {detail.status === 'lost' && ` · Thất bại: ${lostReason ?? ''}${detail.lostNote ? ` (${detail.lostNote})` : ''}`}
            </div>
          )}
          {/* Đổi giai đoạn không cần kéo thả: dùng được trên điện thoại (cảm ứng) và bằng bàn phím */}
          {detail && can(PERMISSIONS.CRM_EDIT) && (
            <div className="stage-move">
              <label>Chuyển giai đoạn
                <select value={move.stageId} onChange={(e) => pickStage(e.target.value)} disabled={busy}>
                  <option value="">Chọn giai đoạn mới</option>
                  {pipeline?.stages.filter((s) => s.id !== detail.stageId).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </label>
              {lostStageSelected && (
                <>
                  <label>Lý do thất bại *
                    <select value={move.reasonId} onChange={(e) => setMove({ ...move, reasonId: e.target.value })}>
                      <option value="">Chọn lý do</option>
                      {lookups.lostReasons.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
                    </select>
                  </label>
                  <button type="button" className="btn danger-fill" disabled={!move.reasonId || busy}
                    onClick={() => moveStage(Number(move.stageId), Number(move.reasonId))}>Xác nhận</button>
                </>
              )}
            </div>
          )}
          <fieldset disabled={!canEdit}>
            <div className="form-grid">
              <label className="span2">Khách hàng *
                <CustomerPicker value={customer} onChange={setCustomer} disabled={!isNew || !!presetCustomer} autoFocus={isNew && !presetCustomer} />
              </label>
              <label className="span2">Tên cơ hội *<input value={form.name} onChange={update('name')} placeholder="Triển khai phần mềm kho - 3 chi nhánh" /></label>
              <label>Người liên hệ
                <select value={form.contactId} onChange={update('contactId')} disabled={!customer}>
                  <option value="">Không chọn</option>
                  {contacts.map((c) => <option key={c.id} value={c.id}>{c.fullName}{c.position ? ` - ${c.position}` : ''}</option>)}
                </select>
              </label>
              {isNew ? (
                <label>Giai đoạn
                  <select value={form.stageId} onChange={update('stageId')}>
                    <option value="">{openStages[0]?.name ?? ''} (mặc định)</option>
                    {openStages.slice(1).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                  </select>
                </label>
              ) : (
                <label>Xác suất thành công (%)<input type="number" min="0" max="100" value={form.probability} onChange={update('probability')} /></label>
              )}
              <label>Giá trị dự kiến (₫)
                <input type="number" min="0" step="1000000" value={form.expectedRevenue} onChange={update('expectedRevenue')} />
                {form.expectedRevenue > 0 && <span className="hint-inline">{formatMoney(Number(form.expectedRevenue))}</span>}
              </label>
              <label>Ngày dự kiến chốt<input type="date" value={form.expectedCloseDate} onChange={update('expectedCloseDate')} /></label>
              <label>Độ ưu tiên
                <div className="stars" role="radiogroup" aria-label="Độ ưu tiên">
                  {[1, 2, 3].map((n) => (
                    <button type="button" key={n} role="radio" aria-checked={Number(form.priority) === n} aria-label={`${n} sao`}
                      className={Number(form.priority) >= n ? 'on' : ''} onClick={() => setForm({ ...form, priority: Number(form.priority) === n ? n - 1 : n })}>
                      <i className="ti ti-star" aria-hidden="true" />
                    </button>
                  ))}
                </div>
              </label>
              <label>Người phụ trách
                <select value={form.ownerUserId} onChange={update('ownerUserId')}>
                  <option value="">{isNew ? 'Tôi' : 'Giữ nguyên'}</option>
                  {lookups.owners.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
                </select>
              </label>
              <label className="span2">Mô tả<textarea rows={3} value={form.description} onChange={update('description')} /></label>
            </div>
          </fieldset>

          {error && <p className="error">{error}</p>}
          <div className="modal-foot">
            {!isNew && can(PERMISSIONS.CRM_DELETE) && detail?.status !== 'won' && (
              confirmDelete
                ? <><span className="error small">Xóa cơ hội này?</span><button type="button" className="btn danger-fill" onClick={remove}>Xóa</button><button type="button" className="btn" onClick={() => setConfirmDelete(false)}>Không</button></>
                : <button type="button" className="btn ghost danger left" onClick={() => setConfirmDelete(true)}><i className="ti ti-trash" aria-hidden="true" /> Xóa</button>
            )}
            <span className="spacer" />
            <button type="button" className="btn" onClick={onClose}>Đóng</button>
            {canEdit && <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Lưu'}</button>}
          </div>
        </form>
      )}
      {!loaded && error && <p className="error">{error}</p>}
    </Modal>
  )
}
