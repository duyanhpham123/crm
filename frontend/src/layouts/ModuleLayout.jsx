import { NavLink } from 'react-router-dom'
import AppIcon from '../components/AppIcon'

/**
 * Bố cục của một ứng dụng (phòng ban): menu chức năng bên trái + nội dung bên phải.
 * menu: [{ to: '/crm/leads', icon: 'user-plus', label: 'Lead' }, { icon: 'building', label: 'Khách hàng', disabled: true }]
 * end: true = chỉ sáng khi đúng đường dẫn (VD "/users" không sáng khi đang ở "/users/roles")
 */
export default function ModuleLayout({ title, icon, color, menu, children }) {
  return (
    <div className="module">
      <aside className="module-nav">
        <div className="module-title">
          <AppIcon icon={icon} color={color} small />
          <span>{title}</span>
        </div>
        {menu.map((item) =>
          item.disabled ? (
            <span key={item.label} className="nav-item disabled" title="Sắp có">
              <i className={`ti ti-${item.icon}`} aria-hidden="true" />
              {item.label}
            </span>
          ) : (
            <NavLink key={item.to} to={item.to} end={item.end} className={({ isActive }) => `nav-item${isActive ? ' active' : ''}`}>
              <i className={`ti ti-${item.icon}`} aria-hidden="true" />
              {item.label}
            </NavLink>
          ),
        )}
      </aside>
      <section className="module-body">{children}</section>
    </div>
  )
}
