import { useEffect, useRef, useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { accountingApi } from '../../api/phase2Api'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import ModuleLayout from '../../layouts/ModuleLayout'
import { formatDateOnly, formatMoney, todayIso } from '../../utils/format'

const MENU = [
  { to: '/accounting', icon: 'chart-line', label: 'Tổng quan', end: true },
  { to: '/accounting/vouchers', icon: 'receipt', label: 'Thu chi' },
  { to: '/accounting/cashbook', icon: 'book', label: 'Sổ quỹ' },
  { to: '/accounting/receivables', icon: 'user-dollar', label: 'Công nợ khách' },
  { to: '/accounting/payables', icon: 'building-factory-2', label: 'Công nợ NCC' },
]

export function AccountingLayout({ children }) {
  return <ModuleLayout title="Kế toán" icon="calculator" color="#534AB7" menu={MENU}>{children}</ModuleLayout>
}

export function useAccountingLookups() {
  const [lookups, setLookups] = useState({ bankAccounts: [], categories: [], paymentMethods: [] })
  const reload = () => accountingApi.lookups().then(setLookups).catch(() => {})
  useEffect(() => { reload() }, [])
  return { ...lookups, reload }
}

/** Ô tìm khách hàng / nhà cung cấp, hiện kèm số còn nợ. value = { id, name, due } */
function PartnerSearch({ kind, value, onChange }) {
  const [text, setText] = useState(value?.name ?? '')
  const [items, setItems] = useState([])
  const [open, setOpen] = useState(false)
  const ref = useRef(null)
  useEffect(() => {
    if (!open) return
    const t = setTimeout(() => accountingApi.partners(kind, text).then(setItems).catch(() => setItems([])), 200)
    return () => clearTimeout(t)
  }, [text, open, kind])
  useEffect(() => {
    const onClick = (e) => ref.current && !ref.current.contains(e.target) && setOpen(false)
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [])
  return (
    <div className="picker" ref={ref}>
      <input value={text} placeholder={kind === 'supplier' ? 'Tìm nhà cung cấp' : 'Tìm khách hàng: tên, mã, SĐT'} role="combobox" aria-expanded={open}
        onFocus={() => setOpen(true)} onChange={(e) => { setText(e.target.value); setOpen(true); if (value) onChange(null) }} />
      {open && (
        <ul className="picker-list" role="listbox">
          {items.length === 0 && <li className="muted">Không tìm thấy</li>}
          {items.map((p) => (
            <li key={p.id} role="option" aria-selected={value?.id === p.id} onMouseDown={() => { onChange(p); setText(p.name); setOpen(false) }}>
              <div className="sku-row"><div><b>{p.name}</b><div className="muted small">{p.code}{p.phone ? ` · ${p.phone}` : ''}</div></div>
                <span className={p.due > 0 ? 'warn-text' : 'muted small'}>{p.due > 0 ? `Nợ ${formatMoney(p.due)}` : 'Không nợ'}</span></div>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

/**
 * Lập phiếu thu / chi.
 * preset: { type, category, partner: { id, name, due }, docId } - mở từ trang công nợ.
 */
export function VoucherModal({ lookups, preset, onClose, onSaved }) {
  const [type, setType] = useState(preset?.type ?? 'receipt')
  const [category, setCategory] = useState(preset?.category ?? (preset?.type === 'payment' ? 'rent' : 'customer'))
  const [partner, setPartner] = useState(preset?.partner ?? null)
  const [docs, setDocs] = useState([])
  const [docId, setDocId] = useState(preset?.docId ? String(preset.docId) : '')
  const [fund, setFund] = useState('cash')
  const [form, setForm] = useState({ amount: preset?.partner?.due ?? 0, date: todayIso(), reason: '', personName: '', reference: '' })
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const cats = lookups.categories.filter((c) => c.type === type && c.code !== 'cod' && c.code !== 'refund')
  const needsPartner = category === 'customer' || category === 'supplier'
  const kind = category === 'supplier' ? 'supplier' : 'customer'

  useEffect(() => {
    if (!partner || !needsPartner) { setDocs([]); return }
    const load = kind === 'supplier' ? accountingApi.supplierDocs : accountingApi.customerDocs
    load(partner.id).then(setDocs).catch(() => setDocs([]))
  }, [partner, needsPartner, kind])

  const selectedDoc = docs.find((d) => String(d.id) === docId)
  const maxAmount = selectedDoc?.due ?? docs.reduce((s, d) => s + d.due, 0)
  const switchType = (t) => { setType(t); setCategory(t === 'receipt' ? 'customer' : 'supplier'); setPartner(null); setDocId('') }

  const save = async (e) => {
    e.preventDefault()
    setError('')
    if (needsPartner && !partner) return setError(kind === 'supplier' ? 'Chọn nhà cung cấp.' : 'Chọn khách hàng.')
    const catName = cats.find((c) => c.code === category)?.name ?? ''
    const reason = form.reason.trim() || (partner ? `${catName} - ${partner.name}` : catName)
    setBusy(true)
    try {
      const r = await accountingApi.createVoucher({
        type, category, bankAccountId: fund === 'cash' ? null : Number(fund), method: fund === 'cash' ? 'cash' : 'bank_transfer',
        partnerId: partner?.id ?? null, salesOrderId: kind === 'customer' && docId ? Number(docId) : null,
        purchaseOrderId: kind === 'supplier' && docId ? Number(docId) : null, amount: Number(form.amount), date: form.date, reason,
        personName: form.personName || null, reference: form.reference || null,
      })
      onSaved(r.vouchers)
    } catch (err) {
      setError(getErrorMessage(err))
      setBusy(false)
    }
  }

  return (
    <Modal title={type === 'receipt' ? 'Lập phiếu thu' : 'Lập phiếu chi'} onClose={onClose}>
      <form onSubmit={save}>
        <div className="segmented" role="radiogroup" aria-label="Loại phiếu">
          {[['receipt', 'Phiếu thu', 'arrow-down-left'], ['payment', 'Phiếu chi', 'arrow-up-right']].map(([v, l, i]) => (
            <button type="button" key={v} role="radio" aria-checked={type === v} className={type === v ? 'on' : ''} onClick={() => switchType(v)}>
              <i className={`ti ti-${i}`} aria-hidden="true" /> {l}
            </button>
          ))}
        </div>
        <div className="form-grid">
          <label>Nội dung
            <select value={category} onChange={(e) => { setCategory(e.target.value); setPartner(null); setDocId('') }}>
              {cats.map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}
            </select>
          </label>
          <label>Quỹ
            <select value={fund} onChange={(e) => setFund(e.target.value)}>
              <option value="cash">Tiền mặt</option>
              {lookups.bankAccounts.filter((b) => b.isActive).map((b) => <option key={b.id} value={b.id}>{b.bankName} - {b.accountNo}</option>)}
            </select>
          </label>
          {needsPartner && (
            <>
              <label className="span2">{kind === 'supplier' ? 'Nhà cung cấp *' : 'Khách hàng *'}
                <PartnerSearch kind={kind} value={partner} onChange={(p) => { setPartner(p); setDocId(''); if (p) setForm((f) => ({ ...f, amount: p.due })) }} />
              </label>
              {partner && (
                <label className="span2">{kind === 'supplier' ? 'Trả cho đơn nhập' : 'Thu cho đơn hàng'}
                  <select value={docId} onChange={(e) => { setDocId(e.target.value); const d = docs.find((x) => String(x.id) === e.target.value); setForm((f) => ({ ...f, amount: d ? d.due : partner.due })) }}>
                    <option value="">Tự trừ vào các đơn cũ nhất trước ({docs.length} đơn còn nợ)</option>
                    {docs.map((d) => <option key={d.id} value={d.id}>{d.docNo} · {formatDateOnly(d.date)} · còn {formatMoney(d.due)}</option>)}
                  </select>
                </label>
              )}
            </>
          )}
          <label>Số tiền *
            <MoneyInput value={form.amount} onChange={(v) => setForm({ ...form, amount: v })} />
            {needsPartner && partner && <span className="hint-inline">Tối đa {formatMoney(maxAmount)}</span>}
          </label>
          <label>Ngày<input type="date" value={form.date} onChange={(e) => setForm({ ...form, date: e.target.value })} /></label>
          <label className="span2">Diễn giải<input value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} placeholder="Để trống sẽ tự ghi theo nội dung" /></label>
          <label>{type === 'receipt' ? 'Người nộp' : 'Người nhận'}<input value={form.personName} onChange={(e) => setForm({ ...form, personName: e.target.value })} /></label>
          {fund !== 'cash' && <label>Mã giao dịch<input value={form.reference} onChange={(e) => setForm({ ...form, reference: e.target.value })} /></label>}
        </div>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot">
          <button type="button" className="btn" onClick={onClose}>Hủy</button>
          <button className="btn primary" disabled={busy || !(form.amount > 0)}>{busy ? 'Đang ghi...' : 'Ghi sổ'}</button>
        </div>
      </form>
    </Modal>
  )
}

/** Thêm / sửa tài khoản ngân hàng của công ty. */
export function BankAccountModal({ bank, onClose, onSaved }) {
  const [form, setForm] = useState({ bankName: bank?.bankName ?? '', bankBranch: bank?.bankBranch ?? '', accountNo: bank?.accountNo ?? '', accountName: bank?.accountName ?? '', isActive: bank?.isActive ?? true })
  const [error, setError] = useState('')
  const save = async (e) => {
    e.preventDefault()
    try { onSaved(bank ? await accountingApi.updateBank(bank.id, form) : await accountingApi.createBank(form)) } catch (err) { setError(getErrorMessage(err)) }
  }
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })
  return (
    <Modal title={bank ? 'Sửa tài khoản ngân hàng' : 'Thêm tài khoản ngân hàng'} onClose={onClose} size="small">
      <form onSubmit={save}>
        <label>Ngân hàng *<input value={form.bankName} onChange={u('bankName')} autoFocus placeholder="Vietcombank" /></label>
        <label>Chi nhánh<input value={form.bankBranch} onChange={u('bankBranch')} /></label>
        <label>Số tài khoản *<input value={form.accountNo} onChange={u('accountNo')} /></label>
        <label>Chủ tài khoản *<input value={form.accountName} onChange={u('accountName')} /></label>
        {bank && <label className="check"><input type="checkbox" checked={form.isActive} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} /> Đang dùng</label>}
        {error && <p className="error">{error}</p>}
        <div className="modal-foot"><button type="button" className="btn" onClick={onClose}>Hủy</button><button className="btn primary">Lưu</button></div>
      </form>
    </Modal>
  )
}
