import { useEffect, useRef, useState } from 'react'
import { customerApi } from '../api/crmApi'

/**
 * Ô chọn khách hàng có tìm kiếm (gõ tên / mã / SĐT / MST).
 * value = { id, name } hoặc null. onChange(customer | null)
 */
export default function CustomerPicker({ value, onChange, disabled = false, autoFocus = false }) {
  const [text, setText] = useState(value?.name ?? '')
  const [results, setResults] = useState([])
  const [open, setOpen] = useState(false)
  const boxRef = useRef(null)

  useEffect(() => setText(value?.name ?? ''), [value])

  useEffect(() => {
    if (!open) return
    const timer = setTimeout(() => {
      customerApi.list({ search: text, pageSize: 8 }).then((r) => setResults(r.items)).catch(() => setResults([]))
    }, 250)
    return () => clearTimeout(timer)
  }, [text, open])

  // Bấm ra ngoài thì đóng danh sách
  useEffect(() => {
    const onClick = (e) => boxRef.current && !boxRef.current.contains(e.target) && setOpen(false)
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [])

  const pick = (c) => {
    onChange(c ? { id: c.id, name: c.name } : null)
    setText(c?.name ?? '')
    setOpen(false)
  }

  return (
    <div className="picker" ref={boxRef}>
      <input
        value={text}
        disabled={disabled}
        autoFocus={autoFocus}
        placeholder="Gõ tên, mã, SĐT hoặc mã số thuế"
        onFocus={() => setOpen(true)}
        onChange={(e) => {
          setText(e.target.value)
          setOpen(true)
          if (value) onChange(null)
        }}
        aria-label="Chọn khách hàng"
        role="combobox"
        aria-expanded={open}
      />
      {open && !disabled && (
        <ul className="picker-list" role="listbox">
          {results.length === 0 && <li className="muted">Không tìm thấy khách hàng</li>}
          {results.map((c) => (
            <li key={c.id} role="option" aria-selected={value?.id === c.id} onMouseDown={() => pick(c)}>
              <b>{c.name}</b>
              <span className="muted small"> {c.code}{c.phone ? ` · ${c.phone}` : ''}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
