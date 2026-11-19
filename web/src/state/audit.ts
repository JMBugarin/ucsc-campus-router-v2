import { useSyncExternalStore } from 'react'
import type { Access, Place } from '../data/types'

/** What someone walking a room records before it goes into data/rooms.json. */
export interface Draft {
  access: Access | ''
  door: [number, number] | null
  doorLabel: string
  floor: string
  wing: string
  note: string
  steps: string
  stepFree: '' | 'yes' | 'no'
  elevator: string
}

export const EMPTY_DRAFT: Draft = { access: '', door: null, doorLabel: '', floor: '', wing: '', note: '', steps: '', stepFree: '', elevator: '' }
export const LIMITS = { doorLabel: 60, floor: 12, wing: 40, note: 160, step: 90, steps: 5, elevator: 120 }

const round = (n: number) => Math.round(n * 1e6) / 1e6

/** The Pacific calendar date, as data/rooms.json stores `checked`. */
export function pacificDate(at: Date): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Los_Angeles', year: 'numeric', month: '2-digit', day: '2-digit' }).format(at)
}

export const roomKey = (p: Place) => `${p.room?.building}:${p.room?.number}`

/** The data/rooms.json entry for a draft, or null when nothing was recorded. */
export function guideEntry(d: Draft, checked: string): Record<string, unknown> | null {
  const g: Record<string, unknown> = {}
  if (d.access) g.access = d.access
  if (d.door) g.entrance = { lat: round(d.door[0]), lon: round(d.door[1]), ...(d.doorLabel.trim() ? { label: d.doorLabel.trim() } : {}) }
  if (d.floor.trim()) g.floor = d.floor.trim()
  if (d.wing.trim()) g.wing = d.wing.trim()
  if (d.note.trim()) g.note = d.note.trim()
  const steps = d.steps.split('\n').map((s) => s.trim()).filter(Boolean).slice(0, LIMITS.steps)
  if (steps.length) g.steps = steps
  if (d.stepFree) g.step_free = d.stepFree === 'yes'
  if (d.elevator.trim()) g.elevator = d.elevator.trim()
  if (!Object.keys(g).length) return null
  return { ...g, checked, source: 'walk' }
}

const PREFIX = 'audit:'

export class AuditStore {
  private listeners = new Set<() => void>()
  private cache = new Map<string, Draft>()
  /** room key waiting for a map tap to place its door */
  picking: string | null = null

  constructor(private storage: () => Storage = () => localStorage) {}

  subscribe = (fn: () => void) => {
    this.listeners.add(fn)
    return () => this.listeners.delete(fn)
  }
  private changed() {
    this.listeners.forEach((fn) => fn())
  }

  get(key: string): Draft {
    const hit = this.cache.get(key)
    if (hit) return hit
    let d = EMPTY_DRAFT
    try {
      const raw = this.storage().getItem(PREFIX + key)
      if (raw) d = { ...EMPTY_DRAFT, ...(JSON.parse(raw) as Partial<Draft>) }
    } catch {
      /* storage may be unavailable */
    }
    this.cache.set(key, d)
    return d
  }

  set(key: string, patch: Partial<Draft>) {
    const d = { ...this.get(key), ...patch }
    this.cache.set(key, d)
    try {
      this.storage().setItem(PREFIX + key, JSON.stringify(d))
    } catch {
      /* the draft still lives for this visit */
    }
    this.changed()
  }

  clear(key: string) {
    this.cache.set(key, EMPTY_DRAFT)
    try {
      this.storage().removeItem(PREFIX + key)
    } catch {
      /* nothing stored */
    }
    this.changed()
  }

  /** Every stored draft that records something, as one data/rooms.json overrides object. */
  all(checked: string): Record<string, unknown> {
    const out: Record<string, unknown> = {}
    try {
      const s = this.storage()
      for (let i = 0; i < s.length; i++) {
        const k = s.key(i)
        if (!k?.startsWith(PREFIX)) continue
        const key = k.slice(PREFIX.length)
        const entry = guideEntry(this.get(key), checked)
        if (entry) out[key] = entry
      }
    } catch {
      /* fall back to drafts from this visit */
      for (const [key, d] of this.cache) {
        const entry = guideEntry(d, checked)
        if (entry) out[key] = entry
      }
    }
    return Object.fromEntries(Object.entries(out).sort(([a], [b]) => a.localeCompare(b)))
  }

  startPick(key: string | null) {
    this.picking = key
    this.changed()
  }

  /** A map tap while a door is being placed; true when it was used. */
  tap(lat: number, lon: number): boolean {
    if (!this.picking) return false
    const key = this.picking
    this.picking = null
    this.set(key, { door: [lat, lon] })
    return true
  }
}

export const audit = new AuditStore()

export function useDraft(key: string | null): Draft | null {
  return useSyncExternalStore(audit.subscribe, () => (key ? audit.get(key) : null))
}
export function usePicking(): string | null {
  return useSyncExternalStore(audit.subscribe, () => audit.picking)
}
