import type { GraphFile } from '../data/types'

export type EdgeKind = 0 | 1 | 2 | 3 // path, steps, road, bridge
export const KIND_LABEL = ['Path', 'Stairs', 'Road', 'Bridge'] as const

export interface Graph {
  n: number
  lat: Float64Array
  lon: Float64Array
  ele: Float32Array
  /** CSR adjacency */
  off: Uint32Array
  to: Uint32Array
  len: Float32Array
  kind: Uint8Array
}

export function buildGraph(f: GraphFile): Graph {
  const n = f.lat.length
  const m = f.edges.length / 4
  const off = new Uint32Array(n + 1)
  for (let i = 0; i < m; i++) off[f.edges[i * 4] + 1]++
  for (let i = 0; i < n; i++) off[i + 1] += off[i]
  const fill = off.slice(0, n)
  const to = new Uint32Array(m)
  const len = new Float32Array(m)
  const kind = new Uint8Array(m)
  for (let i = 0; i < m; i++) {
    const a = f.edges[i * 4]
    const p = fill[a]++
    to[p] = f.edges[i * 4 + 1]
    len[p] = f.edges[i * 4 + 2]
    kind[p] = f.edges[i * 4 + 3]
  }
  return { n, lat: Float64Array.from(f.lat), lon: Float64Array.from(f.lon), ele: Float32Array.from(f.ele), off, to, len, kind }
}

const R = 6371008.8
const rad = (d: number) => (d * Math.PI) / 180
export function haversine(aLat: number, aLon: number, bLat: number, bLon: number): number {
  const dLat = rad(bLat - aLat)
  const dLon = rad(bLon - aLon)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(aLat)) * Math.cos(rad(bLat)) * Math.sin(dLon / 2) ** 2
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)))
}

export function nearestNode(g: Graph, lat: number, lon: number): { node: number; dist: number } {
  let best = -1
  let bd = Infinity
  for (let i = 0; i < g.n; i++) {
    const d = haversine(lat, lon, g.lat[i], g.lon[i])
    if (d < bd) {
      bd = d
      best = i
    }
  }
  return { node: best, dist: bd }
}

/** Tobler's hiking function, m/s. slope = rise / run. Stairs are slowed by a fixed factor. */
export function walkSpeed(slope: number, stairs: boolean): number {
  const s = Math.max(-0.6, Math.min(0.6, slope))
  const kmh = 6 * Math.exp(-3.5 * Math.abs(s + 0.05))
  return Math.max(0.4, (kmh / 3.6) * (stairs ? 0.75 : 0.9))
}

export interface RouteOptions {
  avoidStairs?: boolean
}
export interface Step {
  kind: EdgeKind
  meters: number
  seconds: number
}
export interface RouteResult {
  nodes: number[]
  meters: number
  seconds: number
  gain: number
  loss: number
  steps: Step[]
  stairsMeters: number
  hasStairs: boolean
}

class MinHeap {
  private k: number[] = []
  private v: number[] = []
  get size() {
    return this.k.length
  }
  push(key: number, val: number) {
    const k = this.k
    const v = this.v
    let i = k.length
    k.push(key)
    v.push(val)
    while (i > 0) {
      const p = (i - 1) >> 1
      if (k[p] <= k[i]) break
      ;[k[p], k[i]] = [k[i], k[p]]
      ;[v[p], v[i]] = [v[i], v[p]]
      i = p
    }
  }
  pop(): [number, number] {
    const k = this.k
    const v = this.v
    const top: [number, number] = [k[0], v[0]]
    const lk = k.pop()!
    const lv = v.pop()!
    if (k.length) {
      k[0] = lk
      v[0] = lv
      let i = 0
      for (;;) {
        const l = 2 * i + 1
        const r = l + 1
        let s = i
        if (l < k.length && k[l] < k[s]) s = l
        if (r < k.length && k[r] < k[s]) s = r
        if (s === i) break
        ;[k[s], k[i]] = [k[i], k[s]]
        ;[v[s], v[i]] = [v[i], v[s]]
        i = s
      }
    }
    return top
  }
}

function edgeSeconds(g: Graph, from: number, e: number): number {
  const to = g.to[e]
  const run = g.len[e]
  const rise = g.ele[to] - g.ele[from]
  return run / walkSpeed(run > 0 ? rise / run : 0, g.kind[e] === 1)
}

/** Fastest walking route by Tobler time. Returns null when no path exists under the options. */
export function route(g: Graph, from: number, to: number, opt: RouteOptions = {}): RouteResult | null {
  const cost = new Float64Array(g.n).fill(Infinity)
  const prevNode = new Int32Array(g.n).fill(-1)
  const prevEdge = new Int32Array(g.n).fill(-1)
  const heap = new MinHeap()
  cost[from] = 0
  heap.push(0, from)
  while (heap.size) {
    const [c, u] = heap.pop()
    if (c > cost[u]) continue
    if (u === to) break
    for (let e = g.off[u]; e < g.off[u + 1]; e++) {
      if (opt.avoidStairs && g.kind[e] === 1) continue
      const w = g.to[e]
      const nc = c + edgeSeconds(g, u, e)
      if (nc < cost[w]) {
        cost[w] = nc
        prevNode[w] = u
        prevEdge[w] = e
        heap.push(nc, w)
      }
    }
  }
  if (!Number.isFinite(cost[to])) return null
  const nodes: number[] = []
  const edges: number[] = []
  for (let v = to; v !== -1; v = prevNode[v]) {
    nodes.push(v)
    if (prevEdge[v] >= 0) edges.push(prevEdge[v])
  }
  nodes.reverse()
  edges.reverse()
  let meters = 0
  let gain = 0
  let loss = 0
  let stairsMeters = 0
  const steps: Step[] = []
  edges.forEach((e, i) => {
    const a = nodes[i]
    const b = nodes[i + 1]
    const sec = edgeSeconds(g, a, e)
    meters += g.len[e]
    const d = g.ele[b] - g.ele[a]
    if (d > 0) gain += d
    else loss -= d
    const k = g.kind[e] as EdgeKind
    if (k === 1) stairsMeters += g.len[e]
    const last = steps[steps.length - 1]
    if (last && last.kind === k) {
      last.meters += g.len[e]
      last.seconds += sec
    } else steps.push({ kind: k, meters: g.len[e], seconds: sec })
  })
  return { nodes, meters, seconds: cost[to], gain, loss, steps, stairsMeters, hasStairs: stairsMeters > 0 }
}
