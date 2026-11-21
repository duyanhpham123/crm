import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { purchasingApi } from '../../api/retailApi'
import Modal from '../../components/Modal'
import Pagination from '../../components/Pagination'
import { RETAIL_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatMoney } from '../../utils/format'
import PurchasingLayout from './PurchasingLayout'

const FIELDS = ['name', 'taxCode', 'phone', 'email', 'street', 'note', 'contactName', 'contactPhone']

/** Thêm / sửa nhà cung cấp (mã NCC-0001 tự sinh) */
export function SupplierFormModal({ supplier, onClose, onSaved }) {
  const isNew = !supplier
  const [form, setForm] = useState(() => Object.fromEntries(FIELDS.map((f) => [f, supplier?.[f] ?? ''])))
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })

  const save = async (e) => {
    e.preventDefault()
    if (!form.name.trim()) return setError('Nhập tên nhà cung cấp.')
    setBusy(true)
    try {
      const body = Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v.trim() === '' ? null : v.trim()]))
      onSaved(isNew ? await purchasingApi.createSupplier(body) : await purchasingApi.updateSupplier(supplier.id, body), isNew)
    } catch (err) {
      setError(getErrorMessage(err))
      setBusy(false)
    }
  }

  return (
    <Modal title={isNew ? 'Thêm nhà cung cấp' : `Nhà cung cấp ${supplier.code}`} onClose={onClose}>
      <form onSubmit={save}>
        <div className="form-grid">
          <label className="span2">Tên nhà cung cấp *<input value={form.name} onChange={update('name')} autoFocus placeholder="Xưởng may Thành Công" /></label>
          <label>Mã số thuế<input value={form.taxCode} onChange={update('taxCode')} /></label>
          <label>Điện thoại<input value={form.phone} onChange={update('phone')} /></label>
          <label className="span2">Email<input type="email" value={form.email} onChange={update('email')} /></label>
          <label className="span2">Địa chỉ<input value={form.street} onChange={update('street')} /></label>
          <label>Người liên hệ<input value={form.contactName} onChange={update('contactName')} /></label>
          <label>SĐT người liên hệ<input value={form.contactPhone} onChange={update('contactPhone')} /></label>
          <label className="span2">Ghi chú<textarea rows={2} value={form.note} onChange={update('note')} placeholder="Điều khoản thanh toán, thời gian giao hàng..." /></label>
        </div>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy}>{busy ? 'Đang lưu...' : 'Lưu'}</button>
        </div>
      </form>
    </Modal>
  )
}

export default function SuppliersPage() {
  const { can } = useAuth()
  const [data, setData] = useState(null)
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const [editing, setEditing] = useState(null) // null | 'new' | supplier
  const [message, setMessage] = useState('')

  const load = useCallback(async () => {
    try {
      setError('')
      setData(await purchasingApi.listSuppliers({ search, page, pageSize: 20 }))
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }, [search, page])

  useEffect(() => {
    const timer = setTimeout(load, 250)
    return () => clearTimeout(timer)
  }, [load])

  const canEdit = can(RETAIL_PERMISSIONS.PURCHASING_EDIT)

  return (
    <PurchasingLayout>
      <div className="page-head">
        <h1>Nhà cung cấp</h1>
        {can(RETAIL_PERMISSIONS.PURCHASING_CREATE) && (
          <button className="btn primary" onClick={() => setEditing('new')}><i className="ti ti-plus" aria-hidden="true" /> Thêm nhà cung cấp</button>
        )}
      </div>
      {message && <div className="alert success">{message}</div>}
      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm tên, mã, MST, SĐT" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} aria-label="Tìm nhà cung cấp" />
        </div>
      </div>
      {error && <div className="alert error">{error}</div>}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr><th>Nhà cung cấp</th><th className="hide-sm">Liên hệ</th><th className="num">Số đơn nhập</th><th className="num">Đã nhập</th>{canEdit && <th className="actions" />}</tr>
          </thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.items.length === 0 && <tr><td colSpan={5} className="muted center">Chưa có nhà cung cấp.</td></tr>}
            {data?.items.map((s) => (
              <tr key={s.id}>
                <td>
                  <div className="user-cell">
                    <span className="avatar square"><i className="ti ti-building-factory-2" aria-hidden="true" /></span>
                    <div>
                      <b>{s.name}</b>
                      <div className="muted small">{s.code}{s.taxCode ? ` · MST ${s.taxCode}` : ''}</div>
                    </div>
                  </div>
                </td>
                <td className="hide-sm">
                  {s.contactName ?? s.phone}
                  <div className="muted small">{s.contactName ? (s.contactPhone ?? s.phone) : s.email}</div>
                </td>
                <td className="num"><Link to={`/purchasing/orders?supplierId=${s.id}`}>{s.orderCount}</Link></td>
                <td className="num">{formatMoney(s.totalPurchased)}</td>
                {canEdit && (
                  <td className="actions">
                    <button className="btn ghost" onClick={() => setEditing(s)} aria-label={`Sửa ${s.name}`}><i className="ti ti-pencil" aria-hidden="true" /></button>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data} unit="nhà cung cấp" onPageChange={setPage} />

      {editing && (
        <SupplierFormModal supplier={editing === 'new' ? null : editing} onClose={() => setEditing(null)}
          onSaved={(saved, isNew) => { setEditing(null); setMessage(isNew ? `Đã thêm ${saved.name} (${saved.code}).` : 'Đã lưu nhà cung cấp.'); load() }} />
      )}
    </PurchasingLayout>
  )
}
