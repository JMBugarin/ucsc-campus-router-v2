import { expect, test, type Page } from '@playwright/test'

const at = async (page: Page, iso: string) =>
  page.addInitScript((when) => {
    const R = Date
    const off = new R(when).getTime() - R.now()
    globalThis.Date = class extends R {
      constructor(...a: unknown[]) {
        if (a.length) super(...(a as [string]))
        else super(R.now() + off)
      }
      static now() {
        return R.now() + off
      }
    } as DateConstructor
  }, iso)
const ready = async (page: Page, hash: string) => {
  await page.goto(`/?e2e${hash}`)
  await page.waitForFunction(() => (window as unknown as { __map?: { loaded(): boolean } }).__map?.loaded(), null, { timeout: 45_000 })
}
const kinds = (page: Page) => page.evaluate(() => [...new Set((window as any).__map.querySourceFeatures('route').map((f: any) => f.properties.kind))])

test('the bus is offered even when walking is quicker, with both arrival times side by side', async ({ page }) => {
  await at(page, '2026-11-18T10:00:00-08:00')
  await ready(page, '#/r/quarry-plaza/baskin-engineering')
  const walk = page.getByRole('radio', { name: /^Walk/ })
  const bus = page.getByRole('radio', { name: /^Bus/ })
  await expect(walk).toHaveAttribute('aria-checked', 'true')
  await expect(walk).toContainText(/Leave now · arrive 10:1\d AM/)
  await expect(bus).toContainText(/Route \d+/)
  await expect(bus).toContainText(/Leave by \d{1,2}:\d{2} AM · arrive \d{1,2}:\d{2} AM/)
  await expect(bus).toContainText(/\d+ min later than walking/)
  await page.waitForFunction(() => (window as any).__map.querySourceFeatures('route').some((f: any) => f.properties.kind === 'walk'), null, { timeout: 15_000 })
  expect(await kinds(page)).not.toContain('bus')

  // choosing the bus draws it, lists the buses, and is remembered for the next trip
  await bus.click()
  await expect(bus).toHaveAttribute('aria-checked', 'true')
  await expect(page.getByRole('region', { name: 'Trips by bus' })).toContainText(/Route \d+ toward/)
  await page.waitForFunction(() => (window as any).__map.querySourceFeatures('route').some((f: any) => f.properties.kind === 'bus'), null, { timeout: 15_000 })
  await ready(page, '#/r/mchenry-library/college-nine-apartment-building-2')
  await expect(page.getByRole('radio', { name: /^Bus/ })).toHaveAttribute('aria-checked', 'true')
  await page.getByRole('radio', { name: /^Walk/ }).click()
  await expect(page.getByText('On foot')).toBeVisible()
})

test('for a class, it compares when to leave on foot and by bus', async ({ page }) => {
  await at(page, '2026-11-18T09:20:00-08:00')
  const by = new Date('2026-11-18T10:40:00-08:00').getTime()
  await ready(page, `#/r/crown-college-galileo-house/baskin-engineering-152?arrive=${by}&cls=CSE%20130%20Lecture`)
  await expect(page.getByRole('radio', { name: /^Walk/ })).toContainText(/Leave by 10:2\d AM · arrive 10:40 AM/)
  await expect(page.getByRole('radio', { name: /^Bus/ })).toContainText(/leave \d+ min (later|earlier)|leave when you would walk/)
})

test('with no bus that saves walking, walking stays and says so', async ({ page }) => {
  await at(page, '2026-11-18T10:00:00-08:00')
  await ready(page, '#/r/stevenson-academic/crown-college')
  await expect(page.getByRole('radio', { name: /^Bus/ })).toContainText('No bus saves you walking on this trip right now')
  await expect(page.getByRole('radio', { name: /^Bus/ })).toBeDisabled()
  await expect(page.getByRole('radio', { name: /^Walk/ })).toHaveAttribute('aria-checked', 'true')
})
