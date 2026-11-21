import { useCallback, useEffect, useRef, useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { documentApi } from '../../api/phase4Api'
import CustomerPicker from '../../components/CustomerPicker'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import Pagination from '../../components/Pagination'
import { DOCUMENT_STATUS_CSS, DOCUMENT_TYPE_ICONS, PHASE4_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import ModuleLayout from '../../layouts/ModuleLayout'
import { formatDateOnly, formatDateTime, formatMoney, formatMoneyShort } from '../../utils/format'

const MENU = [{ to: '/documents', icon: 'folder', label: 'Tài liệu', end: true }]

function DocumentsLayout({ children }) {
  return <ModuleLayout title="Tài liệu" icon="folder" color="#888780" menu={MENU}>{children}</ModuleLayout>
}

export const fileSize = (bytes) => {
  if (!bytes) return ''
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1).replace('.', ',')} MB`
}

const label = (list, code) => list.find((x) => x.code === code)?.name ?? code

function expiryText(d) {
  if (d.daysToExpiry === null || d.daysToExpiry === undefined) return null
  if (d.daysToExpiry < 0) return { text: `Hết hạn ${-d.daysToExpiry} ngày`, css: 'overdue' }
  if (d.isExpiring) return { text: d.daysToExpiry === 0 ? 'Hết hạn hôm nay' : `Còn ${d.daysToExpiry} ngày`, css: 'warn-text' }
  return null
}

function FolderModal({ folder, lookups, onClose, onSaved }) {
  const [form, setForm] = useState({ name: folder?.name ?? '', departmentId: folder?.departmentId ?? '' })
  const [error, setError] = useState('')
  const save = async (e) => {
    e.preventDefault()
    const body = { name: form.name, parentId: null, departmentId: form.departmentId ? Number(form.departmentId) : null }
    try { onSaved(folder ? await documentApi.updateFolder(folder.id, body) : await documentApi.createFolder(body)) } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <Modal title={folder ? 'Đổi tên thư mục' : 'Thư mục mới'} onClose={onClose} size="small">
      <form onSubmit={save}>
        <label>Tên thư mục *<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} autoFocus maxLength={255} /></label>
        <label className="top-gap block">Dành cho
          <select value={form.departmentId} onChange={(e) => setForm({ ...form, departmentId: e.target.value })}>
            <option value="">Cả công ty (ai cũng xem được)</option>
            {lookups.departments.map((d) => <option key={d.id} value={d.id}>Riêng {d.name}</option>)}
          </select></label>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot"><button type="button" className="btn" onClick={onClose}>Hủy</button><button className="btn primary">Lưu</button></div>
      </form>
    </Modal>
  )
}

function DocumentFormModal({ doc, lookups, defaultFolderId, onClose, onSaved }) {
  const isNew = !doc
  const [form, setForm] = useState({
    title: doc?.title ?? '', type: doc?.type ?? 'contract', folderId: doc?.folderId ?? defaultFolderId ?? '', status: doc?.rawStatus ?? 'active',
    partner: doc?.partnerId ? { id: doc.partnerId, name: doc.partnerName } : null, effectiveDate: doc?.effectiveDate ?? '', expiryDate: doc?.expiryDate ?? '',
    contractValue: doc?.contractValue ?? '', code: doc?.code ?? '',
  })
  const [file, setFile] = useState(null)
  const [progress, setProgress] = useState(null)
  const [error, setError] = useState('')
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })
  const save = async (e) => {
    e.preventDefault(); setError('')
    const body = { title: form.title, type: form.type, folderId: form.folderId ? Number(form.folderId) : null, partnerId: form.partner?.id ?? null, status: form.status,
      effectiveDate: form.effectiveDate || null, expiryDate: form.expiryDate || null, contractValue: form.contractValue === '' ? null : Number(form.contractValue),
      code: form.code || null, rowVersion: doc?.rowVersion ?? null }
    try {
      let saved = isNew ? await documentApi.create(body) : await documentApi.update(doc.id, body)
      if (file) { setProgress(0); saved = await documentApi.upload(saved.id, file, 'Bản đầu tiên', setProgress) }
      onSaved(saved)
    } catch (err) { setError(getErrorMessage(err)); setProgress(null) }
  }
  const isContract = form.type === 'contract'
  return (
    <Modal title={isNew ? 'Thêm tài liệu' : 'Sửa thông tin tài liệu'} onClose={onClose} size="large">
      <form onSubmit={save}>
        <div className="form-grid">
          <label className="span2">Tên tài liệu *<input value={form.title} onChange={u('title')} autoFocus maxLength={255} placeholder="VD: Hợp đồng thuê mặt bằng cửa hàng" /></label>
          <label>Loại<select value={form.type} onChange={u('type')}>{lookups.types.map((t) => <option key={t.code} value={t.code}>{t.name}</option>)}</select></label>
          <label>Thư mục<select value={form.folderId} onChange={u('folderId')}><option value="">— Riêng của tôi —</option>
            {lookups.folders.map((f) => <option key={f.id} value={f.id}>{f.name}{f.departmentName ? ` (${f.departmentName})` : ''}</option>)}</select></label>
          <label>Trạng thái<select value={form.status} onChange={u('status')}>{lookups.statuses.map((s) => <option key={s.code} value={s.code}>{s.name}</option>)}</select></label>
          <label>Số hiệu<input value={form.code} onChange={u('code')} maxLength={30} placeholder="VD: HD-TMB-01" /></label>
          <label>Ngày hiệu lực<input type="date" value={form.effectiveDate} onChange={u('effectiveDate')} /></label>
          <label>Ngày hết hạn<input type="date" value={form.expiryDate} onChange={u('expiryDate')} /><span className="hint-inline">Báo trước 30 ngày khi sắp hết hạn.</span></label>
          {isContract && <label>Giá trị hợp đồng<MoneyInput value={form.contractValue || 0} onChange={(v) => setForm({ ...form, contractValue: v })} /></label>}
          {isContract && <label>Đối tác (khách / nhà cung cấp)<CustomerPicker value={form.partner} onChange={(p) => setForm({ ...form, partner: p })} /></label>}
          {isNew && (
            <label className="span2">File đính kèm (không bắt buộc)
              <input type="file" accept={lookups.allowedExtensions.join(',')} onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
              <span className="hint-inline">Tối đa {Math.round(lookups.maxUploadBytes / 1024 / 1024)} MB: PDF, Word, Excel, ảnh, ZIP...</span>
            </label>
          )}
        </div>
        {progress !== null && <div className="hbar-track top-gap"><div className="hbar-fill" style={{ width: `${progress}%` }} /></div>}
        {error && <p className="error">{error}</p>}
        <div className="modal-foot"><button type="button" className="btn" onClick={onClose}>Hủy</button><button className="btn primary" disabled={progress !== null}>Lưu</button></div>
      </form>
    </Modal>
  )
}

function DocumentDetailModal({ id, lookups, onClose, onChanged }) {
  const { can } = useAuth()
  const [d, setD] = useState(null)
  const [editing, setEditing] = useState(false)
  const [note, setNote] = useState('')
  const [progress, setProgress] = useState(null)
  const [error, setError] = useState('')
  const fileRef = useRef(null)
  useEffect(() => { documentApi.get(id).then(setD).catch((e) => setError(getErrorMessage(e))) }, [id])

  const upload = async (file) => {
    if (!file) return
    setError(''); setProgress(0)
    try { setD(await documentApi.upload(d.id, file, note, setProgress)); setNote(''); onChanged() } catch (err) { setError(getErrorMessage(err)) } finally { setProgress(null); if (fileRef.current) fileRef.current.value = '' }
  }
  const download = async (v) => { try { await documentApi.download(v.attachmentId, v.fileName) } catch (err) { setError(getErrorMessage(err)) } }
  const remove = async () => {
    if (!window.confirm(`Xóa tài liệu "${d.title}"? Có thể khôi phục lại từ database nếu cần.`)) return
    try { await documentApi.remove(d.id); onChanged(); onClose() } catch (err) { setError(getErrorMessage(err)) }
  }

  if (!d) return <Modal title="Tài liệu" onClose={onClose}>{error ? <p className="error">{error}</p> : <p className="muted">Đang tải...</p>}</Modal>
  if (editing) return <DocumentFormModal doc={d} lookups={lookups} onClose={() => setEditing(false)} onSaved={(x) => { setD(x); setEditing(false); onChanged() }} />
  const exp = expiryText(d)
  return (
    <Modal title={d.title} onClose={onClose} size="large">
      <div className="doc-head">
        <span className={`pill ${DOCUMENT_STATUS_CSS[d.status] ?? ''}`}>{label(lookups.statuses, d.status)}</span>
        <span className="muted small">{label(lookups.types, d.type)}{d.code ? ` · ${d.code}` : ''}{d.folderName ? ` · ${d.folderName}` : ' · Riêng của tôi'}</span>
        {exp && <b className={`small ${exp.css}`}><i className="ti ti-alarm" aria-hidden="true" /> {exp.text}</b>}
      </div>
      <dl className="info-list cols">
        {d.partnerName && <><dt>Đối tác</dt><dd>{d.partnerName}</dd></>}
        <dt>Hiệu lực</dt><dd>{d.effectiveDate ? formatDateOnly(d.effectiveDate) : '-'}</dd>
        <dt>Hết hạn</dt><dd className={exp?.css ?? ''}>{d.expiryDate ? formatDateOnly(d.expiryDate) : 'Không thời hạn'}</dd>
        {d.contractValue !== null && <><dt>Giá trị</dt><dd>{formatMoney(d.contractValue)}</dd></>}
        <dt>Phụ trách</dt><dd>{d.ownerName ?? '-'}</dd>
        <dt>Tạo lúc</dt><dd>{formatDateTime(d.createdAt)}</dd>
      </dl>
      <div className="section-head"><h2>File & phiên bản</h2></div>
      {d.versions.length === 0 && <p className="muted">Chưa có file. {d.canEdit && 'Tải bản scan / file Word lên bên dưới.'}</p>}
      {d.versions.length > 0 && (
        <table className="grid compact">
          <tbody>
            {d.versions.map((v, i) => (
              <tr key={v.id}>
                <td><span className={`pill ${i === 0 ? 'completed' : 'draft'} small-pill`}>v{v.versionNo}</span></td>
                <td><button className="link-button" onClick={() => download(v)}><i className="ti ti-download" aria-hidden="true" /> {v.fileName}</button>
                  <div className="muted small">{fileSize(v.sizeBytes)}{v.note ? ` · ${v.note}` : ''}</div></td>
                <td className="muted small">{v.createdByName}<div>{formatDateTime(v.createdAt)}</div></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {d.canEdit && (
        <div className="inline-form wrap top-gap">
          <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="Ghi chú phiên bản (VD: bản đã ký)" aria-label="Ghi chú phiên bản" maxLength={500} />
          <input ref={fileRef} type="file" className="visually-hidden" id="doc-upload" accept={lookups.allowedExtensions.join(',')} onChange={(e) => upload(e.target.files?.[0])} />
          <label htmlFor="doc-upload" className={`btn${progress !== null ? ' disabled' : ''}`}><i className="ti ti-upload" aria-hidden="true" /> {d.versions.length ? 'Tải phiên bản mới' : 'Tải file lên'}</label>
        </div>
      )}
      {progress !== null && <div className="hbar-track top-gap"><div className="hbar-fill" style={{ width: `${progress}%` }} /></div>}
      {error && <p className="error">{error}</p>}
      <div className="modal-foot">
        {can(PHASE4_PERMISSIONS.DOCUMENT_DELETE) && d.canEdit && <button className="btn danger-text" onClick={remove}><i className="ti ti-trash" aria-hidden="true" /> Xóa</button>}
        <span className="spacer" />
        {d.canEdit && <button className="btn" onClick={() => setEditing(true)}><i className="ti ti-pencil" aria-hidden="true" /> Sửa thông tin</button>}
        <button className="btn primary" onClick={onClose}>Đóng</button>
      </div>
    </Modal>
  )
}

/** Kho tài liệu: thư mục bên trái, danh sách + cảnh báo hợp đồng sắp hết hạn. */
export function DocumentsPage() {
  const { can } = useAuth()
  const [lookups, setLookups] = useState(null)
  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ folderId: '', type: '', status: '', search: '' })
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const [open, setOpen] = useState(null)
  const [folderModal, setFolderModal] = useState(null)
  const [error, setError] = useState('')
  const loadLookups = useCallback(() => documentApi.lookups().then(setLookups).catch((e) => setError(getErrorMessage(e))), [])
  const load = useCallback(() => documentApi.list({ ...filters, page, pageSize: 20 }).then(setData).catch((e) => setError(getErrorMessage(e))), [filters, page])
  useEffect(() => { loadLookups() }, [loadLookups])
  useEffect(() => { load() }, [load])
  useEffect(() => { const t = setTimeout(() => { setFilters((f) => (f.search === search ? f : { ...f, search })); setPage(1) }, 300); return () => clearTimeout(t) }, [search])
  const set = (patch) => { setFilters({ ...filters, ...patch }); setPage(1) }
  const changed = () => { load(); loadLookups() }
  const s = data?.summary
  const currentFolder = lookups?.folders.find((f) => String(f.id) === String(filters.folderId))

  const deleteFolder = async () => {
    if (!window.confirm(`Xóa thư mục "${currentFolder.name}"? Thư mục phải trống.`)) return
    try { await documentApi.deleteFolder(currentFolder.id); set({ folderId: '' }); loadLookups() } catch (err) { setError(getErrorMessage(err)) }
  }

  return (
    <DocumentsLayout>
      <div className="page-head">
        <h1>Tài liệu</h1>
        {can(PHASE4_PERMISSIONS.DOCUMENT_CREATE) && lookups && <button className="btn primary" onClick={() => setOpen('new')}><i className="ti ti-plus" aria-hidden="true" /> Thêm tài liệu</button>}
      </div>
      <div className="kpi-row">
        <button className="kpi as-button" onClick={() => set({ status: '', type: '' })}><span className="muted small">Tổng tài liệu</span><b>{s?.total ?? '…'}</b></button>
        <button className="kpi as-button" onClick={() => set({ status: 'expiring', type: '' })}><span className="muted small">Sắp hết hạn (30 ngày)</span><b className={s?.expiring ? 'warn-text' : ''}>{s?.expiring ?? '…'}</b></button>
        <button className="kpi as-button" onClick={() => set({ status: 'expired', type: '' })}><span className="muted small">Đã hết hạn</span><b className={s?.expired ? 'money-out' : ''}>{s?.expired ?? '…'}</b></button>
        <button className="kpi as-button" onClick={() => set({ type: 'contract', status: '' })}><span className="muted small">Hợp đồng còn hiệu lực</span><b>{s ? formatMoneyShort(s.activeContractValue) : '…'}</b><span className="small muted">{s?.contracts ?? 0} hợp đồng · {s?.pendingSignature ?? 0} chờ ký</span></button>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="doc-layout">
        <nav className="folder-list" aria-label="Thư mục">
          <button className={!filters.folderId ? 'active' : ''} onClick={() => set({ folderId: '' })}><i className="ti ti-files" aria-hidden="true" /> Tất cả tài liệu</button>
          {lookups?.folders.map((f) => (
            <button key={f.id} className={String(filters.folderId) === String(f.id) ? 'active' : ''} onClick={() => set({ folderId: f.id })}>
              <i className={`ti ti-${f.departmentId ? 'folder-star' : 'folder'}`} aria-hidden="true" />
              <span className="grow">{f.name}{f.departmentName && <span className="muted small block">{f.departmentName}</span>}</span>
              <span className="count">{f.documentCount}</span>
            </button>
          ))}
          {can(PHASE4_PERMISSIONS.DOCUMENT_CREATE) && <button className="muted" onClick={() => setFolderModal('new')}><i className="ti ti-folder-plus" aria-hidden="true" /> Thư mục mới</button>}
        </nav>
        <div className="doc-main">
          <div className="toolbar">
            <div className="search"><i className="ti ti-search" aria-hidden="true" /><input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Tìm tên, số hiệu, đối tác" aria-label="Tìm tài liệu" /></div>
            <select value={filters.type} onChange={(e) => set({ type: e.target.value })} aria-label="Lọc loại tài liệu"><option value="">Mọi loại</option>
              {lookups?.types.map((t) => <option key={t.code} value={t.code}>{t.name}</option>)}</select>
            <select value={filters.status} onChange={(e) => set({ status: e.target.value })} aria-label="Lọc trạng thái"><option value="">Mọi trạng thái</option>
              <option value="expiring">Sắp hết hạn</option>{lookups?.statuses.map((t) => <option key={t.code} value={t.code}>{t.name}</option>)}</select>
            {currentFolder && can(PHASE4_PERMISSIONS.DOCUMENT_EDIT) && (
              <span className="toolbar-end">
                <button className="btn ghost small" onClick={() => setFolderModal(currentFolder)}><i className="ti ti-pencil" aria-hidden="true" /> Đổi tên</button>
                {currentFolder.documentCount === 0 && can(PHASE4_PERMISSIONS.DOCUMENT_DELETE) && <button className="btn ghost small" onClick={deleteFolder}><i className="ti ti-trash" aria-hidden="true" /> Xóa thư mục</button>}
              </span>
            )}
          </div>
          <div className="table-wrap">
            <table className="grid">
              <thead><tr><th>Tài liệu</th><th className="hide-sm">File</th><th>Hết hạn</th><th>Trạng thái</th></tr></thead>
              <tbody>
                {!data && <tr><td colSpan={4} className="muted center">Đang tải...</td></tr>}
                {data?.rows.items.length === 0 && <tr><td colSpan={4} className="muted center">Không có tài liệu.</td></tr>}
                {data?.rows.items.map((d) => {
                  const exp = expiryText(d)
                  return (
                    <tr key={d.id} className="clickable" onClick={() => setOpen(d.id)}>
                      <td><span className="doc-title"><i className={`ti ti-${DOCUMENT_TYPE_ICONS[d.type] ?? 'file'}`} aria-hidden="true" /> <b>{d.title}</b></span>
                        <div className="muted small">{lookups ? label(lookups.types, d.type) : d.type}{d.code ? ` · ${d.code}` : ''}{d.partnerName ? ` · ${d.partnerName}` : ''}
                          {!filters.folderId && d.folderName ? ` · ${d.folderName}` : ''}{d.contractValue ? ` · ${formatMoneyShort(d.contractValue)}` : ''}</div></td>
                      <td className="hide-sm">{d.fileName ? <span className="small">{d.fileName}<div className="muted">v{d.versionNo} · {fileSize(d.sizeBytes)}</div></span> : <span className="muted small">Chưa có file</span>}</td>
                      <td>{d.expiryDate ? formatDateOnly(d.expiryDate) : <span className="muted">-</span>}{exp && <div className={`small ${exp.css}`}>{exp.text}</div>}</td>
                      <td><span className={`pill ${DOCUMENT_STATUS_CSS[d.status] ?? ''}`}>{lookups ? label(lookups.statuses, d.status) : d.status}</span></td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          <Pagination data={data?.rows} unit="tài liệu" onPageChange={setPage} />
        </div>
      </div>
      {open === 'new' && lookups && <DocumentFormModal lookups={lookups} defaultFolderId={filters.folderId} onClose={() => setOpen(null)} onSaved={(d) => { changed(); setOpen(d.id) }} />}
      {open && open !== 'new' && lookups && <DocumentDetailModal id={open} lookups={lookups} onClose={() => setOpen(null)} onChanged={changed} />}
      {folderModal && lookups && <FolderModal folder={folderModal === 'new' ? null : folderModal} lookups={lookups} onClose={() => setFolderModal(null)}
        onSaved={(f) => { setFolderModal(null); loadLookups(); set({ folderId: f.id }) }} />}
    </DocumentsLayout>
  )
}
