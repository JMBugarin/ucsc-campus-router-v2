import { useEffect, useState } from 'react'
import { GlassBanner, GlassButton, GlassModal } from '../../design/components'
import { Icon } from '../../design/icons'
import type { SearchIndex } from '../../data/search'
import type { Place } from '../../data/types'
import type { Campus } from '../../schedule/campus'
import { draftFromMeeting, draftLabel, draftTime, daysLabel, flagged, newDraft, problem, toMeeting, type ClassDraft } from '../../schedule/draft'
import { parseSchedule } from '../../schedule/ocr/parser'
import { PictureError, recognizePicture } from '../../schedule/ocr/recognize'
import { needsReview, reasons } from '../../schedule/ocr/rows'
import { ScheduleError } from '../../schedule/meeting'
import { parsePasted } from '../../schedule/paste'
import { ClassEditor } from './ClassEditor'
import { RoomStatus, needsLook, roomState } from './RoomCheck'

/** Check classes read from a paste or a picture before anything is saved. */
export function ImportReview({
  drafts: initial,
  notes,
  campus,
  byId,
  index,
  onSave,
  onClose,
}: {
  drafts: ClassDraft[]
  notes: string[]
  campus: Campus
  byId: Map<string, Place>
  index: SearchIndex
  onSave: (drafts: ClassDraft[]) => void
  onClose: () => void
}) {
  const [drafts, setDrafts] = useState(initial)
  const [editing, setEditing] = useState<ClassDraft | null>(null)
  const blocked = drafts.filter((d) => problem(d))
  const toLook = drafts.filter((d) => flagged(d) || needsLook(roomState(d.location, campus)))
  if (editing)
    return (
      <ClassEditor
        draft={editing}
        title={`Check ${draftLabel(editing) || 'this class'}`}
        campus={campus}
        byId={byId}
        index={index}
        saveLabel="Done"
        onSave={(d) => (setDrafts((all) => all.map((x) => (x.id === d.id ? d : x))), setEditing(null))}
        onClose={() => setEditing(null)}
      />
    )
  return (
    <GlassModal open onClose={onClose} title={`Check ${drafts.length} ${drafts.length === 1 ? 'class' : 'classes'}`}>
      <div className="review">
        {notes.map((n) => (
          <p key={n} className="note">
            {n}
          </p>
        ))}
        {toLook.length > 0 && (
          <GlassBanner tone="warning" title={`${toLook.length} to look at`}>
            Tap a class to fix its room, time or days. Nothing is saved until you press Save.
          </GlassBanner>
        )}
        <ul className="review__list">
          {drafts.map((d) => {
            const issue = problem(d)
            const look = flagged(d) || needsLook(roomState(d.location, campus))
            return (
              <li key={d.id} className="review__item" data-look={look || !!issue}>
                <button className="review__main" onClick={() => setEditing(d)} aria-label={`Edit ${draftLabel(d) || 'class'}`}>
                  <strong>{draftLabel(d) || 'Untitled class'}</strong>
                  <span className="tabular">
                    {daysLabel(d) || 'No days'} · {draftTime(d) || 'No time'}
                  </span>
                  <RoomStatus location={d.location} campus={campus} byId={byId} />
                  {(issue || (flagged(d) && d.reasons.length > 0)) && <small className="review__why">{issue ?? d.reasons.join(' ')}</small>}
                </button>
                <button className="review__remove" aria-label={`Leave out ${draftLabel(d) || 'this class'}`} onClick={() => setDrafts((all) => all.filter((x) => x.id !== d.id))}>
                  <Icon name="close" size={16} />
                </button>
              </li>
            )
          })}
        </ul>
        {blocked.length > 0 && <p className="note">Fix {blocked.length === 1 ? 'the class' : `the ${blocked.length} classes`} marked above, or leave {blocked.length === 1 ? 'it' : 'them'} out, to save.</p>}
        <div className="audit__row">
          <GlassButton variant="primary" icon="check" disabled={!drafts.length || blocked.length > 0} onClick={() => onSave(drafts)}>
            Save {drafts.length} {drafts.length === 1 ? 'class' : 'classes'}
          </GlassButton>
          <GlassButton onClick={onClose}>Cancel</GlassButton>
        </div>
      </div>
    </GlassModal>
  )
}

/** Paste the Class Schedule page from MyUCSC. */
export function PasteImport({ campus, onRead, onClose }: { campus: Campus; onRead: (drafts: ClassDraft[], notes: string[]) => void; onClose: () => void }) {
  const [text, setText] = useState('')
  const [error, setError] = useState<string | null>(null)
  const read = () => {
    try {
      const { meetings, notes } = parsePasted(text, campus)
      if (!meetings.length) return setError(notes.join(' '))
      onRead(meetings.map(draftFromMeeting), notes)
    } catch (e) {
      setError(e instanceof ScheduleError ? `${e.message[0].toUpperCase()}${e.message.slice(1)}.` : 'That text could not be read.')
    }
  }
  return (
    <GlassModal open onClose={onClose} title="Paste from MyUCSC">
      <ol className="howto">
        <li>
          In <a href="https://my.ucsc.edu" target="_blank" rel="noopener">MyUCSC</a>, open your <strong>Class Schedule</strong> (list view).
        </li>
        <li>Select the whole page (Ctrl+A or ⌘A, or "Select All" on a phone) and copy it.</li>
        <li>Paste it below. It is read here in your browser; nothing is uploaded.</li>
      </ol>
      <label className="afield">
        <span>Schedule text</span>
        <textarea rows={7} value={text} onChange={(e) => (setText(e.target.value), setError(null))} placeholder="CSE 130 - Principles of Computer Systems Design Status Units Grading … 10002 01 Lecture MoWeFr 1:20PM - 2:25PM J Baskin Engr 152 …" />
      </label>
      {error && (
        <p className="note fberror" role="alert">
          {error}
        </p>
      )}
      <div className="audit__row">
        <GlassButton variant="primary" disabled={!text.trim()} onClick={read}>
          Read my classes
        </GlassButton>
        <GlassButton onClick={onClose}>Cancel</GlassButton>
      </div>
    </GlassModal>
  )
}

export const toMeetings = (drafts: ClassDraft[]) => drafts.map(toMeeting)

/** Reads a picture of a schedule in this browser, then hands the classes to the review sheet. */
export function PictureImport({ file, onRead, onClose }: { file: File; onRead: (drafts: ClassDraft[], notes: string[]) => void; onClose: () => void }) {
  const [progress, setProgress] = useState(0)
  const [error, setError] = useState<string | null>(null)
  useEffect(() => {
    const abort = new AbortController()
    recognizePicture(file, setProgress, abort.signal)
      .then((reading) => {
        if (abort.signal.aborted) return
        const parsed = parseSchedule(reading)
        if (parsed.problem === 'noText') return setError("I couldn't find any text in that picture. Try a clearer screenshot of your Class Schedule page.")
        if (parsed.problem === 'noClasses') return setError(['I found text but no classes in it. Try a screenshot of your Class Schedule page, or paste it instead.', ...parsed.notes].join(' '))
        onRead(
          parsed.rows.map((r) => newDraft({ course: r.course, title: r.title, section: r.section, component: r.component, days: r.days, start: r.start, end: r.end, location: r.location, startDate: r.startDate, endDate: r.endDate, reasons: needsReview(r) ? reasons(r) : [] })),
          parsed.notes,
        )
      })
      .catch((e) => !abort.signal.aborted && setError(e instanceof PictureError ? e.message : "I couldn't read that picture. Try a clearer screenshot."))
    return () => abort.abort()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [file])
  return (
    <GlassModal open onClose={onClose} title="Reading your schedule">
      {error ? (
        <>
          <p className="note fberror" role="alert">
            {error}
          </p>
          <GlassButton onClick={onClose}>Close</GlassButton>
        </>
      ) : (
        <div className="reading" role="status" aria-live="polite">
          <div className="reading__bar">
            <i style={{ width: `${Math.round(progress * 100)}%` }} />
          </div>
          <p className="note">{progress > 0 ? `Reading… ${Math.round(progress * 100)}%` : 'Getting the reader ready…'} The picture stays on this device.</p>
          <GlassButton onClick={onClose}>Cancel</GlassButton>
        </div>
      )}
    </GlassModal>
  )
}
