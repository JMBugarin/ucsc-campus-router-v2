import { haversine, type Graph } from '../routing/graph'
import { planRoute, type Endpoint } from '../routing/plan'
import { previousDay, serviceRuns, type Clock, type TransitData } from './schedule'

const NEAR_M = 650
const MAX_STOPS = 5

export interface BusOption {
  route: string
  headsign: string
  tripId: string
  board: number // stop index
  alight: number
  walkToStop: number // seconds
  walkFromStop: number
  departs: number // seconds after midnight, campus time
  rides: number // arrival at the alighting stop
  arrives: number // arrival at the destination, walking included
}
export interface BusPlan {
  options: BusOption[]
  walkOnlyArrives: number | null
  walkOnlySeconds: number | null
}

function nearby(data: TransitData, lat: number, lon: number): number[] {
  return data.stops
    .map((s, i) => ({ i, d: haversine(lat, lon, s.lat, s.lon) }))
    .filter((x) => x.d <= NEAR_M)
    .sort((a, b) => a.d - b.d)
    .slice(0, MAX_STOPS)
    .map((x) => x.i)
}
const asEndpoint = (s: TransitData['stops'][number]): Endpoint => ({ id: 'stop-' + s.id, name: s.name, lat: s.lat, lon: s.lon })

/** Direct METRO trips that beat walking, using only the campus stops in the schedule. */
export function busOptions(g: Graph, data: TransitData, from: Endpoint, to: Endpoint, now: Clock, avoidStairs = false): BusPlan {
  const fromPt = from.entrances?.[0] ?? [from.lat, from.lon]
  const toPt = to.entrances?.[0] ?? [to.lat, to.lon]
  const walkOnly = planRoute(g, from, to, { avoidStairs })
  const walkOnlySeconds = 'error' in walkOnly ? null : walkOnly.seconds
  const boards = nearby(data, fromPt[0], fromPt[1])
  const alights = nearby(data, toPt[0], toPt[1])
  const walk = (a: Endpoint, b: Endpoint) => {
    const p = planRoute(g, a, b, { avoidStairs })
    return 'error' in p ? null : p.seconds
  }
  const toStop = new Map<number, number>()
  const fromStop = new Map<number, number>()
  for (const i of boards) { const w = walk(from, asEndpoint(data.stops[i])); if (w !== null) toStop.set(i, w) }
  for (const i of alights) { const w = walk(asEndpoint(data.stops[i]), to); if (w !== null) fromStop.set(i, w) }

  const yesterday = previousDay(now)
  const runs = data.services.map((_, i) => [serviceRuns(data, i, now), serviceRuns(data, i, yesterday)])
  const found: BusOption[] = []
  for (const trip of data.trips) {
    for (const [day, shift] of [[0, 0], [1, 86400]] as const) {
      if (!runs[trip.s][day]) continue
      let best: BusOption | null = null
      for (let a = 0; a < trip.t.length; a++) {
        const w1 = toStop.get(trip.t[a][0])
        if (w1 === undefined) continue
        const dep = trip.t[a][1] - shift
        if (dep < now.secs + w1) continue
        for (let b = a + 1; b < trip.t.length; b++) {
          const w2 = fromStop.get(trip.t[b][0])
          if (w2 === undefined) continue
          const rides = trip.t[b][1] - shift
          const arrives = rides + w2
          if (!best || arrives < best.arrives) best = { route: trip.r, headsign: trip.h, tripId: trip.i, board: trip.t[a][0], alight: trip.t[b][0], walkToStop: w1, walkFromStop: w2, departs: dep, rides, arrives }
        }
      }
      if (best) found.push(best)
    }
  }
  found.sort((x, y) => x.arrives - y.arrives)
  const walkOnlyArrives = walkOnlySeconds === null ? null : now.secs + walkOnlySeconds
  const useful = found.filter((o) => walkOnlyArrives === null || o.arrives < walkOnlyArrives - 120)
  // one option per route and departure, soonest finishing first
  const seen = new Set<string>()
  const options = useful.filter((o) => (seen.has(o.route + o.departs) ? false : (seen.add(o.route + o.departs), true))).slice(0, 3)
  return { options, walkOnlyArrives, walkOnlySeconds }
}
