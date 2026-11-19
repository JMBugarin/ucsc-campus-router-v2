import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { buildRooms, floorFromNumber, floorOf, readGuide } from '../scripts/rooms.mjs'
import { doorSentence, floorText, recentStore, relation, roomGroups } from '../src/data/rooms'
import { SearchIndex } from '../src/data/search'
import type { Place, PlacesFile } from '../src/data/types'

const read = (f: string) => JSON.parse(readFileSync(f, 'utf8'))
const places = (read('public/data/places.json') as PlacesFile).places
const byId = new Map(places.map((p) => [p.id, p]))
const rooms = places.filter((p) => p.kind === 'room')
const sources = {
  buildings: read('../data/buildings.json').buildings,
  extraAliases: read('../data/search_aliases.json'),
  classrooms: read('../data/classrooms.json').rooms,
  overrides: read('../data/rooms.json').overrides ?? {},
}

describe('room places', () => {
  it('match the committed data sources (run npm run data after editing data/)', () => {
    const built = buildRooms(sources)
    expect(built.errors).toEqual([])
    const byKey = (a: Place, b: Place) => a.id.localeCompare(b.id)
    expect([...rooms].sort(byKey)).toEqual(JSON.parse(JSON.stringify(built.rooms)).sort(byKey))
  })
  it('cover every general-assignment classroom', () => {
    expect(rooms).toHaveLength(read('../data/classrooms.json').rooms.length)
    expect(rooms.every((r) => r.room?.door && r.entrances?.length)).toBe(true)
  })
  it('route to the doors nearest the room, not the main entrance', () => {
    const thimann = byId.get('thimann-labs-101')!
    expect(thimann.room?.door?.meters).toBeLessThanOrEqual(6)
    expect(thimann.entrances).toEqual([[thimann.room!.door!.lat, thimann.room!.door!.lon]])
    expect(byId.get('baskin-engineering-372')!.room?.door?.meters).toBeLessThanOrEqual(10)
    for (const r of rooms) expect(r.entrances!.length).toBeLessThanOrEqual(2)
  })
  it('list their rooms on the building, lowest floor first', () => {
    expect(byId.get('baskin-engineering')!.roomIds).toEqual(['baskin-engineering-152', 'baskin-engineering-156', 'baskin-engineering-165', 'baskin-engineering-169', 'baskin-engineering-372'])
  })
})

describe('floors', () => {
  it('reads the floor a room number implies', () => {
    expect(floorFromNumber('152')).toBe('1')
    expect(floorFromNumber('071')).toBe('0')
    expect(floorFromNumber('B206')).toBe('2')
    expect(floorFromNumber('3201')).toBe('2')
    expect(floorFromNumber('1340')).toBe('3')
    expect(floorFromNumber('Hall')).toBeNull()
  })
  it('trusts a campus-map level more when the room number agrees', () => {
    expect(floorOf('L3', '372')).toEqual({ label: '3', basis: 'map+number' })
    expect(floorOf('L1', '001')).toEqual({ label: '1', basis: 'map' })
    expect(floorOf('L1', '152', { floor: '2' })).toEqual({ label: '2', basis: 'checked' })
    expect(floorOf(null, '152')).toBeUndefined()
  })
  it('labels the source only when the campus map alone says so', () => {
    expect(floorText(byId.get('baskin-engineering-372')!.room)).toBe('Floor 3')
    expect(floorText(byId.get('classroom-unit-001')!.room)).toBe('Floor 1 (campus map)')
    expect(floorText(byId.get('social-sciences-2-071')!.room)).toBe('Lower level (floor 0)')
  })
})

describe('room guides', () => {
  const at: [number, number] = [37.00043, -122.063285]
  it('accepts a complete guide', () => {
    const r = readGuide('baskin-engineering:152', {
      access: 'outside',
      entrance: { lat: 37.0005, lon: -122.0631, label: 'Courtyard door' },
      floor: '1',
      wing: 'North wing',
      note: 'Corner room facing the trees',
      steps: ['Through the glass doors', 'Second door on the left'],
      step_free: true,
      elevator: 'By the main lobby',
      checked: '2026-11-20',
    }, at)
    expect(r.errors).toEqual([])
    expect(r.guide).toMatchObject({ access: 'outside', stepFree: true, checked: '2026-11-20', source: 'walk' })
  })
  it('rejects guides without a checked date, with unknown fields, or with a far-away door', () => {
    expect(readGuide('k', { note: 'x' }).errors.join()).toMatch(/checked/)
    expect(readGuide('k', { note: 'x', checked: '2026-11-20', colour: 'red' }).errors.join()).toMatch(/unknown field/)
    expect(readGuide('k', { access: 'roof', checked: '2026-11-20' }).errors.join()).toMatch(/one of/)
    expect(readGuide('k', { entrance: { lat: 37.01, lon: -122.06 }, checked: '2026-11-20' }, at).errors.join()).toMatch(/from the room/)
    expect(readGuide('k', { steps: ['a', 'b', 'c', 'd', 'e', 'f'], checked: '2026-11-20' }).errors.join()).toMatch(/1 to 5/)
  })
  it('fails the build for overrides that name no known room', () => {
    expect(buildRooms({ ...sources, overrides: { 'baskin-engineering:999': { note: 'x', checked: '2026-11-20' } } }).errors.join()).toMatch(/no such building and room/)
  })
  it('routes only to a checked door and splits the building by access', () => {
    const built = buildRooms({
      ...sources,
      overrides: { 'baskin-engineering:152': { access: 'outside', entrance: { lat: 37.0003, lon: -122.0634, label: 'Courtyard door' }, checked: '2026-11-20' } },
    })
    const all = new Map<string, Place>([...places.filter((p) => p.kind !== 'room'), ...built.rooms].map((p) => [p.id, p]))
    const be152 = all.get('baskin-engineering-152')!
    expect(be152.entrances).toEqual([[37.0003, -122.0634]])
    expect(be152.room?.door).toMatchObject({ checked: true, label: 'Courtyard door' })
    const groups = roomGroups(all.get('baskin-engineering')!, all)
    expect(groups.map((g) => g.title)).toEqual(['Outside access', 'Not checked yet'])
    expect(groups[0].rooms.map((r) => r.id)).toEqual(['baskin-engineering-152'])
  })
  it('groups unchecked buildings by floor', () => {
    expect(roomGroups(byId.get('baskin-engineering')!, byId).map((g) => g.title)).toEqual(['Floor 1', 'Floor 3'])
  })
})

describe('door sentences', () => {
  it('describes the room from the door in plain words', () => {
    expect(doorSentence(byId.get('baskin-engineering-152')!.room)).toBe('The room is about 30 m south-west of this door, on floor 1.')
    expect(doorSentence(byId.get('thimann-labs-101')!.room)).toBe('The room is right by this door, on floor 1.')
    expect(relation([37, -122.06], [37.0002, -122.06]).toward).toBe('north')
  })
})

describe('room search', () => {
  const idx = new SearchIndex(places)
  const first = (q: string) => idx.search(q, 3)[0]?.id
  it('finds rooms the way students type them', () => {
    expect(first('BE 152')).toBe('baskin-engineering-152')
    expect(first('be152')).toBe('baskin-engineering-152')
    expect(first('baskin 165')).toBe('baskin-engineering-165')
    expect(first('J Baskin Engr 372')).toBe('baskin-engineering-372')
    expect(first('e2 192')).toBe('engineering-2-192')
    expect(first('mchenry 1340')).toBe('mchenry-library-1340')
    expect(first('ems b206')).toBe('earth-marine-sciences-b206')
    expect(first('Humn Lecture Hall')).toBe('humanities-lecture-hall-206')
  })
  it('keeps buildings ahead of their rooms when no room number is typed', () => {
    for (const q of ['baskin', 'mchenry', 'thimann', 'social sciences 2', 'kresge']) expect(byId.get(first(q)!)!.kind).not.toBe('room')
    expect(first('mchenry')).toBe('mchenry-library')
  })
  it('lists every building that has the typed room number', () => {
    const ids = idx.search('152', 10).map((p) => p.id)
    expect(ids).toEqual(expect.arrayContaining(['baskin-engineering-152', 'stevenson-academic-152']))
  })
})

describe('recent places', () => {
  it('keeps the newest first without duplicates', () => {
    const mem = new Map<string, string>()
    const storage = { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => void mem.set(k, v) } as unknown as Storage
    const r = recentStore('t', 3, () => storage)
    r.push('a')
    r.push('b')
    r.push('a')
    r.push('c')
    expect(r.push('d')).toEqual(['d', 'c', 'a'])
  })
  it('works when storage throws', () => {
    const r = recentStore('t', 3, () => {
      throw new Error('blocked')
    })
    expect(r.get()).toEqual([])
    expect(r.push('a')).toEqual(['a'])
  })
})
