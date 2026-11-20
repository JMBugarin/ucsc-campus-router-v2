import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { buildGraph } from '../src/routing/graph'
import { endpointOf, planRoute, type Plan } from '../src/routing/plan'
import { prepareNetwork, type MetroFile } from '../src/transit/raptor'
import { planTrips, tripGeoJSON } from '../src/transit/trip'
import { parsePointId, pointId, searchAddresses } from '../src/data/geocode'
import type { GraphFile, PlacesFile } from '../src/data/types'

const g = buildGraph(JSON.parse(readFileSync('public/data/graph.json', 'utf8')) as GraphFile)
const places = (JSON.parse(readFileSync('public/data/places.json', 'utf8')) as PlacesFile).places
const net = prepareNetwork(JSON.parse(readFileSync('public/data/metro.json', 'utf8')) as MetroFile)
const be152 = endpointOf(places.find((p) => p.id === 'baskin-engineering-152')!)
const downtown = { id: pointId(36.9719, -122.0263), name: 'Downtown', lat: 36.9719, lon: -122.0263 }
const at = (iso: string) => new Date(iso).getTime()

describe('trips from off campus', () => {
  it('leave now: walk to a stop, ride, walk the campus paths to the room door', () => {
    const trips = planTrips(net, g, downtown, be152, { kind: 'leave', at: at('2026-11-04T08:00:00-08:00') })
    expect(trips.length).toBeGreaterThan(0)
    const t = trips[0]
    expect(t.leave).toBeGreaterThanOrEqual(at('2026-11-04T08:00:00-08:00'))
    expect(t.arrive - t.leave).toBeLessThan(60 * 60_000)
    expect(t.parts[0]).toMatchObject({ kind: 'walk', approximate: true })
    const last = t.parts[t.parts.length - 1]
    expect(last.kind).toBe('walk')
    if (last.kind === 'walk') expect(last.approximate).toBe(false)
    const kinds = tripGeoJSON(g, t).features.map((f) => f.properties?.kind)
    expect(kinds).toContain('bus')
    expect(kinds).toContain('connector')
  })
  it('arrive by a class: every option gets there in time, latest departure first, none already gone', () => {
    const by = at('2026-11-04T09:20:00-08:00')
    const now = at('2026-11-04T08:20:00-08:00')
    const trips = planTrips(net, g, downtown, be152, { kind: 'arrive', by, now })
    expect(trips.length).toBeGreaterThan(0)
    expect(trips.every((t) => t.arrive <= by && !t.late)).toBe(true)
    expect(trips.every((t) => t.leave >= now)).toBe(true)
    for (let i = 1; i < trips.length; i++) expect(trips[i - 1].leave).toBeGreaterThanOrEqual(trips[i].leave)
  })
  it('running late: shows the buses still to come, marked late, never ones that left', () => {
    const by = at('2026-11-04T09:20:00-08:00')
    const now = at('2026-11-04T09:10:00-08:00')
    const trips = planTrips(net, g, downtown, be152, { kind: 'arrive', by, now })
    expect(trips.length).toBeGreaterThan(0)
    expect(trips.every((t) => t.late && t.leave >= now - 60_000)).toBe(true)
    const buses = trips.flatMap((t) => t.parts.filter((p) => p.kind === 'bus'))
    expect(buses.every((b) => b.kind === 'bus' && b.departs >= now)).toBe(true)
  })
  it('after class has started: still the next buses, all late', () => {
    const by = at('2026-11-04T09:20:00-08:00')
    const trips = planTrips(net, g, downtown, be152, { kind: 'arrive', by, now: at('2026-11-04T09:40:00-08:00') })
    expect(trips.length).toBeGreaterThan(0)
    expect(trips.every((t) => t.late && t.leave >= at('2026-11-04T09:39:00-08:00'))).toBe(true)
  })
  it('works the other way, from a room to home', () => {
    expect(planTrips(net, g, be152, downtown, { kind: 'leave', at: at('2026-11-04T17:00:00-08:00') }).length).toBeGreaterThan(0)
  })
})

describe('address search', () => {
  it('reads Photon results into labelled points, and only searches real queries', async () => {
    const get = (async () =>
      new Response(
        JSON.stringify({
          features: [
            { geometry: { coordinates: [-122.0263, 36.9719] }, properties: { name: 'Santa Cruz Metro Center', housenumber: '920', street: 'Pacific Avenue', city: 'Santa Cruz' } },
            { geometry: { coordinates: ['x', 1] }, properties: { name: 'bad' } },
          ],
        }),
      )) as unknown as typeof fetch
    expect(await searchAddresses('metro center', undefined, get)).toEqual([{ label: 'Santa Cruz Metro Center, 920 Pacific Avenue, Santa Cruz', lat: 36.9719, lon: -122.0263 }])
    expect(await searchAddresses('ab', undefined, get)).toEqual([])
  })
  it('round-trips point ids', () => {
    expect(parsePointId(pointId(36.9719, -122.0263))).toEqual([36.9719, -122.0263])
    expect(parsePointId('baskin-engineering')).toBeNull()
  })
})

describe('walking in town', () => {
  const town = buildGraph(JSON.parse(readFileSync('public/data/town.json', 'utf8')) as GraphFile)
  it('routes the walk to the bus along the streets, and draws it', () => {
    const t0 = performance.now()
    const trips = planTrips(net, g, downtown, be152, { kind: 'leave', at: at('2026-11-04T08:00:00-08:00') }, false, town)
    const ms = performance.now() - t0
    const walk = trips[0].parts[0]
    expect(walk.kind).toBe('walk')
    if (walk.kind !== 'walk') return
    expect(walk.on).toBe('town')
    expect(walk.approximate).toBe(false)
    expect(walk.plan?.path.length).toBeGreaterThan(0)
    // the only straight dotted bits left are the short stubs between a point and its street or path
    const stubs = tripGeoJSON(g, trips[0]).features.filter((f) => f.properties?.kind === 'connector')
    for (const f of stubs) {
      const [[lo1, la1], [lo2, la2]] = f.geometry.coordinates as [number, number][]
      expect(Math.hypot((la1 - la2) * 110540, (lo1 - lo2) * 88900)).toBeLessThan(60)
    }
    expect(ms).toBeLessThan(3000)
  })
  it('draws each bus along its route, through its stops', () => {
    const trips = planTrips(net, g, downtown, be152, { kind: 'leave', at: at('2026-11-04T08:00:00-08:00') }, false, town)
    for (const part of trips[0].parts) {
      if (part.kind !== 'bus') continue
      expect(part.line.length).toBeGreaterThan(part.stops.length)
      const near = (p: [number, number]) => Math.min(...part.line.map((q) => Math.hypot((p[0] - q[0]) * 110540, (p[1] - q[1]) * 88900)))
      for (const s of part.stops) expect(near(s)).toBeLessThan(80)
    }
  })
})

describe('the bus for anyone who would rather ride', () => {
  const P = (id: string) => endpointOf(places.find((p) => p.id === id)!)
  const walked = (t: { parts: { kind: string; seconds?: number }[] }) => t.parts.reduce((s, p) => s + (p.kind === 'walk' ? p.seconds! : 0), 0)
  const wed10 = at('2026-11-18T10:00:00-08:00')

  it('offers a bus even when walking gets there sooner, but never one that adds walking', () => {
    const [a, b] = [P('quarry-plaza'), P('baskin-engineering')]
    const walk = planRoute(g, a, b) as Plan
    expect(planTrips(net, g, a, b, { kind: 'leave', at: wed10 })).toEqual([])
    const trips = planTrips(net, g, a, b, { kind: 'leave', at: wed10 }, false, null, { walkOnly: walk.seconds })
    expect(trips.length).toBeGreaterThan(0)
    expect(trips.some((t) => t.arrive > wed10 + walk.seconds * 1000)).toBe(true)
    for (const t of trips) {
      expect(walked(t)).toBeLessThan(walk.seconds)
      expect(t.leave).toBeGreaterThanOrEqual(wed10)
      expect(t.parts.some((p) => p.kind === 'bus')).toBe(true)
    }
  })
  it('lists each bus once, from the stop that lets you leave latest', () => {
    const [a, b] = [P('crown-college-galileo-house'), P('baskin-engineering-152')]
    const walk = planRoute(g, a, b) as Plan
    const trips = planTrips(net, g, a, b, { kind: 'leave', at: wed10 }, false, null, { walkOnly: walk.seconds })
    const buses = trips.map((t) => t.parts.flatMap((p) => (p.kind === 'bus' ? [p.tripId] : [])).join('>'))
    expect(new Set(buses).size).toBe(buses.length)
  })
  it('offers nothing when no bus saves any walking', () => {
    const [a, b] = [P('stevenson-academic'), P('crown-college')]
    const walk = planRoute(g, a, b) as Plan
    expect(planTrips(net, g, a, b, { kind: 'leave', at: wed10 }, false, null, { walkOnly: walk.seconds })).toEqual([])
  })
})
