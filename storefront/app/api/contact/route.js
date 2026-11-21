import { sendContact } from '../../../lib/erp'
import { clientIp, errorResponse } from '../../../lib/clientIp'

export async function POST(request) {
  let body
  try { body = await request.json() } catch { return Response.json({ error: 'Dữ liệu không hợp lệ.' }, { status: 400 }) }
  try {
    return Response.json(await sendContact({ ...body, pageUrl: body.pageUrl ?? '/lien-he' }, clientIp(request)))
  } catch (e) {
    return errorResponse(e)
  }
}
