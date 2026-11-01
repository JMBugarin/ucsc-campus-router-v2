import type { Place } from '../data/types'
import { haversine, nearestNode, route, type Graph, type RouteResult } from './graph'

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
export interface Plan {
  route: RouteResult
  /** [lat, lon] of the points the walker actually leaves from and arrives at, and the graph nodes they snap to */
  originPoint: [number, number]
  destPoint: [number, number]
  originSnap: number
  destSnap: number
  connectorMeters: number
  /** avoid-stairs was requested but every mapped route between the places uses stairs */
  stairsUnavoidable?: boolean
  meters: number
  seconds: number
}

function candidates(e: Endpoint): [number, number][] {
  const pts: [number, number][] = e.entrances?.length ? e.entrances.slice(0, 6) : []
  return pts.length ? pts : [[e.lat, e.lon]]
}

export function planRoute(g: Graph, a: Endpoint, b: Endpoint, opt: { avoidStairs?: boolean } = {}): Plan | { error: PlanError } {
  if (a.id === b.id) return { error: 'same-place' }
  const oc = candidates(a).map((p) => ({ p, ...nearestNode(g, p[0], p[1]) }))
  const dc = candidates(b).map((p) => ({ p, ...nearestNode(g, p[0], p[1]) }))
  const oOk = oc.filter((c) => c.dist <= MAX_SNAP_M)
  const dOk = dc.filter((c) => c.dist <= MAX_SNAP_M)
  if (!oOk.length) return { error: 'no-path-near-origin' }
  if (!dOk.length) return { error: 'no-path-near-destination' }
  let best: Plan | null = null
  for (const o of oOk) {
    for (const d of dOk) {
      const r = o.node === d.node ? { nodes: [o.node], meters: 0, seconds: 0, gain: 0, loss: 0, steps: [], stairsMeters: 0, hasStairs: false } : route(g, o.node, d.node, opt)
      if (!r) continue
      const conn = o.dist + d.dist
      const seconds = r.seconds + conn / CONNECTOR_SPEED
      if (!best || seconds < best.seconds) {
        best = { route: r, originPoint: o.p, destPoint: d.p, originSnap: o.node, destSnap: d.node, connectorMeters: conn, meters: r.meters + conn, seconds }
      }
    }
  }
  if (best) return best
  if (opt.avoidStairs) {
    const fallback = planRoute(g, a, b, {})
    return 'error' in fallback ? fallback : { ...fallback, stairsUnavoidable: true }
  }
  return { error: 'no-route' }
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

export function routeGeoJSON(g: Graph, plan: Plan) {
  const coords = plan.route.nodes.map((n) => [g.lon[n], g.lat[n]])
  // split into per-kind runs so each can be styled on its own
  const features: GeoJSON.Feature<GeoJSON.LineString>[] = []
  const kinds = kindsAlong(g, plan.route.nodes)
  let start = 0
  for (let i = 1; i <= kinds.length; i++) {
    if (i === kinds.length || kinds[i] !== kinds[start]) {
      features.push({ type: 'Feature', properties: { kind: kinds[start] }, geometry: { type: 'LineString', coordinates: coords.slice(start, i + 1) } })
      start = i
    }
  }
  const conn: GeoJSON.Feature<GeoJSON.LineString>[] = [
    { type: 'Feature', properties: { kind: 'connector' }, geometry: { type: 'LineString', coordinates: [[plan.originPoint[1], plan.originPoint[0]], coords[0]] } },
    { type: 'Feature', properties: { kind: 'connector' }, geometry: { type: 'LineString', coordinates: [coords[coords.length - 1], [plan.destPoint[1], plan.destPoint[0]]] } },
  ]
  return { type: 'FeatureCollection' as const, features: [...features, ...conn] }
}

function kindsAlong(g: Graph, nodes: number[]): number[] {
  const out: number[] = []
  for (let i = 0; i + 1 < nodes.length; i++) {
    const a = nodes[i]
    const b = nodes[i + 1]
    let k = 0
    for (let e = g.off[a]; e < g.off[a + 1]; e++) if (g.to[e] === b) { k = g.kind[e]; break }
    out.push(k)
  }
  return out
}
