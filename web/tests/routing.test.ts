import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { buildGraph, haversine, nearestNode, route, walkSpeed } from '../src/routing/graph'
import { planRoute, endpointOf } from '../src/routing/plan'
import type { GraphFile, PlacesFile } from '../src/data/types'

const gf: GraphFile = JSON.parse(readFileSync('public/data/graph.json', 'utf8'))
const places = (JSON.parse(readFileSync('public/data/places.json', 'utf8')) as PlacesFile).places
const g = buildGraph(gf)
const P = (id: string) => endpointOf(places.find((p) => p.id === id)!)

describe('walking graph', () => {
  it('loads all nodes and edges', () => {
    expect(g.n).toBe(1960)
    expect(g.to.length).toBe(5188)
  })
  it('routes along mapped edges only and never undercuts the straight line', () => {
    const r = route(g, 0, 900)!
    expect(r).not.toBeNull()
    const straight = haversine(g.lat[0], g.lon[0], g.lat[900], g.lon[900])
    expect(r.meters).toBeGreaterThanOrEqual(straight - 1)
    // every hop is a real edge
    for (let i = 0; i + 1 < r.nodes.length; i++) {
      let ok = false
      for (let e = g.off[r.nodes[i]]; e < g.off[r.nodes[i] + 1]; e++) ok ||= g.to[e] === r.nodes[i + 1]
      expect(ok).toBe(true)
    }
  })
  it('walks uphill slower than downhill', () => {
    expect(walkSpeed(0.15, false)).toBeLessThan(walkSpeed(-0.05, false))
    expect(walkSpeed(0, true)).toBeLessThan(walkSpeed(0, false))
  })
  it('avoid-stairs never uses a stairs edge', () => {
    const r = route(g, 0, 900, { avoidStairs: true })
    if (r) expect(r.stairsMeters).toBe(0)
  })
})

describe('campus routes', () => {
  it('McHenry Library to Baskin Engineering is a plausible walk', () => {
    const p = planRoute(g, P('mchenry-library'), P('baskin-engineering'))
    expect('error' in p).toBe(false)
    if ('error' in p) return
    expect(p.meters).toBeGreaterThan(200)
    expect(p.meters).toBeLessThan(1600)
    expect(p.seconds / 60).toBeLessThan(25)
  })
  it('Quarry Plaza to Science Hill climbs', () => {
    const p = planRoute(g, P('quarry-plaza'), P('science-hill'))
    expect('error' in p).toBe(false)
    if ('error' in p) return
    expect(p.route.gain).toBeGreaterThan(p.route.loss)
  })
  it('falls back to a stairs route and says so when no stair-free route exists', () => {
    const p = planRoute(g, P('quarry-plaza'), P('mchenry-library'), { avoidStairs: true })
    if ('error' in p) throw new Error(p.error)
    expect(p.stairsUnavoidable ? p.route.hasStairs : !p.route.hasStairs).toBe(true)
  })
  it('reports the same place', () => {
    expect(planRoute(g, P('mchenry-library'), P('mchenry-library'))).toEqual({ error: 'same-place' })
  })
  it('refuses a point far from any mapped path instead of drawing a straight line', () => {
    const far = { id: 'x', name: 'Far', lat: 36.9, lon: -122.2 }
    expect(planRoute(g, far, P('mchenry-library'))).toEqual({ error: 'no-path-near-origin' })
  })
  it('snaps within the graph', () => {
    const n = nearestNode(g, 36.9995, -122.063)
    expect(n.dist).toBeLessThan(150)
  })
})
