import { describe, expect, it } from 'vitest'
import { distanceToLine, metres, replan, worthKeeping, type Fix } from '../src/state/tracking'

const fix = (lat: number, lon: number, at = 0, accuracy = 10): Fix => ({ lat, lon, accuracy, heading: null, at })
// a straight path running north along a meridian
const line: [number, number][] = [
  [-122.06, 37.0],
  [-122.06, 37.002],
]

describe('following the route', () => {
  it('measures how far you are from the line', () => {
    expect(distanceToLine({ lat: 37.001, lon: -122.06 }, line)).toBeLessThan(0.5)
    expect(distanceToLine({ lat: 37.001, lon: -122.0596 }, line)).toBeCloseTo(35.6, 0)
  })
  it('plans again after 20 m, after 30 s, or at once when off the route', () => {
    const last = { lat: 37.0, lon: -122.06, at: 0 }
    expect(replan(null, fix(37, -122.06), line)).toEqual({ again: true, offRoute: false })
    expect(replan(last, fix(37.0001, -122.06, 1000), line).again).toBe(false)
    expect(replan(last, fix(37.0003, -122.06, 1000), line).again).toBe(true)
    expect(replan(last, fix(37.0001, -122.06, 31_000), line).again).toBe(true)
    expect(replan(last, fix(37.0005, -122.0594, 2000), line)).toEqual({ again: true, offRoute: true })
  })
  it('does not call a vague fix off the route', () => {
    const last = { lat: 37.0, lon: -122.06, at: 0 }
    expect(replan(last, fix(37.0001, -122.0596, 1000, 60), line).offRoute).toBe(false)
  })
  it('keeps fixes that move, sharpen or age, and drops jitter', () => {
    const a = fix(37, -122.06, 0, 20)
    expect(worthKeeping(a, fix(37.00001, -122.06, 1000, 20))).toBe(false)
    expect(worthKeeping(a, fix(37.0001, -122.06, 1000, 20))).toBe(true)
    expect(worthKeeping(a, fix(37, -122.06, 1000, 8))).toBe(true)
    expect(worthKeeping(a, fix(37, -122.06, 6000, 20))).toBe(true)
    expect(metres({ lat: 37, lon: -122.06 }, { lat: 37.001, lon: -122.06 })).toBeCloseTo(111.2, 0)
  })
})
