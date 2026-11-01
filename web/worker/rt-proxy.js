// Pass-through for Santa Cruz METRO's GTFS-realtime feeds, which send no CORS headers.
// Deploy as a free Cloudflare Worker, then build the site with VITE_RT_BASE=https://<your-worker>.workers.dev
// Only the three public feeds are reachable; responses are cached for 15 s to stay polite to METRO's servers.
const FEEDS = new Set(['trips', 'vehicles', 'alerts'])

export default {
  async fetch(request) {
    const kind = new URL(request.url).pathname.replace(/^\/+|\/+$/g, '')
    const cors = { 'access-control-allow-origin': '*', 'access-control-allow-methods': 'GET' }
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors })
    if (!FEEDS.has(kind)) return new Response('not found', { status: 404, headers: cors })
    const upstream = await fetch(`https://rt.scmetro.org/gtfsrt/${kind}`, {
      headers: { 'user-agent': 'ucsc-map-proxy/1.0' },
      cf: { cacheTtl: 15, cacheEverything: true },
    })
    return new Response(upstream.body, {
      status: upstream.status,
      headers: { ...cors, 'content-type': 'application/x-protobuf', 'cache-control': 'public, max-age=15' },
    })
  },
}
