import { useEffect, useState } from 'react'
import { crmLookupApi } from '../../api/crmApi'

const EMPTY = { sources: [], customerGroups: [], pipelines: [], lostReasons: [], owners: [] }
let cache = null   // danh mục ít thay đổi: tải 1 lần, dùng chung cho mọi trang CRM

/** Danh mục cho ô chọn: nguồn lead, nhóm khách, pipeline + giai đoạn, lý do thất bại, người phụ trách. */
export default function useCrmLookups() {
  const [lookups, setLookups] = useState(cache ?? EMPTY)

  useEffect(() => {
    if (cache) return
    crmLookupApi
      .get()
      .then((data) => {
        cache = data
        setLookups(data)
      })
      .catch(() => {})
  }, [])

  return lookups
}
