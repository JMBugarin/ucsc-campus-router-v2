/** Campus clock: classes are on Pacific time whatever the viewer's device is set to. */
export const DAY_CODES = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
export const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
export const WEEKDAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

const parts = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/Los_Angeles',
  hourCycle: 'h23',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
})

export interface Wall {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second: number
}

/** The Pacific wall clock at an instant (ms since epoch). */
export function pacificWall(ms: number): Wall {
  const p = Object.fromEntries(parts.formatToParts(new Date(ms)).map((x) => [x.type, x.value]))
  return { year: +p.year, month: +p.month, day: +p.day, hour: +p.hour % 24, minute: +p.minute, second: +p.second }
}

const pad = (n: number, w = 2) => String(n).padStart(w, '0')
export const isoOf = (w: { year: number; month: number; day: number }) => `${pad(w.year, 4)}-${pad(w.month)}-${pad(w.day)}`

/** `YYYY-MM-DD` of the Pacific day holding the instant. */
export const pacificDate = (ms: number) => isoOf(pacificWall(ms))

/** The instant a Pacific wall-clock time happens. */
export function pacificInstant(iso: string, hhmm: string): number {
  const [y, mo, d] = iso.split('-').map(Number)
  const [h, mi] = hhmm.split(':').map(Number)
  const target = Date.UTC(y, mo - 1, d, h, mi)
  let guess = target + 8 * 3600_000
  for (let i = 0; i < 3; i++) {
    const w = pacificWall(guess)
    const seen = Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second)
    const diff = target - seen
    if (diff === 0) break
    guess += diff
  }
  return guess
}

/** Minutes east of UTC at an instant: -420 for PDT. */
export function pacificOffset(ms: number): number {
  const w = pacificWall(ms)
  return Math.round((Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second) - Math.floor(ms / 1000) * 1000) / 60000)
}

/** `2026-10-12T14:40:00-07:00`. */
export function isoWithOffset(ms: number): string {
  const w = pacificWall(ms)
  const off = pacificOffset(ms)
  const a = Math.abs(off)
  return `${isoOf(w)}T${pad(w.hour)}:${pad(w.minute)}:${pad(w.second)}${off < 0 ? '-' : '+'}${pad(Math.floor(a / 60))}:${pad(a % 60)}`
}

/** 0 = Monday, for a `YYYY-MM-DD` date. */
export function weekdayOf(iso: string): number {
  const [y, m, d] = iso.split('-').map(Number)
  return (new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7
}

export function addDays(iso: string, n: number): string {
  const [y, m, d] = iso.split('-').map(Number)
  const t = new Date(Date.UTC(y, m - 1, d + n))
  return isoOf({ year: t.getUTCFullYear(), month: t.getUTCMonth() + 1, day: t.getUTCDate() })
}

export function isRealDate(iso: string): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso)
  if (!m) return false
  const t = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]))
  return +m[1] > 0 && t.getUTCFullYear() === +m[1] && t.getUTCMonth() === +m[2] - 1 && t.getUTCDate() === +m[3]
}

export function clock12(hour: number, minute: number): string {
  const h = hour % 12 === 0 ? 12 : hour % 12
  return `${h}:${pad(minute)} ${hour < 12 ? 'AM' : 'PM'}`
}

/** `14:40` as `2:40 PM`. */
export function clockFromHhmm(hhmm: string): string {
  const [h, m] = hhmm.split(':')
  if (m === undefined) return hhmm
  return clock12(parseInt(h, 10) || 0, parseInt(m, 10) || 0)
}

/** The Pacific clock time of an instant, as `2:40 PM`. */
export function clockAt(ms: number): string {
  const w = pacificWall(ms)
  return clock12(w.hour, w.minute)
}

/** `95` as `1 h 35 min`; under a minute as `less than a minute`. */
export function durationText(minutes: number): string {
  const total = Math.round(minutes)
  if (total < 1) return 'less than a minute'
  if (total < 60) return `${total} min`
  const h = Math.floor(total / 60)
  const m = total % 60
  return m === 0 ? `${h} h` : `${h} h ${m} min`
}

/** `Mon, Oct 12`. */
export function dayLabel(iso: string): string {
  const [, m, d] = iso.split('-').map(Number)
  return `${WEEKDAYS[weekdayOf(iso)]}, ${MONTHS[m - 1]} ${d}`
}

/** `Oct 12`. */
export function shortDayLabel(iso: string): string {
  const [, m, d] = iso.split('-').map(Number)
  return `${MONTHS[m - 1]} ${d}`
}
