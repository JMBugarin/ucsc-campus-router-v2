import { afterEach, describe, expect, it, vi } from 'vitest'
import { alertsFor, getAlerts, getVehicles, recent } from '../src/transit/liveClient'

const respond = (json: unknown, status = 200) => vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify(json), { status }))
afterEach(() => vi.restoreAllMocks())

describe('live buses', () => {
  it('accepts a well-formed vehicles reply', async () => {
    respond({ status: { source_time: 1, fetched_at: null, freshness: 'fresh' }, vehicles: [{ id: '1', lat: 37, lon: -122, trip: 't', occupancy: 'standing' }] })
    expect((await getVehicles('/svc')).vehicles[0].occupancy).toBe('standing')
  })
  it('rejects nonsense instead of drawing it', async () => {
    respond({ status: { freshness: 'fresh' }, vehicles: [{ id: '1', lat: 900, lon: -122 }] })
    await expect(getVehicles('/svc')).rejects.toThrow()
    respond({ status: { freshness: 'fresh' }, vehicles: [{ id: '1', lat: 37, lon: -122, occupancy: 'roomy' }] })
    await expect(getVehicles('/svc')).rejects.toThrow()
    respond({}, 503)
    await expect(getAlerts('/svc')).rejects.toThrow()
  })
  it('keeps only recent reports', () => {
    expect(recent({ id: '1', lat: 0, lon: 0, time: 1000 }, 1100)).toBe(true)
    expect(recent({ id: '1', lat: 0, lon: 0, time: 1000 }, 1300)).toBe(false)
  })
  it('picks the alerts that touch a trip, and ones meant for everyone', () => {
    const alerts = [
      { id: 'a', header: 'detour', routes: ['18'] },
      { id: 'b', header: 'other route', routes: ['3'] },
      { id: 'c', header: 'stop closed', stops: ['1168'] },
      { id: 'd', header: 'systemwide' },
    ]
    expect(alertsFor(alerts, ['18'], ['1168']).map((a) => a.id)).toEqual(['a', 'c', 'd'])
  })
})
