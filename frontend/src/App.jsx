import { Navigate, Route, Routes } from 'react-router-dom'
import ProtectedRoute from './components/ProtectedRoute'
import MainLayout from './layouts/MainLayout'
import LoginPage from './pages/LoginPage'
import HomePage from './pages/HomePage'
import ComingSoonPage from './pages/ComingSoonPage'
import NotFoundPage from './pages/NotFoundPage'
import LeadsPage from './pages/crm/LeadsPage'
import UsersPage from './pages/users/UsersPage'
import RolesPage from './pages/users/RolesPage'
import RoleEditorPage from './pages/users/RoleEditorPage'

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

          {/* Người dùng, vai trò & quyền */}
          <Route path="users" element={<UsersPage />} />
          <Route path="users/roles" element={<RolesPage />} />
          <Route path="users/roles/new" element={<RoleEditorPage />} />
          <Route path="users/roles/:id" element={<RoleEditorPage />} />

          {/* Ứng dụng chưa làm: /quotations, /orders, /inventory ... */}
          <Route path=":slug" element={<ComingSoonPage />} />
        </Route>
      </Route>

      <Route path="*" element={<NotFoundPage />} />
    </Routes>
  )
}
