import { useEffect, useState } from 'react'
import { getDepartures, type Departures } from './serviceClient'

export const SERVICE_BASE = import.meta.env.VITE_TRANSIT_API as string | undefined
const MAX_STOPS = 8

export function useServiceDepartures(stops: string[]) {
  const [value, setValue] = useState<Departures[]>([])
  const [loaded, setLoaded] = useState(false)
  const [failed, setFailed] = useState(false)
  const key = stops.slice(0, MAX_STOPS).join(',')
  useEffect(() => {
    if (!SERVICE_BASE || !key) return
    const base = SERVICE_BASE
    const ctl = new AbortController()
    let busy = false
    setLoaded(false)
    const tick = async () => {
      if (busy) return
      busy = true
      try {
        const signal = AbortSignal.any([ctl.signal, AbortSignal.timeout(5000)])
        const results = await Promise.all(key.split(',').map(id => getDepartures(base, id, signal)))
        if (!ctl.signal.aborted) { setValue(results); setFailed(false); setLoaded(true) }
      } catch {
        if (!ctl.signal.aborted) { setValue([]); setFailed(true); setLoaded(true) }
      } finally {
        busy = false
      }
    }
    void tick()
    const timer = window.setInterval(tick, 20000)
    return () => { ctl.abort(); window.clearInterval(timer) }
  }, [key])
  return { value, loaded, failed, enabled: !!SERVICE_BASE }
}
