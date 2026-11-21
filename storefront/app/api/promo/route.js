import { checkPromotion } from '../../../lib/erp'
import { errorResponse } from '../../../lib/clientIp'

/** GET /api/promo?code=GIAM20K&subTotal=450000 → { code, name, discount } */
export async function GET(request) {
  const { searchParams } = new URL(request.url)
  const code = (searchParams.get('code') || '').trim()
  const subTotal = Number(searchParams.get('subTotal')) || 0
  if (!code) return Response.json({ error: 'Nhập mã giảm giá.' }, { status: 400 })
  try {
    return Response.json(await checkPromotion(code, subTotal))
  } catch (e) {
    return errorResponse(e)
  }
}
