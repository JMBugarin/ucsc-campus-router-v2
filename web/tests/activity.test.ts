import { describe, expect, it } from 'vitest'
import { Activity, pacificWeek, type Sender, type Sent, type Store } from '../src/state/activity'

class FakeSender implements Sender {
  recorded: [string, string][] = []
  withdrawn: string[] = []
  next: Sent = 'ok'
  async record(install: string, week: string) {
    if (this.next === 'ok') this.recorded.push([install, week])
    return this.next
  }
  async withdraw(install: string) {
    if (this.next === 'ok') this.withdrawn.push(install)
    return this.next
  }
}
function memory(init: Record<string, string> = {}): Store & { data: Record<string, string> } {
  const data = { ...init }
  return { data, get: (k) => data[k] ?? null, set: (k, v) => void (data[k] = v), remove: (k) => void delete data[k] }
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

function rig(sender: FakeSender | null = new FakeSender(), store = memory()) {
  let now = new Date('2026-11-18T19:00:00Z')
  const a = new Activity(store, sender, () => now)
  return { a, sender: sender!, store, setNow: (t: string) => (now = new Date(t)) }
}

describe('opt-in weekly activity', () => {
  it('weeks start on Monday, Pacific time, across both clock changes', () => {
    expect(pacificWeek(new Date('2026-11-23T07:30:00Z'))).toBe('2026-11-16')
    expect(pacificWeek(new Date('2026-11-23T08:10:00Z'))).toBe('2026-11-23')
    expect(pacificWeek(new Date('2026-11-02T07:59:00Z'))).toBe('2026-10-26')
    expect(pacificWeek(new Date('2026-11-02T08:00:00Z'))).toBe('2026-11-02')
    expect(pacificWeek(new Date('2027-03-15T06:30:00Z'))).toBe('2027-03-08')
    expect(pacificWeek(new Date('2027-03-15T07:00:00Z'))).toBe('2027-03-15')
  })

  it('sends nothing until turned on', async () => {
    const { a, sender } = rig()
    expect(a.install).toBeNull()
    await a.meaningfulAction()
    expect(sender.recorded).toEqual([])
  })

  it('sends one ping per week however many places are opened', async () => {
    const { a, sender, setNow } = rig()
    await a.setOn(true)
    const id = a.install!
    expect(id).toMatch(uuid)
    expect(a.participantCode).toBe(id.slice(0, 8))
    for (let i = 0; i < 4; i++) await a.meaningfulAction()
    setNow('2026-11-23T07:59:00Z')
    await a.meaningfulAction()
    setNow('2026-11-23T08:00:00Z')
    await a.meaningfulAction()
    await a.meaningfulAction()
    expect(sender.recorded).toEqual([
      [id, '2026-11-16'],
      [id, '2026-11-23'],
    ])
  })

  it('sends a ping made offline later, and drops one too old', async () => {
    const { a, sender, store, setNow } = rig()
    await a.setOn(true)
    const id = a.install!
    sender.next = 'failed'
    await a.meaningfulAction()
    sender.next = 'ok'
    setNow('2026-11-30T19:00:00Z')
    await a.meaningfulAction()
    expect(sender.recorded).toEqual([
      [id, '2026-11-16'],
      [id, '2026-11-30'],
    ])
    sender.next = 'failed'
    setNow('2026-12-09T19:00:00Z')
    await a.meaningfulAction()
    sender.next = 'ok'
    setNow('2027-01-20T19:00:00Z')
    await a.flush()
    expect(sender.recorded).toHaveLength(2)
    expect(JSON.parse(store.data.activity_pending_weeks)).toEqual([])
  })

  it('turning it off forgets the id and keeps trying to delete what was sent', async () => {
    const { a, sender } = rig()
    await a.setOn(true)
    const id = a.install!
    await a.meaningfulAction()
    sender.next = 'failed'
    await a.setOn(false)
    expect(a.install).toBeNull()
    expect(sender.withdrawn).toEqual([])
    await a.meaningfulAction()
    sender.next = 'ok'
    await a.flush()
    expect(sender.withdrawn).toEqual([id])
    expect(sender.recorded).toHaveLength(1)
    await a.setOn(true)
    expect(a.install).not.toBe(id)
  })

  it('a build without a server never counts', async () => {
    const store = memory({ activity_install: crypto.randomUUID() })
    const a = new Activity(store, null)
    expect(a.available).toBe(false)
    expect(a.install).toBeNull()
    await a.setOn(true)
    await a.meaningfulAction()
    expect(a.install).toBeNull()
  })

  it('survives a corrupted queue in storage', async () => {
    const { a, sender } = rig(new FakeSender(), memory({ activity_install: crypto.randomUUID(), activity_pending_weeks: '{oops' }))
    await a.meaningfulAction()
    expect(sender.recorded).toHaveLength(1)
  })
})
