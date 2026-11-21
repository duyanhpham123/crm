import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { marketingApi } from '../../api/phase3Api'
import Modal from '../../components/Modal'
import MoneyInput from '../../components/MoneyInput'
import Pagination from '../../components/Pagination'
import { CAMPAIGN_STATUSES, campaignStatus, PHASE3_PERMISSIONS, PROMOTION_CSS, PROMOTION_STATES, PROMOTION_TYPES, SEGMENTS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import ModuleLayout from '../../layouts/ModuleLayout'
import { formatDateOnly, formatDateTime, formatMoney, formatMoneyShort, formatQty, todayIso } from '../../utils/format'

const MENU = [
  { to: '/marketing', icon: 'speakerphone', label: 'Chiến dịch', end: true },
  { to: '/marketing/promotions', icon: 'ticket', label: 'Mã giảm giá' },
  { to: '/marketing/segments', icon: 'users-group', label: 'Nhóm khách hàng' },
]

function MarketingLayout({ children }) {
  return <ModuleLayout title="Marketing" icon="speakerphone" color="#D85A30" menu={MENU}>{children}</ModuleLayout>
}

function useMarketingLookups() {
  const [l, setL] = useState({ channels: [], campaigns: [], salesChannels: [] })
  useEffect(() => { marketingApi.lookups().then(setL).catch(() => {}) }, [])
  return l
}

const roas = (v) => (v === null || v === undefined ? '-' : `${formatQty(v)}x`)

function CampaignFormModal({ campaign, lookups, onClose, onSaved }) {
  const isNew = !campaign
  const [form, setForm] = useState({
    name: campaign?.name ?? '', channel: campaign?.channel ?? 'facebook', startDate: campaign?.startDate ?? todayIso(), endDate: campaign?.endDate ?? '',
    budget: campaign?.budget ?? 5_000_000, targetLeads: campaign?.targetLeads ?? '', utmCampaign: campaign?.utmCampaign ?? '',
    status: campaign?.status ?? 'running', description: campaign?.description ?? '',
  })
  const [error, setError] = useState('')
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })
  const save = async (e) => {
    e.preventDefault()
    const body = { ...form, endDate: form.endDate || null, targetLeads: form.targetLeads === '' ? null : Number(form.targetLeads), utmCampaign: form.utmCampaign || null,
      description: form.description || null, budget: Number(form.budget) || 0, rowVersion: campaign?.rowVersion ?? null }
    try { onSaved(isNew ? await marketingApi.createCampaign(body) : await marketingApi.updateCampaign(campaign.id, body)) } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <Modal title={isNew ? 'Tạo chiến dịch' : `Sửa ${campaign.code}`} onClose={onClose}>
      <form onSubmit={save}>
        <div className="form-grid">
          <label className="span2">Tên chiến dịch *<input value={form.name} onChange={u('name')} autoFocus placeholder="Sale Black Friday 2026" /></label>
          <label>Kênh<select value={form.channel} onChange={u('channel')}>{lookups.channels.map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}</select></label>
          <label>Trạng thái<select value={form.status} onChange={u('status')}>{CAMPAIGN_STATUSES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}</select></label>
          <label>Bắt đầu<input type="date" value={form.startDate} onChange={u('startDate')} /></label>
          <label>Kết thúc<input type="date" value={form.endDate} onChange={u('endDate')} /></label>
          <label>Ngân sách<MoneyInput value={form.budget} onChange={(v) => setForm({ ...form, budget: v })} /></label>
          <label>Mục tiêu khách để lại thông tin<input type="number" min="0" value={form.targetLeads} onChange={u('targetLeads')} /></label>
          <label className="span2">Mô tả<textarea rows={2} value={form.description} onChange={u('description')} /></label>
        </div>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot"><button type="button" className="btn" onClick={onClose}>Hủy</button><button className="btn primary">Lưu</button></div>
      </form>
    </Modal>
  )
}

/** Danh sách chiến dịch: chi phí, lead, doanh thu từ mã giảm giá, ROAS. */
export function CampaignsPage() {
  const { can } = useAuth()
  const navigate = useNavigate()
  const lookups = useMarketingLookups()
  const [data, setData] = useState(null)
  const [status, setStatus] = useState('')
  const [page, setPage] = useState(1)
  const [creating, setCreating] = useState(false)
  const [error, setError] = useState('')
  useEffect(() => { marketingApi.campaigns({ status, page, pageSize: 20 }).then(setData).catch((e) => setError(getErrorMessage(e))) }, [status, page])
  const s = data?.summary
  const channelName = (c) => lookups.channels.find((x) => x.code === c)?.name ?? c

  return (
    <MarketingLayout>
      <div className="page-head">
        <h1>Chiến dịch marketing</h1>
        {can(PHASE3_PERMISSIONS.MARKETING_CREATE) && <button className="btn primary" onClick={() => setCreating(true)}><i className="ti ti-plus" aria-hidden="true" /> Tạo chiến dịch</button>}
      </div>
      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Đang chạy</span><b>{s?.running ?? '…'}</b></div>
        <div className="kpi"><span className="muted small">Tổng chi phí quảng cáo</span><b className="money-out">{s ? formatMoney(s.totalSpend) : '…'}</b></div>
        <div className="kpi"><span className="muted small">Doanh thu từ mã chiến dịch</span><b className="ok-text">{s ? formatMoney(s.totalRevenue) : '…'}</b></div>
        <div className="kpi"><span className="muted small">ROAS (doanh thu / chi phí) · lead</span><b>{s ? `${roas(s.roas)} · ${s.totalLeads}` : '…'}</b></div>
      </div>
      <div className="toolbar">
        <div className="segmented no-margin">
          {[{ value: '', label: 'Tất cả' }, ...CAMPAIGN_STATUSES].map((x) => <button key={x.value} className={status === x.value ? 'on' : ''} onClick={() => { setStatus(x.value); setPage(1) }}>{x.label}</button>)}
        </div>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Chiến dịch</th><th className="num">Chi phí / ngân sách</th><th className="num hide-sm">Lead</th><th className="num">Doanh thu</th><th className="num hide-sm">ROAS</th><th>Trạng thái</th></tr></thead>
          <tbody>
            {!data && <tr><td colSpan={6} className="muted center">Đang tải...</td></tr>}
            {data?.rows.items.length === 0 && <tr><td colSpan={6} className="muted center">Chưa có chiến dịch.</td></tr>}
            {data?.rows.items.map((c) => (
              <tr key={c.id} className="clickable" onClick={() => navigate(`/marketing/campaigns/${c.id}`)}>
                <td><Link to={`/marketing/campaigns/${c.id}`} onClick={(e) => e.stopPropagation()}>{c.name}</Link>
                  <div className="muted small">{c.code} · {channelName(c.channel)} · {formatDateOnly(c.startDate)}{c.endDate ? ` → ${formatDateOnly(c.endDate)}` : ''}</div></td>
                <td className="num">{formatMoneyShort(c.actualCost)}<div className="muted small">/ {formatMoneyShort(c.budget)}</div></td>
                <td className="num hide-sm">{c.leads}{c.costPerLead ? <div className="muted small">{formatMoneyShort(c.costPerLead)}/lead</div> : null}</td>
                <td className="num">{formatMoneyShort(c.revenue)}<div className="muted small">{c.orders} đơn</div></td>
                <td className="num hide-sm"><b className={c.roas >= 3 ? 'ok-text' : c.roas !== null && c.roas < 1 ? 'money-out' : ''}>{roas(c.roas)}</b></td>
                <td><span className={`pill ${campaignStatus(c.status).css}`}>{campaignStatus(c.status).label}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data?.rows} unit="chiến dịch" onPageChange={setPage} />
      {creating && <CampaignFormModal lookups={lookups} onClose={() => setCreating(false)} onSaved={(c) => navigate(`/marketing/campaigns/${c.id}`)} />}
    </MarketingLayout>
  )
}

/** Chi tiết chiến dịch: hiệu quả, nhập số liệu theo ngày, mã giảm giá gắn chiến dịch. */
export function CampaignDetailPage() {
  const { id } = useParams()
  const { can } = useAuth()
  const lookups = useMarketingLookups()
  const [c, setC] = useState(null)
  const [stat, setStat] = useState({ date: todayIso(), impressions: '', clicks: '', spend: 0, leads: '' })
  const [editing, setEditing] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  useEffect(() => { marketingApi.campaign(id).then(setC).catch((e) => setError(getErrorMessage(e))) }, [id])
  if (!c) return <MarketingLayout>{error ? <div className="alert error">{error}</div> : <p className="muted">Đang tải...</p>}</MarketingLayout>
  const canEdit = can(PHASE3_PERMISSIONS.MARKETING_EDIT)
  const budgetPct = c.budget ? Math.round((c.actualCost / c.budget) * 100) : 0

  const saveStat = async (e) => {
    e.preventDefault(); setError('')
    try {
      setC(await marketingApi.setStat(c.id, { date: stat.date, impressions: Number(stat.impressions) || 0, clicks: Number(stat.clicks) || 0, spend: Number(stat.spend) || 0, leads: Number(stat.leads) || 0 }))
      setMessage(`Đã lưu số liệu ngày ${formatDateOnly(stat.date)}.`)
    } catch (err) { setError(getErrorMessage(err)) }
  }

  return (
    <MarketingLayout>
      <div className="breadcrumb"><Link to="/marketing">Chiến dịch</Link> / {c.code}</div>
      <div className="page-head">
        <div><h1>{c.name} <span className={`pill ${campaignStatus(c.status).css} small-pill`}>{campaignStatus(c.status).label}</span></h1>
          <div className="muted small">{lookups.channels.find((x) => x.code === c.channel)?.name} · {formatDateOnly(c.startDate)}{c.endDate ? ` → ${formatDateOnly(c.endDate)}` : ''}</div></div>
        {canEdit && <button className="btn" onClick={() => setEditing(true)}><i className="ti ti-pencil" aria-hidden="true" /> Sửa</button>}
      </div>
      {message && <div className="alert success">{message}</div>}
      {error && <div className="alert error">{error}</div>}
      <div className="kpi-row">
        <div className="kpi"><span className="muted small">Chi phí / ngân sách</span><b>{formatMoney(c.actualCost)}</b>
          <div className="hbar-track"><div className="hbar-fill" style={{ width: `${Math.min(100, budgetPct)}%`, background: budgetPct > 100 ? 'var(--danger)' : undefined }} /></div>
          <span className="small muted">{budgetPct}% của {formatMoney(c.budget)}</span></div>
        <div className="kpi"><span className="muted small">Hiển thị · click · CTR</span><b>{formatQty(c.impressions)}</b><span className="small muted">{formatQty(c.clicks)} click · CTR {c.ctr ?? 0}%</span></div>
        <div className="kpi"><span className="muted small">Khách để lại thông tin</span><b>{c.leads}{c.targetLeads ? ` / ${c.targetLeads}` : ''}</b><span className="small muted">{c.costPerLead ? `${formatMoney(c.costPerLead)} / lead` : ''}</span></div>
        <div className="kpi"><span className="muted small">Doanh thu · ROAS</span><b className="ok-text">{formatMoney(c.revenue)}</b><span className="small muted">{c.orders} đơn · ROAS {roas(c.roas)}</span></div>
      </div>
      <div className="two-col">
        <div className="card">
          <div className="section-head first"><h2>Số liệu theo ngày</h2></div>
          {canEdit && (
            <form className="form-grid" onSubmit={saveStat}>
              <label>Ngày<input type="date" value={stat.date} max={todayIso()} onChange={(e) => setStat({ ...stat, date: e.target.value })} /></label>
              <label>Chi phí<MoneyInput value={stat.spend} onChange={(v) => setStat({ ...stat, spend: v })} /></label>
              <label>Lượt hiển thị<input type="number" min="0" value={stat.impressions} onChange={(e) => setStat({ ...stat, impressions: e.target.value })} /></label>
              <label>Lượt click<input type="number" min="0" value={stat.clicks} onChange={(e) => setStat({ ...stat, clicks: e.target.value })} /></label>
              <label>Lead (khách nhắn tin / để số)<input type="number" min="0" value={stat.leads} onChange={(e) => setStat({ ...stat, leads: e.target.value })} /></label>
              <div><button className="btn primary top-gap">Lưu số liệu ngày</button></div>
            </form>
          )}
          <div className="table-wrap scroll-y">
            <table className="grid compact">
              <thead><tr><th>Ngày</th><th className="num">Chi phí</th><th className="num">Hiển thị</th><th className="num">Click</th><th className="num">Lead</th></tr></thead>
              <tbody>
                {c.stats.length === 0 && <tr><td colSpan={5} className="muted center">Chưa nhập số liệu.</td></tr>}
                {c.stats.map((s) => (
                  <tr key={s.date} className={canEdit ? 'clickable' : ''} onClick={() => canEdit && setStat({ date: s.date, impressions: s.impressions, clicks: s.clicks, spend: s.spend, leads: s.leads })}>
                    <td>{formatDateOnly(s.date)}</td><td className="num">{formatMoney(s.spend)}</td><td className="num">{formatQty(s.impressions)}</td><td className="num">{formatQty(s.clicks)}</td><td className="num">{s.leads}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
        <div className="card">
          <div className="section-head first"><h2>Mã giảm giá của chiến dịch</h2><Link className="small" to="/marketing/promotions">Quản lý mã</Link></div>
          <p className="hint-inline">Doanh thu chiến dịch = đơn hàng dùng các mã dưới đây.</p>
          <table className="grid compact">
            <thead><tr><th>Mã</th><th className="num">Đã dùng</th><th className="num">Doanh thu</th></tr></thead>
            <tbody>
              {c.promotions.length === 0 && <tr><td colSpan={3} className="muted center">Chưa gắn mã nào. Tạo mã và chọn chiến dịch này.</td></tr>}
              {c.promotions.map((p) => <tr key={p.id}><td><b className="code">{p.code}</b><div className="muted small">{p.name}</div></td><td className="num">{p.usedCount}</td><td className="num">{formatMoney(p.revenue)}</td></tr>)}
            </tbody>
          </table>
          <p />
        </div>
      </div>
      {editing && <CampaignFormModal campaign={c} lookups={lookups} onClose={() => setEditing(false)} onSaved={(r) => { setC(r); setEditing(false); setMessage('Đã lưu chiến dịch.') }} />}
    </MarketingLayout>
  )
}

const toLocalInput = (iso) => (iso ? iso.slice(0, 16) : '')

function PromotionFormModal({ promo, lookups, onClose, onSaved }) {
  const isNew = !promo
  const now = new Date()
  const plus = (d) => { const x = new Date(now.getTime() - now.getTimezoneOffset() * 60000); x.setDate(x.getDate() + d); return x.toISOString().slice(0, 16) }
  const [form, setForm] = useState({
    code: promo?.code ?? '', name: promo?.name ?? '', type: promo?.type ?? 'percent', value: promo?.value ?? 10, maxDiscount: promo?.maxDiscount ?? '',
    minOrderAmount: promo?.minOrderAmount ?? 0, startAt: toLocalInput(promo?.startAt) || plus(0), endAt: toLocalInput(promo?.endAt) || plus(30),
    usageLimit: promo?.usageLimit ?? '', channels: promo?.channels ? promo.channels.split(',') : [], campaignId: promo?.campaignId ?? '', isActive: promo?.isActive ?? true,
  })
  const [error, setError] = useState('')
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })
  const toggleChannel = (c) => setForm({ ...form, channels: form.channels.includes(c) ? form.channels.filter((x) => x !== c) : [...form.channels, c] })
  const save = async (e) => {
    e.preventDefault()
    const body = { ...form, value: Number(form.value) || 0, maxDiscount: form.maxDiscount === '' ? null : Number(form.maxDiscount), minOrderAmount: Number(form.minOrderAmount) || 0,
      usageLimit: form.usageLimit === '' ? null : Number(form.usageLimit), channels: form.channels.length ? form.channels.join(',') : null,
      campaignId: form.campaignId ? Number(form.campaignId) : null }
    try { onSaved(isNew ? await marketingApi.createPromotion(body) : await marketingApi.updatePromotion(promo.id, body)) } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <Modal title={isNew ? 'Tạo mã giảm giá' : `Sửa mã ${promo.code}`} onClose={onClose}>
      <form onSubmit={save}>
        <div className="form-grid">
          <label>Mã *<input value={form.code} onChange={u('code')} disabled={!isNew} autoFocus placeholder="SALE10" style={{ textTransform: 'uppercase' }} /></label>
          <label>Tên chương trình *<input value={form.name} onChange={u('name')} placeholder="Giảm 10% Black Friday" /></label>
          <label>Loại<select value={form.type} onChange={u('type')}>{Object.entries(PROMOTION_TYPES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
          {form.type === 'percent' && <label>Giảm (%)<input type="number" min="1" max="100" value={form.value} onChange={u('value')} /></label>}
          {form.type === 'fixed' && <label>Số tiền giảm<MoneyInput value={form.value} onChange={(v) => setForm({ ...form, value: v })} /></label>}
          {form.type === 'free_ship' && <div />}
          {form.type === 'percent' && <label>Giảm tối đa<MoneyInput value={form.maxDiscount} onChange={(v) => setForm({ ...form, maxDiscount: v || '' })} /></label>}
          <label>Đơn tối thiểu<MoneyInput value={form.minOrderAmount} onChange={(v) => setForm({ ...form, minOrderAmount: v })} /></label>
          <label>Bắt đầu<input type="datetime-local" value={form.startAt} onChange={u('startAt')} /></label>
          <label>Kết thúc<input type="datetime-local" value={form.endAt} onChange={u('endAt')} /></label>
          <label>Giới hạn lượt dùng<input type="number" min="1" value={form.usageLimit} onChange={u('usageLimit')} placeholder="Không giới hạn" /></label>
          <label>Thuộc chiến dịch<select value={form.campaignId} onChange={u('campaignId')}><option value="">Không</option>{lookups.campaigns.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
          <div className="span2">
            <div className="field-label">Áp dụng cho kênh (bỏ trống = mọi kênh)</div>
            <div className="chip-suggest">{lookups.salesChannels.map((c) => <button type="button" key={c.code} className={`chip-option${form.channels.includes(c.code) ? ' on' : ''}`} onClick={() => toggleChannel(c.code)}>{c.name}</button>)}</div>
          </div>
          {!isNew && <label className="check"><input type="checkbox" checked={form.isActive} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} /> Đang áp dụng</label>}
        </div>
        {error && <p className="error">{error}</p>}
        <div className="modal-foot"><button type="button" className="btn" onClick={onClose}>Hủy</button><button className="btn primary">Lưu</button></div>
      </form>
    </Modal>
  )
}

export function PromotionsPage() {
  const { can } = useAuth()
  const lookups = useMarketingLookups()
  const [list, setList] = useState(null)
  const [state, setState] = useState('')
  const [editing, setEditing] = useState(null)
  const [error, setError] = useState('')
  const load = useCallback(() => marketingApi.promotions({ state }).then(setList).catch((e) => setError(getErrorMessage(e))), [state])
  useEffect(() => { load() }, [load])
  const describe = (p) => p.type === 'percent' ? `Giảm ${formatQty(p.value)}%${p.maxDiscount ? ` (tối đa ${formatMoneyShort(p.maxDiscount)})` : ''}` : p.type === 'fixed' ? `Giảm ${formatMoney(p.value)}` : 'Miễn phí giao hàng'

  return (
    <MarketingLayout>
      <div className="page-head">
        <h1>Mã giảm giá</h1>
        {can(PHASE3_PERMISSIONS.MARKETING_CREATE) && <button className="btn primary" onClick={() => setEditing('new')}><i className="ti ti-plus" aria-hidden="true" /> Tạo mã</button>}
      </div>
      <p className="muted page-intro">Nhân viên nhập mã ở màn hình tạo đơn hàng; hệ thống kiểm tra hạn dùng, kênh, đơn tối thiểu và số lượt.</p>
      <div className="toolbar">
        <div className="segmented no-margin">
          {[['', 'Tất cả'], ...Object.entries(PROMOTION_STATES)].map(([k, v]) => <button key={k} className={state === k ? 'on' : ''} onClick={() => setState(k)}>{v}</button>)}
        </div>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Mã</th><th>Ưu đãi</th><th className="hide-sm">Thời gian</th><th className="num">Đã dùng</th><th className="num hide-sm">Doanh thu</th><th>Trạng thái</th></tr></thead>
          <tbody>
            {!list && <tr><td colSpan={6} className="muted center">Đang tải...</td></tr>}
            {list?.length === 0 && <tr><td colSpan={6} className="muted center">Chưa có mã giảm giá.</td></tr>}
            {list?.map((p) => (
              <tr key={p.id} className="clickable" onClick={() => can(PHASE3_PERMISSIONS.MARKETING_EDIT) && setEditing(p)}>
                <td><b className="code">{p.code}</b><div className="muted small">{p.name}{p.campaignName ? ` · ${p.campaignName}` : ''}</div></td>
                <td>{describe(p)}<div className="muted small">{p.minOrderAmount ? `Đơn từ ${formatMoneyShort(p.minOrderAmount)}` : 'Mọi đơn'}{p.channels ? ` · ${p.channels.split(',').length} kênh` : ''}</div></td>
                <td className="hide-sm small">{formatDateOnly(p.startAt.slice(0, 10))} → {formatDateOnly(p.endAt.slice(0, 10))}</td>
                <td className="num">{p.usedCount}{p.usageLimit ? ` / ${p.usageLimit}` : ''}<div className="muted small">giảm {formatMoneyShort(p.discountGiven)}</div></td>
                <td className="num hide-sm">{formatMoney(p.revenue)}</td>
                <td><span className={`pill ${PROMOTION_CSS[p.state]}`}>{PROMOTION_STATES[p.state]}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {editing && <PromotionFormModal promo={editing === 'new' ? null : editing} lookups={lookups} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); load() }} />}
    </MarketingLayout>
  )
}

/** Nhóm khách hàng theo hành vi mua - để chăm sóc / gửi ưu đãi đúng người. */
export function SegmentsPage() {
  const [data, setData] = useState(null)
  const [segment, setSegment] = useState('')
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  useEffect(() => { const t = setTimeout(() => marketingApi.segments({ segment, search, page, pageSize: 20 }).then(setData).catch((e) => setError(getErrorMessage(e))), 250); return () => clearTimeout(t) }, [segment, search, page])
  const segOf = (v) => SEGMENTS.find((s) => s.value === v)

  return (
    <MarketingLayout>
      <div className="page-head"><h1>Nhóm khách hàng</h1></div>
      <div className="segment-cards">
        {SEGMENTS.map((s) => (
          <button key={s.value} type="button" className={`kpi clickable-kpi${segment === s.value ? ' on-accent' : ''}`} onClick={() => { setSegment(segment === s.value ? '' : s.value); setPage(1) }}>
            <span className="muted small"><i className={`ti ti-${s.icon}`} aria-hidden="true" /> {s.label}</span><b>{data?.counts[s.value] ?? 0}</b><span className="small muted">{s.hint}</span>
          </button>
        ))}
      </div>
      <div className="toolbar">
        <div className="search"><i className="ti ti-search" aria-hidden="true" /><input placeholder="Tìm tên, SĐT" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} aria-label="Tìm khách" /></div>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Khách hàng</th><th className="num">Số đơn</th><th className="num">Tổng mua</th><th className="hide-sm">Mua gần nhất</th><th>Nhóm</th></tr></thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.rows.items.length === 0 && <tr><td colSpan={5} className="muted center">Không có khách nào.</td></tr>}
            {data?.rows.items.map((r) => (
              <tr key={r.partnerId}>
                <td><Link to={`/crm/customers/${r.partnerId}`}>{r.name}</Link><div className="muted small">{r.code}{r.phone ? ` · ${r.phone}` : ''}</div></td>
                <td className="num">{r.orders}</td>
                <td className="num"><b>{formatMoney(r.totalSpent)}</b></td>
                <td className="hide-sm">{formatDateOnly(r.lastOrderDate)} <span className="muted small">({r.daysSinceLast} ngày trước)</span></td>
                <td><span className="pill"><i className={`ti ti-${segOf(r.segment)?.icon}`} aria-hidden="true" /> {segOf(r.segment)?.label}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data?.rows} unit="khách hàng" onPageChange={setPage} />
    </MarketingLayout>
  )
}
