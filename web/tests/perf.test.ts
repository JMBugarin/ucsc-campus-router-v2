import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { SearchIndex } from '../src/data/search'
import { buildGraph } from '../src/routing/graph'
import { endpointOf, planRoute } from '../src/routing/plan'
import type { GraphFile, PlacesFile } from '../src/data/types'

const places = (JSON.parse(readFileSync('public/data/places.json', 'utf8')) as PlacesFile).places
const g = buildGraph(JSON.parse(readFileSync('public/data/graph.json', 'utf8')) as GraphFile)
const idx = new SearchIndex(places)

describe('performance budgets', () => {
  it('search stays under 3 ms per keystroke', () => {
    const qs = ['m', 'mc', 'mche', 'mchenery lib', 'baskin eng', 'quarry', 'kresge', 'coffee', 'lot 1', 'thimman']
    const t = performance.now()
    const N = 300
    for (let i = 0; i < N; i++) idx.search(qs[i % qs.length])
    const per = (performance.now() - t) / N
    console.log(`search: ${per.toFixed(2)} ms per query over ${places.length} places`)
    expect(per).toBeLessThan(3)
  })
  it('a route plans in under 25 ms', () => {
    const pts = places.filter((p) => p.kind !== 'parking').slice(0, 40).map(endpointOf)
    const t = performance.now()
    let n = 0
    for (let i = 0; i < pts.length - 1; i++) {
      planRoute(g, pts[i], pts[i + 1])
      n++
    }
    const per = (performance.now() - t) / n
    console.log(`route: ${per.toFixed(2)} ms per plan (${n} plans)`)
    expect(per).toBeLessThan(25)
  })
})
