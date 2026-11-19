// Turns the curated buildings, the official room points, the hand-checked guides in
// data/rooms.json and the published floors in data/floors.json into one searchable place per classroom.

export const ACCESS = ['outside', 'lobby', 'library']
export const SOURCES = ['walk', 'student-tip', 'published']
export const WHERE = ['entrance', 'upstairs', 'below']
const MAX_DOOR_GAP_M = 15
const MAX_ENTRANCE_FROM_ROOM_M = 120
const COMPASS = ['north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west']

const R = 6371000
const rad = (d) => (d * Math.PI) / 180
const round = (n, d = 6) => Math.round(n * 10 ** d) / 10 ** d

export function metres(a, b) {
  const dLat = rad(b[0] - a[0])
  const dLon = rad(b[1] - a[1])
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(dLon / 2) ** 2
  return 2 * R * Math.asin(Math.sqrt(h))
}

export function bearing(a, b) {
  const y = Math.sin(rad(b[1] - a[1])) * Math.cos(rad(b[0]))
  const x = Math.cos(rad(a[0])) * Math.sin(rad(b[0])) - Math.sin(rad(a[0])) * Math.cos(rad(b[0])) * Math.cos(rad(b[1] - a[1]))
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360
}

export const compass = (deg) => COMPASS[Math.round(deg / 45) % 8]

/**
 * The floor shown for a room: checked on foot, else confirmed by a published UCSC source, else none.
 * Neither the room number nor the campus map level is a floor (McHenry 1340 is on floor 1, map level L3).
 */
export function floorOf(key, guide, floors) {
  if (guide?.floor) return { label: guide.floor, basis: 'checked' }
  const f = floors?.rooms?.[key]
  const s = f && floors.sources?.[f.source]
  if (!s) return undefined
  return { label: f.floor, basis: 'published', ...(f.where ? { where: f.where } : {}), source: { name: s.name, url: s.url } }
}

/** Errors in data/floors.json: every room must exist, cite a listed source and say where it is plainly. */
export function checkFloors(floors, exists) {
  const errors = []
  const sources = floors?.sources ?? {}
  for (const [id, s] of Object.entries(sources)) {
    if (!s?.name || !/^https:\/\//.test(s.url ?? '') || !/^\d{4}-\d{2}-\d{2}$/.test(s.read ?? '')) errors.push(`floors.json sources.${id}: needs name, https url and the YYYY-MM-DD it was read`)
  }
  for (const [key, f] of Object.entries(floors?.rooms ?? {})) {
    if (!exists(key)) errors.push(`floors.json ${key}: no such building and room`)
    if (typeof f?.floor !== 'string' || !/^(\d{1,2}|G)$/.test(f.floor)) errors.push(`floors.json ${key}.floor: a floor as signed, like "1" or "G"`)
    if (f?.where != null && !WHERE.includes(f.where)) errors.push(`floors.json ${key}.where: one of ${WHERE.join(', ')}`)
    if (!sources[f?.source]) errors.push(`floors.json ${key}.source: not in sources`)
  }
  return errors
}

const text = (v, max, where, errors) => {
  if (v == null) return undefined
  if (typeof v !== 'string' || !v.trim()) errors.push(`${where}: must be non-empty text`)
  else if (v.length > max) errors.push(`${where}: longer than ${max} characters`)
  return typeof v === 'string' ? v.trim() : undefined
}

/** Checks one data/rooms.json override and returns the guide the app shows, or errors. */
export function readGuide(key, raw, roomPoint) {
  const errors = []
  const where = (f) => `rooms.json ${key}${f ? '.' + f : ''}`
  if (!raw || typeof raw !== 'object') return { errors: [`${where()}: must be an object`] }
  const known = new Set(['entrance', 'access', 'floor', 'wing', 'note', 'steps', 'step_free', 'elevator', 'checked', 'source', 'url', 'cite'])
  for (const k of Object.keys(raw)) if (!known.has(k)) errors.push(`${where(k)}: unknown field`)
  const g = {}
  if (raw.access != null) {
    if (!ACCESS.includes(raw.access)) errors.push(`${where('access')}: one of ${ACCESS.join(', ')}`)
    else g.access = raw.access
  }
  g.floor = text(raw.floor, 12, where('floor'), errors)
  g.wing = text(raw.wing, 40, where('wing'), errors)
  g.note = text(raw.note, 160, where('note'), errors)
  g.elevator = text(raw.elevator, 120, where('elevator'), errors)
  if (raw.steps != null) {
    if (!Array.isArray(raw.steps) || raw.steps.length === 0 || raw.steps.length > 5) errors.push(`${where('steps')}: 1 to 5 short lines`)
    else g.steps = raw.steps.map((s, i) => text(s, 90, where(`steps[${i}]`), errors))
  }
  if (raw.step_free != null) {
    if (typeof raw.step_free !== 'boolean') errors.push(`${where('step_free')}: true or false`)
    else g.stepFree = raw.step_free
  }
  if (raw.entrance != null) {
    const e = raw.entrance
    if (!e || typeof e.lat !== 'number' || typeof e.lon !== 'number') errors.push(`${where('entrance')}: needs numeric lat and lon`)
    else {
      if (roomPoint && metres([e.lat, e.lon], roomPoint) > MAX_ENTRANCE_FROM_ROOM_M) errors.push(`${where('entrance')}: more than ${MAX_ENTRANCE_FROM_ROOM_M} m from the room`)
      g.entrance = { lat: e.lat, lon: e.lon, label: text(e.label, 60, where('entrance.label'), errors) }
    }
  }
  const has = Object.values(g).some((v) => v !== undefined)
  if (has) {
    if (typeof raw.checked !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(raw.checked) || Number.isNaN(Date.parse(raw.checked))) errors.push(`${where('checked')}: the YYYY-MM-DD date someone checked this on foot`)
    else g.checked = raw.checked
    const source = raw.source ?? 'walk'
    if (!SOURCES.includes(source)) errors.push(`${where('source')}: one of ${SOURCES.join(', ')}`)
    else g.source = source
    if (source === 'published') {
      if (typeof raw.url !== 'string' || !/^https:\/\//.test(raw.url)) errors.push(`${where('url')}: the https page the guide comes from`)
      else g.url = raw.url
      g.cite = text(raw.cite, 60, where('cite'), errors)
      if (!raw.cite) errors.push(`${where('cite')}: who published it, like "UCSC Library"`)
    }
  }
  if (raw.source !== 'published' && (raw.url != null || raw.cite != null)) errors.push(`${where('url')}: only for "source": "published"`)
  for (const k of Object.keys(g)) if (g[k] === undefined) delete g[k]
  return { guide: has ? g : undefined, errors }
}

const cleanName = (n) => n.replace(/\s*\([^)]*\)\s*$/, '')

/** One place per room point, plus the room ids each building lists. */
export function buildRooms({ buildings, extraAliases = {}, classrooms = [], overrides = {}, floors = { sources: {}, rooms: {} } }) {
  const errors = []
  const rooms = []
  const byBuilding = {}
  const used = new Set()
  const exists = (key) => {
    const [bid, room] = key.split(':')
    const b = buildings.find((x) => x.id === bid)
    return !!(b && room && b.room_points?.[room])
  }
  for (const key of Object.keys(overrides)) if (!exists(key)) errors.push(`rooms.json ${key}: no such building and room`)
  errors.push(...checkFloors(floors, exists))
  for (const b of buildings) {
    const points = b.room_points ?? {}
    const doors = (b.entrances ?? []).filter((e) => e.kind !== 'approach')
    const name = cleanName(b.name)
    const baseAliases = [...new Set([b.name, name, ...(b.aliases ?? []), ...(extraAliases[b.id] ?? [])])]
    const exactFor = Object.fromEntries(Object.entries(b.exact_names ?? {}).map(([full, r]) => [r, full]))
    const facility = Object.fromEntries(
      classrooms
        .filter((c) => (b.facility_ids ?? []).some((f) => c.facility_id?.startsWith(f + ' ')))
        .map((c) => [c.facility_id.split(' ').slice(1).join(' '), c]),
    )
    const ids = []
    for (const [room, p] of Object.entries(points)) {
      const at = [p.lat, p.lon]
      const key = `${b.id}:${room}`
      const read = overrides[key] ? readGuide(key, overrides[key], at) : { guide: undefined, errors: [] }
      errors.push(...read.errors)
      const guide = read.guide
      const ranked = doors
        .map((d) => ({ lat: d.lat, lon: d.lon, meters: metres([d.lat, d.lon], at), main: d.kind === 'main' }))
        .sort((x, y) => x.meters - y.meters)
      let entrances
      let door
      if (guide?.entrance) {
        const e = guide.entrance
        door = { lat: e.lat, lon: e.lon, meters: metres([e.lat, e.lon], at), label: e.label, checked: true }
        entrances = [[round(e.lat), round(e.lon)]]
      } else if (ranked.length) {
        const near = ranked.filter((d) => d.meters <= ranked[0].meters + MAX_DOOR_GAP_M).slice(0, 2)
        door = { ...ranked[0] }
        entrances = near.map((d) => [round(d.lat), round(d.lon)])
      }
      if (door) {
        door = {
          lat: round(door.lat),
          lon: round(door.lon),
          meters: Math.round(door.meters),
          toward: compass(bearing([door.lat, door.lon], at)),
          ...(door.label ? { label: door.label } : {}),
          ...(door.checked ? { checked: true } : {}),
        }
      }
      const fac = facility[room]
      const aliases = [
        ...baseAliases.map((a) => `${a} ${room}`),
        ...(exactFor[room] ? [exactFor[room]] : []),
        ...(fac?.facility_id ? [fac.facility_id] : []),
        ...(fac?.ais_display_name ? [fac.ais_display_name] : []),
      ]
      let id = `${b.id}-${room.toLowerCase()}`
      while (used.has(id)) id += '-x'
      used.add(id)
      const floor = floorOf(key, guide, floors)
      rooms.push({
        id,
        name: `${name} ${room}`,
        kind: 'room',
        lat: round(p.lat),
        lon: round(p.lon),
        aliases: [...new Set(aliases)].filter((a) => a !== `${name} ${room}`),
        subtitle: name,
        entrances,
        source: !guide ? 'ucsc-dataset' : guide.source === 'published' ? 'ucsc-dataset+published' : 'ucsc-dataset+walk',
        room: {
          building: b.id,
          number: room,
          ...(floor ? { floor } : {}),
          ...(door ? { door } : {}),
          ...(guide ? { guide: Object.fromEntries(Object.entries(guide).filter(([k]) => k !== 'entrance' && k !== 'floor')) } : {}),
        },
      })
      ids.push({ id, floor: floor?.label ?? '', room })
    }
    if (ids.length) {
      byBuilding[b.id] = ids
        .sort((x, y) => x.floor.localeCompare(y.floor, 'en', { numeric: true }) || x.room.localeCompare(y.room, 'en', { numeric: true }))
        .map((x) => x.id)
    }
  }
  return { rooms, byBuilding, errors }
}
