import type { Place } from '../data/types'
import { cutEdge, describePath, edgeIndex, edgeSeconds, haversine, nearestOnEdges, searchFrom, type EdgeKind, type EdgeSnap, type Graph, type RouteResult } from './graph'

export const MAX_SNAP_M = 150
const CONNECTOR_SPEED = 1.3

export interface Endpoint {
  id: string
  name: string
  lat: number
  lon: number
  /** Building doors when known; the route may use whichever is quickest. */
  entrances?: [number, number][]
  isLocation?: boolean
}

export const endpointOf = (p: Place): Endpoint => ({ id: p.id, name: p.name, lat: p.lat, lon: p.lon, entrances: p.entrances })

export type PlanError = 'no-path-near-origin' | 'no-path-near-destination' | 'no-route' | 'same-place'

/** A stretch of the walk along mapped paths, with the real shape of the path. */
export interface Piece {
  kind: EdgeKind
  pts: [number, number][]
}

export interface Plan {
  /** the walk on mapped paths, partial edges at either end included */
  route: RouteResult
  /** [lat, lon] of the door or point the walker leaves from and arrives at */
  originPoint: [number, number]
  destPoint: [number, number]
  /** where those points meet the nearest mapped path */
  originOn: [number, number]
  destOn: [number, number]
  /** first and last graph node on the way, or -1 when the walk stays on one path */
  originSnap: number
  destSnap: number
  /** straight, unmapped stretches between a point and its path (approximate; drawn dotted) */
  connectorMeters: number
  path: Piece[]
  /** avoid-stairs was requested but every mapped route between the places uses stairs */
  stairsUnavoidable?: boolean
  meters: number
  seconds: number
}

function candidates(e: Endpoint): [number, number][] {
  const pts: [number, number][] = e.entrances?.length ? e.entrances.slice(0, 6) : []
  return pts.length ? pts : [[e.lat, e.lon]]
}

const edgeLen = (g: Graph, a: number, b: number) => {
  const e = edgeIndex(g, a, b)
  return e >= 0 ? g.len[e] : g.len[edgeIndex(g, b, a)]
}
/** Seconds to walk part of edge a-b, from a fraction `from` to a fraction `to` of its length from a. */
function partSeconds(g: Graph, a: number, b: number, from: number, to: number): number {
  const forward = to >= from
  const e = forward ? edgeIndex(g, a, b) : edgeIndex(g, b, a)
  const e2 = e >= 0 ? e : forward ? edgeIndex(g, b, a) : edgeIndex(g, a, b)
  return Math.abs(to - from) * edgeSeconds(g, forward ? a : b, e2)
}
const kindOf = (g: Graph, a: number, b: number) => {
  const e = edgeIndex(g, a, b)
  return g.kind[e >= 0 ? e : edgeIndex(g, b, a)] as EdgeKind
}

/** The fastest walk between two places: from wherever each meets the mapped paths, along the real shape of the paths. */
export function planRoute(g: Graph, a: Endpoint, b: Endpoint, opt: { avoidStairs?: boolean } = {}): Plan | { error: PlanError } {
  if (a.id === b.id) return { error: 'same-place' }
  const snap = (p: [number, number]) => ({ p, s: nearestOnEdges(g, p[0], p[1]) })
  const ok = (c: { s: EdgeSnap | null }): c is { p: [number, number]; s: EdgeSnap } => !!c.s && c.s.dist <= MAX_SNAP_M
  const oOk = candidates(a).map(snap).filter(ok)
  const dOk = candidates(b).map(snap).filter(ok)
  if (!oOk.length) return { error: 'no-path-near-origin' }
  if (!dOk.length) return { error: 'no-path-near-destination' }

  type Best = { seconds: number; o: (typeof oOk)[number]; d: (typeof dOk)[number]; start: number; end: number; prevNode: Int32Array | null; prevEdge: Int32Array | null }
  let best: Best | null = null
  for (const o of oOk) {
    const { a: oa, b: ob, t } = o.s
    const seeds = new Map<number, number>([
      [oa, partSeconds(g, oa, ob, t, 0)],
      [ob, partSeconds(g, oa, ob, t, 1)],
    ])
    const { cost, prevNode, prevEdge } = searchFrom(g, seeds, opt)
    for (const d of dOk) {
      const conn = (o.s.dist + d.s.dist) / CONNECTOR_SPEED
      const { a: da, b: db, t: s } = d.s
      const options: [number, number, number][] = [
        [cost[da] + partSeconds(g, da, db, 0, s), da, da],
        [cost[db] + partSeconds(g, da, db, 1, s), db, db],
      ]
      if (Math.min(oa, ob) === Math.min(da, db) && Math.max(oa, ob) === Math.max(da, db)) {
        const s2 = da === oa ? s : 1 - s
        options.push([partSeconds(g, oa, ob, t, s2), -1, -1])
      }
      for (const [sec, end] of options) {
        if (!Number.isFinite(sec)) continue
        const total = sec + conn
        if (!best || total < best.seconds) {
          let start = -1
          if (end >= 0) for (start = end; prevNode[start] !== -1; start = prevNode[start]);
          best = { seconds: total, o, d, start, end, prevNode: end >= 0 ? prevNode : null, prevEdge: end >= 0 ? prevEdge : null }
        }
      }
    }
  }
  if (!best) {
    if (opt.avoidStairs) {
      const fallback = planRoute(g, a, b, {})
      return 'error' in fallback ? fallback : { ...fallback, stairsUnavoidable: true }
    }
    return { error: 'no-route' }
  }
  return assemble(g, best)
}

function assemble(
  g: Graph,
  best: { seconds: number; o: { p: [number, number]; s: EdgeSnap }; d: { p: [number, number]; s: EdgeSnap }; start: number; end: number; prevNode: Int32Array | null; prevEdge: Int32Array | null },
): Plan {
  const { o, d, start, end } = best
  const path: Piece[] = []
  let route: RouteResult
  let extraMeters = 0
  let extraGain = 0
  let extraLoss = 0
  const climb = (from: number, to: number, fraction: number) => {
    const rise = (g.ele[to] - g.ele[from]) * fraction
    if (rise > 0) extraGain += rise
    else extraLoss -= rise
  }
  if (end < 0) {
    // both ends on the same path
    const { a, b, t } = o.s
    const s2 = d.s.a === a ? d.s.t : 1 - d.s.t
    const k = kindOf(g, a, b)
    path.push({ kind: k, pts: cutEdge(g, a, b, t, s2) })
    const m = Math.abs(s2 - t) * edgeLen(g, a, b)
    climb(s2 > t ? a : b, s2 > t ? b : a, Math.abs(s2 - t))
    route = { nodes: [], meters: m, seconds: 0, gain: 0, loss: 0, steps: [{ kind: k, meters: m, seconds: 0 }], stairsMeters: k === 1 ? m : 0, hasStairs: k === 1 }
  } else {
    const nodes: number[] = []
    const edges: number[] = []
    for (let v = end; v !== -1; v = best.prevNode![v]) {
      nodes.push(v)
      if (best.prevEdge![v] >= 0) edges.push(best.prevEdge![v])
    }
    nodes.reverse()
    edges.reverse()
    route = describePath(g, nodes, edges, 0)
    const { a: oa, b: ob, t } = o.s
    const startFrac = start === oa ? t : 1 - t
    const startKind = kindOf(g, oa, ob)
    const startM = startFrac * edgeLen(g, oa, ob)
    climb(start === oa ? ob : oa, start, startFrac)
    const { a: da, b: db, t: s } = d.s
    const endFrac = end === da ? s : 1 - s
    const endKind = kindOf(g, da, db)
    const endM = endFrac * edgeLen(g, da, db)
    climb(end, end === da ? db : da, endFrac)
    if (startM > 0.5) path.push({ kind: startKind, pts: cutEdge(g, oa, ob, t, start === oa ? 0 : 1) })
    for (let i = 0; i + 1 < nodes.length; i++) {
      const pts = cutEdge(g, nodes[i], nodes[i + 1], 0, 1)
      path.push({ kind: g.kind[edges[i]] as EdgeKind, pts })
    }
    if (endM > 0.5) path.push({ kind: endKind, pts: cutEdge(g, da, db, end === da ? 0 : 1, s) })
    const steps = [...route.steps]
    const addStep = (kind: EdgeKind, m: number, atStart: boolean) => {
      if (m <= 0.5) return
      const at = atStart ? 0 : steps.length - 1
      if (steps[at]?.kind === kind) steps[at] = { ...steps[at], meters: steps[at].meters + m }
      else if (atStart) steps.unshift({ kind, meters: m, seconds: 0 })
      else steps.push({ kind, meters: m, seconds: 0 })
    }
    addStep(startKind, startM, true)
    addStep(endKind, endM, false)
    extraMeters = startM + endM
    const stairs = (startKind === 1 ? startM : 0) + (endKind === 1 ? endM : 0)
    route = { ...route, steps, meters: route.meters + extraMeters, stairsMeters: route.stairsMeters + stairs, hasStairs: route.stairsMeters + stairs > 0 }
  }
  route = { ...route, gain: route.gain + extraGain, loss: route.loss + extraLoss, seconds: best.seconds }
  const connectorMeters = o.s.dist + d.s.dist
  return {
    route,
    originPoint: o.p,
    destPoint: d.p,
    originOn: o.s.point,
    destOn: d.s.point,
    originSnap: start,
    destSnap: end,
    connectorMeters,
    path,
    meters: route.meters + connectorMeters,
    seconds: best.seconds,
  }
}

/** Walking seconds from one point to each of several points, from a single search (Infinity where no path joins them). */
export function walkSeconds(g: Graph, from: [number, number], targets: [number, number][], opt: { avoidStairs?: boolean } = {}): number[] {
  const o = nearestOnEdges(g, from[0], from[1])
  if (!o || o.dist > MAX_SNAP_M) return targets.map(() => Infinity)
  const { cost } = searchFrom(
    g,
    new Map([
      [o.a, partSeconds(g, o.a, o.b, o.t, 0)],
      [o.b, partSeconds(g, o.a, o.b, o.t, 1)],
    ]),
    opt,
  )
  return targets.map(([la, lo]) => {
    const d = nearestOnEdges(g, la, lo)
    if (!d || d.dist > MAX_SNAP_M) return Infinity
    const along = Math.min(cost[d.a] + partSeconds(g, d.a, d.b, 0, d.t), cost[d.b] + partSeconds(g, d.a, d.b, 1, d.t))
    return along + (o.dist + d.dist) / CONNECTOR_SPEED
  })
}

export function straightMeters(a: Endpoint, b: Endpoint): number {
  return haversine(a.lat, a.lon, b.lat, b.lon)
}

export function formatDistance(m: number): string {
  if (m < 1000) return `${Math.round(m / 10) * 10 || Math.round(m)} m`
  return `${(m / 1000).toFixed(m < 10000 ? 2 : 1)} km`
}
export function formatDuration(s: number): string {
  const min = Math.max(1, Math.round(s / 60))
  return min < 60 ? `${min} min` : `${Math.floor(min / 60)} h ${min % 60} min`
}

/** The walk as map lines: each kind of path in its own style, along the real shape, with the unmapped ends dotted. */
export function routeGeoJSON(_g: Graph, plan: Plan) {
  const features: GeoJSON.Feature<GeoJSON.LineString>[] = []
  let run: { kind: EdgeKind; pts: [number, number][] } | null = null
  const flush = () => {
    if (run && run.pts.length > 1) features.push({ type: 'Feature', properties: { kind: run.kind }, geometry: { type: 'LineString', coordinates: run.pts.map(([la, lo]) => [lo, la]) } })
  }
  for (const piece of plan.path) {
    if (run && run.kind === piece.kind) run.pts.push(...piece.pts.slice(1))
    else {
      flush()
      run = { kind: piece.kind, pts: [...piece.pts] }
    }
  }
  flush()
  const line = (x: [number, number], y: [number, number]): GeoJSON.Feature<GeoJSON.LineString> => ({ type: 'Feature', properties: { kind: 'connector' }, geometry: { type: 'LineString', coordinates: [[x[1], x[0]], [y[1], y[0]]] } })
  return { type: 'FeatureCollection' as const, features: [...features, line(plan.originPoint, plan.originOn), line(plan.destOn, plan.destPoint)] }
}

/** Every [lon, lat] the walk passes through, for fitting the camera. */
export const planCoords = (plan: Plan): [number, number][] => [plan.originPoint, ...plan.path.flatMap((p) => p.pts), plan.destPoint].map(([la, lo]) => [lo, la])
