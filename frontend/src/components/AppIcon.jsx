/** Ô icon màu của ứng dụng. icon = tên icon Tabler (https://tabler.io/icons), VD "heart-handshake". */
export default function AppIcon({ icon, color, small = false }) {
  return (
    <span className={`app-icon${small ? ' small' : ''}`} style={{ background: color || '#5F5E5A' }}>
      <i className={`ti ti-${icon || 'apps'}`} aria-hidden="true" />
    </span>
  )
}
