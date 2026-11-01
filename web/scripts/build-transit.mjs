// Builds public/data/transit.json: Santa Cruz METRO's published GTFS schedule, cut down to the trips that
// serve UCSC stops. Source: https://developer.scmetro.org/ (CC BY 4.0 and the SCMTD Developer License).
// Run: npm run transit   (downloads gtfs.zip, needs the `unzip` command)
import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const out = join(here, '..', 'public', 'data')
mkdirSync(out, { recursive: true })

const res = await fetch('https://developer.scmetro.org/gtfs.zip', { headers: { 'user-agent': 'ucsc-map/1.0 (student project)' } })
if (!res.ok) throw new Error(`gtfs.zip ${res.status}`)
const dir = mkdtempSync(join(tmpdir(), 'gtfs-'))
const zip = join(dir, 'gtfs.zip')
writeFileSync(zip, Buffer.from(await res.arrayBuffer()))
const file = (name) => execFileSync('unzip', ['-p', zip, name], { maxBuffer: 1 << 30 }).toString('utf8')

function parseCsv(text) {
  const rows = []
  let row = [], cell = '', q = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (q) {
      if (c === '"' && text[i + 1] === '"') (cell += '"', i++)
      else if (c === '"') q = false
      else cell += c
    } else if (c === '"') q = true
    else if (c === ',') (row.push(cell), (cell = ''))
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++
      row.push(cell); cell = ''
      if (row.length > 1 || row[0] !== '') rows.push(row)
      row = []
    } else cell += c
  }
  if (cell || row.length) (row.push(cell), rows.push(row))
  const head = rows.shift()
  return rows.map((r) => Object.fromEntries(head.map((h, i) => [h, r[i] ?? ''])))
}
const secs = (t) => { const [h, m, s] = t.split(':').map(Number); return h * 3600 + m * 60 + s }

const stops = parseCsv(file('stops.txt'))
const campus = stops.filter((s) => +s.stop_lat > 36.985 && +s.stop_lat < 37.003 && +s.stop_lon > -122.075 && +s.stop_lon < -122.045 && /UCSC/.test(s.stop_name))
const idx = new Map(campus.map((s, i) => [s.stop_id, i]))
const routes = Object.fromEntries(parseCsv(file('routes.txt')).map((r) => [r.route_id, { s: r.route_short_name, n: r.route_long_name, c: r.route_color || '' }]))
const tripsAll = new Map(parseCsv(file('trips.txt')).map((t) => [t.trip_id, t]))

const byTrip = new Map()
for (const r of parseCsv(file('stop_times.txt'))) {
  const i = idx.get(r.stop_id)
  if (i === undefined) continue
  if (!byTrip.has(r.trip_id)) byTrip.set(r.trip_id, [])
  byTrip.get(r.trip_id).push([+r.stop_sequence, i, secs(r.arrival_time || r.departure_time)])
}

const services = parseCsv(file('calendar.txt'))
const dates = parseCsv(file('calendar_dates.txt'))
const svcIdx = new Map(services.map((s, i) => [s.service_id, i]))
const svc = services.map((s) => ({
  d: [s.monday, s.tuesday, s.wednesday, s.thursday, s.friday, s.saturday, s.sunday].map(Number),
  a: s.start_date, z: s.end_date, add: [], del: [],
}))
for (const d of dates) {
  const i = svcIdx.get(d.service_id)
  if (i !== undefined) (d.exception_type === '1' ? svc[i].add : svc[i].del).push(d.date)
}

const trips = []
for (const [id, list] of byTrip) {
  const t = tripsAll.get(id)
  if (!t || !svcIdx.has(t.service_id)) continue
  list.sort((a, b) => a[0] - b[0])
  trips.push({ i: id, r: routes[t.route_id].s, h: t.trip_headsign, s: svcIdx.get(t.service_id), t: list.map(([, s, time]) => [s, time]) })
}
trips.sort((a, b) => a.t[0][1] - b.t[0][1])

const clean = (n) => n.replace(/^.*\(UCSC - (.*)\)$/, '$1').replace(/^(.*) \(UCSC.*$/, '$1')
const feed = parseCsv(file('feed_info.txt'))[0]
const data = {
  attribution: 'Schedule data: Santa Cruz METRO GTFS, CC BY 4.0 and the SCMTD Developer License (developer.scmetro.org).',
  feed: { version: feed.feed_version, start: feed.feed_start_date, end: feed.feed_end_date },
  stops: campus.map((s) => ({ id: s.stop_id, name: clean(s.stop_name), full: s.stop_name, lat: +(+s.stop_lat).toFixed(6), lon: +(+s.stop_lon).toFixed(6) })),
  routes: Object.fromEntries(Object.values(routes).filter((r) => trips.some((t) => t.r === r.s)).map((r) => [r.s, { n: r.n, c: r.c }])),
  services: svc,
  trips,
}
writeFileSync(join(out, 'transit.json'), JSON.stringify(data))
console.log(`transit: ${data.stops.length} stops, ${trips.length} trips, routes ${Object.keys(data.routes).join(' ')}, feed ${feed.feed_start_date}-${feed.feed_end_date}`)
