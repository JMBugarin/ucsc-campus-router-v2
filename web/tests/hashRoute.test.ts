import { describe, expect, it } from 'vitest'
import { formatHash, parseHash, type Route } from '../src/state/hashRoute'

describe('hash routes', () => {
  it('parses normal links', () => {
    expect(parseHash('#/')).toEqual({ name: 'home' })
    expect(parseHash('#/p/mchenry-library')).toEqual({ name: 'place', id: 'mchenry-library' })
    expect(parseHash('#/p/science%20hill?q=1')).toEqual({ name: 'place', id: 'science hill' })
    expect(parseHash('#/r/me/quarry-plaza')).toEqual({ name: 'directions', from: 'me', to: 'quarry-plaza' })
    expect(parseHash('#/gallery')).toEqual({ name: 'gallery' })
  })

  it('keeps a malformed escape as the raw segment instead of throwing', () => {
    expect(parseHash('#/p/mchenry-library%')).toEqual({ name: 'place', id: 'mchenry-library%' })
    expect(parseHash('#/p/%E0')).toEqual({ name: 'place', id: '%E0' })
    expect(parseHash('#/r/me/100%')).toEqual({ name: 'directions', from: 'me', to: '100%' })
    expect(parseHash('#/r/%E0%A4/quarry%20plaza')).toEqual({ name: 'directions', from: '%E0%A4', to: 'quarry plaza' })
  })

  it('round-trips ids with special characters', () => {
    const routes: Route[] = [
      { name: 'place', id: 'a/b c%25?#&é' },
      { name: 'place', id: '100%' },
      { name: 'directions', from: 'me', to: 'kresge/college %' },
      { name: 'directions', to: 'ü' },
    ]
    for (const r of routes) expect(parseHash(formatHash(r, { q: 'x y' }))).toEqual(r)
  })
})
