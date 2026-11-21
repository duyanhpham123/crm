'use client'

import { useState } from 'react'

/** Gửi về ERP > Website > Liên hệ từ web (nhân viên chuyển thành khách tiềm năng trong CRM). */
export default function ContactForm() {
  const [form, setForm] = useState({ fullName: '', phone: '', email: '', message: '', website: '' })
  const [state, setState] = useState({ busy: false, done: '', error: '' })
  const u = (f) => (e) => setForm({ ...form, [f]: e.target.value })
  const submit = async (e) => {
    e.preventDefault()
    setState({ busy: true, done: '', error: '' })
    const params = new URLSearchParams(window.location.search)
    const res = await fetch('/api/contact', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...form, phone: form.phone || null, email: form.email || null, consent: true, pageUrl: window.location.pathname,
        utmSource: params.get('utm_source'), utmMedium: params.get('utm_medium'), utmCampaign: params.get('utm_campaign') }),
    })
    const data = await res.json()
    setState({ busy: false, done: res.ok ? data.message : '', error: res.ok ? '' : data.error })
    if (res.ok) setForm({ fullName: '', phone: '', email: '', message: '', website: '' })
  }
  if (state.done) return <div className="card success"><p>{state.done}</p></div>
  return (
    <form className="card" onSubmit={submit}>
      <h2>Gửi tin nhắn cho cửa hàng</h2>
      <label>Họ tên *<input value={form.fullName} onChange={u('fullName')} required maxLength={150} /></label>
      <label>Số điện thoại<input value={form.phone} onChange={u('phone')} type="tel" /></label>
      <label>Email<input value={form.email} onChange={u('email')} type="email" /></label>
      <label>Nội dung<textarea value={form.message} onChange={u('message')} rows={4} maxLength={2000} /></label>
      {/* Ô bẫy chống bot: người thật không thấy nên để trống */}
      <input className="hp" value={form.website} onChange={u('website')} tabIndex={-1} autoComplete="off" aria-hidden="true" />
      {state.error && <p className="error">{state.error}</p>}
      <button className="btn primary" disabled={state.busy}>{state.busy ? 'Đang gửi...' : 'Gửi'}</button>
    </form>
  )
}
