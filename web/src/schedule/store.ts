import { useSyncExternalStore } from 'react'
import { cleanSchedule, sameClass, type Meeting } from './meeting'

const KEY = 'classmap.schedule.v1'
const PREFS = 'classmap.reminders.v1'

export interface ReminderPrefs {
  lead: number | null
  sent: string[]
}

/** The schedule lives only in this browser (localStorage), never on a server. */
export class ScheduleStore {
  private meetings: Meeting[]
  private prefs: ReminderPrefs
  private listeners = new Set<() => void>()
  /** false when the browser won't keep data, so the student can be told */
  persistent = true

  constructor(private storage: () => Storage = () => localStorage) {
    this.meetings = this.read()
    this.prefs = this.readPrefs()
  }

  private read(): Meeting[] {
    try {
      const raw = this.storage().getItem(KEY)
      if (!raw) return []
      const json = JSON.parse(raw) as { meetings?: unknown[] }
      return cleanSchedule(Array.isArray(json.meetings) ? json.meetings : [])
    } catch {
      return []
    }
  }
  private readPrefs(): ReminderPrefs {
    try {
      const v = JSON.parse(this.storage().getItem(PREFS) ?? 'null') as ReminderPrefs | null
      return { lead: typeof v?.lead === 'number' ? v.lead : null, sent: Array.isArray(v?.sent) ? v!.sent.slice(-200) : [] }
    } catch {
      return { lead: null, sent: [] }
    }
  }
  private write() {
    try {
      this.storage().setItem(KEY, JSON.stringify({ meetings: this.meetings }))
      this.storage().setItem(PREFS, JSON.stringify(this.prefs))
      this.persistent = true
    } catch {
      this.persistent = false
    }
    this.listeners.forEach((fn) => fn())
  }

  subscribe = (fn: () => void) => {
    this.listeners.add(fn)
    return () => this.listeners.delete(fn)
  }
  get all(): Meeting[] {
    return this.meetings
  }
  get reminders(): ReminderPrefs {
    return this.prefs
  }

  /** Adds classes, leaving out ones already saved. Returns how many were new. */
  add(list: Meeting[]): number {
    const fresh: Meeting[] = []
    for (const m of list) if (![...this.meetings, ...fresh].some((o) => sameClass(o, m))) fresh.push(m)
    this.meetings = cleanSchedule([...this.meetings, ...fresh])
    this.write()
    return fresh.length
  }
  replace(index: number, m: Meeting) {
    const next = [...this.meetings]
    next[index] = m
    this.meetings = cleanSchedule(next)
    this.write()
  }
  remove(index: number) {
    this.meetings = this.meetings.filter((_, i) => i !== index)
    this.write()
  }
  clear() {
    this.meetings = []
    this.write()
  }
  setReminderLead(lead: number | null) {
    this.prefs = { ...this.prefs, lead }
    this.write()
  }
  markSent(key: string) {
    this.prefs = { ...this.prefs, sent: [...this.prefs.sent, key].slice(-200) }
    this.write()
  }
}

export const schedule = new ScheduleStore()

export function useSchedule(): Meeting[] {
  return useSyncExternalStore(schedule.subscribe, () => schedule.all)
}
export function useReminderPrefs(): ReminderPrefs {
  return useSyncExternalStore(schedule.subscribe, () => schedule.reminders)
}
