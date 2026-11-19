/** Matches schedule locations ("J Baskin Engr 152", "Humn Lecture Hall") to campus buildings and rooms, as the phone app does. */
const ONLINE = new Set(['online', 'remote', 'remote instruction', 'zoom', 'asynchronous', 'async', 'web', 'online asynchronous', 'online synchronous'])
const TBA = new Set(['', 'tba', 'tbd', 'to be announced', 'no room', 'none'])
const ROOM_WORDS = new Set(['room', 'rm'])

export const normalize = (text: string) =>
  text
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()

const words = (normalized: string) => (normalized ? normalized.split(' ') : [])
const hasDigit = (s: string) => /[0-9]/.test(s)

export interface CampusBuilding {
  id: string
  name: string
  osm_name?: string | null
  aliases?: string[]
  exact_names?: Record<string, string>
  known_rooms?: string[]
  room_points?: Record<string, { lat: number; lon: number; level?: string | null }>
}
export interface CampusFile {
  buildings: CampusBuilding[]
  /** what students call buildings (`BE`, `S&E Library`); used only where no official name already matches */
  nicknames?: Record<string, string[]>
}

export interface Resolution {
  raw: string
  /** `building`, `online`, `tba` or `unknown` */
  kind: 'building' | 'online' | 'tba' | 'unknown'
  buildingId?: string
  room?: string
  /** true or false when the building lists its rooms */
  roomKnown?: boolean
  level?: string
}

export class Campus {
  readonly buildings = new Map<string, CampusBuilding>()
  private index = new Map<string, string>()
  private loose = new Map<string, string>()
  private exact = new Map<string, [string, string]>()

  constructor(file: CampusFile) {
    for (const b of file.buildings) {
      if (this.buildings.has(b.id)) throw new Error(`duplicate building id ${b.id}`)
      this.buildings.set(b.id, b)
    }
    for (const b of file.buildings) {
      for (const [name, room] of Object.entries(b.exact_names ?? {})) this.exact.set(normalize(name), [b.id, room])
      for (const alias of [b.name, b.osm_name ?? '', ...(b.aliases ?? [])]) {
        const key = normalize(alias)
        if (!key) continue
        const owner = this.index.get(key) ?? b.id
        if (owner !== b.id) throw new Error(`alias "${alias}" belongs to both ${owner} and ${b.id}`)
        this.index.set(key, b.id)
      }
    }
    this.loose = new Map(this.index)
    for (const [id, names] of Object.entries(file.nicknames ?? {})) {
      if (!this.buildings.has(id)) continue
      for (const n of names) {
        const key = normalize(n)
        if (key && !this.loose.has(key)) this.loose.set(key, id)
      }
    }
  }

  /** Splits a location followed by other words, such as a schedule row's room and instructor. */
  splitLocation(text: string): [string, string] {
    const ws = text.split(/\s+/).filter(Boolean)
    const norm = ws.map(normalize)
    const phrase = (k: number) => norm.slice(0, k).filter(Boolean).join(' ')
    const cut = (k: number): [string, string] => [ws.slice(0, k).join(' '), ws.slice(k).join(' ')]
    for (let k = 1; k <= Math.min(ws.length, 3); k++) {
      const p = phrase(k)
      if (ONLINE.has(p) || (TBA.has(p) && p)) return cut(k)
    }
    for (let k = ws.length; k > 0; k--) if (this.exact.has(phrase(k))) return cut(k)
    let aliasLen = 0
    for (let k = ws.length; k > 0; k--) {
      if (this.index.has(phrase(k))) {
        aliasLen = k
        break
      }
    }
    for (let j = aliasLen; j < ws.length; j++) if (hasDigit(ws[j])) return cut(j + 1)
    return [text, '']
  }

  /** Like the phone app; `nicknames` also accepts what students type, such as "BE 152". */
  resolve(location?: string | null, nicknames = false): Resolution {
    const index = nicknames ? this.loose : this.index
    const raw = location ?? ''
    const text = normalize(raw)
    if (TBA.has(text)) return { raw, kind: 'tba' }
    if (ONLINE.has(text) || text.startsWith('online ') || text.startsWith('remote ')) return { raw, kind: 'online' }
    const exact = this.exact.get(text)
    if (exact) return this.building(raw, exact[0], [exact[1].toLowerCase()])
    const tokens = words(text)
    for (let k = tokens.length; k > 0; k--) {
      const id = index.get(tokens.slice(0, k).join(' '))
      if (id) return this.building(raw, id, tokens.slice(k))
    }
    return { raw, kind: 'unknown' }
  }

  private building(raw: string, buildingId: string, rest: string[]): Resolution {
    const ws = rest.length && ROOM_WORDS.has(rest[0]) ? rest.slice(1) : rest
    const joined = ws.join(' ').toUpperCase()
    const room = joined || undefined
    const b = this.buildings.get(buildingId)!
    const known = b.known_rooms ?? []
    const out: Resolution = { raw, kind: 'building', buildingId }
    if (room) out.room = room
    if (known.length && room) out.roomKnown = known.includes(room)
    const level = room ? b.room_points?.[room]?.level : undefined
    if (level) out.level = level
    return out
  }

  /** The web map place a resolution points at: the room when the map has it, else the building. */
  placeId(r: Resolution, has: (id: string) => boolean): string | null {
    if (r.kind !== 'building' || !r.buildingId) return null
    if (r.room) {
      const id = `${r.buildingId}-${r.room.toLowerCase()}`
      if (has(id)) return id
    }
    return has(r.buildingId) ? r.buildingId : null
  }
}
