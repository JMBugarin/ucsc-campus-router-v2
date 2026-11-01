import { useMemo } from 'react'
import { GlassBanner, SectionLabel } from '../design/components'
import { clockText, DAY_NAMES, upcoming, feedCovers, type Clock, type TransitData } from '../transit/schedule'
import { delayAt } from '../transit/realtime'
import type { LiveState } from '../transit/useTransit'

const minutes = (s: number) => Math.round(s / 60)

export function Departures({ data, stopIds, now, live }: { data: TransitData; stopIds: string[]; now: Clock; live: LiveState }) {
  const idx = useMemo(() => stopIds.flatMap((id) => data.stops.flatMap((s, i) => (s.id === id ? [i] : []))), [data, stopIds])
  const { list, today, day } = useMemo(() => upcoming(data, idx, now, 8), [data, idx, now])
  const covered = feedCovers(data, now)
  const alerts = live.alerts.filter((a) => a.stops.some((s) => stopIds.includes(s)) || a.routes.some((r) => list.some((d) => d.trip.r === r)))

  return (
    <section aria-label="Next buses" className="departures">
      <SectionLabel>Next buses</SectionLabel>
      {!covered && (
        <GlassBanner tone="warning" title="Schedule out of date">
          The bundled METRO schedule covers {data.feed.start.slice(4, 6)}/{data.feed.start.slice(6)} to {data.feed.end.slice(4, 6)}/{data.feed.end.slice(6)}. Check scmetro.org for current times.
        </GlassBanner>
      )}
      {alerts.slice(0, 2).map((a, i) => (
        <GlassBanner key={i} tone="warning" title={a.header || 'Service alert'}>
          {a.text}
        </GlassBanner>
      ))}
      {covered && !list.length && <p className="note">No scheduled buses in the next week.</p>}
      {!today && list.length > 0 && <p className="note">No more buses today. Next service: {DAY_NAMES[day.dow]} {day.date.slice(4, 6)}/{day.date.slice(6)}.</p>}
      <ul className="deps">
        {list.map((d, i) => {
          const stop = data.stops[d.stop]
          const upd = live.trips.get(d.trip.i)
          const seq = undefined
          const delay = live.status === 'live' ? delayAt(upd, stop.id, seq) : null
          const eta = d.secs + (delay ?? 0)
          const away = today ? minutes(eta - now.secs) : null
          return (
            <li key={d.trip.i + i}>
              <span className="route" aria-label={`Route ${d.trip.r}`}>{d.trip.r}</span>
              <span className="deps__main">
                {d.trip.h}
                <small>
                  {clockText(d.secs)}
                  {delay !== null && Math.abs(delay) >= 60 ? ` · ${delay > 0 ? `${minutes(delay)} min late` : `${minutes(-delay)} min early`}` : delay !== null ? ' · on time' : ' · scheduled'}
                </small>
              </span>
              <span className="deps__eta tabular">{away === null ? '' : away <= 0 ? 'Now' : `${away} min`}</span>
            </li>
          )
        })}
      </ul>
      <p className="note">
        {live.status === 'live'
          ? 'Live delays from METRO. Times in Pacific time.'
          : live.enabled && live.status === 'error'
            ? 'Live feed unavailable; showing the schedule.'
            : 'Scheduled times from METRO. Live tracking is not connected in this build.'}{' '}
        Campus shuttles (Loop, Upper Campus) are not listed: their live positions are only in UCSC's flexigo app.
      </p>
    </section>
  )
}
