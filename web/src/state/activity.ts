import { useSyncExternalStore } from 'react'

export const ACTIVITY_URL = import.meta.env.VITE_ACTIVITY_URL as string | undefined
export const WEEKS_BACK = 5

export type Sent = 'ok' | 'rejected' | 'failed'
export interface Sender {
  record(install: string, week: string): Promise<Sent>
  withdraw(install: string): Promise<Sent>
}
export interface Store {
  get(key: string): string | null
  set(key: string, value: string): void
  remove(key: string): void
}

/** The Monday that starts the America/Los_Angeles week holding `at`. */
export function pacificWeek(at: Date): string {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Los_Angeles', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(at)
  const n = (t: string) => Number(parts.find((p) => p.type === t)!.value)
  const day = new Date(Date.UTC(n('year'), n('month') - 1, n('day')))
  day.setUTCDate(day.getUTCDate() - ((day.getUTCDay() + 6) % 7))
  return day.toISOString().slice(0, 10)
}

const K = { install: 'activity_install', sent: 'activity_sent_week', pending: 'activity_pending_weeks', withdraw: 'activity_withdraw' }

export class Activity {
  private flushing: Promise<void> | null = null
  private listeners = new Set<() => void>()

  constructor(
    private store: Store,
    private sender: Sender | null,
    private now: () => Date = () => new Date(),
    private newId: () => string = () => crypto.randomUUID(),
  ) {}

  get available() {
    return this.sender !== null
  }
  get install(): string | null {
    return this.sender ? this.store.get(K.install) : null
  }
  get participantCode(): string | null {
    return this.install?.slice(0, 8) ?? null
  }

  subscribe = (fn: () => void) => {
    this.listeners.add(fn)
    return () => this.listeners.delete(fn)
  }
  private changed() {
    this.listeners.forEach((fn) => fn())
  }
  private list(key: string): string[] {
    try {
      const v = JSON.parse(this.store.get(key) ?? '[]')
      return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []
    } catch {
      return []
    }
  }
  private setList(key: string, v: string[]) {
    this.store.set(key, JSON.stringify(v))
  }

  async setOn(on: boolean) {
    if (!this.sender || on === (this.install !== null)) return
    if (on) {
      this.store.set(K.install, this.newId())
      this.changed()
      return
    }
    const id = this.install!
    for (const k of [K.install, K.sent, K.pending]) this.store.remove(k)
    this.setList(K.withdraw, [...this.list(K.withdraw), id])
    this.changed()
    await this.flushing
    await this.flush()
  }

  /** A place was opened: a room or building found, or a stop's departures shown. */
  async meaningfulAction() {
    if (!this.install) return
    const week = pacificWeek(this.now())
    const pending = this.list(K.pending)
    if (this.store.get(K.sent) === week || pending.includes(week)) return
    this.setList(K.pending, [...pending, week])
    await this.flush()
  }

  flush(): Promise<void> {
    return (this.flushing ??= this.doFlush().finally(() => (this.flushing = null)))
  }

  private async doFlush() {
    const sender = this.sender
    if (!sender) return
    for (const id of this.list(K.withdraw)) {
      if ((await sender.withdraw(id)) === 'failed') continue
      this.setList(K.withdraw, this.list(K.withdraw).filter((x) => x !== id))
    }
    const install = this.install
    if (!install) return
    const oldest = new Date(pacificWeek(this.now()))
    oldest.setUTCDate(oldest.getUTCDate() - 7 * WEEKS_BACK)
    for (const week of this.list(K.pending)) {
      const result: Sent = new Date(week) < oldest ? 'rejected' : await sender.record(install, week)
      if (result === 'failed') continue
      if (this.install !== install) return
      this.setList(K.pending, this.list(K.pending).filter((x) => x !== week))
      if (result === 'ok') this.store.set(K.sent, week)
    }
  }
}

export function httpSender(url: string): Sender {
  const send = async (method: string, target: string, body?: string): Promise<Sent> => {
    try {
      const r = await fetch(target, {
        method,
        body,
        headers: body ? { 'Content-Type': 'application/json' } : undefined,
        keepalive: true,
        credentials: 'omit',
        referrerPolicy: 'no-referrer',
        signal: AbortSignal.timeout(15000),
      })
      return r.status === 204 ? 'ok' : r.status === 400 ? 'rejected' : 'failed'
    } catch {
      return 'failed'
    }
  }
  return {
    record: (install, week) => send('POST', url, JSON.stringify({ install, week })),
    withdraw: (install) => send('DELETE', `${url}?install=${encodeURIComponent(install)}`),
  }
}

const browserStore: Store = {
  get: (k) => {
    try {
      return localStorage.getItem(k)
    } catch {
      return null
    }
  },
  set: (k, v) => {
    try {
      localStorage.setItem(k, v)
    } catch {
      /* storage may be unavailable */
    }
  },
  remove: (k) => {
    try {
      localStorage.removeItem(k)
    } catch {
      /* storage may be unavailable */
    }
  },
}

export const activity = new Activity(browserStore, ACTIVITY_URL ? httpSender(ACTIVITY_URL) : null)

export function useActivity() {
  const install = useSyncExternalStore(activity.subscribe, () => activity.install)
  return { available: activity.available, on: install !== null, code: install?.slice(0, 8) ?? null, setOn: (v: boolean) => void activity.setOn(v) }
}
