import ModuleLayout from '../../layouts/ModuleLayout'

const USERS_MENU = [
  { to: '/users', icon: 'users', label: 'Người dùng', end: true },
  { to: '/users/roles', icon: 'shield-lock', label: 'Vai trò & quyền' },
  { icon: 'history', label: 'Nhật ký hoạt động', disabled: true },
]

export default function UsersLayout({ children }) {
  return (
    <ModuleLayout title="Người dùng" icon="user-shield" color="#5F5E5A" menu={USERS_MENU}>
      {children}
    </ModuleLayout>
  )
}
