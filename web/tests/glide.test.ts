import { describe, expect, it } from 'vitest'
import { Glide } from '../src/map/glide'
import { metres } from '../src/state/tracking'

const M_PER_DEG = 110_574
// walking north at 1.4 m/s, a fix every second
const walker = (ms: number) => ({ lat: 37 + (1.4 * ms) / 1000 / M_PER_DEG, lon: -122.06 })

describe('the location dot between fixes', () => {
  it('starts at the first fix', () => {
    const g = new Glide()
    g.push({ ...walker(0), accuracy: 5, at: 0, speed: 1.4 }, 0)
    expect(g.at(0)).toMatchObject(walker(0))
  })

  it('moves every frame while walking, never jumps, and stays close to the walker', () => {
    const g = new Glide()
    let prev: { lat: number; lon: number } | null = null
    let biggestStep = 0
    let worstLag = 0
    for (let now = 0; now <= 10_000; now += 16) {
      if (now % 1008 === 0) g.push({ ...walker(now), accuracy: 5, at: now, speed: 1.4 }, now)
      const y = g.at(now)!
      if (prev) biggestStep = Math.max(biggestStep, metres(prev, y))
      if (now > 3000) worstLag = Math.max(worstLag, metres(y, walker(now)))
      if (prev && now > 1100) expect(metres(prev, y)).toBeGreaterThan(0)
      prev = y
    }
    expect(biggestStep).toBeLessThan(0.1)
    expect(worstLag).toBeLessThan(0.5)
  })

  it('stays put when standing still, however the fixes wobble', () => {
    const g = new Glide()
    g.push({ lat: 37, lon: -122.06, accuracy: 10, at: 0, speed: 0 }, 0)
    g.push({ lat: 37.00002, lon: -122.06, accuracy: 10, at: 1000, speed: 0 }, 1000)
    const a = g.at(2000)!
    expect(g.at(5000)).toEqual(a)
    expect(g.moving(5000)).toBe(false)
  })

  it('treats a small wobble as standing still when the device gives no speed', () => {
    const g = new Glide()
    g.push({ lat: 37, lon: -122.06, accuracy: 15, at: 0 }, 0)
    g.push({ lat: 37.00001, lon: -122.06, accuracy: 15, at: 1000 }, 1000)
    expect(g.at(2500)).toEqual(g.at(9000))
  })

  it('goes straight to a fix far from the last one, and stops guessing after a long gap', () => {
    const g = new Glide()
    g.push({ lat: 37, lon: -122.06, accuracy: 5, at: 0, speed: 1.4 }, 0)
    g.push({ lat: 37.002, lon: -122.06, accuracy: 5, at: 1000, speed: 1.4 }, 1000)
    expect(g.at(1000)).toMatchObject({ lat: 37.002, lon: -122.06 })
    g.push({ lat: 37.00201, lon: -122.06, accuracy: 5, at: 20_000, speed: 1.4 }, 20_000)
    expect(g.at(30_000)).toEqual(g.at(25_000))
  })
})
