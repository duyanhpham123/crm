import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { hrApi } from '../../api/phase3Api'
import { accountingApi } from '../../api/phase2Api'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import Pagination from '../../components/Pagination'
import { ATTENDANCE_STATUSES, EMPLOYMENT_STATUSES, employmentStatus, LEAVE_CSS, LEAVE_STATUSES, PAYROLL_CSS, PAYROLL_STATUSES, PHASE3_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateOnly, formatDateTime, formatMoney, formatQty, todayIso } from '../../utils/format'
import { EmployeeFormModal, HrLayout, useHrLookups } from './HrShared'

/** Giờ chấm công lưu theo giờ Việt Nam (không phải UTC): lấy thẳng HH:mm */
const hhmm = (iso) => (iso ? iso.slice(11, 16) : '')
const attStatus = (v) => ATTENDANCE_STATUSES.find((s) => s.value === v) ?? ATTENDANCE_STATUSES[0]

/** Danh sách nhân viên + số liệu nhanh. */
export function EmployeesPage() {
  const { can } = useAuth()
  const lookups = useHrLookups()
  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ search: '', departmentId: '', status: 'working' })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const [editing, setEditing] = useState(null)
  const [message, setMessage] = useState('')

  const load = useCallback(async () => {
    try { setError(''); setData(await hrApi.employees({ ...filters, page, pageSize: 20 })) } catch (e) { setError(getErrorMessage(e)) }
  }, [filters, page])
  useEffect(() => { const t = setTimeout(load, 250); return () => clearTimeout(t) }, [load])
  const setFilter = (f, v) => { setFilters({ ...filters, [f]: v }); setPage(1) }
  const open = async (id) => { try { setEditing(await hrApi.employee(id)) } catch (e) { setError(getErrorMessage(e)) } }
  const s = data?.summary

  return (
    <HrLayout>
      <div className="page-head">
        <h1>Nhân viên</h1>
        {can(PHASE3_PERMISSIONS.HR_CREATE) && <button className="btn primary" onClick={() => setEditing('new')}><i className="ti ti-plus" aria-hidden="true" /> Thêm nhân viên</button>}
      </div>
      {message && <div className="alert success">{message}</div>}
      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Đang làm việc</span><b>{s?.working ?? '…'}</b><span className="small muted">{s ? `${s.probation} thử việc` : ''}</span></div>
        <div className="kpi"><span className="muted small">Hôm nay đi làm / nghỉ phép</span><b>{s ? `${s.presentToday} / ${s.onLeaveToday}` : '…'}</b></div>
        <Link className="kpi clickable-kpi" to="/hr/leaves"><span className="muted small">Đơn nghỉ chờ duyệt</span><b className={s?.pendingLeaves ? 'warn-text' : ''}>{s?.pendingLeaves ?? '…'}</b></Link>
        <div className="kpi"><span className="muted small">Quỹ lương / tháng (HĐ)</span><b>{s ? formatMoney(s.monthlySalaryFund) : '…'}</b></div>
      </div>
      <div className="toolbar">
        <div className="search"><i className="ti ti-search" aria-hidden="true" /><input placeholder="Tìm tên, mã, SĐT" value={filters.search} onChange={(e) => setFilter('search', e.target.value)} aria-label="Tìm nhân viên" /></div>
        <select value={filters.departmentId} onChange={(e) => setFilter('departmentId', e.target.value)} aria-label="Phòng ban"><option value="">Mọi phòng ban</option>{lookups.departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}</select>
        <select value={filters.status} onChange={(e) => setFilter('status', e.target.value)} aria-label="Trạng thái">
          <option value="working">Đang làm việc</option><option value="all">Tất cả</option>
          {EMPLOYMENT_STATUSES.map((x) => <option key={x.value} value={x.value}>{x.label}</option>)}
        </select>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Nhân viên</th><th className="hide-sm">Phòng ban / chức danh</th><th className="hide-sm">Vào làm</th><th className="num">Lương HĐ</th><th>Trạng thái</th></tr></thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.rows.items.length === 0 && <tr><td colSpan={5} className="muted center">Chưa có nhân viên.</td></tr>}
            {data?.rows.items.map((e) => (
              <tr key={e.id} className="clickable" onClick={() => open(e.id)}>
                <td><b>{e.fullName}</b><div className="muted small">{e.code}{e.phone ? ` · ${e.phone}` : ''}{e.userName ? ` · TK ${e.userName}` : ''}</div></td>
                <td className="hide-sm">{e.departmentName}<div className="muted small">{e.positionName}</div></td>
                <td className="hide-sm">{formatDateOnly(e.hireDate)}</td>
                <td className="num">{formatMoney(e.baseSalary)}</td>
                <td><span className={`pill ${employmentStatus(e.status).css}`}>{employmentStatus(e.status).label}</span>
                  {e.todayStatus && <div className={`small ${attStatus(e.todayStatus).css}`}>Hôm nay: {attStatus(e.todayStatus).label}</div>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data?.rows} unit="nhân viên" onPageChange={setPage} />
      {editing && (
        <EmployeeFormModal employee={editing === 'new' ? null : editing} lookups={lookups} onClose={() => setEditing(null)}
          onSaved={(e, isNew) => { setEditing(null); setMessage(isNew ? `Đã thêm ${e.fullName} (${e.code}).` : `Đã lưu ${e.fullName}.`); load() }} />
      )}
    </HrLayout>
  )
}

/** Bảng chấm công tháng: bấm ô để sửa; check-in / check-out nhanh cho hôm nay; chấm đủ công. */
export function AttendancePage() {
  const { can } = useAuth()
  const now = new Date()
  const [ym, setYm] = useState({ year: now.getFullYear(), month: now.getMonth() + 1 })
  const [data, setData] = useState(null)
  const [cell, setCell] = useState(null)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const canEdit = can(PHASE3_PERMISSIONS.HR_EDIT)
  const isCurrent = ym.year === now.getFullYear() && ym.month === now.getMonth() + 1
  const today = now.getDate()

  const load = useCallback(() => hrApi.attendance(ym).then(setData).catch((e) => setError(getErrorMessage(e))), [ym])
  useEffect(() => { load() }, [load])
  const shift = (d) => { const m = ym.month + d; setYm(m < 1 ? { year: ym.year - 1, month: 12 } : m > 12 ? { year: ym.year + 1, month: 1 } : { ...ym, month: m }) }

  const fill = async () => {
    if (!window.confirm('Chấm đủ 8 giờ cho các ngày làm việc còn trống (trừ Chủ nhật) từ đầu tháng đến hôm nay?')) return
    try { const r = await hrApi.fillAttendance(ym.year, ym.month); setMessage(`Đã chấm ${r.filled} ngày công.`); load() } catch (e) { setError(getErrorMessage(e)) }
  }
  const check = async (emp, action) => {
    try { await hrApi.check(emp.employeeId, action); setMessage(`${emp.fullName} đã ${action === 'in' ? 'check-in' : 'check-out'}.`); load() } catch (e) { setError(getErrorMessage(e)) }
  }

  return (
    <HrLayout>
      <div className="page-head">
        <h1>Chấm công</h1>
        <div className="head-actions">
          <button className="btn" onClick={() => shift(-1)} aria-label="Tháng trước"><i className="ti ti-chevron-left" aria-hidden="true" /></button>
          <b className="period-label">Tháng {ym.month}/{ym.year}</b>
          <button className="btn" onClick={() => shift(1)} aria-label="Tháng sau"><i className="ti ti-chevron-right" aria-hidden="true" /></button>
          {canEdit && <button className="btn" onClick={fill}><i className="ti ti-checks" aria-hidden="true" /> Chấm đủ công</button>}
        </div>
      </div>
      {message && <div className="alert success">{message}</div>}
      {error && <div className="alert error">{error}</div>}

      {isCurrent && canEdit && data && (
        <>
          <div className="section-head first"><h2>Hôm nay</h2></div>
          <div className="check-panel">
            {data.rows.map((r) => {
              const c = r.cells[today]
              return (
                <div key={r.employeeId} className="check-card">
                  <div><b className="small">{r.fullName}</b>
                    <div className="muted small">{c?.checkIn ? `Vào ${hhmm(c.checkIn)}` : c ? attStatus(c.status).label : 'Chưa chấm'}{c?.checkOut ? ` · Ra ${hhmm(c.checkOut)}` : ''}{c?.lateMinutes ? ` · trễ ${c.lateMinutes}'` : ''}</div></div>
                  {!c?.checkIn && c?.status !== 'leave' && <button className="btn primary" onClick={() => check(r, 'in')}>Vào ca</button>}
                  {c?.checkIn && !c?.checkOut && <button className="btn" onClick={() => check(r, 'out')}>Ra ca</button>}
                </div>
              )
            })}
          </div>
        </>
      )}

      <div className="legend-row">
        {ATTENDANCE_STATUSES.map((s) => <span key={s.value}><b className={s.css}>{s.short}</b> {s.label}</span>)}
        <span><b className="att-present">½</b> Nửa ngày</span><span>● đi trễ</span>
      </div>
      {!data ? <p className="muted">Đang tải...</p> : (
        <div className="att-wrap">
          <table className="att">
            <thead>
              <tr>
                <th className="name">Nhân viên</th>
                {Array.from({ length: data.daysInMonth }, (_, i) => i + 1).map((d) => (
                  <th key={d} className={`${data.sundays.includes(d) ? 'sun' : ''} ${isCurrent && d === today ? 'today' : ''}`}>{d}</th>
                ))}
                <th>Công</th><th>Phép</th><th>Tăng ca</th>
              </tr>
            </thead>
            <tbody>
              {data.rows.map((r) => (
                <tr key={r.employeeId}>
                  <td className="name"><b>{r.fullName}</b> <span className="muted">{r.code}</span></td>
                  {Array.from({ length: data.daysInMonth }, (_, i) => i + 1).map((d) => {
                    const c = r.cells[d]
                    const s = c ? attStatus(c.status) : null
                    const future = isCurrent && d > today
                    return (
                      <td key={d} className={`${data.sundays.includes(d) ? 'sun' : ''} ${s?.css ?? ''} ${c?.lateMinutes ? 'late' : ''}`}>
                        <button className="cell" disabled={!canEdit || future} title={c ? `${s.label}${c.workHours ? ` · ${c.workHours} giờ` : ''}${c.overtimeHours ? ` · tăng ca ${c.overtimeHours}h` : ''}${c.note ? ` · ${c.note}` : ''}` : 'Chưa chấm'}
                          onClick={() => setCell({ row: r, day: d, c })}>
                          {c ? (c.status === 'present' && c.workDays === 0.5 ? '½' : s.short) : ''}
                        </button>
                      </td>
                    )
                  })}
                  <td className="total">{formatQty(r.workDays)}</td>
                  <td className="total">{formatQty(r.leaveDays)}</td>
                  <td className="total">{r.overtimeHours ? `${formatQty(r.overtimeHours)}h` : ''}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {cell && <AttendanceModal ym={ym} cell={cell} onClose={() => setCell(null)} onSaved={() => { setCell(null); load() }} />}
    </HrLayout>
  )
}

function AttendanceModal({ ym, cell, onClose, onSaved }) {
  const [form, setForm] = useState({ status: cell.c?.status ?? 'present', workHours: cell.c?.workHours || 8, overtimeHours: cell.c?.overtimeHours ?? 0, note: cell.c?.note ?? '' })
  const [error, setError] = useState('')
  const date = `${ym.year}-${String(ym.month).padStart(2, '0')}-${String(cell.day).padStart(2, '0')}`
  const save = async () => {
    try {
      await hrApi.setAttendance({ employeeId: cell.row.employeeId, date, status: form.status, workHours: Number(form.workHours) || 0, overtimeHours: Number(form.overtimeHours) || 0, note: form.note || null })
      onSaved()
    } catch (e) { setError(getErrorMessage(e)) }
  }
  return (
    <Modal title={`${cell.row.fullName} - ${formatDateOnly(date)}`} onClose={onClose} size="small">
      <div className="segmented" role="radiogroup">
        {ATTENDANCE_STATUSES.map((s) => <button key={s.value} type="button" className={form.status === s.value ? 'on' : ''} onClick={() => setForm({ ...form, status: s.value })}>{s.label}</button>)}
      </div>
      {form.status === 'present' && (
        <div className="form-grid">
          <label>Số giờ làm<input type="number" step="0.5" min="0" max="12" value={form.workHours} onChange={(e) => setForm({ ...form, workHours: e.target.value })} /><span className="hint-inline">8 = 1 công, 4 = nửa công</span></label>
          <label>Giờ tăng ca<input type="number" step="0.5" min="0" max="12" value={form.overtimeHours} onChange={(e) => setForm({ ...form, overtimeHours: e.target.value })} /></label>
        </div>
      )}
      <label>Ghi chú<input value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></label>
      {cell.c?.checkIn && <p className="hint-inline">Vào ca {hhmm(cell.c.checkIn)}{cell.c.checkOut ? ` · ra ca ${hhmm(cell.c.checkOut)}` : ''}{cell.c.lateMinutes ? ` · trễ ${cell.c.lateMinutes} phút` : ''}</p>}
      {error && <p className="error">{error}</p>}
      <div className="modal-foot"><button className="btn" onClick={onClose}>Hủy</button><button className="btn primary" onClick={save}>Lưu</button></div>
    </Modal>
  )
}

/** Đơn nghỉ phép: tạo, duyệt / từ chối, quỹ phép năm của từng người. */
export function LeavesPage() {
  const { can } = useAuth()
  const lookups = useHrLookups()
  const [data, setData] = useState(null)
  const [status, setStatus] = useState('')
  const [page, setPage] = useState(1)
  const [creating, setCreating] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const load = useCallback(() => hrApi.leaves({ status, page, pageSize: 20 }).then(setData).catch((e) => setError(getErrorMessage(e))), [status, page])
  useEffect(() => { load() }, [load])

  const act = async (fn, msg) => { setError(''); try { await fn(); setMessage(msg); load() } catch (e) { setError(getErrorMessage(e)) } }

  return (
    <HrLayout>
      <div className="page-head">
        <h1>Nghỉ phép</h1>
        {can(PHASE3_PERMISSIONS.HR_CREATE) && <button className="btn primary" onClick={() => setCreating(true)}><i className="ti ti-plus" aria-hidden="true" /> Tạo đơn nghỉ</button>}
      </div>
      {message && <div className="alert success">{message}</div>}
      {error && <div className="alert error">{error}</div>}
      <div className="toolbar">
        <div className="segmented no-margin">
          {[['', 'Tất cả'], ['submitted', 'Chờ duyệt'], ['approved', 'Đã duyệt'], ['rejected', 'Từ chối']].map(([v, l]) => <button key={v} className={status === v ? 'on' : ''} onClick={() => { setStatus(v); setPage(1) }}>{l}</button>)}
        </div>
      </div>
      <div className="order-grid">
        <div>
          <div className="table-wrap">
            <table className="grid">
              <thead><tr><th>Nhân viên</th><th>Thời gian</th><th className="num">Ngày</th><th>Trạng thái</th><th className="actions" /></tr></thead>
              <tbody>
                {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
                {data?.rows.items.length === 0 && <tr><td colSpan={5} className="muted center">Không có đơn nào.</td></tr>}
                {data?.rows.items.map((l) => (
                  <tr key={l.id}>
                    <td><b>{l.employeeName}</b><div className="muted small">{l.typeName}{l.reason ? ` · ${l.reason}` : ''}</div></td>
                    <td>{formatDateOnly(l.fromDate)}{l.toDate !== l.fromDate ? ` → ${formatDateOnly(l.toDate)}` : ''}</td>
                    <td className="num">{formatQty(l.days)}</td>
                    <td><span className={`pill ${LEAVE_CSS[l.status]}`}>{LEAVE_STATUSES[l.status]}</span>
                      {l.approverName && <div className="muted small">{l.approverName}{l.rejectReason ? `: ${l.rejectReason}` : ''}</div>}</td>
                    <td className="actions">
                      {l.status === 'submitted' && can(PHASE3_PERMISSIONS.HR_APPROVE) && (
                        <>
                          <button className="btn primary" onClick={() => act(() => hrApi.approveLeave(l.id), `Đã duyệt đơn của ${l.employeeName}, chấm công đã cập nhật.`)}>Duyệt</button>{' '}
                          <button className="btn ghost danger" onClick={() => { const r = window.prompt('Lý do từ chối'); if (r?.trim()) act(() => hrApi.rejectLeave(l.id, r.trim()), 'Đã từ chối đơn.') }}>Từ chối</button>
                        </>
                      )}
                      {['submitted', 'approved'].includes(l.status) && can(PHASE3_PERMISSIONS.HR_EDIT) && (
                        <button className="btn ghost" title="Hủy đơn" aria-label="Hủy đơn" onClick={() => window.confirm('Hủy đơn nghỉ này?') && act(() => hrApi.cancelLeave(l.id), 'Đã hủy đơn, trả lại ngày phép.')}><i className="ti ti-x" aria-hidden="true" /></button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination data={data?.rows} unit="đơn" onPageChange={setPage} />
        </div>
        <aside className="card">
          <div className="section-head first"><h2>Quỹ phép năm {new Date().getFullYear()}</h2></div>
          <table className="grid compact">
            <thead><tr><th>Nhân viên</th><th className="num">Đã nghỉ</th><th className="num">Còn</th></tr></thead>
            <tbody>
              {data?.balances.map((b) => <tr key={b.employeeId}><td>{b.fullName}</td><td className="num">{formatQty(b.used)}</td><td className="num"><b className={b.remaining <= 2 ? 'warn-text' : ''}>{formatQty(b.remaining)}</b></td></tr>)}
            </tbody>
          </table>
          <p />
        </aside>
      </div>
      {creating && <LeaveModal lookups={lookups} onClose={() => setCreating(false)} onSaved={() => { setCreating(false); setMessage('Đã gửi đơn nghỉ, chờ duyệt.'); load() }} />}
    </HrLayout>
  )
}

function LeaveModal({ lookups, onClose, onSaved }) {
  const [form, setForm] = useState({ employeeId: '', leaveTypeId: lookups.leaveTypes[0]?.id ?? '', fromDate: todayIso(), toDate: todayIso(), halfDay: false, reason: '' })
  const [error, setError] = useState('')
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.type === 'checkbox' ? e.target.checked : e.target.value })
  const save = async () => {
    if (!form.employeeId) return setError('Chọn nhân viên.')
    try { await hrApi.createLeave({ ...form, employeeId: Number(form.employeeId), leaveTypeId: Number(form.leaveTypeId), reason: form.reason || null }); onSaved() } catch (e) { setError(getErrorMessage(e)) }
  }
  return (
    <Modal title="Tạo đơn nghỉ" onClose={onClose} size="small">
      <label>Nhân viên *<select value={form.employeeId} onChange={u('employeeId')} autoFocus><option value="">Chọn nhân viên</option>{lookups.employees.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}</select></label>
      <label>Loại nghỉ<select value={form.leaveTypeId} onChange={u('leaveTypeId')}>{lookups.leaveTypes.map((t) => <option key={t.id} value={t.id}>{t.name}{t.isPaid ? '' : ' (không lương)'}</option>)}</select></label>
      <div className="form-grid">
        <label>Từ ngày<input type="date" value={form.fromDate} onChange={(e) => setForm({ ...form, fromDate: e.target.value, toDate: e.target.value > form.toDate ? e.target.value : form.toDate })} /></label>
        <label>Đến ngày<input type="date" value={form.toDate} min={form.fromDate} onChange={u('toDate')} /></label>
      </div>
      {form.fromDate === form.toDate && <label className="check"><input type="checkbox" checked={form.halfDay} onChange={u('halfDay')} /> Chỉ nghỉ nửa ngày</label>}
      <label>Lý do<input value={form.reason} onChange={u('reason')} /></label>
      {error && <p className="error">{error}</p>}
      <div className="modal-foot"><button className="btn" onClick={onClose}>Hủy</button><button className="btn primary" onClick={save}>Gửi đơn</button></div>
    </Modal>
  )
}

/** Danh sách bảng lương các tháng. */
export function PayrollListPage() {
  const { can } = useAuth()
  const navigate = useNavigate()
  const [list, setList] = useState(null)
  const [error, setError] = useState('')
  useEffect(() => { hrApi.payrolls().then(setList).catch((e) => setError(getErrorMessage(e))) }, [])

  const create = async () => {
    const d = new Date()
    const def = `${d.getMonth() + 1}/${d.getFullYear()}`
    const v = window.prompt('Lập bảng lương tháng (tháng/năm):', def)
    if (!v) return
    const [m, y] = v.split('/').map((x) => Number(x.trim()))
    try { const p = await hrApi.createPayroll(y, m, 26); navigate(`/hr/payroll/${p.id}`) } catch (e) { setError(getErrorMessage(e)) }
  }

  return (
    <HrLayout>
      <div className="page-head">
        <h1>Bảng lương</h1>
        {can(PHASE3_PERMISSIONS.HR_CREATE) && <button className="btn primary" onClick={create}><i className="ti ti-plus" aria-hidden="true" /> Lập bảng lương</button>}
      </div>
      <p className="muted page-intro">Lương tự tính từ chấm công, nghỉ phép có lương và hợp đồng. Bảo hiểm NLĐ 10,5%, thuế TNCN lũy tiến sau giảm trừ gia cảnh.</p>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Tháng</th><th className="num">Nhân viên</th><th className="num">Tổng thu nhập</th><th className="num hide-sm">BH + thuế</th><th className="num">Thực lĩnh</th><th>Trạng thái</th></tr></thead>
          <tbody>
            {!list && <tr><td colSpan={6} className="muted center">Đang tải...</td></tr>}
            {list?.length === 0 && <tr><td colSpan={6} className="muted center">Chưa có bảng lương. Bấm "Lập bảng lương".</td></tr>}
            {list?.map((p) => (
              <tr key={p.id} className="clickable" onClick={() => navigate(`/hr/payroll/${p.id}`)}>
                <td><Link to={`/hr/payroll/${p.id}`} onClick={(e) => e.stopPropagation()}>Tháng {p.month}/{p.year}</Link><div className="muted small">Công chuẩn {formatQty(p.standardDays)}</div></td>
                <td className="num">{p.employeeCount}</td>
                <td className="num">{formatMoney(p.totalGross)}</td>
                <td className="num hide-sm muted">{formatMoney(p.totalInsurance + p.totalTax)}</td>
                <td className="num"><b>{formatMoney(p.totalNet)}</b></td>
                <td><span className={`pill ${PAYROLL_CSS[p.status]}`}>{PAYROLL_STATUSES[p.status]}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </HrLayout>
  )
}

/** Chi tiết bảng lương: từng phiếu lương, sửa thưởng / tạm ứng, tính lại, duyệt, chi lương. */
export function PayrollDetailPage() {
  const { id } = useParams()
  const { can } = useAuth()
  const [p, setP] = useState(null)
  const [banks, setBanks] = useState([])
  const [editing, setEditing] = useState(null)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  useEffect(() => { hrApi.payroll(id).then(setP).catch((e) => setError(getErrorMessage(e))) }, [id])
  useEffect(() => { accountingApi.lookups().then((l) => setBanks(l.bankAccounts.filter((b) => b.isActive))).catch(() => {}) }, [])

  const act = async (fn, msg) => { setBusy(true); setError(''); try { setP(await fn()); setMessage(msg) } catch (e) { setError(getErrorMessage(e)) } finally { setBusy(false) } }
  if (!p) return <HrLayout>{error ? <div className="alert error">{error}</div> : <p className="muted">Đang tải...</p>}</HrLayout>
  const editable = ['draft', 'calculated'].includes(p.status) && can(PHASE3_PERMISSIONS.HR_EDIT)

  return (
    <HrLayout>
      <div className="breadcrumb"><Link to="/hr/payroll">Bảng lương</Link> / Tháng {p.month}/{p.year}</div>
      <div className="page-head">
        <h1>Bảng lương tháng {p.month}/{p.year} <span className={`pill ${PAYROLL_CSS[p.status]} small-pill`}>{PAYROLL_STATUSES[p.status]}</span></h1>
        <div className="head-actions">
          {editable && <button className="btn" disabled={busy} onClick={() => { const v = window.prompt('Số công chuẩn của tháng:', p.standardDays); if (v) act(() => hrApi.recalculate(p.id, Number(v)), 'Đã tính lại theo chấm công mới nhất.') }}>
            <i className="ti ti-refresh" aria-hidden="true" /> Tính lại</button>}
          {editable && can(PHASE3_PERMISSIONS.HR_APPROVE) && <button className="btn primary" disabled={busy} onClick={() => act(() => hrApi.approvePayroll(p.id), 'Đã duyệt bảng lương.')}>Duyệt bảng lương</button>}
          {p.status === 'approved' && can(PHASE3_PERMISSIONS.HR_APPROVE) && (
            <>
              <button className="btn" disabled={busy} onClick={() => act(() => hrApi.reopenPayroll(p.id), 'Đã mở lại để sửa.')}>Mở lại</button>
              <button className="btn primary" disabled={busy} onClick={() => window.confirm(`Chi lương ${formatMoney(p.totalNet)} qua ${banks[0]?.bankName ?? 'ngân hàng'}? Hệ thống tạo phiếu chi bên Kế toán.`) && act(() => hrApi.payPayroll(p.id, banks[0]?.id ?? null), 'Đã chi lương và ghi phiếu chi.')}>
                <i className="ti ti-cash" aria-hidden="true" /> Chi lương</button>
            </>
          )}
        </div>
      </div>
      {message && <div className="alert success">{message}</div>}
      {error && <div className="alert error">{error}</div>}
      {p.voucherDocNo && <div className="alert info"><i className="ti ti-receipt" aria-hidden="true" /> Đã chi lương - phiếu chi <Link to="/accounting/vouchers">{p.voucherDocNo}</Link></div>}
      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Tổng thu nhập</span><b>{formatMoney(p.totalGross)}</b></div>
        <div className="kpi"><span className="muted small">BH người lao động / thuế TNCN</span><b>{formatMoney(p.totalInsurance)}</b><span className="small muted">Thuế: {formatMoney(p.totalTax)}</span></div>
        <div className="kpi"><span className="muted small">Thực lĩnh (chi trả)</span><b className="ok-text">{formatMoney(p.totalNet)}</b></div>
        <div className="kpi"><span className="muted small">BH công ty đóng (21,5%)</span><b>{formatMoney(p.totalEmployerInsurance)}</b></div>
      </div>
      <div className="table-wrap">
        <table className="grid payroll-grid">
          <thead><tr><th>Nhân viên</th><th className="num">Công</th><th className="num">Lương HĐ</th><th className="num">Lương theo công</th><th className="num hide-sm">Phụ cấp</th>
            <th className="num hide-sm">Tăng ca</th><th className="num">Thưởng</th><th className="num hide-sm">BH</th><th className="num hide-sm">Thuế</th><th className="num hide-sm">Tạm ứng</th><th className="num">Thực lĩnh</th></tr></thead>
          <tbody>
            {p.payslips.length === 0 && <tr><td colSpan={11} className="muted center">Chưa có nhân viên nào có hợp đồng / lương.</td></tr>}
            {p.payslips.map((s) => (
              <tr key={s.id} className={editable ? 'clickable' : ''} onClick={() => editable && setEditing(s)}>
                <td><b>{s.fullName}</b><div className="muted small">{s.code}{s.departmentName ? ` · ${s.departmentName}` : ''}</div></td>
                <td className="num">{formatQty(s.actualDays)}{s.paidLeaveDays ? <div className="muted small">+{formatQty(s.paidLeaveDays)} phép</div> : null}</td>
                <td className="num muted">{formatMoney(s.contractSalary)}</td>
                <td className="num">{formatMoney(s.baseSalary)}</td>
                <td className="num hide-sm">{formatMoney(s.totalAllowance)}</td>
                <td className="num hide-sm">{s.overtimePay ? formatMoney(s.overtimePay) : ''}{s.overtimeHours ? <div className="muted small">{formatQty(s.overtimeHours)}h</div> : null}</td>
                <td className="num">{s.bonus ? formatMoney(s.bonus) : ''}</td>
                <td className="num hide-sm money-out">{formatMoney(s.insurance)}</td>
                <td className="num hide-sm money-out">{s.personalIncomeTax ? formatMoney(s.personalIncomeTax) : ''}</td>
                <td className="num hide-sm money-out">{s.advance ? formatMoney(s.advance) : ''}</td>
                <td className="num"><b>{formatMoney(s.netPay)}</b></td>
              </tr>
            ))}
            <tr className="total-row"><td><b>Cộng</b></td><td colSpan={9} /><td className="num"><b>{formatMoney(p.totalNet)}</b></td></tr>
          </tbody>
        </table>
      </div>
      {editable && <p className="hint-inline top-gap">Bấm vào từng dòng để nhập thưởng, tạm ứng, khấu trừ khác. Sửa chấm công xong bấm "Tính lại".</p>}
      {editing && <PayslipModal payroll={p} slip={editing} onClose={() => setEditing(null)} onSaved={(r) => { setP(r); setEditing(null) }} />}
    </HrLayout>
  )
}

function PayslipModal({ payroll, slip, onClose, onSaved }) {
  const [form, setForm] = useState({ bonus: slip.bonus, advance: slip.advance, otherDeductions: slip.otherDeductions })
  const [error, setError] = useState('')
  const save = async () => { try { onSaved(await hrApi.updatePayslip(payroll.id, slip.id, form)) } catch (e) { setError(getErrorMessage(e)) } }
  return (
    <Modal title={`Phiếu lương ${slip.fullName}`} onClose={onClose} size="small">
      <label>Thưởng<MoneyInput value={form.bonus} onChange={(v) => setForm({ ...form, bonus: v })} autoFocus /></label>
      <label>Tạm ứng đã nhận<MoneyInput value={form.advance} onChange={(v) => setForm({ ...form, advance: v })} /></label>
      <label>Khấu trừ khác<MoneyInput value={form.otherDeductions} onChange={(v) => setForm({ ...form, otherDeductions: v })} /></label>
      <p className="hint-inline">Thu nhập chịu thuế hiện tại: {formatMoney(slip.taxableIncome)}</p>
      {error && <p className="error">{error}</p>}
      <div className="modal-foot"><button className="btn" onClick={onClose}>Hủy</button><button className="btn primary" onClick={save}>Lưu & tính lại</button></div>
    </Modal>
  )
}
