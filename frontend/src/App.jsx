import { Navigate, Route, Routes } from 'react-router-dom'
import ProtectedRoute from './components/ProtectedRoute'
import MainLayout from './layouts/MainLayout'
import LoginPage from './pages/LoginPage'
import HomePage from './pages/HomePage'
import ComingSoonPage from './pages/ComingSoonPage'
import NotFoundPage from './pages/NotFoundPage'
import LeadsPage from './pages/crm/LeadsPage'
import CustomersPage from './pages/crm/CustomersPage'
import CustomerDetailPage from './pages/crm/CustomerDetailPage'
import OpportunitiesPage from './pages/crm/OpportunitiesPage'
import UsersPage from './pages/users/UsersPage'
import RolesPage from './pages/users/RolesPage'
import RoleEditorPage from './pages/users/RoleEditorPage'
import ProductsPage from './pages/inventory/ProductsPage'
import ProductDetailPage from './pages/inventory/ProductDetailPage'
import StockPage from './pages/inventory/StockPage'
import StockDocumentsPage from './pages/inventory/StockDocumentsPage'
import OrdersPage from './pages/orders/OrdersPage'
import OrderFormPage from './pages/orders/OrderFormPage'
import PurchaseOrdersPage from './pages/purchasing/PurchaseOrdersPage'
import PurchaseFormPage from './pages/purchasing/PurchaseFormPage'
import SuppliersPage from './pages/purchasing/SuppliersPage'
import DashboardPage from './pages/reports/DashboardPage'
import QuotationsPage from './pages/quotations/QuotationsPage'
import QuotationFormPage from './pages/quotations/QuotationFormPage'
import { CodPage, ReadyOrdersPage, ShipmentsPage } from './pages/logistics/LogisticsPages'
import { AccountingOverviewPage, CashBookPage, DebtsPage, VouchersPage } from './pages/accounting/AccountingPages'
import { TicketDetailPage, TicketsPage } from './pages/support/SupportPages'
import { AttendancePage, EmployeesPage, LeavesPage, PayrollDetailPage, PayrollListPage } from './pages/hr/HrPages'
import { CampaignDetailPage, CampaignsPage, PromotionsPage, SegmentsPage } from './pages/marketing/MarketingPages'
import { AppsSettingsPage, CompanySettingsPage, DepartmentsPage, NumberingPage, WarehousesPage } from './pages/settings/SettingsPages'
import { ProjectDetailPage, ProjectsPage, TasksPage } from './pages/projects/ProjectPages'
import { DocumentsPage } from './pages/documents/DocumentPages'
import ChatPage from './pages/chat/ChatPage'
import { WebConnectPage, WebContactsPage, WebContentPage, WebMenuPage, WebProductsPage, WebsiteOverviewPage } from './pages/website/WebsitePages'

/**
 * Bảng định tuyến của ứng dụng.
 * Thêm trang mới: tạo file trong pages/ rồi khai báo <Route> ở đây.
 */
export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />

      {/* Các trang cần đăng nhập */}
      <Route element={<ProtectedRoute />}>
        <Route element={<MainLayout />}>
          <Route index element={<HomePage />} />

          {/* CRM */}
          <Route path="crm" element={<Navigate to="/crm/leads" replace />} />
          <Route path="crm/leads" element={<LeadsPage />} />
          <Route path="crm/opportunities" element={<OpportunitiesPage />} />
          <Route path="crm/customers" element={<CustomersPage />} />
          <Route path="crm/customers/:id" element={<CustomerDetailPage />} />

          {/* Người dùng, vai trò & quyền */}
          <Route path="users" element={<UsersPage />} />
          <Route path="users/roles" element={<RolesPage />} />
          <Route path="users/roles/new" element={<RoleEditorPage />} />
          <Route path="users/roles/:id" element={<RoleEditorPage />} />

          {/* Kho */}
          <Route path="inventory" element={<Navigate to="/inventory/products" replace />} />
          <Route path="inventory/products" element={<ProductsPage />} />
          <Route path="inventory/products/:id" element={<ProductDetailPage />} />
          <Route path="inventory/stock" element={<StockPage />} />
          <Route path="inventory/documents" element={<StockDocumentsPage />} />

          {/* Đơn hàng */}
          <Route path="orders" element={<OrdersPage />} />
          <Route path="orders/new" element={<OrderFormPage />} />
          <Route path="orders/:id" element={<OrderFormPage />} />

          {/* Mua hàng */}
          <Route path="purchasing" element={<Navigate to="/purchasing/orders" replace />} />
          <Route path="purchasing/orders" element={<PurchaseOrdersPage />} />
          <Route path="purchasing/orders/new" element={<PurchaseFormPage />} />
          <Route path="purchasing/orders/:id" element={<PurchaseFormPage />} />
          <Route path="purchasing/suppliers" element={<SuppliersPage />} />

          {/* Báo cáo */}
          <Route path="reports" element={<DashboardPage />} />

          {/* Báo giá */}
          <Route path="quotations" element={<QuotationsPage />} />
          <Route path="quotations/new" element={<QuotationFormPage />} />
          <Route path="quotations/:id" element={<QuotationFormPage />} />

          {/* Vận chuyển */}
          <Route path="logistics" element={<ShipmentsPage />} />
          <Route path="logistics/ready" element={<ReadyOrdersPage />} />
          <Route path="logistics/cod" element={<CodPage />} />

          {/* Kế toán */}
          <Route path="accounting" element={<AccountingOverviewPage />} />
          <Route path="accounting/vouchers" element={<VouchersPage />} />
          <Route path="accounting/cashbook" element={<CashBookPage />} />
          <Route path="accounting/receivables" element={<DebtsPage kind="receivable" />} />
          <Route path="accounting/payables" element={<DebtsPage kind="payable" />} />

          {/* CSKH */}
          <Route path="support" element={<TicketsPage />} />
          <Route path="support/:id" element={<TicketDetailPage />} />

          {/* Nhân sự */}
          <Route path="hr" element={<EmployeesPage />} />
          <Route path="hr/attendance" element={<AttendancePage />} />
          <Route path="hr/leaves" element={<LeavesPage />} />
          <Route path="hr/payroll" element={<PayrollListPage />} />
          <Route path="hr/payroll/:id" element={<PayrollDetailPage />} />

          {/* Marketing */}
          <Route path="marketing" element={<CampaignsPage />} />
          <Route path="marketing/campaigns/:id" element={<CampaignDetailPage />} />
          <Route path="marketing/promotions" element={<PromotionsPage />} />
          <Route path="marketing/segments" element={<SegmentsPage />} />

          {/* Cài đặt */}
          <Route path="settings" element={<CompanySettingsPage />} />
          <Route path="settings/departments" element={<DepartmentsPage />} />
          <Route path="settings/warehouses" element={<WarehousesPage />} />
          <Route path="settings/apps" element={<AppsSettingsPage />} />
          <Route path="settings/numbering" element={<NumberingPage />} />

          {/* Dự án & công việc */}
          <Route path="projects" element={<TasksPage />} />
          <Route path="projects/list" element={<ProjectsPage />} />
          <Route path="projects/:id" element={<ProjectDetailPage />} />

          {/* Tài liệu */}
          <Route path="documents" element={<DocumentsPage />} />

          {/* Chat nội bộ */}
          <Route path="chat" element={<ChatPage />} />

          {/* Website */}
          <Route path="website" element={<WebsiteOverviewPage />} />
          <Route path="website/products" element={<WebProductsPage />} />
          <Route path="website/content" element={<WebContentPage />} />
          <Route path="website/contacts" element={<WebContactsPage />} />
          <Route path="website/menu" element={<WebMenuPage />} />
          <Route path="website/connect" element={<WebConnectPage />} />

          {/* Ứng dụng mới khai báo trong core.Apps nhưng chưa có trang */}
          <Route path=":slug" element={<ComingSoonPage />} />
        </Route>
      </Route>

      <Route path="*" element={<NotFoundPage />} />
    </Routes>
  )
}
