import type { Graph } from '../routing/graph'
import { haversine, nearestOnEdges } from '../routing/graph'
import { MAX_SNAP_M, planRoute, routeGeoJSON, walkSeconds, type Endpoint, type Plan, type RouteFeature } from '../routing/plan'
import { smoothLine } from '../routing/smooth'
import { arriveBy, leaveAt, stopsNear, DETOUR, WALK_SPEED, type Day, type Journey, type Network } from './raptor'
import { pacificClock } from './schedule'

/** `now` keeps arrive-by from offering buses that have already left. */
export type When = { kind: 'leave'; at: number } | { kind: 'arrive'; by: number; now: number }

export interface WalkPart {
  kind: 'walk'
  seconds: number
  /** with no mapped way to follow, the time comes from a straight line with a detour */
  approximate: boolean
  /** campus paths, or streets in town */
  on?: 'campus' | 'town'
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
  /** the path the bus drives, along its route */
  line: [number, number][]
}
/** The bus's path between two of its stops: along the route's shape where METRO publishes one, else stop to stop. */
export function busLine(net: Network, pattern: number, board: number, alight: number): [number, number][] {
  const f = net.file
  const p = f.patterns[pattern]
  const stopAt = (i: number): [number, number] => [f.stops[p.s[i]][2], f.stops[p.s[i]][3]]
  const shape = p.g !== undefined && p.gi ? f.shapes?.[p.g] : undefined
  if (!shape || !p.gi) return p.s.slice(board, alight + 1).map((_, k) => stopAt(board + k))
  const from = p.gi[board]
  const to = p.gi[alight]
  const mid: [number, number][] = []
  for (let i = from + 1; i < to; i++) mid.push([shape[2 * i], shape[2 * i + 1]])
  return [stopAt(board), ...mid, stopAt(alight)]
}

export interface TripOption {
  /** epoch ms */
  leave: number
  arrive: number
  /** arrives after the time it was asked to arrive by */
  late: boolean
  parts: (WalkPart | BusPart)[]
  transfers: number
}

const onCampus = (g: Graph, lat: number, lon: number) => (nearestOnEdges(g, lat, lon)?.dist ?? Infinity) <= MAX_SNAP_M
const stopEndpoint = (net: Network, i: number): Endpoint => ({ id: `metro-${net.file.stops[i][0]}`, name: net.file.stops[i][1], lat: net.file.stops[i][2], lon: net.file.stops[i][3] })

/** Seconds to walk between a place and each nearby stop: on the campus paths or town streets where mapped, else estimated. */
function walksToStops(net: Network, g: Graph, place: Endpoint, outbound: boolean, avoidStairs: boolean, town: Graph | null) {
  const campus = onCampus(g, place.lat, place.lon)
  const near = stopsNear(net, place.lat, place.lon, campus ? 900 : 1200, campus ? 8 : 12)
  const secs = new Map<number, number>()
  const plans = new Map<number, Plan>()
  if (!campus && town) {
    const list = [...near.keys()]
    const times = walkSeconds(town, [place.lat, place.lon], list.map((s) => [net.file.stops[s][2], net.file.stops[s][3]]))
    list.forEach((s, i) => secs.set(s, Number.isFinite(times[i]) ? Math.round(times[i]) : near.get(s)!))
    return { secs, plans, campus, town: Number.isFinite(Math.min(...times)) }
  }
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
  return { secs, plans, campus, town: false }
}

/** Bus trips between two places, any distance within METRO's area: leaving at a time, or arriving by one. */
export function planTrips(net: Network, g: Graph, from: Endpoint, to: Endpoint, when: When, avoidStairs = false, town: Graph | null = null): TripOption[] {
  const access = walksToStops(net, g, from, true, avoidStairs, town)
  const egress = walksToStops(net, g, to, false, avoidStairs, town)
  if (!access.secs.size || !egress.secs.size) return []
  const at = when.kind === 'leave' ? when.at : when.by
  const clock = pacificClock(new Date(at))
  const day: Day = { date: clock.date, dow: clock.dow }
  const midnight = at - clock.secs * 1000
  let journeys: Journey[]
  if (when.kind === 'leave') journeys = leaveAt(net, day, clock.secs, access.secs, egress.secs)
  else {
    const nowSecs = Math.floor((when.now - midnight) / 1000)
    journeys = arriveBy(net, day, clock.secs, access.secs, egress.secs, 3, nowSecs)
    // nothing makes it in time any more: the soonest trips from now, which will be late
    if (!journeys.length) journeys = leaveAt(net, day, Math.max(nowSecs, 0), access.secs, egress.secs)
  }
  const deadline = when.kind === 'arrive' ? when.by : Infinity
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
          line: busLine(net, l.pattern, l.board, l.alight),
        })
        continue
      }
      const fromPt: [number, number] = l.from === null ? [from.lat, from.lon] : [f.stops[l.from][2], f.stops[l.from][3]]
      const toPt: [number, number] = l.to === null ? [to.lat, to.lon] : [f.stops[l.to][2], f.stops[l.to][3]]
      let plan = l.from === null && l.to !== null ? access.plans.get(l.to) : l.to === null && l.from !== null ? egress.plans.get(l.from) : undefined
      let on: WalkPart['on'] = plan ? 'campus' : undefined
      // in town, the walk to or from the stop follows the streets
      const townEnd = (l.from === null && access.town) || (l.to === null && egress.town)
      if (!plan && town && townEnd) {
        const stopIdx = (l.from === null ? l.to : l.from)!
        const stop = { id: `metro-${f.stops[stopIdx][0]}`, name: f.stops[stopIdx][1], lat: f.stops[stopIdx][2], lon: f.stops[stopIdx][3] }
        const p = l.from === null ? planRoute(town, from, stop) : planRoute(town, stop, to)
        if (!('error' in p)) {
          plan = p
          on = 'town'
        }
      }
      if (l.seconds < 1 && i > 0 && i < j.legs.length - 1) continue
      parts.push({ kind: 'walk', seconds: l.seconds, approximate: !plan, on, plan, from: fromPt, to: toPt, toName: l.to === null ? to.name : f.stops[l.to][1] })
    }
    const arrive = midnight + j.arrives * 1000
    return { leave: midnight + j.departs * 1000, arrive, late: arrive > deadline, parts, transfers: j.transfers }
  })
}

/** Walking estimate between two points where no mapped path joins them. */
export const estimateWalk = (a: [number, number], b: [number, number]) => Math.round((haversine(a[0], a[1], b[0], b[1]) * DETOUR) / WALK_SPEED)

/** The trip as map features: walks along their paths (dotted where estimated) and each bus along its road. */
export function tripGeoJSON(g: Graph, trip: TripOption) {
  const features: RouteFeature[] = []
  for (const p of trip.parts) {
    if (p.kind === 'bus') features.push({ type: 'Feature', properties: { kind: 'bus' }, geometry: { type: 'LineString', coordinates: smoothLine(p.line).map(([la, lo]) => [lo, la]) } })
    else if (p.plan) features.push(...routeGeoJSON(g, p.plan).features)
    else features.push({ type: 'Feature', properties: { kind: 'connector' }, geometry: { type: 'LineString', coordinates: [[p.from[1], p.from[0]], [p.to[1], p.to[0]]] } })
  }
  return { type: 'FeatureCollection' as const, features }
}
