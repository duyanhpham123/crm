import { useCallback, useEffect, useState } from 'react'
import { getErrorMessage } from '../../api/client'
import { aiApi } from '../../api/aiApi'
import Modal from '../../components/Modal'
import { formatDateTime } from '../../utils/format'

/** Địa chỉ backend: khi chạy dev, trang ở cổng 5173 còn API ở 5121. */
const apiUrl = () => (window.location.port === '5173' ? window.location.origin.replace(':5173', ':5121') : window.location.origin)

const EXAMPLES = [
  'Báo cáo doanh thu tháng này so với tháng trước, kênh nào bán tốt nhất?',
  'Những size nào sắp hết hàng? Gợi ý số lượng cần nhập.',
  'Giảm 10% toàn bộ nhóm Giày sneaker (cho mình xem trước).',
  'Bật mẫu Mũ lưỡi trai lên web MyStyle Sneaker, giá 99.000 đ, đưa lên nổi bật.',
  'Tạo mã giảm giá TET2027 giảm 15% tối đa 100k cho đơn từ 500k, từ 20/01 đến 10/02.',
  'Viết bài blog "5 cách phối đồ đi chơi Tết" cho web MyStyle Fashion, lưu nháp.',
  'Giao việc cho Châu: gọi lại khách VIP lâu chưa mua, hạn thứ 6.',
  'Đơn DH2611-00105 của ai, giao đi đâu, đã thanh toán chưa?',
]

function Copy({ text, label = 'Chép' }) {
  const [done, setDone] = useState(false)
  const copy = async () => { try { await navigator.clipboard.writeText(text); setDone(true); setTimeout(() => setDone(false), 1500) } catch { /* trình duyệt chặn */ } }
  return <button type="button" className="btn small" onClick={copy}><i className={`ti ti-${done ? 'check' : 'copy'}`} aria-hidden="true" /> {done ? 'Đã chép' : label}</button>
}

/** Kết nối trợ lý AI (Claude Desktop) với ERP: tạo khóa truy cập cá nhân, lệnh cài, ví dụ câu lệnh. */
export default function AiConnectPage() {
  const [tokens, setTokens] = useState(null)
  const [setup, setSetup] = useState(null)
  const [creating, setCreating] = useState(false)
  const [form, setForm] = useState({ name: 'Claude Desktop', expiresInDays: '90' })
  const [newToken, setNewToken] = useState(null)
  const [error, setError] = useState('')
  const load = useCallback(() => aiApi.tokens().then(setTokens).catch((e) => setError(getErrorMessage(e))), [])
  useEffect(() => { load(); aiApi.setup().then(setSetup).catch(() => setSetup({ mcpDir: null })) }, [load])

  const create = async (e) => {
    e.preventDefault(); setError('')
    try {
      const r = await aiApi.createToken(form.name, form.expiresInDays ? Number(form.expiresInDays) : null)
      setNewToken(r.token); setCreating(false); load()
    } catch (err) { setError(getErrorMessage(err)) }
  }
  const revoke = async (t) => {
    if (!window.confirm(`Thu hồi khóa "${t.name}"? Trợ lý AI dùng khóa này sẽ mất kết nối ngay.`)) return
    try { await aiApi.revokeToken(t.id); load() } catch (err) { setError(getErrorMessage(err)) }
  }

  const dir = setup?.mcpDir ?? '<thư mục dự án>\\mcp'
  const token = newToken ?? '<dán khóa erp_... vào đây>'
  const installCmd = `powershell -ExecutionPolicy Bypass -File "${dir}\\cai-claude-desktop.ps1" -Token ${token} -ApiUrl ${apiUrl()}`
  const config = JSON.stringify({ mcpServers: { myerp: { command: 'node', args: [`${dir}\\server.js`], env: { ERP_API_URL: apiUrl(), ERP_TOKEN: token } } } }, null, 2)

  return (
    <div className="ai-page">
      <div className="page-head">
        <div><h1><i className="ti ti-robot" aria-hidden="true" /> Trợ lý AI</h1>
          <p className="muted small">Cho Claude (app Claude Desktop) xem và làm việc trong ERP bằng lời: hỏi doanh thu, đổi giá, bật sản phẩm lên web, tạo mã giảm giá, viết bài, giao việc...
            AI dùng <b>khóa truy cập của bạn</b> nên chỉ làm được những gì tài khoản bạn được phép; mọi thay đổi vẫn ghi nhật ký như thao tác thường.</p></div>
      </div>
      {error && <div className="alert error">{error}</div>}

      <div className="card">
        <div className="section-head first"><h2>1. Khóa truy cập</h2>
          <button className="btn primary" onClick={() => setCreating(true)}><i className="ti ti-key" aria-hidden="true" /> Tạo khóa</button></div>
        {newToken && (
          <div className="alert success">
            <b>Khóa mới - chỉ hiện 1 lần, chép ngay vào bước 2.</b>
            <div className="copy-box"><code className="grow">{newToken}</code><Copy text={newToken} /></div>
          </div>
        )}
        <table className="grid compact">
          <thead><tr><th>Tên</th><th>Khóa</th><th className="hide-sm">Dùng lần cuối</th><th>Hết hạn</th><th aria-label="Thao tác" /></tr></thead>
          <tbody>
            {!tokens && <tr><td colSpan={5} className="muted center">Đang tải...</td></tr>}
            {tokens?.length === 0 && <tr><td colSpan={5} className="muted center">Chưa có khóa nào.</td></tr>}
            {tokens?.map((t) => (
              <tr key={t.id} className={t.isActive ? '' : 'muted'}>
                <td>{t.name}</td>
                <td><code>{t.prefix}…</code></td>
                <td className="hide-sm small">{t.lastUsedAt ? formatDateTime(t.lastUsedAt) : 'Chưa dùng'}</td>
                <td className="small">{!t.isActive ? 'Đã thu hồi / hết hạn' : t.expiresAt ? formatDateTime(t.expiresAt) : 'Không hết hạn'}</td>
                <td>{t.isActive && <button className="btn ghost small danger-text" onClick={() => revoke(t)}>Thu hồi</button>}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="hint-inline top-gap">Khóa không dùng được cho việc quản lý người dùng, vai trò, mật khẩu và khóa khác. Lộ khóa (VD để quên trên máy lab) thì bấm Thu hồi ngay.</p>
      </div>

      <div className="card">
        <div className="section-head first"><h2>2. Cắm ERP vào Claude Desktop</h2></div>
        <ol className="steps">
          <li>Cài <b>Claude Desktop</b> (claude.ai/download) và đăng nhập tài khoản Claude của bạn. Máy cần có <b>Node.js</b>.</li>
          <li>Lần đầu: mở terminal ở thư mục <code>{dir}</code> chạy <code>npm install</code>.</li>
          <li>Chạy lệnh sau (tự thêm ERP vào cấu hình Claude Desktop, có sao lưu file cũ):
            <div className="copy-box"><code className="grow">{installCmd}</code><Copy text={installCmd} /></div>
          </li>
          <li><b>Thoát hẳn</b> Claude Desktop (chuột phải biểu tượng ở khay hệ thống → Quit) rồi mở lại. Trong ô chat sẽ thấy công cụ <b>myerp</b>.</li>
        </ol>
        <details className="top-gap">
          <summary className="small">Hoặc tự sửa file cấu hình (%APPDATA%\Claude\claude_desktop_config.json)</summary>
          <pre className="env-box">{config.replace(/erp_[A-Za-z0-9]+/, (m) => `${m.slice(0, 10)}…`)}</pre>
          <Copy text={config} label="Chép cấu hình" />
        </details>
        <p className="hint-inline top-gap">Claude Desktop hỏi bạn đồng ý mỗi khi AI muốn dùng công cụ. Đổi giá hàng loạt luôn hiện bảng xem trước, chỉ áp dụng khi bạn đồng ý.</p>
      </div>

      <div className="card">
        <div className="section-head first"><h2>3. Thử ra lệnh</h2></div>
        <ul className="examples">{EXAMPLES.map((x) => <li key={x}><span>{x}</span><Copy text={x} label="" /></li>)}</ul>
      </div>

      {creating && (
        <Modal title="Tạo khóa truy cập cho AI" onClose={() => setCreating(false)} size="small">
          <form onSubmit={create}>
            <label>Tên khóa (để nhớ dùng ở đâu)<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} autoFocus maxLength={100} /></label>
            <label className="top-gap block">Hết hạn sau
              <select value={form.expiresInDays} onChange={(e) => setForm({ ...form, expiresInDays: e.target.value })}>
                <option value="7">7 ngày (máy lab, dùng thử)</option><option value="30">30 ngày</option><option value="90">90 ngày</option>
                <option value="365">1 năm</option><option value="">Không hết hạn</option>
              </select></label>
            {error && <p className="error">{error}</p>}
            <div className="modal-foot"><button type="button" className="btn" onClick={() => setCreating(false)}>Hủy</button><button className="btn primary">Tạo khóa</button></div>
          </form>
        </Modal>
      )}
    </div>
  )
}
