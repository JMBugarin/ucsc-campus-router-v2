import { GlassBanner, SectionLabel, StatusPill } from '../design/components'
import { Icon } from '../design/icons'
import { clockAt } from '../schedule/time'
import type { TripOption } from '../transit/trip'
import { useServiceDepartures } from '../transit/useServiceDepartures'
import { freshPredictions } from '../transit/serviceState'
import { OCCUPANCY_TEXT, recent, type Vehicle } from '../transit/liveClient'
import type { LiveState } from '../transit/useTransit'

const mins = (s: number) => Math.max(1, Math.round(s / 60))

/** Bus trips to or from somewhere off campus: when to leave, each leg, and what the live feeds say about each bus. */
export function TripList({ trips, index, onIndex, deadline, now, vehicles, live }: { trips: TripOption[]; index: number; onIndex: (i: number) => void; deadline: number | null; now: number; vehicles: Vehicle[]; live?: LiveState }) {
  const trip = trips[Math.min(index, trips.length - 1)]
  const boards = trip ? trip.parts.flatMap((p) => (p.kind === 'bus' ? [p.boardStop] : [])) : []
  const service = useServiceDepartures(boards)
  const predictions = freshPredictions(service.value)
  if (!trip) return null
  const nowSecs = Math.floor(now / 1000)
  const routes = trip.parts.flatMap((p) => (p.kind === 'bus' ? [p.route] : []))
  const stops = trip.parts.flatMap((p) => (p.kind === 'bus' ? [p.boardStop, p.alightStop] : []))
  const alerts = (live?.alerts ?? []).filter((a) => (!a.routes.length && !a.stops.length) || a.routes.some((r) => routes.includes(r)) || a.stops.some((s) => stops.includes(s)))
  return (
    <section className="trips" aria-label="Trips by bus">
      <SectionLabel>By bus</SectionLabel>
      <div className="trips__options" role="radiogroup" aria-label="Trip options">
        {trips.map((t, i) => {
          const late = deadline !== null && t.arrive > deadline
          return (
            <button key={t.leave + '-' + i} role="radio" aria-checked={i === index} className="trips__option" onClick={() => onIndex(i)}>
              <strong>Leave by {clockAt(t.leave)}</strong>
              <span>
                Arrive around {clockAt(t.arrive)} · {t.parts.filter((p) => p.kind === 'bus').map((p) => (p.kind === 'bus' ? p.route : '')).join(' → ')}
                {t.transfers > 0 ? ` · ${t.transfers} transfer${t.transfers > 1 ? 's' : ''}` : ''}
              </span>
              {late && <StatusPill tone="danger">Late</StatusPill>}
            </button>
          )
        })}
      </div>
      {alerts.map((a, i) => (
        <GlassBanner key={i} tone="warning" title={a.header || 'Service alert'}>
          {a.text}
        </GlassBanner>
      ))}
      <ol className="steps">
        {trip.parts.map((p, i) => {
          if (p.kind === 'walk') {
            if (p.seconds < 30) return null
            return (
              <li key={i}>
                <span className="steps__icon" data-kind={0}>
                  <Icon name="walk" size={16} />
                </span>
                <span className="steps__main">
                  Walk {mins(p.seconds)} min to {p.toName}
                  <small>{p.approximate ? 'Estimated: no mapped path here, so follow streets and sidewalks.' : 'Along the mapped campus paths.'}</small>
                </span>
              </li>
            )
          }
          const pred = predictions.find((x) => x.trip === p.tripId && x.stop === p.boardStop)
          const delay = pred ? pred.time - Math.floor(p.departs / 1000) : null
          const v = vehicles.find((x) => x.trip === p.tripId && recent(x, nowSecs))
          const when = delay === null ? 'Scheduled' : Math.abs(delay) < 60 ? 'Live: on time' : delay > 0 ? `Live: ${Math.round(delay / 60)} min late` : `Live: ${Math.round(-delay / 60)} min early`
          return (
            <li key={i}>
              <span className="steps__icon steps__icon--bus">
                <Icon name="transit" size={16} />
              </span>
              <span className="steps__main">
                Route {p.route} toward {p.headsign} from {p.boardName} at {clockAt(p.departs + (delay ?? 0) * 1000)}
                <small>
                  Get off at {p.alightName} around {clockAt(p.arrives + (delay ?? 0) * 1000)}. {when}.
                  {v && ` Bus ${v.label || v.id} is on the map${v.occupancy ? `: ${OCCUPANCY_TEXT[v.occupancy].toLowerCase()}` : ''}.`}
                </small>
              </span>
            </li>
          )
        })}
      </ol>
      <p className="note">Times come from METRO's schedule, with live predictions where the transit service has them. Walks off campus are estimates.</p>
    </section>
  )
}
