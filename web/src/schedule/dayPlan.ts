import { meetingLabel, type Meeting } from './meeting'
import { WEEKDAYS, addDays, clockAt, durationText, isoWithOffset, pacificDate, pacificInstant, weekdayOf } from './time'

export const SEARCH_DAYS = 21
export const TIGHT_MIN = 5

export interface Occurrence {
  start: number
  end: number
  meeting: Meeting
}
export type DayState = 'in_class' | 'before_classes' | 'between_classes' | 'done_for_today' | 'no_classes_today'
export type Reason = 'no_schedule' | 'holiday' | 'before_term' | 'after_term' | 'weekend' | 'no_classes'

export function occursOn(m: Meeting, iso: string, holidays: Set<string>): boolean {
  if (iso < m.start_date || iso > m.end_date) return false
  if ((m.skip_dates ?? []).includes(iso)) return false
  if (!m.days.length) return iso === m.start_date
  return !holidays.has(iso) && m.days.includes(weekdayOf(iso))
}

export function occurrences(meetings: Meeting[], iso: string, holidays: Set<string>): Occurrence[] {
  return meetings
    .filter((m) => occursOn(m, iso, holidays))
    .map((m) => ({ start: pacificInstant(iso, m.start), end: pacificInstant(iso, m.end), meeting: m }))
    .sort((a, b) => a.start - b.start || a.end - b.end)
}

/** The first class that starts after `now`, today or within the next three weeks. */
export function nextOccurrence(meetings: Meeting[], now: number, holidays: Set<string>): Occurrence | null {
  if (!meetings.length) return null
  const first = meetings.map((m) => m.start_date).reduce((a, b) => (a < b ? a : b))
  const today = pacificDate(now)
  const base = today >= first ? today : first
  for (let offset = 0; offset <= SEARCH_DAYS; offset++) {
    for (const o of occurrences(meetings, addDays(base, offset), holidays)) if (o.start > now) return o
  }
  return null
}

export function whyNoClasses(meetings: Meeting[], iso: string, holidays: Set<string>): Reason {
  if (!meetings.length) return 'no_schedule'
  const first = meetings.map((m) => m.start_date).reduce((a, b) => (a < b ? a : b))
  const last = meetings.map((m) => m.end_date).reduce((a, b) => (a > b ? a : b))
  if (holidays.has(iso)) return 'holiday'
  if (iso < first) return 'before_term'
  if (iso > last) return 'after_term'
  if (weekdayOf(iso) >= 5) return 'weekend'
  return 'no_classes'
}

export interface DayPlan {
  day: string
  isToday: boolean
  state: DayState
  classes: Occurrence[]
  reason: Reason | null
  current: Occurrence | null
  /** for today, the next class to start, maybe on a later day */
  next: Occurrence | null
}

/** Where a day stands. `viewDay` shows another day, which has no "now" or "next". */
export function planDay(meetings: Meeting[], now: number, holidays: Set<string>, viewDay?: string | null): DayPlan {
  if (viewDay) {
    const classes = occurrences(meetings, viewDay, holidays)
    return { day: viewDay, isToday: false, state: classes.length ? 'before_classes' : 'no_classes_today', classes, reason: classes.length ? null : whyNoClasses(meetings, viewDay, holidays), current: null, next: null }
  }
  const day = pacificDate(now)
  const today = occurrences(meetings, day, holidays)
  const current = today.find((o) => o.start <= now && now < o.end) ?? null
  const previousEnded = today.some((o) => o.end <= now)
  const upcoming = today.filter((o) => o.start > now)
  const next = upcoming[0] ?? nextOccurrence(meetings, now, holidays)
  const state: DayState = current ? 'in_class' : upcoming.length ? (previousEnded ? 'between_classes' : 'before_classes') : today.length ? 'done_for_today' : 'no_classes_today'
  return { day, isToday: true, state, classes: today, reason: today.length ? null : whyNoClasses(meetings, day, holidays), current, next }
}

/** Minutes between the class before `index` and its start. */
export const breakBefore = (plan: DayPlan, index: number) => (index <= 0 ? null : (plan.classes[index].start - plan.classes[index - 1].end) / 60000)

// ---- getting there ---------------------------------------------------------------------------------------

/** Walking minutes to a class location, from the student's own position (`from` null) or another location. */
export type Walk = (from: string | null, to: string) => number | null
export type Status = 'ok' | 'tight' | 'late' | 'unknown'

export const statusFor = (free: number | null): Status => (free === null ? 'unknown' : free < 0 ? 'late' : free < TIGHT_MIN ? 'tight' : 'ok')

export interface Transition {
  walkMin: number
  freeMin: number
  status: Status
}

/** The walk between each pair of back-to-back classes today, where both rooms can be walked. */
export function transitions(plan: DayPlan, walk: Walk): (Transition | null)[] {
  return plan.classes.map((o, i) => {
    if (i === 0) return null
    const prev = plan.classes[i - 1]
    const w = walk(prev.meeting.location, o.meeting.location)
    if (w === null) return null
    const free = (o.start - prev.end) / 60000 - w
    return { walkMin: w, freeMin: free, status: statusFor(free) }
  })
}

export interface Departure {
  walkMin: number
  /** `here`, `current_class` or `previous_class` */
  from: 'here' | 'current_class' | 'previous_class'
  freeMin: number
  status: Status
  leaveBy: number
}

/** When to leave for today's next class, and from where: the current class, else here, else the class before. */
export function departure(plan: DayPlan, now: number, walk: Walk, here: boolean): Departure | null {
  const next = plan.next
  if (!plan.isToday || !next || pacificDate(next.start) !== plan.day) return null
  const before = plan.classes.filter((o) => o.end <= now).at(-1)
  let from: Departure['from'] | null = null
  let w: number | null = null
  let readyAt = now
  if (plan.current) {
    from = 'current_class'
    w = walk(plan.current.meeting.location, next.meeting.location)
    readyAt = plan.current.end
  } else if (here) {
    from = 'here'
    w = walk(null, next.meeting.location)
  } else if (before) {
    from = 'previous_class'
    w = walk(before.meeting.location, next.meeting.location)
  }
  if (from === null || w === null) return null
  const free = (next.start - readyAt) / 60000 - w
  return { walkMin: w, from, freeMin: free, status: statusFor(free), leaveBy: next.start - w * 60000 }
}

// ---- words ---------------------------------------------------------------------------------------------------

const NO_CLASSES: Record<Reason, string> = {
  weekend: 'No classes on weekends.',
  holiday: 'No classes today (holiday).',
  before_term: "The term hasn't started yet.",
  after_term: 'The term is over.',
  no_schedule: 'Add your classes to see what is next.',
  no_classes: 'No classes today.',
}
const NO_CLASSES_OTHER: Record<Reason, string> = {
  weekend: 'No classes: weekend.',
  holiday: 'No classes: holiday.',
  before_term: 'The term has not started.',
  after_term: 'The term is over.',
  no_schedule: 'No classes yet.',
  no_classes: 'No classes.',
}
export const noClassesOtherDay = (r: Reason | null) => NO_CLASSES_OTHER[r ?? 'no_classes']
export const label = (o: Occurrence) => meetingLabel(o.meeting)

/** `XYZ 10 Lecture at 2:40 PM in 40 min`, or for a later day `Tue 9:50 AM, XYZ 10 Lecture`. */
export function nextClassText(next: Occurrence, now: number): string {
  if (pacificDate(next.start) === pacificDate(now)) return `${label(next)} at ${clockAt(next.start)} in ${durationText((next.start - now) / 60000)}`
  return `${WEEKDAYS[weekdayOf(pacificDate(next.start))]} ${clockAt(next.start)}, ${label(next)}`
}

export function daySummary(plan: DayPlan, now: number): string {
  if (!plan.isToday) {
    if (!plan.classes.length) return noClassesOtherDay(plan.reason)
    const n = plan.classes.length
    return `${n} ${n === 1 ? 'class' : 'classes'}, ${clockAt(plan.classes[0].start)} to ${clockAt(plan.classes[n - 1].end)}.`
  }
  const next = plan.next
  switch (plan.state) {
    case 'in_class': {
      const c = plan.current!
      const head = `In ${label(c)} until ${clockAt(c.end)} (${durationText((c.end - now) / 60000)} left).`
      return next ? `${head} Next: ${nextClassText(next, now)}.` : head
    }
    case 'before_classes':
    case 'between_classes':
      return next ? `Next: ${nextClassText(next, now)}.` : 'No more classes today.'
    case 'done_for_today':
      return next ? `Done for today. Next class: ${nextClassText(next, now)}.` : 'Done for today.'
    default: {
      const why = NO_CLASSES[plan.reason ?? 'no_classes']
      return next ? `${why} Next class: ${nextClassText(next, now)}.` : why
    }
  }
}

export const occurrenceKey = (o: Occurrence) => `${isoWithOffset(o.start)}|${o.meeting.course}|${o.meeting.component}|${o.meeting.section}`
