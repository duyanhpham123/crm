#!/usr/bin/env node
/**
 * MCP server cho MyERP - để trợ lý AI (Claude Desktop, Claude Code...) xem và thao tác dữ liệu ERP.
 *
 * - Gọi REST API của ERP bằng KHÓA TRUY CẬP CÁ NHÂN (ERP > nút robot trên thanh trên cùng > Kết nối AI):
 *   AI có đúng quyền của chủ khóa, mọi thao tác vẫn qua kiểm tra quyền / dữ liệu / ghi nhật ký của ERP.
 * - Thao tác hàng loạt (đổi giá) luôn XEM TRƯỚC; chỉ áp dụng khi gọi lại với apply=true.
 * - Chạy qua stdio: KHÔNG in gì ra stdout ngoài giao thức MCP (log dùng console.error).
 *
 * Biến môi trường: ERP_API_URL (mặc định http://localhost:5121), ERP_TOKEN (khóa erp_...).
 */
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { z } from 'zod'

const BASE = (process.env.ERP_API_URL || 'http://localhost:5121').replace(/\/+$/, '')
const TOKEN = process.env.ERP_TOKEN || ''
const MAX_BULK = 300

// ---------------------------------------------------------------- gọi ERP

class ErpError extends Error {
  constructor(status, message) { super(message); this.status = status }
}

async function erp(method, path, { query, body } = {}) {
  if (!TOKEN) throw new ErpError(0, 'Chưa cấu hình ERP_TOKEN. Tạo khóa ở ERP > Kết nối AI rồi đặt vào cấu hình Claude Desktop.')
  const url = new URL(BASE + path)
  for (const [k, v] of Object.entries(query ?? {})) if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, String(v))
  let res
  try {
    res = await fetch(url, {
      method,
      headers: { Authorization: `Bearer ${TOKEN}`, Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(30_000),
    })
  } catch (e) {
    throw new ErpError(0, `Không kết nối được ERP tại ${BASE} (${e.message}). Backend có đang chạy không?`)
  }
  const text = await res.text()
  let data = null
  if (text) { try { data = JSON.parse(text) } catch { data = text } }
  if (!res.ok) {
    const msg = data?.title || data?.detail || (res.status === 401 ? 'Khóa truy cập sai, đã thu hồi hoặc hết hạn.' : `ERP trả lỗi ${res.status}`)
    throw new ErpError(res.status, res.status === 403 ? `Không có quyền: ${msg}` : msg)
  }
  return data
}

const ok = (data) => ({ content: [{ type: 'text', text: typeof data === 'string' ? data : JSON.stringify(data, null, 2) }] })
const fail = (e) => ({ isError: true, content: [{ type: 'text', text: e instanceof ErpError ? e.message : `Lỗi: ${e.message}` }] })

/** Bọc handler: lỗi ERP trả về cho AI dưới dạng thông báo (AI đọc và giải thích cho người dùng). */
const tool = (fn) => async (args) => { try { return ok(await fn(args ?? {})) } catch (e) { return fail(e) } }

const round = (n) => Math.round(Number(n) || 0)
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Ngày dạng yyyy-MM-dd')

// ---------------------------------------------------------------- tra cứu giúp

async function findModel(codeOrName) {
  const q = String(codeOrName).trim()
  const page = await erp('GET', '/api/inventory/models', { query: { search: q, pageSize: 50 } })
  const items = page.items ?? []
  const exact = items.find((m) => m.code.toLowerCase() === q.toLowerCase())
  if (exact) return exact
  if (items.length === 1) return items[0]
  if (items.length === 0) throw new ErpError(404, `Không tìm thấy mẫu sản phẩm "${q}".`)
  throw new ErpError(400, `"${q}" khớp nhiều mẫu: ${items.slice(0, 10).map((m) => `${m.code} (${m.name})`).join(', ')}. Hãy dùng mã mẫu.`)
}

async function findSite(siteIdOrName) {
  const sites = await erp('GET', '/api/website/sites')
  if (siteIdOrName === undefined || siteIdOrName === null || siteIdOrName === '') {
    if (sites.length === 1) return sites[0]
    throw new ErpError(400, `Có ${sites.length} website, hãy chọn: ${sites.map((s) => `${s.id} = ${s.name} (${s.domain})`).join('; ')}.`)
  }
  const key = String(siteIdOrName).toLowerCase()
  const site = sites.find((s) => String(s.id) === key || s.domain.toLowerCase() === key || s.name.toLowerCase() === key)
    ?? sites.find((s) => s.name.toLowerCase().includes(key) || s.domain.toLowerCase().includes(key))
  if (!site) throw new ErpError(404, `Không có website "${siteIdOrName}". Danh sách: ${sites.map((s) => `${s.id} = ${s.name}`).join('; ')}.`)
  return site
}

// ---------------------------------------------------------------- server

const server = new McpServer({ name: 'myerp', version: '0.1.0' }, {
  instructions: [
    'Bạn đang làm việc với MyERP - phần mềm quản lý shop thời trang (quần áo, giày dép) của người dùng. Trả lời bằng tiếng Việt.',
    'Tiền là VND (đ). Ngày theo giờ Việt Nam, dạng yyyy-MM-dd.',
    'Mẫu sản phẩm (model, VD ATB01) có nhiều biến thể màu - size (SKU, VD ATB01-DEN-M). Giá / tồn kho nằm ở từng SKU.',
    'Website bán hàng đọc dữ liệu thẳng từ ERP: sửa giá, bật sản phẩm, viết bài ở ERP là website đổi theo.',
    'Đổi giá hàng loạt: LUÔN gọi update_prices với apply=false trước, cho người dùng xem bảng thay đổi, chỉ gọi apply=true khi họ đồng ý rõ ràng.',
    'Nếu công cụ báo "Không có quyền", giải thích người dùng cần được cấp quyền trong ERP; đừng thử cách khác để vượt quyền.',
  ].join('\n'),
})

const RO = { readOnlyHint: true, openWorldHint: false }
const WRITE = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false }

server.registerTool('whoami', {
  title: 'Tài khoản đang dùng',
  description: 'Xem khóa truy cập đang chạy bằng tài khoản nào, công ty nào, có những quyền gì. Gọi khi cần biết mình được làm gì.',
  annotations: RO,
}, tool(async () => {
  const me = await erp('GET', '/api/me')
  return { user: me.fullName, userName: me.userName, company: me.companyName ?? me.companyId, permissions: me.permissions }
}))

server.registerTool('get_sales_report', {
  title: 'Báo cáo kinh doanh',
  description: 'Doanh thu, lãi gộp, số đơn, giá trị TB/đơn (so với kỳ trước cùng độ dài), doanh thu theo ngày/tuần/tháng, theo kênh bán, nhóm hàng, top sản phẩm, hàng sắp hết, công nợ khách, giá trị tồn kho. Mặc định 30 ngày gần nhất.',
  inputSchema: { from: isoDate.optional().describe('Từ ngày (tính cả ngày này)'), to: isoDate.optional().describe('Đến ngày (tính cả ngày này)') },
  annotations: RO,
}, tool(async ({ from, to }) => {
  const d = await erp('GET', '/api/reports/dashboard', { query: from || to ? { from, to } : { days: 30 } })
  const pct = (k) => (k.previousValue ? Math.round(((k.value - k.previousValue) / k.previousValue) * 1000) / 10 : null)
  const kpi = (k) => ({ value: round(k.value), previous: round(k.previousValue), changePercent: pct(k) })
  return {
    period: `${d.from} → ${d.to} (${d.days} ngày)`, comparedWith: `${d.previousFrom} → ${d.previousTo}`,
    revenue: kpi(d.revenue), grossProfit: kpi(d.grossProfit), orders: kpi(d.orders), averageOrderValue: kpi(d.averageOrderValue),
    receivableOutstanding: round(d.receivableOutstanding), stockValue: round(d.stockValue),
    byChannel: d.revenueByChannel.map((x) => ({ channel: x.name, revenue: round(x.value), orders: x.quantity })),
    byCategory: d.revenueByCategory.map((x) => ({ category: x.name, revenue: round(x.value), quantity: x.quantity })),
    topProducts: d.topProducts.map((p) => ({ code: p.code, name: p.name, sold: p.quantity, revenue: round(p.revenue), grossProfit: round(p.grossProfit) })),
    lowStock: d.lowStock.map((p) => ({ sku: p.code, name: p.name, onHand: p.onHand, min: p.minStock })),
    ordersByStatus: d.ordersByStatus.map((s) => ({ status: s.name, orders: s.quantity })),
    series: { granularity: d.granularity, points: d.revenueByDay.map((x) => ({ date: x.date, revenue: round(x.revenue), orders: x.orders })) },
  }
}))

server.registerTool('search_products', {
  title: 'Tìm mẫu sản phẩm',
  description: 'Tìm mẫu sản phẩm theo tên hoặc mã (để trống = tất cả). Trả về mã mẫu, giá, tổng tồn, số SKU sắp hết.',
  inputSchema: { search: z.string().optional().describe('Tên hoặc mã, VD "giày sneaker", "ATB01"'), page: z.number().int().min(1).optional() },
  annotations: RO,
}, tool(async ({ search, page }) => {
  const r = await erp('GET', '/api/inventory/models', { query: { search, page, pageSize: 50 } })
  return {
    total: r.totalCount, page: r.page,
    models: r.items.map((m) => ({ code: m.code, name: m.name, category: m.categoryName, price: m.minPrice === m.maxPrice ? round(m.salePrice) : `${round(m.minPrice)} - ${round(m.maxPrice)}`, totalStock: m.totalStock, variants: m.variantCount, lowStockVariants: m.lowStockVariants, active: m.isActive })),
  }
}))

server.registerTool('get_product', {
  title: 'Chi tiết mẫu sản phẩm',
  description: 'Chi tiết 1 mẫu: mô tả, chất liệu và từng SKU màu - size với giá bán, giá vốn, tồn kho.',
  inputSchema: { model: z.string().describe('Mã mẫu (VD ATB01) hoặc tên') },
  annotations: RO,
}, tool(async ({ model }) => {
  const m = await findModel(model)
  const d = await erp('GET', `/api/inventory/models/${m.id}`)
  return {
    code: d.code, name: d.name, category: d.categoryName, brand: d.brandName, material: d.material, season: d.season, description: d.description, active: d.isActive,
    variants: d.variants.map((v) => ({ sku: v.code, color: v.color, size: v.size, price: round(v.salePrice), cost: round(v.costPrice), onHand: v.onHand, minStock: v.minStock, active: v.isActive })),
  }
}))

server.registerTool('low_stock', {
  title: 'Hàng sắp hết',
  description: 'Các SKU có tồn kho bằng hoặc dưới mức tối thiểu - dùng khi cần lên kế hoạch nhập hàng.',
  annotations: RO,
}, tool(async () => {
  const r = await erp('GET', '/api/inventory/stock', { query: { lowOnly: true, pageSize: 100 } })
  return { count: r.rows.totalCount, items: r.rows.items.map((s) => ({ sku: s.code, name: s.name, warehouse: s.warehouseName, onHand: s.onHand, min: s.minStock })) }
}))

server.registerTool('list_orders', {
  title: 'Danh sách đơn hàng',
  description: 'Đơn bán hàng, lọc theo trạng thái (draft = nháp / chờ xác nhận, confirmed, completed, cancelled), kênh (direct, facebook, shopee, tiktok, lazada, website, zalo, phone), khoảng ngày, tìm theo mã đơn / tên / SĐT khách.',
  inputSchema: {
    status: z.enum(['draft', 'confirmed', 'completed', 'cancelled']).optional(),
    channel: z.string().optional(), from: isoDate.optional(), to: isoDate.optional(), search: z.string().optional(), page: z.number().int().min(1).optional(),
  },
  annotations: RO,
}, tool(async (a) => {
  const r = await erp('GET', '/api/sales/orders', { query: { ...a, pageSize: 50 } })
  return {
    total: r.rows.totalCount, page: r.rows.page, summary: r.summary,
    orders: r.rows.items.map((o) => ({ orderNo: o.docNo, date: o.orderDate, channel: o.channel, customer: o.customerName, phone: o.customerPhone, items: o.itemCount, total: round(o.totalAmount), paid: round(o.amountPaid), status: o.status, payment: o.paymentStatus })),
  }
}))

server.registerTool('get_order', {
  title: 'Chi tiết đơn hàng',
  description: 'Chi tiết 1 đơn theo mã (VD DH2611-00105): khách, địa chỉ giao, từng dòng hàng, thanh toán, lãi gộp.',
  inputSchema: { orderNo: z.string() },
  annotations: RO,
}, tool(async ({ orderNo }) => {
  const r = await erp('GET', '/api/sales/orders', { query: { search: orderNo.trim(), pageSize: 5 } })
  const hit = r.rows.items.find((o) => o.docNo.toLowerCase() === orderNo.trim().toLowerCase()) ?? r.rows.items[0]
  if (!hit) throw new ErpError(404, `Không tìm thấy đơn ${orderNo}.`)
  const o = await erp('GET', `/api/sales/orders/${hit.id}`)
  return {
    orderNo: o.docNo, date: o.orderDate, channel: o.channel, status: o.status, payment: o.paymentStatus, delivery: o.deliveryStatus,
    customer: o.customerName, receiver: o.receiverName, phone: o.receiverPhone, address: o.shippingAddress, note: o.note, promotionCode: o.promotionCode,
    lines: o.lines.map((l) => ({ sku: l.code, name: l.name, qty: l.quantity, price: round(l.unitPrice), discountPercent: l.discountPercent, total: round(l.lineTotal) })),
    subTotal: round(o.subTotal), discount: round(o.discountAmount), shipping: round(o.shippingFee), total: round(o.totalAmount), paid: round(o.amountPaid), due: round(o.amountDue), grossProfit: round(o.grossProfit),
  }
}))

server.registerTool('search_customers', {
  title: 'Tìm khách hàng',
  description: 'Tìm khách hàng theo tên, mã, số điện thoại hoặc mã số thuế.',
  inputSchema: { search: z.string().optional() },
  annotations: RO,
}, tool(async ({ search }) => {
  const r = await erp('GET', '/api/crm/customers', { query: { search, pageSize: 30 } })
  return { total: r.totalCount, customers: r.items.map((c) => ({ code: c.code, name: c.name, phone: c.phone, email: c.email, type: c.partnerType })) }
}))

server.registerTool('list_websites', {
  title: 'Danh sách website',
  description: 'Các website bán hàng nối với ERP (id, tên, tên miền, số mẫu đang bày, trạng thái kết nối).',
  annotations: RO,
}, tool(async () => (await erp('GET', '/api/website/sites')).map((s) => ({ id: s.id, name: s.name, domain: s.domain, active: s.isActive, connected: s.hasApiKey, productsListed: s.productCount, lastSync: s.lastSyncStatus }))))

server.registerTool('website_products', {
  title: 'Sản phẩm trên website',
  description: 'Mẫu sản phẩm đang hiện / đang ẩn / nổi bật trên 1 website, kèm giá trên web (giá riêng nếu có) và tồn kho.',
  inputSchema: { site: z.union([z.string(), z.number()]).optional().describe('Id, tên hoặc tên miền website'), state: z.enum(['published', 'hidden', 'featured']).optional(), search: z.string().optional() },
  annotations: RO,
}, tool(async ({ site, state, search }) => {
  const s = await findSite(site)
  const r = await erp('GET', '/api/website/products', { query: { siteId: s.id, state, search, pageSize: 100 } })
  return { website: `${s.name} (${s.domain})`, total: r.totalCount, products: r.items.map((p) => ({ code: p.code, name: p.name, published: p.isPublished, featured: p.isFeatured, priceOnWeb: round(p.priceOverride ?? p.salePrice), priceOverride: p.priceOverride, stock: p.stock })) }
}))

server.registerTool('list_promotions', {
  title: 'Mã giảm giá',
  description: 'Các mã giảm giá: loại, giá trị, thời gian, số lượt đã dùng, doanh thu mang lại. state: active | scheduled | expired | inactive | used_up.',
  inputSchema: { state: z.enum(['active', 'scheduled', 'expired', 'inactive', 'used_up']).optional() },
  annotations: RO,
}, tool(async ({ state }) => (await erp('GET', '/api/marketing/promotions', { query: { state } }))
  .map((p) => ({ code: p.code, name: p.name, type: p.type, value: p.value, maxDiscount: p.maxDiscount, minOrder: p.minOrderAmount, start: p.startAt, end: p.endAt, used: p.usedCount, limit: p.usageLimit, channels: p.channels, state: p.state, revenue: round(p.revenue) }))))

server.registerTool('list_tasks', {
  title: 'Công việc',
  description: 'Công việc trong app Dự án & công việc. assignee: "me" (của tôi) hoặc để trống (mọi người trong phạm vi được xem); status: open | overdue | done.',
  inputSchema: { assignee: z.enum(['me', 'none']).optional(), status: z.enum(['open', 'overdue', 'done']).optional(), search: z.string().optional() },
  annotations: RO,
}, tool(async (a) => {
  const b = await erp('GET', '/api/projects/tasks', { query: a })
  const stage = Object.fromEntries(b.stages.map((s) => [s.id, s.name]))
  return { total: b.total, tasks: b.tasks.map((t) => ({ code: t.code, title: t.title, project: t.projectName, assignee: t.assigneeName, due: t.dueDate, overdue: t.isOverdue, stage: stage[t.stageId], priority: t.priority, progress: t.progressPercent })) }
}))

// ---------------------------------------------------------------- thao tác ghi

server.registerTool('update_prices', {
  title: 'Đổi giá bán',
  description: [
    'Đổi giá bán SKU trong Kho (website và bán hàng dùng chung giá này; website có "giá riêng" thì dùng set_website_product).',
    'Chọn hàng: model (mã mẫu - mọi màu size), skus (danh sách SKU), hoặc category (tên nhóm hàng, VD "Giày sneaker").',
    'Cách đổi: mode=set (đặt đúng giá value), percent (tăng/giảm %, VD -10), amount (cộng/trừ tiền, VD -20000). Giá làm tròn tới roundTo đ (mặc định 1000).',
    'LUÔN gọi với apply=false trước để xem bảng thay đổi; chỉ apply=true khi người dùng đồng ý.',
  ].join(' '),
  inputSchema: {
    model: z.string().optional(), skus: z.array(z.string()).max(MAX_BULK).optional(), category: z.string().optional(),
    mode: z.enum(['set', 'percent', 'amount']), value: z.number(), roundTo: z.number().int().min(1).max(100000).optional(),
    apply: z.boolean().default(false),
  },
  annotations: { ...WRITE, destructiveHint: true },
}, tool(async ({ model, skus, category, mode, value, roundTo = 1000, apply }) => {
  if (!model && !skus?.length && !category) throw new ErpError(400, 'Chọn hàng cần đổi giá: model, skus hoặc category.')
  if (mode === 'percent' && (value <= -90 || value > 300)) throw new ErpError(400, 'Phần trăm từ -90% đến +300%.')
  // Gom các mẫu liên quan
  let models = []
  if (model) models = [await findModel(model)]
  else if (category) {
    const lk = await erp('GET', '/api/inventory/lookups')
    const cat = (lk.categories ?? []).find((c) => c.name.toLowerCase() === category.trim().toLowerCase())
    if (!cat) throw new ErpError(404, `Không có nhóm hàng "${category}". Có: ${(lk.categories ?? []).map((c) => c.name).join(', ')}.`)
    for (let page = 1; ; page++) {
      const r = await erp('GET', '/api/inventory/models', { query: { categoryId: cat.id, page, pageSize: 100 } })
      models.push(...r.items)
      if (models.length >= r.totalCount || r.items.length === 0) break
    }
    if (!models.length) throw new ErpError(404, `Nhóm "${category}" chưa có mẫu nào.`)
  } else {
    const prefixes = [...new Set(skus.map((s) => s.trim().toUpperCase().split('-')[0]))]
    for (const p of prefixes) models.push(await findModel(p))
  }
  const wanted = skus?.length ? new Set(skus.map((s) => s.trim().toUpperCase())) : null
  const changes = []
  for (const m of models) {
    const d = await erp('GET', `/api/inventory/models/${m.id}`)
    for (const v of d.variants) {
      if (wanted && !wanted.has(v.code.toUpperCase())) continue
      if (!v.isActive) continue
      const old = round(v.salePrice)
      let next = mode === 'set' ? value : mode === 'percent' ? old * (1 + value / 100) : old + value
      next = Math.max(0, Math.round(next / roundTo) * roundTo)
      if (next !== old) changes.push({ id: v.id, sku: v.code, name: `${d.name} ${[v.color, v.size].filter(Boolean).join(' ')}`.trim(), oldPrice: old, newPrice: next, barcode: v.barcode, minStock: v.minStock })
    }
  }
  if (wanted) {
    const found = new Set(changes.map((c) => c.sku.toUpperCase()))
    const missing = [...wanted].filter((s) => !found.has(s))
    if (missing.length && !changes.length) throw new ErpError(404, `Không tìm thấy (hoặc giá không đổi) SKU: ${missing.join(', ')}.`)
  }
  if (changes.length > MAX_BULK) throw new ErpError(400, `Quá nhiều SKU (${changes.length}) - mỗi lần tối đa ${MAX_BULK}. Hãy chia nhỏ theo mẫu / nhóm hàng.`)
  const table = changes.map(({ sku, name, oldPrice, newPrice }) => ({ sku, name, oldPrice, newPrice }))
  if (!apply) return { preview: true, count: changes.length, changes: table, note: 'Chưa đổi gì. Gọi lại với apply=true sau khi người dùng đồng ý.' }
  const done = []
  const failed = []
  for (const c of changes) {
    try {
      await erp('PUT', `/api/inventory/products/${c.id}`, { body: { salePrice: c.newPrice, barcode: c.barcode, minStock: c.minStock, isActive: true } })
      done.push(c.sku)
    } catch (e) { failed.push({ sku: c.sku, error: e.message }) }
  }
  return { applied: true, updated: done.length, failed, changes: table.filter((t) => done.includes(t.sku)), note: 'Website đọc giá từ ERP nên đã đổi theo.' }
}))

server.registerTool('set_website_product', {
  title: 'Bày / ẩn sản phẩm trên website',
  description: 'Bật hoặc tắt 1 mẫu sản phẩm trên 1 website, đặt giá riêng cho website đó (priceOverride, null = dùng giá Kho) và đánh dấu nổi bật (lên trang chủ).',
  inputSchema: {
    site: z.union([z.string(), z.number()]).optional().describe('Id, tên hoặc tên miền website'), model: z.string().describe('Mã mẫu, VD GSN14'),
    isPublished: z.boolean(), priceOverride: z.number().min(0).nullable().optional(), isFeatured: z.boolean().optional(),
  },
  annotations: WRITE,
}, tool(async ({ site, model, isPublished, priceOverride, isFeatured }) => {
  const s = await findSite(site)
  const m = await findModel(model)
  const current = (await erp('GET', '/api/website/products', { query: { siteId: s.id, search: m.code, pageSize: 10 } })).items.find((x) => x.modelId === m.id)
  const r = await erp('PUT', `/api/website/products/${m.id}`, {
    query: { siteId: s.id },
    body: { isPublished, priceOverride: priceOverride === undefined ? current?.priceOverride ?? null : priceOverride, isFeatured: isFeatured ?? current?.isFeatured ?? false },
  })
  return { website: `${s.name} (${s.domain})`, model: r.code, name: r.name, published: r.isPublished, featured: r.isFeatured, priceOnWeb: round(r.priceOverride ?? r.salePrice) }
}))

server.registerTool('create_promotion', {
  title: 'Tạo mã giảm giá',
  description: 'Tạo mã giảm giá dùng ở đơn hàng và website. type: percent (giảm %, có thể kèm maxDiscount), fixed (giảm số tiền), free_ship. Thời gian theo giờ Việt Nam.',
  inputSchema: {
    code: z.string().min(3).max(30).describe('VD SALE10 - chữ không dấu, số, - _'), name: z.string().min(2),
    type: z.enum(['percent', 'fixed', 'free_ship']), value: z.number().min(0), maxDiscount: z.number().min(0).nullable().optional(),
    minOrderAmount: z.number().min(0).default(0), startDate: isoDate, endDate: isoDate, usageLimit: z.number().int().min(1).nullable().optional(),
    channels: z.string().nullable().optional().describe('Kênh áp dụng, cách nhau dấu phẩy (VD "website,facebook"); bỏ trống = mọi kênh'),
  },
  annotations: WRITE,
}, tool(async (a) => {
  const p = await erp('POST', '/api/marketing/promotions', {
    body: { code: a.code, name: a.name, type: a.type, value: a.value, maxDiscount: a.maxDiscount ?? null, minOrderAmount: a.minOrderAmount ?? 0,
      startAt: `${a.startDate}T00:00:00`, endAt: `${a.endDate}T23:59:59`, usageLimit: a.usageLimit ?? null, channels: a.channels ?? null, campaignId: null, isActive: true },
  })
  return { created: true, code: p.code, name: p.name, state: p.state, start: p.startAt, end: p.endAt }
}))

server.registerTool('create_blog_post', {
  title: 'Viết bài lên website',
  description: 'Tạo bài viết blog trên 1 website (nội dung văn bản thuần, xuống dòng bình thường). publish=false thì lưu nháp để người dùng duyệt trong ERP.',
  inputSchema: {
    site: z.union([z.string(), z.number()]).optional(), title: z.string().min(3).max(255), summary: z.string().max(1000).optional(),
    content: z.string().min(10), publish: z.boolean().default(false), metaDescription: z.string().max(500).optional(),
  },
  annotations: WRITE,
}, tool(async ({ site, title, summary, content, publish, metaDescription }) => {
  const s = await findSite(site)
  const p = await erp('POST', '/api/website/posts', {
    query: { siteId: s.id },
    body: { title, slug: null, summary: summary ?? null, content, thumbnailUrl: null, categoryId: null, metaTitle: null, metaDescription: metaDescription ?? null, isPublished: publish },
  })
  return { website: `${s.name} (${s.domain})`, title: p.title, url: `/blog/${p.slug}`, published: p.isPublished }
}))

server.registerTool('create_task', {
  title: 'Giao việc',
  description: 'Tạo công việc trong app Dự án & công việc, giao cho nhân viên (theo tên) và gắn dự án (theo tên) nếu có.',
  inputSchema: {
    title: z.string().min(2).max(255), description: z.string().optional(), assignee: z.string().optional().describe('Tên nhân viên, VD "Châu"'),
    project: z.string().optional().describe('Tên dự án'), dueDate: isoDate.optional(), priority: z.enum(['low', 'normal', 'high', 'urgent']).default('normal'),
  },
  annotations: WRITE,
}, tool(async ({ title, description, assignee, project, dueDate, priority }) => {
  const lk = await erp('GET', '/api/projects/lookups')
  const pick = (list, name, what) => {
    if (!name) return null
    const k = name.trim().toLowerCase()
    const hits = list.filter((x) => x.name.toLowerCase().includes(k))
    if (hits.length === 1) return hits[0]
    if (!hits.length) throw new ErpError(404, `Không có ${what} "${name}". Có: ${list.map((x) => x.name).join(', ')}.`)
    const exact = hits.find((x) => x.name.toLowerCase() === k)
    if (exact) return exact
    throw new ErpError(400, `"${name}" khớp nhiều ${what}: ${hits.map((x) => x.name).join(', ')}.`)
  }
  const user = pick(lk.users, assignee, 'nhân viên')
  const proj = pick(lk.projects, project, 'dự án đang mở')
  const t = await erp('POST', '/api/projects/tasks', {
    body: { title, description: description ?? null, projectId: proj?.id ?? null, priority, assigneeUserId: user?.id ?? null, departmentId: null, startDate: null, dueDate: dueDate ?? null, estimatedHours: null },
  })
  return { created: true, code: t.code, title: t.title, assignee: t.assigneeName, project: t.projectName, due: t.dueDate }
}))

// ---------------------------------------------------------------- chạy

const transport = new StdioServerTransport()
await server.connect(transport)
console.error(`[myerp-mcp] sẵn sàng - ERP: ${BASE}${TOKEN ? '' : ' (CHƯA có ERP_TOKEN)'}`)
