import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { customerApi } from '../../api/crmApi'
import { getErrorMessage } from '../../api/client'
import Modal from '../../components/Modal'
import { PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDate, formatDateOnly, formatMoney } from '../../utils/format'
import ContactFormModal from './ContactFormModal'
import CrmLayout from './CrmLayout'
import CustomerFormModal from './CustomerFormModal'
import OpportunityFormModal from './OpportunityFormModal'
import useCrmLookups from './useCrmLookups'

const STATUS_LABEL = { open: 'Đang mở', won: 'Thành công', lost: 'Thất bại' }
const STATUS_PILL = { open: 'new', won: 'qualified', lost: 'unqualified' }

/** Hồ sơ khách hàng: thông tin, người liên hệ, các cơ hội. */
export default function CustomerDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { can } = useAuth()
  const lookups = useCrmLookups()

  const [customer, setCustomer] = useState(null)
  const [error, setError] = useState('')
  const [editing, setEditing] = useState(false)
  const [contactEditing, setContactEditing] = useState(null)   // null | 'new' | contact
  const [contactDeleting, setContactDeleting] = useState(null)
  const [opportunityEditing, setOpportunityEditing] = useState(null) // null | 'new' | id
  const [deleting, setDeleting] = useState(false)

  const load = useCallback(() => {
    customerApi.get(id).then(setCustomer).catch((err) => setError(getErrorMessage(err)))
  }, [id])

  useEffect(load, [load])

  const removeContact = async () => {
    try {
      await customerApi.removeContact(id, contactDeleting.id)
      setContactDeleting(null)
      load()
    } catch (err) {
      setError(getErrorMessage(err))
      setContactDeleting(null)
    }
  }

  const removeCustomer = async () => {
    try {
      await customerApi.remove(id)
      navigate('/crm/customers', { replace: true })
    } catch (err) {
      setError(getErrorMessage(err))
      setDeleting(false)
    }
  }

  if (!customer) return <CrmLayout>{error ? <div className="alert error">{error}</div> : <p className="muted">Đang tải...</p>}</CrmLayout>

  const canEdit = can(PERMISSIONS.CRM_EDIT)
  const stageName = (stageId) => lookups.pipelines.flatMap((p) => p.stages).find((s) => s.id === stageId)?.name ?? ''
  const openValue = customer.opportunities.filter((o) => o.status === 'open').reduce((s, o) => s + o.expectedRevenue, 0)
  const wonValue = customer.opportunities.filter((o) => o.status === 'won').reduce((s, o) => s + o.expectedRevenue, 0)

  return (
    <CrmLayout>
      <div className="page-head">
        <div>
          <Link to="/crm/customers" className="muted small"><i className="ti ti-arrow-left" aria-hidden="true" /> Khách hàng</Link>
          <h1>
            <i className={`ti ti-${customer.partnerType === 'company' ? 'building' : 'user'} muted`} aria-hidden="true" /> {customer.name}
          </h1>
          <p className="muted small">{customer.code}{customer.groupName ? ` · ${customer.groupName}` : ''}{customer.ownerName ? ` · Phụ trách: ${customer.ownerName}` : ''}</p>
        </div>
        <div className="head-actions">
          {can(PERMISSIONS.CRM_DELETE) && <button className="btn ghost danger" onClick={() => setDeleting(true)} title="Xóa khách hàng"><i className="ti ti-trash" aria-hidden="true" /></button>}
          {canEdit && <button className="btn" onClick={() => setEditing(true)}><i className="ti ti-edit" aria-hidden="true" /> Sửa</button>}
          {can(PERMISSIONS.CRM_CREATE) && <button className="btn primary" onClick={() => setOpportunityEditing('new')}><i className="ti ti-plus" aria-hidden="true" /> Tạo cơ hội</button>}
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="detail-grid">
        <div className="card">
          <h2>Thông tin</h2>
          <dl className="info">
            {customer.taxCode && <><dt>Mã số thuế</dt><dd>{customer.taxCode}</dd></>}
            <dt>Điện thoại</dt><dd>{customer.phone ? <a href={`tel:${customer.phone}`}>{customer.phone}</a> : <span className="muted">-</span>}</dd>
            <dt>Email</dt><dd>{customer.email ? <a href={`mailto:${customer.email}`}>{customer.email}</a> : <span className="muted">-</span>}</dd>
            {customer.website && <><dt>Website</dt><dd>{customer.website}</dd></>}
            {customer.industry && <><dt>Ngành nghề</dt><dd>{customer.industry}</dd></>}
            {customer.street && <><dt>Địa chỉ</dt><dd>{customer.street}</dd></>}
            {customer.source && <><dt>Nguồn</dt><dd>{customer.source}</dd></>}
            <dt>Ngày tạo</dt><dd>{formatDate(customer.createdAt)}</dd>
          </dl>
          {customer.note && <p className="note">{customer.note}</p>}
        </div>

        <div className="card stats">
          <div><span className="muted small">Cơ hội đang mở</span><b>{formatMoney(openValue) || '0 ₫'}</b></div>
          <div><span className="muted small">Đã thắng</span><b className="won">{formatMoney(wonValue) || '0 ₫'}</b></div>
          <div><span className="muted small">Số cơ hội</span><b>{customer.opportunities.length}</b></div>
        </div>
      </div>

      <div className="section-head">
        <h2>Người liên hệ</h2>
        {canEdit && <button className="btn" onClick={() => setContactEditing('new')}><i className="ti ti-plus" aria-hidden="true" /> Thêm</button>}
      </div>
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Họ tên</th><th>Chức vụ</th><th>Điện thoại</th><th className="hide-sm">Email</th><th /></tr></thead>
          <tbody>
            {customer.contacts.length === 0 && <tr><td colSpan={5} className="muted center">Chưa có người liên hệ.</td></tr>}
            {customer.contacts.map((c) => (
              <tr key={c.id}>
                <td>{c.fullName} {c.isPrimary && <span className="pill admin small-pill">Liên hệ chính</span>}</td>
                <td>{c.position}</td>
                <td>{c.phone}</td>
                <td className="hide-sm">{c.email}</td>
                <td className="actions">
                  {canEdit && (
                    <>
                      <button className="btn ghost" title="Sửa" aria-label={`Sửa ${c.fullName}`} onClick={() => setContactEditing(c)}><i className="ti ti-edit" aria-hidden="true" /></button>
                      <button className="btn ghost danger" title="Xóa" aria-label={`Xóa ${c.fullName}`} onClick={() => setContactDeleting(c)}><i className="ti ti-trash" aria-hidden="true" /></button>
                    </>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="section-head">
        <h2>Cơ hội</h2>
        <Link className="muted small" to="/crm/opportunities">Xem bảng Kanban <i className="ti ti-arrow-right" aria-hidden="true" /></Link>
      </div>
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Cơ hội</th><th>Giai đoạn</th><th className="num">Giá trị</th><th className="hide-sm">Dự kiến chốt</th><th>Trạng thái</th></tr></thead>
          <tbody>
            {customer.opportunities.length === 0 && <tr><td colSpan={5} className="muted center">Chưa có cơ hội nào.</td></tr>}
            {customer.opportunities.map((o) => (
              <tr key={o.id} className="clickable" onClick={() => setOpportunityEditing(o.id)}>
                <td><button className="link" onClick={(e) => { e.stopPropagation(); setOpportunityEditing(o.id) }}>{o.name}</button><div className="muted small">{o.code}</div></td>
                <td>{stageName(o.stageId)}</td>
                <td className="num">{formatMoney(o.expectedRevenue)}</td>
                <td className={`hide-sm ${o.isOverdue ? 'overdue' : ''}`}>{formatDateOnly(o.expectedCloseDate)}</td>
                <td><span className={`pill ${STATUS_PILL[o.status]}`}>{STATUS_LABEL[o.status]}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {editing && (
        <CustomerFormModal customer={customer} lookups={lookups} onClose={() => setEditing(false)} onSaved={() => { setEditing(false); load() }} />
      )}
      {contactEditing && (
        <ContactFormModal customerId={customer.id} contact={contactEditing === 'new' ? null : contactEditing}
          onClose={() => setContactEditing(null)} onSaved={() => { setContactEditing(null); load() }} />
      )}
      {opportunityEditing && (
        <OpportunityFormModal opportunityId={opportunityEditing === 'new' ? null : opportunityEditing}
          presetCustomer={{ id: customer.id, name: customer.name }} lookups={lookups}
          onClose={() => setOpportunityEditing(null)} onSaved={() => { setOpportunityEditing(null); load() }} onStageChanged={load} />
      )}
      {contactDeleting && (
        <Modal title="Xóa người liên hệ?" size="small" onClose={() => setContactDeleting(null)}
          footer={<><button className="btn" onClick={() => setContactDeleting(null)}>Hủy</button><button className="btn danger-fill" onClick={removeContact}>Xóa</button></>}>
          <p>Xóa <b>{contactDeleting.fullName}</b> khỏi danh sách liên hệ của {customer.name}?</p>
        </Modal>
      )}
      {deleting && (
        <Modal title="Xóa khách hàng?" size="small" onClose={() => setDeleting(false)}
          footer={<><button className="btn" onClick={() => setDeleting(false)}>Hủy</button><button className="btn danger-fill" onClick={removeCustomer}>Xóa</button></>}>
          <p><b>{customer.name}</b> sẽ được chuyển vào thùng rác. Không xóa được nếu khách hàng còn cơ hội đang mở.</p>
        </Modal>
      )}
    </CrmLayout>
  )
}
