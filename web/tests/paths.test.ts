import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { buildGraph, cutEdge, edgeIndex, edgePoints, haversine, nearestNode, nearestOnEdges } from '../src/routing/graph'
import { endpointOf, planRoute, routeGeoJSON, type Plan } from '../src/routing/plan'
import type { GraphFile, PlacesFile } from '../src/data/types'

const g = buildGraph(JSON.parse(readFileSync('public/data/graph.json', 'utf8')) as GraphFile)
const places = (JSON.parse(readFileSync('public/data/places.json', 'utf8')) as PlacesFile).places
const P = (id: string) => endpointOf(places.find((p) => p.id === id)!)
const lineLength = (pts: [number, number][]) => pts.slice(1).reduce((s, p, i) => s + haversine(pts[i][0], pts[i][1], p[0], p[1]), 0)
const drawn = (plan: Plan) => plan.path.reduce((s, p) => s + lineLength(p.pts), 0)
const straight = new Set((JSON.parse(readFileSync('../graph/ucsc/shapes.json', 'utf8')).unmatched as { from: number; to: number }[]).map((u) => `${u.from}-${u.to}`))

describe('path shapes', () => {
  it('give most edges their bends, each as long as the edge it draws', () => {
    expect(g.shape.size).toBeGreaterThan(1500)
    let checked = 0
    expect(straight.size).toBeLessThanOrEqual(5)
    for (const [a, b] of g.pairs) {
      if (straight.has(`${a}-${b}`)) continue
      const e = edgeIndex(g, a, b)
      const len = lineLength(edgePoints(g, a, b))
      expect(Math.abs(len - g.len[e]), `${a}-${b}`).toBeLessThanOrEqual(Math.max(3.5, 0.035 * g.len[e]))
      checked++
    }
    expect(checked).toBe(g.pairs.length - straight.size)
  })
  it('cut an edge at any two points along it', () => {
    const [a, b] = g.pairs.find(([x, y]) => (g.shape.get(x * g.n + y)?.length ?? 0) > 3)!
    const whole = lineLength(edgePoints(g, a, b))
    expect(lineLength(cutEdge(g, a, b, 0.25, 0.75))).toBeCloseTo(whole / 2, 0)
    expect(cutEdge(g, a, b, 0.75, 0.25)[0]).toEqual(cutEdge(g, a, b, 0.25, 0.75).at(-1))
  })
})

describe('snapping to the nearest path', () => {
  it('is never farther than snapping to the nearest intersection, and usually much closer', () => {
    const doors = places.flatMap((p) => p.entrances ?? []).slice(0, 300)
    let node = 0
    let edge = 0
    for (const [la, lo] of doors) {
      const n = nearestNode(g, la, lo).dist
      const e = nearestOnEdges(g, la, lo)!.dist
      expect(e).toBeLessThanOrEqual(n + 0.1)
      node += n
      edge += e
    }
    expect(edge / doors.length).toBeLessThan(0.6 * (node / doors.length))
  })
})

describe('routes follow the paths', () => {
  const trips: [string, string][] = [
    ['quarry-plaza', 'baskin-engineering-152'],
    ['mchenry-library', 'baskin-engineering'],
    ['kresge-college', 'science-hill'],
    ['thimann-labs-101', 'mchenry-library-1340'],
    ['quarry-plaza', 'kresge-academic-3201'],
  ]
  for (const [from, to] of trips) {
    it(`${from} to ${to}: the line drawn is the walk timed, joined end to end`, () => {
      const plan = planRoute(g, P(from), P(to))
      if ('error' in plan) throw new Error(plan.error)
      expect(Math.abs(drawn(plan) - plan.route.meters)).toBeLessThan(Math.max(5, 0.04 * plan.route.meters))
      expect(haversine(...plan.path[0].pts[0], ...plan.originOn)).toBeLessThan(0.5)
      expect(haversine(...plan.path.at(-1)!.pts.at(-1)!, ...plan.destOn)).toBeLessThan(0.5)
      for (let i = 1; i < plan.path.length; i++) expect(haversine(...plan.path[i - 1].pts.at(-1)!, ...plan.path[i].pts[0])).toBeLessThan(0.5)
      const kinds = routeGeoJSON(g, plan).features.map((f) => f.properties?.kind)
      expect(kinds.filter((k) => k === 'connector')).toHaveLength(2)
    })
  }
  it('stays on one path when both ends are on it', () => {
    const [a, b] = g.pairs.find(([x, y]) => edgeIndex(g, x, y) >= 0 && g.len[edgeIndex(g, x, y)] > 120)!
    const pts = cutEdge(g, a, b, 0.2, 0.8)
    const plan = planRoute(g, { id: 'x', name: 'x', lat: pts[0][0], lon: pts[0][1] }, { id: 'y', name: 'y', lat: pts.at(-1)![0], lon: pts.at(-1)![1] })
    if ('error' in plan) throw new Error(plan.error)
    expect(plan.route.nodes).toEqual([])
    expect(plan.route.meters).toBeCloseTo(0.6 * g.len[edgeIndex(g, a, b)], -1)
  })
})
