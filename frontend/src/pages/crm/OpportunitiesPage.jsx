import { useCallback, useEffect, useState } from 'react'
import { opportunityApi } from '../../api/crmApi'
import { getErrorMessage } from '../../api/client'
import Modal from '../../components/Modal'
import { PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { formatDateOnly, formatMoneyShort, initials } from '../../utils/format'
import CrmLayout from './CrmLayout'
import OpportunityFormModal from './OpportunityFormModal'
import useCrmLookups from './useCrmLookups'

/**
 * Bảng Kanban cơ hội: mỗi cột là một giai đoạn. Kéo thẻ sang cột khác để chuyển giai đoạn.
 * Kéo vào "Thất bại" sẽ hỏi lý do. Cột Thành công / Thất bại chỉ hiện cơ hội đóng trong 90 ngày.
 */
export default function OpportunitiesPage() {
  const { can } = useAuth()
  const lookups = useCrmLookups()
  const canMove = can(PERMISSIONS.CRM_EDIT)

  const [board, setBoard] = useState(null)
  const [filters, setFilters] = useState({ search: '', ownerId: '' })
  const [error, setError] = useState('')
  const [editing, setEditing] = useState(null)       // null | 'new' | id
  const [dragging, setDragging] = useState(null)     // card đang kéo
  const [dropTarget, setDropTarget] = useState(null) // stageId đang rê qua
  const [losing, setLosing] = useState(null)         // { card, stage } chờ chọn lý do thất bại
  const [lost, setLost] = useState({ reasonId: '', note: '' })

  const load = useCallback(async () => {
    try {
      setError('')
      setBoard(await opportunityApi.board(filters))
    } catch (err) {
      setError(getErrorMessage(err))
    }
  }, [filters])

  useEffect(() => {
    const timer = setTimeout(load, 300)
    return () => clearTimeout(timer)
  }, [load])

  // Chuyển giai đoạn: cập nhật giao diện ngay (lạc quan), lỗi thì tải lại từ server
  const move = async (card, stage, lostReasonId = null, lostNote = null) => {
    setBoard((b) => ({
      ...b,
      columns: b.columns.map((col) => ({
        ...col,
        items: col.stage.id === stage.id ? [{ ...card, stageId: stage.id }, ...col.items] : col.items.filter((i) => i.id !== card.id),
      })),
    }))
    try {
      await opportunityApi.moveStage(card.id, stage.id, lostReasonId, lostNote)
    } catch (err) {
      setError(getErrorMessage(err))
    }
    load()
  }

  const onDrop = (stage) => {
    setDropTarget(null)
    const card = dragging
    setDragging(null)
    if (!card || card.stageId === stage.id) return
    if (stage.stageType === 'lost') {
      setLost({ reasonId: '', note: '' })
      setLosing({ card, stage })
      return
    }
    move(card, stage)
  }

  const totals = board?.columns.filter((c) => c.stage.stageType === 'open')
    .reduce((t, c) => ({ count: t.count + c.count, value: t.value + c.totalValue, weighted: t.weighted + c.weightedValue }), { count: 0, value: 0, weighted: 0 })

  return (
    <CrmLayout>
      <div className="page-head">
        <div>
          <h1>Cơ hội</h1>
          {totals && (
            <p className="muted small kpi-line">
              {totals.count} cơ hội đang mở · Tổng giá trị <b>{formatMoneyShort(totals.value)}</b> · Doanh thu kỳ vọng <b>{formatMoneyShort(totals.weighted)}</b>
            </p>
          )}
        </div>
        {can(PERMISSIONS.CRM_CREATE) && (
          <button className="btn primary" onClick={() => setEditing('new')}>
            <i className="ti ti-plus" aria-hidden="true" /> Tạo cơ hội
          </button>
        )}
      </div>

      <div className="toolbar">
        <div className="search">
          <i className="ti ti-search" aria-hidden="true" />
          <input placeholder="Tìm tên cơ hội, mã, khách hàng" value={filters.search} onChange={(e) => setFilters({ ...filters, search: e.target.value })} aria-label="Tìm cơ hội" />
        </div>
        <select value={filters.ownerId} onChange={(e) => setFilters({ ...filters, ownerId: e.target.value })} aria-label="Lọc theo người phụ trách">
          <option value="">Mọi người phụ trách</option>
          {lookups.owners.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
        </select>
      </div>

      {error && <div className="alert error">{error}</div>}
      {!board && !error && <p className="muted">Đang tải...</p>}

      {board && (
        <div className="kanban">
          {board.columns.map((col) => (
            <section
              key={col.stage.id}
              className={`kanban-col ${col.stage.stageType}${dropTarget === col.stage.id ? ' drop' : ''}`}
              onDragOver={(e) => { if (dragging) { e.preventDefault(); setDropTarget(col.stage.id) } }}
              onDragLeave={() => setDropTarget((t) => (t === col.stage.id ? null : t))}
              onDrop={() => onDrop(col.stage)}
              aria-label={`Giai đoạn ${col.stage.name}`}
            >
              <header>
                <div className="kanban-title">
                  <span>{col.stage.name}</span>
                  <span className="count">{col.count}</span>
                </div>
                <div className="muted small">
                  {formatMoneyShort(col.totalValue)}
                  {col.stage.stageType === 'open' && <> · {col.stage.probability}%</>}
                </div>
              </header>
              <div className="kanban-items">
                {col.items.map((card) => (
                  <article
                    key={card.id}
                    className={`kanban-card${dragging?.id === card.id ? ' dragging' : ''}`}
                    draggable={canMove}
                    onDragStart={(e) => { e.dataTransfer.effectAllowed = 'move'; setDragging(card) }}
                    onDragEnd={() => { setDragging(null); setDropTarget(null) }}
                    onClick={() => setEditing(card.id)}
                    tabIndex={0}
                    onKeyDown={(e) => e.key === 'Enter' && setEditing(card.id)}
                  >
                    <div className="card-title">{card.name}</div>
                    <div className="muted small">{card.customerName}</div>
                    <div className="card-meta">
                      <b>{formatMoneyShort(card.expectedRevenue)}</b>
                      {card.priority > 0 && <span className="prio" aria-label={`Ưu tiên ${card.priority} sao`}>{'★'.repeat(card.priority)}</span>}
                      <span className="spacer" />
                      {card.expectedCloseDate && (
                        <span className={`small ${card.isOverdue ? 'overdue' : 'muted'}`} title={card.isOverdue ? 'Quá ngày dự kiến chốt' : 'Ngày dự kiến chốt'}>
                          <i className="ti ti-calendar" aria-hidden="true" /> {formatDateOnly(card.expectedCloseDate)}
                        </span>
                      )}
                      {card.ownerName && <span className="avatar tiny" title={card.ownerName}>{initials(card.ownerName)}</span>}
                    </div>
                  </article>
                ))}
                {col.items.length === 0 && <div className="kanban-empty muted small">{canMove ? 'Kéo thẻ vào đây' : 'Trống'}</div>}
              </div>
            </section>
          ))}
        </div>
      )}

      {editing && (
        <OpportunityFormModal
          opportunityId={editing === 'new' ? null : editing}
          lookups={lookups}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); load() }}
          onStageChanged={load}
        />
      )}

      {losing && (
        <Modal
          title="Đánh dấu thất bại"
          size="small"
          onClose={() => setLosing(null)}
          footer={
            <>
              <button className="btn" onClick={() => setLosing(null)}>Hủy</button>
              <button className="btn danger-fill" disabled={!lost.reasonId}
                onClick={() => { move(losing.card, losing.stage, Number(lost.reasonId), lost.note || null); setLosing(null) }}>
                Xác nhận
              </button>
            </>
          }
        >
          <p><b>{losing.card.name}</b> - {losing.card.customerName}</p>
          <label>Lý do thất bại *
            <select value={lost.reasonId} onChange={(e) => setLost({ ...lost, reasonId: e.target.value })} autoFocus>
              <option value="">Chọn lý do</option>
              {lookups.lostReasons.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
            </select>
          </label>
          <label>Ghi chú<input value={lost.note} onChange={(e) => setLost({ ...lost, note: e.target.value })} placeholder="Đối thủ báo giá thấp hơn 15%" /></label>
        </Modal>
      )}
    </CrmLayout>
  )
}
