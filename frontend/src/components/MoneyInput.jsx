import { parseMoney } from '../utils/format'

/** Ô nhập tiền có dấu chấm phân cách: gõ 1250000 hiện "1.250.000". value / onChange là số. */
export default function MoneyInput({ value, onChange, ...props }) {
  const text = value === '' || value === null || value === undefined ? '' : new Intl.NumberFormat('vi-VN').format(value)
  return (
    <input
      inputMode="numeric"
      value={text}
      onChange={(e) => onChange(e.target.value.trim() === '' ? 0 : parseMoney(e.target.value))}
      onFocus={(e) => e.target.select()}
      {...props}
    />
  )
}
