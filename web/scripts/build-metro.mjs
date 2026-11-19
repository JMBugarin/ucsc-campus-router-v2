// Builds public/data/metro.json: Santa Cruz METRO's whole published schedule, for planning trips that start or end
// off campus. Trips that stop at the same stops in the same order share a pattern, and trips that also keep the same
// running times share a profile, so the file stays small. Source: https://developer.scmetro.org/ (CC BY 4.0 and the
// SCMTD Developer License). Run: npm run metro   (downloads gtfs.zip, needs the `unzip` command)
import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const out = join(here, '..', 'public', 'data')
mkdirSync(out, { recursive: true })

const local = process.argv[2]
let zip = local
if (!zip) {
  const res = await fetch('https://developer.scmetro.org/gtfs.zip', { headers: { 'user-agent': 'classmap data tool (student project)' } })
  if (!res.ok) throw new Error(`gtfs.zip ${res.status}`)
  zip = join(mkdtempSync(join(tmpdir(), 'gtfs-')), 'gtfs.zip')
  writeFileSync(zip, Buffer.from(await res.arrayBuffer()))
}
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
  const head = rows.shift().map((h) => h.replace(/^﻿/, ''))
  return rows.map((r) => Object.fromEntries(head.map((h, i) => [h, r[i] ?? ''])))
}
const secs = (t) => { const [h, m, s] = t.split(':').map(Number); return h * 3600 + m * 60 + s }

const stops = parseCsv(file('stops.txt')).filter((s) => s.stop_lat && s.stop_lon)
const stopIdx = new Map(stops.map((s, i) => [s.stop_id, i]))
const routes = Object.fromEntries(parseCsv(file('routes.txt')).map((r) => [r.route_id, [r.route_short_name, r.route_long_name, r.route_color || '']]))
const tripsAll = new Map(parseCsv(file('trips.txt')).map((t) => [t.trip_id, t]))

const services = parseCsv(file('calendar.txt'))
const svcIdx = new Map(services.map((s, i) => [s.service_id, i]))
const svc = services.map((s) => ({ d: [s.monday, s.tuesday, s.wednesday, s.thursday, s.friday, s.saturday, s.sunday].map(Number), a: s.start_date, z: s.end_date, add: [], del: [] }))
for (const d of parseCsv(file('calendar_dates.txt'))) {
  const i = svcIdx.get(d.service_id)
  if (i !== undefined) (d.exception_type === '1' ? svc[i].add : svc[i].del).push(d.date)
}

const byTrip = new Map()
for (const r of parseCsv(file('stop_times.txt'))) {
  const i = stopIdx.get(r.stop_id)
  if (i === undefined) continue
  if (!byTrip.has(r.trip_id)) byTrip.set(r.trip_id, [])
  byTrip.get(r.trip_id).push([+r.stop_sequence, i, secs(r.departure_time || r.arrival_time), r.pickup_type === '1' ? 1 : 0, r.drop_off_type === '1' ? 1 : 0])
}

const patterns = new Map()
for (const [id, list] of byTrip) {
  const t = tripsAll.get(id)
  if (!t || !svcIdx.has(t.service_id) || !routes[t.route_id] || list.length < 2) continue
  list.sort((a, b) => a[0] - b[0])
  const stopsKey = list.map((x) => x[1]).join(',')
  const key = `${t.route_id}|${t.trip_headsign}|${stopsKey}`
  if (!patterns.has(key)) patterns.set(key, { r: t.route_id, h: t.trip_headsign, s: list.map((x) => x[1]), np: list.map((x) => x[3]), nd: list.map((x) => x[4]), profiles: new Map(), t: [] })
  const p = patterns.get(key)
  const start = list[0][2]
  const offsets = list.map((x) => x[2] - start).join(',')
  if (!p.profiles.has(offsets)) p.profiles.set(offsets, p.profiles.size)
  p.t.push([svcIdx.get(t.service_id), start, p.profiles.get(offsets), id])
}

const feed = parseCsv(file('feed_info.txt'))[0]
const data = {
  attribution: 'Schedule data: Santa Cruz METRO GTFS, CC BY 4.0 and the SCMTD Developer License (developer.scmetro.org).',
  feed: { version: feed.feed_version, start: feed.feed_start_date, end: feed.feed_end_date },
  stops: stops.map((s) => [s.stop_id, s.stop_name, +(+s.stop_lat).toFixed(6), +(+s.stop_lon).toFixed(6)]),
  routes,
  services: svc,
  patterns: [...patterns.values()]
    .sort((a, b) => a.r.localeCompare(b.r, 'en', { numeric: true }) || a.h.localeCompare(b.h))
    .map((p) => ({
      r: p.r,
      h: p.h,
      s: p.s,
      ...(p.np.some(Boolean) ? { np: p.np } : {}),
      ...(p.nd.some(Boolean) ? { nd: p.nd } : {}),
      p: [...p.profiles.keys()].map((k) => k.split(',').map(Number)),
      t: p.t.sort((x, y) => x[1] - y[1]),
    })),
}
writeFileSync(join(out, 'metro.json'), JSON.stringify(data))
const tripCount = data.patterns.reduce((n, p) => n + p.t.length, 0)
console.log(`metro: ${data.stops.length} stops, ${Object.keys(routes).length} routes, ${data.patterns.length} patterns, ${data.patterns.reduce((n, p) => n + p.p.length, 0)} profiles, ${tripCount} trips, feed ${feed.feed_start_date}-${feed.feed_end_date}`)
