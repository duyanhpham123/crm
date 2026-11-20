import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { customerApi } from '../../api/crmApi'
import { getErrorMessage } from '../../api/client'
import Pagination from '../../components/Pagination'
import { PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatMoneyShort, initials } from '../../utils/format'
import CrmLayout from './CrmLayout'
import CustomerFormModal from './CustomerFormModal'
import useCrmLookups from './useCrmLookups'

const PAGE_SIZE = 20

/** Danh sách khách hàng: tìm theo tên / MST / SĐT / người liên hệ, lọc nhóm & người phụ trách. */
export default function CustomersPage() {
  const { can } = useAuth()
  const navigate = useNavigate()
  const lookups = useCrmLookups()

  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ search: '', groupId: '', ownerId: '' })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const [creating, setCreating] = useState(false)

  const load = useCallback(async () => {
    try {
      setError('')
      setData(await customerApi.list({ ...filters, page, pageSize: PAGE_SIZE }))
    } catch (err) {
      setError(getErrorMessage(err))
      setData((d) => d ?? { items: [], page: 1, totalPages: 0, totalCount: 0 })
    }
  }, [filters, page])

  useEffect(() => {
    const timer = setTimeout(load, 300)
    return () => clearTimeout(timer)
  }, [load])

  const setFilter = (field) => (e) => {
    setFilters({ ...filters, [field]: e.target.value })
    setPage(1)
  }

  return (
    <CrmLayout>
      <div className="page-head">
        <h1>Khách hàng</h1>
        {can(PERMISSIONS.CRM_CREATE) && (
          <button className="btn primary" onClick={() => setCreating(true)}>
            <i className="ti ti-plus" aria-hidden="true" /> Thêm khách hàng
          </button>
        )}
      </div>

      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm tên, mã, MST, SĐT, người liên hệ" value={filters.search} onChange={setFilter('search')} aria-label="Tìm khách hàng" />
        </div>
        <select value={filters.groupId} onChange={setFilter('groupId')} aria-label="Lọc theo nhóm">
          <option value="">Mọi nhóm</option>
          {lookups.customerGroups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
        <select value={filters.ownerId} onChange={setFilter('ownerId')} aria-label="Lọc theo người phụ trách">
          <option value="">Mọi người phụ trách</option>
          {lookups.owners.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
        </select>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr>
              <th>Khách hàng</th>
              <th className="hide-sm">Liên hệ</th>
              <th className="hide-sm">Nhóm</th>
              <th className="num">Cơ hội đang mở</th>
              <th className="hide-sm">Phụ trách</th>
            </tr>
          </thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.items.length === 0 && (
              <tr><td colSpan={5} className="muted center">
                {filters.search || filters.groupId || filters.ownerId ? 'Không có khách hàng nào khớp bộ lọc.' : 'Chưa có khách hàng. Thêm mới hoặc chuyển đổi từ Lead.'}
              </td></tr>
            )}
            {data?.items.map((c) => (
              <tr key={c.id} className="clickable" onClick={() => navigate(`/crm/customers/${c.id}`)}>
                <td>
                  <div className="user-cell">
                    <span className="avatar square"><i className={`ti ti-${c.partnerType === 'company' ? 'building' : 'user'}`} aria-hidden="true" /></span>
                    <div>
                      <Link to={`/crm/customers/${c.id}`} onClick={(e) => e.stopPropagation()}>{c.name}</Link>
                      <div className="muted small">{c.code}{c.taxCode ? ` · MST ${c.taxCode}` : ''}</div>
                    </div>
                  </div>
                </td>
                <td className="hide-sm">
                  {c.primaryContact ?? c.phone}
                  <div className="muted small">{c.primaryContact ? c.phone : c.email}</div>
                </td>
                <td className="hide-sm">{c.groupName}</td>
                <td className="num">
                  {c.openOpportunities > 0 ? <>{c.openOpportunities} <span className="muted small">· {formatMoneyShort(c.openPipelineValue)}</span></> : <span className="muted">-</span>}
                </td>
                <td className="hide-sm">{c.ownerName && <span className="owner"><span className="avatar tiny">{initials(c.ownerName)}</span>{c.ownerName}</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination data={data} unit="khách hàng" onPageChange={setPage} />

      {creating && (
        <CustomerFormModal
          lookups={lookups}
          onClose={() => setCreating(false)}
          onSaved={(saved) => navigate(`/crm/customers/${saved.id}`)}
        />
      )}
    </CrmLayout>
  )
}
