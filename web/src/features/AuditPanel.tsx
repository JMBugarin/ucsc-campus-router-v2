import { useState } from 'react'
import { GlassButton, GlassSegmentedControl, SectionLabel } from '../design/components'
import type { Access, Place } from '../data/types'
import { relation } from '../data/rooms'
import { LIMITS, audit, guideEntry, pacificDate, roomKey, useDraft, usePicking, type Draft } from '../state/audit'

function Field({ label, value, max, onChange, multiline, placeholder }: { label: string; value: string; max: number; onChange: (v: string) => void; multiline?: boolean; placeholder?: string }) {
  return (
    <label className="afield">
      <span>{label}</span>
      {multiline ? (
        <textarea value={value} rows={3} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} />
      ) : (
        <input value={value} maxLength={max} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} />
      )}
    </label>
  )
}

/** Field tool for walking a room: shown only with ?audit, it writes the data/rooms.json entry to paste. */
export function AuditPanel({ room, onLocate }: { room: Place; onLocate: () => Promise<[number, number] | null> }) {
  const key = roomKey(room)
  const d = useDraft(key) as Draft
  const picking = usePicking() === key
  const [copied, setCopied] = useState<string | null>(null)
  const [locError, setLocError] = useState<string | null>(null)
  const set = (patch: Partial<Draft>) => audit.set(key, patch)
  const today = pacificDate(new Date())
  const entry = guideEntry(d, today)
  const json = entry ? JSON.stringify({ [key]: entry }, null, 2).slice(1, -1).trim() : ''
  const door = d.door ? relation(d.door, [room.lat, room.lon]) : null
  const copy = async (text: string, what: string) => {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(what)
    } catch {
      setCopied('Copy failed; select the text below instead')
    }
  }
  return (
    <section className="audit" aria-label="Audit this room">
      <SectionLabel>Audit {room.name}</SectionLabel>
      <p className="note">Record only what you checked here today. Leave a field empty rather than guess.</p>
      <div className="afield">
        <span>How you get in</span>
        <GlassSegmentedControl<Access | ''>
          label="How you get in"
          value={d.access}
          onChange={(v) => set({ access: v })}
          options={[
            { value: '', label: 'Not set' },
            { value: 'outside', label: 'Outside' },
            { value: 'lobby', label: 'Lobby' },
            { value: 'library', label: 'Library' },
          ]}
        />
      </div>
      <div className="afield">
        <span>Door you would use</span>
        <div className="audit__row">
          <GlassButton size="s" icon="pin" aria-pressed={picking} onClick={() => audit.startPick(picking ? null : key)}>
            {picking ? 'Tap the door on the map…' : 'Tap it on the map'}
          </GlassButton>
          <GlassButton
            size="s"
            icon="locate"
            onClick={async () => {
              setLocError(null)
              const at = await onLocate()
              if (at) set({ door: at })
              else setLocError('Location unavailable.')
            }}
          >
            I'm at the door
          </GlassButton>
          {d.door && (
            <GlassButton size="s" icon="close" onClick={() => set({ door: null })}>
              Clear
            </GlassButton>
          )}
        </div>
        <small className="tabular">{d.door ? `${d.door[0].toFixed(6)}, ${d.door[1].toFixed(6)} · room is ${Math.round(door!.meters)} m ${door!.toward} of it` : 'Not set'}</small>
        {locError && <small>{locError}</small>}
      </div>
      <Field label="Door name" value={d.doorLabel} max={LIMITS.doorLabel} placeholder="East patio door by the bike racks" onChange={(v) => set({ doorLabel: v })} />
      <Field label="Floor as signed" value={d.floor} max={LIMITS.floor} placeholder={room.room?.floor?.label ?? ''} onChange={(v) => set({ floor: v })} />
      <Field label="Wing or side" value={d.wing} max={LIMITS.wing} placeholder="North wing" onChange={(v) => set({ wing: v })} />
      <Field label="One-line tip" value={d.note} max={LIMITS.note} placeholder="Enter from the lower plaza, not the upper path" onChange={(v) => set({ note: v })} />
      <Field label={`Steps from the door (one per line, up to ${LIMITS.steps})`} value={d.steps} max={LIMITS.step * LIMITS.steps} multiline placeholder={'Through the glass doors\nLeft past the stairwell'} onChange={(v) => set({ steps: v })} />
      <div className="afield">
        <span>Step-free from that door</span>
        <GlassSegmentedControl<Draft['stepFree']>
          label="Step-free from that door"
          value={d.stepFree}
          onChange={(v) => set({ stepFree: v })}
          options={[
            { value: '', label: 'Not checked' },
            { value: 'yes', label: 'Yes' },
            { value: 'no', label: 'No, stairs' },
          ]}
        />
      </div>
      <Field label="Elevator" value={d.elevator} max={LIMITS.elevator} placeholder="Just inside the main lobby" onChange={(v) => set({ elevator: v })} />
      {d.doorLabel.trim() && !d.door && <p className="note">Place the door on the map to keep its name.</p>}
      <label className="afield">
        <span>For data/rooms.json</span>
        <textarea className="tabular" readOnly rows={Math.min(14, json.split('\n').length + 1)} value={json || 'Nothing recorded yet.'} aria-label="Entry for data/rooms.json" />
      </label>
      <div className="audit__row">
        <GlassButton size="s" variant="primary" icon="check" disabled={!json} onClick={() => copy(json + ',', 'Copied this room')}>
          Copy this room
        </GlassButton>
        <GlassButton size="s" onClick={() => copy(JSON.stringify(audit.all(today), null, 2), 'Copied every room you audited')}>
          Copy all audited rooms
        </GlassButton>
        <GlassButton size="s" icon="close" onClick={() => audit.clear(key)}>
          Clear draft
        </GlassButton>
      </div>
      {copied && <p className="note" role="status">{copied}</p>}
    </section>
  )
}
