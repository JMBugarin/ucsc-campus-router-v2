// Runtime measurements in Chrome against the preview build: load time, frame times while panning, heap, DOM size.
import { launch } from './shot.mjs'
const base = process.argv[2] ?? 'http://localhost:4173'
const b = await launch()
for (const vp of [{ n: 'desktop', w: 1440, h: 900 }, { n: 'mobile', w: 390, h: 844, mobile: true }]) {
  const ctx = await b.newContext({ viewport: { width: vp.w, height: vp.h }, deviceScaleFactor: 2, isMobile: !!vp.mobile, hasTouch: !!vp.mobile })
  const p = await ctx.newPage()
  const t0 = Date.now()
  await p.goto(`${base}/?e2e`)
  await p.waitForFunction(() => window.__map?.loaded(), null, { timeout: 60000 })
  const loadMs = Date.now() - t0
  await p.waitForTimeout(1500)
  const r = await p.evaluate(async () => {
    const m = window.__map
    const frames = []
    let last = performance.now()
    let run = true
    const tick = (t) => { frames.push(t - last); last = t; if (run) requestAnimationFrame(tick) }
    requestAnimationFrame(tick)
    for (let i = 0; i < 12; i++) { m.panBy([i % 2 ? -120 : 120, 40], { duration: 250 }); await new Promise((r) => setTimeout(r, 300)) }
    run = false
    const s = frames.slice(2).sort((a, b) => a - b)
    const nav = performance.getEntriesByType('navigation')[0]
    return {
      frames: s.length, medianMs: s[Math.floor(s.length / 2)], p95Ms: s[Math.floor(s.length * 0.95)],
      domNodes: document.getElementsByTagName('*').length,
      heapMB: performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : null,
      domContentLoaded: Math.round(nav.domContentLoadedEventEnd), transferKB: Math.round(performance.getEntriesByType('resource').reduce((a, e) => a + (e.transferSize || 0), 0) / 1024),
    }
  })
  console.log(vp.n, JSON.stringify({ mapReadyMs: loadMs, ...r }))
  await ctx.close()
}
await b.close()
