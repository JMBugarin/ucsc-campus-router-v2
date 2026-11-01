// Renders every component state over real map backdrops to PNGs. Usage: npm run gallery [-- --base=http://localhost:4173] [--out=../docs/gallery]
import { mkdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { launch } from './shot.mjs'

const arg = (k, d) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split('=')[1] ?? d
const base = arg('base', 'http://localhost:4173')
const out = arg('out', '../docs/gallery')
const only = arg('only', '')
const BACKDROPS = ['forest', 'bright', 'detail', 'terrain']
const THEMES = ['light', 'dark']
const VIEWPORTS = [
  { name: 'desktop', width: 1360, height: 2100, mobile: false },
  { name: 'mobile', width: 390, height: 3400, mobile: true },
]

rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
const browser = await launch()
let count = 0
for (const vp of VIEWPORTS) {
  for (const theme of THEMES) {
    for (const bd of BACKDROPS) {
      if (only && !`${vp.name}-${theme}-${bd}`.includes(only)) continue
      const ctx = await browser.newContext({ viewport: { width: vp.width, height: vp.height }, deviceScaleFactor: 2, colorScheme: theme, hasTouch: vp.mobile, isMobile: vp.mobile })
      const page = await ctx.newPage()
      page.on('pageerror', (e) => console.log('[pageerror]', e.message))
      await page.goto(`${base}/?theme=${theme}#/gallery?bd=${bd}`)
      await page.waitForSelector('.gal[data-ready="true"]', { timeout: 30000 })
      await page.waitForFunction(() => window.__map?.loaded() && window.__map.areTilesLoaded(), null, { timeout: 40000 }).catch(() => console.log('tiles not settled', bd))
      await page.waitForTimeout(1500)
      const dir = join(out, vp.name, theme, bd)
      mkdirSync(dir, { recursive: true })
      await page.screenshot({ path: join(dir, '_overview.png'), fullPage: true })
      const cells = await page.$$('[data-gallery]')
      for (const c of cells) {
        const id = await c.getAttribute('data-gallery')
        const box = await c.boundingBox()
        if (!box) continue
        const pad = 36
        const clip = { x: Math.max(0, box.x - pad), y: Math.max(0, box.y - pad), width: box.width + 2 * pad, height: box.height + 2 * pad }
        await page.screenshot({ path: join(dir, `${id}.png`), clip, fullPage: true })
        count++
      }
      await ctx.close()
    }
  }
}
await browser.close()
console.log(`gallery: wrote ${count} component captures to ${out}`)
