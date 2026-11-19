import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { buildGraph } from '../src/routing/graph'
import { endpointOf, planRoute, routeGeoJSON, type Plan } from '../src/routing/plan'
import { lineMetres, pointAlong, smoothLine } from '../src/routing/smooth'
import type { GraphFile, PlacesFile } from '../src/data/types'

type LL = [number, number]
const g = buildGraph(JSON.parse(readFileSync('public/data/graph.json', 'utf8')) as GraphFile)
const places = (JSON.parse(readFileSync('public/data/places.json', 'utf8')) as PlacesFile).places
const P = (id: string) => endpointOf(places.find((p) => p.id === id)!)

const LAT0 = 36.99
const KX = 111320 * Math.cos((LAT0 * Math.PI) / 180)
const xy = ([la, lo]: LL): LL => [lo * KX, la * 110540]
const m = (x: number, y: number): LL => [LAT0 + y / 110540, -122.06 + x / KX]
function toLine(p: LL, line: LL[]): number {
  const [px, py] = xy(p)
  let best = Infinity
  for (let i = 1; i < line.length; i++) {
    const [ax, ay] = xy(line[i - 1])
    const [bx, by] = xy(line[i])
    const dx = bx - ax
    const dy = by - ay
    const t = dx || dy ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))) : 0
    best = Math.min(best, Math.hypot(px - ax - t * dx, py - ay - t * dy))
  }
  return best
}
function sharpest(line: LL[]): number {
  let max = 0
  for (let i = 1; i < line.length - 1; i++) {
    const [ax, ay] = xy(line[i - 1])
    const [bx, by] = xy(line[i])
    const [cx, cy] = xy(line[i + 1])
    const a = Math.atan2(by - ay, bx - ax)
    const b = Math.atan2(cy - by, cx - bx)
    max = Math.max(max, Math.abs((((b - a) * 180) / Math.PI + 540) % 360 - 180))
  }
  return max
}
const walk = (plan: Plan) => plan.path.reduce<LL[]>((pts, p) => [...pts, ...(pts.length ? p.pts.slice(1) : p.pts)], [])

describe('smooth route lines', () => {
  it('keep their ends and leave a straight line straight', () => {
    const line = [m(0, 0), m(10, 0.3), m(20, -0.2), m(30, 0)]
    const out = smoothLine(line)
    expect(out[0]).toEqual(line[0])
    expect(out.at(-1)).toEqual(line.at(-1))
    expect(out).toHaveLength(2)
  })

  it('round a right angle into a curve that stays within the offset', () => {
    const line = [m(0, 0), m(40, 0), m(40, 40)]
    const out = smoothLine(line, { maxOffset: 4 })
    expect(out.length).toBeGreaterThan(6)
    expect(sharpest(out)).toBeLessThan(15)
    for (const p of out) expect(toLine(p, line)).toBeLessThan(4.05)
    expect(Math.min(...out.map((p) => Math.hypot(xy(p)[0] - xy(m(40, 0))[0], xy(p)[1] - xy(m(40, 0))[1])))).toBeGreaterThan(2.5)
  })

  it('never take more than half of a short side, so two close corners stay apart', () => {
    const line = [m(0, 0), m(30, 0), m(30, 6), m(60, 6)]
    const out = smoothLine(line)
    for (const p of out) expect(toLine(p, line)).toBeLessThan(4.05)
    expect(sharpest(out)).toBeLessThan(20)
  })

  for (const [a, b] of [
    ['quarry-plaza', 'mchenry-library'],
    ['stevenson-academic', 'mchenry-library'],
    ['kresge-college', 'baskin-engineering'],
  ]) {
    it(`follow the paths from ${a} to ${b} without a hard corner`, () => {
      const plan = planRoute(g, P(a), P(b))
      if ('error' in plan) throw new Error(plan.error)
      const raw = walk(plan)
      const out = smoothLine(raw)
      expect(sharpest(raw)).toBeGreaterThan(45)
      expect(sharpest(out)).toBeLessThan(30)
      for (const p of out) expect(toLine(p, raw)).toBeLessThan(5)
      for (const p of raw) expect(toLine(p, out)).toBeLessThan(5)
      expect(Math.abs(lineMetres(out) - lineMetres(raw)) / lineMetres(raw)).toBeLessThan(0.06)

      const fc = routeGeoJSON(g, plan)
      const line = fc.features.filter((f) => f.properties.kind === 'walk')
      expect(line).toHaveLength(1)
      const drawn = (line[0].geometry.coordinates as number[][]).map(([lo, la]) => [la, lo] as LL)
      const stairs = fc.features.filter((f) => f.properties.kind === 'stairs')
      expect(stairs.length > 0).toBe(plan.route.stairsMeters >= 4)
      for (const s of stairs) {
        const [lo, la] = s.geometry.coordinates as number[]
        expect(toLine([la, lo], drawn)).toBeLessThan(0.5)
      }
    })
  }

  it('find the point a distance along a line', () => {
    const line = [m(0, 0), m(10, 0), m(10, 10)]
    const p = xy(pointAlong(line, 15))
    expect(p[0] - xy(m(10, 5))[0]).toBeCloseTo(0, 1)
    expect(p[1] - xy(m(10, 5))[1]).toBeCloseTo(0, 1)
    expect(pointAlong(line, 99)).toEqual(line[2])
  })
})
