/** A small GTFS-realtime reader (protocol buffers) for METRO's trip updates, vehicle positions and alerts. */

class Reader {
  pos = 0
  constructor(private b: Uint8Array, private end = b.length) {}
  get more() {
    return this.pos < this.end
  }
  varint(): number {
    let r = 0, shift = 0
    for (;;) {
      const x = this.b[this.pos++]
      r += (x & 0x7f) * 2 ** shift
      if (!(x & 0x80)) return r
      shift += 7
    }
  }
  tag(): [number, number] {
    const v = this.varint()
    return [Math.floor(v / 8), v % 8]
  }
  bytes(): Reader {
    const n = this.varint()
    const r = new Reader(this.b, this.pos + n)
    r.pos = this.pos
    this.pos += n
    return r
  }
  string(): string {
    const r = this.bytes()
    return new TextDecoder().decode(this.b.subarray(r.pos, r.end))
  }
  float(): number {
    const v = new DataView(this.b.buffer, this.b.byteOffset + this.pos, 4).getFloat32(0, true)
    this.pos += 4
    return v
  }
  skip(wire: number) {
    if (wire === 0) this.varint()
    else if (wire === 1) this.pos += 8
    else if (wire === 2) {
      const n = this.varint()
      this.pos += n
    }
    else if (wire === 5) this.pos += 4
    else throw new Error(`bad wire type ${wire}`)
  }
}
const int32 = (v: number) => (v > 2 ** 31 ? v - 2 ** 32 : v)

export interface StopUpdate { seq?: number; stop?: string; delay?: number; time?: number }
export interface TripUpdate { tripId: string; route?: string; updates: StopUpdate[]; canceled: boolean }
export interface Vehicle { tripId?: string; route?: string; lat: number; lon: number; stop?: string; time?: number }
export interface Alert { header: string; text: string; routes: string[]; stops: string[] }

function walk(r: Reader, f: (field: number, wire: number, r: Reader) => void) {
  while (r.more) {
    const [field, wire] = r.tag()
    f(field, wire, r)
  }
}
function tripDescriptor(r: Reader) {
  const t: { id?: string; route?: string; canceled?: boolean } = {}
  walk(r, (f, w, x) => {
    if (f === 1 && w === 2) t.id = x.string()
    else if (f === 5 && w === 2) t.route = x.string()
    else if (f === 4 && w === 0) t.canceled = x.varint() === 3
    else x.skip(w)
  })
  return t
}
function stopEvent(r: Reader) {
  const e: { delay?: number; time?: number } = {}
  walk(r, (f, w, x) => {
    if (f === 1 && w === 0) e.delay = int32(x.varint())
    else if (f === 2 && w === 0) e.time = x.varint()
    else x.skip(w)
  })
  return e
}
function translated(r: Reader) {
  let text = ''
  walk(r, (f, w, x) => {
    if (f === 1 && w === 2) walk(x.bytes(), (g, v, y) => { if (g === 1 && v === 2) { const t = y.string(); text ||= t } else y.skip(v) })
    else x.skip(w)
  })
  return text
}

export function parseFeed(buf: ArrayBuffer | Uint8Array) {
  const root = new Reader(buf instanceof Uint8Array ? buf : new Uint8Array(buf))
  const trips: TripUpdate[] = [], vehicles: Vehicle[] = [], alerts: Alert[] = []
  let timestamp = 0
  walk(root, (f, w, r) => {
    if (f === 1 && w === 2) walk(r.bytes(), (g, v, h) => (g === 3 && v === 0 ? (timestamp = h.varint()) : h.skip(v)))
    else if (f === 2 && w === 2) {
      walk(r.bytes(), (g, v, e) => {
        if (g === 3 && v === 2) {
          const tu: TripUpdate = { tripId: '', updates: [], canceled: false }
          walk(e.bytes(), (h, u, x) => {
            if (h === 1 && u === 2) { const t = tripDescriptor(x.bytes()); tu.tripId = t.id ?? ''; tu.route = t.route; tu.canceled = !!t.canceled }
            else if (h === 2 && u === 2) {
              const s: StopUpdate = {}
              walk(x.bytes(), (i, y, z) => {
                if (i === 1 && y === 0) s.seq = z.varint()
                else if (i === 4 && y === 2) s.stop = z.string()
                else if ((i === 2 || i === 3) && y === 2) { const ev = stopEvent(z.bytes()); s.delay ??= ev.delay; s.time ??= ev.time }
                else z.skip(y)
              })
              tu.updates.push(s)
            } else x.skip(u)
          })
          trips.push(tu)
        } else if (g === 4 && v === 2) {
          const veh: Vehicle = { lat: 0, lon: 0 }
          walk(e.bytes(), (h, u, x) => {
            if (h === 1 && u === 2) { const t = tripDescriptor(x.bytes()); veh.tripId = t.id; veh.route = t.route }
            else if (h === 2 && u === 2) walk(x.bytes(), (i, y, z) => (i === 1 && y === 5 ? (veh.lat = z.float()) : i === 2 && y === 5 ? (veh.lon = z.float()) : z.skip(y)))
            else if (h === 5 && u === 0) veh.time = x.varint()
            else if (h === 7 && u === 2) veh.stop = x.string()
            else x.skip(u)
          })
          vehicles.push(veh)
        } else if (g === 5 && v === 2) {
          const a: Alert = { header: '', text: '', routes: [], stops: [] }
          walk(e.bytes(), (h, u, x) => {
            if (h === 10 && u === 2) a.header = translated(x.bytes())
            else if (h === 11 && u === 2) a.text = translated(x.bytes())
            else if (h === 5 && u === 2) walk(x.bytes(), (i, y, z) => (i === 2 && y === 2 ? a.routes.push(z.string()) : i === 5 && y === 2 ? a.stops.push(z.string()) : z.skip(y)))
            else x.skip(u)
          })
          alerts.push(a)
        } else e.skip(v)
      })
    } else r.skip(w)
  })
  return { timestamp, trips, vehicles, alerts }
}

/** Delay in seconds for a trip at a stop: the stop's own update, else the nearest earlier one. */
export function delayAt(update: TripUpdate | undefined, stopId: string, stopSeq?: number): number | null {
  if (!update) return null
  const own = update.updates.find((u) => u.stop === stopId && u.delay !== undefined)
  if (own) return own.delay!
  if (stopSeq === undefined) return null
  const earlier = update.updates.filter((u) => u.seq !== undefined && u.seq <= stopSeq && u.delay !== undefined)
  return earlier.length ? earlier[earlier.length - 1].delay! : null
}

export const REALTIME_BASE: string | undefined = import.meta.env.VITE_RT_BASE

export async function fetchRealtime(kind: 'trips' | 'vehicles' | 'alerts', signal?: AbortSignal) {
  if (!REALTIME_BASE) return null
  const r = await fetch(`${REALTIME_BASE.replace(/\/$/, '')}/${kind}`, { signal })
  if (!r.ok) throw new Error(`realtime ${r.status}`)
  return parseFeed(await r.arrayBuffer())
}
