import ModuleLayout from '../../layouts/ModuleLayout'

/** Menu bên trái của ứng dụng CRM. Làm xong chức năng nào thì bỏ "disabled" và thêm "to". */
const CRM_MENU = [
  { to: '/crm/leads', icon: 'user-plus', label: 'Lead' },
  { to: '/crm/opportunities', icon: 'layout-kanban', label: 'Cơ hội' },
  { to: '/crm/customers', icon: 'building', label: 'Khách hàng' },
  { icon: 'calendar-event', label: 'Hoạt động', disabled: true },
]

export default function CrmLayout({ children }) {
  return (
    <ModuleLayout title="CRM" icon="heart-handshake" color="#D4537E" menu={CRM_MENU}>
      {children}
    </ModuleLayout>
  )
}
