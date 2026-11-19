import { useMemo, useRef, useState } from 'react'
import { GlassBanner, GlassButton, GlassIconButton, GlassSearch, GlassSwitch, SectionLabel } from '../design/components'
import { Icon } from '../design/icons'
import { formatDistance, formatDuration, type Plan, type PlanError } from '../routing/plan'
import type { Place } from '../data/types'
import type { SearchIndex } from '../data/search'
import { PlaceRows } from './Browse'
import { clockText, type TransitData } from '../transit/schedule'
import type { BusPlan } from '../transit/plan'
import { ACCESS_LABEL, checkedText, doorSentence, relation } from '../data/rooms'

export type Pick = { id: string; name: string } | null

function Arrival({ room, end }: { room: Place; end: [number, number] }) {
  const info = room.room!
  const g = info.guide
  const atDoor = !!info.door && Math.abs(info.door.lat - end[0]) < 1e-5 && Math.abs(info.door.lon - end[1]) < 1e-5
  const ends = info.door?.checked && atDoor ? `The route ends at ${info.door.label ?? 'the checked door'}. ` : atDoor ? 'The route ends at the closest mapped door. ' : 'The route ends at a mapped door near the room. '
  return (
    <section className="arrive" aria-label="Arriving at the room">
      <h2 className="arrive__title">
        <Icon name="door" size={16} />
        Arriving at {info.number}
      </h2>
      {g?.access && <p className="arrive__line">{ACCESS_LABEL[g.access].detail}</p>}
      {g?.note && <p className="arrive__note">{g.note}</p>}
      {g?.steps && (
        <ol className="arrive__steps">
          {g.steps.map((s, i) => (
            <li key={i}>{s}</li>
          ))}
        </ol>
      )}
      <p className="arrive__line">
        {ends}
        {doorSentence(info, relation(end, [room.lat, room.lon]))}
      </p>
      {g?.elevator && <p className="arrive__line">Elevator: {g.elevator}</p>}
      <p className="note">{g ? checkedText(info) : 'Nobody has walked this room for the app yet, so check signs at the door.'}</p>
    </section>
  )
}
const LOWER = ['path', 'stairs', 'road', 'bridge']

/** Merge consecutive non-stair steps into one "Walk" leg and keep the surface mix as detail. */
function legs(plan: Plan) {
  const out: { stairs: boolean; meters: number; by: number[] }[] = []
  for (const s of plan.route.steps) {
    const stairs = s.kind === 1
    const last = out[out.length - 1]
    if (last && last.stairs === stairs) {
      last.meters += s.meters
      last.by[s.kind] += s.meters
    } else {
      const by = [0, 0, 0, 0]
      by[s.kind] = s.meters
      out.push({ stairs, meters: s.meters, by })
    }
  }
  return out.map((l) => ({
    stairs: l.stairs,
    meters: l.meters,
    detail: l.stairs ? 'Mapped steps' : l.by.map((m, k) => (m >= 5 ? `${LOWER[k]} ${formatDistance(m)}` : '')).filter(Boolean).join(' · '),
  }))
}

const ERROR_TEXT: Record<PlanError, string> = {
  'no-path-near-origin': 'The starting point is not near a mapped campus path, so a walking route cannot be drawn.',
  'no-path-near-destination': 'The destination is not near a mapped campus path, so a walking route cannot be drawn.',
  'no-route': 'No walking route connects these two places in the mapped path network.',
  'same-place': 'Choose two different places.',
}

function Field({ label, value, placeholder, onFocus, query, onQuery, active }: { label: string; value: string; placeholder: string; onFocus: () => void; query: string; onQuery: (v: string) => void; active: boolean }) {
  return (
    <GlassSearch
      label={label}
      value={active ? query : value}
      onChange={onQuery}
      onFocus={onFocus}
      placeholder={placeholder}
      leading={<span className="fieldtag">{label[0]}</span>}
    />
  )
}

export function Directions({
  from,
  to,
  plan,
  error,
  avoidStairs,
  onAvoidStairs,
  onPickFrom,
  onPickTo,
  onSwap,
  onClose,
  index,
  hasLocation,
  onLocate,
  locating,
  locationError,
  straightMeters,
  bus,
  transit,
  toRoom,
}: {
  toRoom?: Place | null
  bus?: BusPlan | null
  transit?: TransitData | null
  from: Pick
  to: Pick
  plan: Plan | null
  error: PlanError | null
  avoidStairs: boolean
  onAvoidStairs: (v: boolean) => void
  onPickFrom: (p: Pick) => void
  onPickTo: (p: Pick) => void
  onSwap: () => void
  onClose: () => void
  index: SearchIndex
  hasLocation: boolean
  onLocate: () => void
  locating: boolean
  locationError: string | null
  straightMeters: number | null
}) {
  const [editing, setEditing] = useState<'from' | 'to' | null>(!from ? 'from' : !to ? 'to' : null)
  const [q, setQ] = useState('')
  const inputRef = useRef<HTMLDivElement>(null)
  const suggestions = useMemo(() => (editing ? index.search(q, 8) : []), [editing, q, index])

  const choose = (p: Place) => {
    const v = { id: p.id, name: p.name }
    if (editing === 'from') onPickFrom(v)
    else onPickTo(v)
    setEditing(null)
    setQ('')
  }

  return (
    <section aria-label="Walking directions" className="directions" ref={inputRef}>
      <div className="detail__head">
        <GlassIconButton icon="back" label="Close directions" onClick={onClose} />
        <h1 className="detail__title" style={{ flex: 1 }}>
          Walking directions
        </h1>
      </div>
      <div className="dfields">
        <div className="dfields__col">
          <Field label="From" value={from?.name ?? ''} placeholder="Choose starting point" query={q} onQuery={setQ} active={editing === 'from'} onFocus={() => (setEditing('from'), setQ(''))} />
          <Field label="To" value={to?.name ?? ''} placeholder="Choose destination" query={q} onQuery={setQ} active={editing === 'to'} onFocus={() => (setEditing('to'), setQ(''))} />
        </div>
        <GlassIconButton icon="swap" label="Swap start and destination" onClick={onSwap} />
      </div>

      {editing ? (
        <div>
          {editing === 'from' && (
            <GlassButton size="s" icon="locate" onClick={() => (onLocate(), setEditing(null))} disabled={locating} style={{ margin: '4px 0 6px' }}>
              {locating ? 'Locating…' : hasLocation ? 'Use my location' : 'Use my location'}
            </GlassButton>
          )}
          <PlaceRows places={suggestions} onPick={choose} label={`Choose ${editing === 'from' ? 'starting point' : 'destination'}`} />
        </div>
      ) : (
        <>
          <div className="dopt">
            <span>
              Avoid stairs
              <small>Routes around mapped steps when a path exists. Not a verified accessibility route.</small>
            </span>
            <GlassSwitch checked={avoidStairs} onChange={onAvoidStairs} label="Avoid stairs" />
          </div>
          {locationError && <GlassBanner tone="warning" title="Location unavailable">{locationError}</GlassBanner>}
          {error && (
            <GlassBanner tone={error === 'same-place' ? 'accent' : 'warning'} title={error === 'same-place' ? undefined : 'No walking route'}>
              {ERROR_TEXT[error]}
              {straightMeters != null && error !== 'same-place' && <> Straight-line distance: {formatDistance(straightMeters)}.</>}
            </GlassBanner>
          )}
          {plan && (
            <>
              <div className="summary" aria-live="polite">
                <div className="summary__time">{formatDuration(plan.seconds)}</div>
                <div className="summary__meta tabular">
                  {formatDistance(plan.meters)} · ↑ {Math.round(plan.route.gain)} m · ↓ {Math.round(plan.route.loss)} m
                </div>
              </div>
              {avoidStairs && plan.stairsUnavoidable && (
                <GlassBanner tone="warning" title="Stairs on this route">
                  No route without mapped stairs exists between these places, so the shortest one is shown.
                </GlassBanner>
              )}
              {bus && transit && (
                <>
                  <SectionLabel>By bus</SectionLabel>
                  {bus.options.length ? (
                    <ul className="bus">
                      {bus.options.map((o) => (
                        <li key={o.tripId + o.departs}>
                          <span className="route">{o.route}</span>
                          <span className="bus__main">
                            {transit.stops[o.board].name} {clockText(o.departs)} to {transit.stops[o.alight].name}
                            <small>
                              Walk {Math.max(1, Math.round(o.walkToStop / 60))} min to the stop, ride, walk {Math.max(1, Math.round(o.walkFromStop / 60))} min. Scheduled.
                            </small>
                          </span>
                          <span className="bus__eta tabular">{clockText(o.arrives)}</span>
                        </li>
                      ))}
                    </ul>
                  ) : (
                    <p className="note">No direct METRO bus gets there sooner than walking{bus.walkOnlyArrives ? ` (arrive ${clockText(bus.walkOnlyArrives)})` : ''}.</p>
                  )}
                </>
              )}
              <SectionLabel>On foot</SectionLabel>
              <ol className="steps">
                {legs(plan).map((l, i) => (
                  <li key={i}>
                    <span className="steps__icon" data-kind={l.stairs ? 1 : 0}>
                      <Icon name={l.stairs ? 'stairs' : 'walk'} size={16} />
                    </span>
                    <span className="steps__main">
                      {l.stairs ? 'Climb stairs' : 'Walk'}
                      <small>{l.detail}</small>
                    </span>
                    <span className="steps__trail tabular">{formatDistance(l.meters)}</span>
                  </li>
                ))}
              </ol>
              {toRoom?.room && <Arrival room={toRoom} end={plan.destPoint} />}
              <p className="note">
                Times use Tobler's walking function on USGS elevation (10 m), so they are estimates.
                {plan.connectorMeters > 5 && <> {formatDistance(plan.connectorMeters)} of the trip is from a door or point to the nearest mapped path (dotted).</>}
              </p>
              <div className="legend" aria-label="Route legend">
                <span><i data-k="0" /> Path</span>
                <span><i data-k="1" /> Stairs</span>
                <span><i data-k="2" /> Road</span>
                <span><i data-k="3" /> Bridge</span>
              </div>
            </>
          )}
        </>
      )}
    </section>
  )
}
