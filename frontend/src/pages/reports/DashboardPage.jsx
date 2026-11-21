import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { reportApi } from '../../api/retailApi'
import { RETAIL_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateOnly, formatMoney, formatMoneyShort, formatQty } from '../../utils/format'

const PERIODS = [{ days: 7, label: '7 ngày' }, { days: 30, label: '30 ngày' }, { days: 90, label: '90 ngày' }]
/** API trả tên trạng thái tiếng Việt (ReportService.statusNames) → màu nhãn */
const STATUS_CSS = { 'Nháp': 'draft', 'Đã xác nhận': 'confirmed', 'Hoàn thành': 'completed', 'Đã hủy': 'cancelled' }

/** Ô chỉ số: giá trị + % so với kỳ trước (mũi tên + chữ, không chỉ dựa vào màu) */
function Kpi({ label, kpi, money = true, hint }) {
  const change = kpi?.changePercent
  return (
    <div className="kpi">
      <span className="muted small">{label}</span>
      <b>{kpi ? (money ? formatMoney(Math.round(kpi.value)) : formatQty(kpi.value)) : '…'}</b>
      {change !== null && change !== undefined && (
        <span className={`small change ${change >= 0 ? 'up' : 'down'}`}>
          <i className={`ti ti-arrow-${change >= 0 ? 'up' : 'down'}-right`} aria-hidden="true" />
          {change >= 0 ? '+' : ''}{change}% so với kỳ trước
        </span>
      )}
      {hint && <span className="small muted">{hint}</span>}
    </div>
  )
}

/** Cột doanh thu theo ngày (1 chuỗi, 1 màu). Rê chuột: tooltip ngày / doanh thu / lãi / số đơn. */
function RevenueChart({ data }) {
  const [hover, setHover] = useState(null)
  const max = Math.max(...data.map((d) => d.revenue), 1)
  const step = max > 0 ? niceStep(max / 4) : 1
  const top = Math.ceil(max / step) * step
  const ticks = [0, 1, 2, 3, 4].map((i) => (top / 4) * i).filter((t, i, a) => a.indexOf(t) === i)
  const labelEvery = Math.ceil(data.length / 8)

  return (
    <div className="bar-chart" onMouseLeave={() => setHover(null)}>
      <div className="bar-axis">
        <div className="bar-area">
          {ticks.map((t) => <span key={t} style={{ bottom: `${(t / top) * 100}%` }}>{formatMoneyShort(t)}</span>)}
        </div>
      </div>
      <div className="bar-plot">
        <div className="bar-area">
        {ticks.map((t) => <div key={t} className="bar-grid" style={{ bottom: `${(t / top) * 100}%` }} />)}
        <div className="bar-cols">
          {data.map((d, i) => (
            <div key={d.date} className={`bar-col${hover === i ? ' on' : ''}`} onMouseEnter={() => setHover(i)}
              tabIndex={0} onFocus={() => setHover(i)} onBlur={() => setHover(null)}
              aria-label={`${formatDateOnly(d.date)}: ${formatMoney(Math.round(d.revenue))}, ${d.orders} đơn`}>
              <div className="bar" style={{ height: `${(d.revenue / top) * 100}%` }} />
              <span className="bar-label">{i % labelEvery === 0 ? formatDateOnly(d.date).slice(0, 5) : ''}</span>
            </div>
          ))}
        </div>
        {hover !== null && data[hover] && (
          <div className="chart-tip" style={{ left: `${((hover + 0.5) / data.length) * 100}%` }}>
            <b>{formatDateOnly(data[hover].date)}</b>
            <div>Doanh thu: {formatMoney(Math.round(data[hover].revenue))}</div>
            <div>Lãi gộp: {formatMoney(Math.round(data[hover].grossProfit))}</div>
            <div>{data[hover].orders} đơn</div>
          </div>
        )}
        </div>
      </div>
    </div>
  )
}

function niceStep(raw) {
  const pow = 10 ** Math.floor(Math.log10(raw))
  const n = raw / pow
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * pow
}

/** Thanh ngang so sánh độ lớn (kênh bán, nhóm hàng). Tên + giá trị là chữ, thanh chỉ minh họa. */
function HBars({ items, total }) {
  const max = Math.max(...items.map((i) => i.value), 1)
  if (items.length === 0) return <p className="muted">Chưa có dữ liệu.</p>
  return (
    <div className="hbars">
      {items.map((it) => (
        <div key={it.name} className="hbar" title={`${it.name}: ${formatMoney(Math.round(it.value))} · ${formatQty(it.quantity)} sp`}>
          <div className="hbar-head">
            <span>{it.name}</span>
            <span><b>{formatMoneyShort(it.value)}</b> <span className="muted small">{total ? Math.round((it.value / total) * 100) : 0}%</span></span>
          </div>
          <div className="hbar-track"><div className="hbar-fill" style={{ width: `${(it.value / max) * 100}%` }} /></div>
        </div>
      ))}
    </div>
  )
}

/** Tổng quan kinh doanh: doanh thu, lãi gộp, đơn hàng, kênh bán, nhóm hàng, sản phẩm bán chạy, hàng sắp hết. */
export default function DashboardPage() {
  const { can } = useAuth()
  const [days, setDays] = useState(30)
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [showTable, setShowTable] = useState(false)

  useEffect(() => {
    setError('')
    reportApi.dashboard(days).then(setData).catch((err) => setError(getErrorMessage(err)))
  }, [days])

  const revenueTotal = data?.revenue.value ?? 0
  const margin = revenueTotal > 0 ? Math.round((data.grossProfit.value / revenueTotal) * 100) : 0

  return (
    <div className="dashboard">
      <div className="page-head">
        <div>
          <h1>Báo cáo kinh doanh</h1>
          <p className="muted small kpi-line">Doanh thu = đơn đã xác nhận / hoàn thành, sau giảm giá, không tính phí giao hàng.</p>
        </div>
        <div className="segmented no-margin" role="tablist" aria-label="Khoảng thời gian">
          {PERIODS.map((p) => (
            <button key={p.days} role="tab" aria-selected={days === p.days} className={days === p.days ? 'on' : ''} onClick={() => setDays(p.days)}>{p.label}</button>
          ))}
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="kpi-row">
        <Kpi label="Doanh thu" kpi={data?.revenue} />
        <Kpi label="Lãi gộp" kpi={data?.grossProfit} hint={data ? `Biên lãi ${margin}%` : null} />
        <Kpi label="Số đơn" kpi={data?.orders} money={false} />
        <Kpi label="Giá trị TB / đơn" kpi={data?.averageOrderValue} />
      </div>
      <div className="kpi-row">
        <div className="kpi">
          <span className="muted small">Khách còn nợ</span>
          <b className={data?.receivableOutstanding ? 'warn-text' : ''}>{data ? formatMoney(Math.round(data.receivableOutstanding)) : '…'}</b>
          <Link className="small" to="/orders">Xem đơn hàng</Link>
        </div>
        <div className="kpi">
          <span className="muted small">Giá trị hàng tồn (giá vốn)</span>
          <b>{data ? formatMoney(Math.round(data.stockValue)) : '…'}</b>
          {can(RETAIL_PERMISSIONS.INVENTORY_VIEW) && <Link className="small" to="/inventory/stock">Xem tồn kho</Link>}
        </div>
        <div className="kpi">
          <span className="muted small">Trạng thái đơn trong kỳ</span>
          <div className="status-counts">
            {data?.ordersByStatus.map((s) => (
              <span key={s.name} className={`pill ${STATUS_CSS[s.name] ?? ''}`} title={formatMoney(Math.round(s.value))}>{s.name}: {formatQty(s.quantity)} đơn</span>
            ))}
          </div>
        </div>
      </div>

      <div className="card chart-card">
        <div className="section-head first">
          <h2>Doanh thu theo ngày</h2>
          <button className="btn ghost" onClick={() => setShowTable(!showTable)}>
            <i className={`ti ti-${showTable ? 'chart-bar' : 'table'}`} aria-hidden="true" /> {showTable ? 'Xem biểu đồ' : 'Xem bảng'}
          </button>
        </div>
        {!data ? <p className="muted">Đang tải...</p> : showTable ? (
          <div className="table-wrap scroll-y">
            <table className="grid">
              <thead><tr><th>Ngày</th><th className="num">Số đơn</th><th className="num">Doanh thu</th><th className="num">Lãi gộp</th></tr></thead>
              <tbody>
                {data.revenueByDay.slice().reverse().map((d) => (
                  <tr key={d.date}><td>{formatDateOnly(d.date)}</td><td className="num">{d.orders}</td>
                    <td className="num">{formatMoney(Math.round(d.revenue))}</td><td className="num">{formatMoney(Math.round(d.grossProfit))}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : <RevenueChart data={data.revenueByDay} />}
      </div>

      <div className="two-col">
        <div className="card">
          <div className="section-head first"><h2>Doanh thu theo kênh bán</h2></div>
          {data && <HBars items={data.revenueByChannel} total={revenueTotal} />}
        </div>
        <div className="card">
          <div className="section-head first"><h2>Doanh thu theo nhóm hàng</h2></div>
          {data && <HBars items={data.revenueByCategory} total={revenueTotal} />}
        </div>
      </div>

      <div className="two-col">
        <div className="card">
          <div className="section-head first"><h2>Sản phẩm bán chạy</h2></div>
          <table className="grid compact">
            <thead><tr><th>#</th><th>Sản phẩm</th><th className="num">Đã bán</th><th className="num">Doanh thu</th></tr></thead>
            <tbody>
              {data?.topProducts.length === 0 && <tr><td colSpan={4} className="muted center">Chưa có dữ liệu.</td></tr>}
              {data?.topProducts.map((p, i) => (
                <tr key={p.modelId}>
                  <td className="muted">{i + 1}</td>
                  <td>{can(RETAIL_PERMISSIONS.INVENTORY_VIEW) ? <Link to={`/inventory/products/${p.modelId}`}>{p.name}</Link> : p.name}
                    <div className="muted small">Lãi {formatMoneyShort(p.grossProfit)}</div></td>
                  <td className="num">{formatQty(p.quantity)}</td>
                  <td className="num">{formatMoneyShort(p.revenue)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="card">
          <div className="section-head first">
            <h2>Hàng sắp hết</h2>
            {can(RETAIL_PERMISSIONS.INVENTORY_VIEW) && <Link to="/inventory/stock?low=1" className="small">Xem tất cả</Link>}
          </div>
          <table className="grid compact">
            <thead><tr><th>Sản phẩm</th><th className="num">Còn</th><th className="num">Tối thiểu</th></tr></thead>
            <tbody>
              {data?.lowStock.length === 0 && <tr><td colSpan={3} className="muted center">Không có mặt hàng nào sắp hết.</td></tr>}
              {data?.lowStock.map((p) => (
                <tr key={p.productId}>
                  <td>{p.name}<div className="muted small">{p.code}</div></td>
                  <td className="num"><b className={p.onHand <= 0 ? 'error' : 'warn-text'}>{formatQty(p.onHand)}</b></td>
                  <td className="num muted">{formatQty(p.minStock)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {can(RETAIL_PERMISSIONS.PURCHASING_CREATE) && (
            <Link className="btn top-gap" to="/purchasing/orders/new"><i className="ti ti-basket-down" aria-hidden="true" /> Tạo đơn nhập hàng</Link>
          )}
        </div>
      </div>
    </div>
  )
}
