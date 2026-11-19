import type { Graph } from '../routing/graph'
import { haversine, nearestOnEdges } from '../routing/graph'
import { MAX_SNAP_M, planRoute, routeGeoJSON, type Endpoint, type Plan } from '../routing/plan'
import { arriveBy, leaveAt, stopsNear, DETOUR, WALK_SPEED, type Day, type Journey, type Network } from './raptor'
import { pacificClock } from './schedule'

export type When = { kind: 'leave'; at: number } | { kind: 'arrive'; by: number }

export interface WalkPart {
  kind: 'walk'
  seconds: number
  /** off the mapped campus paths the time comes from a straight line with a detour */
  approximate: boolean
  plan?: Plan
  from: [number, number]
  to: [number, number]
  toName: string
}
export interface BusPart {
  kind: 'bus'
  route: string
  headsign: string
  tripId: string
  boardStop: string
  boardName: string
  alightStop: string
  alightName: string
  departs: number
  arrives: number
  stops: [number, number][]
}
export interface TripOption {
  /** epoch ms */
  leave: number
  arrive: number
  parts: (WalkPart | BusPart)[]
  transfers: number
}

const onCampus = (g: Graph, lat: number, lon: number) => (nearestOnEdges(g, lat, lon)?.dist ?? Infinity) <= MAX_SNAP_M
const stopEndpoint = (net: Network, i: number): Endpoint => ({ id: `metro-${net.file.stops[i][0]}`, name: net.file.stops[i][1], lat: net.file.stops[i][2], lon: net.file.stops[i][3] })

/** Seconds to walk between a place and each nearby stop: on the campus paths where they are mapped, else estimated. */
function walksToStops(net: Network, g: Graph, place: Endpoint, outbound: boolean, avoidStairs: boolean) {
  const campus = onCampus(g, place.lat, place.lon)
  const near = stopsNear(net, place.lat, place.lon, campus ? 900 : 1200, campus ? 8 : 12)
  const secs = new Map<number, number>()
  const plans = new Map<number, Plan>()
  for (const [s, est] of near) {
    if (!campus || !onCampus(g, net.file.stops[s][2], net.file.stops[s][3])) {
      secs.set(s, est)
      continue
    }
    const stop = stopEndpoint(net, s)
    const p = outbound ? planRoute(g, place, stop, { avoidStairs }) : planRoute(g, stop, place, { avoidStairs })
    if ('error' in p) secs.set(s, est)
    else {
      secs.set(s, Math.round(p.seconds))
      plans.set(s, p)
    }
  }
  return { secs, plans, campus }
}

/** Bus trips between two places, any distance within METRO's area: leaving at a time, or arriving by one. */
export function planTrips(net: Network, g: Graph, from: Endpoint, to: Endpoint, when: When, avoidStairs = false): TripOption[] {
  const access = walksToStops(net, g, from, true, avoidStairs)
  const egress = walksToStops(net, g, to, false, avoidStairs)
  if (!access.secs.size || !egress.secs.size) return []
  const at = when.kind === 'leave' ? when.at : when.by
  const clock = pacificClock(new Date(at))
  const day: Day = { date: clock.date, dow: clock.dow }
  const midnight = at - clock.secs * 1000
  const journeys: Journey[] = when.kind === 'leave' ? leaveAt(net, day, clock.secs, access.secs, egress.secs) : arriveBy(net, day, clock.secs, access.secs, egress.secs)
  const f = net.file
  return journeys.map((j) => {
    const parts: (WalkPart | BusPart)[] = []
    for (let i = 0; i < j.legs.length; i++) {
      const l = j.legs[i]
      if (l.kind === 'bus') {
        const p = f.patterns[l.pattern]
        const b = p.s[l.board]
        const a = p.s[l.alight]
        parts.push({
          kind: 'bus',
          route: f.routes[p.r]?.[0] ?? p.r,
          headsign: p.h,
          tripId: p.t[l.trip][3],
          boardStop: f.stops[b][0],
          boardName: f.stops[b][1],
          alightStop: f.stops[a][0],
          alightName: f.stops[a][1],
          departs: midnight + l.departs * 1000,
          arrives: midnight + l.arrives * 1000,
          stops: p.s.slice(l.board, l.alight + 1).map((s) => [f.stops[s][2], f.stops[s][3]] as [number, number]),
        })
        continue
      }
      const fromPt: [number, number] = l.from === null ? [from.lat, from.lon] : [f.stops[l.from][2], f.stops[l.from][3]]
      const toPt: [number, number] = l.to === null ? [to.lat, to.lon] : [f.stops[l.to][2], f.stops[l.to][3]]
      const plan = l.from === null && l.to !== null ? access.plans.get(l.to) : l.to === null && l.from !== null ? egress.plans.get(l.from) : undefined
      if (l.seconds < 1 && i > 0 && i < j.legs.length - 1) continue
      parts.push({ kind: 'walk', seconds: l.seconds, approximate: !plan, plan, from: fromPt, to: toPt, toName: l.to === null ? to.name : f.stops[l.to][1] })
    }
    return { leave: midnight + j.departs * 1000, arrive: midnight + j.arrives * 1000, parts, transfers: j.transfers }
  })
}

/** Walking estimate between two points where no mapped path joins them. */
export const estimateWalk = (a: [number, number], b: [number, number]) => Math.round((haversine(a[0], a[1], b[0], b[1]) * DETOUR) / WALK_SPEED)

/** The trip as map lines: walks along their paths (or dotted where estimated) and each bus through its stops. */
export function tripGeoJSON(g: Graph, trip: TripOption) {
  const features: GeoJSON.Feature<GeoJSON.LineString>[] = []
  for (const p of trip.parts) {
    if (p.kind === 'bus') features.push({ type: 'Feature', properties: { kind: 'bus' }, geometry: { type: 'LineString', coordinates: p.stops.map(([la, lo]) => [lo, la]) } })
    else if (p.plan) features.push(...routeGeoJSON(g, p.plan).features)
    else features.push({ type: 'Feature', properties: { kind: 'connector' }, geometry: { type: 'LineString', coordinates: [[p.from[1], p.from[0]], [p.to[1], p.to[0]]] } })
  }
  return { type: 'FeatureCollection' as const, features }
}
