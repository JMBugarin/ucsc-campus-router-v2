/** Address search for trip starts and ends off campus, through Photon (komoot's OpenStreetMap geocoder). */
export interface Address {
  label: string
  lat: number
  lon: number
}

const BBOX = '-122.35,36.85,-121.55,37.30'

/** Only called when someone presses search, so typing a room never leaves the device. */
export async function searchAddresses(q: string, signal?: AbortSignal, get: typeof fetch = fetch): Promise<Address[]> {
  const text = q.trim().slice(0, 120)
  if (text.length < 3) return []
  const url = `https://photon.komoot.io/api/?q=${encodeURIComponent(text)}&limit=6&lat=36.975&lon=-122.03&lang=en&bbox=${BBOX}`
  const r = await get(url, { signal, credentials: 'omit' })
  if (!r.ok) throw new Error(`geocoder ${r.status}`)
  const json = (await r.json()) as { features?: { geometry?: { coordinates?: unknown }; properties?: Record<string, unknown> }[] }
  const out: Address[] = []
  for (const f of json.features ?? []) {
    const c = f.geometry?.coordinates
    if (!Array.isArray(c) || !Number.isFinite(c[0]) || !Number.isFinite(c[1])) continue
    const p = f.properties ?? {}
    const str = (k: string) => (typeof p[k] === 'string' ? (p[k] as string) : '')
    const street = [str('housenumber'), str('street')].filter(Boolean).join(' ')
    const label = [str('name'), street, str('city') || str('district')].filter((x, i, all) => x && all.indexOf(x) === i).join(', ')
    if (label) out.push({ label, lat: c[1] as number, lon: c[0] as number })
  }
  return out
}

/** `@36.97,-122.03` ids for places that are a point, not a campus place. */
export const pointId = (lat: number, lon: number) => `@${lat.toFixed(6)},${lon.toFixed(6)}`
export function parsePointId(id: string): [number, number] | null {
  const m = /^@(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)$/.exec(id)
  return m ? [+m[1], +m[2]] : null
}
