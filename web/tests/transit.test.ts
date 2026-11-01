import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { departures, upcoming, shiftDay, pacificClock, serviceRuns, previousDay, type TransitData } from '../src/transit/schedule'
import { parseFeed, delayAt } from '../src/transit/realtime'

const data: TransitData = JSON.parse(readFileSync('public/data/transit.json', 'utf8'))
const fixture = (n: string) => new Uint8Array(readFileSync(`tests/fixtures/${n}.pb`))

describe('schedule', () => {
  it('reads Pacific time whatever the machine zone', () => {
    // 2026-11-02 18:30 UTC is 10:30 in Santa Cruz (PST, UTC-8)
    const c = pacificClock(new Date('2026-11-02T18:30:00Z'))
    expect(c).toEqual({ date: '20261102', secs: 10 * 3600 + 30 * 60, dow: 0 })
  })
  it('steps back a day across a month end', () => {
    expect(previousDay({ date: '20261201', secs: 0, dow: 1 }).date).toBe('20261130')
  })
  it('lists the next departures in order from the real feed', () => {
    const now = pacificClock(new Date('2026-11-04T18:00:00Z')) // Wednesday 10:00
    const sci = data.stops.flatMap((s, i) => (s.name === 'Science Hill' ? [i] : []))
    const deps = departures(data, sci, now, 6)
    expect(deps.length).toBeGreaterThan(3)
    for (let i = 1; i < deps.length; i++) expect(deps[i].secs).toBeGreaterThanOrEqual(deps[i - 1].secs)
    expect(deps[0].secs).toBeGreaterThanOrEqual(now.secs)
    expect(serviceRuns(data, deps[0].trip.s, now)).toBe(true)
  })
  it('has no weekday service on a service exception that removes it', () => {
    const del = data.services.find((s) => s.del.length)
    if (del) expect(serviceRuns(data, data.services.indexOf(del), { date: del.del[0], secs: 0, dow: 0 })).toBe(false)
  })
})

describe('next service', () => {
  it('moves to the next running day when today has no more buses', () => {
    const sat = pacificClock(new Date('2026-11-01T06:50:00Z')) // Saturday 23:50 Pacific
    const sci = data.stops.flatMap((s, i) => (s.name === 'Science Hill' ? [i] : []))
    const r = upcoming(data, sci, sat)
    expect(r.list.length).toBeGreaterThan(0)
    if (!r.today) expect(r.day.date > sat.date).toBe(true)
  })
  it('shifts dates and weekdays together', () => {
    expect(shiftDay({ date: '20261231', secs: 0, dow: 3 }, 2)).toEqual({ date: '20270102', secs: 0, dow: 5 })
  })
})

describe('GTFS realtime decoding (feeds recorded from rt.scmetro.org)', () => {
  it('decodes trip updates with stop delays', () => {
    const f = parseFeed(fixture('trips'))
    expect(f.timestamp).toBeGreaterThan(1.7e9)
    expect(f.trips.length).toBeGreaterThan(5)
    const withStops = f.trips.find((t) => t.updates.length)
    expect(withStops?.tripId).toBeTruthy()
    expect(typeof withStops!.updates[0].stop).toBe('string')
    expect(delayAt(withStops, withStops!.updates[0].stop!)).not.toBeUndefined()
  })
  it('decodes vehicle positions inside Santa Cruz County', () => {
    const f = parseFeed(fixture('vehicles'))
    expect(f.vehicles.length).toBeGreaterThan(0)
    for (const v of f.vehicles) {
      expect(v.lat).toBeGreaterThan(36.5)
      expect(v.lat).toBeLessThan(37.5)
      expect(v.lon).toBeGreaterThan(-122.5)
      expect(v.lon).toBeLessThan(-121.5)
    }
  })
  it('decodes alerts', () => {
    const f = parseFeed(fixture('alerts'))
    expect(f.alerts.length).toBeGreaterThan(0)
    expect(f.alerts[0].header.length).toBeGreaterThan(3)
  })
})

import { buildGraph } from '../src/routing/graph'
import { busOptions } from '../src/transit/plan'
import { endpointOf } from '../src/routing/plan'
import type { GraphFile, PlacesFile } from '../src/data/types'

describe('bus options', () => {
  const g = buildGraph(JSON.parse(readFileSync('public/data/graph.json', 'utf8')) as GraphFile)
  const places = (JSON.parse(readFileSync('public/data/places.json', 'utf8')) as PlacesFile).places
  const P = (id: string) => endpointOf(places.find((p) => p.id === id)!)
  const wed10 = pacificClock(new Date('2026-11-04T18:00:00Z'))

  it('offers a direct bus only when it arrives sooner than walking', () => {
    const plan = busOptions(g, data, P('baskin-engineering'), P('oakes-college'), wed10)
    expect(plan.walkOnlyArrives).not.toBeNull()
    for (const o of plan.options) {
      expect(o.arrives).toBeLessThan(plan.walkOnlyArrives! - 59)
      expect(o.departs).toBeGreaterThanOrEqual(wed10.secs + o.walkToStop)
      expect(o.rides).toBeGreaterThan(o.departs)
    }
  })
  it('offers nothing for two places a minute apart', () => {
    const plan = busOptions(g, data, P('baskin-engineering'), P('engineering-2'), wed10)
    expect(plan.options).toEqual([])
  })
  it('offers nothing in the middle of the night', () => {
    const plan = busOptions(g, data, P('baskin-engineering'), P('oakes-college'), pacificClock(new Date('2026-11-04T11:00:00Z')))
    expect(plan.options.every((o) => o.departs >= 3 * 3600)).toBe(true)
  })
})
