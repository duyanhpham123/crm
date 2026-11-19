/** Phân trang: "25 lead · trang 1/2  [<] [>]" */
export default function Pagination({ data, unit = 'bản ghi', onPageChange }) {
  if (!data) return null
  const { page, totalPages, totalCount } = data
  return (
    <div className="pager">
      <span className="muted">
        {totalCount} {unit}
        {totalPages > 1 && ` · trang ${page}/${totalPages}`}
      </span>
      {totalPages > 1 && (
        <>
          <button className="btn" disabled={page <= 1} onClick={() => onPageChange(page - 1)} aria-label="Trang trước">
            <i className="ti ti-chevron-left" aria-hidden="true" />
          </button>
          <button className="btn" disabled={page >= totalPages} onClick={() => onPageChange(page + 1)} aria-label="Trang sau">
            <i className="ti ti-chevron-right" aria-hidden="true" />
          </button>
        </>
      )}
    </div>
  )
}
