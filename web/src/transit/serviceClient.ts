export type Freshness = 'fresh' | 'stale' | 'unavailable'
export type Kind = Freshness | 'scheduled'

export interface Status {
  generation: number | null
  source_time: number | null
  fetched_at: string | null
  processed_at: string | null
  freshness: Freshness
}

export interface Departure {
  trip: string
  stop: string
  time: number
  event_time: number | null
  kind: Kind
}

export interface Departures {
  status: Status
  departures: Departure[]
}

export interface Ops {
  status: Status
  jobs: Record<string, number>
  outcomes: Record<string, number>
  schedule: string | null
}

const FRESHNESS: readonly string[] = ['fresh', 'stale', 'unavailable']
const KINDS: readonly string[] = [...FRESHNESS, 'scheduled']

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)

function validStatus(v: unknown): v is Status {
  return isRecord(v) && FRESHNESS.includes(v.freshness as string)
}

function validDeparture(v: unknown): v is Departure {
  return isRecord(v) && typeof v.trip === 'string' && typeof v.stop === 'string' && Number.isFinite(v.time) && KINDS.includes(v.kind as string)
}

function validCounts(v: unknown): v is Record<string, number> {
  return isRecord(v) && Object.values(v).every(n => Number.isInteger(n) && (n as number) >= 0)
}

async function getJSON(url: string, signal?: AbortSignal): Promise<unknown> {
  const response = await fetch(url, { signal })
  if (!response.ok) throw new Error(`Transit HTTP ${response.status}`)
  return response.json()
}

export async function getDepartures(base: string, stop: string, signal?: AbortSignal): Promise<Departures> {
  const value = await getJSON(`${base}/v1/departures?stop=${encodeURIComponent(stop)}&limit=20`, signal)
  if (!isRecord(value) || !validStatus(value.status) || !Array.isArray(value.departures) || value.departures.length > 100 || !value.departures.every(validDeparture)) {
    throw new Error('Invalid transit response')
  }
  return value as unknown as Departures
}

export async function getOps(base: string, signal?: AbortSignal): Promise<Ops> {
  const value = await getJSON(`${base}/v1/ops`, signal)
  if (!isRecord(value) || !validStatus(value.status) || !validCounts(value.jobs) || !validCounts(value.outcomes) || !(value.schedule === null || typeof value.schedule === 'string')) {
    throw new Error('Invalid ops response')
  }
  return value as unknown as Ops
}

export function displayState(value: Departures): Kind {
  if (value.departures.length && value.departures.every(d => d.kind === 'scheduled')) return 'scheduled'
  return value.status.freshness
}
