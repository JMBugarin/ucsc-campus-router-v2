import { GlassBanner, GlassButton, GlassIconButton, StatusPill } from '../../design/components'
import { Icon } from '../../design/icons'
import type { Place } from '../../data/types'
import { floorName } from '../../data/rooms'
import type { ClassesData } from '../../schedule/data'
import { placeFor } from '../../schedule/data'
import { breakBefore, daySummary, departure, label, planDay, transitions, type Occurrence, type Status, type Walk } from '../../schedule/dayPlan'
import type { Meeting } from '../../schedule/meeting'
import { addDays, clockAt, dayLabel, durationText, pacificDate } from '../../schedule/time'

const STATUS_TONE: Record<Status, 'success' | 'warning' | 'danger' | 'accent'> = { ok: 'success', tight: 'warning', late: 'danger', unknown: 'accent' }
const FROM_TEXT = { here: 'from here', current_class: 'from this class', previous_class: 'from your last class' }

export function Today({
  meetings,
  data,
  byId,
  now,
  day,
  walk,
  hasLocation,
  onDay,
  onOpen,
  onGetThere,
  onSchedule,
}: {
  meetings: Meeting[]
  data: ClassesData
  byId: Map<string, Place>
  now: number
  day: string | null
  walk: Walk
  hasLocation: boolean
  onDay: (day: string | null) => void
  onOpen: (p: Place) => void
  onGetThere: (o: Occurrence, place: Place) => void
  onSchedule: () => void
}) {
  const today = pacificDate(now)
  const viewing = day && day !== today ? day : null
  const plan = planDay(meetings, now, data.holidays, viewing)
  const trips = transitions(plan, walk)
  const leave = departure(plan, now, walk, hasLocation)
  const shownDay = plan.day
  const place = (o: Occurrence) => placeFor(o.meeting.location, data.campus, byId)

  return (
    <section className="today" aria-label="Today">
      <div className="today__head">
        <GlassIconButton icon="back" label="Previous day" size="s" onClick={() => onDay(addDays(shownDay, -1))} />
        <div className="today__title">
          <h1 className="detail__title">{plan.isToday ? 'Today' : dayLabel(shownDay)}</h1>
          <div className="detail__sub">{plan.isToday ? dayLabel(shownDay) : <button className="linkbtn" onClick={() => onDay(null)}>Back to today</button>}</div>
        </div>
        <GlassIconButton icon="chevron" label="Next day" size="s" onClick={() => onDay(addDays(shownDay, 1))} />
      </div>

      {!meetings.length ? (
        <GlassBanner title="Add your classes" action={<GlassButton size="s" variant="primary" onClick={onSchedule}>Add</GlassButton>}>
          Paste your schedule from MyUCSC or add classes by hand. They stay in this browser.
        </GlassBanner>
      ) : (
        <p className="today__summary" aria-live="polite">
          {daySummary(plan, now)}
        </p>
      )}

      {leave && plan.next && (
        <div className="leave" data-status={leave.status}>
          <div className="leave__time">
            <span>Leave by {clockAt(leave.leaveBy)}</span>
            <StatusPill tone={STATUS_TONE[leave.status]}>{leave.status === 'late' ? `${Math.ceil(-leave.freeMin)} min late` : leave.status === 'tight' ? 'Tight' : 'On time'}</StatusPill>
          </div>
          <div className="leave__meta">
            {label(plan.next)} at {clockAt(plan.next.start)} · {leave.walkMin} min walk {FROM_TEXT[leave.from]}
          </div>
          {place(plan.next) && (
            <GlassButton variant="primary" icon="route" onClick={() => onGetThere(plan.next!, place(plan.next!)!)}>
              Get me there
            </GlassButton>
          )}
        </div>
      )}

      <ol className="classes">
        {plan.classes.map((o, i) => {
          const p = place(o)
          const isNow = plan.current === o
          const isNext = plan.next === o
          const gap = breakBefore(plan, i)
          const t = trips[i]
          const past = plan.isToday && o.end <= now
          return (
            <li key={`${o.start}-${o.meeting.course}-${o.meeting.component}`}>
              {gap !== null && (
                <div className="classes__gap" data-status={t?.status ?? 'unknown'}>
                  {durationText(gap)} break{t ? ` · ${t.walkMin} min walk` : ''}
                  {t?.status === 'late' && ' · not enough time'}
                  {t?.status === 'tight' && ' · tight'}
                </div>
              )}
              <article className="classcard" data-now={isNow} data-past={past} aria-label={`${label(o)} at ${clockAt(o.start)}`}>
                <div className="classcard__time tabular">
                  {clockAt(o.start)}
                  <small>{clockAt(o.end)}</small>
                </div>
                <div className="classcard__main">
                  <div className="classcard__title">
                    {label(o)}
                    {isNow && <StatusPill tone="success">Now</StatusPill>}
                    {isNext && !isNow && <StatusPill tone="accent">Next</StatusPill>}
                  </div>
                  {o.meeting.title && <div className="classcard__sub">{o.meeting.title}</div>}
                  {p ? (
                    <button className="classcard__room" onClick={() => onOpen(p)}>
                      <Icon name={p.kind === 'room' ? 'door' : 'academic'} size={14} />
                      <span>
                        {p.name}
                        {p.room?.floor ? ` · ${floorName(p.room.floor.label)}` : ''}
                      </span>
                    </button>
                  ) : (
                    <div className="classcard__sub">{o.meeting.location || 'No room'}</div>
                  )}
                </div>
                {p && !past && <GlassIconButton icon="route" label={`Get me to ${label(o)}`} onClick={() => onGetThere(o, p)} />}
              </article>
            </li>
          )
        })}
      </ol>
      {plan.isToday && !hasLocation && meetings.length > 0 && <p className="note">Turn on your location on the map for leave-by times from where you are.</p>}
    </section>
  )
}
