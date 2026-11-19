import { useEffect, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { roleApi } from '../../api/roleApi'
import Modal from '../../components/Modal'
import { PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import UsersLayout from './UsersLayout'

/** Danh sách vai trò: số người dùng, số quyền; tạo mới, nhân bản, xóa. */
export default function RolesPage() {
  const { can } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()

  const [roles, setRoles] = useState(null)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState(location.state?.notice ?? '')
  const [deleting, setDeleting] = useState(null)

  const load = () =>
    roleApi
      .list()
      .then(setRoles)
      .catch((err) => setError(getErrorMessage(err)))

  useEffect(() => {
    load()
    if (location.state?.notice) {
      navigate(location.pathname, { replace: true, state: null })   // không hiện lại thông báo khi bấm F5
      setTimeout(() => setNotice(''), 4000)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const confirmDelete = async () => {
    try {
      await roleApi.remove(deleting.id)
      setNotice(`Đã xóa vai trò ${deleting.name}.`)
      setDeleting(null)
      load()
    } catch (err) {
      setError(getErrorMessage(err))
      setDeleting(null)
    }
  }

  return (
    <UsersLayout>
      <div className="page-head">
        <h1>Vai trò & quyền</h1>
        {can(PERMISSIONS.USERS_CREATE) && (
          <Link className="btn primary" to="/users/roles/new">
            <i className="ti ti-plus" aria-hidden="true" /> Tạo vai trò
          </Link>
        )}
      </div>
      <p className="muted page-intro">
        Vai trò là tập quyền dùng chung, VD "Kế toán", "Thủ kho". Gán vai trò cho người dùng ở trang Người dùng; một người có thể giữ nhiều vai trò.
      </p>

      {error && <div className="alert error">{error}</div>}
      {notice && <div className="alert success">{notice}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr>
              <th>Vai trò</th>
              <th className="hide-sm">Mô tả</th>
              <th className="num">Người dùng</th>
              <th className="num hide-sm">Số quyền</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {!roles && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {roles?.map((r) => (
              <tr key={r.id}>
                <td>
                  <Link to={`/users/roles/${r.id}`}>{r.name}</Link>
                  {r.isSystem && <span className="pill admin small-pill">Hệ thống</span>}
                  <div className="muted small code">{r.code}</div>
                </td>
                <td className="hide-sm muted">{r.description}</td>
                <td className="num">{r.userCount}</td>
                <td className="num hide-sm">{r.isSystem ? 'Toàn quyền' : r.permissionCount}</td>
                <td className="actions">
                  {can(PERMISSIONS.USERS_CREATE) && !r.isSystem && (
                    <Link className="btn ghost" to={`/users/roles/new?copyFrom=${r.id}`} title="Nhân bản" aria-label={`Nhân bản ${r.name}`}>
                      <i className="ti ti-copy" aria-hidden="true" />
                    </Link>
                  )}
                  {can(PERMISSIONS.USERS_DELETE) && !r.isSystem && (
                    <button className="btn ghost danger" title="Xóa" aria-label={`Xóa ${r.name}`} onClick={() => setDeleting(r)}>
                      <i className="ti ti-trash" aria-hidden="true" />
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {deleting && (
        <Modal
          title="Xóa vai trò?"
          size="small"
          onClose={() => setDeleting(null)}
          footer={
            <>
              <button className="btn" onClick={() => setDeleting(null)}>Hủy</button>
              <button className="btn danger-fill" onClick={confirmDelete}>Xóa</button>
            </>
          }
        >
          {deleting.userCount > 0 ? (
            <p>Vai trò <b>{deleting.name}</b> đang được gán cho {deleting.userCount} người dùng. Hệ thống sẽ từ chối xóa cho tới khi gỡ vai trò khỏi họ.</p>
          ) : (
            <p>Xóa vai trò <b>{deleting.name}</b>? Thao tác này không ảnh hưởng tới người dùng nào.</p>
          )}
        </Modal>
      )}
    </UsersLayout>
  )
}
