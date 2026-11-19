import { useEffect, useState } from 'react'
import { getAlerts, getVehicles, type Alert, type LiveStatus, type Vehicle } from './liveClient'
import { SERVICE_BASE } from './useServiceDepartures'

export interface LiveBuses {
  enabled: boolean
  vehicles: Vehicle[]
  vehiclesStatus: LiveStatus | null
  alerts: Alert[]
  failed: boolean
}

/** Bus positions every 20 s and alerts every minute, only while `active` (a stop page or a trip is open). */
export function useLiveBuses(active: boolean): LiveBuses {
  const [state, setState] = useState<LiveBuses>({ enabled: !!SERVICE_BASE, vehicles: [], vehiclesStatus: null, alerts: [], failed: false })
  useEffect(() => {
    if (!SERVICE_BASE || !active) return
    const base = SERVICE_BASE
    const ctl = new AbortController()
    let ticks = 0
    const tick = async () => {
      const signal = AbortSignal.any([ctl.signal, AbortSignal.timeout(6000)])
      try {
        const [v, a] = await Promise.all([getVehicles(base, signal), ticks % 3 === 0 ? getAlerts(base, signal) : Promise.resolve(null)])
        if (ctl.signal.aborted) return
        setState((s) => ({ ...s, vehicles: v.status.freshness === 'unavailable' ? [] : v.vehicles, vehiclesStatus: v.status, alerts: a ? a.alerts : s.alerts, failed: false }))
      } catch {
        if (!ctl.signal.aborted) setState((s) => ({ ...s, vehicles: [], failed: true }))
      }
      ticks++
    }
    void tick()
    const timer = window.setInterval(tick, 20_000)
    return () => (ctl.abort(), window.clearInterval(timer))
  }, [active])
  return state
}
