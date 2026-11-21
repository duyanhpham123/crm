import { useCallback, useEffect, useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { settingsApi } from '../../api/phase3Api'
import AppIcon from '../../components/AppIcon'
import Modal from '../../components/Modal'
import { PHASE3_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import ModuleLayout from '../../layouts/ModuleLayout'
import { formatMoney } from '../../utils/format'

const MENU = [
  { to: '/settings', icon: 'building-store', label: 'Thông tin cửa hàng', end: true },
  { to: '/settings/departments', icon: 'sitemap', label: 'Phòng ban' },
  { to: '/settings/warehouses', icon: 'building-warehouse', label: 'Kho hàng' },
  { to: '/settings/apps', icon: 'apps', label: 'Ứng dụng' },
  { to: '/settings/numbering', icon: 'hash', label: 'Đánh số chứng từ' },
]

function SettingsLayout({ children }) {
  return <ModuleLayout title="Cài đặt" icon="settings" color="#444441" menu={MENU}>{children}</ModuleLayout>
}

/** Thông tin công ty / cửa hàng - in trên báo giá và chứng từ. */
export function CompanySettingsPage() {
  const { can } = useAuth()
  const [form, setForm] = useState(null)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  useEffect(() => { settingsApi.company().then((c) => setForm(Object.fromEntries(Object.entries(c).map(([k, v]) => [k, v ?? ''])))).catch((e) => setError(getErrorMessage(e))) }, [])
  const canEdit = can(PHASE3_PERMISSIONS.SETTINGS_EDIT)
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })
  const save = async (e) => {
    e.preventDefault(); setError(''); setMessage('')
    try { await settingsApi.updateCompany(Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v === '' ? null : v]))); setMessage('Đã lưu thông tin cửa hàng.') } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <SettingsLayout>
      <div className="page-head"><h1>Thông tin cửa hàng</h1></div>
      <p className="muted page-intro">Hiển thị trên báo giá, phiếu in gửi khách.</p>
      {message && <div className="alert success">{message}</div>}
      {error && <div className="alert error">{error}</div>}
      {form && (
        <form className="card" onSubmit={save}>
          <fieldset disabled={!canEdit}>
            <div className="form-grid">
              <label className="span2">Tên công ty / cửa hàng *<input value={form.name} onChange={u('name')} /></label>
              <label>Tên ngắn (thương hiệu)<input value={form.shortName} onChange={u('shortName')} placeholder="MyStyle" /></label>
              <label>Mã số thuế<input value={form.taxCode} onChange={u('taxCode')} /></label>
              <label className="span2">Địa chỉ<input value={form.address} onChange={u('address')} /></label>
              <label>Hotline<input value={form.phone} onChange={u('phone')} /></label>
              <label>Email<input value={form.email} onChange={u('email')} /></label>
              <label>Website / fanpage<input value={form.website} onChange={u('website')} /></label>
              <label>Người đại diện<input value={form.legalRepresentative} onChange={u('legalRepresentative')} /></label>
              <label className="span2">Chính sách đổi trả (in trên báo giá)<textarea rows={3} value={form.returnPolicy} onChange={u('returnPolicy')} placeholder="Đổi size trong 7 ngày, còn tem mác..." /></label>
              <label className="span2">Lời cảm ơn cuối phiếu<input value={form.printFooter} onChange={u('printFooter')} placeholder="Cảm ơn quý khách đã tin tưởng!" /></label>
            </div>
            {canEdit && <div className="modal-foot"><button className="btn primary">Lưu</button></div>}
          </fieldset>
          <p />
        </form>
      )}
    </SettingsLayout>
  )
}

function DepartmentModal({ dept, departments, onClose, onSaved }) {
  const [form, setForm] = useState({ code: dept?.code ?? '', name: dept?.name ?? '', parentId: dept?.parentId ?? '', sortOrder: dept?.sortOrder ?? 0, isActive: dept?.isActive ?? true })
  const [error, setError] = useState('')
  const save = async (e) => {
    e.preventDefault()
    const body = { ...form, parentId: form.parentId ? Number(form.parentId) : null, sortOrder: Number(form.sortOrder) || 0 }
    try { onSaved(dept ? await settingsApi.updateDepartment(dept.id, body) : await settingsApi.createDepartment(body)) } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <Modal title={dept ? `Phòng ban ${dept.code}` : 'Thêm phòng ban'} onClose={onClose} size="small">
      <form onSubmit={save}>
        <label>Mã *<input value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} disabled={!!dept} autoFocus={!dept} placeholder="ONLINE" /></label>
        <label>Tên *<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} autoFocus={!!dept} /></label>
        <label>Thuộc phòng ban<select value={form.parentId} onChange={(e) => setForm({ ...form, parentId: e.target.value })}><option value="">Không</option>{departments.filter((d) => d.id !== dept?.id).map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}</select></label>
        <label>Thứ tự<input type="number" value={form.sortOrder} onChange={(e) => setForm({ ...form, sortOrder: e.target.value })} /></label>
        {dept && <label className="check"><input type="checkbox" checked={form.isActive} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} /> Đang dùng</label>}
        {error && <p className="error">{error}</p>}
        <div className="modal-foot"><button type="button" className="btn" onClick={onClose}>Hủy</button><button className="btn primary">Lưu</button></div>
      </form>
    </Modal>
  )
}

export function DepartmentsPage() {
  const { can } = useAuth()
  const [list, setList] = useState(null)
  const [editing, setEditing] = useState(null)
  const [error, setError] = useState('')
  const load = useCallback(() => settingsApi.departments().then(setList).catch((e) => setError(getErrorMessage(e))), [])
  useEffect(() => { load() }, [load])
  const nameOf = (id) => list?.find((d) => d.id === id)?.name
  return (
    <SettingsLayout>
      <div className="page-head"><h1>Phòng ban</h1>
        {can(PHASE3_PERMISSIONS.SETTINGS_EDIT) && <button className="btn primary" onClick={() => setEditing('new')}><i className="ti ti-plus" aria-hidden="true" /> Thêm phòng ban</button>}</div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Phòng ban</th><th className="hide-sm">Thuộc</th><th className="num">Nhân viên</th><th className="num">Tài khoản</th><th /></tr></thead>
          <tbody>
            {list?.map((d) => (
              <tr key={d.id} className={`clickable${d.isActive ? '' : ' inactive'}`} onClick={() => can(PHASE3_PERMISSIONS.SETTINGS_EDIT) && setEditing(d)}>
                <td><b>{d.name}</b><div className="muted small code-inline">{d.code}</div></td>
                <td className="hide-sm">{nameOf(d.parentId)}</td>
                <td className="num">{d.employeeCount}</td><td className="num">{d.userCount}</td>
                <td>{!d.isActive && <span className="pill draft">Ngừng dùng</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {editing && <DepartmentModal dept={editing === 'new' ? null : editing} departments={list ?? []} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); load() }} />}
    </SettingsLayout>
  )
}

function WarehouseModal({ wh, onClose, onSaved }) {
  const [form, setForm] = useState({ code: wh?.code ?? '', name: wh?.name ?? '', street: wh?.street ?? '', allowNegativeStock: wh?.allowNegativeStock ?? false, isActive: wh?.isActive ?? true })
  const [error, setError] = useState('')
  const save = async (e) => {
    e.preventDefault()
    try { onSaved(wh ? await settingsApi.updateWarehouse(wh.id, form) : await settingsApi.createWarehouse(form)) } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <Modal title={wh ? `Kho ${wh.code}` : 'Thêm kho'} onClose={onClose} size="small">
      <form onSubmit={save}>
        <label>Mã kho *<input value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} disabled={!!wh} autoFocus={!wh} placeholder="KHO02" /></label>
        <label>Tên kho *<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Kho chi nhánh Quận 3" /></label>
        <label>Địa chỉ<input value={form.street} onChange={(e) => setForm({ ...form, street: e.target.value })} /></label>
        <label className="check"><input type="checkbox" checked={form.allowNegativeStock} onChange={(e) => setForm({ ...form, allowNegativeStock: e.target.checked })} /> Cho phép bán khi hết hàng (tồn âm)</label>
        {wh && <label className="check"><input type="checkbox" checked={form.isActive} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} /> Đang dùng</label>}
        {error && <p className="error">{error}</p>}
        <div className="modal-foot"><button type="button" className="btn" onClick={onClose}>Hủy</button><button className="btn primary">Lưu</button></div>
      </form>
    </Modal>
  )
}

export function WarehousesPage() {
  const { can } = useAuth()
  const [list, setList] = useState(null)
  const [editing, setEditing] = useState(null)
  const [error, setError] = useState('')
  const load = useCallback(() => settingsApi.warehouses().then(setList).catch((e) => setError(getErrorMessage(e))), [])
  useEffect(() => { load() }, [load])
  return (
    <SettingsLayout>
      <div className="page-head"><h1>Kho hàng</h1>
        {can(PHASE3_PERMISSIONS.SETTINGS_EDIT) && <button className="btn primary" onClick={() => setEditing('new')}><i className="ti ti-plus" aria-hidden="true" /> Thêm kho</button>}</div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Kho</th><th className="num">Mã hàng còn tồn</th><th className="num">Giá trị tồn</th><th /></tr></thead>
          <tbody>
            {list?.map((w) => (
              <tr key={w.id} className={`clickable${w.isActive ? '' : ' inactive'}`} onClick={() => can(PHASE3_PERMISSIONS.SETTINGS_EDIT) && setEditing(w)}>
                <td><b>{w.name}</b><div className="muted small">{w.code}{w.street ? ` · ${w.street}` : ''}</div></td>
                <td className="num">{w.skuCount}</td><td className="num">{formatMoney(Math.round(w.stockValue))}</td>
                <td>{!w.isActive && <span className="pill draft">Ngừng dùng</span>}{w.allowNegativeStock && <span className="pill warn">Cho tồn âm</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {editing && <WarehouseModal wh={editing === 'new' ? null : editing} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); load() }} />}
    </SettingsLayout>
  )
}

/** Bật / tắt ứng dụng trên màn hình chính cho cả công ty. */
export function AppsSettingsPage() {
  const { can } = useAuth()
  const [list, setList] = useState(null)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  useEffect(() => { settingsApi.apps().then(setList).catch((e) => setError(getErrorMessage(e))) }, [])
  const toggle = async (a) => {
    setError('')
    try { const r = await settingsApi.toggleApp(a.id, !a.isEnabled); setList(list.map((x) => (x.id === a.id ? r : x))); setMessage(`${r.isEnabled ? 'Đã bật' : 'Đã tắt'} ${r.name}. Tải lại trang chủ để thấy thay đổi.`) } catch (e) { setError(getErrorMessage(e)) }
  }
  return (
    <SettingsLayout>
      <div className="page-head"><h1>Ứng dụng</h1></div>
      <p className="muted page-intro">Tắt ứng dụng chưa dùng để màn hình chính gọn hơn. Dữ liệu không bị xóa, bật lại là dùng tiếp.</p>
      {message && <div className="alert success">{message}</div>}
      {error && <div className="alert error">{error}</div>}
      <div className="card no-pad">
        {list?.map((a) => (
          <div key={a.id} className="app-toggle">
            <AppIcon icon={a.icon} color={a.color} small />
            <div><b>{a.name}</b>{a.locked && <div className="muted small">Luôn bật</div>}</div>
            <span className="spacer" />
            <label className="switch" aria-label={`Bật / tắt ${a.name}`}>
              <input type="checkbox" checked={a.isEnabled} disabled={a.locked || !can(PHASE3_PERMISSIONS.SETTINGS_EDIT)} onChange={() => toggle(a)} />
              <span />
            </label>
          </div>
        ))}
      </div>
    </SettingsLayout>
  )
}

/** Quy tắc đánh số chứng từ: tiền tố, mẫu ngày, số chữ số. */
export function NumberingPage() {
  const { can } = useAuth()
  const [list, setList] = useState(null)
  const [editing, setEditing] = useState(null)
  const [error, setError] = useState('')
  useEffect(() => { settingsApi.sequences().then(setList).catch((e) => setError(getErrorMessage(e))) }, [])
  const save = async () => {
    setError('')
    try { const r = await settingsApi.updateSequence(editing.id, { prefix: editing.prefix, datePattern: editing.datePattern || null, padding: Number(editing.padding) }); setList(list.map((x) => (x.id === r.id ? r : x))); setEditing(null) } catch (e) { setError(getErrorMessage(e)) }
  }
  return (
    <SettingsLayout>
      <div className="page-head"><h1>Đánh số chứng từ</h1></div>
      <p className="muted page-intro">Đổi tiền tố chỉ áp dụng cho chứng từ tạo mới, chứng từ cũ giữ nguyên số.</p>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Chứng từ</th><th>Tiền tố</th><th className="hide-sm">Mẫu ngày</th><th>Mẫu số chứng từ</th><th className="actions" /></tr></thead>
          <tbody>
            {list?.map((s) => (
              <tr key={s.id}>
                <td>{s.label}</td><td className="code">{s.prefix}</td><td className="hide-sm code">{s.datePattern ?? '-'}</td><td className="code">{s.example}</td>
                <td className="actions">{can(PHASE3_PERMISSIONS.SETTINGS_EDIT) && <button className="btn ghost" onClick={() => setEditing({ ...s, datePattern: s.datePattern ?? '' })} aria-label={`Sửa ${s.label}`}><i className="ti ti-pencil" aria-hidden="true" /></button>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {editing && (
        <Modal title={editing.label} onClose={() => setEditing(null)} size="small">
          <label>Tiền tố<input value={editing.prefix} onChange={(e) => setEditing({ ...editing, prefix: e.target.value.toUpperCase() })} autoFocus /></label>
          <label>Mẫu ngày
            <select value={editing.datePattern} onChange={(e) => setEditing({ ...editing, datePattern: e.target.value })}>
              <option value="">Không (đếm liên tục)</option><option value="yyMM">yyMM - năm tháng (đếm lại mỗi tháng)</option>
              <option value="yyyyMM">yyyyMM</option><option value="yyyy">yyyy - năm (đếm lại mỗi năm)</option>
            </select>
          </label>
          <label>Số chữ số<input type="number" min="3" max="8" value={editing.padding} onChange={(e) => setEditing({ ...editing, padding: e.target.value })} /></label>
          {error && <p className="error">{error}</p>}
          <div className="modal-foot"><button className="btn" onClick={() => setEditing(null)}>Hủy</button><button className="btn primary" onClick={save}>Lưu</button></div>
        </Modal>
      )}
    </SettingsLayout>
  )
}
