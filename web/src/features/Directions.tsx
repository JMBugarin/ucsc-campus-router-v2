import { useMemo, useRef, useState } from 'react'
import { GlassBanner, GlassButton, GlassIconButton, GlassSearch, GlassSwitch, SectionLabel } from '../design/components'
import { Icon } from '../design/icons'
import { formatDistance, formatDuration, type Plan, type PlanError } from '../routing/plan'
import type { Place } from '../data/types'
import type { SearchIndex } from '../data/search'
import { PlaceRows } from './Browse'
import { clockText, pacificClock, type TransitData } from '../transit/schedule'
import { useServiceDepartures } from '../transit/useServiceDepartures'
import { freshPredictions, predictedDelay } from '../transit/serviceState'
import { OCCUPANCY_TEXT, recent, type Vehicle } from '../transit/liveClient'
import type { LiveState } from '../transit/useTransit'
import type { TripOption } from '../transit/trip'
import { TripList } from './TripList'
import { searchAddresses, type Address } from '../data/geocode'
import type { BusPlan } from '../transit/plan'
import { ACCESS_LABEL, checkedText, doorSentence, relation } from '../data/rooms'
import { GlassSegmentedControl, StatusPill } from '../design/components'
import { clockAt, pacificDate, pacificInstant } from '../schedule/time'

export type Pick = { id: string; name: string } | null

/** The direct buses, with live departure times, the bus itself and how full METRO says it is, when the service has them. */
function BusOptions({ bus, transit, now, vehicles, live }: { bus: BusPlan; transit: TransitData; now: number; vehicles: Vehicle[]; live?: LiveState }) {
  const stopIds = [...new Set(bus.options.map((o) => transit.stops[o.board].id))]
  const service = useServiceDepartures(stopIds)
  const predictions = freshPredictions(service.value)
  const clock = pacificClock(new Date(now))
  const nowSecs = Math.floor(now / 1000)
  const routes = bus.options.map((o) => o.route)
  const stops = bus.options.flatMap((o) => [transit.stops[o.board].id, transit.stops[o.alight].id])
  const alerts = (live?.alerts ?? []).filter((a) => (!a.routes.length && !a.stops.length) || a.routes.some((r) => routes.includes(r)) || a.stops.some((s) => stops.includes(s)))
  return (
    <>
      {alerts.map((a, i) => (
        <GlassBanner key={i} tone="warning" title={a.header || 'Service alert'}>
          {a.text}
        </GlassBanner>
      ))}
      <ul className="bus">
        {bus.options.map((o) => {
          const stop = transit.stops[o.board].id
          const delay = predictedDelay(predictions, o.tripId, stop, o.departs, clock.secs, nowSecs)
          const leaves = delay === null ? o.departs : o.departs + delay
          const v = vehicles.find((x) => x.trip === o.tripId && recent(x, nowSecs))
          const when = delay === null ? 'Scheduled' : Math.abs(delay) < 60 ? 'Live: on time' : delay > 0 ? `Live: ${Math.round(delay / 60)} min late` : `Live: ${Math.round(-delay / 60)} min early`
          return (
            <li key={o.tripId + o.departs}>
              <span className="route">{o.route}</span>
              <span className="bus__main">
                {transit.stops[o.board].name} {clockText(leaves)} to {transit.stops[o.alight].name}
                <small>
                  Walk {Math.max(1, Math.round(o.walkToStop / 60))} min to the stop, ride, walk {Math.max(1, Math.round(o.walkFromStop / 60))} min. {when}.
                  {v && ` Bus ${v.label || v.id} is on the map${v.occupancy ? `: ${OCCUPANCY_TEXT[v.occupancy].toLowerCase()}` : ''}.`}
                </small>
              </span>
              <span className="bus__eta tabular">{clockText(o.arrives + (delay ?? 0))}</span>
            </li>
          )
        })}
      </ul>
    </>
  )
}

/** "Leave by" for a class: when to set off to make it, on foot or by one of the buses that gets there in time. */
function ArriveBy({ plan, at, label, now, bus, transit }: { plan: Plan; at: number; label: string; now: number; bus?: BusPlan | null; transit?: TransitData | null }) {
  const [mode, setMode] = useState<'arrive' | 'now'>('arrive')
  const walkMs = plan.seconds * 1000
  const leaveBy = at - walkMs
  const lateMin = Math.ceil((now + walkMs - at) / 60000)
  const midnight = pacificInstant(pacificDate(now), '00:00')
  const deadline = (at - midnight) / 1000
  const buses = (bus?.options ?? []).filter((o) => o.arrives <= deadline && o.departs - o.walkToStop >= (now - midnight) / 1000)
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
      {mode === 'arrive' && transit && buses.length > 0 && (
        <p className="arrive__line">
          Or by bus: leave by {clockText(buses[0].departs - buses[0].walkToStop)}, take route {buses[0].route} from {transit.stops[buses[0].board].name} at {clockText(buses[0].departs)}, arrive around {clockText(buses[0].arrives)}. Scheduled time.
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
}: {
  /** set while the trip starts from the walker's live location */
  following?: { finding: boolean; rerouted: boolean; arrived: string | null; updated: number | null } | null
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
  const showTrips = !!trips?.length && !editing

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
      {arriveBy && plan && !editing && !showTrips && <ArriveBy plan={plan} at={arriveBy.at} label={arriveBy.label} now={now} bus={bus} transit={transit} />}
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
          {following && !following.arrived && (
            <p className="live-status" role="status" aria-live="polite">
              <StatusPill tone={following.finding ? 'warning' : 'success'}>{following.finding ? 'Finding you…' : 'Live'}</StatusPill>
              {following.finding ? 'Waiting for your location.' : following.rerouted ? 'Off the route, so it was redrawn from where you are.' : 'Following your location: the route updates as you move.'}
            </p>
          )}
          {picking && <GlassBanner title="Tap the map">Tap where the trip {picking === 'from' ? 'starts' : 'ends'}.</GlassBanner>}
          {tripsLoading && <p className="note" role="status">Finding buses…</p>}
          {showTrips && trips && <TripList trips={trips} index={tripIndex} onIndex={onTrip} deadline={arriveBy?.at ?? null} now={now} vehicles={vehicles} live={live} />}
          {showTrips && plan && <p className="note">Walking the whole way takes {formatDuration(plan.seconds)}.</p>}
          {error && !showTrips && !tripsLoading && (
            <GlassBanner tone={error === 'same-place' ? 'accent' : 'warning'} title={error === 'same-place' ? undefined : 'No walking route'}>
              {ERROR_TEXT[error]}
              {straightMeters != null && error !== 'same-place' && <> Straight-line distance: {formatDistance(straightMeters)}.</>}
            </GlassBanner>
          )}
          {plan && !showTrips && (
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
                    <BusOptions bus={bus} transit={transit} now={now} vehicles={vehicles} live={live} />
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
                {plan.connectorMeters > 5 && <> {formatDistance(plan.connectorMeters)} of the trip, between a door or point and the nearest mapped path, has no mapped path: it's drawn dotted and is approximate.</>}
              </p>
            </>
          )}
        </>
      )}
    </section>
  )
}
