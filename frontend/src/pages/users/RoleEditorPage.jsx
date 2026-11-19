import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { roleApi } from '../../api/roleApi'
import AppIcon from '../../components/AppIcon'
import { DATA_SCOPES, PERMISSION_ACTIONS } from '../../constants'
import UsersLayout from './UsersLayout'

const DEFAULT_SCOPE = 'own'   // quyền mới cấp mặc định hẹp nhất (nguyên tắc đặc quyền tối thiểu)

/**
 * Tạo / sửa vai trò với ma trận phân quyền:
 *   hàng = ứng dụng, cột = hành động (Xem, Tạo, Sửa...), cột cuối = phạm vi dữ liệu.
 * Quyền đặc thù (VD "Ghi sổ bút toán") hiện thành ô chọn bên dưới hàng của ứng dụng.
 */
export default function RoleEditorPage() {
  const { id } = useParams()
  const [params] = useSearchParams()
  const navigate = useNavigate()
  const isNew = !id
  const copyFrom = params.get('copyFrom')

  const [catalog, setCatalog] = useState(null)
  const [role, setRole] = useState(null)
  const [form, setForm] = useState({ code: '', name: '', description: '' })
  const [grants, setGrants] = useState({})   // permissionId -> dataScope
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    const sourceId = id ?? copyFrom
    Promise.all([roleApi.catalog(), sourceId ? roleApi.get(sourceId) : null])
      .then(([cat, source]) => {
        setCatalog(cat)
        if (!source) return
        setGrants(Object.fromEntries(source.permissions.map((p) => [p.permissionId, p.dataScope])))
        if (isNew) {
          setForm({ code: `${source.code}_copy`, name: `Bản sao của ${source.name}`, description: source.description ?? '' })
        } else {
          setRole(source)
          setForm({ code: source.code, name: source.name, description: source.description ?? '' })
        }
      })
      .catch((err) => setError(getErrorMessage(err)))
  }, [id, copyFrom, isNew])

  const readOnly = role?.isReadOnly ?? false
  const scopes = DATA_SCOPES.filter((s) => !s.adminOnly || catalog?.canGrantAllCompanies)

  // ---------- Thao tác trên ma trận ----------
  const viewOf = (group) => group.permissions.find((p) => p.action === 'view')
  const groupScope = (group) => group.permissions.map((p) => grants[p.id]).find(Boolean) ?? DEFAULT_SCOPE

  const toggle = (group, permission) => {
    const next = { ...grants }
    const view = viewOf(group)
    if (next[permission.id]) {
      delete next[permission.id]
      // Bỏ "Xem" thì bỏ hết quyền của ứng dụng (không xem được thì không làm gì được)
      if (permission.id === view?.id) group.permissions.forEach((p) => delete next[p.id])
    } else {
      const scope = groupScope(group)
      next[permission.id] = scope
      if (view && !next[view.id]) next[view.id] = scope   // cấp bất kỳ quyền nào thì tự cấp "Xem"
    }
    setGrants(next)
  }

  const toggleGroup = (group) => {
    const next = { ...grants }
    const allOn = group.permissions.every((p) => next[p.id])
    const scope = groupScope(group)
    group.permissions.forEach((p) => (allOn ? delete next[p.id] : (next[p.id] = next[p.id] ?? scope)))
    setGrants(next)
  }

  const setScope = (group, scope) => {
    const next = { ...grants }
    group.permissions.forEach((p) => { if (next[p.id]) next[p.id] = scope })
    setGrants(next)
  }

  const summary = useMemo(() => {
    if (!catalog) return ''
    const count = Object.keys(grants).length
    const apps = catalog.groups.filter((g) => g.permissions.some((p) => grants[p.id])).length
    return count === 0 ? 'Chưa cấp quyền nào' : `${count} quyền trên ${apps} ứng dụng`
  }, [grants, catalog])

  // ---------- Lưu ----------
  const save = async (e) => {
    e.preventDefault()
    setError('')
    if (isNew && !form.code.trim()) return setError('Nhập mã vai trò.')
    if (!form.name.trim()) return setError('Nhập tên vai trò.')

    const body = {
      code: isNew ? form.code : null,
      name: form.name,
      description: form.description || null,
      permissions: Object.entries(grants).map(([permissionId, dataScope]) => ({ permissionId: Number(permissionId), dataScope })),
      rowVersion: role?.rowVersion ?? null,
    }
    setBusy(true)
    try {
      const saved = isNew ? await roleApi.create(body) : await roleApi.update(role.id, body)
      navigate('/users/roles', { state: { notice: isNew ? `Đã tạo vai trò ${saved.name}.` : `Đã lưu vai trò ${saved.name}. Người dùng giữ vai trò này nhận quyền mới ngay.` } })
    } catch (err) {
      setError(getErrorMessage(err))
      window.scrollTo({ top: 0, behavior: 'smooth' })
    } finally {
      setBusy(false)
    }
  }

  if (!catalog && !error) return <UsersLayout><p className="muted">Đang tải...</p></UsersLayout>

  return (
    <UsersLayout>
      <form onSubmit={save}>
        <div className="page-head">
          <div>
            <Link to="/users/roles" className="muted small"><i className="ti ti-arrow-left" aria-hidden="true" /> Vai trò & quyền</Link>
            <h1>{isNew ? 'Tạo vai trò' : role?.name}</h1>
          </div>
          {!readOnly && (
            <div className="head-actions">
              <Link className="btn" to="/users/roles">Hủy</Link>
              <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Lưu vai trò'}</button>
            </div>
          )}
        </div>

        {readOnly && <div className="alert info"><i className="ti ti-lock" aria-hidden="true" /> {role.readOnlyReason}</div>}
        {error && <div className="alert error">{error}</div>}

        <fieldset disabled={readOnly}>
          <div className="card">
            <div className="form-grid three">
              <label>Mã vai trò *
                <input value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} disabled={!isNew} placeholder="ke_toan_truong" />
              </label>
              <label>Tên vai trò *
                <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Kế toán trưởng" />
              </label>
              <label>Mô tả
                <input value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="Duyệt chứng từ, khóa sổ" />
              </label>
            </div>
            {!isNew && <p className="muted small">Đang được gán cho {role?.userCount ?? 0} người dùng.</p>}
          </div>

          {role?.isSystem ? null : (
            <>
              <div className="matrix-head">
                <h2>Quyền</h2>
                <span className="muted">{summary}</span>
              </div>
              <div className="table-wrap">
                <table className="grid matrix">
                  <thead>
                    <tr>
                      <th>Ứng dụng</th>
                      {PERMISSION_ACTIONS.map((a) => <th key={a.action} className="center">{a.label}</th>)}
                      <th>Phạm vi dữ liệu</th>
                    </tr>
                  </thead>
                  <tbody>
                    {catalog?.groups.map((group) => {
                      const special = group.permissions.filter((p) => !p.isStandard)
                      const any = group.permissions.some((p) => grants[p.id])
                      const all = group.permissions.every((p) => grants[p.id])
                      return (
                        <tr key={group.appCode} className={any ? 'granted' : ''}>
                          <td>
                            <label className="app-cell" title="Chọn / bỏ tất cả quyền của ứng dụng">
                              <input type="checkbox" checked={all} ref={(el) => el && (el.indeterminate = any && !all)} onChange={() => toggleGroup(group)} aria-label={`Tất cả quyền - ${group.appName}`} />
                              <AppIcon icon={group.icon} color={group.color} small />
                              <span>{group.appName}</span>
                            </label>
                            {special.length > 0 && (
                              <div className="special-perms">
                                {special.map((p) => (
                                  <label key={p.id} className="special">
                                    <input type="checkbox" checked={!!grants[p.id]} onChange={() => toggle(group, p)} aria-label={`${p.name} - ${group.appName}`} />
                                    {p.name}
                                  </label>
                                ))}
                              </div>
                            )}
                          </td>
                          {PERMISSION_ACTIONS.map((a) => {
                            const p = group.permissions.find((x) => x.action === a.action)
                            return (
                              <td key={a.action} className="center">
                                {p && (
                                  <input type="checkbox" checked={!!grants[p.id]} onChange={() => toggle(group, p)} aria-label={`${a.label} - ${group.appName}`} />
                                )}
                              </td>
                            )
                          })}
                          <td>
                            <select value={groupScope(group)} onChange={(e) => setScope(group, e.target.value)} disabled={!any} aria-label={`Phạm vi dữ liệu - ${group.appName}`}>
                              {scopes.map((s) => <option key={s.value} value={s.value} title={s.hint}>{s.label}</option>)}
                            </select>
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
              <p className="muted small">
                Phạm vi dữ liệu: <b>Của tôi</b> = chỉ dữ liệu mình phụ trách · <b>Phòng ban</b> = của cả phòng · <b>Chi nhánh</b> = của cả chi nhánh · <b>Toàn công ty</b> = mọi dữ liệu.
                Người dùng có nhiều vai trò sẽ nhận phạm vi rộng nhất.
              </p>
            </>
          )}
        </fieldset>
      </form>
    </UsersLayout>
  )
}
