import type { Freshness } from './serviceClient'

export type Occupancy = 'empty' | 'many_seats' | 'few_seats' | 'standing' | 'crushed' | 'full' | 'not_accepting'
export interface LiveStatus {
  source_time: number | null
  fetched_at: string | null
  freshness: Freshness
}
export interface Vehicle {
  id: string
  label?: string
  trip?: string
  route?: string
  lat: number
  lon: number
  bearing?: number
  time?: number
  stop?: string
  status?: string
  occupancy?: Occupancy
}
export interface Alert {
  id: string
  header: string
  description?: string
  url?: string
  effect?: string
  routes?: string[]
  stops?: string[]
  trips?: string[]
}

export const OCCUPANCY_TEXT: Record<Occupancy, string> = {
  empty: 'Lots of seats',
  many_seats: 'Seats available',
  few_seats: 'Few seats',
  standing: 'Standing room',
  crushed: 'Very full',
  full: 'Full',
  not_accepting: 'Not taking riders',
}
const OCCUPANCY = Object.keys(OCCUPANCY_TEXT)
const FRESHNESS = ['fresh', 'stale', 'unavailable']
const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const optString = (v: unknown) => v === undefined || typeof v === 'string'
const strings = (v: unknown) => v === undefined || (Array.isArray(v) && v.every((x) => typeof x === 'string'))

function validStatus(v: unknown): v is LiveStatus {
  return isRecord(v) && FRESHNESS.includes(v.freshness as string)
}
function validVehicle(v: unknown): v is Vehicle {
  return (
    isRecord(v) &&
    typeof v.id === 'string' &&
    Number.isFinite(v.lat) &&
    Number.isFinite(v.lon) &&
    Math.abs(v.lat as number) <= 90 &&
    Math.abs(v.lon as number) <= 180 &&
    optString(v.trip) &&
    optString(v.route) &&
    optString(v.label) &&
    (v.occupancy === undefined || OCCUPANCY.includes(v.occupancy as string)) &&
    (v.time === undefined || Number.isFinite(v.time))
  )
}
function validAlert(v: unknown): v is Alert {
  return isRecord(v) && typeof v.id === 'string' && typeof v.header === 'string' && optString(v.description) && optString(v.url) && strings(v.routes) && strings(v.stops) && strings(v.trips)
}

async function getJSON(url: string, signal?: AbortSignal): Promise<unknown> {
  const r = await fetch(url, { signal })
  if (!r.ok) throw new Error(`Transit HTTP ${r.status}`)
  return r.json()
}

export async function getVehicles(base: string, signal?: AbortSignal): Promise<{ status: LiveStatus; vehicles: Vehicle[] }> {
  const v = await getJSON(`${base}/v1/vehicles`, signal)
  if (!isRecord(v) || !validStatus(v.status) || !Array.isArray(v.vehicles) || v.vehicles.length > 500 || !v.vehicles.every(validVehicle)) throw new Error('Invalid vehicles response')
  return v as unknown as { status: LiveStatus; vehicles: Vehicle[] }
}

export async function getAlerts(base: string, signal?: AbortSignal): Promise<{ status: LiveStatus; alerts: Alert[] }> {
  const v = await getJSON(`${base}/v1/alerts`, signal)
  if (!isRecord(v) || !validStatus(v.status) || !Array.isArray(v.alerts) || v.alerts.length > 200 || !v.alerts.every(validAlert)) throw new Error('Invalid alerts response')
  return v as unknown as { status: LiveStatus; alerts: Alert[] }
}

/** A vehicle whose own report is recent enough to draw: within three minutes. */
export const recent = (v: Vehicle, nowSecs: number) => v.time === undefined || nowSecs - v.time <= 180

/** Alerts that touch these routes or stops, plus ones that name none (they apply to everyone). */
export function alertsFor(alerts: Alert[], routes: string[], stops: string[]): Alert[] {
  return alerts.filter((a) => (!a.routes?.length && !a.stops?.length && !a.trips?.length) || a.routes?.some((r) => routes.includes(r)) || a.stops?.some((s) => stops.includes(s)))
}
