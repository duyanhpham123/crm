import { useCallback, useEffect, useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { userApi } from '../../api/userApi'
import Modal from '../../components/Modal'
import Pagination from '../../components/Pagination'
import { PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateTime, initials } from '../../utils/format'
import ResetPasswordModal from './ResetPasswordModal'
import UserFormModal from './UserFormModal'
import UsersLayout from './UsersLayout'

const PAGE_SIZE = 20

/** Danh sách tài khoản nhân viên: tìm, lọc theo phòng ban / vai trò / trạng thái, tạo, sửa, khóa, đặt lại mật khẩu. */
export default function UsersPage() {
  const { me, can } = useAuth()

  const [data, setData] = useState(null)
  const [options, setOptions] = useState({ departments: [], roles: [] })
  const [filters, setFilters] = useState({ search: '', departmentId: '', roleId: '', isActive: '' })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [editing, setEditing] = useState(null)      // null | 'new' | UserDetail
  const [resetting, setResetting] = useState(null)  // UserListItem
  const [toggling, setToggling] = useState(null)    // UserListItem

  const load = useCallback(async () => {
    try {
      setError('')
      setData(await userApi.list({ ...filters, page, pageSize: PAGE_SIZE }))
    } catch (err) {
      setError(getErrorMessage(err))
      setData((d) => d ?? { items: [], page: 1, totalPages: 0, totalCount: 0 })
    }
  }, [filters, page])

  useEffect(() => {
    const timer = setTimeout(load, 300)
    return () => clearTimeout(timer)
  }, [load])

  useEffect(() => {
    userApi.formOptions().then(setOptions).catch(() => {})
  }, [])

  const setFilter = (field) => (e) => {
    setFilters({ ...filters, [field]: e.target.value })
    setPage(1)
  }

  const flash = (message) => {
    setNotice(message)
    setTimeout(() => setNotice(''), 4000)
  }

  const openEdit = async (id) => {
    try {
      setEditing(await userApi.get(id))
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }

  const confirmToggle = async () => {
    try {
      await userApi.setStatus(toggling.id, !toggling.isActive)
      flash(toggling.isActive ? `Đã khóa tài khoản ${toggling.userName}.` : `Đã mở khóa tài khoản ${toggling.userName}.`)
      setToggling(null)
      load()
    } catch (err) {
      setError(getErrorMessage(err))
      setToggling(null)
    }
  }

  const canEdit = can(PERMISSIONS.USERS_EDIT)

  return (
    <UsersLayout>
      <div className="page-head">
        <h1>Người dùng</h1>
        {can(PERMISSIONS.USERS_CREATE) && (
          <button className="btn primary" onClick={() => setEditing('new')}>
            <i className="ti ti-user-plus" aria-hidden="true" /> Thêm người dùng
          </button>
        )}
      </div>

      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm tên, tên đăng nhập, email, SĐT" value={filters.search} onChange={setFilter('search')} aria-label="Tìm người dùng" />
        </div>
        <select value={filters.departmentId} onChange={setFilter('departmentId')} aria-label="Lọc theo phòng ban">
          <option value="">Tất cả phòng ban</option>
          {options.departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
        <select value={filters.roleId} onChange={setFilter('roleId')} aria-label="Lọc theo vai trò">
          <option value="">Tất cả vai trò</option>
          {options.roles.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
        </select>
        <select value={filters.isActive} onChange={setFilter('isActive')} aria-label="Lọc theo trạng thái">
          <option value="">Mọi trạng thái</option>
          <option value="true">Đang hoạt động</option>
          <option value="false">Đã khóa</option>
        </select>
      </div>

      {error && <div className="alert error">{error}</div>}
      {notice && <div className="alert success">{notice}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr>
              <th>Người dùng</th>
              <th className="hide-sm">Liên hệ</th>
              <th className="hide-sm">Phòng ban</th>
              <th>Vai trò</th>
              <th>Trạng thái</th>
              <th className="hide-sm">Đăng nhập gần nhất</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {!data && <tr><td colSpan={7} className="muted center">Đang tải...</td></tr>}
            {data?.items.length === 0 && <tr><td colSpan={7} className="muted center">Không có người dùng nào khớp bộ lọc.</td></tr>}
            {data?.items.map((u) => {
              const isMe = u.id === me.userId
              return (
                <tr key={u.id} className={u.isActive ? '' : 'inactive'}>
                  <td>
                    <div className="user-cell">
                      <span className="avatar">{initials(u.fullName)}</span>
                      <div>
                        <button className="link" onClick={() => openEdit(u.id)}>{u.fullName}</button>
                        {isMe && <span className="muted small"> (bạn)</span>}
                        <div className="muted small">{u.userName}</div>
                      </div>
                    </div>
                  </td>
                  <td className="hide-sm">{u.email}<div className="muted small">{u.phoneNumber}</div></td>
                  <td className="hide-sm">{u.departmentName}</td>
                  <td>
                    <div className="chips">
                      {u.isSystemAdmin && <span className="pill admin">Quản trị hệ thống</span>}
                      {u.roles.filter((r) => !(u.isSystemAdmin && r === 'Quản trị hệ thống')).map((r) => <span key={r} className="pill">{r}</span>)}
                    </div>
                  </td>
                  <td>
                    {!u.isActive ? <span className="pill unqualified">Đã khóa</span>
                      : u.isLockedOut ? <span className="pill contacted" title="Sai mật khẩu nhiều lần, tự mở sau 15 phút">Tạm khóa</span>
                      : <span className="pill qualified">Hoạt động</span>}
                  </td>
                  <td className="hide-sm">{u.lastLoginAt ? formatDateTime(u.lastLoginAt) : <span className="muted">Chưa đăng nhập</span>}</td>
                  <td className="actions">
                    {canEdit && (
                      <>
                        <button className="btn ghost" title="Sửa" aria-label={`Sửa ${u.fullName}`} onClick={() => openEdit(u.id)}>
                          <i className="ti ti-edit" aria-hidden="true" />
                        </button>
                        <button className="btn ghost" title="Đặt lại mật khẩu" aria-label={`Đặt lại mật khẩu ${u.fullName}`} onClick={() => setResetting(u)}>
                          <i className="ti ti-key" aria-hidden="true" />
                        </button>
                        {!isMe && (
                          <button
                            className={`btn ghost${u.isActive ? ' danger' : ''}`}
                            title={u.isActive ? 'Khóa tài khoản' : 'Mở khóa'}
                            aria-label={`${u.isActive ? 'Khóa' : 'Mở khóa'} ${u.fullName}`}
                            onClick={() => setToggling(u)}
                          >
                            <i className={`ti ti-${u.isActive ? 'lock' : 'lock-open'}`} aria-hidden="true" />
                          </button>
                        )}
                      </>
                    )}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      <Pagination data={data} unit="người dùng" onPageChange={setPage} />

      {editing && (
        <UserFormModal
          user={editing === 'new' ? null : editing}
          options={options}
          isSelf={editing !== 'new' && editing.id === me.userId}
          canEdit={editing === 'new' || canEdit}
          onClose={() => setEditing(null)}
          onSaved={(saved, isNew) => {
            setEditing(null)
            flash(isNew ? `Đã tạo tài khoản ${saved.userName}.` : `Đã lưu thông tin ${saved.fullName}.`)
            load()
          }}
        />
      )}

      {resetting && (
        <ResetPasswordModal
          user={resetting}
          onClose={() => setResetting(null)}
          onDone={() => {
            flash(`Đã đặt lại mật khẩu cho ${resetting.userName}. Các phiên đăng nhập cũ của người này đã bị đăng xuất.`)
            setResetting(null)
          }}
        />
      )}

      {toggling && (
        <Modal
          title={toggling.isActive ? 'Khóa tài khoản?' : 'Mở khóa tài khoản?'}
          size="small"
          onClose={() => setToggling(null)}
          footer={
            <>
              <button className="btn" onClick={() => setToggling(null)}>Hủy</button>
              <button className={toggling.isActive ? 'btn danger-fill' : 'btn primary'} onClick={confirmToggle}>
                {toggling.isActive ? 'Khóa' : 'Mở khóa'}
              </button>
            </>
          }
        >
          {toggling.isActive ? (
            <p><b>{toggling.fullName}</b> ({toggling.userName}) sẽ không đăng nhập được nữa và bị đăng xuất khỏi mọi thiết bị. Dữ liệu người này tạo vẫn được giữ nguyên.</p>
          ) : (
            <p><b>{toggling.fullName}</b> ({toggling.userName}) sẽ đăng nhập lại được với mật khẩu hiện tại.</p>
          )}
        </Modal>
      )}
    </UsersLayout>
  )
}
