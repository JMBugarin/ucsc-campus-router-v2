// Real-app screenshots over real UCSC locations. Usage: node scripts/screenshots.mjs [--base=http://localhost:4173] [--out=../docs/screenshots/web]
import { mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { launch } from './shot.mjs'

const arg = (k, d) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split('=')[1] ?? d
const base = arg('base', 'http://localhost:4173')
const out = arg('out', '../docs/screenshots/web')
mkdirSync(out, { recursive: true })

const shots = [
  { name: '01-home-light', w: 1440, h: 900, theme: 'light', hash: '' },
  { name: '02-search-typo-dark', w: 1440, h: 900, theme: 'dark', hash: '', type: 'mchenery libr' },
  { name: '03-mchenry-library-light', w: 1440, h: 900, theme: 'light', hash: '#/p/mchenry-library' },
  { name: '04-science-hill-dark', w: 1440, h: 900, theme: 'dark', hash: '#/p/science-hill' },
  { name: '05-quarry-plaza-to-mchenry-light', w: 1440, h: 900, theme: 'light', hash: '#/r/quarry-plaza/mchenry-library' },
  { name: '06-kresge-to-baskin-dark', w: 1440, h: 900, theme: 'dark', hash: '#/r/kresge-college/baskin-engineering' },
  { name: '07-dining-category-light', w: 1440, h: 900, theme: 'light', hash: '', chip: 'Dining' },
  { name: '08-parking-clusters-light', w: 1440, h: 900, theme: 'light', hash: '', chip: 'Parking', zoom: 15.6 },
  { name: '09-mobile-home-dark', w: 390, h: 844, theme: 'dark', hash: '' },
  { name: '10-mobile-place-light', w: 390, h: 844, theme: 'light', hash: '#/p/mchenry-library' },
  { name: '11-mobile-route-dark', w: 390, h: 844, theme: 'dark', hash: '#/r/quarry-plaza/mchenry-library', full: true },
  { name: '12-about-light', w: 1440, h: 900, theme: 'light', hash: '', about: true },
]
const browser = await launch()
for (const s of shots) {
  const mobile = s.w < 700
  const ctx = await browser.newContext({ viewport: { width: s.w, height: s.h }, deviceScaleFactor: 2, colorScheme: s.theme, hasTouch: mobile, isMobile: mobile })
  const page = await ctx.newPage()
  await page.goto(`${base}/?e2e&theme=${s.theme}${s.hash}`)
  await page.waitForFunction(() => window.__map?.loaded(), null, { timeout: 45000 })
  if (s.zoom) await page.evaluate((z) => window.__map.jumpTo({ zoom: z }), s.zoom)
  if (s.type) await page.getByRole('combobox', { name: 'Search UCSC' }).fill(s.type)
  if (s.chip) await page.getByRole('button', { name: s.chip }).click()
  if (s.about) await page.getByRole('button', { name: 'Settings and about' }).click()
  if (s.full) await page.getByRole('button', { name: 'Resize panel' }).click()
  await page.waitForFunction(() => window.__map.loaded() && window.__map.areTilesLoaded(), null, { timeout: 45000 }).catch(() => undefined)
  await page.waitForTimeout(1800)
  await page.screenshot({ path: join(out, `${s.name}.png`) })
  await ctx.close()
}
await browser.close()
console.log(`wrote ${shots.length} screenshots to ${out}`)
