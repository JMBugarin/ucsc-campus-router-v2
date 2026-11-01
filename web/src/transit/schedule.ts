export interface TransitData {
  attribution: string
  feed: { version: string; start: string; end: string }
  stops: { id: string; name: string; full: string; lat: number; lon: number }[]
  routes: Record<string, { n: string; c: string }>
  services: { d: number[]; a: string; z: string; add: string[]; del: string[] }[]
  trips: { i: string; r: string; h: string; s: number; t: [number, number][] }[]
}

export interface Clock {
  date: string // YYYYMMDD in Pacific time
  secs: number // seconds since local midnight
  dow: number // 0 = Monday
}

const fmt = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/Los_Angeles',
  hourCycle: 'h23',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  weekday: 'short',
})
const DOW = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

/** Campus time: stops and schedules are in Pacific time whatever the viewer's clock says. */
export function pacificClock(now: Date): Clock {
  const p = Object.fromEntries(fmt.formatToParts(now).map((x) => [x.type, x.value]))
  return { date: `${p.year}${p.month}${p.day}`, secs: +p.hour * 3600 + +p.minute * 60 + +p.second, dow: DOW.indexOf(p.weekday) }
}

export function shiftDay(c: Clock, n: number): Clock {
  const y = +c.date.slice(0, 4), m = +c.date.slice(4, 6) - 1, d = +c.date.slice(6, 8)
  const t = new Date(Date.UTC(y, m, d + n))
  const pad = (x: number) => String(x).padStart(2, '0')
  return { date: `${t.getUTCFullYear()}${pad(t.getUTCMonth() + 1)}${pad(t.getUTCDate())}`, secs: c.secs, dow: (((c.dow + n) % 7) + 7) % 7 }
}
export const previousDay = (c: Clock) => shiftDay(c, -1)

/** Departures from these stops: today's remaining ones, else the first day within a week that has any. */
export function upcoming(data: TransitData, stops: number[], now: Clock, limit = 8): { day: Clock; today: boolean; list: Departure[] } {
  const list = departures(data, stops, now, limit)
  if (list.length) return { day: now, today: true, list }
  for (let n = 1; n <= 7; n++) {
    const day = { ...shiftDay(now, n), secs: 0 }
    const next = departures(data, stops, day, limit, 0)
    if (next.length) return { day, today: false, list: next }
  }
  return { day: now, today: true, list: [] }
}
export const DAY_NAMES = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

export function serviceRuns(data: TransitData, service: number, c: Clock): boolean {
  const s = data.services[service]
  if (s.del.includes(c.date)) return false
  if (s.add.includes(c.date)) return true
  return c.date >= s.a && c.date <= s.z && s.d[c.dow] === 1
}

export interface Departure {
  trip: TransitData['trips'][number]
  stop: number // index into data.stops
  secs: number // seconds after midnight of the campus date being asked about; may exceed 86400
  pos: number // position of the stop in the trip
}

/** Scheduled departures from any of these stops at or after `now`, soonest first. */
export function departures(data: TransitData, stops: number[], now: Clock, limit = 8, from = now.secs): Departure[] {
  const want = new Set(stops)
  const yesterday = previousDay(now)
  const runsToday = data.services.map((_, i) => serviceRuns(data, i, now))
  const runsYesterday = data.services.map((_, i) => serviceRuns(data, i, yesterday))
  const out: Departure[] = []
  for (const trip of data.trips) {
    trip.t.forEach(([stop, time], pos) => {
      if (!want.has(stop)) return
      if (runsToday[trip.s] && time >= from) out.push({ trip, stop, secs: time, pos })
      else if (runsYesterday[trip.s] && time >= 86400 && time - 86400 >= from) out.push({ trip, stop, secs: time - 86400, pos })
    })
  }
  out.sort((a, b) => a.secs - b.secs)
  return out.slice(0, limit)
}

export const clockText = (secs: number) => {
  const m = Math.round(secs / 60) % 1440
  const h = Math.floor(m / 60)
  return `${((h + 11) % 12) + 1}:${String(m % 60).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`
}

export function feedCovers(data: TransitData, c: Clock): boolean {
  return c.date >= data.feed.start && c.date <= data.feed.end
}

export const stopsNamed = (data: TransitData, name: string) => data.stops.flatMap((s, i) => (s.name === name ? [i] : []))
