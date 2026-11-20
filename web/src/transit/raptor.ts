import { haversine } from '../routing/graph'

/** METRO's whole schedule as built by scripts/build-metro.mjs. */
export interface MetroFile {
  feed: { version: string; start: string; end: string }
  stops: [string, string, number, number][]
  routes: Record<string, [string, string, string]>
  services: { d: number[]; a: string; z: string; add: string[]; del: string[] }[]
  /** route shapes as flat lat, lon lists */
  shapes?: number[][]
  /** g: the pattern's shape; gi: for each stop, its point on that shape */
  patterns: { r: string; h: string; s: number[]; np?: number[]; nd?: number[]; p: number[][]; t: [number, number, number, string][]; g?: number; gi?: number[] }[]
}

export interface Network {
  file: MetroFile
  /** for each stop, the patterns through it and where */
  at: [number, number][][]
  /** for each stop, the stops a short walk away and the seconds it takes */
  near: [number, number][][]
}

export const WALK_SPEED = 1.3
/** walking off the mapped campus paths is estimated from the straight line and this detour */
export const DETOUR = 1.25
const TRANSFER_M = 300

export function prepareNetwork(file: MetroFile): Network {
  const at: [number, number][][] = file.stops.map(() => [])
  file.patterns.forEach((p, pi) => p.s.forEach((s, pos) => at[s].push([pi, pos])))
  const near: [number, number][][] = file.stops.map(() => [])
  for (let a = 0; a < file.stops.length; a++) {
    for (let b = a + 1; b < file.stops.length; b++) {
      const sa = file.stops[a]
      const sb = file.stops[b]
      if (Math.abs(sa[2] - sb[2]) > 0.004) continue
      const d = haversine(sa[2], sa[3], sb[2], sb[3])
      if (d <= TRANSFER_M) {
        const secs = Math.round((d * DETOUR) / WALK_SPEED)
        near[a].push([b, secs])
        near[b].push([a, secs])
      }
    }
  }
  return { file, at, near }
}

/** A service day in Pacific time: `YYYYMMDD` and 0 = Monday. */
export interface Day {
  date: string
  dow: number
}
const runs = (f: MetroFile, svc: number, day: Day) => {
  const s = f.services[svc]
  if (s.del.includes(day.date)) return false
  if (s.add.includes(day.date)) return true
  return day.date >= s.a && day.date <= s.z && s.d[day.dow] === 1
}
export function previousDay(day: Day): Day {
  const y = +day.date.slice(0, 4), m = +day.date.slice(4, 6) - 1, d = +day.date.slice(6, 8)
  const t = new Date(Date.UTC(y, m, d - 1))
  const pad = (x: number) => String(x).padStart(2, '0')
  return { date: `${t.getUTCFullYear()}${pad(t.getUTCMonth() + 1)}${pad(t.getUTCDate())}`, dow: (day.dow + 6) % 7 }
}

export type Leg =
  | { kind: 'walk'; from: number | null; to: number | null; seconds: number; departs: number; arrives: number }
  | { kind: 'bus'; pattern: number; trip: number; shift: number; board: number; alight: number; departs: number; arrives: number }

export interface Journey {
  departs: number
  arrives: number
  legs: Leg[]
  transfers: number
}

interface TripRef {
  trip: number
  shift: number
}

/**
 * Earliest arrival from `access` stops (seconds to walk to each) to `egress` stops (seconds to walk on from each),
 * leaving at `depart` seconds after midnight of `day`, with at most `maxTransfers` transfers (RAPTOR).
 * With `mustRide`, walking the whole way never counts, so the best bus is found even when walking would be quicker.
 */
export function earliest(net: Network, day: Day, depart: number, access: Map<number, number>, egress: Map<number, number>, maxTransfers = 2, mustRide = false): Journey | null {
  const f = net.file
  const n = f.stops.length
  const rounds = maxTransfers + 1
  const today = f.services.map((_, i) => runs(f, i, day))
  const yesterday = f.services.map((_, i) => runs(f, i, previousDay(day)))
  const tau: Float64Array[] = [new Float64Array(n).fill(Infinity)]
  const best = new Float64Array(n).fill(Infinity)
  type Label = { kind: 'bus'; pattern: number; ref: TripRef; board: number; alight: number } | { kind: 'walk'; from: number; secs: number }
  const labels: (Label | null)[][] = [new Array(n).fill(null)]
  let marked = new Set<number>()
  for (const [s, w] of access) {
    const t = depart + w
    if (t < tau[0][s]) {
      tau[0][s] = t
      if (!mustRide) best[s] = t
      marked.add(s)
    }
  }
  let target = Infinity
  if (!mustRide) for (const [s, w] of egress) target = Math.min(target, tau[0][s] + w)

  const time = (pi: number, ref: TripRef, pos: number) => {
    const p = f.patterns[pi]
    const [, start, prof] = p.t[ref.trip]
    return start + p.p[prof][pos] - ref.shift
  }
  const earliestTrip = (pi: number, pos: number, after: number): TripRef | null => {
    const p = f.patterns[pi]
    let found: TripRef | null = null
    let foundAt = Infinity
    for (let i = 0; i < p.t.length; i++) {
      const [svc, start, prof] = p.t[i]
      for (const [ok, shift] of [[today[svc], 0], [yesterday[svc], 86400]] as const) {
        if (!ok) continue
        const dep = start + p.p[prof][pos] - shift
        if (dep >= after && dep < foundAt) {
          found = { trip: i, shift }
          foundAt = dep
        }
      }
    }
    return found
  }

  for (let k = 1; k <= rounds && marked.size; k++) {
    tau.push(Float64Array.from(tau[k - 1]))
    labels.push(new Array(n).fill(null))
    const queue = new Map<number, number>()
    for (const s of marked) for (const [pi, pos] of net.at[s]) queue.set(pi, Math.min(queue.get(pi) ?? Infinity, pos))
    const improved = new Set<number>()
    for (const [pi, from] of queue) {
      const p = f.patterns[pi]
      let ref: TripRef | null = null
      let board = -1
      for (let pos = from; pos < p.s.length; pos++) {
        const s = p.s[pos]
        if (ref && !p.nd?.[pos]) {
          const arr = time(pi, ref, pos)
          if (arr < Math.min(best[s], target)) {
            tau[k][s] = arr
            best[s] = arr
            labels[k][s] = { kind: 'bus', pattern: pi, ref, board, alight: pos }
            improved.add(s)
          }
        }
        if (!p.np?.[pos] && tau[k - 1][s] < Infinity && (!ref || tau[k - 1][s] <= time(pi, ref, pos))) {
          const next = earliestTrip(pi, pos, tau[k - 1][s])
          if (next && (!ref || time(pi, next, pos) < time(pi, ref, pos))) {
            ref = next
            board = pos
          }
        }
      }
    }
    marked = new Set(improved)
    for (const s of improved) {
      for (const [q, w] of net.near[s]) {
        const t = tau[k][s] + w
        if (t < Math.min(best[q], target)) {
          tau[k][q] = t
          best[q] = t
          labels[k][q] = { kind: 'walk', from: s, secs: w }
          marked.add(q)
        }
      }
    }
    for (const [s, w] of egress) if (!mustRide || labels[k][s]) target = Math.min(target, tau[k][s] + w)
  }

  // the best arrival, with the fewest transfers on a tie
  let end = -1
  let endK = -1
  let arrive = Infinity
  for (let k = 1; k < tau.length; k++) {
    for (const [s, w] of egress) {
      if (labels[k][s] === null) continue
      const t = tau[k][s] + w
      if (t < arrive - 0.5) {
        arrive = t
        end = s
        endK = k
      }
    }
  }
  if (end < 0) return null
  const legs: Leg[] = []
  let stop = end
  let k = endK
  while (k > 0) {
    const lab = labels[k][stop]
    if (!lab) break
    if (lab.kind === 'walk') {
      legs.unshift({ kind: 'walk', from: lab.from, to: stop, seconds: lab.secs, departs: tau[k][lab.from], arrives: tau[k][stop] })
      stop = lab.from
      continue
    }
    const p = f.patterns[lab.pattern]
    legs.unshift({ kind: 'bus', pattern: lab.pattern, trip: lab.ref.trip, shift: lab.ref.shift, board: lab.board, alight: lab.alight, departs: time(lab.pattern, lab.ref, lab.board), arrives: time(lab.pattern, lab.ref, lab.alight) })
    stop = p.s[lab.board]
    k -= 1
  }
  const first = legs[0]
  const firstStop = first.kind === 'bus' ? f.patterns[first.pattern].s[first.board] : first.from!
  const accessSecs = access.get(firstStop) ?? 0
  const lastStop = (() => {
    const last = legs[legs.length - 1]
    return last.kind === 'bus' ? f.patterns[last.pattern].s[last.alight] : last.to!
  })()
  const egressSecs = egress.get(lastStop) ?? 0
  const firstBus = legs.find((l) => l.kind === 'bus') as Extract<Leg, { kind: 'bus' }>
  const leave = (legs[0].kind === 'bus' ? firstBus.departs : legs[0].departs) - accessSecs
  legs.unshift({ kind: 'walk', from: null, to: firstStop, seconds: accessSecs, departs: leave, arrives: leave + accessSecs })
  const lastArr = legs[legs.length - 1].arrives
  legs.push({ kind: 'walk', from: lastStop, to: null, seconds: egressSecs, departs: lastArr, arrives: lastArr + egressSecs })
  return { departs: leave, arrives: lastArr + egressSecs, legs, transfers: legs.filter((l) => l.kind === 'bus').length - 1 }
}

/** A few journeys leaving at or after `depart`, each catching a later first bus than the one before. */
export function leaveAt(net: Network, day: Day, depart: number, access: Map<number, number>, egress: Map<number, number>, count = 3, mustRide = false): Journey[] {
  const out: Journey[] = []
  let t = depart
  for (let i = 0; i < count; i++) {
    const j = earliest(net, day, t, access, egress, 2, mustRide)
    if (!j || out.some((o) => o.arrives === j.arrives && o.departs === j.departs)) break
    out.push(j)
    const firstBus = j.legs.find((l) => l.kind === 'bus')!
    const walkIn = j.legs[0].kind === 'walk' ? j.legs[0].seconds : 0
    t = firstBus.departs - walkIn + 60
  }
  return out
}

/**
 * Journeys that get there by `deadline`, latest departure first: one search per five minutes over the two hours before,
 * never leaving before `earliestStart` (now), so a bus that has already gone is never offered.
 */
export function arriveBy(net: Network, day: Day, deadline: number, access: Map<number, number>, egress: Map<number, number>, count = 3, earliestStart = -Infinity, mustRide = false): Journey[] {
  const found = new Map<string, Journey>()
  for (let t = Math.max(deadline - 150 * 60, earliestStart); t <= deadline; t += 300) {
    const j = earliest(net, day, t, access, egress, 2, mustRide)
    if (!j || j.arrives > deadline) continue
    const key = j.legs.filter((l) => l.kind === 'bus').map((l) => `${(l as { pattern: number }).pattern}:${(l as { trip: number }).trip}`).join('>')
    const prev = found.get(key)
    if (j.departs >= earliestStart && (!prev || j.departs > prev.departs)) found.set(key, j)
  }
  return [...found.values()].sort((a, b) => b.departs - a.departs).slice(0, count)
}

/** Stops within `radius` metres of a point, with an estimated walking time (straight line with a detour). */
export function stopsNear(net: Network, lat: number, lon: number, radius = 1200, max = 12): Map<number, number> {
  const list: [number, number][] = []
  net.file.stops.forEach((s, i) => {
    if (Math.abs(s[2] - lat) > 0.02) return
    const d = haversine(lat, lon, s[2], s[3])
    if (d <= radius) list.push([i, Math.round((d * DETOUR) / WALK_SPEED)])
  })
  return new Map(list.sort((a, b) => a[1] - b[1]).slice(0, max))
}
