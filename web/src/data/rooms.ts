import type { Access, Place, RoomInfo } from './types'

export const ACCESS_LABEL: Record<Access, { title: string; detail: string }> = {
  outside: { title: 'Outside access', detail: 'The door is on a patio, plaza or outdoor walkway. Stay outside until you reach it.' },
  lobby: { title: 'Inside the building', detail: 'Go in through the building’s doors and find the room inside.' },
  library: { title: 'Inside the library', detail: 'Go in through the library doors; the room is past them.' },
}
const ACCESS_ORDER: Access[] = ['outside', 'lobby', 'library']

export function floorName(label: string): string {
  if (label === '0') return 'Lower level (floor 0)'
  return /^\d+$/.test(label) ? `Floor ${label}` : label
}

/** "Floor 2", or with its source when only the campus map says so. */
export function floorText(info?: RoomInfo): string | null {
  if (!info?.floor) return null
  const name = floorName(info.floor.label)
  return info.floor.basis === 'map' ? `${name} (campus map)` : name
}

const about = (m: number) => `about ${Math.max(5, Math.round(m / 5) * 5)} m`
const COMPASS = ['north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west']
const rad = (d: number) => (d * Math.PI) / 180

/** Distance and compass direction from `a` to `b`, both [lat, lon]. */
export function relation(a: [number, number], b: [number, number]): { meters: number; toward: string } {
  const dLat = rad(b[0] - a[0])
  const dLon = rad(b[1] - a[1])
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(dLon / 2) ** 2
  const meters = 2 * 6371000 * Math.asin(Math.sqrt(h))
  const y = Math.sin(dLon) * Math.cos(rad(b[0]))
  const x = Math.cos(rad(a[0])) * Math.sin(rad(b[0])) - Math.sin(rad(a[0])) * Math.cos(rad(b[0])) * Math.cos(dLon)
  const deg = ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360
  return { meters, toward: COMPASS[Math.round(deg / 45) % 8] }
}

/** Where the room is from a door: "The room is about 30 m south-west of this door, on floor 1." */
export function doorSentence(info?: RoomInfo, from?: { meters: number; toward: string }): string | null {
  const d = from ?? info?.door
  if (!d) return null
  const where = d.meters < 6 ? 'right by this door' : `${about(d.meters)} ${d.toward} of this door`
  const floor = info?.floor ? `, on ${floorName(info.floor.label).toLowerCase()}` : ''
  return `The room is ${where}${floor}.`
}

export function doorTitle(info?: RoomInfo): string | null {
  const d = info?.door
  if (!d) return null
  if (d.checked) return d.label ?? 'Marked door'
  return 'Closest mapped door'
}

export function checkedText(info?: RoomInfo): string | null {
  const g = info?.guide
  if (!g) return null
  const date = new Date(g.checked + 'T12:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
  return g.source === 'student-tip' ? `From a student tip, checked ${date}` : `Checked on foot ${date}`
}

export interface RoomGroup {
  key: string
  title: string
  rooms: Place[]
}

/** A building's rooms split the way a student needs: by how you get in once anyone has checked, by floor before that. */
export function roomGroups(building: Place, byId: Map<string, Place>): RoomGroup[] {
  const rooms = (building.roomIds ?? []).map((id) => byId.get(id)).filter((p): p is Place => !!p?.room)
  if (!rooms.length) return []
  if (rooms.some((r) => r.room?.guide?.access)) {
    const groups: RoomGroup[] = ACCESS_ORDER.map((a) => ({ key: a, title: ACCESS_LABEL[a].title, rooms: rooms.filter((r) => r.room?.guide?.access === a) }))
    groups.push({ key: 'unchecked', title: 'Not checked yet', rooms: rooms.filter((r) => !r.room?.guide?.access) })
    return groups.filter((g) => g.rooms.length)
  }
  const floors = new Map<string, Place[]>()
  for (const r of rooms) {
    const k = r.room?.floor?.label ?? '?'
    floors.set(k, [...(floors.get(k) ?? []), r])
  }
  return [...floors].map(([k, rs]) => ({ key: `floor-${k}`, title: k === '?' ? 'Floor not known' : floorName(k), rooms: rs }))
}

export interface RecentStore {
  get(): string[]
  push(id: string): string[]
}

export function recentStore(key = 'recentPlaces', max = 5, storage: () => Storage = () => localStorage): RecentStore {
  const get = () => {
    try {
      const v = JSON.parse(storage().getItem(key) ?? '[]')
      return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string').slice(0, max) : []
    } catch {
      return []
    }
  }
  return {
    get,
    push(id) {
      const next = [id, ...get().filter((x) => x !== id)].slice(0, max)
      try {
        storage().setItem(key, JSON.stringify(next))
      } catch {
        /* storage may be unavailable */
      }
      return next
    },
  }
}
