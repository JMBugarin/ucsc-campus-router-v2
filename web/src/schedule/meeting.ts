import { DAY_CODES, clockFromHhmm, isRealDate } from './time'

/**
 * One weekly class meeting, or a one-off event when `days` is empty. Days are 0 = Monday, times 24-hour
 * `HH:MM`, dates `YYYY-MM-DD`, all Pacific. Field names match the phone app's saved schedule.
 */
export interface Meeting {
  course: string
  title: string
  section: string
  component: string
  class_nbr: string
  days: number[]
  start: string
  end: string
  location: string
  start_date: string
  end_date: string
  skip_dates?: string[]
}

export class ScheduleError extends Error {}

export const MAX_MEETINGS = 60
export const MAX_SKIP_DATES = 60
export const MAX_PASTED_CHARS = 100_000

export const meetingLabel = (m: Pick<Meeting, 'course' | 'component'>) => [m.course, m.component].filter(Boolean).join(' ')
export const whenLabel = (m: Meeting) => (m.days.length ? m.days.map((d) => DAY_CODES[d]).join('') : m.start_date)
export const timeLabel = (m: Pick<Meeting, 'start' | 'end'>) => `${clockFromHhmm(m.start)}–${clockFromHhmm(m.end)}`

const sameDays = (a: number[], b: number[]) => a.length === b.length && a.every((d, i) => d === b[i])

/** True if both are the same class, so importing a schedule twice adds nothing. */
export const sameClass = (a: Meeting, b: Meeting) =>
  a.course === b.course && a.component === b.component && a.section === b.section && sameDays(a.days, b.days) && a.start === b.start && a.end === b.end && a.location === b.location && a.start_date === b.start_date

export const skips = (m: Meeting, iso: string) => (m.skip_dates ?? []).includes(iso)

/** This class not meeting on `iso` either; past dates are dropped. Null when no room is left for another. */
export function skipping(m: Meeting, iso: string, today: string): Meeting | null {
  const dates = [...new Set([...(m.skip_dates ?? []).filter((d) => d >= today), iso])].sort()
  if (dates.length > MAX_SKIP_DATES) return null
  return { ...m, skip_dates: dates }
}

/** This class meeting on `iso` after all. */
export function meetingOn(m: Meeting, iso: string): Meeting {
  const dates = (m.skip_dates ?? []).filter((d) => d !== iso)
  const out: Meeting = { ...m, skip_dates: dates }
  if (!dates.length) delete out.skip_dates
  return out
}

function text(raw: Record<string, unknown>, key: string, maxLen: number, required = false): string {
  const value = raw[key] ?? ''
  if (typeof value !== 'string' && !(typeof value === 'number' && Number.isInteger(value))) throw new ScheduleError(`${key} must be text`)
  const t = String(value).split(/\s+/).filter(Boolean).join(' ')
  if (required && !t) throw new ScheduleError(`${key} is required`)
  if (t.length > maxLen) throw new ScheduleError(`${key} is too long`)
  return t
}

function clock(value: unknown, key: string): string {
  const m = typeof value === 'string' ? /^(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(value) : null
  if (m && +m[1] < 24 && +m[2] < 60 && +(m[3] ?? '0') < 60) return `${m[1]}:${m[2]}`
  throw new ScheduleError(`${key} must look like 14:40`)
}

function day(value: unknown, key: string): string {
  if (typeof value === 'string' && isRealDate(value)) return value
  throw new ScheduleError(`${key} must look like 2026-09-24`)
}

/** Checks one meeting and returns a tidy copy, or throws a ScheduleError whose message is safe to show. */
export function cleanMeeting(raw: Record<string, unknown>): Meeting {
  const days = raw.days ?? []
  if (!Array.isArray(days) || !days.every((d) => Number.isInteger(d) && d >= 0 && d <= 6)) throw new ScheduleError('days must be a list of weekday numbers, 0 (Monday) to 6 (Sunday)')
  const skip = raw.skip_dates ?? []
  if (!Array.isArray(skip) || skip.length > MAX_SKIP_DATES) throw new ScheduleError(`skip_dates must be a list of at most ${MAX_SKIP_DATES} dates`)
  const course = text(raw, 'course', 40, true)
  const title = text(raw, 'title', 80)
  const section = text(raw, 'section', 10)
  const component = text(raw, 'component', 30)
  const classNbr = text(raw, 'class_nbr', 10)
  const sortedDays = [...new Set(days as number[])].sort((a, b) => a - b)
  const start = clock(raw.start, 'start')
  const end = clock(raw.end, 'end')
  const location = text(raw, 'location', 80)
  const startDate = day(raw.start_date, 'start_date')
  const endDate = day(raw.end_date, 'end_date')
  const skipDates = [...new Set(skip.map((d) => day(d, 'skip_dates')))].sort()
  if (end <= start) throw new ScheduleError(`${course}: the end time must be after the start time`)
  if (endDate < startDate) throw new ScheduleError(`${course}: the end date is before the start date`)
  if (!sortedDays.length && startDate !== endDate) throw new ScheduleError(`${course}: pick the days it meets, or use one date for a one-off event`)
  const m: Meeting = { course, title, section, component, class_nbr: classNbr, days: sortedDays, start, end, location, start_date: startDate, end_date: endDate }
  if (skipDates.length) m.skip_dates = skipDates
  return m
}

export function cleanSchedule(meetings: unknown[]): Meeting[] {
  if (meetings.length > MAX_MEETINGS) throw new ScheduleError(`too many meetings (the limit is ${MAX_MEETINGS})`)
  return meetings.map((m) => cleanMeeting(m as Record<string, unknown>))
}
