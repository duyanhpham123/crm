import { useState } from 'react'
import { generatePassword } from '../utils/format'

/** Ô mật khẩu có nút hiện/ẩn và (tùy chọn) nút tạo mật khẩu ngẫu nhiên. */
export default function PasswordInput({ value, onChange, allowGenerate = false, autoComplete = 'new-password', ...rest }) {
  const [visible, setVisible] = useState(false)

  return (
    <div className="password-input">
      <input type={visible ? 'text' : 'password'} value={value} onChange={onChange} autoComplete={autoComplete} {...rest} />
      <button type="button" className="btn ghost" onClick={() => setVisible(!visible)} title={visible ? 'Ẩn' : 'Hiện'} aria-label={visible ? 'Ẩn mật khẩu' : 'Hiện mật khẩu'}>
        <i className={`ti ti-${visible ? 'eye-off' : 'eye'}`} aria-hidden="true" />
      </button>
      {allowGenerate && (
        <button
          type="button"
          className="btn ghost"
          title="Tạo mật khẩu ngẫu nhiên"
          aria-label="Tạo mật khẩu ngẫu nhiên"
          onClick={() => {
            onChange({ target: { value: generatePassword() } })
            setVisible(true)
          }}
        >
          <i className="ti ti-wand" aria-hidden="true" />
        </button>
      )}
    </div>
  )
}
