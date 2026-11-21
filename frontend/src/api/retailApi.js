import { api } from './client'

/**
 * API bán lẻ: Kho, Đơn hàng, Mua hàng, Báo cáo.
 * Khớp backend/MyERP.Api/Controllers/{Inventory,Sales,Purchasing}/ và ReportsController.
 */

/** Bỏ tham số rỗng để URL gọn: { search: '', page: 1 } → { page: 1 } */
const clean = (params) => Object.fromEntries(Object.entries(params).filter(([, v]) => v !== '' && v !== null && v !== undefined && v !== false))
const data = (r) => r.data

export const inventoryApi = {
  /** GET /api/inventory/lookups → { categories, brands, units, warehouses, suggestedColors, suggestedSizes } */
  lookups: () => api.get('/api/inventory/lookups').then(data),

  /** Mẫu sản phẩm (mỗi mẫu có nhiều SKU theo màu × size) */
  listModels: (params) => api.get('/api/inventory/models', { params: clean(params) }).then(data),
  getModel: (id) => api.get(`/api/inventory/models/${id}`).then(data),
  createModel: (body) => api.post('/api/inventory/models', body).then(data),
  updateModel: (id, body) => api.put(`/api/inventory/models/${id}`, body).then(data),

  /** PUT /api/inventory/products/{id} body: { salePrice, barcode, minStock, isActive } - sửa 1 SKU */
  updateVariant: (id, body) => api.put(`/api/inventory/products/${id}`, body).then(data),

  createCategory: (name) => api.post('/api/inventory/categories', { name }).then(data),
  createBrand: (name) => api.post('/api/inventory/brands', { name }).then(data),

  /** GET /api/inventory/stock → { rows: PagedResult<StockRow>, summary } */
  stock: (params) => api.get('/api/inventory/stock', { params: clean(params) }).then(data),

  /** Phiếu kho: nhập / xuất / điều chỉnh */
  listDocuments: (params) => api.get('/api/inventory/documents', { params: clean(params) }).then(data),
  getDocument: (id) => api.get(`/api/inventory/documents/${id}`).then(data),
  createDocument: (body) => api.post('/api/inventory/documents', body).then(data),
}

export const catalogApi = {
  /** GET /api/catalog/skus?search=thun den m&warehouseId= → SkuOption[] (kèm tồn khả dụng) */
  searchSkus: (search, warehouseId, forPurchase = false) =>
    api.get('/api/catalog/skus', { params: clean({ search, warehouseId, forPurchase }) }).then(data),
}

export const salesApi = {
  /** GET /api/sales/lookups → { warehouses, salespeople, channels, paymentMethods } */
  lookups: () => api.get('/api/sales/lookups').then(data),

  /** GET /api/sales/orders → { rows: PagedResult<OrderListItem>, summary } */
  list: (params) => api.get('/api/sales/orders', { params: clean(params) }).then(data),
  get: (id) => api.get(`/api/sales/orders/${id}`).then(data),
  create: (body) => api.post('/api/sales/orders', body).then(data),
  update: (id, body) => api.put(`/api/sales/orders/${id}`, body).then(data),

  /** Xác nhận đơn = xuất kho */
  confirm: (id) => api.post(`/api/sales/orders/${id}/confirm`).then(data),
  complete: (id) => api.post(`/api/sales/orders/${id}/complete`).then(data),
  /** Hủy đơn. Đơn đã xuất kho thì tự nhập lại hàng. */
  cancel: (id, reason) => api.post(`/api/sales/orders/${id}/cancel`, { reason }).then(data),
  pay: (id, amount, method) => api.post(`/api/sales/orders/${id}/payments`, { amount, method }).then(data),
}

export const purchasingApi = {
  listSuppliers: (params) => api.get('/api/purchasing/suppliers', { params: clean(params) }).then(data),
  createSupplier: (body) => api.post('/api/purchasing/suppliers', body).then(data),
  updateSupplier: (id, body) => api.put(`/api/purchasing/suppliers/${id}`, body).then(data),

  list: (params) => api.get('/api/purchasing/orders', { params: clean(params) }).then(data),
  get: (id) => api.get(`/api/purchasing/orders/${id}`).then(data),
  create: (body) => api.post('/api/purchasing/orders', body).then(data),
  update: (id, body) => api.put(`/api/purchasing/orders/${id}`, body).then(data),
  confirm: (id) => api.post(`/api/purchasing/orders/${id}/confirm`).then(data),
  /** Nhận hàng = tạo phiếu nhập kho, cập nhật giá vốn */
  receive: (id) => api.post(`/api/purchasing/orders/${id}/receive`).then(data),
  cancel: (id) => api.post(`/api/purchasing/orders/${id}/cancel`).then(data),
}

export const reportApi = {
  /** GET /api/reports/dashboard?days=30 */
  dashboard: (days = 30) => api.get('/api/reports/dashboard', { params: { days } }).then(data),
}
