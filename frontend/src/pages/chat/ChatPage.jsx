import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { getErrorMessage } from '../../api/client'
import { chatApi } from '../../api/phase4Api'
import Modal from '../../components/Modal'
import { PHASE4_PERMISSIONS } from '../../constants'
import { useAuth } from '../../context/AuthContext'
import { initials } from '../../utils/format'

const REACTIONS = ['👍', '❤️', '😂', '😮', '😢', '✅']
const POLL_CHANNELS_MS = 8000
const POLL_MESSAGES_MS = 4000

/** API trả giờ UTC không kèm "Z" - thêm vào để trình duyệt đổi đúng sang giờ máy. */
const toDate = (v) => new Date(/[zZ]|[+-]\d\d:\d\d$/.test(v) ? v : `${v}Z`)
const timeOf = (iso) => toDate(iso).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })
const dayKey = (iso) => toDate(iso).toLocaleDateString('vi-VN')
function dayLabel(iso) {
  const d = toDate(iso)
  const today = new Date()
  const yesterday = new Date(); yesterday.setDate(today.getDate() - 1)
  if (d.toDateString() === today.toDateString()) return 'Hôm nay'
  if (d.toDateString() === yesterday.toDateString()) return 'Hôm qua'
  return d.toLocaleDateString('vi-VN', { weekday: 'long', day: '2-digit', month: '2-digit' })
}
function shortWhen(iso) {
  if (!iso) return ''
  const d = toDate(iso)
  return d.toDateString() === new Date().toDateString() ? timeOf(iso) : d.toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit' })
}

/** Chạy hàm định kỳ khi tab trình duyệt đang mở (ẩn tab thì tạm dừng). */
function usePolling(fn, ms, enabled = true) {
  const saved = useRef(fn)
  useEffect(() => { saved.current = fn }, [fn])
  useEffect(() => {
    if (!enabled) return undefined
    const tick = () => { if (document.visibilityState === 'visible') saved.current() }
    const id = setInterval(tick, ms)
    document.addEventListener('visibilitychange', tick)
    return () => { clearInterval(id); document.removeEventListener('visibilitychange', tick) }
  }, [ms, enabled])
}

function ChannelIcon({ channel }) {
  if (channel.type === 'direct') return <span className="avatar">{initials(channel.name)}</span>
  return <span className={`avatar channel-${channel.type}`}><i className={`ti ti-${channel.type === 'company' ? 'building' : 'users-group'}`} aria-hidden="true" /></span>
}

function NewChatModal({ onClose, onOpened }) {
  const { can } = useAuth()
  const [users, setUsers] = useState(null)
  const [mode, setMode] = useState('direct')
  const [name, setName] = useState('')
  const [picked, setPicked] = useState([])
  const [filter, setFilter] = useState('')
  const [error, setError] = useState('')
  useEffect(() => { chatApi.users().then(setUsers).catch((e) => setError(getErrorMessage(e))) }, [])
  const shown = (users ?? []).filter((u) => !filter || u.name.toLowerCase().includes(filter.toLowerCase()) || (u.description ?? '').toLowerCase().includes(filter.toLowerCase()))
  const direct = async (u) => { try { onOpened(await chatApi.direct(u.id)) } catch (err) { setError(getErrorMessage(err)) } }
  const create = async (e) => {
    e.preventDefault()
    try { onOpened(await chatApi.createGroup(name, picked)) } catch (err) { setError(getErrorMessage(err)) }
  }
  return (
    <Modal title="Cuộc trò chuyện mới" onClose={onClose}>
      {can(PHASE4_PERMISSIONS.CHAT_CREATE) && (
        <div className="segmented">
          <button className={mode === 'direct' ? 'on' : ''} onClick={() => setMode('direct')}>Nhắn riêng</button>
          <button className={mode === 'group' ? 'on' : ''} onClick={() => setMode('group')}>Tạo nhóm</button>
        </div>
      )}
      {mode === 'group' && <label className="block">Tên nhóm *<input value={name} onChange={(e) => setName(e.target.value)} autoFocus maxLength={150} placeholder="VD: Ca tối cửa hàng Lê Lợi" /></label>}
      <div className="search top-gap"><i className="ti ti-search" aria-hidden="true" /><input value={filter} onChange={(e) => setFilter(e.target.value)} placeholder="Tìm đồng nghiệp" aria-label="Tìm đồng nghiệp" autoFocus={mode === 'direct'} /></div>
      <div className="people-list">
        {!users && <p className="muted">Đang tải...</p>}
        {users?.length === 0 && <p className="muted">Chưa có đồng nghiệp nào có tài khoản. Tạo tài khoản ở app Người dùng.</p>}
        {shown.map((u) => mode === 'direct' ? (
          <button key={u.id} className="person" onClick={() => direct(u)}><span className="avatar tiny">{initials(u.name)}</span><span>{u.name}<span className="muted small block">{u.description}</span></span></button>
        ) : (
          <label key={u.id} className="person check"><input type="checkbox" checked={picked.includes(u.id)} onChange={() => setPicked(picked.includes(u.id) ? picked.filter((x) => x !== u.id) : [...picked, u.id])} />
            <span className="avatar tiny">{initials(u.name)}</span><span>{u.name}<span className="muted small block">{u.description}</span></span></label>
        ))}
      </div>
      {error && <p className="error">{error}</p>}
      {mode === 'group' && <div className="modal-foot"><button className="btn" onClick={onClose}>Hủy</button><button className="btn primary" onClick={create} disabled={!name.trim() || picked.length === 0}>Tạo nhóm ({picked.length + 1} người)</button></div>}
    </Modal>
  )
}

function AddMembersModal({ channel, onClose, onDone }) {
  const [users, setUsers] = useState([])
  const [picked, setPicked] = useState([])
  const [error, setError] = useState('')
  useEffect(() => { chatApi.users().then((all) => setUsers(all.filter((u) => !channel.members.some((m) => m.userId === u.id)))).catch(() => {}) }, [channel])
  const save = async () => { try { await chatApi.addMembers(channel.id, picked); onDone() } catch (err) { setError(getErrorMessage(err)) } }
  return (
    <Modal title={`Thêm người vào "${channel.name}"`} onClose={onClose} size="small">
      <div className="people-list">
        {users.length === 0 && <p className="muted">Mọi người đã ở trong nhóm.</p>}
        {users.map((u) => <label key={u.id} className="person check"><input type="checkbox" checked={picked.includes(u.id)} onChange={() => setPicked(picked.includes(u.id) ? picked.filter((x) => x !== u.id) : [...picked, u.id])} />
          <span>{u.name}<span className="muted small block">{u.description}</span></span></label>)}
      </div>
      {error && <p className="error">{error}</p>}
      <div className="modal-foot"><button className="btn" onClick={onClose}>Hủy</button><button className="btn primary" disabled={picked.length === 0} onClick={save}>Thêm</button></div>
    </Modal>
  )
}

function Conversation({ channelId, onBack, onActivity }) {
  const [channel, setChannel] = useState(null)
  const [messages, setMessages] = useState([])
  const [hasMore, setHasMore] = useState(false)
  const [text, setText] = useState('')
  const [replyTo, setReplyTo] = useState(null)
  const [editingId, setEditingId] = useState(null)
  const [showMembers, setShowMembers] = useState(false)
  const [adding, setAdding] = useState(false)
  const [error, setError] = useState('')
  const [sending, setSending] = useState(false)
  const listRef = useRef(null)
  const inputRef = useRef(null)
  const stickBottom = useRef(true)
  const lastRead = useRef(0)
  const keepScroll = useRef(null)

  const markRead = useCallback((msgs) => {
    const last = msgs[msgs.length - 1]
    if (last && last.id > lastRead.current) { lastRead.current = last.id; chatApi.read(channelId, last.id).then(onActivity).catch(() => {}) }
  }, [channelId, onActivity])

  const refresh = useCallback(async () => {
    try {
      const c = await chatApi.channel(channelId)
      setChannel(c)
      setMessages((prev) => {
        const minNew = c.messages[0]?.id ?? Infinity
        return [...prev.filter((m) => m.id < minNew), ...c.messages]
      })
      setHasMore((h) => (lastRead.current === 0 ? c.hasMore : h))
      markRead(c.messages)
    } catch (err) { setError(getErrorMessage(err)) }
  }, [channelId, markRead])

  useEffect(() => {
    setChannel(null); setMessages([]); setReplyTo(null); setEditingId(null); setText(''); setError(''); lastRead.current = 0; stickBottom.current = true
    refresh()
  }, [channelId]) // eslint-disable-line react-hooks/exhaustive-deps
  usePolling(refresh, POLL_MESSAGES_MS)

  useLayoutEffect(() => {
    const el = listRef.current
    if (!el) return
    if (keepScroll.current !== null) { el.scrollTop = el.scrollHeight - keepScroll.current; keepScroll.current = null }
    else if (stickBottom.current) el.scrollTop = el.scrollHeight
  }, [messages])

  const onScroll = () => {
    const el = listRef.current
    stickBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80
  }

  const loadOlder = async () => {
    try {
      const page = await chatApi.older(channelId, messages[0]?.id)
      keepScroll.current = listRef.current.scrollHeight - listRef.current.scrollTop
      setMessages((prev) => [...page.messages, ...prev])
      setHasMore(page.hasMore)
    } catch (err) { setError(getErrorMessage(err)) }
  }

  const replace = (m) => setMessages((prev) => prev.map((x) => (x.id === m.id ? m : x)))
  const send = async (e) => {
    e?.preventDefault()
    const body = text.trim()
    if (!body || sending) return
    setSending(true); setError('')
    try {
      if (editingId) { replace(await chatApi.edit(editingId, body)); setEditingId(null) }
      else {
        const m = await chatApi.post(channelId, body, replyTo?.id)
        stickBottom.current = true
        setMessages((prev) => [...prev, m])
        lastRead.current = m.id
        onActivity()
      }
      setText(''); setReplyTo(null)
    } catch (err) { setError(getErrorMessage(err)) } finally { setSending(false); inputRef.current?.focus() }
  }
  const onKey = (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) send(e)
    if (e.key === 'Escape') { setReplyTo(null); setEditingId(null); setText('') }
  }
  const react = async (m, r) => { try { replace(await chatApi.react(m.id, r)) } catch (err) { setError(getErrorMessage(err)) } }
  const recall = async (m) => { if (window.confirm('Thu hồi tin nhắn này?')) { try { replace(await chatApi.recall(m.id)) } catch (err) { setError(getErrorMessage(err)) } } }
  const leave = async () => {
    if (!window.confirm(`Rời nhóm "${channel.name}"?`)) return
    try { await chatApi.leave(channelId); onActivity(); onBack(true) } catch (err) { setError(getErrorMessage(err)) }
  }

  if (!channel) return <div className="chat-main"><p className="muted center top-gap">{error || 'Đang tải...'}</p></div>
  return (
    <div className="chat-main">
      <header className="chat-head">
        <button className="btn ghost only-sm" onClick={() => onBack(false)} aria-label="Quay lại danh sách"><i className="ti ti-arrow-left" aria-hidden="true" /></button>
        <ChannelIcon channel={channel} />
        <div className="grow"><b>{channel.name}</b>
          <div className="muted small">{channel.type === 'company' ? 'Mọi người trong công ty' : channel.type === 'direct' ? 'Nhắn riêng' : `${channel.members.length} thành viên`}</div></div>
        {channel.type === 'group' && <button className="btn ghost" onClick={() => setShowMembers(!showMembers)} aria-label="Thành viên nhóm" aria-expanded={showMembers}><i className="ti ti-users" aria-hidden="true" /></button>}
      </header>
      {showMembers && (
        <div className="chat-members">
          {channel.members.map((m) => <span key={m.userId} className="member-chip"><span className="avatar tiny">{initials(m.fullName)}</span>{m.fullName}{m.role === 'owner' && <span className="muted small"> · trưởng nhóm</span>}</span>)}
          {channel.canAddMembers && <button className="btn small" onClick={() => setAdding(true)}><i className="ti ti-user-plus" aria-hidden="true" /> Thêm người</button>}
          {channel.canLeave && <button className="btn small danger-text" onClick={leave}>Rời nhóm</button>}
        </div>
      )}
      <div className="chat-messages" ref={listRef} onScroll={onScroll} aria-live="polite">
        {hasMore && <div className="center"><button className="btn small" onClick={loadOlder}>Tải tin cũ hơn</button></div>}
        {messages.length === 0 && <p className="muted center top-gap">Chưa có tin nhắn. Gửi lời chào đầu tiên 👋</p>}
        {messages.map((m, i) => {
          const prev = messages[i - 1]
          const newDay = !prev || dayKey(prev.createdAt) !== dayKey(m.createdAt)
          const grouped = !newDay && prev.senderId === m.senderId && toDate(m.createdAt) - toDate(prev.createdAt) < 5 * 60 * 1000
          return (
            <div key={m.id}>
              {newDay && <div className="day-sep"><span>{dayLabel(m.createdAt)}</span></div>}
              <div className={`chat-msg${m.isMine ? ' mine' : ''}${grouped ? ' grouped' : ''}`}>
                {!m.isMine && <span className="avatar tiny msg-avatar" aria-hidden="true">{grouped ? '' : initials(m.senderName)}</span>}
                <div className="msg-body">
                  {!grouped && !m.isMine && <div className="msg-sender">{m.senderName}</div>}
                  <div className={`bubble${m.isDeleted ? ' recalled' : ''}`}>
                    {m.parentMessageId && <div className="reply-quote"><b>{m.parentSender}</b> {m.parentPreview}</div>}
                    {m.isDeleted ? <i>Tin nhắn đã thu hồi</i> : <span className="pre-wrap">{m.body}</span>}
                    <span className="msg-time">{timeOf(m.createdAt)}{m.isEdited && ' · đã sửa'}</span>
                  </div>
                  {m.reactions.length > 0 && (
                    <div className="reactions">
                      {m.reactions.map((r) => <button key={r.reaction} className={`reaction${r.mine ? ' mine' : ''}`} title={r.names.join(', ')} onClick={() => react(m, r.reaction)}>{r.reaction} {r.count}</button>)}
                    </div>
                  )}
                  {!m.isDeleted && (
                    <div className="msg-actions">
                      {REACTIONS.map((r) => <button key={r} onClick={() => react(m, r)} aria-label={`Thả ${r}`}>{r}</button>)}
                      <button onClick={() => { setReplyTo(m); setEditingId(null); inputRef.current?.focus() }} aria-label="Trả lời"><i className="ti ti-arrow-back-up" aria-hidden="true" /></button>
                      {m.isMine && <button onClick={() => { setEditingId(m.id); setReplyTo(null); setText(m.body); inputRef.current?.focus() }} aria-label="Sửa tin nhắn"><i className="ti ti-pencil" aria-hidden="true" /></button>}
                      {m.isMine && <button onClick={() => recall(m)} aria-label="Thu hồi tin nhắn"><i className="ti ti-trash" aria-hidden="true" /></button>}
                    </div>
                  )}
                </div>
              </div>
            </div>
          )
        })}
      </div>
      {error && <div className="alert error compact">{error}</div>}
      <form className="chat-composer" onSubmit={send}>
        {(replyTo || editingId) && (
          <div className="composer-context">
            {replyTo ? <span>Trả lời <b>{replyTo.senderName}</b>: {replyTo.body?.slice(0, 80)}</span> : <span><i className="ti ti-pencil" aria-hidden="true" /> Đang sửa tin nhắn</span>}
            <button type="button" className="btn ghost small" onClick={() => { setReplyTo(null); setEditingId(null); setText('') }} aria-label="Bỏ"><i className="ti ti-x" aria-hidden="true" /></button>
          </div>
        )}
        <div className="composer-row">
          <textarea ref={inputRef} rows={1} value={text} onChange={(e) => setText(e.target.value)} onKeyDown={onKey} maxLength={4000}
            placeholder={`Nhắn tới ${channel.name}… (Enter để gửi, Shift+Enter xuống dòng)`} aria-label="Nội dung tin nhắn" />
          <button className="btn primary" disabled={!text.trim() || sending} aria-label="Gửi"><i className="ti ti-send" aria-hidden="true" /></button>
        </div>
      </form>
      {adding && <AddMembersModal channel={channel} onClose={() => setAdding(false)} onDone={() => { setAdding(false); refresh() }} />}
    </div>
  )
}

/** Chat nội bộ: danh sách kênh bên trái, cuộc trò chuyện bên phải. Tự cập nhật tin mới vài giây một lần. */
export default function ChatPage() {
  const [params, setParams] = useSearchParams()
  const [channels, setChannels] = useState(null)
  const [filter, setFilter] = useState('')
  const [creating, setCreating] = useState(false)
  const [error, setError] = useState('')
  const activeId = Number(params.get('c')) || null

  const load = useCallback(() => chatApi.channels().then((list) => { setChannels(list); setError('') }).catch((e) => setError(getErrorMessage(e))), [])
  useEffect(() => { load() }, [load])
  usePolling(load, POLL_CHANNELS_MS)
  const open = (id) => setParams(id ? { c: String(id) } : {})
  // Màn hình rộng: tự mở kênh đầu tiên
  useEffect(() => {
    if (!activeId && channels?.length && window.matchMedia('(min-width: 769px)').matches) setParams({ c: String(channels[0].id) }, { replace: true })
  }, [channels, activeId, setParams])

  const shown = (channels ?? []).filter((c) => !filter || c.name.toLowerCase().includes(filter.toLowerCase()))
  const totalUnread = (channels ?? []).reduce((t, c) => t + c.unread, 0)

  return (
    <div className={`chat-page${activeId ? ' has-active' : ''}`}>
      <aside className="chat-list">
        <div className="chat-list-head">
          <h1>Chat {totalUnread > 0 && <span className="badge">{totalUnread}</span>}</h1>
          <button className="btn primary small" onClick={() => setCreating(true)}><i className="ti ti-edit" aria-hidden="true" /> Mới</button>
        </div>
        <div className="search"><i className="ti ti-search" aria-hidden="true" /><input value={filter} onChange={(e) => setFilter(e.target.value)} placeholder="Tìm cuộc trò chuyện" aria-label="Tìm cuộc trò chuyện" /></div>
        {error && <div className="alert error compact">{error}</div>}
        <nav className="channels" aria-label="Cuộc trò chuyện">
          {!channels && <p className="muted">Đang tải...</p>}
          {shown.map((c) => (
            <button key={c.id} className={`chat-channel${c.id === activeId ? ' active' : ''}${c.unread ? ' unread' : ''}`} onClick={() => open(c.id)}>
              <ChannelIcon channel={c} />
              <span className="grow">
                <span className="channel-top"><b>{c.name}</b><span className="muted small">{shortWhen(c.lastMessageAt)}</span></span>
                <span className="channel-last muted small">{c.lastMessage ? `${c.type !== 'direct' && c.lastSenderName ? `${c.lastSenderName}: ` : ''}${c.lastMessage}` : 'Chưa có tin nhắn'}</span>
              </span>
              {c.unread > 0 && <span className="badge">{c.unread > 99 ? '99+' : c.unread}</span>}
            </button>
          ))}
        </nav>
      </aside>
      {activeId ? <Conversation key={activeId} channelId={activeId} onBack={(left) => { open(null); if (left) load() }} onActivity={load} />
        : <div className="chat-main empty"><div className="center muted"><i className="ti ti-messages big-icon" aria-hidden="true" /><p>Chọn một cuộc trò chuyện để bắt đầu.</p></div></div>}
      {creating && <NewChatModal onClose={() => setCreating(false)} onOpened={(c) => { setCreating(false); load(); open(c.id) }} />}
    </div>
  )
}
