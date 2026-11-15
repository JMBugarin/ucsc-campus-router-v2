import type { Departure, Departures } from './serviceClient'

export type ServiceState = 'off' | 'loading' | 'unavailable' | 'fresh' | 'stale' | 'scheduled'

export function freshPredictions(values: Departures[]): Departure[] {
  return values.flatMap(v => (v.status.freshness === 'fresh' ? v.departures.filter(d => d.kind === 'fresh') : []))
}

export function serviceState(enabled: boolean, loaded: boolean, failed: boolean, values: Departures[]): ServiceState {
  if (!enabled) return 'off'
  if (failed) return 'unavailable'
  if (!loaded) return 'loading'
  if (freshPredictions(values).length) return 'fresh'
  if (values.some(v => v.status.freshness === 'stale')) return 'stale'
  return 'scheduled'
}

export const SERVICE_NOTES: Record<Exclude<ServiceState, 'off'>, string> = {
  loading: 'Checking the transit service…',
  unavailable: 'Transit service unavailable; showing the bundled schedule.',
  fresh: 'Live predictions from the Classmap transit service. Times in Pacific time.',
  stale: 'Transit predictions are stale; showing the bundled schedule.',
  scheduled: 'No fresh predictions; showing the bundled schedule.',
}

/** Seconds a fresh prediction runs behind (+) or ahead (−) of the bundled schedule. */
export function predictedDelay(predictions: Departure[], trip: string, stop: string, scheduledSecs: number, nowSecs: number, nowEpoch: number): number | null {
  const p = predictions.find(x => x.trip === trip && x.stop === stop)
  if (!p) return null
  const delay = p.time - nowEpoch - (scheduledSecs - nowSecs)
  return Math.abs(delay) > 6 * 3600 ? null : delay
}
