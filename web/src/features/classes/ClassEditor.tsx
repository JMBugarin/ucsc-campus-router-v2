import { useState } from 'react'
import { GlassButton, GlassModal } from '../../design/components'
import type { SearchIndex } from '../../data/search'
import type { Place } from '../../data/types'
import type { Campus } from '../../schedule/campus'
import { problem, type ClassDraft } from '../../schedule/draft'
import { DAY_CODES, WEEKDAY_NAMES, dayLabel } from '../../schedule/time'
import { RoomPicker, RoomStatus } from './RoomCheck'

const COMPONENTS = ['Lecture', 'Discussion', 'Laboratory', 'Seminar', 'Studio', 'Tutorial']

/** Add or change one class. Used for "Add a class", editing a saved class and fixing an imported one. */
export function ClassEditor({
  draft,
  title,
  campus,
  byId,
  index,
  onSave,
  onDelete,
  onClose,
  saveLabel = 'Save',
}: {
  draft: ClassDraft
  title: string
  campus: Campus
  byId: Map<string, Place>
  index: SearchIndex
  onSave: (d: ClassDraft) => void
  onDelete?: () => void
  onClose: () => void
  saveLabel?: string
}) {
  const [d, setD] = useState<ClassDraft>(draft)
  const [picking, setPicking] = useState(false)
  const [skipDay, setSkipDay] = useState('')
  const [confirmDelete, setConfirmDelete] = useState(false)
  const set = (patch: Partial<ClassDraft>) => setD((x) => ({ ...x, ...patch, edited: true }))
  const issue = problem(d)
  const toggleDay = (i: number) => set({ days: d.days.includes(i) ? d.days.filter((x) => x !== i) : [...d.days, i].sort((a, b) => a - b) })
  return (
    <GlassModal open onClose={onClose} title={title}>
      <form
        className="editor"
        onSubmit={(e) => {
          e.preventDefault()
          if (!issue) onSave(d)
        }}
      >
        {d.reasons.length > 0 && !d.edited && <p className="note editor__why">Check this one: {d.reasons.join(' ')}</p>}
        <div className="editor__row">
          <label className="afield">
            <span>Course</span>
            <input value={d.course} placeholder="CSE 130" maxLength={40} onChange={(e) => set({ course: e.target.value.toUpperCase() })} />
          </label>
          <label className="afield">
            <span>Type</span>
            <input list="components" value={d.component} placeholder="Lecture" maxLength={30} onChange={(e) => set({ component: e.target.value })} />
            <datalist id="components">
              {COMPONENTS.map((c) => (
                <option key={c} value={c} />
              ))}
            </datalist>
          </label>
        </div>
        <label className="afield">
          <span>Title (optional)</span>
          <input value={d.title} maxLength={80} placeholder="Principles of Computer System Design" onChange={(e) => set({ title: e.target.value })} />
        </label>
        <div className="afield">
          <span>Days</span>
          <div className="daypick" role="group" aria-label="Days it meets">
            {DAY_CODES.map((code, i) => (
              <button key={code} type="button" className="daypick__day" aria-pressed={d.days.includes(i)} aria-label={WEEKDAY_NAMES[i]} onClick={() => toggleDay(i)}>
                {code}
              </button>
            ))}
          </div>
        </div>
        <div className="editor__row">
          <label className="afield">
            <span>Starts</span>
            <input type="time" value={d.start ?? ''} onChange={(e) => set({ start: e.target.value || null })} />
          </label>
          <label className="afield">
            <span>Ends</span>
            <input type="time" value={d.end ?? ''} onChange={(e) => set({ end: e.target.value || null })} />
          </label>
        </div>
        <label className="afield">
          <span>Room</span>
          <input value={d.location} maxLength={80} placeholder="J Baskin Engr 152" onChange={(e) => set({ location: e.target.value })} />
        </label>
        <div className="editor__room">
          <RoomStatus location={d.location} campus={campus} byId={byId} />
          {!picking && (
            <GlassButton size="s" icon="search" onClick={() => setPicking(true)}>
              Find the room
            </GlassButton>
          )}
        </div>
        {picking && (
          <RoomPicker
            index={index}
            initial={d.location}
            onPick={(name) => (set({ location: name }), setPicking(false))}
            onCancel={() => setPicking(false)}
          />
        )}
        <div className="editor__row">
          <label className="afield">
            <span>First day</span>
            <input type="date" value={d.startDate ?? ''} onChange={(e) => set({ startDate: e.target.value || null })} />
          </label>
          <label className="afield">
            <span>Last day</span>
            <input type="date" value={d.endDate ?? ''} onChange={(e) => set({ endDate: e.target.value || null })} />
          </label>
        </div>
        {onDelete && (
          <div className="afield">
            <span>Skipped days</span>
            {(d.skipDates ?? []).length > 0 && (
              <div className="chips-wrap">
                {(d.skipDates ?? []).map((s) => (
                  <button key={s} type="button" className="roomchip" aria-label={`Meet on ${dayLabel(s)} after all`} onClick={() => set({ skipDates: (d.skipDates ?? []).filter((x) => x !== s) })}>
                    {dayLabel(s)} ✕
                  </button>
                ))}
              </div>
            )}
            <div className="editor__row editor__row--tight">
              <input type="date" aria-label="Day to skip" value={skipDay} min={d.startDate ?? undefined} max={d.endDate ?? undefined} onChange={(e) => setSkipDay(e.target.value)} />
              <GlassButton
                size="s"
                disabled={!skipDay}
                onClick={() => {
                  set({ skipDates: [...new Set([...(d.skipDates ?? []), skipDay])].sort() })
                  setSkipDay('')
                }}
              >
                Skip that day
              </GlassButton>
            </div>
          </div>
        )}
        {issue && <p className="note editor__issue">{issue}</p>}
        <div className="audit__row">
          <GlassButton variant="primary" type="submit" disabled={!!issue}>
            {saveLabel}
          </GlassButton>
          <GlassButton onClick={onClose}>Cancel</GlassButton>
          {onDelete && (
            <GlassButton icon="close" onClick={() => (confirmDelete ? onDelete() : setConfirmDelete(true))}>
              {confirmDelete ? 'Tap again to delete' : 'Delete class'}
            </GlassButton>
          )}
        </div>
      </form>
    </GlassModal>
  )
}
