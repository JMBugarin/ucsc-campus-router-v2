import { expect, test, type Page } from '@playwright/test'

const ready = async (page: Page, hash = '') => {
  await page.goto(`/?e2e${hash}`)
  await page.waitForFunction(() => (window as unknown as { __map?: { loaded(): boolean } }).__map?.loaded(), null, { timeout: 45_000 })
}
const search = (page: Page) => page.getByRole('combobox', { name: 'Search UCSC' })

test('map and campus data load', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (e) => errors.push(e.message))
  await ready(page)
  await expect(page.getByRole('region', { name: /Search and details/ }).or(page.getByLabel('Search and details'))).toBeVisible()
  await expect(page.getByText('McHenry Library').first()).toBeVisible()
  const layers = await page.evaluate(() => (window as any).__map.getStyle().layers.length)
  expect(layers).toBeGreaterThan(30)
  expect(errors).toEqual([])
})

test('typo-tolerant search opens a place and fills the share link', async ({ page }) => {
  await ready(page)
  await search(page).fill('mchenery library')
  await expect(page.getByRole('option').first()).toContainText('McHenry Library')
  await search(page).press('Enter')
  await expect(page).toHaveURL(/#\/p\/mchenry-library/)
  await expect(page.getByRole('heading', { name: 'McHenry Library' })).toBeVisible()
  await page.waitForFunction(() => Math.abs((window as any).__map.getCenter().lat - 36.99572) < 0.002, null, { timeout: 15_000 })
})

test('nicknames and landmarks resolve', async ({ page }) => {
  await ready(page)
  await search(page).fill('BE')
  await expect(page.getByRole('option').first()).toContainText('Jack Baskin Engineering')
  await search(page).fill('Quarry Plaza')
  await expect(page.getByRole('option').first()).toContainText('Quarry Plaza')
  await search(page).fill('science hill')
  await expect(page.getByRole('option').first()).toContainText('Science Hill')
})

test('category filter lists only that category', async ({ page }) => {
  await ready(page)
  await page.getByRole('button', { name: 'Dining' }).click()
  const opts = page.getByRole('option')
  await expect(opts.first()).toBeVisible()
  expect(await opts.count()).toBeGreaterThan(5)
  await expect(page.getByRole('option', { name: /Lot 1/ })).toHaveCount(0)
})

test('shared place link opens directly', async ({ page }) => {
  await ready(page, '#/p/science-hill')
  await expect(page.getByRole('heading', { name: 'Science Hill' })).toBeVisible()
})

test('walking route follows mapped paths and reports time and distance', async ({ page }) => {
  await ready(page, '#/r/quarry-plaza/mchenry-library')
  await expect(page.getByText(/^\d+ min$/)).toBeVisible()
  await expect(page.getByText(/\d+ m · ↑/)).toBeVisible()
  await page.waitForFunction(() => (window as any).__map.querySourceFeatures('route').length > 0, null, { timeout: 15_000 })
  const kinds = await page.evaluate(() => [...new Set((window as any).__map.querySourceFeatures('route').map((f: any) => f.properties.kind))])
  expect(kinds).toContain('connector')
  expect(kinds.length).toBeGreaterThan(1)
})

test('avoid stairs either removes stair legs or explains that none exists', async ({ page }) => {
  await ready(page, '#/r/quarry-plaza/mchenry-library')
  await expect(page.getByText('Climb stairs').first()).toBeVisible()
  await page.getByRole('switch', { name: 'Avoid stairs' }).click()
  await expect(page.getByText(/^\d+ min$/)).toBeVisible()
  const stairs = await page.getByText('Climb stairs').count()
  if (stairs > 0) await expect(page.getByText('Stairs on this route')).toBeVisible()
})

const stubLocation = (page: Page, mode: 'denied' | { lat: number; lon: number }) =>
  page.addInitScript((m) => {
    navigator.geolocation.getCurrentPosition = (ok, err) => {
      if (m === 'denied') err?.({ code: 1, PERMISSION_DENIED: 1, message: 'denied' } as GeolocationPositionError)
      else ok({ coords: { latitude: m.lat, longitude: m.lon, accuracy: 20 } } as GeolocationPosition)
    }
  }, mode)

test('current location off campus gives an honest message, not a straight line', async ({ page }) => {
  await stubLocation(page, { lat: 36.9741, lon: -122.0308 })
  await ready(page, '#/r//mchenry-library')
  await page.getByRole('button', { name: 'Use my location' }).click()
  await expect(page.getByText(/not near a mapped campus path/)).toBeVisible({ timeout: 15_000 })
  expect(await page.evaluate(() => (window as any).__map.querySourceFeatures('route').length)).toBe(0)
})

test('current location on campus routes from here', async ({ page }) => {
  await stubLocation(page, { lat: 36.9998, lon: -122.0631 })
  await ready(page, '#/r//mchenry-library')
  await page.getByRole('button', { name: 'Use my location' }).click()
  await expect(page.getByText(/^\d+ min$/)).toBeVisible({ timeout: 15_000 })
})

test('location permission denied is explained', async ({ page }) => {
  await stubLocation(page, 'denied')
  await ready(page, '#/r//mchenry-library')
  await page.getByRole('button', { name: 'Use my location' }).click()
  await expect(page.getByText(/Location permission was denied/)).toBeVisible({ timeout: 15_000 })
})

test('transit info says campus shuttles have no public live feed', async ({ page }) => {
  await ready(page)
  await page.getByRole('option', { name: /Shuttles and buses/ }).click()
  await expect(page.getByRole('dialog', { name: 'Shuttles and buses' })).toContainText('No live shuttle times here')
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toHaveCount(0)
})

test('dark mode switches the map style and design tokens', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' })
  await ready(page)
  const bg = await page.evaluate(() => (window as any).__map.getPaintProperty('background', 'background-color'))
  expect(bg).toBe('#17202a')
  await page.getByRole('button', { name: 'Settings and about' }).click()
  await page.getByRole('radio', { name: 'Light' }).click()
  await page.waitForFunction(() => (window as any).__map.getPaintProperty('background', 'background-color') === '#eef0e8', null, { timeout: 15_000 })
  expect(await page.evaluate(() => document.documentElement.dataset.theme)).toBe('light')
})

test('reduced motion zeroes UI transition tokens', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await ready(page)
  const d = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--m-base').trim())
  expect(d).toMatch(/^0(ms|s)$/)
})

test('keyboard: slash focuses search, arrows move, enter opens', async ({ page }) => {
  await ready(page)
  await page.keyboard.press('/')
  await expect(search(page)).toBeFocused()
  await search(page).fill('kresge')
  await search(page).press('ArrowDown')
  await search(page).press('Enter')
  await expect(page).toHaveURL(/#\/p\//)
})

test('a METRO stop lists scheduled buses and says live tracking is not connected', async ({ page }) => {
  await page.addInitScript(() => {
    const R = Date
    const off = new R('2026-11-04T18:00:00Z').getTime() - R.now()
    globalThis.Date = class extends R {
      constructor(...a: unknown[]) { if (a.length) super(...(a as [string])); else super(R.now() + off) }
      static now() { return R.now() + off }
    } as DateConstructor
  })
  await ready(page, '#/p/stop-science-hill')
  await expect(page.getByRole('region', { name: 'Next buses' })).toBeVisible()
  await expect(page.getByLabel(/^Route (11|16|18|19|20)$/).first()).toBeVisible()
  await expect(page.getByText(/Live tracking is not connected/)).toBeVisible()
  await expect(page.getByText(/flexigo/)).toBeVisible()
})
