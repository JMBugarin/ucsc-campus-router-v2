import { useState } from 'react'
import { GlassButton } from '../design/components'
import { FEEDBACK_URL, MAX_MESSAGE, markedEasy, rememberEasy, sendFeedback, type FeedbackKind, type FeedbackResult } from '../state/feedback'

const RESULT_TEXT: Record<Exclude<FeedbackResult, 'ok'>, string> = {
  rejected: 'That could not be sent. Check the note and try again.',
  busy: 'Lots of feedback right now. Try again in a minute.',
  failed: 'Could not reach the server. Try again when you are online.',
}
const PRIVACY = 'Anonymous: only the room and your note are sent. Leave out names and contact details. Tips are checked on foot before they show up.'

function NoteForm({ label, placeholder, required, onSend, onCancel, initial = '' }: { label: string; placeholder: string; required: boolean; onSend: (text: string) => void; onCancel: () => void; initial?: string }) {
  const [text, setText] = useState(initial)
  return (
    <form
      className="fbform"
      onSubmit={(e) => {
        e.preventDefault()
        if (!required || text.trim()) onSend(text)
      }}
    >
      <label className="afield">
        <span>{label}</span>
        <textarea value={text} maxLength={MAX_MESSAGE} rows={2} placeholder={placeholder} onChange={(e) => setText(e.target.value)} autoFocus />
      </label>
      <div className="audit__row">
        <GlassButton size="s" variant="primary" type="submit" disabled={required && !text.trim()}>
          Send
        </GlassButton>
        <GlassButton size="s" onClick={onCancel}>
          Cancel
        </GlassButton>
        <small className="fbcount tabular">
          {text.length}/{MAX_MESSAGE}
        </small>
      </div>
    </form>
  )
}

/** Easy / off / tip buttons on a room page. Hidden when no feedback endpoint is configured. */
export function RoomFeedback({ place, url = FEEDBACK_URL }: { place: string; url?: string }) {
  const [open, setOpen] = useState<FeedbackKind | null>(null)
  const [sent, setSent] = useState<string | null>(() => (markedEasy(place) ? 'You marked this room easy to find.' : null))
  const [error, setError] = useState<string | null>(null)
  if (!url) return null
  const send = async (kind: FeedbackKind, message = '') => {
    setError(null)
    const r = await sendFeedback(place, kind, message, url)
    if (r !== 'ok') return setError(RESULT_TEXT[r])
    if (kind === 'easy') rememberEasy(place)
    setOpen(null)
    setSent(kind === 'easy' ? 'Thanks. Marked easy to find.' : kind === 'tip' ? 'Thanks. Your tip will be checked before it shows up.' : 'Thanks. This room goes on the list to walk.')
  }
  return (
    <section className="feedback" aria-label="Room feedback">
      <div className="feedback__q">Did this get you there?</div>
      {open === null && (
        <div className="audit__row">
          <GlassButton size="s" icon="check" disabled={markedEasy(place)} onClick={() => send('easy')}>
            Easy to find
          </GlassButton>
          <GlassButton size="s" icon="warn" onClick={() => setOpen('unclear')}>
            Pin or route was off
          </GlassButton>
          <GlassButton size="s" icon="plus" onClick={() => setOpen('tip')}>
            Add a tip
          </GlassButton>
        </div>
      )}
      {open === 'unclear' && <NoteForm label="What was off? (optional)" placeholder="The door on the map is locked; use the one by the stairs" required={false} onSend={(t) => send('unclear', t)} onCancel={() => setOpen(null)} />}
      {open === 'tip' && <NoteForm label="Your finding tip" placeholder="Door is tucked behind the vending machines" required onSend={(t) => send('tip', t)} onCancel={() => setOpen(null)} />}
      {sent && (
        <p className="note" role="status">
          {sent}
        </p>
      )}
      {error && (
        <p className="note fberror" role="alert">
          {error}
        </p>
      )}
      <p className="note">{PRIVACY}</p>
    </section>
  )
}

/** "Can't find a room?" under search results: asks for the room to be added. */
export function MissingRoom({ query, url = FEEDBACK_URL }: { query: string; url?: string }) {
  const [open, setOpen] = useState(false)
  const [state, setState] = useState<string | null>(null)
  if (!url) return null
  if (state === 'ok') return <p className="note" role="status">Thanks. We'll look for that room.</p>
  return (
    <div className="feedback">
      {!open ? (
        <button className="rowlink" onClick={() => setOpen(true)}>
          Can't find your room? Tell us which one →
        </button>
      ) : (
        <NoteForm
          label="Which room is missing?"
          placeholder="Crown 207, or the class and building"
          required
          initial={query}
          onCancel={() => setOpen(false)}
          onSend={async (t) => {
            const r = await sendFeedback('campus', 'missing', t, url)
            setState(r === 'ok' ? 'ok' : RESULT_TEXT[r])
          }}
        />
      )}
      {state && state !== 'ok' && (
        <p className="note fberror" role="alert">
          {state}
        </p>
      )}
      {open && <p className="note">{PRIVACY}</p>}
    </div>
  )
}
