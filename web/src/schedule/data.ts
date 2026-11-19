import { useEffect, useState } from 'react'
import { Campus, type CampusFile } from './campus'
import { holidaysOf, termsFromJson, type Term } from './terms'
import type { Graph } from '../routing/graph'
import { endpointOf, planRoute, type Endpoint } from '../routing/plan'
import type { Place } from '../data/types'
import type { Walk } from './dayPlan'

export interface ClassesData {
  campus: Campus
  terms: Term[]
  holidays: Set<string>
}

const base = import.meta.env.BASE_URL
export async function loadClassesData(): Promise<ClassesData> {
  const [c, t] = await Promise.all([fetch(`${base}data/campus.json`), fetch(`${base}data/terms.json`)])
  if (!c.ok || !t.ok) throw new Error(`campus ${c.status}, terms ${t.status}`)
  const terms = termsFromJson(await t.json())
  return { campus: new Campus((await c.json()) as CampusFile), terms, holidays: holidaysOf(terms) }
}

/** The current time, ticking every `ms`. */
export function useNow(ms = 30_000): number {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const t = window.setInterval(() => setNow(Date.now()), ms)
    const on = () => setNow(Date.now())
    document.addEventListener('visibilitychange', on)
    return () => (window.clearInterval(t), document.removeEventListener('visibilitychange', on))
  }, [ms])
  return now
}

/** The map place for a class location: the room when the map has it, else its building. */
export function placeFor(location: string, campus: Campus, byId: Map<string, Place>): Place | null {
  const id = campus.placeId(campus.resolve(location, true), (x) => byId.has(x))
  return id ? byId.get(id) ?? null : null
}

/** Walking minutes between class locations (or from `you`) over the campus path graph. */
export function makeWalk(graph: Graph | null, campus: Campus, byId: Map<string, Place>, you: { lat: number; lon: number } | null, avoidStairs: boolean): Walk {
  const cache = new Map<string, number | null>()
  const endpoint = (location: string | null): Endpoint | null => {
    if (location === null) return you ? { id: 'me', name: 'My location', lat: you.lat, lon: you.lon, isLocation: true } : null
    const p = placeFor(location, campus, byId)
    return p ? endpointOf(p) : null
  }
  return (from, to) => {
    if (!graph) return null
    const key = `${from ?? '*'}>${to}`
    if (cache.has(key)) return cache.get(key)!
    const a = endpoint(from)
    const b = endpoint(to)
    let minutes: number | null = null
    if (a && b) {
      if (a.id === b.id) minutes = 0
      else {
        const r = planRoute(graph, a, b, { avoidStairs })
        minutes = 'error' in r ? null : Math.max(1, Math.round(r.seconds / 60))
      }
    }
    cache.set(key, minutes)
    return minutes
  }
}
