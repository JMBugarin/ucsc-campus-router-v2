import { useMemo, useRef, useState } from 'react'
import { GlassBanner, GlassButton, GlassDisclosure, GlassIconButton, GlassList, GlassListRow, GlassSearch, GlassSwitch } from '../design/components'
import { CATEGORY_COLOR } from '../design/tokens'
import { Icon } from '../design/icons'
import { formatDistance, formatDuration, type Plan, type PlanError } from '../routing/plan'
import type { Place } from '../data/types'
import type { SearchIndex } from '../data/search'
import { PlaceRows } from './Browse'
import type { Vehicle } from '../transit/liveClient'
import type { LiveState } from '../transit/useTransit'
import type { TripOption } from '../transit/trip'
import { TripList } from './TripList'
import { searchAddresses, type Address } from '../data/geocode'
import { ACCESS_LABEL, checkedText, doorSentence, relation } from '../data/rooms'
import { GlassSegmentedControl, StatusPill } from '../design/components'
import { clockAt } from '../schedule/time'
import { useFold } from '../state/prefs'

export type Pick = { id: string; name: string } | null

export type Mode = 'walk' | 'bus'

/** Walking and the best bus side by side: when each gets you there, and how far apart they are. */
function ModeCompare({ plan, trip, loading, mode, onMode, now, arriveAt }: { plan: Plan; trip: TripOption | null; loading: boolean; mode: Mode; onMode: (m: Mode) => void; now: number; arriveAt: number | null }) {
  const walkMs = plan.seconds * 1000
  const walkLeave = arriveAt !== null ? Math.max(now, arriveAt - walkMs) : now
  const walkArrive = walkLeave + walkMs
  const routes = trip ? trip.parts.flatMap((p) => (p.kind === 'bus' ? [p.route] : [])).join(' → ') : ''
  let delta: { text: string; tone: 'success' | 'accent' | 'danger' } | null = null
  if (trip && arriveAt !== null && trip.late) delta = { text: `${Math.ceil((trip.arrive - arriveAt) / 60000)} min late`, tone: 'danger' }
  else if (trip && arriveAt !== null) {
    const d = Math.round((trip.leave - walkLeave) / 60000)
    delta = Math.abs(d) < 1 ? { text: 'leave when you would walk', tone: 'accent' } : d > 0 ? { text: `leave ${d} min later`, tone: 'success' } : { text: `leave ${-d} min earlier`, tone: 'accent' }
  } else if (trip) {
    const d = Math.round((trip.arrive - walkArrive) / 60000)
    delta = Math.abs(d) < 1 ? { text: 'same time as walking', tone: 'accent' } : d > 0 ? { text: `${d} min later than walking`, tone: 'accent' } : { text: `${-d} min sooner`, tone: 'success' }
  }
  return (
    <div className="modes" role="radiogroup" aria-label="Walk or take the bus">
      <button type="button" role="radio" aria-checked={mode === 'walk'} className="mode" onClick={() => onMode('walk')}>
        <span className="steps__icon" data-kind={0}>
          <Icon name="walk" size={16} />
        </span>
        <span className="mode__main">
          <strong>Walk · {formatDuration(plan.seconds)}</strong>
          <small className="tabular">
            {arriveAt !== null || walkLeave > now ? `Leave by ${clockAt(walkLeave)} · ` : 'Leave now · '}arrive {clockAt(walkArrive)}
          </small>
        </span>
      </button>
      <button type="button" role="radio" aria-checked={mode === 'bus'} className="mode" disabled={!trip} onClick={() => onMode('bus')}>
        <span className="steps__icon steps__icon--bus">
          <Icon name="transit" size={16} />
        </span>
        <span className="mode__main">
          <strong>Bus{routes ? ` · Route ${routes}` : ''}{trip ? ` · ${formatDuration((trip.arrive - trip.leave) / 1000)}` : ''}</strong>
          <small className="tabular">{loading ? 'Finding buses…' : trip ? `Leave by ${clockAt(trip.leave)} · arrive ${clockAt(trip.arrive)}` : 'No bus saves you walking on this trip right now'}</small>
          {delta && <StatusPill tone={delta.tone}>{delta.text}</StatusPill>}
        </span>
      </button>
    </div>
  )
}

/** "Leave by" for a class: when to set off on foot to make it. */
function ArriveBy({ plan, at, label, now }: { plan: Plan; at: number; label: string; now: number }) {
  const [mode, setMode] = useState<'arrive' | 'now'>('arrive')
  const walkMs = plan.seconds * 1000
  const leaveBy = at - walkMs
  const lateMin = Math.ceil((now + walkMs - at) / 60000)
  return (
    <section className="arrive arrive--plan" aria-label="When to leave">
      <GlassSegmentedControl<'arrive' | 'now'>
        label="Plan for"
        value={mode}
        onChange={setMode}
        options={[
          { value: 'arrive', label: `Arrive by ${clockAt(at)}` },
          { value: 'now', label: 'Leave now' },
        ]}
      />
      {mode === 'arrive' ? (
        lateMin > 0 ? (
          <p className="arrive__note">
            Leave now: walking gets you there about {lateMin} min late. <StatusPill tone="danger">Late</StatusPill>
          </p>
        ) : (
          <p className="arrive__note">
            Leave by {clockAt(leaveBy)} · Arrive around {clockAt(at)} {at - (now + walkMs) < 5 * 60000 ? <StatusPill tone="warning">Tight</StatusPill> : <StatusPill tone="success">On time</StatusPill>}
          </p>
        )
      ) : (
        <p className="arrive__note">
          Leave now · Arrive around {clockAt(now + walkMs)} for {label} at {clockAt(at)}
        </p>
      )}
    </section>
  )
}
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

/** "Paths and roads, 70 m of stairs": what the walk is like, for the folded section. */
function footSummary(plan: Plan): string {
  const by = [0, 0, 0, 0]
  for (const s of plan.route.steps) by[s.kind] += s.meters
  const level = by[0] + by[2] + by[3]
  const ways = [by[0] + by[3] >= level * 0.2 && 'paths', by[2] >= level * 0.2 && 'roads'].filter(Boolean).join(' and ') || 'paths'
  return `${ways[0].toUpperCase()}${ways.slice(1)}, ${by[1] >= 5 ? `${formatDistance(by[1])} of stairs` : 'no stairs'}`
}

function OnFoot({ plan }: { plan: Plan }) {
  const [open, toggle] = useFold('foot', false)
  return (
    <GlassDisclosure title="On foot" icon="walk" open={open} onToggle={toggle} summary={footSummary(plan)}>
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
    </GlassDisclosure>
  )
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
  toRoom,
  arriveBy,
  now = Date.now(),
  vehicles = [],
  live,
  following = null,
  trips = null,
  tripsLoading = false,
  tripIndex = 0,
  onTrip = () => {},
  picking = null,
  onPickOnMap = () => {},
  onPickAddress = () => {},
  homePlace = null,
  mode = 'walk',
  onMode = () => {},
}: {
  /** walk, or ride one of the bus trips: the map draws whichever is chosen */
  mode?: Mode
  onMode?: (m: Mode) => void
  /** the dorm or apartment saved as home, offered first when choosing a place */
  homePlace?: Place | null
  /** set while the trip starts from the walker's live location */
  following?: { finding: boolean; arrived: string | null } | null
  trips?: TripOption[] | null
  tripsLoading?: boolean
  tripIndex?: number
  onTrip?: (i: number) => void
  picking?: 'from' | 'to' | null
  onPickOnMap?: (field: 'from' | 'to') => void
  onPickAddress?: (field: 'from' | 'to', a: Address) => void
  vehicles?: Vehicle[]
  live?: LiveState
  arriveBy?: { at: number; label: string } | null
  now?: number
  toRoom?: Place | null
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
  const [addresses, setAddresses] = useState<Address[] | null>(null)
  const [addressError, setAddressError] = useState<string | null>(null)
  const findAddresses = async () => {
    setAddressError(null)
    try {
      const found = await searchAddresses(q)
      setAddresses(found)
      if (!found.length) setAddressError('No address found in the Santa Cruz area.')
    } catch {
      setAddressError('Address search is unavailable right now.')
    }
  }
  // the bus trip is shown when chosen, and always when there is no walking route
  const busView = !editing && (mode === 'bus' || !plan)
  const showTrips = busView && !!trips?.length
  const lastWalk = trips?.[tripIndex]?.parts.at(-1)

  const choose = (p: Place) => {
    const v = { id: p.id, name: p.name }
    if (editing === 'from') onPickFrom(v)
    else onPickTo(v)
    setEditing(null)
    setQ('')
  }

  return (
    <section aria-label="Directions" className="directions" ref={inputRef}>
      <div className="detail__head">
        <GlassIconButton icon="back" label="Close directions" onClick={onClose} />
        <h1 className="detail__title" style={{ flex: 1 }}>
          Directions
        </h1>
      </div>
      {arriveBy && plan && !editing && !busView && <ArriveBy plan={plan} at={arriveBy.at} label={arriveBy.label} now={now} />}
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
          <div className="audit__row" style={{ margin: '4px 0 6px' }}>
            <GlassButton size="s" icon="pin" aria-pressed={picking === editing} onClick={() => (onPickOnMap(editing), setEditing(null))}>
              Pick on the map
            </GlassButton>
            {q.trim().length >= 3 && (
              <GlassButton size="s" icon="search" onClick={findAddresses}>
                Search addresses for “{q.trim()}”
              </GlassButton>
            )}
          </div>
          {homePlace && !q.trim() && (
            <GlassList label="Home">
              <GlassListRow icon="home" iconColor={CATEGORY_COLOR.housing} title="Home" subtitle={homePlace.name} onClick={() => choose(homePlace)} />
            </GlassList>
          )}
          {addresses && addresses.length > 0 && (
            <ul className="glist" role="listbox" aria-label="Addresses">
              {addresses.map((a) => (
                <li key={`${a.lat},${a.lon}`}>
                  <button className="roompicker__row" role="option" aria-selected="false" onClick={() => (onPickAddress(editing, a), setEditing(null), setQ(''), setAddresses(null))}>
                    <Icon name="pin" size={15} />
                    <span>{a.label}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
          {addressError && <p className="note">{addressError}</p>}
          <PlaceRows places={suggestions} onPick={choose} label={`Choose ${editing === 'from' ? 'starting point' : 'destination'}`} empty="No campus place matches. Search addresses for somewhere off campus." />
          {q.trim().length >= 3 && <p className="note">Address search sends what you typed to Photon, an OpenStreetMap geocoder. Campus places are searched on this device.</p>}
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
          {following?.arrived && (
            <GlassBanner tone="success" title={`You've arrived at ${following.arrived}`}>
              {toRoom?.room ? 'Check the room number by the door.' : 'Enjoy your class.'}
            </GlassBanner>
          )}
          {following?.finding && (
            <p className="note" role="status">
              Finding your location…
            </p>
          )}
          {picking && <GlassBanner title="Tap the map">Tap where the trip {picking === 'from' ? 'starts' : 'ends'}.</GlassBanner>}
          {tripsLoading && !plan && <p className="note" role="status">Finding buses…</p>}
          {plan && <ModeCompare plan={plan} trip={trips?.[mode === 'bus' ? tripIndex : 0] ?? null} loading={tripsLoading} mode={mode} onMode={onMode} now={now} arriveAt={arriveBy?.at ?? null} />}
          {showTrips && trips && <TripList trips={trips} index={tripIndex} onIndex={onTrip} deadline={arriveBy?.at ?? null} now={now} vehicles={vehicles} live={live} />}
          {showTrips && plan && toRoom?.room && lastWalk?.kind === 'walk' && lastWalk.plan && <Arrival room={toRoom} end={lastWalk.plan.destPoint} />}
          {error && !showTrips && !tripsLoading && (
            <GlassBanner tone={error === 'same-place' ? 'accent' : 'warning'} title={error === 'same-place' ? undefined : 'No walking route'}>
              {ERROR_TEXT[error]}
              {straightMeters != null && error !== 'same-place' && <> Straight-line distance: {formatDistance(straightMeters)}.</>}
            </GlassBanner>
          )}
          {plan && !busView && (
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
              <OnFoot plan={plan} />
              {toRoom?.room && <Arrival room={toRoom} end={plan.destPoint} />}
            </>
          )}
        </>
      )}
    </section>
  )
}
