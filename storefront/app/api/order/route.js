import { placeOrder } from '../../../lib/erp'
import { clientIp, errorResponse } from '../../../lib/clientIp'

/** Trình duyệt gửi đơn về đây; máy chủ Next.js chuyển sang ERP kèm khóa website (khóa không lộ ra trình duyệt). */
export async function POST(request) {
  let body
  try { body = await request.json() } catch { return Response.json({ error: 'Dữ liệu không hợp lệ.' }, { status: 400 }) }
  try {
    return Response.json(await placeOrder(body, clientIp(request)))
  } catch (e) {
    return errorResponse(e)
  }
}
