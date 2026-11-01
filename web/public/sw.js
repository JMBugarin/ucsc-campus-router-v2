// App shell and campus data are cached; map tiles are never stored (provider policy).
const CACHE = 'ucsc-map-v1'
const SHELL = ['./', 'manifest.webmanifest', 'icon.svg', 'data/places.json', 'data/graph.json', 'maplibre/maplibre-gl-worker.mjs', 'maplibre/maplibre-gl-shared.mjs']

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()))
})
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()))
})
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url)
  if (e.request.method !== 'GET' || url.origin !== location.origin) return
  const isPage = e.request.mode === 'navigate'
  e.respondWith(
    isPage
      ? fetch(e.request).then((r) => (caches.open(CACHE).then((c) => c.put(e.request, r.clone())), r)).catch(() => caches.match(e.request).then((r) => r || caches.match('./')))
      : caches.match(e.request).then((hit) => hit || fetch(e.request).then((r) => (r.ok && caches.open(CACHE).then((c) => c.put(e.request, r.clone())), r))),
  )
})
