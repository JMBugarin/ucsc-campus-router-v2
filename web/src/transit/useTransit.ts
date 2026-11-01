import { useEffect, useState } from 'react'
import { fetchRealtime, REALTIME_BASE, type Alert, type TripUpdate } from './realtime'
import { pacificClock, type Clock, type TransitData } from './schedule'

export async function loadTransit(): Promise<TransitData> {
  const r = await fetch(`${import.meta.env.BASE_URL}data/transit.json`)
  if (!r.ok) throw new Error(`transit ${r.status}`)
  return r.json()
}

/** Campus time, refreshed every 20 seconds while something is showing departures. */
export function useClock(active: boolean): Clock {
  const [c, setC] = useState(() => pacificClock(new Date()))
  useEffect(() => {
    if (!active) return
    const t = window.setInterval(() => setC(pacificClock(new Date())), 20000)
    setC(pacificClock(new Date()))
    return () => window.clearInterval(t)
  }, [active])
  return c
}

export interface LiveState {
  enabled: boolean
  status: 'off' | 'loading' | 'live' | 'error'
  updated?: number
  trips: Map<string, TripUpdate>
  alerts: Alert[]
}

/** Polls METRO's GTFS-realtime feed (through the proxy named by VITE_RT_BASE) every 30 s while `active`. */
export function useLive(active: boolean): LiveState {
  const [s, setS] = useState<LiveState>({ enabled: !!REALTIME_BASE, status: REALTIME_BASE ? 'loading' : 'off', trips: new Map(), alerts: [] })
  useEffect(() => {
    if (!active || !REALTIME_BASE) return
    const ctl = new AbortController()
    const tick = async () => {
      try {
        const [t, a] = await Promise.all([fetchRealtime('trips', ctl.signal), fetchRealtime('alerts', ctl.signal)])
        if (ctl.signal.aborted) return
        setS({ enabled: true, status: 'live', updated: t?.timestamp, trips: new Map((t?.trips ?? []).map((x) => [x.tripId, x])), alerts: a?.alerts ?? [] })
      } catch {
        if (!ctl.signal.aborted) setS((p) => ({ ...p, status: 'error' }))
      }
    }
    tick()
    const id = window.setInterval(tick, 30000)
    return () => {
      ctl.abort()
      window.clearInterval(id)
    }
  }, [active])
  return s
}
