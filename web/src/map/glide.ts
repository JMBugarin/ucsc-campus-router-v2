import { metres } from '../state/tracking'

export interface GlideFix {
  lat: number
  lon: number
  accuracy: number
  /** epoch ms when the fix was taken */
  at?: number
  /** metres per second, when the device reports it */
  speed?: number | null
}

export interface Shown {
  lat: number
  lon: number
  accuracy: number
}

const STILL_MPS = 0.4
const JUMP_M = 80
const STALE_MS = 8000

/**
 * Where to draw someone between position fixes, which arrive about once a second at best. The dot carries on at the
 * walker's pace after each fix instead of waiting for the next one, and each new fix is blended in over one fix interval
 * so it never jumps. Times are in milliseconds on one clock (the animation frame clock).
 */
export class Glide {
  private fix: GlideFix | null = null
  private from: Shown | null = null
  private pushedAt = 0
  /** degrees per millisecond */
  private v = { lat: 0, lon: 0 }
  /** the usual time between fixes */
  private gap = 1000

  push(f: GlideFix, now: number) {
    const prev = this.fix
    let from = prev ? this.at(now) : null
    if (prev && prev.at !== undefined && f.at !== undefined) {
      const dt = f.at - prev.at
      const d = metres(prev, f)
      if (dt <= 0 || dt > STALE_MS || d > JUMP_M) {
        this.v = { lat: 0, lon: 0 }
        if (d > JUMP_M) from = null
      } else {
        this.gap = Math.min(2500, Math.max(250, this.gap * 0.6 + dt * 0.4))
        const still = f.speed != null ? f.speed < STILL_MPS : d < Math.min(3, f.accuracy * 0.25) || (d / dt) * 1000 < STILL_MPS
        this.v = still ? { lat: 0, lon: 0 } : { lat: this.v.lat * 0.4 + ((f.lat - prev.lat) / dt) * 0.6, lon: this.v.lon * 0.4 + ((f.lon - prev.lon) / dt) * 0.6 }
      }
    } else if (prev) {
      this.v = { lat: 0, lon: 0 }
    }
    this.fix = f
    this.from = from
    this.pushedAt = now
  }

  clear() {
    this.fix = null
    this.from = null
    this.v = { lat: 0, lon: 0 }
  }

  at(now: number): Shown | null {
    const f = this.fix
    if (!f) return null
    const t = Math.max(0, now - this.pushedAt)
    const ahead = Math.min(t, this.gap * 1.5)
    const lat = f.lat + this.v.lat * ahead
    const lon = f.lon + this.v.lon * ahead
    if (!this.from || t >= this.gap) return { lat, lon, accuracy: f.accuracy }
    const k = t / this.gap
    const e = 1 - (1 - k) * (1 - k)
    return {
      lat: this.from.lat + (lat - this.from.lat) * e,
      lon: this.from.lon + (lon - this.from.lon) * e,
      accuracy: this.from.accuracy + (f.accuracy - this.from.accuracy) * e,
    }
  }

  /** whether the dot will still move after `now`, so another frame is worth drawing */
  moving(now: number): boolean {
    if (!this.fix) return false
    const t = now - this.pushedAt
    return (!!this.from && t < this.gap) || ((this.v.lat !== 0 || this.v.lon !== 0) && t < this.gap * 1.5)
  }
}
