import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { websiteApi } from '../../api/phase4Api'
import Modal from '../../components/Modal'
import Pagination from '../../components/Pagination'
import { PERMISSIONS, PHASE4_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import ModuleLayout from '../../layouts/ModuleLayout'
import { formatDate, formatDateTime, formatMoney, formatMoneyShort, formatQty } from '../../utils/format'

const MENU = [
  { to: '/website', icon: 'world', label: 'Tổng quan', end: true },
  { to: '/website/products', icon: 'shirt', label: 'Sản phẩm trên web' },
  { to: '/website/content', icon: 'article', label: 'Bài viết & trang' },
  { to: '/website/contacts', icon: 'mail', label: 'Liên hệ từ web' },
  { to: '/website/menu', icon: 'menu-2', label: 'Menu' },
  { to: '/website/connect', icon: 'plug-connected', label: 'Kết nối website' },
]

// ----- Website đang thao tác (nhớ trong trình duyệt, đổi ở ô chọn trên đầu trang) -----
const SITE_KEY = 'myerp.website.siteId'
const readSite = () => { try { return Number(localStorage.getItem(SITE_KEY)) || null } catch { return null } }
export function chooseSite(id) {
  try { localStorage.setItem(SITE_KEY, String(id)) } catch { /* trình duyệt chặn lưu: vẫn đổi trong phiên này */ }
  window.dispatchEvent(new CustomEvent('myerp:site', { detail: id }))
}
/** siteId đang chọn (null = website đầu tiên). Đổi ở ô chọn thì mọi trang Website tải lại theo website mới. */
export function useSite() {
  const [siteId, setSiteId] = useState(readSite)
  useEffect(() => {
    const onChange = (e) => setSiteId(e.detail ?? readSite())
    window.addEventListener('myerp:site', onChange)
    return () => window.removeEventListener('myerp:site', onChange)
  }, [])
  return siteId
}

function SiteSwitcher() {
  const siteId = useSite()
  const [sites, setSites] = useState(null)
  useEffect(() => {
    const load = () => websiteApi.sites().then((list) => {
      setSites(list)
      if (list.length && !list.some((x) => x.id === readSite())) chooseSite(list[0].id)
    }).catch(() => setSites([]))
    load()
    window.addEventListener('myerp:sites-changed', load)
    return () => window.removeEventListener('myerp:sites-changed', load)
  }, [])
  if (!sites?.length) return null
  const current = sites.find((x) => x.id === siteId) ?? sites[0]
  return (
    <div className="site-switcher">
      <i className="ti ti-world" aria-hidden="true" />
      {sites.length > 1 ? (
        <select value={current.id} onChange={(e) => chooseSite(Number(e.target.value))} aria-label="Chọn website đang quản lý">
          {sites.map((x) => <option key={x.id} value={x.id}>{x.name} · {x.domain}</option>)}
        </select>
      ) : <b>{current.name} <span className="muted small">· {current.domain}</span></b>}
      <span className={`small ${current.hasApiKey ? 'ok-text' : 'warn-text'}`}>{current.hasApiKey ? '● Đã có khóa API' : '● Chưa kết nối website'}</span>
      <Link className="small" to="/website/connect">Kết nối</Link>
    </div>
  )
}

function WebsiteLayout({ children }) {
  return <ModuleLayout title="Website" icon="world" color="#185FA5" menu={MENU}><SiteSwitcher />{children}</ModuleLayout>
}

const emptySettings = { slogan: '', hotline: '', email: '', address: '', openingHours: '', facebook: '', instagram: '', tikTok: '', zalo: '', primaryColor: '', shippingFee: '', freeShippingFrom: '' }

function SiteSettingsCard({ siteId, site, onSaved }) {
  const { can } = useAuth()
  const canEdit = can(PHASE4_PERMISSIONS.WEBSITE_EDIT)
  const [form, setForm] = useState(() => ({ name: site.name, domain: site.domain, logoUrl: site.logoUrl ?? '', isActive: site.isActive,
    settings: { ...emptySettings, ...Object.fromEntries(Object.entries(site.settings).map(([k, v]) => [k, v ?? ''])) } }))
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })
  const us = (f) => (e) => setForm({ ...form, settings: { ...form.settings, [f]: e.target.value } })
  const save = async (e) => {
    e.preventDefault(); setError(''); setMessage('')
    const money = ['shippingFee', 'freeShippingFrom']
    const settings = Object.fromEntries(Object.entries(form.settings).map(([k, v]) => {
      const t = String(v ?? '').trim()
      return [k, !t ? null : money.includes(k) ? Number(t) : t]
    }))
    try { onSaved(await websiteApi.saveSite(siteId, { ...form, logoUrl: form.logoUrl || null, settings })); setMessage('Đã lưu thông tin website.') } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <form className="card" onSubmit={save}>
      <div className="section-head first"><h2>Thông tin website</h2>
        <label className="check"><input type="checkbox" checked={form.isActive} disabled={!canEdit} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} /> Đang hoạt động</label></div>
      <fieldset disabled={!canEdit} className="plain">
        <div className="form-grid">
          <label>Tên cửa hàng trên web *<input value={form.name} onChange={u('name')} maxLength={150} /></label>
          <label>Tên miền *<input value={form.domain} onChange={u('domain')} placeholder="mystyle.vn" maxLength={255} /></label>
          <label>Khẩu hiệu<input value={form.settings.slogan} onChange={us('slogan')} maxLength={150} /></label>
          <label>Hotline<input value={form.settings.hotline} onChange={us('hotline')} maxLength={30} /></label>
          <label>Email CSKH<input type="email" value={form.settings.email} onChange={us('email')} maxLength={150} /></label>
          <label>Giờ mở cửa<input value={form.settings.openingHours} onChange={us('openingHours')} maxLength={100} /></label>
          <label className="span2">Địa chỉ<input value={form.settings.address} onChange={us('address')} maxLength={255} /></label>
          <label>Facebook<input value={form.settings.facebook} onChange={us('facebook')} placeholder="https://facebook.com/..." /></label>
          <label>Instagram<input value={form.settings.instagram} onChange={us('instagram')} /></label>
          <label>TikTok<input value={form.settings.tikTok} onChange={us('tikTok')} /></label>
          <label>Zalo<input value={form.settings.zalo} onChange={us('zalo')} /></label>
          <label>Phí giao hàng (đ)<input type="number" min="0" step="1000" value={form.settings.shippingFee} onChange={us('shippingFee')} placeholder="30000" /></label>
          <label>Miễn phí giao hàng cho đơn từ (đ)<input type="number" min="0" step="1000" value={form.settings.freeShippingFrom} onChange={us('freeShippingFrom')} placeholder="Bỏ trống = không miễn phí" /></label>
          <label>Logo (đường dẫn ảnh)<input value={form.logoUrl} onChange={u('logoUrl')} placeholder="https://..." /></label>
          <label>Màu chủ đạo
            <span className="color-field"><input type="color" value={form.settings.primaryColor || '#185FA5'} onChange={us('primaryColor')} aria-label="Chọn màu" />
              <input value={form.settings.primaryColor} onChange={us('primaryColor')} placeholder="#185FA5" maxLength={7} /></span></label>
        </div>
      </fieldset>
      {message && <div className="alert success">{message}</div>}
      {error && <p className="error">{error}</p>}
      {canEdit && <div className="form-actions"><button className="btn primary">Lưu thông tin</button></div>}
    </form>
  )
}

/** Tổng quan website: sản phẩm đang bán online, bài viết, liên hệ mới, doanh thu đơn kênh website. */
export function WebsiteOverviewPage() {
  const siteId = useSite()
  const [o, setO] = useState(null)
  const [error, setError] = useState('')
  useEffect(() => { setO(null); websiteApi.overview(siteId).then(setO).catch((e) => setError(getErrorMessage(e))) }, [siteId])
  return (
    <WebsiteLayout>
      <div className="page-head">
        <div><h1>Website {o?.site && <span className="muted small">· {o.site.domain}</span>}</h1>
          {o?.site && <div className="muted small">{o.site.isActive ? <span className="ok-text">● Đang hoạt động</span> : <span className="money-out">● Đang tắt</span>} · Web tự code đọc dữ liệu qua <code>/api/public/...</code> (xem mục Kết nối)</div>}</div>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="kpi-row">
        <Link className="kpi as-button" to="/website/products"><span className="muted small">Mẫu đang bán trên web</span><b>{o ? `${o.publishedModels}/${o.totalModels}` : '…'}</b></Link>
        <Link className="kpi as-button" to="/website/contacts"><span className="muted small">Liên hệ chưa xử lý</span><b className={o?.newContacts ? 'warn-text' : ''}>{o?.newContacts ?? '…'}</b><span className="small muted">{o?.contactsThisMonth ?? 0} liên hệ trong tháng</span></Link>
        <Link className="kpi as-button" to="/orders"><span className="muted small">Đơn online 30 ngày</span><b className="ok-text">{o ? formatMoneyShort(o.onlineRevenue30d) : '…'}</b><span className="small muted">{o?.onlineOrders30d ?? 0} đơn kênh Website</span></Link>
        <Link className="kpi as-button" to="/website/content"><span className="muted small">Bài viết đã đăng</span><b>{o?.publishedPosts ?? '…'}</b><span className="small muted">{o?.draftPosts ?? 0} nháp · {o?.pages ?? 0} trang</span></Link>
      </div>
      {o && (
        <div className="two-col">
          <div className="card">
            <div className="section-head first"><h2>Liên hệ mới nhất</h2><Link className="small" to="/website/contacts">Xem tất cả</Link></div>
            <table className="grid compact">
              <tbody>
                {o.recentContacts.length === 0 && <tr><td className="muted center">Chưa có liên hệ.</td></tr>}
                {o.recentContacts.map((c) => (
                  <tr key={c.id}><td><b>{c.fullName}</b> <span className="muted small">{c.phone ?? c.email}</span><div className="small muted clamp-1">{c.message}</div></td>
                    <td className="small muted nowrap">{formatDateTime(c.createdAt)}{c.leadCode && <div className="ok-text">→ {c.leadCode}</div>}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="card">
            <div className="section-head first"><h2>Bài viết xem nhiều</h2><Link className="small" to="/website/content">Quản lý bài viết</Link></div>
            <table className="grid compact">
              <tbody>
                {o.topPosts.length === 0 && <tr><td className="muted center">Chưa có bài viết.</td></tr>}
                {o.topPosts.map((p) => <tr key={p.id}><td>{p.title}<div className="muted small">{p.publishedAt ? formatDate(p.publishedAt) : ''}</div></td><td className="num">{formatQty(p.viewCount)} lượt xem</td></tr>)}
              </tbody>
            </table>
          </div>
        </div>
      )}
      {o?.site && <SiteSettingsCard key={o.site.id} siteId={o.site.id} site={o.site} onSaved={(site) => { setO({ ...o, site }); window.dispatchEvent(new Event('myerp:sites-changed')) }} />}
    </WebsiteLayout>
  )
}

/** Bật / tắt mẫu sản phẩm hiện trên website. */
export function WebProductsPage() {
  const { can } = useAuth()
  const canEdit = can(PHASE4_PERMISSIONS.WEBSITE_EDIT)
  const [data, setData] = useState(null)
  const [state, setState] = useState('')
  const [search, setSearch] = useState('')
  const [q, setQ] = useState('')
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const siteId = useSite()
  const [priceEdit, setPriceEdit] = useState(null)
  const load = useCallback(() => websiteApi.products(siteId, { state, search: q, page, pageSize: 20 }).then(setData).catch((e) => setError(getErrorMessage(e))), [siteId, state, q, page])
  useEffect(() => { load() }, [load])
  useEffect(() => { const t = setTimeout(() => { setQ(search); setPage(1) }, 300); return () => clearTimeout(t) }, [search])
  const save = async (p, patch) => {
    setError('')
    const body = { isPublished: p.isPublished, priceOverride: p.priceOverride, isFeatured: p.isFeatured, ...patch }
    try { const row = await websiteApi.publish(siteId, p.modelId, body); setData((d) => ({ ...d, items: d.items.map((x) => (x.modelId === row.modelId ? row : x)) })) } catch (err) { setError(getErrorMessage(err)) }
  }
  const toggle = (p) => save(p, { isPublished: !p.isPublished })
  return (
    <WebsiteLayout>
      <div className="page-head"><div><h1>Sản phẩm trên web</h1><p className="muted small">Bật theo mẫu: mọi màu - size đang kinh doanh của mẫu hiện trên website đang chọn. Giá và tồn kho lấy trực tiếp từ app Kho - sửa ở Kho là website đổi theo. Đặt giá riêng nếu website này bán giá khác.</p></div></div>
      <div className="toolbar">
        <div className="segmented no-margin">
          {[['', 'Tất cả'], ['published', 'Đang hiện'], ['featured', 'Nổi bật'], ['hidden', 'Đang ẩn']].map(([v, l]) => <button key={v} className={state === v ? 'on' : ''} onClick={() => { setState(v); setPage(1) }}>{l}</button>)}
        </div>
        <div className="search"><i className="ti ti-search" aria-hidden="true" /><input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Tìm mẫu" aria-label="Tìm mẫu sản phẩm" /></div>
      </div>
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Mẫu sản phẩm</th><th className="num">Giá trên web</th><th className="num hide-sm">Tồn kho</th><th className="hide-sm">Nổi bật</th><th>Trên web</th></tr></thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.items.length === 0 && <tr><td colSpan={5} className="muted center">Không có mẫu nào.</td></tr>}
            {data?.items.map((p) => (
              <tr key={p.modelId}>
                <td><Link to={`/inventory/products/${p.modelId}`}>{p.name}</Link><div className="muted small">{p.code}{p.categoryName ? ` · ${p.categoryName}` : ''} · {p.variants} biến thể{!p.isActive && ' · ngừng kinh doanh'}</div></td>
                <td className="num">
                  {priceEdit?.id === p.modelId ? (
                    <form className="inline-form" onSubmit={(e) => { e.preventDefault(); save(p, { isPublished: true, priceOverride: priceEdit.value === '' ? null : Number(priceEdit.value) }); setPriceEdit(null) }}>
                      <input type="number" min="0" step="1000" value={priceEdit.value} autoFocus onChange={(e) => setPriceEdit({ ...priceEdit, value: e.target.value })}
                        placeholder={String(p.salePrice)} aria-label="Giá riêng trên website" className="w-sm" />
                      <button className="btn small primary">Lưu</button><button type="button" className="btn small ghost" onClick={() => setPriceEdit(null)}>Hủy</button>
                    </form>
                  ) : (
                    <button className="link-button" disabled={!canEdit} onClick={() => setPriceEdit({ id: p.modelId, value: p.priceOverride ?? '' })} title="Đặt giá riêng cho website này">
                      {formatMoney(p.priceOverride ?? p.salePrice)}
                    </button>
                  )}
                  {p.priceOverride !== null && priceEdit?.id !== p.modelId && <div className="small muted">Giá riêng · ở Kho {formatMoney(p.salePrice)}</div>}
                </td>
                <td className={`num hide-sm ${p.stock <= 0 ? 'money-out' : ''}`}>{formatQty(p.stock)}</td>
                <td className="hide-sm">
                  <button className={`btn ghost small${p.isFeatured ? ' warn-text' : ''}`} disabled={!canEdit || !p.isPublished} onClick={() => save(p, { isFeatured: !p.isFeatured })}
                    aria-pressed={p.isFeatured} title={p.isPublished ? 'Nổi bật = hiện ở trang chủ website' : 'Bật hiện trên web trước'}>
                    <i className={`ti ti-star${p.isFeatured ? '-filled' : ''}`} aria-hidden="true" />
                  </button>
                </td>
                <td>
                  <span className="switch-row" title={p.isPublished ? 'Đang hiện trên web - bấm để ẩn' : 'Đang ẩn - bấm để hiện'}>
                    <label className="switch">
                      <input type="checkbox" checked={p.isPublished} disabled={!canEdit || (!p.isActive && !p.isPublished)} onChange={() => toggle(p)} aria-label={`Hiện ${p.name} trên web`} />
                      <span />
                    </label>
                    <span className="small">{p.isPublished ? `Hiện (${p.activeVariants} màu-size)` : 'Ẩn'}</span>
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data} unit="mẫu" onPageChange={setPage} />
    </WebsiteLayout>
  )
}

function ContentEditor({ siteId, kind, item, categories, onClose, onSaved, onCategory }) {
  const isPost = kind === 'post'
  const [form, setForm] = useState({
    title: item?.title ?? '', slug: item?.slug ?? '', summary: item?.summary ?? '', content: item?.content ?? '', thumbnailUrl: item?.thumbnailUrl ?? '',
    categoryId: item?.categoryId ?? '', metaTitle: item?.metaTitle ?? '', metaDescription: item?.metaDescription ?? '', isPublished: item?.isPublished ?? false,
  })
  const [preview, setPreview] = useState(false)
  const [newCat, setNewCat] = useState('')
  const [error, setError] = useState('')
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })
  const save = async (e) => {
    e.preventDefault(); setError('')
    const body = { ...form, slug: form.slug || null, summary: form.summary || null, content: form.content || null, thumbnailUrl: form.thumbnailUrl || null,
      categoryId: form.categoryId ? Number(form.categoryId) : null, metaTitle: form.metaTitle || null, metaDescription: form.metaDescription || null }
    try {
      const saved = isPost ? (item ? await websiteApi.updatePost(siteId, item.id, body) : await websiteApi.createPost(siteId, body))
        : (item ? await websiteApi.updatePage(siteId, item.id, body) : await websiteApi.createPage(siteId, body))
      onSaved(saved)
    } catch (err) { setError(getErrorMessage(err)) }
  }
  const addCategory = async () => {
    try { const c = await websiteApi.createCategory(siteId, newCat); onCategory(c); setForm({ ...form, categoryId: c.id }); setNewCat('') } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <Modal title={item ? `Sửa ${isPost ? 'bài viết' : 'trang'}` : isPost ? 'Viết bài mới' : 'Tạo trang mới'} onClose={onClose} size="large">
      <div className="segmented"><button className={!preview ? 'on' : ''} onClick={() => setPreview(false)}>Soạn</button><button className={preview ? 'on' : ''} onClick={() => setPreview(true)}>Xem trước</button></div>
      {preview ? (
        <article className="web-preview">
          {form.thumbnailUrl && <img src={form.thumbnailUrl} alt="" />}
          <h1>{form.title || '(Chưa có tiêu đề)'}</h1>
          {form.summary && <p className="lead">{form.summary}</p>}
          <div className="pre-wrap">{form.content}</div>
        </article>
      ) : (
        <form id="content-form" onSubmit={save}>
          <div className="form-grid">
            <label className="span2">Tiêu đề *<input value={form.title} onChange={u('title')} autoFocus maxLength={255} /></label>
            <label>Đường dẫn (bỏ trống để tự tạo)<input value={form.slug} onChange={u('slug')} placeholder="tu-dong-theo-tieu-de" maxLength={200} /></label>
            {isPost && (
              <label>Chuyên mục
                <span className="inline-form"><select value={form.categoryId} onChange={u('categoryId')}><option value="">—</option>{categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select>
                  <input value={newCat} onChange={(e) => setNewCat(e.target.value)} placeholder="+ mới" aria-label="Tên chuyên mục mới" className="w-sm" />
                  {newCat.trim() && <button type="button" className="btn small" onClick={addCategory}>Thêm</button>}</span></label>
            )}
            {isPost && <label className="span2">Tóm tắt<textarea rows={2} value={form.summary} onChange={u('summary')} maxLength={1000} /></label>}
            {isPost && <label className="span2">Ảnh đại diện (đường dẫn)<input value={form.thumbnailUrl} onChange={u('thumbnailUrl')} placeholder="https://..." /></label>}
            <label className="span2">Nội dung<textarea rows={10} value={form.content} onChange={u('content')} /></label>
            <label>Tiêu đề SEO<input value={form.metaTitle} onChange={u('metaTitle')} maxLength={255} placeholder="Hiện trên Google" /></label>
            <label>Mô tả SEO<input value={form.metaDescription} onChange={u('metaDescription')} maxLength={500} /></label>
          </div>
          <label className="check top-gap"><input type="checkbox" checked={form.isPublished} onChange={(e) => setForm({ ...form, isPublished: e.target.checked })} /> Đăng lên website (bỏ chọn = lưu nháp)</label>
        </form>
      )}
      {error && <p className="error">{error}</p>}
      <div className="modal-foot"><button type="button" className="btn" onClick={onClose}>Hủy</button><button className="btn primary" type="submit" form="content-form" disabled={preview}>Lưu</button></div>
    </Modal>
  )
}

/** Bài viết blog và trang tĩnh của website. */
export function WebContentPage() {
  const { can } = useAuth()
  const [tab, setTab] = useState('posts')
  const [posts, setPosts] = useState(null)
  const [pages, setPages] = useState(null)
  const [categories, setCategories] = useState([])
  const [state, setState] = useState('')
  const [page, setPage] = useState(1)
  const [editing, setEditing] = useState(null)
  const [error, setError] = useState('')
  const siteId = useSite()
  const loadPosts = useCallback(() => websiteApi.posts(siteId, { state, page, pageSize: 20 }).then(setPosts).catch((e) => setError(getErrorMessage(e))), [siteId, state, page])
  const loadPages = useCallback(() => websiteApi.pages(siteId).then(setPages).catch((e) => setError(getErrorMessage(e))), [siteId])
  useEffect(() => { loadPosts() }, [loadPosts])
  useEffect(() => { loadPages(); websiteApi.categories(siteId).then(setCategories).catch(() => {}) }, [loadPages, siteId])

  const openPost = async (id) => { try { setEditing({ kind: 'post', item: await websiteApi.post(siteId, id) }) } catch (err) { setError(getErrorMessage(err)) } }
  const remove = async (kind, item) => {
    if (!window.confirm(`Xóa "${item.title}"?`)) return
    try { if (kind === 'post') { await websiteApi.deletePost(siteId, item.id); loadPosts() } else { await websiteApi.deletePage(siteId, item.id); loadPages() } } catch (err) { setError(getErrorMessage(err)) }
  }
  const canCreate = can(PHASE4_PERMISSIONS.WEBSITE_CREATE)
  const canEdit = can(PHASE4_PERMISSIONS.WEBSITE_EDIT)
  const canDelete = can(PHASE4_PERMISSIONS.WEBSITE_DELETE)

  return (
    <WebsiteLayout>
      <div className="page-head">
        <h1>Bài viết & trang</h1>
        {canCreate && <button className="btn primary" onClick={() => setEditing({ kind: tab === 'posts' ? 'post' : 'page', item: null })}><i className="ti ti-plus" aria-hidden="true" /> {tab === 'posts' ? 'Viết bài' : 'Tạo trang'}</button>}
      </div>
      <div className="toolbar">
        <div className="segmented no-margin">
          <button className={tab === 'posts' ? 'on' : ''} onClick={() => setTab('posts')}>Bài viết (blog)</button>
          <button className={tab === 'pages' ? 'on' : ''} onClick={() => setTab('pages')}>Trang tĩnh</button>
        </div>
        {tab === 'posts' && <select value={state} onChange={(e) => { setState(e.target.value); setPage(1) }} aria-label="Lọc trạng thái"><option value="">Tất cả</option><option value="published">Đã đăng</option><option value="draft">Nháp</option></select>}
      </div>
      {error && <div className="alert error">{error}</div>}
      {tab === 'posts' ? (
        <>
          <div className="table-wrap">
            <table className="grid">
              <thead><tr><th>Bài viết</th><th className="hide-sm">Chuyên mục</th><th className="num hide-sm">Lượt xem</th><th>Trạng thái</th><th aria-label="Thao tác" /></tr></thead>
              <tbody>
                {!posts && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
                {posts?.items.length === 0 && <tr><td colSpan={5} className="muted center">Chưa có bài viết.</td></tr>}
                {posts?.items.map((p) => (
                  <tr key={p.id} className={canEdit ? 'clickable' : ''} onClick={() => canEdit && openPost(p.id)}>
                    <td><b>{p.title}</b><div className="muted small clamp-1">{p.summary}</div><div className="muted small">{p.authorName} · <code>/blog/{p.slug}</code></div></td>
                    <td className="hide-sm">{p.categoryName ?? '-'}</td>
                    <td className="num hide-sm">{formatQty(p.viewCount)}</td>
                    <td>{p.isPublished ? <span className="pill completed">Đã đăng</span> : <span className="pill draft">Nháp</span>}<div className="muted small">{p.publishedAt ? formatDate(p.publishedAt) : ''}</div></td>
                    <td>{canDelete && <button className="btn ghost small" onClick={(e) => { e.stopPropagation(); remove('post', p) }} aria-label={`Xóa ${p.title}`}><i className="ti ti-trash" aria-hidden="true" /></button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination data={posts} unit="bài" onPageChange={setPage} />
        </>
      ) : (
        <div className="table-wrap">
          <table className="grid">
            <thead><tr><th>Trang</th><th className="hide-sm">Cập nhật</th><th>Trạng thái</th><th aria-label="Thao tác" /></tr></thead>
            <tbody>
              {!pages && <tr><td colSpan={4} className="muted center">Đang tải...</td></tr>}
              {pages?.length === 0 && <tr><td colSpan={4} className="muted center">Chưa có trang.</td></tr>}
              {pages?.map((p) => (
                <tr key={p.id} className={canEdit ? 'clickable' : ''} onClick={() => canEdit && setEditing({ kind: 'page', item: p })}>
                  <td><b>{p.title}</b><div className="muted small"><code>/pages/{p.slug}</code></div></td>
                  <td className="hide-sm small muted">{p.updatedAt ? formatDateTime(p.updatedAt) : ''}</td>
                  <td>{p.isPublished ? <span className="pill completed">Đã đăng</span> : <span className="pill draft">Nháp</span>}</td>
                  <td>{canDelete && <button className="btn ghost small" onClick={(e) => { e.stopPropagation(); remove('page', p) }} aria-label={`Xóa ${p.title}`}><i className="ti ti-trash" aria-hidden="true" /></button>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {editing && <ContentEditor siteId={siteId} kind={editing.kind} item={editing.item} categories={categories} onClose={() => setEditing(null)}
        onCategory={(c) => setCategories([...categories, c])}
        onSaved={() => { setEditing(null); if (editing.kind === 'post') loadPosts(); else loadPages() }} />}
    </WebsiteLayout>
  )
}

/** Liên hệ khách gửi từ form website: gọi lại, chuyển thành khách tiềm năng (Lead). */
export function WebContactsPage() {
  const { can } = useAuth()
  const [data, setData] = useState(null)
  const [state, setState] = useState('new')
  const [search, setSearch] = useState('')
  const [q, setQ] = useState('')
  const [page, setPage] = useState(1)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const siteId = useSite()
  const load = useCallback(() => websiteApi.contacts(siteId, { state, search: q, page, pageSize: 20 }).then(setData).catch((e) => setError(getErrorMessage(e))), [siteId, state, q, page])
  useEffect(() => { load() }, [load])
  useEffect(() => { const t = setTimeout(() => { setQ(search); setPage(1) }, 300); return () => clearTimeout(t) }, [search])
  const convert = async (c) => {
    setError(''); setMessage('')
    try { const r = await websiteApi.convertContact(siteId, c.id); setMessage(`Đã chuyển ${r.fullName} thành khách tiềm năng ${r.leadCode}.`); load() } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <WebsiteLayout>
      <div className="page-head"><div><h1>Liên hệ từ website</h1><p className="muted small">Khách gửi form "Liên hệ" trên web. Chuyển thành khách tiềm năng để theo dõi ở app CRM.</p></div></div>
      <div className="toolbar">
        <div className="segmented no-margin">
          {[['new', 'Chưa xử lý'], ['converted', 'Đã chuyển CRM'], ['', 'Tất cả']].map(([v, l]) => <button key={v} className={state === v ? 'on' : ''} onClick={() => { setState(v); setPage(1) }}>{l}</button>)}
        </div>
        <div className="search"><i className="ti ti-search" aria-hidden="true" /><input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Tìm tên, SĐT, email" aria-label="Tìm liên hệ" /></div>
      </div>
      {message && <div className="alert success">{message}</div>}
      {error && <div className="alert error">{error}</div>}
      <div className="table-wrap">
        <table className="grid">
          <thead><tr><th>Khách</th><th>Nội dung</th><th className="hide-sm">Nguồn</th><th className="hide-sm">Thời gian</th><th aria-label="Thao tác" /></tr></thead>
          <tbody>
            {!data && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {data?.items.length === 0 && <tr><td colSpan={5} className="muted center">Không có liên hệ.</td></tr>}
            {data?.items.map((c) => (
              <tr key={c.id}>
                <td><b>{c.fullName}</b>{c.phone && <div className="small"><a href={`tel:${c.phone}`}>{c.phone}</a></div>}{c.email && <div className="small muted">{c.email}</div>}</td>
                <td className="small">{c.message}{c.pageUrl && <div className="muted">Từ trang <code>{c.pageUrl}</code></div>}</td>
                <td className="hide-sm small">{c.utmSource ?? <span className="muted">Trực tiếp</span>}{c.utmCampaign && <div className="muted">{c.utmCampaign}</div>}</td>
                <td className="hide-sm small muted nowrap">{formatDateTime(c.createdAt)}</td>
                <td className="nowrap">{c.leadId ? <Link className="small ok-text" to="/crm/leads">→ {c.leadCode}</Link>
                  : can(PERMISSIONS.CRM_CREATE) && <button className="btn small" onClick={() => convert(c)}><i className="ti ti-user-plus" aria-hidden="true" /> Tạo lead</button>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination data={data} unit="liên hệ" onPageChange={setPage} />
    </WebsiteLayout>
  )
}

function MenuEditor({ siteId, code, title, canEdit }) {
  const [items, setItems] = useState(null)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  useEffect(() => { setItems(null); websiteApi.menu(siteId, code).then((m) => setItems(m.items)).catch((e) => setError(getErrorMessage(e))) }, [siteId, code])
  const set = (i, patch) => setItems(items.map((x, j) => (j === i ? { ...x, ...patch } : x)))
  const move = (i, d) => { const next = [...items]; const [x] = next.splice(i, 1); next.splice(i + d, 0, x); setItems(next) }
  const save = async () => {
    setError(''); setMessage('')
    try { setItems((await websiteApi.saveMenu(siteId, code, items)).items); setMessage('Đã lưu menu.') } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <div className="card">
      <div className="section-head first"><h2>{title}</h2></div>
      {!items && <p className="muted">Đang tải...</p>}
      {items && (
        <table className="grid compact menu-table">
          <thead><tr><th>Tên hiển thị</th><th>Đường dẫn</th><th>Tab mới</th><th aria-label="Thao tác" /></tr></thead>
          <tbody>
            {items.map((it, i) => (
              <tr key={i}>
                <td><input value={it.label} disabled={!canEdit} onChange={(e) => set(i, { label: e.target.value })} aria-label="Tên mục" maxLength={100} /></td>
                <td><input value={it.url} disabled={!canEdit} onChange={(e) => set(i, { url: e.target.value })} aria-label="Đường dẫn" placeholder="/collections/nam" maxLength={500} /></td>
                <td className="center"><input type="checkbox" checked={it.openNewTab} disabled={!canEdit} onChange={(e) => set(i, { openNewTab: e.target.checked })} aria-label="Mở tab mới" /></td>
                <td className="nowrap">{canEdit && <>
                  <button className="btn ghost small" disabled={i === 0} onClick={() => move(i, -1)} aria-label="Lên"><i className="ti ti-arrow-up" aria-hidden="true" /></button>
                  <button className="btn ghost small" disabled={i === items.length - 1} onClick={() => move(i, 1)} aria-label="Xuống"><i className="ti ti-arrow-down" aria-hidden="true" /></button>
                  <button className="btn ghost small" onClick={() => setItems(items.filter((_, j) => j !== i))} aria-label="Xóa mục"><i className="ti ti-x" aria-hidden="true" /></button></>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {message && <div className="alert success">{message}</div>}
      {error && <p className="error">{error}</p>}
      {canEdit && items && <div className="form-actions"><button className="btn" onClick={() => setItems([...items, { label: '', url: '/', openNewTab: false }])}><i className="ti ti-plus" aria-hidden="true" /> Thêm mục</button>
        <button className="btn primary" onClick={save}>Lưu menu</button></div>}
    </div>
  )
}

export function WebMenuPage() {
  const { can } = useAuth()
  const canEdit = can(PHASE4_PERMISSIONS.WEBSITE_EDIT)
  const siteId = useSite()
  return (
    <WebsiteLayout>
      <div className="page-head"><div><h1>Menu website</h1><p className="muted small">Đường dẫn bắt đầu bằng / (trang trong web) hoặc https:// (trang ngoài).</p></div></div>
      <div className="two-col">
        <MenuEditor siteId={siteId} code="header" title="Menu đầu trang" canEdit={canEdit} />
        <MenuEditor siteId={siteId} code="footer" title="Menu chân trang" canEdit={canEdit} />
      </div>
    </WebsiteLayout>
  )
}

function CopyBox({ label, value, secret = false }) {
  const [shown, setShown] = useState(!secret)
  const [copied, setCopied] = useState(false)
  const copy = async () => {
    try { await navigator.clipboard.writeText(value); setCopied(true); setTimeout(() => setCopied(false), 1500) } catch { setShown(true) }
  }
  return (
    <div className="copy-box">
      <span className="muted small">{label}</span>
      <code className="grow">{shown ? value : '•'.repeat(Math.min(24, value.length))}</code>
      {secret && <button type="button" className="btn ghost small" onClick={() => setShown(!shown)} aria-label={shown ? 'Ẩn' : 'Hiện'}><i className={`ti ti-eye${shown ? '-off' : ''}`} aria-hidden="true" /></button>}
      <button type="button" className="btn small" onClick={copy}><i className={`ti ti-${copied ? 'check' : 'copy'}`} aria-hidden="true" /> {copied ? 'Đã chép' : 'Chép'}</button>
    </div>
  )
}

function SiteConnectCard({ site, canEdit, onChanged }) {
  const [newKey, setNewKey] = useState(null)
  const [hook, setHook] = useState(null)
  const [url, setUrl] = useState(site.revalidateUrl ?? '')
  const [status, setStatus] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  useEffect(() => { if (canEdit) websiteApi.webhook(site.id).then((h) => { setHook(h); setUrl(h.url ?? '') }).catch(() => {}) }, [site.id, canEdit])
  const run = async (fn) => { setError(''); setBusy(true); try { await fn() } catch (err) { setError(getErrorMessage(err)) } finally { setBusy(false) } }
  const issue = () => {
    if (site.hasApiKey && !window.confirm('Tạo khóa mới thì khóa đang dùng hết hiệu lực ngay - website sẽ lỗi cho tới khi bạn dán khóa mới vào. Tiếp tục?')) return
    run(async () => { setNewKey(await websiteApi.issueKey(site.id)); onChanged() })
  }
  const revoke = () => {
    if (!window.confirm('Thu hồi khóa: website sẽ không đọc được dữ liệu nữa. Tiếp tục?')) return
    run(async () => { await websiteApi.revokeKey(site.id); setNewKey(null); onChanged() })
  }
  const saveHook = (newSecret = false) => run(async () => { const h = await websiteApi.saveWebhook(site.id, url.trim() || null, newSecret); setHook(h); onChanged() })
  const test = () => run(async () => { setStatus((await websiteApi.revalidate(site.id)).status); onChanged() })
  // Khung hiển thị che mật khẩu; nút "Chép" chép đủ để dán vào .env.local
  const envLines = (mask) => [
    `ERP_API_URL=${window.location.origin.replace(':5173', ':5121')}`,
    `ERP_SITE_KEY=${newKey?.key ?? '<dán khóa API vào đây>'}`,
    `REVALIDATE_SECRET=${hook?.secret ? (mask ? '•'.repeat(16) : hook.secret) : '<lưu webhook để có mật khẩu>'}`,
  ].join('\n')

  return (
    <div className="card">
      <div className="section-head first">
        <h2>{site.name} <span className="muted small">· {site.domain}</span> {!site.isActive && <span className="pill draft small-pill">Đang tắt</span>}</h2>
        <span className="muted small">{site.productCount} mẫu đang bày</span>
      </div>

      <h3 className="sub-head">1. Khóa API <span className="muted small">- website gửi trong header <code>X-Site-Key</code> khi gọi ERP</span></h3>
      {newKey ? (
        <div className="alert success">
          <b>Khóa mới - chỉ hiện 1 lần này, hãy chép ngay vào biến môi trường của website.</b>
          <CopyBox label="ERP_SITE_KEY" value={newKey.key} />
        </div>
      ) : (
        <p className="small">{site.hasApiKey ? <>Đang dùng khóa <code>{site.apiKeyPrefix}…</code> tạo lúc {formatDateTime(site.apiKeyCreatedAt)}. ERP chỉ lưu bản băm nên không xem lại được khóa - quên thì tạo khóa mới.</>
          : <span className="warn-text">Chưa có khóa - website chưa đọc được dữ liệu.</span>}</p>
      )}
      {canEdit && <div className="side-actions">
        <button className="btn" disabled={busy} onClick={issue}><i className="ti ti-key" aria-hidden="true" /> {site.hasApiKey ? 'Tạo khóa mới' : 'Tạo khóa API'}</button>
        {site.hasApiKey && <button className="btn danger-text" disabled={busy} onClick={revoke}>Thu hồi khóa</button>}
      </div>}

      <h3 className="sub-head">2. Webhook làm mới <span className="muted small">- ERP gọi khi sản phẩm, giá, tồn kho, bài viết, menu thay đổi</span></h3>
      {canEdit ? (
        <>
          <form className="inline-form wrap" onSubmit={(e) => { e.preventDefault(); saveHook() }}>
            <input value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://mystyle.vn/api/revalidate" aria-label="Địa chỉ webhook" />
            <button className="btn primary" disabled={busy}>Lưu</button>
          </form>
          {hook?.secret && hook?.url && (
            <div className="top-gap">
              <CopyBox label="REVALIDATE_SECRET" value={hook.secret} secret />
              <div className="side-actions top-gap">
                <button className="btn" disabled={busy} onClick={test}><i className="ti ti-refresh" aria-hidden="true" /> Làm mới website ngay</button>
                <button className="btn ghost" disabled={busy} onClick={() => window.confirm('Đổi mật khẩu webhook? Phải cập nhật REVALIDATE_SECRET ở website.') && saveHook(true)}>Đổi mật khẩu</button>
              </div>
            </div>
          )}
        </>
      ) : <p className="small">{site.revalidateUrl ?? 'Chưa cấu hình.'}</p>}
      {(status || site.lastSyncStatus) && (
        <p className={`small ${(status ?? site.lastSyncStatus).startsWith('OK') ? 'ok-text' : 'warn-text'}`}>
          Lần gửi gần nhất{!status && site.lastSyncAt ? ` (${formatDateTime(site.lastSyncAt)})` : ''}: {status ?? site.lastSyncStatus}</p>
      )}

      <h3 className="sub-head">3. Biến môi trường cho website Next.js <span className="muted small">(file <code>.env.local</code>)</span></h3>
      <pre className="env-box">{envLines(true)}</pre>
      <CopyBox label="Chép cả 3 dòng" value={envLines(false)} secret />
      <div className="top-gap" />
      {error && <p className="error">{error}</p>}
    </div>
  )
}

/** Kết nối website tự code (Next.js): khóa API, webhook làm mới, thêm website. */
export function WebConnectPage() {
  const { can } = useAuth()
  const canEdit = can(PHASE4_PERMISSIONS.WEBSITE_EDIT)
  const [sites, setSites] = useState(null)
  const [adding, setAdding] = useState(false)
  const [form, setForm] = useState({ name: '', domain: '' })
  const [error, setError] = useState('')
  const load = useCallback(() => websiteApi.sites().then(setSites).catch((e) => setError(getErrorMessage(e))), [])
  useEffect(() => { load() }, [load])
  const changed = () => { load(); window.dispatchEvent(new Event('myerp:sites-changed')) }
  const create = async (e) => {
    e.preventDefault(); setError('')
    try {
      const s = await websiteApi.createSite({ name: form.name, domain: form.domain, logoUrl: null, isActive: true, settings: null })
      setAdding(false); setForm({ name: '', domain: '' }); changed(); chooseSite(s.id)
    } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <WebsiteLayout>
      <div className="page-head">
        <div><h1>Kết nối website</h1>
          <p className="muted small">Website tự code (Next.js) không có database riêng: mọi trang đọc dữ liệu từ ERP qua <code>/api/public/...</code>. Sửa sản phẩm, giá, tồn kho, bài viết, menu ở ERP là website đổi theo (webhook báo làm mới ngay; nếu webhook lỗi, website tự làm mới sau vài phút). Mã nguồn website mẫu: thư mục <code>storefront/</code>.</p></div>
        {can(PHASE4_PERMISSIONS.WEBSITE_CREATE) && <button className="btn primary" onClick={() => setAdding(true)}><i className="ti ti-plus" aria-hidden="true" /> Thêm website</button>}
      </div>
      {error && <div className="alert error">{error}</div>}
      {!sites && <p className="muted">Đang tải...</p>}
      {sites?.map((s) => <SiteConnectCard key={s.id} site={s} canEdit={canEdit} onChanged={changed} />)}
      {adding && (
        <Modal title="Thêm website" onClose={() => setAdding(false)} size="small">
          <form onSubmit={create}>
            <label>Tên website *<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} autoFocus placeholder="MyStyle Sneaker" maxLength={150} /></label>
            <label>Tên miền *<input value={form.domain} onChange={(e) => setForm({ ...form, domain: e.target.value })} placeholder="sneaker.mystyle.vn" maxLength={255} /></label>
            <p className="hint-inline">Sau khi tạo: chọn mẫu bày bán ở mục "Sản phẩm trên web", tạo khóa API ở đây.</p>
            {error && <p className="error">{error}</p>}
            <div className="modal-foot"><button type="button" className="btn" onClick={() => setAdding(false)}>Hủy</button><button className="btn primary">Tạo website</button></div>
          </form>
        </Modal>
      )}
    </WebsiteLayout>
  )
}
