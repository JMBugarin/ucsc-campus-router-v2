import { expect, test, type Page } from '@playwright/test'

test.use({ baseURL: 'http://localhost:4174' })

const status = (freshness: string) => ({ generation: 7, source_time: 1_794_000_000, fetched_at: null, processed_at: null, freshness })
const open = async (page: Page) => {
  await page.addInitScript(() => {
    const R = Date
    const off = new R('2026-11-04T18:00:00Z').getTime() - R.now()
    globalThis.Date = class extends R {
      constructor(...a: unknown[]) { if (a.length) super(...(a as [string])); else super(R.now() + off) }
      static now() { return R.now() + off }
    } as DateConstructor
  })
  await page.goto('/?e2e#/p/stop-science-hill')
  await expect(page.getByRole('region', { name: 'Next buses' })).toBeVisible({ timeout: 45_000 })
}
const note = (page: Page) => page.getByRole('region', { name: 'Next buses' }).getByRole('status')

test('fresh service predictions are labeled', async ({ page }) => {
  await page.route('**/svc/v1/departures?**', r => r.fulfill({ json: { status: status('fresh'), departures: [{ trip: 'x', stop: 's', time: 1_794_000_600, event_time: 1_794_000_000, kind: 'fresh' }] } }))
  await open(page)
  await expect(note(page)).toHaveText(/Live predictions from the Classmap transit service/)
})

test('stale service falls back to the bundled schedule', async ({ page }) => {
  await page.route('**/svc/v1/departures?**', r => r.fulfill({ json: { status: status('stale'), departures: [] } }))
  await open(page)
  await expect(note(page)).toHaveText(/stale; showing the bundled schedule/)
  await expect(page.getByLabel(/^Route (11|16|18|19|20)$/).first()).toBeVisible()
})

test('service outage keeps offline schedule and rooms usable', async ({ page }) => {
  await page.route('**/svc/v1/departures?**', r => r.fulfill({ status: 503, json: { error: 'database unavailable' } }))
  await open(page)
  await expect(note(page)).toHaveText(/Transit service unavailable/)
  await expect(page.getByLabel(/^Route (11|16|18|19|20)$/).first()).toBeVisible()
  await page.getByRole('combobox', { name: 'Search UCSC' }).fill('mchenry library')
  await expect(page.getByRole('option').first()).toContainText('McHenry Library')
})

test('malformed service response is treated as unavailable', async ({ page }) => {
  await page.route('**/svc/v1/departures?**', r => r.fulfill({ json: { departures: 'nope' } }))
  await open(page)
  await expect(note(page)).toHaveText(/Transit service unavailable/)
})

test('service worker never caches transit responses', async ({ page }) => {
  let state = 'fresh'
  await page.route('**/svc/v1/departures?**', r => r.fulfill({ json: { status: status(state), departures: state === 'fresh' ? [{ trip: 'x', stop: 's', time: 1_794_000_600, event_time: 1_794_000_000, kind: 'fresh' }] : [] } }))
  await open(page)
  await page.waitForFunction(() => navigator.serviceWorker.controller !== null || navigator.serviceWorker.ready.then(() => true))
  await page.reload()
  await expect(page.getByRole('region', { name: 'Next buses' })).toBeVisible({ timeout: 45_000 })
  expect(await page.evaluate(() => navigator.serviceWorker.controller !== null)).toBe(true)
  await expect(note(page)).toHaveText(/Live predictions/)
  state = 'stale'
  await page.reload()
  await expect(note(page)).toHaveText(/stale; showing the bundled schedule/)
  expect(await page.evaluate(async () => (await caches.keys()).length && (await Promise.all((await caches.keys()).map(async k => (await (await caches.open(k)).keys()).filter(r => r.url.includes('/svc/')).length))).reduce((a, b) => a + b, 0))).toBe(0)
})

test('weekly counting is off until chosen, sends only an id and week, and withdrawal deletes it', async ({ page }) => {
  const posts: unknown[] = []
  const deletes: string[] = []
  await page.route('**/svc/v1/departures?**', r => r.fulfill({ json: { status: status('fresh'), departures: [] } }))
  await page.route('**/svc/v1/activity**', r => {
    const req = r.request()
    if (req.method() === 'POST') posts.push(req.postDataJSON())
    if (req.method() === 'DELETE') deletes.push(new URL(req.url()).searchParams.get('install') ?? '')
    return r.fulfill({ status: 204 })
  })
  await open(page)
  expect(posts).toEqual([])
  await page.getByRole('button', { name: 'Settings and about' }).click()
  const toggle = page.getByRole('switch', { name: 'Count my weekly use' })
  await expect(toggle).toHaveAttribute('aria-checked', 'false')
  await toggle.click()
  await expect(toggle).toHaveAttribute('aria-checked', 'true')
  const code = (await page.getByText(/^Participant code: /).textContent())!.slice(-8)
  await page.keyboard.press('Escape')
  await page.getByRole('combobox', { name: 'Search UCSC' }).fill('mchenry library')
  await page.getByRole('option').first().click()
  await expect.poll(() => posts.length).toBe(1)
  expect(posts[0]).toEqual({ install: expect.stringMatching(new RegExp(`^${code}-`)), week: '2026-11-02' })
  await page.getByRole('button', { name: 'Settings and about' }).click()
  await page.getByRole('switch', { name: 'Count my weekly use' }).click()
  await expect.poll(() => deletes.length).toBe(1)
  expect(deletes[0]).toBe((posts[0] as { install: string }).install)
})
