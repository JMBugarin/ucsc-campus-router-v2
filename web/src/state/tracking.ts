/** Following the device's position while someone is on their way, and deciding when the route needs redrawing. */

export interface Fix {
  lat: number
  lon: number
  accuracy: number
  /** degrees from north, when the device is moving and knows */
  heading: number | null
  /** epoch ms */
  at: number
}

const R = 6371008.8
const rad = (d: number) => (d * Math.PI) / 180
export function metres(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const dLat = rad(b.lat - a.lat)
  const dLon = rad(b.lon - a.lon)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)))
}

/** How far a point is from a line given as [lon, lat] points. */
export function distanceToLine(p: { lat: number; lon: number }, line: [number, number][]): number {
  if (!line.length) return Infinity
  const kx = Math.cos(rad(p.lat)) * 111320
  const ky = 110540
  let best = Infinity
  for (let i = 0; i < line.length; i++) {
    const ax = (line[i][0] - p.lon) * kx
    const ay = (line[i][1] - p.lat) * ky
    if (i === 0) best = Math.hypot(ax, ay)
    if (i + 1 >= line.length) break
    const bx = (line[i + 1][0] - p.lon) * kx
    const by = (line[i + 1][1] - p.lat) * ky
    const dx = bx - ax
    const dy = by - ay
    const l2 = dx * dx + dy * dy
    const u = l2 ? Math.max(0, Math.min(1, -(ax * dx + ay * dy) / l2)) : 0
    best = Math.min(best, Math.hypot(ax + u * dx, ay + u * dy))
  }
  return best
}

export const REPLAN_MOVED_M = 20
export const REPLAN_AGE_MS = 30_000
export const OFF_ROUTE_M = 35

/**
 * Whether to plan again from `fix`: the first fix, a fix far enough from where the route was last planned, an old plan,
 * or a fix off the route line (allowing for how uncertain the fix is). `offRoute` says which.
 */
export function replan(last: { lat: number; lon: number; at: number } | null, fix: Fix, line: [number, number][]): { again: boolean; offRoute: boolean } {
  if (!last) return { again: true, offRoute: false }
  const off = line.length > 1 && distanceToLine(fix, line) > Math.max(OFF_ROUTE_M, Math.min(fix.accuracy, 80))
  if (off) return { again: true, offRoute: true }
  return { again: metres(last, fix) >= REPLAN_MOVED_M || fix.at - last.at >= REPLAN_AGE_MS, offRoute: false }
}

/** Keeps every fix that matters: a few metres of movement, a much better accuracy, or a few seconds passing. */
export function worthKeeping(prev: Fix | null, next: Fix): boolean {
  if (!prev) return true
  return metres(prev, next) >= 3 || next.accuracy < prev.accuracy - 5 || next.at - prev.at >= 5000
}

/** watchPosition, paused while the page is hidden to save battery. */
export class Tracker {
  private id: number | null = null
  private last: Fix | null = null
  private hidden = () => (document.visibilityState === 'hidden' ? this.pause() : this.resume())
  private running = false

  constructor(
    private onFix: (f: Fix) => void,
    private onError: (code: number) => void,
  ) {}

  get active() {
    return this.running
  }

  start() {
    if (this.running || !('geolocation' in navigator)) return
    this.running = true
    document.addEventListener('visibilitychange', this.hidden)
    if (document.visibilityState !== 'hidden') this.resume()
  }

  stop() {
    this.running = false
    document.removeEventListener('visibilitychange', this.hidden)
    this.pause()
  }

  private resume() {
    if (!this.running || this.id !== null) return
    this.id = navigator.geolocation.watchPosition(
      (p) => {
        const fix: Fix = { lat: p.coords.latitude, lon: p.coords.longitude, accuracy: p.coords.accuracy, heading: Number.isFinite(p.coords.heading) && (p.coords.speed ?? 0) > 0.3 ? p.coords.heading : null, at: Date.now() }
        if (!worthKeeping(this.last, fix)) return
        this.last = fix
        this.onFix(fix)
      },
      (e) => {
        this.onError(e.code)
        if (e.code === 1) this.stop()
      },
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 30_000 },
    )
  }

  private pause() {
    if (this.id !== null) navigator.geolocation.clearWatch(this.id)
    this.id = null
  }
}
