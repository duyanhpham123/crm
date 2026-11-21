import { useCallback, useEffect, useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { hrApi } from '../../api/phase3Api'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import { CONTRACT_TYPES, EMPLOYMENT_STATUSES } from '../../constants'
import ModuleLayout from '../../layouts/ModuleLayout'
import { formatMoney, todayIso } from '../../utils/format'

const MENU = [
  { to: '/hr', icon: 'users', label: 'Nhân viên', end: true },
  { to: '/hr/attendance', icon: 'calendar-check', label: 'Chấm công' },
  { to: '/hr/leaves', icon: 'beach', label: 'Nghỉ phép' },
  { to: '/hr/payroll', icon: 'cash-banknote', label: 'Bảng lương' },
]

export function HrLayout({ children }) {
  return <ModuleLayout title="Nhân sự" icon="users" color="#7F77DD" menu={MENU}>{children}</ModuleLayout>
}

export function useHrLookups() {
  const [l, setL] = useState({ departments: [], positions: [], users: [], leaveTypes: [], employees: [] })
  const reload = useCallback(() => hrApi.lookups().then(setL).catch(() => {}), [])
  useEffect(() => { reload() }, [reload])
  return { ...l, reload }
}

const FIELDS = ['fullName', 'gender', 'dateOfBirth', 'idNumber', 'phone', 'email', 'address', 'departmentId', 'positionId', 'userId', 'hireDate',
  'status', 'personalTaxCode', 'dependents', 'bankName', 'bankAccountNo', 'baseSalary', 'insuranceSalary', 'allowance', 'contractType']

/** Thêm / sửa nhân viên. Đổi lương / loại hợp đồng thì hệ thống tự lập hợp đồng mới từ hôm nay. */
export function EmployeeFormModal({ employee, lookups, onClose, onSaved }) {
  const isNew = !employee
  const [form, setForm] = useState(() => ({
    ...Object.fromEntries(FIELDS.map((f) => [f, employee?.[f] ?? ''])),
    status: employee?.status ?? 'probation', hireDate: employee?.hireDate ?? todayIso(), dependents: employee?.dependents ?? 0,
    baseSalary: employee?.baseSalary ?? 7_000_000, insuranceSalary: employee?.insuranceSalary ?? 0, allowance: employee?.allowance ?? 730_000,
    contractType: employee?.contractType ?? 'probation',
  }))
  const [newPosition, setNewPosition] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })

  const addPosition = async () => {
    if (!newPosition?.trim()) return setNewPosition(null)
    try { const p = await hrApi.createPosition(newPosition.trim()); await lookups.reload(); setForm((f) => ({ ...f, positionId: p.id })); setNewPosition(null) } catch (e) { setError(getErrorMessage(e)) }
  }

  const save = async (e) => {
    e.preventDefault()
    setError('')
    if (!form.fullName.trim()) return setError('Nhập họ tên.')
    const body = {
      ...Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v === '' ? null : v])),
      departmentId: form.departmentId ? Number(form.departmentId) : null, positionId: form.positionId ? Number(form.positionId) : null,
      userId: form.userId ? Number(form.userId) : null, dependents: Number(form.dependents) || 0,
      baseSalary: Number(form.baseSalary) || 0, insuranceSalary: Number(form.insuranceSalary) || 0, allowance: Number(form.allowance) || 0,
      contractType: form.contractType || 'probation', rowVersion: employee?.rowVersion ?? null,
    }
    setBusy(true)
    try { onSaved(isNew ? await hrApi.createEmployee(body) : await hrApi.updateEmployee(employee.id, body), isNew) } catch (err) { setError(getErrorMessage(err)); setBusy(false) }
  }

  return (
    <Modal title={isNew ? 'Thêm nhân viên' : `Nhân viên ${employee.code}`} onClose={onClose} size="large">
      <form onSubmit={save}>
        <div className="form-grid three-col">
          <label className="span2">Họ tên *<input value={form.fullName} onChange={u('fullName')} autoFocus /></label>
          <label>Giới tính<select value={form.gender ?? ''} onChange={u('gender')}><option value="">-</option><option value="F">Nữ</option><option value="M">Nam</option><option value="O">Khác</option></select></label>
          <label>Ngày sinh<input type="date" value={form.dateOfBirth ?? ''} onChange={u('dateOfBirth')} /></label>
          <label>Số điện thoại<input value={form.phone ?? ''} onChange={u('phone')} /></label>
          <label>Email<input type="email" value={form.email ?? ''} onChange={u('email')} /></label>
          <label>Phòng ban<select value={form.departmentId ?? ''} onChange={u('departmentId')}><option value="">Chưa chọn</option>{lookups.departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}</select></label>
          <label>Chức danh
            {newPosition === null ? (
              <div className="inline-add">
                <select value={form.positionId ?? ''} onChange={u('positionId')}><option value="">Chưa chọn</option>{lookups.positions.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select>
                <button type="button" className="btn" onClick={() => setNewPosition('')} aria-label="Thêm chức danh"><i className="ti ti-plus" aria-hidden="true" /></button>
              </div>
            ) : (
              <div className="inline-add">
                <input autoFocus value={newPosition} onChange={(e) => setNewPosition(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addPosition() } }} />
                <button type="button" className="btn" onClick={addPosition}>Thêm</button>
              </div>
            )}
          </label>
          <label>Tài khoản đăng nhập<select value={form.userId ?? ''} onChange={u('userId')}><option value="">Không có</option>{lookups.users.map((x) => <option key={x.id} value={x.id}>{x.name} ({x.description})</option>)}</select></label>
          <label>Ngày vào làm<input type="date" value={form.hireDate ?? ''} onChange={u('hireDate')} /></label>
          <label>Trạng thái<select value={form.status} onChange={u('status')}>{EMPLOYMENT_STATUSES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}</select></label>
          <label>CCCD<input value={form.idNumber ?? ''} onChange={u('idNumber')} /></label>
          <label className="span3">Địa chỉ<input value={form.address ?? ''} onChange={u('address')} /></label>
        </div>
        <div className="variant-box">
          <div className="field-label">Hợp đồng & lương</div>
          <div className="form-grid three-col">
            <label>Loại hợp đồng<select value={form.contractType} onChange={u('contractType')}>{Object.entries(CONTRACT_TYPES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
            <label>Lương cơ bản / tháng<MoneyInput value={form.baseSalary} onChange={(v) => setForm({ ...form, baseSalary: v })} /></label>
            <label>Phụ cấp (ăn trưa, xăng xe)<MoneyInput value={form.allowance} onChange={(v) => setForm({ ...form, allowance: v })} /></label>
            <label>Lương đóng bảo hiểm<MoneyInput value={form.insuranceSalary} onChange={(v) => setForm({ ...form, insuranceSalary: v })} />
              <span className="hint-inline">0 = bằng lương cơ bản</span></label>
            <label>Người phụ thuộc<input type="number" min="0" max="20" value={form.dependents} onChange={u('dependents')} /></label>
            <label>Mã số thuế cá nhân<input value={form.personalTaxCode ?? ''} onChange={u('personalTaxCode')} /></label>
            <label>Ngân hàng<input value={form.bankName ?? ''} onChange={u('bankName')} placeholder="Vietcombank" /></label>
            <label>Số tài khoản<input value={form.bankAccountNo ?? ''} onChange={u('bankAccountNo')} /></label>
            <div className="hint-inline">Thu nhập / tháng: <b>{formatMoney((Number(form.baseSalary) || 0) + (Number(form.allowance) || 0))}</b></div>
          </div>
        </div>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot"><button type="button" className="btn" onClick={onClose}>Hủy</button><button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Lưu'}</button></div>
      </form>
    </Modal>
  )
}
