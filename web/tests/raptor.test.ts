import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { arriveBy, earliest, leaveAt, prepareNetwork, stopsNear, type MetroFile } from '../src/transit/raptor'

// a tiny made-up network: route A runs 0 → 1 → 2, route B runs 3 → 4, and stop 2 is next to stop 3
const tiny: MetroFile = {
  feed: { version: 't', start: '20260101', end: '20261231' },
  stops: [
    ['s0', 'Zero', 37.0, -122.0],
    ['s1', 'One', 37.01, -122.0],
    ['s2', 'Two', 37.02, -122.0],
    ['s3', 'Three', 37.0201, -122.0001],
    ['s4', 'Four', 37.04, -122.0],
  ],
  routes: { A: ['A', 'A line', ''], B: ['B', 'B line', ''] },
  services: [{ d: [1, 1, 1, 1, 1, 0, 0], a: '20260101', z: '20261231', add: [], del: [] }],
  patterns: [
    { r: 'A', h: 'to Two', s: [0, 1, 2], p: [[0, 300, 600]], t: [[0, 8 * 3600, 0, 'a1'], [0, 9 * 3600, 0, 'a2']] },
    { r: 'B', h: 'to Four', s: [3, 4], p: [[0, 600]], t: [[0, 8 * 3600 + 900, 0, 'b1'], [0, 8 * 3600 + 2400, 0, 'b2']] },
  ],
}
const net = prepareNetwork(tiny)
const weekday = { date: '20261104', dow: 2 }

describe('the trip planner', () => {
  it('rides, walks a short transfer and rides again', () => {
    const j = earliest(net, weekday, 8 * 3600 - 120, new Map([[0, 60]]), new Map([[4, 30]]))!
    expect(j.legs.map((l) => l.kind)).toEqual(['walk', 'bus', 'walk', 'bus', 'walk'])
    expect(j.transfers).toBe(1)
    expect(j.departs).toBe(8 * 3600 - 60)
    expect(j.arrives).toBe(8 * 3600 + 900 + 600 + 30)
  })
  it('waits for the next bus when the first has gone', () => {
    const j = earliest(net, weekday, 8 * 3600 + 30, new Map([[0, 60]]), new Map([[2, 0]]))!
    const bus = j.legs.find((l) => l.kind === 'bus')!
    expect(bus.departs).toBe(9 * 3600)
  })
  it('finds nothing on a day without service', () => {
    expect(earliest(net, { date: '20261107', dow: 5 }, 7 * 3600, new Map([[0, 60]]), new Map([[4, 0]]))).toBeNull()
  })
  it('works back from a deadline to the latest bus that makes it', () => {
    const js = arriveBy(net, weekday, 9 * 3600 + 700, new Map([[0, 60]]), new Map([[2, 0]]))
    expect(js[0].legs.find((l) => l.kind === 'bus')!.departs).toBe(9 * 3600)
    expect(js.every((j) => j.arrives <= 9 * 3600 + 700)).toBe(true)
  })
  it('lists later options in order', () => {
    const js = leaveAt(net, weekday, 7 * 3600, new Map([[0, 60]]), new Map([[2, 0]]))
    expect(js.map((j) => j.legs.find((l) => l.kind === 'bus')!.departs)).toEqual([8 * 3600, 9 * 3600])
  })
})

describe('the real METRO schedule', () => {
  const metro = prepareNetwork(JSON.parse(readFileSync('public/data/metro.json', 'utf8')) as MetroFile)
  it('gets from downtown Santa Cruz to Science Hill on a weekday morning', () => {
    // Pacific Ave and Cathcart, downtown, to the stops below Baskin Engineering
    const access = stopsNear(metro, 36.9719, -122.0263, 800)
    const egress = stopsNear(metro, 36.9995, -122.0605, 400)
    const t0 = performance.now()
    const js = leaveAt(metro, { date: '20261104', dow: 2 }, 8 * 3600, access, egress)
    const ms = performance.now() - t0
    expect(js.length).toBeGreaterThan(0)
    const j = js[0]
    expect(j.arrives - j.departs).toBeLessThan(60 * 60)
    expect(j.legs.some((l) => l.kind === 'bus')).toBe(true)
    expect(ms).toBeLessThan(1500)
  })
})
