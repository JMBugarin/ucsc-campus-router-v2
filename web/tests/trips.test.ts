import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { buildGraph } from '../src/routing/graph'
import { endpointOf } from '../src/routing/plan'
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
  it('arrive by a class: every option gets there in time, latest departure first', () => {
    const by = at('2026-11-04T09:20:00-08:00')
    const trips = planTrips(net, g, downtown, be152, { kind: 'arrive', by })
    expect(trips.length).toBeGreaterThan(1)
    expect(trips.every((t) => t.arrive <= by)).toBe(true)
    expect(trips[0].leave).toBeGreaterThanOrEqual(trips[1].leave)
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
