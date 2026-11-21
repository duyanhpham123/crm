import ContactForm from '../../components/ContactForm'
import { getSite } from '../../lib/erp'

export const metadata = { title: 'Liên hệ' }

export default async function ContactPage() {
  const site = await getSite()
  const s = site.settings
  return (
    <div className="two-col">
      <div>
        <h1>Liên hệ</h1>
        {s.address && <p>📍 {s.address}</p>}
        {s.hotline && <p>📞 {s.hotline}</p>}
        {s.email && <p>✉️ {s.email}</p>}
        {s.openingHours && <p>🕘 {s.openingHours}</p>}
      </div>
      <ContactForm />
    </div>
  )
}
