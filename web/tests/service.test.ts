import { afterEach, expect, test, vi } from 'vitest'
import { displayState, getDepartures, type Departures, type Status } from '../src/transit/serviceClient'
import { freshPredictions, predictedDelay, serviceState } from '../src/transit/serviceState'

const status = (freshness: Status['freshness']): Status => ({ generation: 1, source_time: 1, fetched_at: null, processed_at: null, freshness })
const respond = (body: unknown, ok = true, code = 200) => vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok, status: code, json: async () => body }))
const fresh: Departures = { status: status('fresh'), departures: [{ trip: 't', stop: 's', time: 10_600, event_time: 10_000, kind: 'fresh' }] }
const stale: Departures = { status: status('stale'), departures: [{ trip: 't', stop: 's', time: 10_600, event_time: 1, kind: 'stale' }] }
const scheduled: Departures = { status: status('stale'), departures: [{ trip: 't', stop: 's', time: 10_600, event_time: null, kind: 'scheduled' }] }

afterEach(() => vi.unstubAllGlobals())

test('rejects failed and malformed responses', async () => {
  respond(null, false, 503)
  await expect(getDepartures('', 'a')).rejects.toThrow('503')
  respond({ departures: [] })
  await expect(getDepartures('', 'a')).rejects.toThrow('Invalid')
  respond({ status: status('fresh'), departures: [{ trip: 'a', stop: 'b', time: 1, kind: 'cancelled' }] })
  await expect(getDepartures('', 'a')).rejects.toThrow('Invalid')
})

test('labels scheduled fallback without promoting source freshness', () => {
  expect(displayState(scheduled)).toBe('scheduled')
})

test('only fresh predictions from a fresh feed are used', () => {
  expect(freshPredictions([fresh, stale, scheduled])).toHaveLength(1)
  expect(freshPredictions([{ ...fresh, status: status('stale') }])).toHaveLength(0)
})

test('service state falls back explicitly', () => {
  expect(serviceState(false, true, false, [fresh])).toBe('off')
  expect(serviceState(true, false, false, [])).toBe('loading')
  expect(serviceState(true, true, true, [])).toBe('unavailable')
  expect(serviceState(true, true, false, [stale, fresh])).toBe('fresh')
  expect(serviceState(true, true, false, [stale])).toBe('stale')
  expect(serviceState(true, true, false, [scheduled])).toBe('stale')
  expect(serviceState(true, true, false, [{ status: status('unavailable'), departures: [] }])).toBe('scheduled')
})

test('delay compares the prediction against the bundled schedule', () => {
  const p = freshPredictions([fresh])
  expect(predictedDelay(p, 't', 's', 3_900, 3_600, 10_000)).toBe(300)
  expect(predictedDelay(p, 't', 'other', 3_900, 3_600, 10_000)).toBeNull()
  expect(predictedDelay(p, 't', 's', 3_900 + 86_400, 3_600, 10_000)).toBeNull()
})
