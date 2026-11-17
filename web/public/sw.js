// The app shell and campus data stay available offline. Only fingerprinted build assets are cache-first.
const CACHE = 'ucsc-map-v2'
const STATIC = /\/(assets|data|maplibre)\/[^?]*$|\.(svg|png|webmanifest)$/
const ASSET_PATH = new URL('./assets/', self.location.href).pathname
const SHELL = ['./', 'manifest.webmanifest', 'icon.svg', 'data/places.json', 'data/graph.json', 'maplibre/maplibre-gl-worker.mjs', 'maplibre/maplibre-gl-shared.mjs']

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()))
})
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => /^ucsc-map-v\d+$/.test(k) && k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()))
})

async function serve(event, cacheFirst, isPage) {
  const { request } = event
  const cache = await caches.open(CACHE).catch(() => undefined)
  if (!cache) return fetch(request)
  if (cacheFirst) {
    const hit = await cache.match(request)
    if (hit) return hit
  }

  let response
  try {
    response = await fetch(request)
  } catch (error) {
    const cached = await cache.match(request) || (isPage && await cache.match('./'))
    if (cached) return cached
    throw error
  }

  if (response.ok) {
    event.waitUntil(cache.put(request, response.clone()).catch(() => {}))
  }
  return response
}

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url)
  if (e.request.method !== 'GET' || url.origin !== location.origin) return
  const isPage = e.request.mode === 'navigate'
  if (!isPage && (url.search || !STATIC.test(url.pathname))) return
  e.respondWith(serve(e, !isPage && url.pathname.startsWith(ASSET_PATH), isPage))
})
