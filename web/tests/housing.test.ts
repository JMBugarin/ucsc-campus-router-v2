import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { SearchIndex } from '../src/data/search'
import { buildGraph } from '../src/routing/graph'
import { endpointOf, planRoute } from '../src/routing/plan'
import type { GraphFile, PlacesFile } from '../src/data/types'

const places = (JSON.parse(readFileSync('public/data/places.json', 'utf8')) as PlacesFile).places
const housing = places.filter((p) => p.kind === 'housing')
const g = buildGraph(JSON.parse(readFileSync('public/data/graph.json', 'utf8')) as GraphFile)
const idx = new SearchIndex(places)
const first = (q: string) => idx.search(q, 3)[0]?.name

describe('housing', () => {
  it('lists every on-campus residence hall and apartment building from the campus map', () => {
    const file = JSON.parse(readFileSync('../data/housing.json', 'utf8')).buildings
    expect(housing).toHaveLength(file.length)
    expect(housing.length).toBeGreaterThan(150)
    expect(new Set(places.map((p) => p.id)).size).toBe(places.length)
    for (const h of housing) {
      expect(h.subtitle, h.name).toBeTruthy()
      expect(h.entrances!.length, h.name).toBeGreaterThan(0)
    }
  })
  it('is found by the names students use', () => {
    expect(first('c9 apt 2')).toBe('College Nine Apartment Building 2')
    expect(first('college 9 apartment building 2')).toBe('College Nine Apartment Building 2')
    expect(first('casa primera')).toBe('Stevenson College House 1')
    expect(first('galileo')).toBe('Crown College Galileo House')
    expect(first('porter a')).toBe('Porter College House A')
    expect(first('merrill dubois')).toBe('Merrill College House D')
    expect(first('biko')).toBe('Oakes College Dorm 1')
    expect(first('village b1')).toBe('Village Housing B1')
    expect(first('c10 hall 4')).toBe('John R. Lewis College Residence Hall 4')
  })
  it('never pushes a college, building or room below its dorms', () => {
    expect(first('crown')).toBe('Crown College')
    expect(first('c9')).toBe('College Nine')
    expect(first('porter')).toBe('Porter College')
    expect(first('be 152')).toBe('Jack Baskin Engineering 152')
  })
  it('routes to each building on the campus paths', () => {
    const be = endpointOf(places.find((p) => p.id === 'baskin-engineering')!)
    let ok = 0
    for (const h of housing) if (!('error' in planRoute(g, be, endpointOf(h)))) ok++
    expect(ok).toBe(housing.length)
    const c9 = planRoute(g, be, endpointOf(housing.find((h) => h.name === 'College Nine Apartment Building 2')!))
    expect('error' in c9).toBe(false)
  })
})
