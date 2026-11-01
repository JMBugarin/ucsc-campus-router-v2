import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { parseHash } from '../src/state/hashRoute'
import { SearchIndex, editDistance } from '../src/data/search'
import type { PlacesFile } from '../src/data/types'

const idx = new SearchIndex((JSON.parse(readFileSync('public/data/places.json', 'utf8')) as PlacesFile).places)
const top = (q: string, n = 1) => idx.search(q, n).map((p) => p.name)

describe('search', () => {
  it('finds exact and partial names', () => {
    expect(top('McHenry Library')[0]).toBe('McHenry Library')
    expect(top('mchen')[0]).toBe('McHenry Library')
  })
  it('knows aliases and nicknames', () => {
    expect(top('BE')[0]).toBe('Jack Baskin Engineering')
    expect(top('S&E Library')[0]).toBe('Science & Engineering Library')
    expect(top('Kresge')[0]).toMatch(/Kresge/)
  })
  it('tolerates typos', () => {
    expect(top('mchenery library')[0]).toBe('McHenry Library')
    expect(top('Thimman')[0]).toMatch(/Thimann/)
    expect(top('quary plaza')[0]).toBe('Quarry Plaza')
  })
  it('finds landmarks and categories by word', () => {
    expect(top('science hill')[0]).toBe('Science Hill')
    expect(idx.search('coffee', 8).some((p) => p.kind === 'dining')).toBe(true)
  })
  it('filters by category', () => {
    expect(idx.search('', 50, 'college').every((p) => p.kind === 'college')).toBe(true)
  })
  it('edit distance', () => {
    expect(editDistance('thimann', 'thimman')).toBe(2)
    expect(editDistance('library', 'libary')).toBe(1)
    expect(editDistance('mchenry', 'mchenyr')).toBe(1)
    expect(editDistance('abc', 'xyzxyz')).toBeGreaterThan(2)
  })
})

describe('hash routes', () => {
  it('keeps empty segments so a missing origin stays missing', () => {
    expect(parseHash('#/r//mchenry-library')).toEqual({ name: 'directions', from: undefined, to: 'mchenry-library' })
    expect(parseHash('#/r/quarry-plaza/mchenry-library')).toEqual({ name: 'directions', from: 'quarry-plaza', to: 'mchenry-library' })
    expect(parseHash('#/p/science-hill?q=1')).toEqual({ name: 'place', id: 'science-hill' })
    expect(parseHash('')).toEqual({ name: 'home' })
  })
})
