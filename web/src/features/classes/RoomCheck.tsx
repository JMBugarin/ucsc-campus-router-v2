import { useMemo, useState } from 'react'
import type { Campus } from '../../schedule/campus'
import type { Place } from '../../data/types'
import type { SearchIndex } from '../../data/search'
import { placeFor } from '../../schedule/data'
import { GlassButton } from '../../design/components'
import { Icon } from '../../design/icons'

export type RoomState = 'found' | 'unlisted' | 'notFound' | 'none' | 'empty'

/** What the campus data makes of a class location, for the student to act on. */
export function roomState(location: string, campus: Campus): RoomState {
  if (!location.trim()) return 'empty'
  const r = campus.resolve(location, true)
  if (r.kind === 'online' || r.kind === 'tba') return 'none'
  if (r.kind === 'unknown') return 'notFound'
  return r.roomKnown === false ? 'unlisted' : 'found'
}
export const needsLook = (s: RoomState) => s === 'unlisted' || s === 'notFound'

export function RoomStatus({ location, campus, byId }: { location: string; campus: Campus; byId: Map<string, Place> }) {
  const state = roomState(location, campus)
  const place = placeFor(location, campus, byId)
  const r = campus.resolve(location, true)
  const text: Record<RoomState, string> = {
    found: place ? `On the map: ${place.name}` : 'A campus building',
    unlisted: `${campus.buildings.get(r.buildingId ?? '')?.name ?? 'That building'} doesn't list room ${r.room ?? ''}. Check the number.`,
    notFound: "Not a campus room the map knows. Find the room below.",
    none: r.kind === 'online' ? 'Online: nothing to walk to.' : 'Room to be announced.',
    empty: 'No room yet.',
  }
  return (
    <span className="roomstate" data-state={state}>
      <Icon name={state === 'found' ? 'check' : state === 'none' || state === 'empty' ? 'info' : 'warn'} size={14} />
      {text[state]}
    </span>
  )
}

/** Search the map's rooms and buildings to fix a class's room. */
export function RoomPicker({ index, initial, onPick, onCancel }: { index: SearchIndex; initial: string; onPick: (name: string) => void; onCancel: () => void }) {
  const [q, setQ] = useState(initial)
  const results = useMemo(() => index.search(q, 8).filter((p) => p.kind === 'room' || p.kind === 'academic' || p.kind === 'library'), [index, q])
  return (
    <div className="roompicker">
      <label className="afield">
        <span>Find the room</span>
        <input autoFocus value={q} placeholder="Kresge 3201" onChange={(e) => setQ(e.target.value)} />
      </label>
      <div className="roompicker__list" role="listbox" aria-label="Rooms">
        {q.trim() && !results.length && <p className="note">No match. Try the building and room, like "Kresge 3201".</p>}
        {results.map((p) => (
          <button key={p.id} role="option" aria-selected="false" className="roompicker__row" onClick={() => onPick(p.name)}>
            <Icon name={p.kind === 'room' ? 'door' : 'academic'} size={15} />
            <span>{p.name}</span>
          </button>
        ))}
      </div>
      <GlassButton size="s" onClick={onCancel}>
        Cancel
      </GlassButton>
    </div>
  )
}
