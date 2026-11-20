import { useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { leadApi } from '../../api/leadApi'
import CustomerPicker from '../../components/CustomerPicker'
import Modal from '../../components/Modal'

/**
 * Chuyển đổi lead: tạo khách hàng mới (hoặc gắn vào khách hàng có sẵn) + cơ hội.
 * Sau khi chuyển đổi, lead bị khóa và trỏ sang khách hàng.
 */
export default function ConvertLeadModal({ lead, onClose, onConverted }) {
  const [mode, setMode] = useState('new')     // new | existing
  const [existing, setExisting] = useState(null)
  const [createOpportunity, setCreateOpportunity] = useState(true)
  const [opp, setOpp] = useState({
    name: lead.organizationName ? `${lead.organizationName} - ${lead.interestNote ?? 'Cơ hội mới'}`.slice(0, 200) : `${lead.fullName} - Cơ hội mới`,
    expectedRevenue: lead.estimatedValue ?? '',
    expectedCloseDate: '',
  })
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const submit = async () => {
    setError('')
    if (mode === 'existing' && !existing) return setError('Chọn khách hàng có sẵn.')
    if (createOpportunity && !opp.name.trim()) return setError('Nhập tên cơ hội.')
    setBusy(true)
    try {
      const result = await leadApi.convert(lead.id, {
        existingCustomerId: mode === 'existing' ? existing.id : null,
        createOpportunity,
        opportunityName: createOpportunity ? opp.name : null,
        expectedRevenue: createOpportunity && opp.expectedRevenue !== '' ? Number(opp.expectedRevenue) : null,
        expectedCloseDate: createOpportunity && opp.expectedCloseDate ? opp.expectedCloseDate : null,
      })
      onConverted(result)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      title={`Chuyển đổi lead ${lead.code}`}
      onClose={onClose}
      footer={
        <>
          <button className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy} onClick={submit}>{busy ? 'Đang chuyển đổi...' : 'Chuyển đổi'}</button>
        </>
      }
    >
      <p className="muted">Lead sẽ trở thành khách hàng và không sửa được nữa. Mọi thông tin được giữ lại.</p>

      <div className="field-label">Khách hàng</div>
      <div className="choice">
        <label className="check">
          <input type="radio" name="mode" checked={mode === 'new'} onChange={() => setMode('new')} />
          Tạo khách hàng mới: <b>{lead.organizationName || lead.fullName}</b>
          <span className="muted small"> ({lead.organizationName ? `doanh nghiệp, ${lead.fullName} là người liên hệ` : 'cá nhân'})</span>
        </label>
        <label className="check">
          <input type="radio" name="mode" checked={mode === 'existing'} onChange={() => setMode('existing')} />
          Gắn vào khách hàng có sẵn
        </label>
        {mode === 'existing' && <CustomerPicker value={existing} onChange={setExisting} autoFocus />}
      </div>

      <label className="check top-gap">
        <input type="checkbox" checked={createOpportunity} onChange={(e) => setCreateOpportunity(e.target.checked)} />
        Tạo cơ hội bán hàng
      </label>
      {createOpportunity && (
        <div className="form-grid">
          <label className="span2">Tên cơ hội *<input value={opp.name} onChange={(e) => setOpp({ ...opp, name: e.target.value })} /></label>
          <label>Giá trị dự kiến (₫)<input type="number" min="0" step="1000000" value={opp.expectedRevenue} onChange={(e) => setOpp({ ...opp, expectedRevenue: e.target.value })} /></label>
          <label>Ngày dự kiến chốt<input type="date" value={opp.expectedCloseDate} onChange={(e) => setOpp({ ...opp, expectedCloseDate: e.target.value })} /></label>
        </div>
      )}

      {error && <p className="error">{error}</p>}
    </Modal>
  )
}
