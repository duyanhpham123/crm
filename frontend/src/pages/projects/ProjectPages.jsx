import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { projectApi } from '../../api/phase4Api'
import CustomerPicker from '../../components/CustomerPicker'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import Pagination from '../../components/Pagination'
import { PHASE4_PERMISSIONS, PROJECT_STATUSES, projectStatus, TASK_PRIORITIES, taskPriority } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import ModuleLayout from '../../layouts/ModuleLayout'
import { formatDateOnly, formatDateTime, formatMoney, formatMoneyShort, formatQty, initials, todayIso } from '../../utils/format'

const MENU = [
  { to: '/projects', icon: 'layout-kanban', label: 'Công việc', end: true },
  { to: '/projects/list', icon: 'briefcase', label: 'Dự án' },
]

function ProjectsLayout({ children }) {
  return <ModuleLayout title="Dự án, việc" icon="checklist" color="#993556" menu={MENU}>{children}</ModuleLayout>
}

function useProjectLookups() {
  const [l, setL] = useState({ users: [], departments: [], stages: [], projects: [], currentUserId: 0 })
  const reload = useCallback(() => projectApi.lookups().then(setL).catch(() => {}), [])
  useEffect(() => { reload() }, [reload])
  return [l, reload]
}

function Progress({ value, late }) {
  const v = Math.round(Number(value) || 0)
  return (
    <div className="progress-cell" title={`${v}%`}>
      <div className="hbar-track"><div className="hbar-fill" style={{ width: `${v}%`, background: late ? 'var(--danger)' : v >= 100 ? 'var(--success)' : undefined }} /></div>
      <span className="small muted">{v}%</span>
    </div>
  )
}

function PriorityTag({ value }) {
  const p = taskPriority(value)
  if (value === 'normal') return null
  return <span className={`pill ${p.css} small-pill`} title={`Ưu tiên: ${p.label}`}><i className={`ti ti-${p.icon}`} aria-hidden="true" /> {p.label}</span>
}

// ===================== Bảng Kanban công việc =====================

function TaskBoardView({ filters, lookups, onOpen, reloadKey, canMove }) {
  const [board, setBoard] = useState(null)
  const [error, setError] = useState('')
  const [dragging, setDragging] = useState(null)
  const [dropTarget, setDropTarget] = useState(null)
  const load = useCallback(() => projectApi.board(filters).then(setBoard).catch((e) => setError(getErrorMessage(e))), [filters])
  useEffect(() => { load() }, [load, reloadKey])

  const onDrop = async (stage) => {
    setDropTarget(null)
    const card = dragging
    setDragging(null)
    if (!card || card.stageId === stage.id) return
    setBoard((b) => ({ ...b, tasks: b.tasks.map((t) => (t.id === card.id ? { ...t, stageId: stage.id, isDone: stage.isDone } : t)) }))
    try { await projectApi.moveTask(card.id, stage.id) } catch (err) { setError(getErrorMessage(err)) }
    load()
  }

  if (!board) return error ? <div className="alert error">{error}</div> : <p className="muted">Đang tải...</p>
  return (
    <>
      {error && <div className="alert error">{error}</div>}
      {board.truncated && <div className="alert">Đang hiện {board.tasks.length}/{board.total} việc. Lọc theo dự án hoặc người nhận để xem đủ.</div>}
      <div className="kanban">
        {board.stages.map((stage) => {
          const items = board.tasks.filter((t) => t.stageId === stage.id)
          return (
            <section key={stage.id} className={`kanban-col${stage.isDone ? ' won' : ''}${dropTarget === stage.id ? ' drop' : ''}`}
              onDragOver={(e) => { if (dragging) { e.preventDefault(); setDropTarget(stage.id) } }}
              onDragLeave={() => setDropTarget((t) => (t === stage.id ? null : t))}
              onDrop={() => onDrop(stage)} aria-label={`Cột ${stage.name}`}>
              <header><div className="kanban-title"><span>{stage.name}</span><span className="count">{items.length}</span></div></header>
              <div className="kanban-items">
                {items.map((t) => (
                  <article key={t.id} className={`kanban-card task-card${dragging?.id === t.id ? ' dragging' : ''}${t.isDone ? ' done' : ''}`}
                    draggable={canMove} onDragStart={(e) => { e.dataTransfer.effectAllowed = 'move'; setDragging(t) }}
                    onDragEnd={() => { setDragging(null); setDropTarget(null) }}
                    onClick={() => onOpen(t.id)} tabIndex={0} onKeyDown={(e) => e.key === 'Enter' && onOpen(t.id)}>
                    <div className="card-title">{t.title}</div>
                    {(t.projectName || t.departmentName) && <div className="muted small">{t.projectName ?? t.departmentName}</div>}
                    {t.checklistTotal > 0 && !t.isDone && (
                      <div className="task-progress"><div className="hbar-track"><div className="hbar-fill" style={{ width: `${t.progressPercent}%` }} /></div>
                        <span className="small muted"><i className="ti ti-checkbox" aria-hidden="true" /> {t.checklistDone}/{t.checklistTotal}</span></div>
                    )}
                    <div className="card-meta">
                      <PriorityTag value={t.priority} />
                      <span className="spacer" />
                      {t.dueDate && <span className={`small ${t.isOverdue ? 'overdue' : 'muted'}`} title={t.isOverdue ? 'Quá hạn' : 'Hạn chót'}>
                        <i className="ti ti-calendar" aria-hidden="true" /> {formatDateOnly(t.dueDate)}</span>}
                      {t.assigneeName ? <span className="avatar tiny" title={t.assigneeName}>{initials(t.assigneeName)}</span>
                        : <span className="avatar tiny empty" title="Chưa giao cho ai"><i className="ti ti-user-question" aria-hidden="true" /></span>}
                    </div>
                  </article>
                ))}
                {items.length === 0 && <div className="kanban-empty muted small">{canMove ? 'Kéo việc vào đây' : 'Trống'}</div>}
              </div>
            </section>
          )
        })}
      </div>
    </>
  )
}

function TaskListView({ filters, onOpen, reloadKey }) {
  const [board, setBoard] = useState(null)
  useEffect(() => { projectApi.board(filters).then(setBoard).catch(() => setBoard({ stages: [], tasks: [] })) }, [filters, reloadKey])
  const stageName = (id) => board?.stages.find((s) => s.id === id)?.name ?? ''
  return (
    <div className="table-wrap">
      <table className="grid">
        <thead><tr><th>Công việc</th><th className="hide-sm">Người nhận</th><th>Hạn chót</th><th className="hide-sm">Tiến độ</th><th>Cột</th></tr></thead>
        <tbody>
          {!board && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
          {board?.tasks.length === 0 && <tr><td colSpan={5} className="muted center">Không có công việc.</td></tr>}
          {board?.tasks.map((t) => (
            <tr key={t.id} className="clickable" onClick={() => onOpen(t.id)}>
              <td><b className={t.isDone ? 'strike' : ''}>{t.title}</b> <PriorityTag value={t.priority} />
                <div className="muted small">{t.code}{t.projectName ? ` · ${t.projectName}` : t.departmentName ? ` · ${t.departmentName}` : ''}</div></td>
              <td className="hide-sm">{t.assigneeName ?? <span className="muted">Chưa giao</span>}</td>
              <td className={t.isOverdue ? 'overdue' : ''}>{t.dueDate ? formatDateOnly(t.dueDate) : '-'}</td>
              <td className="hide-sm"><Progress value={t.progressPercent} /></td>
              <td><span className={`pill ${t.isDone ? 'completed' : 'draft'}`}>{stageName(t.stageId)}</span></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

// ===================== Hộp thoại công việc =====================

const emptyTask = (defaults) => ({
  title: '', description: '', projectId: defaults?.projectId ?? '', priority: 'normal', assigneeUserId: defaults?.assigneeUserId ?? '',
  departmentId: '', startDate: '', dueDate: '', estimatedHours: '', stageId: defaults?.stageId ?? '',
})

function TaskModal({ taskId, defaults, lookups, onClose, onChanged }) {
  const { can } = useAuth()
  const [task, setTask] = useState(null)
  const [form, setForm] = useState(emptyTask(defaults))
  const [editing, setEditing] = useState(!taskId)
  const [newItem, setNewItem] = useState('')
  const [log, setLog] = useState({ date: todayIso(), hours: '', note: '' })
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const canEdit = can(PHASE4_PERMISSIONS.PROJECT_EDIT)

  const fill = (t) => {
    setTask(t)
    setForm({ title: t.title, description: t.description ?? '', projectId: t.projectId ?? '', priority: t.priority, assigneeUserId: t.assigneeUserId ?? '',
      departmentId: t.departmentId ?? '', startDate: t.startDate ?? '', dueDate: t.dueDate ?? '', estimatedHours: t.estimatedHours ?? '', stageId: t.stageId ?? '' })
  }
  useEffect(() => { if (taskId) projectApi.task(taskId).then(fill).catch((e) => setError(getErrorMessage(e))) }, [taskId])

  const run = async (fn) => {
    setError(''); setBusy(true)
    try { const t = await fn(); if (t) fill(t); onChanged?.() } catch (err) { setError(getErrorMessage(err)) } finally { setBusy(false) }
  }
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })
  const body = () => ({
    title: form.title, description: form.description || null, projectId: form.projectId ? Number(form.projectId) : null, priority: form.priority,
    assigneeUserId: form.assigneeUserId ? Number(form.assigneeUserId) : null, departmentId: form.departmentId ? Number(form.departmentId) : null,
    startDate: form.startDate || null, dueDate: form.dueDate || null, estimatedHours: form.estimatedHours === '' ? null : Number(form.estimatedHours),
    stageId: form.stageId ? Number(form.stageId) : null, rowVersion: task?.rowVersion ?? null,
  })
  const save = (e) => {
    e.preventDefault()
    run(async () => {
      const t = task ? await projectApi.updateTask(task.id, body()) : await projectApi.createTask(body())
      setEditing(false)
      return t
    })
  }
  const remove = () => {
    if (!window.confirm(`Xóa công việc "${task.title}"?`)) return
    run(async () => { await projectApi.deleteTask(task.id); onClose() })
  }

  const fields = (
    <form onSubmit={save}>
      <div className="form-grid">
        <label className="span2">Tên công việc *<input value={form.title} onChange={u('title')} autoFocus maxLength={255} placeholder="VD: Chụp ảnh BST mới cho website" /></label>
        <label>Dự án<select value={form.projectId} onChange={u('projectId')}><option value="">— Không thuộc dự án —</option>
          {lookups.projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>
        <label>Người nhận việc<select value={form.assigneeUserId} onChange={u('assigneeUserId')}><option value="">— Chưa giao —</option>
          {lookups.users.map((x) => <option key={x.id} value={x.id}>{x.name}{x.description ? ` (${x.description})` : ''}</option>)}</select></label>
        <label>Phòng ban phụ trách<select value={form.departmentId} onChange={u('departmentId')}><option value="">—</option>
          {lookups.departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}</select></label>
        <label>Mức ưu tiên<select value={form.priority} onChange={u('priority')}>{TASK_PRIORITIES.map((p) => <option key={p.value} value={p.value}>{p.label}</option>)}</select></label>
        <label>Bắt đầu<input type="date" value={form.startDate} onChange={u('startDate')} /></label>
        <label>Hạn chót<input type="date" value={form.dueDate} onChange={u('dueDate')} /></label>
        <label>Giờ dự kiến<input type="number" min="0" step="0.5" value={form.estimatedHours} onChange={u('estimatedHours')} /></label>
        {!task && <label>Cột<select value={form.stageId} onChange={u('stageId')}>{lookups.stages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>}
        <label className="span2">Mô tả<textarea rows={3} value={form.description} onChange={u('description')} /></label>
      </div>
      {error && <p className="error">{error}</p>}
      <div className="modal-foot">
        <button type="button" className="btn" onClick={() => (task ? setEditing(false) : onClose())}>Hủy</button>
        <button className="btn primary" disabled={busy}>{task ? 'Lưu' : 'Giao việc'}</button>
      </div>
    </form>
  )

  if (!task) return <Modal title="Giao việc mới" onClose={onClose} size="large">{taskId ? (error ? <p className="error">{error}</p> : <p className="muted">Đang tải...</p>) : fields}</Modal>

  const hasChecklist = task.checklist.length > 0
  return (
    <Modal title={`${task.code} · ${task.title}`} onClose={onClose} size="large">
      {editing ? fields : (
        <div className="task-detail">
          <div className="task-main">
            <div className="task-badges">
              {canEdit ? (
                <select className="stage-select" value={task.stageId ?? ''} onChange={(e) => run(() => projectApi.moveTask(task.id, Number(e.target.value)))} aria-label="Chuyển cột">
                  {lookups.stages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              ) : <span className="pill">{task.stageName}</span>}
              <PriorityTag value={task.priority} />
              {task.isOverdue && <span className="pill cancelled small-pill"><i className="ti ti-alarm" aria-hidden="true" /> Quá hạn</span>}
              {task.completedAt && <span className="pill completed small-pill">Xong {formatDateTime(task.completedAt)}</span>}
            </div>
            {task.description ? <p className="pre-wrap">{task.description}</p> : <p className="muted small">Chưa có mô tả.</p>}

            <div className="section-head"><h2>Việc cần làm {hasChecklist && <span className="muted small">({task.checklist.filter((c) => c.isDone).length}/{task.checklist.length})</span>}</h2></div>
            <Progress value={task.progressPercent} late={task.isOverdue} />
            <ul className="checklist">
              {task.checklist.map((c) => (
                <li key={c.id}>
                  <label className="check"><input type="checkbox" checked={c.isDone} disabled={!canEdit || busy}
                    onChange={(e) => run(() => projectApi.toggleChecklist(task.id, c.id, e.target.checked))} /> <span className={c.isDone ? 'strike' : ''}>{c.title}</span></label>
                  {canEdit && <button className="btn ghost small" aria-label={`Xóa mục ${c.title}`} onClick={() => run(() => projectApi.removeChecklist(task.id, c.id))}><i className="ti ti-x" aria-hidden="true" /></button>}
                </li>
              ))}
            </ul>
            {canEdit && (
              <form className="inline-form" onSubmit={(e) => { e.preventDefault(); if (newItem.trim()) run(async () => { const t = await projectApi.addChecklist(task.id, newItem); setNewItem(''); return t }) }}>
                <input value={newItem} onChange={(e) => setNewItem(e.target.value)} placeholder="Thêm việc nhỏ, Enter để lưu" aria-label="Thêm mục checklist" maxLength={255} />
                <button className="btn" disabled={busy || !newItem.trim()}>Thêm</button>
              </form>
            )}
            {canEdit && !hasChecklist && !task.completedAt && (
              <label className="top-gap block">Tiến độ tự nhập: <b>{Math.round(task.progressPercent)}%</b>
                <input type="range" key={task.progressPercent} min="0" max="100" step="10" defaultValue={task.progressPercent}
                  onMouseUp={(e) => run(() => projectApi.setProgress(task.id, Number(e.target.value)))}
                  onKeyUp={(e) => run(() => projectApi.setProgress(task.id, Number(e.target.value)))} aria-label="Tiến độ (%)" />
              </label>
            )}

            <div className="section-head"><h2>Giờ làm <span className="muted small">{formatQty(task.loggedHours)}{task.estimatedHours ? ` / ${formatQty(task.estimatedHours)}` : ''} giờ</span></h2></div>
            {canEdit && (
              <form className="inline-form wrap" onSubmit={(e) => {
                e.preventDefault()
                run(async () => { const t = await projectApi.logTime(task.id, { date: log.date, hours: Number(log.hours), note: log.note || null }); setLog({ ...log, hours: '', note: '' }); return t })
              }}>
                <input type="date" value={log.date} max={todayIso()} onChange={(e) => setLog({ ...log, date: e.target.value })} aria-label="Ngày làm" />
                <input type="number" min="0.25" max="24" step="0.25" value={log.hours} onChange={(e) => setLog({ ...log, hours: e.target.value })} placeholder="Số giờ" aria-label="Số giờ" className="w-sm" />
                <input value={log.note} onChange={(e) => setLog({ ...log, note: e.target.value })} placeholder="Đã làm gì (không bắt buộc)" aria-label="Ghi chú" maxLength={500} />
                <button className="btn" disabled={busy || !log.hours}>Ghi giờ</button>
              </form>
            )}
            {task.timesheets.length > 0 && (
              <table className="grid compact top-gap">
                <tbody>{task.timesheets.map((s) => <tr key={s.id}><td>{formatDateOnly(s.workDate)}</td><td>{s.userName}</td><td className="num">{formatQty(s.hours)} giờ</td><td className="muted small">{s.note}</td></tr>)}</tbody>
              </table>
            )}
          </div>
          <aside className="task-side">
            <dl className="info-list">
              <dt>Người nhận</dt><dd>{task.assigneeName ?? <span className="muted">Chưa giao</span>}</dd>
              <dt>Người giao</dt><dd>{task.reporterName ?? '-'}</dd>
              {task.projectName && <><dt>Dự án</dt><dd><Link to={`/projects/${task.projectId}`} onClick={onClose}>{task.projectName}</Link></dd></>}
              {task.departmentName && <><dt>Phòng ban</dt><dd>{task.departmentName}</dd></>}
              <dt>Bắt đầu</dt><dd>{task.startDate ? formatDateOnly(task.startDate) : '-'}</dd>
              <dt>Hạn chót</dt><dd className={task.isOverdue ? 'overdue' : ''}>{task.dueDate ? formatDateOnly(task.dueDate) : '-'}</dd>
              <dt>Tạo lúc</dt><dd>{formatDateTime(task.createdAt)}</dd>
            </dl>
            {error && <p className="error">{error}</p>}
            <div className="side-actions">
              {canEdit && <button className="btn" onClick={() => setEditing(true)}><i className="ti ti-pencil" aria-hidden="true" /> Sửa</button>}
              {can(PHASE4_PERMISSIONS.PROJECT_DELETE) && <button className="btn danger-text" onClick={remove}><i className="ti ti-trash" aria-hidden="true" /> Xóa</button>}
            </div>
          </aside>
        </div>
      )}
    </Modal>
  )
}

// ===================== Trang Công việc =====================

/** Bảng công việc của mọi người / của tôi: kéo thả giữa các cột, lọc theo dự án, quá hạn. */
export function TasksPage() {
  const { can } = useAuth()
  const [lookups, reloadLookups] = useProjectLookups()
  const [summary, setSummary] = useState(null)
  const [filters, setFilters] = useState({ assignee: 'me', status: '', projectId: '', search: '' })
  const [search, setSearch] = useState('')
  const [view, setView] = useState(() => { try { return localStorage.getItem('myerp.tasks.view') || 'board' } catch { return 'board' } })
  const [open, setOpen] = useState(null)
  const [reloadKey, setReloadKey] = useState(0)
  useEffect(() => { projectApi.list({ pageSize: 1 }).then((r) => setSummary(r.summary)).catch(() => {}) }, [reloadKey])
  useEffect(() => { const t = setTimeout(() => setFilters((f) => (f.search === search ? f : { ...f, search })), 300); return () => clearTimeout(t) }, [search])
  const setViewMode = (v) => { setView(v); try { localStorage.setItem('myerp.tasks.view', v) } catch { /* trình duyệt chặn lưu */ } }
  const refresh = () => { setReloadKey((k) => k + 1); reloadLookups() }

  return (
    <ProjectsLayout>
      <div className="page-head">
        <h1>Công việc</h1>
        {can(PHASE4_PERMISSIONS.PROJECT_CREATE) && <button className="btn primary" onClick={() => setOpen('new')}><i className="ti ti-plus" aria-hidden="true" /> Giao việc</button>}
      </div>
      <div className="kpi-row">
        <button className="kpi as-button" onClick={() => setFilters({ ...filters, assignee: 'me', status: 'open' })}><span className="muted small">Việc của tôi đang mở</span><b>{summary?.myOpenTasks ?? '…'}</b></button>
        <button className="kpi as-button" onClick={() => setFilters({ ...filters, assignee: '', status: 'overdue' })}><span className="muted small">Quá hạn</span><b className={summary?.overdueTasks ? 'money-out' : ''}>{summary?.overdueTasks ?? '…'}</b></button>
        <div className="kpi"><span className="muted small">Đến hạn trong 7 ngày</span><b>{summary?.dueThisWeek ?? '…'}</b></div>
        <div className="kpi"><span className="muted small">Xong trong tháng</span><b className="ok-text">{summary?.doneThisMonth ?? '…'}</b></div>
      </div>
      <div className="toolbar">
        <div className="segmented no-margin">
          {[['me', 'Của tôi'], ['', 'Tất cả'], ['none', 'Chưa giao']].map(([v, l]) => <button key={v} className={filters.assignee === v ? 'on' : ''} onClick={() => setFilters({ ...filters, assignee: v })}>{l}</button>)}
        </div>
        <select value={filters.status} onChange={(e) => setFilters({ ...filters, status: e.target.value })} aria-label="Lọc trạng thái">
          <option value="">Đang mở + xong 30 ngày qua</option><option value="open">Chỉ việc đang mở</option><option value="overdue">Quá hạn</option><option value="done">Đã xong</option>
        </select>
        <select value={filters.projectId} onChange={(e) => setFilters({ ...filters, projectId: e.target.value })} aria-label="Lọc dự án">
          <option value="">Mọi dự án</option>{lookups.projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
        <div className="search"><i className="ti ti-search" aria-hidden="true" /><input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Tìm công việc" aria-label="Tìm công việc" /></div>
        <div className="segmented no-margin">
          <button className={view === 'board' ? 'on' : ''} onClick={() => setViewMode('board')} aria-label="Xem dạng bảng Kanban"><i className="ti ti-layout-kanban" aria-hidden="true" /></button>
          <button className={view === 'list' ? 'on' : ''} onClick={() => setViewMode('list')} aria-label="Xem dạng danh sách"><i className="ti ti-list" aria-hidden="true" /></button>
        </div>
      </div>
      {view === 'board'
        ? <TaskBoardView filters={filters} lookups={lookups} onOpen={setOpen} reloadKey={reloadKey} canMove={can(PHASE4_PERMISSIONS.PROJECT_EDIT)} />
        : <TaskListView filters={filters} onOpen={setOpen} reloadKey={reloadKey} />}
      {open && <TaskModal taskId={open === 'new' ? null : open} defaults={{ stageId: lookups.stages[0]?.id, assigneeUserId: filters.assignee === 'me' ? lookups.currentUserId : '' }}
        lookups={lookups} onClose={() => { setOpen(null); refresh() }} onChanged={() => setReloadKey((k) => k + 1)} />}
    </ProjectsLayout>
  )
}

// ===================== Dự án =====================

function ProjectFormModal({ project, lookups, onClose, onSaved }) {
  const isNew = !project
  const [form, setForm] = useState({
    name: project?.name ?? '', partner: project?.partnerId ? { id: project.partnerId, name: project.partnerName } : null,
    managerUserId: project?.managerUserId ?? lookups.currentUserId ?? '', departmentId: project?.departmentId ?? '',
    startDate: project?.startDate ?? todayIso(), endDate: project?.endDate ?? '', budget: project?.budget ?? 0, status: project?.status ?? 'active',
    description: project?.description ?? '', memberIds: project?.members.map((m) => m.userId) ?? [lookups.currentUserId].filter(Boolean),
  })
  const [error, setError] = useState('')
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })
  const toggleMember = (id) => setForm({ ...form, memberIds: form.memberIds.includes(id) ? form.memberIds.filter((x) => x !== id) : [...form.memberIds, id] })
  const save = async (e) => {
    e.preventDefault()
    const body = { name: form.name, partnerId: form.partner?.id ?? null, managerUserId: form.managerUserId ? Number(form.managerUserId) : null,
      departmentId: form.departmentId ? Number(form.departmentId) : null, startDate: form.startDate || null, endDate: form.endDate || null,
      budget: Number(form.budget) || 0, status: form.status, description: form.description || null, memberIds: form.memberIds, rowVersion: project?.rowVersion ?? null }
    try { onSaved(isNew ? await projectApi.create(body) : await projectApi.update(project.id, body)) } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <Modal title={isNew ? 'Tạo dự án' : `Sửa ${project.code}`} onClose={onClose} size="large">
      <form onSubmit={save}>
        <div className="form-grid">
          <label className="span2">Tên dự án *<input value={form.name} onChange={u('name')} autoFocus placeholder="VD: Khai trương chi nhánh Quận 7" /></label>
          <label>Quản lý dự án<select value={form.managerUserId} onChange={u('managerUserId')}><option value="">—</option>
            {lookups.users.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}</select></label>
          <label>Trạng thái<select value={form.status} onChange={u('status')}>{PROJECT_STATUSES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}</select></label>
          <label>Bắt đầu<input type="date" value={form.startDate} onChange={u('startDate')} /></label>
          <label>Kết thúc dự kiến<input type="date" value={form.endDate} onChange={u('endDate')} /></label>
          <label>Ngân sách<MoneyInput value={form.budget} onChange={(v) => setForm({ ...form, budget: v })} /></label>
          <label>Phòng ban<select value={form.departmentId} onChange={u('departmentId')}><option value="">—</option>
            {lookups.departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}</select></label>
          <label className="span2">Khách hàng (nếu làm cho khách)<CustomerPicker value={form.partner} onChange={(p) => setForm({ ...form, partner: p })} /></label>
          <label className="span2">Mô tả<textarea rows={2} value={form.description} onChange={u('description')} /></label>
        </div>
        <fieldset className="member-pick">
          <legend>Thành viên ({form.memberIds.length})</legend>
          {lookups.users.map((x) => (
            <label key={x.id} className="check"><input type="checkbox" checked={form.memberIds.includes(x.id) || String(x.id) === String(form.managerUserId)}
              disabled={String(x.id) === String(form.managerUserId)} onChange={() => toggleMember(x.id)} /> {x.name}{x.description ? <span className="muted small"> · {x.description}</span> : null}</label>
          ))}
        </fieldset>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot"><button type="button" className="btn" onClick={onClose}>Hủy</button><button className="btn primary">Lưu</button></div>
      </form>
    </Modal>
  )
}

/** Danh sách dự án: tiến độ theo công việc, việc quá hạn, trễ hạn dự án. */
export function ProjectsPage() {
  const { can } = useAuth()
  const navigate = useNavigate()
  const [lookups] = useProjectLookups()
  const [data, setData] = useState(null)
  const [status, setStatus] = useState('open')
  const [page, setPage] = useState(1)
  const [creating, setCreating] = useState(false)
  const [error, setError] = useState('')
  useEffect(() => { projectApi.list({ status, page, pageSize: 20 }).then(setData).catch((e) => setError(getErrorMessage(e))) }, [status, page])
  const s = data?.summary

  return (
    <ProjectsLayout>
      <div className="page-head">
        <h1>Dự án</h1>
        {can(PHASE4_PERMISSIONS.PROJECT_CREATE) && <button className="btn primary" onClick={() => setCreating(true)}><i className="ti ti-plus" aria-hidden="true" /> Tạo dự án</button>}
      </div>
      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Dự án đang chạy</span><b>{s?.active ?? '…'}</b></div>
        <div className="kpi"><span className="muted small">Việc của tôi đang mở</span><b>{s?.myOpenTasks ?? '…'}</b></div>
        <div className="kpi"><span className="muted small">Việc quá hạn</span><b className={s?.overdueTasks ? 'money-out' : ''}>{s?.overdueTasks ?? '…'}</b></div>
        <div className="kpi"><span className="muted small">Xong trong tháng</span><b className="ok-text">{s?.doneThisMonth ?? '…'}</b></div>
      </div>
      <div className="toolbar">
        <div className="segmented no-margin">
          {[{ value: 'open', label: 'Đang mở' }, { value: '', label: 'Tất cả' }, ...PROJECT_STATUSES.filter((x) => x.value === 'completed' || x.value === 'cancelled')]
            .map((x) => <button key={x.value} className={status === x.value ? 'on' : ''} onClick={() => { setStatus(x.value); setPage(1) }}>{x.label}</button>)}
        </div>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Dự án</th><th className="hide-sm">Tiến độ</th><th className="num">Công việc</th><th className="hide-sm">Kết thúc</th><th>Trạng thái</th></tr></thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.rows.items.length === 0 && <tr><td colSpan={5} className="muted center">Chưa có dự án.</td></tr>}
            {data?.rows.items.map((p) => (
              <tr key={p.id} className="clickable" onClick={() => navigate(`/projects/${p.id}`)}>
                <td><Link to={`/projects/${p.id}`} onClick={(e) => e.stopPropagation()}>{p.name}</Link>
                  <div className="muted small">{p.code}{p.managerName ? ` · QL: ${p.managerName}` : ''} · {p.memberCount} người{p.partnerName ? ` · ${p.partnerName}` : ''}</div></td>
                <td className="hide-sm"><Progress value={p.progressPercent} late={p.isLate} /></td>
                <td className="num">{p.doneCount}/{p.taskCount}{p.overdueCount > 0 && <div className="small overdue">{p.overdueCount} quá hạn</div>}</td>
                <td className={`hide-sm ${p.isLate ? 'overdue' : ''}`}>{p.endDate ? formatDateOnly(p.endDate) : '-'}{p.isLate && <div className="small">Trễ hạn</div>}</td>
                <td><span className={`pill ${projectStatus(p.status).css}`}>{projectStatus(p.status).label}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data?.rows} unit="dự án" onPageChange={setPage} />
      {creating && <ProjectFormModal lookups={lookups} onClose={() => setCreating(false)} onSaved={(p) => navigate(`/projects/${p.id}`)} />}
    </ProjectsLayout>
  )
}

/** Chi tiết dự án: tiến độ, thành viên, bảng công việc của dự án. */
export function ProjectDetailPage() {
  const { id } = useParams()
  const { can } = useAuth()
  const [lookups, reloadLookups] = useProjectLookups()
  const [p, setP] = useState(null)
  const [editing, setEditing] = useState(false)
  const [open, setOpen] = useState(null)
  const [reloadKey, setReloadKey] = useState(0)
  const [error, setError] = useState('')
  const filters = useMemo(() => ({ projectId: id, status: '' }), [id])
  useEffect(() => { projectApi.get(id).then(setP).catch((e) => setError(getErrorMessage(e))) }, [id, reloadKey])
  if (!p) return <ProjectsLayout>{error ? <div className="alert error">{error}</div> : <p className="muted">Đang tải...</p>}</ProjectsLayout>
  const closed = p.status === 'completed' || p.status === 'cancelled'

  return (
    <ProjectsLayout>
      <div className="breadcrumb"><Link to="/projects/list">Dự án</Link> / {p.code}</div>
      <div className="page-head">
        <div><h1>{p.name} <span className={`pill ${projectStatus(p.status).css} small-pill`}>{projectStatus(p.status).label}</span></h1>
          <div className="muted small">{p.startDate ? formatDateOnly(p.startDate) : '?'} → {p.endDate ? formatDateOnly(p.endDate) : '?'}{p.isLate && <b className="overdue"> · Trễ hạn</b>}
            {p.partnerName && <> · Khách: {p.partnerName}</>}{p.departmentName && <> · {p.departmentName}</>}</div></div>
        <div className="head-actions">
          {!closed && can(PHASE4_PERMISSIONS.PROJECT_CREATE) && <button className="btn primary" onClick={() => setOpen('new')}><i className="ti ti-plus" aria-hidden="true" /> Thêm việc</button>}
          {p.canEdit && <button className="btn" onClick={() => setEditing(true)}><i className="ti ti-pencil" aria-hidden="true" /> Sửa dự án</button>}
        </div>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Tiến độ</span><b>{Math.round(p.progressPercent)}%</b><Progress value={p.progressPercent} late={p.isLate} /></div>
        <div className="kpi"><span className="muted small">Công việc xong</span><b>{p.doneCount}/{p.taskCount}</b>{p.overdueCount > 0 && <span className="small overdue">{p.overdueCount} việc quá hạn</span>}</div>
        <div className="kpi"><span className="muted small">Giờ làm đã ghi</span><b>{formatQty(p.loggedHours)}</b><span className="small muted">dự kiến {formatQty(p.estimatedHours)} giờ</span></div>
        <div className="kpi"><span className="muted small">Ngân sách</span><b>{p.budget ? formatMoneyShort(p.budget) : '-'}</b><span className="small muted">{p.budget ? formatMoney(p.budget) : ''}</span></div>
      </div>
      {p.description && <p className="pre-wrap muted">{p.description}</p>}
      <div className="card">
        <div className="section-head first"><h2>Thành viên ({p.members.length})</h2></div>
        <div className="member-chips">
          {p.members.map((m) => (
            <div key={m.userId} className="member-chip" title={`${m.openTasks} việc đang mở · ${formatQty(m.hours)} giờ`}>
              <span className="avatar tiny">{initials(m.fullName)}</span>
              <span>{m.fullName}{m.role === 'manager' && <span className="muted small"> · Quản lý</span>}</span>
              <span className="muted small">{m.openTasks} việc</span>
            </div>
          ))}
        </div>
      </div>
      <div className="section-head"><h2>Công việc của dự án</h2></div>
      <TaskBoardView filters={filters} lookups={lookups} onOpen={setOpen} reloadKey={reloadKey} canMove={!closed && can(PHASE4_PERMISSIONS.PROJECT_EDIT)} />
      {editing && <ProjectFormModal project={p} lookups={lookups} onClose={() => setEditing(false)} onSaved={(x) => { setP(x); setEditing(false); reloadLookups() }} />}
      {open && <TaskModal taskId={open === 'new' ? null : open} defaults={{ projectId: p.id, stageId: lookups.stages[0]?.id }} lookups={lookups}
        onClose={() => { setOpen(null); setReloadKey((k) => k + 1) }} onChanged={() => setReloadKey((k) => k + 1)} />}
    </ProjectsLayout>
  )
}
