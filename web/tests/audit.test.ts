import { describe, expect, it } from 'vitest'
import { AuditStore, EMPTY_DRAFT, guideEntry, pacificDate } from '../src/state/audit'
import { readGuide } from '../scripts/rooms.mjs'

function memoryStorage(): Storage {
  const m = new Map<string, string>()
  return {
    get length() {
      return m.size
    },
    key: (i: number) => [...m.keys()][i] ?? null,
    getItem: (k: string) => m.get(k) ?? null,
    setItem: (k: string, v: string) => void m.set(k, v),
    removeItem: (k: string) => void m.delete(k),
    clear: () => m.clear(),
  }
}

describe('audit drafts', () => {
  it('turn into an entry the data build accepts', () => {
    const entry = guideEntry(
      { ...EMPTY_DRAFT, access: 'outside', door: [37.00031234567, -122.0634], doorLabel: ' Courtyard door ', note: 'Corner room facing the trees', steps: 'Through the glass doors\n\n Left past the stairwell ', stepFree: 'no' },
      '2026-11-20',
    )
    expect(entry).toEqual({
      access: 'outside',
      entrance: { lat: 37.000312, lon: -122.0634, label: 'Courtyard door' },
      note: 'Corner room facing the trees',
      steps: ['Through the glass doors', 'Left past the stairwell'],
      step_free: false,
      checked: '2026-11-20',
      source: 'walk',
    })
    expect(readGuide('baskin-engineering:152', entry, [37.00043, -122.063285]).errors).toEqual([])
  })
  it('record nothing until a field is filled', () => {
    expect(guideEntry(EMPTY_DRAFT, '2026-11-20')).toBeNull()
  })
  it('use the Pacific date', () => {
    expect(pacificDate(new Date('2026-11-21T05:30:00Z'))).toBe('2026-11-20')
  })
  it('persist, export every audited room and place a door from a map tap', () => {
    const storage = memoryStorage()
    const a = new AuditStore(() => storage)
    a.set('baskin-engineering:152', { note: 'Corner room' })
    a.set('mchenry-library:1340', { access: 'library' })
    expect(a.tap(37, -122)).toBe(false)
    a.startPick('baskin-engineering:152')
    expect(a.tap(37.0003, -122.0634)).toBe(true)
    expect(a.picking).toBeNull()
    const again = new AuditStore(() => storage)
    expect(again.get('baskin-engineering:152').door).toEqual([37.0003, -122.0634])
    expect(Object.keys(again.all('2026-11-20'))).toEqual(['baskin-engineering:152', 'mchenry-library:1340'])
    again.clear('mchenry-library:1340')
    expect(Object.keys(again.all('2026-11-20'))).toEqual(['baskin-engineering:152'])
  })
  it('keep working when storage is blocked', () => {
    const a = new AuditStore(() => {
      throw new Error('blocked')
    })
    a.set('k:1', { note: 'x' })
    expect(a.get('k:1').note).toBe('x')
    expect(Object.keys(a.all('2026-11-20'))).toEqual(['k:1'])
  })
})
