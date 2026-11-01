import { useCallback, useEffect, useState } from 'react'

export type Route =
  | { name: 'home' }
  | { name: 'place'; id: string }
  | { name: 'directions'; from?: string; to?: string }
  | { name: 'gallery' }

/** #/ · #/p/<id> · #/r/<from>/<to> (either may be empty; "me" is current location) · #/gallery */
export function parseHash(h: string): Route {
  const path = h.replace(/^#/, '').split('?')[0]
  const seg = path.replace(/^\/+/, '').split('/').map(decodeURIComponent)
  if (seg[0] === 'p' && seg[1]) return { name: 'place', id: seg[1] }
  if (seg[0] === 'r') return { name: 'directions', from: seg[1] || undefined, to: seg[2] || undefined }
  if (seg[0] === 'gallery') return { name: 'gallery' }
  return { name: 'home' }
}

export function formatHash(r: Route, params?: Record<string, string>): string {
  const q = params && Object.keys(params).length ? '?' + new URLSearchParams(params).toString() : ''
  switch (r.name) {
    case 'place':
      return `#/p/${encodeURIComponent(r.id)}${q}`
    case 'directions':
      return `#/r/${encodeURIComponent(r.from ?? '')}/${encodeURIComponent(r.to ?? '')}${q}`
    case 'gallery':
      return '#/gallery'
    default:
      return '#/'
  }
}

export function hashParams(): URLSearchParams {
  const i = location.hash.indexOf('?')
  return new URLSearchParams(i >= 0 ? location.hash.slice(i + 1) : '')
}

export function useHashRoute(): [Route, (r: Route, params?: Record<string, string>, replace?: boolean) => void] {
  const [route, setRoute] = useState<Route>(() => parseHash(location.hash))
  useEffect(() => {
    const on = () => setRoute(parseHash(location.hash))
    window.addEventListener('hashchange', on)
    return () => window.removeEventListener('hashchange', on)
  }, [])
  const go = useCallback((r: Route, params?: Record<string, string>, replace = false) => {
    const h = formatHash(r, params)
    if (replace) history.replaceState(null, '', h)
    else history.pushState(null, '', h)
    setRoute(r)
  }, [])
  return [route, go]
}
