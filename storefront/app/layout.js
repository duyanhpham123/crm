import Link from 'next/link'
import { CartButton, CartProvider } from '../components/Cart'
import { getSite } from '../lib/erp'
import './globals.css'

/** Tiêu đề, mô tả lấy từ ERP (Website > Thông tin website) - đổi ở ERP là website đổi theo. */
export async function generateMetadata() {
  try {
    const site = await getSite()
    return { title: { default: site.name, template: `%s | ${site.name}` }, description: site.settings.slogan ?? site.name }
  } catch {
    return { title: 'Cửa hàng' }
  }
}

function MenuLink({ item }) {
  return item.openNewTab
    ? <a href={item.url} target="_blank" rel="noopener noreferrer">{item.label}</a>
    : <Link href={item.url}>{item.label}</Link>
}

export default async function RootLayout({ children }) {
  let site = null
  let error = null
  try { site = await getSite() } catch (e) { error = e.message }
  const s = site?.settings ?? {}
  return (
    <html lang="vi">
      <body style={s.primaryColor ? { '--brand': s.primaryColor } : undefined}>
        <CartProvider>
          <header className="site-header">
            <div className="container header-row">
              <Link href="/" className="logo">
                {site?.logoUrl ? <img src={site.logoUrl} alt={site.name} /> : <span>{site?.name ?? 'Cửa hàng'}</span>}
              </Link>
              <nav className="main-nav" aria-label="Menu chính">
                {site?.menu.map((m) => <MenuLink key={m.url + m.label} item={m} />)}
              </nav>
              <CartButton />
            </div>
          </header>
          <main className="container main">
            {error ? <div className="alert">Không lấy được dữ liệu từ ERP: {error}</div> : children}
          </main>
          <footer className="site-footer">
            <div className="container footer-grid">
              <div>
                <b>{site?.name}</b>
                {s.slogan && <p>{s.slogan}</p>}
                {site?.companyName && <p className="muted">{site.companyName}{site.taxCode ? ` · MST ${site.taxCode}` : ''}</p>}
              </div>
              <div>
                {s.address && <p>📍 {s.address}</p>}
                {s.hotline && <p>📞 <a href={`tel:${s.hotline.replace(/\s/g, '')}`}>{s.hotline}</a></p>}
                {s.email && <p>✉️ <a href={`mailto:${s.email}`}>{s.email}</a></p>}
                {s.openingHours && <p>🕘 {s.openingHours}</p>}
              </div>
              <div>
                {site?.footerMenu.map((m) => <p key={m.url}><MenuLink item={m} /></p>)}
                <p className="socials">
                  {s.facebook && <a href={s.facebook} target="_blank" rel="noopener noreferrer">Facebook</a>}
                  {s.instagram && <a href={s.instagram} target="_blank" rel="noopener noreferrer">Instagram</a>}
                  {s.tikTok && <a href={s.tikTok} target="_blank" rel="noopener noreferrer">TikTok</a>}
                </p>
              </div>
            </div>
          </footer>
        </CartProvider>
      </body>
    </html>
  )
}
