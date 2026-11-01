// Usage: node scripts/shot.mjs <url> <out.png> [width height] [--wait=ms] [--dark] [--click=selector] [--type=selector:text]
import { chromium } from '@playwright/test'

export const launch = () =>
  chromium.launch({ channel: 'chrome', args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] })

if (import.meta.url === `file://${process.argv[1]}`) {
  const [url, out, w = '1440', h = '900', ...rest] = process.argv.slice(2)
  const opt = Object.fromEntries(rest.filter((r) => r.startsWith('--')).map((r) => r.slice(2).split('=')))
  const browser = await launch()
  const ctx = await browser.newContext({ viewport: { width: +w, height: +h }, deviceScaleFactor: 2, colorScheme: 'dark' in opt ? 'dark' : 'light', hasTouch: +w < 700, isMobile: +w < 700 })
  const page = await ctx.newPage()
  page.on('console', (m) => ['error', 'warning'].includes(m.type()) && console.log('[console]', m.type(), m.text().slice(0, 200)))
  page.on('pageerror', (e) => console.log('[pageerror]', e.message))
  await page.goto(url)
  await page.waitForFunction(() => window.__map && window.__map.loaded(), null, { timeout: 30000 }).catch(() => console.log('map not loaded'))
  if (opt.type) { const [sel, text] = opt.type.split('::'); await page.fill(sel, text) }
  if (opt.click) await page.click(opt.click)
  await page.waitForTimeout(+(opt.wait ?? 2500))
  await page.screenshot({ path: out })
  await browser.close()
}
