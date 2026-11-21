import { Fragment, useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { accountingApi } from '../../api/phase2Api'
import Pagination from '../../components/Pagination'
import { PHASE2_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateOnly, formatMoney, todayIso } from '../../utils/format'
import { AccountingLayout, BankAccountModal, useAccountingLookups, VoucherModal } from './AccountingShared'

const monthStart = (offset = 0) => { const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() + offset); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10) }
const monthEnd = (offset = 0) => { const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() + offset + 1); d.setDate(0); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10) }
const daysAgo = (n) => { const d = new Date(); d.setDate(d.getDate() - n); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10) }
const PERIODS = [
  { label: 'Tháng này', from: () => monthStart(0), to: () => todayIso() },
  { label: 'Tháng trước', from: () => monthStart(-1), to: () => monthEnd(-1) },
  { label: '30 ngày', from: () => daysAgo(29), to: () => todayIso() },
  { label: '90 ngày', from: () => daysAgo(89), to: () => todayIso() },
]

function PeriodPicker({ range, onChange }) {
  return (
    <div className="toolbar">
      <div className="segmented no-margin">
        {PERIODS.map((p) => {
          const on = range.from === p.from() && range.to === p.to()
          return <button key={p.label} className={on ? 'on' : ''} onClick={() => onChange({ from: p.from(), to: p.to() })}>{p.label}</button>
        })}
      </div>
      <input type="date" className="date-input" value={range.from} onChange={(e) => onChange({ ...range, from: e.target.value })} aria-label="Từ ngày" />
      <input type="date" className="date-input" value={range.to} onChange={(e) => onChange({ ...range, to: e.target.value })} aria-label="Đến ngày" />
    </div>
  )
}

/** Tổng quan: lãi lỗ trong kỳ, dòng tiền, số dư quỹ, công nợ. */
export function AccountingOverviewPage() {
  const [range, setRange] = useState({ from: monthStart(0), to: todayIso() })
  const [d, setD] = useState(null)
  const [error, setError] = useState('')
  useEffect(() => { accountingApi.overview(range).then(setD).catch((e) => setError(getErrorMessage(e))) }, [range])
  const pct = (v) => (d?.netRevenue ? ` (${Math.round((v / d.netRevenue) * 100)}%)` : '')

  return (
    <AccountingLayout>
      <div className="page-head"><h1>Tổng quan tài chính</h1></div>
      <PeriodPicker range={range} onChange={setRange} />
      {error && <div className="alert error">{error}</div>}
      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Doanh thu thuần</span><b>{d ? formatMoney(d.netRevenue) : '…'}</b></div>
        <div className="kpi"><span className="muted small">Lãi gộp</span><b>{d ? formatMoney(Math.round(d.grossProfit)) : '…'}</b><span className="small muted">{d && pct(d.grossProfit)}</span></div>
        <div className="kpi"><span className="muted small">Chi phí hoạt động</span><b className="money-out">{d ? formatMoney(d.totalExpense) : '…'}</b></div>
        <div className="kpi"><span className="muted small">Lợi nhuận</span><b className={d && d.netProfit < 0 ? 'money-out' : 'ok-text'}>{d ? formatMoney(Math.round(d.netProfit)) : '…'}</b><span className="small muted">{d && pct(d.netProfit)}</span></div>
      </div>
      <div className="two-col">
        <div className="card">
          <div className="section-head first"><h2>Báo cáo lãi lỗ</h2></div>
          {d && (
            <table className="pnl">
              <tbody>
                <tr><td>Doanh thu bán hàng</td><td className="num">{formatMoney(d.revenue)}</td></tr>
                <tr className="sub"><td>Hàng bán bị trả lại</td><td className="num">-{formatMoney(d.returns)}</td></tr>
                <tr><td><b>Doanh thu thuần</b></td><td className="num"><b>{formatMoney(d.netRevenue)}</b></td></tr>
                <tr className="sub"><td>Giá vốn hàng bán</td><td className="num">-{formatMoney(Math.round(d.cogs))}</td></tr>
                <tr><td><b>Lãi gộp</b></td><td className="num"><b>{formatMoney(Math.round(d.grossProfit))}</b></td></tr>
                {d.expenses.map((e) => <tr key={e.name} className="sub"><td>{e.name}</td><td className="num">-{formatMoney(e.value)}</td></tr>)}
                {d.expenses.length === 0 && <tr className="sub"><td>Chưa có khoản chi phí nào</td><td /></tr>}
                <tr className="total"><td>Lợi nhuận</td><td className={`num ${d.netProfit < 0 ? 'money-out' : 'ok-text'}`}>{formatMoney(Math.round(d.netProfit))}</td></tr>
              </tbody>
            </table>
          )}
          <p className="hint-inline top-gap">Chi phí lấy từ phiếu chi (thuê mặt bằng, lương, quảng cáo, ship...). Trả tiền nhà cung cấp là mua hàng, đã tính vào giá vốn.</p>
        </div>
        <div>
          <div className="card">
            <div className="section-head first"><h2>Tiền hiện có</h2><Link className="small" to="/accounting/cashbook">Sổ quỹ</Link></div>
            <div className="fund-list">
              {d?.funds.map((f) => <div key={f.key} className="fund-row"><span>{f.name}</span><b>{formatMoney(f.balance)}</b></div>)}
              {d && <div className="fund-row sum-row total"><span>Tổng</span><b>{formatMoney(d.funds.reduce((s, f) => s + f.balance, 0))}</b></div>}
            </div>
          </div>
          <div className="card">
            <div className="section-head first"><h2>Dòng tiền trong kỳ</h2></div>
            <div className="fund-row"><span>Tiền vào</span><b className="money-in">+{formatMoney(d?.cashIn ?? 0)}</b></div>
            <div className="fund-row top-gap"><span>Tiền ra</span><b className="money-out">-{formatMoney(d?.cashOut ?? 0)}</b></div>
            <p />
          </div>
          <div className="card">
            <div className="fund-row"><span>Khách còn nợ</span><Link to="/accounting/receivables"><b className="warn-text">{formatMoney(d?.receivable ?? 0)}</b></Link></div>
            <div className="fund-row top-gap"><span>Còn nợ nhà cung cấp</span><Link to="/accounting/payables"><b>{formatMoney(d?.payable ?? 0)}</b></Link></div>
            <p />
          </div>
        </div>
      </div>
    </AccountingLayout>
  )
}

/** Danh sách phiếu thu / chi. */
export function VouchersPage() {
  const { can } = useAuth()
  const lookups = useAccountingLookups()
  const [data, setData] = useState(null)
  const [filters, setFilters] = useState({ type: '', category: '', fund: '', from: monthStart(0), to: todayIso(), search: '' })
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [creating, setCreating] = useState(null)

  const load = useCallback(async () => {
    try { setError(''); setData(await accountingApi.vouchers({ ...filters, page, pageSize: 30 })) } catch (e) { setError(getErrorMessage(e)) }
  }, [filters, page])
  useEffect(() => { const t = setTimeout(load, 250); return () => clearTimeout(t) }, [load])
  const setFilter = (f, v) => { setFilters({ ...filters, [f]: v }); setPage(1) }

  const cancel = async (v) => {
    if (!window.confirm(`Hủy phiếu ${v.docNo}? Số tiền sẽ bị trừ khỏi sổ quỹ${v.sourceDocNo ? ` và trả lại công nợ của ${v.sourceDocNo}` : ''}.`)) return
    try { await accountingApi.cancelVoucher(v.id); setMessage(`Đã hủy phiếu ${v.docNo}.`); load(); lookups.reload() } catch (e) { setError(getErrorMessage(e)) }
  }
  const s = data?.summary

  return (
    <AccountingLayout>
      <div className="page-head">
        <h1>Phiếu thu chi</h1>
        {can(PHASE2_PERMISSIONS.ACCOUNTING_CREATE) && (
          <div className="head-actions">
            <button className="btn primary" onClick={() => setCreating({ type: 'receipt' })}><i className="ti ti-arrow-down-left" aria-hidden="true" /> Lập phiếu thu</button>
            <button className="btn" onClick={() => setCreating({ type: 'payment', category: 'rent' })}><i className="ti ti-arrow-up-right" aria-hidden="true" /> Lập phiếu chi</button>
          </div>
        )}
      </div>
      {message && <div className="alert success">{message}</div>}
      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Tổng thu</span><b className="money-in">{s ? formatMoney(s.totalReceipt) : '…'}</b></div>
        <div className="kpi"><span className="muted small">Tổng chi</span><b className="money-out">{s ? formatMoney(s.totalPayment) : '…'}</b></div>
        <div className="kpi"><span className="muted small">Chênh lệch</span><b>{s ? formatMoney(s.net) : '…'}</b></div>
      </div>
      <div className="toolbar">
        <div className="segmented no-margin">
          {[['', 'Tất cả'], ['receipt', 'Thu'], ['payment', 'Chi']].map(([v, l]) => <button key={v} className={filters.type === v ? 'on' : ''} onClick={() => { setFilters({ ...filters, type: v, category: '' }); setPage(1) }}>{l}</button>)}
        </div>
        <select value={filters.category} onChange={(e) => setFilter('category', e.target.value)} aria-label="Nội dung">
          <option value="">Mọi nội dung</option>
          {lookups.categories.filter((c) => !filters.type || c.type === filters.type).map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}
        </select>
        <select value={filters.fund} onChange={(e) => setFilter('fund', e.target.value)} aria-label="Quỹ">
          <option value="">Mọi quỹ</option>
          <option value="cash">Tiền mặt</option>
          {lookups.bankAccounts.map((b) => <option key={b.id} value={b.id}>{b.bankName}</option>)}
        </select>
      </div>
      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm số phiếu, diễn giải, đối tượng" value={filters.search} onChange={(e) => setFilter('search', e.target.value)} aria-label="Tìm phiếu" />
        </div>
        <input type="date" className="date-input" value={filters.from} onChange={(e) => setFilter('from', e.target.value)} aria-label="Từ ngày" />
        <input type="date" className="date-input" value={filters.to} onChange={(e) => setFilter('to', e.target.value)} aria-label="Đến ngày" />
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Số phiếu</th><th>Diễn giải</th><th className="hide-sm">Quỹ</th><th className="num">Số tiền</th><th className="actions" /></tr></thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.rows.items.length === 0 && <tr><td colSpan={5} className="muted center">Không có phiếu nào trong kỳ.</td></tr>}
            {data?.rows.items.map((v) => (
              <tr key={v.id} className={v.status === 'cancelled' ? 'inactive' : ''}>
                <td><b>{v.docNo}</b><div className="muted small">{formatDateOnly(v.date)} · {v.categoryName}</div></td>
                <td>{v.reason}
                  <div className="muted small">{v.partnerName ?? v.personName}
                    {v.sourceDocNo && <> · <Link to={v.sourceType === 'order' ? `/orders/${v.sourceId}` : `/purchasing/orders/${v.sourceId}`}>{v.sourceDocNo}</Link></>}
                    {v.status === 'cancelled' && <span className="pill cancelled small-pill">Đã hủy</span>}</div></td>
                <td className="hide-sm">{v.fundName}</td>
                <td className="num"><b className={v.type === 'receipt' ? 'money-in' : 'money-out'}>{v.type === 'receipt' ? '+' : '-'}{formatMoney(v.amount)}</b></td>
                <td className="actions">
                  {v.status === 'posted' && can(PHASE2_PERMISSIONS.ACCOUNTING_EDIT) && !['cod', 'refund'].includes(v.category) && (
                    <button className="btn ghost danger" onClick={() => cancel(v)} aria-label={`Hủy ${v.docNo}`} title="Hủy phiếu"><i className="ti ti-ban" aria-hidden="true" /></button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data?.rows} unit="phiếu" onPageChange={setPage} />
      {creating && (
        <VoucherModal lookups={lookups} preset={creating} onClose={() => setCreating(null)}
          onSaved={(vs) => { setCreating(null); setMessage(`Đã ghi sổ ${vs.map((v) => v.docNo).join(', ')}.`); load(); lookups.reload() }} />
      )}
    </AccountingLayout>
  )
}

/** Sổ quỹ tiền mặt / ngân hàng: tồn đầu, thu, chi, tồn cuối từng ngày. */
export function CashBookPage() {
  const { can } = useAuth()
  const lookups = useAccountingLookups()
  const [fund, setFund] = useState('cash')
  const [range, setRange] = useState({ from: monthStart(0), to: todayIso() })
  const [book, setBook] = useState(null)
  const [error, setError] = useState('')
  const [editingBank, setEditingBank] = useState(null)

  const load = useCallback(() => accountingApi.cashbook({ fund, ...range }).then(setBook).catch((e) => setError(getErrorMessage(e))), [fund, range])
  useEffect(() => { load() }, [load])

  return (
    <AccountingLayout>
      <div className="page-head"><h1>Sổ quỹ</h1></div>
      <div className="kpi-row">
        {book?.funds.map((f) => (
          <button key={f.key} type="button" className={`kpi clickable-kpi${fund === f.key ? ' on-accent' : ''}`} onClick={() => setFund(f.key)}>
            <span className="muted small">{f.name}</span><b>{formatMoney(f.balance)}</b>
          </button>
        ))}
      </div>
      <PeriodPicker range={range} onChange={setRange} />
      {error && <div className="alert error">{error}</div>}
      {book && (
        <>
          <div className="kpi-row">
            <div className="kpi"><span className="muted small">Tồn đầu kỳ</span><b>{formatMoney(book.opening)}</b></div>
            <div className="kpi"><span className="muted small">Thu trong kỳ</span><b className="money-in">+{formatMoney(book.totalIn)}</b></div>
            <div className="kpi"><span className="muted small">Chi trong kỳ</span><b className="money-out">-{formatMoney(book.totalOut)}</b></div>
            <div className="kpi"><span className="muted small">Tồn cuối kỳ</span><b>{formatMoney(book.closing)}</b></div>
          </div>
          <div className="table-wrap">
            <table className="grid">
              <thead><tr><th>Ngày</th><th>Số phiếu</th><th>Diễn giải</th><th className="num">Thu</th><th className="num">Chi</th><th className="num">Tồn</th></tr></thead>
              <tbody>
                <tr className="total-row"><td colSpan={5}><b>Tồn đầu kỳ {book.fundName}</b></td><td className="num"><b>{formatMoney(book.opening)}</b></td></tr>
                {book.rows.length === 0 && <tr><td colSpan={6} className="muted center">Không có phát sinh trong kỳ.</td></tr>}
                {book.rows.map((r) => (
                  <tr key={r.id}>
                    <td>{formatDateOnly(r.date)}</td><td className="code">{r.docNo}</td>
                    <td>{r.reason}<div className="muted small">{r.partnerName}</div></td>
                    <td className="num money-in">{r.in ? formatMoney(r.in) : ''}</td>
                    <td className="num money-out">{r.out ? formatMoney(r.out) : ''}</td>
                    <td className="num">{formatMoney(r.balance)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      <div className="section-head"><h2>Tài khoản ngân hàng</h2>
        {can(PHASE2_PERMISSIONS.ACCOUNTING_EDIT) && <button className="btn" onClick={() => setEditingBank('new')}><i className="ti ti-plus" aria-hidden="true" /> Thêm tài khoản</button>}
      </div>
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Ngân hàng</th><th>Số tài khoản</th><th className="num">Số dư</th><th className="actions" /></tr></thead>
          <tbody>
            {lookups.bankAccounts.map((b) => (
              <tr key={b.id} className={b.isActive ? '' : 'inactive'}>
                <td>{b.bankName}<div className="muted small">{b.bankBranch}</div></td>
                <td className="code">{b.accountNo}<div className="muted small">{b.accountName}</div></td>
                <td className="num">{formatMoney(b.balance)}</td>
                <td className="actions">{can(PHASE2_PERMISSIONS.ACCOUNTING_EDIT) && <button className="btn ghost" onClick={() => setEditingBank(b)} aria-label={`Sửa ${b.bankName}`}><i className="ti ti-pencil" aria-hidden="true" /></button>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {editingBank && <BankAccountModal bank={editingBank === 'new' ? null : editingBank} onClose={() => setEditingBank(null)} onSaved={() => { setEditingBank(null); lookups.reload(); load() }} />}
    </AccountingLayout>
  )
}

/** Công nợ khách hàng (kind=receivable) hoặc nhà cung cấp (kind=payable). */
export function DebtsPage({ kind }) {
  const { can } = useAuth()
  const lookups = useAccountingLookups()
  const isCustomer = kind === 'receivable'
  const [data, setData] = useState(null)
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const [open, setOpen] = useState(null)
  const [docs, setDocs] = useState([])
  const [paying, setPaying] = useState(null)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  const load = useCallback(async () => {
    try {
      setError('')
      setData(await (isCustomer ? accountingApi.receivables : accountingApi.payables)({ search, page, pageSize: 20 }))
    } catch (e) { setError(getErrorMessage(e)) }
  }, [isCustomer, search, page])
  useEffect(() => { const t = setTimeout(load, 250); return () => clearTimeout(t) }, [load])
  useEffect(() => { setOpen(null); setMessage('') }, [kind])

  const toggle = async (id) => {
    if (open === id) return setOpen(null)
    setOpen(id); setDocs([])
    setDocs(await (isCustomer ? accountingApi.customerDocs : accountingApi.supplierDocs)(id))
  }

  return (
    <AccountingLayout>
      <div className="page-head"><h1>{isCustomer ? 'Công nợ khách hàng' : 'Công nợ nhà cung cấp'}</h1></div>
      <div className="kpi-row">
        <div className="kpi"><span className="muted small">{isCustomer ? 'Tổng khách còn nợ' : 'Tổng còn nợ NCC'}</span><b className="warn-text">{data ? formatMoney(data.totalDue) : '…'}</b></div>
        <div className="kpi"><span className="muted small">{isCustomer ? 'Số khách đang nợ' : 'Số NCC đang nợ'}</span><b>{data?.partnerCount ?? '…'}</b></div>
      </div>
      {message && <div className="alert success">{message}</div>}
      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm tên, mã, SĐT" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} aria-label="Tìm" />
        </div>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>{isCustomer ? 'Khách hàng' : 'Nhà cung cấp'}</th><th className="num hide-sm">Tổng tiền</th><th className="num hide-sm">Đã {isCustomer ? 'thu' : 'trả'}</th><th className="num">Còn nợ</th><th className="actions" /></tr></thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.rows.items.length === 0 && <tr><td colSpan={5} className="muted center">Không còn công nợ.</td></tr>}
            {data?.rows.items.map((r) => (
              <Fragment key={r.partnerId}>
                <tr className="clickable" onClick={() => toggle(r.partnerId)}>
                  <td><i className={`ti ti-chevron-${open === r.partnerId ? 'down' : 'right'}`} aria-hidden="true" /> <b>{r.name}</b>
                    <div className="muted small">{r.code}{r.phone ? ` · ${r.phone}` : ''} · {r.docCount} đơn · nợ từ {formatDateOnly(r.oldestDate)}</div></td>
                  <td className="num hide-sm">{formatMoney(r.total)}</td>
                  <td className="num hide-sm">{formatMoney(r.paid)}</td>
                  <td className="num"><b className="warn-text">{formatMoney(r.due)}</b></td>
                  <td className="actions">
                    {can(PHASE2_PERMISSIONS.ACCOUNTING_CREATE) && (
                      <button className="btn primary" onClick={(e) => { e.stopPropagation(); setPaying({ type: isCustomer ? 'receipt' : 'payment', category: isCustomer ? 'customer' : 'supplier', partner: { id: r.partnerId, name: r.name, due: r.due } }) }}>
                        {isCustomer ? 'Thu tiền' : 'Trả tiền'}
                      </button>
                    )}
                  </td>
                </tr>
                {open === r.partnerId && docs.map((d) => (
                  <tr key={`d${d.id}`} className="sub-row">
                    <td style={{ paddingLeft: 36 }}><Link to={isCustomer ? `/orders/${d.id}` : `/purchasing/orders/${d.id}`}>{d.docNo}</Link> <span className="muted small">· {formatDateOnly(d.date)}</span></td>
                    <td className="num hide-sm muted">{formatMoney(d.total)}</td>
                    <td className="num hide-sm muted">{formatMoney(d.paid)}</td>
                    <td className="num">{formatMoney(d.due)}</td>
                    <td />
                  </tr>
                ))}
              </Fragment>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data?.rows} unit={isCustomer ? 'khách hàng' : 'nhà cung cấp'} onPageChange={setPage} />
      {paying && (
        <VoucherModal lookups={lookups} preset={paying} onClose={() => setPaying(null)}
          onSaved={(vs) => { setPaying(null); setOpen(null); setMessage(`Đã ghi sổ ${vs.map((v) => v.docNo).join(', ')}.`); load() }} />
      )}
    </AccountingLayout>
  )
}
