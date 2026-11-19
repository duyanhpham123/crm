import { useEffect } from 'react'

/** Hộp thoại dùng chung. Đóng bằng nút X, phím Esc hoặc bấm ra ngoài. */
export default function Modal({ title, onClose, size = 'medium', children, footer }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  return (
    <>
      <div className="modal-backdrop" onClick={onClose} />
      <div className={`modal ${size}`} role="dialog" aria-modal="true" aria-label={title}>
        <div className="modal-head">
          <h2>{title}</h2>
          <button className="btn ghost" onClick={onClose} aria-label="Đóng">
            <i className="ti ti-x" aria-hidden="true" />
          </button>
        </div>
        {children}
        {footer && <div className="modal-foot">{footer}</div>}
      </div>
    </>
  )
}
