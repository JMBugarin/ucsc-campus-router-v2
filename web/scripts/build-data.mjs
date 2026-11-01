// Builds public/data/{graph,places}.json from the repo's walking graph, the curated building
// list and a snapshot of OpenStreetMap features (ODbL). Run: npm run data
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..', '..')
const src = join(here, '..', 'data-src')
const out = join(here, '..', 'public', 'data')
mkdirSync(out, { recursive: true })

const R = 6371000
const rad = (d) => (d * Math.PI) / 180
function metres(a, b) {
  const dLat = rad(b[0] - a[0])
  const dLon = rad(b[1] - a[1])
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(dLon / 2) ** 2
  return 2 * R * Math.asin(Math.sqrt(h))
}
function distToSegment(p, a, b) {
  const k = Math.cos(rad(p[0]))
  const ax = (a[1] - p[1]) * k * 111320, ay = (a[0] - p[0]) * 110540
  const bx = (b[1] - p[1]) * k * 111320, by = (b[0] - p[0]) * 110540
  const dx = bx - ax, dy = by - ay
  const len2 = dx * dx + dy * dy
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, -(ax * dx + ay * dy) / len2))
  return Math.hypot(ax + t * dx, ay + t * dy)
}
const round = (n, d = 6) => Math.round(n * 10 ** d) / 10 ** d

// ---------------------------------------------------------------- graph
const csv = (f) => readFileSync(join(root, 'graph', 'ucsc', f), 'utf8').trim().split('\n').slice(1).map((l) => l.split(','))
const nodes = csv('nodes.csv').map(([, , lat, lon, ele]) => [+lat, +lon, +ele])
const bridges = JSON.parse(readFileSync(join(src, 'osm-bridges.json'), 'utf8')).elements.map((w) =>
  w.geometry.map((g) => [g.lat, g.lon]),
)
const isBridge = (mid) => bridges.some((line) => line.some((pt, i) => i > 0 && distToSegment(mid, line[i - 1], pt) < 3))
const ROAD = /^(residential|secondary|secondary_link|tertiary|unclassified|service|living_street|track)$/
const edges = []
const kindCount = { path: 0, steps: 0, road: 0, bridge: 0 }
for (const [f, t, len, stairs, hw] of csv('edges.csv')) {
  const a = nodes[+f], b = nodes[+t]
  const parts = hw.split('|')
  let kind = 0
  if (+stairs || parts.includes('steps')) kind = 1
  else if (parts.every((p) => ROAD.test(p))) kind = 2
  if (kind !== 1 && isBridge([(a[0] + b[0]) / 2, (a[1] + b[1]) / 2])) kind = 3
  kindCount[['path', 'steps', 'road', 'bridge'][kind]]++
  edges.push(+f, +t, round(+len, 2), kind)
}
writeFileSync(
  join(out, 'graph.json'),
  JSON.stringify({
    lat: nodes.map((n) => round(n[0])),
    lon: nodes.map((n) => round(n[1])),
    ele: nodes.map((n) => n[2]),
    edges,
  }),
)
console.log('graph', nodes.length, 'nodes', edges.length / 4, 'edges', kindCount)

// ---------------------------------------------------------------- places
const osm = JSON.parse(readFileSync(join(src, 'osm-pois.json'), 'utf8')).elements
const curated = JSON.parse(readFileSync(join(root, 'data', 'buildings.json'), 'utf8')).buildings
const extra = JSON.parse(readFileSync(join(root, 'data', 'search_aliases.json'), 'utf8'))
const pt = (e) => [e.lat ?? e.center?.lat, e.lon ?? e.center?.lon]
const key = (e) => e.type[0] + e.id

const places = []
const used = new Set()
const add = (p) => {
  const id = p.id
  if (used.has(id)) return
  used.add(id)
  places.push({ ...p, lat: round(p.lat), lon: round(p.lon) })
}
const slug = (s) => s.toLowerCase().replace(/&/g, 'and').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')

const kindOf = (b) => {
  if (/library/i.test(b.name) || b.primary_use === 'LIB') return 'library'
  if (!b.primary_use || b.primary_use === 'CLS' || b.primary_use === 'LAB') return 'academic'
  return 'landmark'
}
// curated academic buildings first: they carry schedule aliases and entrances
const claimed = new Set()
for (const b of curated) {
  if (!b.centroid) continue
  claimed.add(b.osm_name?.toLowerCase())
  add({
    id: b.id,
    name: b.name,
    kind: kindOf(b),
    lat: b.centroid.lat,
    lon: b.centroid.lon,
    aliases: [...new Set([...(b.aliases || []), ...(extra[b.id] || [])])].filter((a) => a !== b.name),
    entrances: (b.entrances || []).map((e) => [round(e.lat), round(e.lon)]),
    rooms: Object.keys(b.room_points || {}).length || undefined,
    source: b.source === 'ucsc-facilities' ? 'ucsc-facilities' : 'ucsc-dataset',
    subtitle: b.region && b.source === 'ucsc-facilities' ? b.region : undefined,
  })
}

const BLOCK = /(studio|shed|storage|dumpster|restroom|garage|kiosk|recycl|maintenance|woodshop|foundry|laundry|mailroom|gatehouse|modular|faculty|office|apartment|suite|flats|trash|heat plant|facility|transmitter|casa \d|garden|guest|annex|^[0-9]+$|^[a-z]-?[a-z]?$|room|lab$|residence|lounge)/i
const OK_NAMED = /(student union|bay tree|cowell student health|wellness|field house|east gym|recital|music center|theater arts|media theater|kerr hall|redwood building|university center|hahn student services|quarry amphitheater|communications|digital arts|visual arts|elena baskin|center for adaptive|academic resource|ghandi|cantu|kzsc|science & engineering|engineering auditorium|linguistics|transfer student|opers|baskin arts|sinsheimer|humanities lecture|crown college classroom|porter academic|stevenson academic|kresge academic|oakes academic|merrill academic|carson|rachel carson college academic)/i

const COLLEGE_NAMES = {
  'Cowell College': ['Cowell'], 'Stevenson College': ['Stevenson'], 'Crown College': ['Crown'], 'Merrill College': ['Merrill'],
  'Porter College': ['Porter'], 'Kresge College': ['Kresge'], 'Oakes College': ['Oakes'], 'Rachel Carson College': ['Carson', 'Rachel Carson'],
  'College Nine': ['College 9', 'Nine'], 'John R. Lewis College': ['College Ten', 'College 10', 'Lewis', 'Ten'],
}

const SKIP = /dressing|toilet|\bshed\b|storage|transmitter|offices|press bldg|core west parking|dining hall\b.*\(|\(f4\)|building b$|kzsc-fm|studio$|east remote parking interior|west remote parking interior/i
for (const e of osm) {
  const t = e.tags
  const name = t.name
  if (name && SKIP.test(name)) continue
  const [lat, lon] = pt(e)
  if (!name || lat == null) continue
  const id = slug(name) + '-' + key(e)

  if (t.amenity === 'college' && COLLEGE_NAMES[name]) {
    add({ id: slug(name), name, kind: 'college', lat, lon, aliases: COLLEGE_NAMES[name], source: 'osm', osm: key(e) })
    continue
  }
  if (['restaurant', 'cafe', 'fast_food', 'food_court'].includes(t.amenity) && !used.has(slug(name))) {
    add({ id, name, kind: 'dining', lat, lon, aliases: [], subtitle: t.amenity === 'cafe' ? 'Café' : undefined, source: 'osm', osm: key(e) })
    continue
  }
  if (t.highway === 'bus_stop' && t.public_transport === 'platform') {
    add({
      id: id, name: name.replace(/^UCSC /, '') + ' stop', kind: 'transit', lat, lon,
      aliases: [name], subtitle: t.operator === 'Santa Cruz Metropolitan Transit District' ? 'Santa Cruz METRO' : 'Campus', source: 'osm', osm: key(e),
    })
    continue
  }
  if (t.highway === 'bus_stop') {
    add({ id, name: name + ' stop', kind: 'transit', lat, lon, aliases: [name], subtitle: 'Campus', source: 'osm', osm: key(e) })
    continue
  }
  if (t.amenity === 'parking' && e.type !== 'node') {
    const numeric = /^\d{3}$/.test(name)
    const big = /remote|core west|performing|hahn|north perimeter|parking lot/i.test(name)
    if (!numeric && !big) continue
    const label = numeric ? `Lot ${name}` : name.replace(/^Parking Lot (\d+)$/i, 'Lot $1')
    if ([...used].some((u) => u.startsWith(slug(label) + '-') || u === slug(label))) continue
    add({ id: slug(label) + '-' + key(e), name: label, kind: 'parking', lat, lon, aliases: numeric ? [`Parking ${name}`, name] : [], source: 'osm', osm: key(e) })
    continue
  }
  if (t.place === 'locality' && name === 'Science Hill') {
    add({ id: 'science-hill', name, kind: 'landmark', lat, lon, aliases: ['Sci Hill'], subtitle: 'Area', source: 'osm', osm: key(e) })
    continue
  }
  if (t.highway === 'pedestrian' && /plaza/i.test(name)) {
    if (used.has(slug(name))) continue
    add({ id: slug(name), name, kind: 'landmark', lat, lon, aliases: [], subtitle: 'Plaza', source: 'osm', osm: key(e) })
    continue
  }
  if (t.theatre || t.amenity === 'theatre' || t.amenity === 'arts_centre') {
    if (!/main stage|second stage|porter stage|festival glen|experimental|eXperimental/i.test(name) && !/gallery|amphitheater|event center/i.test(name)) continue
    if (e.type !== 'way' && /main stage/i.test(name)) continue
    add({ id: slug(name), name, kind: 'landmark', lat, lon, aliases: [], subtitle: 'Arts', source: 'osm', osm: key(e) })
    continue
  }
  if (t.amenity === 'library' || t.building === 'library') {
    if (claimed.has(name.toLowerCase())) continue
    add({ id: slug(name), name, kind: 'library', lat, lon, aliases: [], source: 'osm', osm: key(e) })
    continue
  }
  if (e.type !== 'node' && ['university', 'yes', 'doctors'].includes(t.building || '') || t.amenity === 'doctors') {
    if (claimed.has(name.toLowerCase())) continue
    if (/dining|dinning/i.test(name)) {
      add({ id: slug(name), name, kind: 'dining', lat, lon, aliases: [], source: 'osm', osm: key(e) })
      continue
    }
    if (BLOCK.test(name) && !OK_NAMED.test(name)) continue
    if (!OK_NAMED.test(name)) continue
    add({ id: slug(name), name, kind: 'landmark', lat, lon, aliases: [], source: 'osm', osm: key(e) })
    continue
  }
  if (t.building === 'dormitory' && e.type !== 'node' && /house|hall$/i.test(name) && false) continue
}

// METRO stops from the GTFS schedule (built by build-transit.mjs); OSM stops they cover are dropped
try {
  const transit = JSON.parse(readFileSync(join(out, 'transit.json'), 'utf8'))
  const groups = new Map()
  for (const st of transit.stops) groups.set(st.name, [...(groups.get(st.name) ?? []), st])
  const near = (p) => transit.stops.some((st) => metres([p.lat, p.lon], [st.lat, st.lon]) < 100)
  places.splice(0, places.length, ...places.filter((p) => !(p.kind === 'transit' && p.source === 'osm' && near(p))))
  for (const [name, g] of groups) {
    add({
      id: 'stop-' + slug(name), name: `${name} stop`, kind: 'transit',
      lat: g.reduce((a, b) => a + b.lat, 0) / g.length, lon: g.reduce((a, b) => a + b.lon, 0) / g.length,
      aliases: [name, `${name} bus`], subtitle: 'METRO bus', stops: g.map((x) => x.id), source: 'metro-gtfs',
    })
  }
} catch {
  console.log('no transit.json: run npm run transit first for METRO stops')
}

// OSM features that restate a curated building (same words, within 120 m) are dropped
const words = (n) => slug(n).replace(/-(building|bldg|college|hall)\b/g, '').replace('laboratories', 'labs')
const curatedPlaces = places.filter((p) => p.source.startsWith('ucsc'))
const similar = (a, b) => {
  const [short, long] = a.length <= b.length ? [a, b] : [b, a]
  return short === long || (long.startsWith(short) && short.length / long.length >= 0.6)
}
const restates = (p) =>
  p.source === 'osm' &&
  ['landmark', 'library'].includes(p.kind) &&
  curatedPlaces.some((c) => metres([p.lat, p.lon], [c.lat, c.lon]) < 120 && similar(words(c.name), words(p.name)))
places.splice(0, places.length, ...places.filter((p) => !restates(p)))

// de-duplicate near-identical names (curated wins because it was added first)
const seen = new Map()
const final = []
for (const p of places) {
  const k = slug(p.name) + '|' + p.kind
  if (seen.has(k)) continue
  seen.set(k, true)
  final.push(p)
}

// dining halls and cafés that OSM lists as nodes; keep college nodes unique
const order = { college: 0, academic: 1, library: 2, dining: 3, landmark: 4, transit: 5, parking: 6 }
final.sort((a, b) => order[a.kind] - order[b.kind] || a.name.localeCompare(b.name))
const counts = {}
for (const p of final) counts[p.kind] = (counts[p.kind] || 0) + 1
writeFileSync(
  join(out, 'places.json'),
  JSON.stringify({
    attribution: 'Map data © OpenStreetMap contributors (ODbL). Building list and room data: UC Santa Cruz public classroom data.',
    places: final,
  }),
)
console.log('places', final.length, counts)
