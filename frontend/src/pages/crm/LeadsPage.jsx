import { useCallback, useEffect, useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { leadApi } from '../../api/leadApi'
import Modal from '../../components/Modal'
import Pagination from '../../components/Pagination'
import { LEAD_STATUSES, PERMISSIONS, leadStatusLabel } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDate, formatMoney } from '../../utils/format'
import CrmLayout from './CrmLayout'
import LeadFormModal from './LeadFormModal'

const PAGE_SIZE = 20

/** Danh sách lead: tìm kiếm, lọc trạng thái, phân trang, tạo / sửa / xóa. */
export default function LeadsPage() {
  const { can } = useAuth()

  const [data, setData] = useState(null)
  const [sources, setSources] = useState([])
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState('')
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const [editing, setEditing] = useState(null) // null = đóng | 'new' = tạo mới | LeadDto = sửa
  const [deleting, setDeleting] = useState(null)

  const load = useCallback(async () => {
    try {
      setError('')
      setData(await leadApi.list({ search, status, page, pageSize: PAGE_SIZE }))
    } catch (err) {
      setError(getErrorMessage(err))
      setData((d) => d ?? { items: [], page: 1, totalPages: 0, totalCount: 0 })
    }
  }, [search, status, page])

  // Gõ tìm kiếm: đợi 350ms sau phím cuối mới gọi API
  useEffect(() => {
    const timer = setTimeout(load, 350)
    return () => clearTimeout(timer)
  }, [load])

  useEffect(() => {
    leadApi.sources().then(setSources).catch(() => {})
  }, [])

  const openEdit = async (id) => {
    try {
      setEditing(await leadApi.get(id))
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }

  const confirmDelete = async () => {
    try {
      await leadApi.remove(deleting.id)
      setDeleting(null)
      load()
    } catch (err) {
      setError(getErrorMessage(err))
      setDeleting(null)
    }
  }

  const filtered = search || status

  return (
    <CrmLayout>
      <div className="page-head">
        <h1>Lead</h1>
        {can(PERMISSIONS.CRM_CREATE) && (
          <button className="btn primary" onClick={() => setEditing('new')}>
            <i className="ti ti-plus" aria-hidden="true" /> Tạo lead
          </button>
        )}
      </div>

      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input
            placeholder="Tìm tên, công ty, SĐT, email, mã"
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1) }}
            aria-label="Tìm kiếm lead"
          />
        </div>
        <select value={status} onChange={(e) => { setStatus(e.target.value); setPage(1) }} aria-label="Lọc theo trạng thái">
          <option value="">Tất cả trạng thái</option>
          {LEAD_STATUSES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
        </select>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr>
              <th className="hide-sm">Mã</th>
              <th>Họ tên</th>
              <th className="hide-sm">Công ty</th>
              <th>Liên hệ</th>
              <th className="hide-sm">Nguồn</th>
              <th className="num hide-sm">Giá trị dự kiến</th>
              <th>Trạng thái</th>
              <th className="hide-sm">Ngày tạo</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {!data && <tr><td colSpan={9} className="muted center">Đang tải...</td></tr>}
            {data?.items.length === 0 && (
              <tr><td colSpan={9} className="muted center">
                {filtered ? 'Không có lead nào khớp bộ lọc.' : 'Chưa có lead nào. Bấm "Tạo lead" để thêm.'}
              </td></tr>
            )}
            {data?.items.map((l) => (
              <tr key={l.id}>
                <td className="code hide-sm">{l.code}</td>
                <td><button className="link" onClick={() => openEdit(l.id)}>{l.fullName}</button></td>
                <td className="hide-sm">{l.organizationName}</td>
                <td>{l.phone}<div className="muted small">{l.email}</div></td>
                <td className="hide-sm">{l.sourceName}</td>
                <td className="num hide-sm">{formatMoney(l.estimatedValue)}</td>
                <td><span className={`pill ${l.status}`}>{leadStatusLabel(l.status)}</span></td>
                <td className="hide-sm">{formatDate(l.createdAt)}</td>
                <td className="actions">
                  {can(PERMISSIONS.CRM_EDIT) && l.status !== 'converted' && (
                    <button className="btn ghost" title="Sửa" aria-label={`Sửa ${l.fullName}`} onClick={() => openEdit(l.id)}>
                      <i className="ti ti-edit" aria-hidden="true" />
                    </button>
                  )}
                  {can(PERMISSIONS.CRM_DELETE) && l.status !== 'converted' && (
                    <button className="btn ghost danger" title="Xóa" aria-label={`Xóa ${l.fullName}`} onClick={() => setDeleting(l)}>
                      <i className="ti ti-trash" aria-hidden="true" />
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination data={data} unit="lead" onPageChange={setPage} />

      {editing && (
        <LeadFormModal
          lead={editing === 'new' ? null : editing}
          sources={sources}
          canEdit={can(PERMISSIONS.CRM_EDIT) || editing === 'new'}
          onClose={() => setEditing(null)}
          onSaved={(isNew) => {
            setEditing(null)
            if (isNew && page !== 1) setPage(1)   // tạo mới: về trang 1 để thấy lead vừa tạo
            else load()
          }}
          onChanged={load}
        />
      )}

      {deleting && (
        <Modal
          title="Xóa lead?"
          size="small"
          onClose={() => setDeleting(null)}
          footer={
            <>
              <button className="btn" onClick={() => setDeleting(null)}>Hủy</button>
              <button className="btn danger-fill" onClick={confirmDelete}>Xóa</button>
            </>
          }
        >
          <p>
            Lead <b>{deleting.code} - {deleting.fullName}</b> sẽ được chuyển vào thùng rác (xóa mềm, quản trị viên có thể khôi phục).
          </p>
        </Modal>
      )}
    </CrmLayout>
  )
}
