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

test('a trip from downtown to a classroom: walk, bus, then the campus paths to the door', async ({ page }) => {
  await at(page, '2026-11-04T08:00:00-08:00')
  await ready(page, '#/r/@36.971900,-122.026300/baskin-engineering-152')
  const trips = page.getByRole('region', { name: 'Trips by bus' })
  await expect(trips).toBeVisible({ timeout: 20_000 })
  await expect(trips.getByRole('radio').first()).toContainText(/Leave by \d{1,2}:\d{2} AM/)
  await expect(trips).toContainText('Estimated: no mapped path here')
  await expect(trips).toContainText('Along the mapped campus paths.')
  await expect(trips).toContainText(/Route \d+ toward/)
  await expect(page.getByText('No walking route')).toHaveCount(0)
  await page.waitForFunction(() => (window as any).__map.querySourceFeatures('route').some((f: any) => f.properties.kind === 'bus'), null, { timeout: 15_000 })
  await trips.getByRole('radio').nth(1).click()
  await expect(trips.getByRole('radio').nth(1)).toHaveAttribute('aria-checked', 'true')
})

test('get me there from home arrives by class time', async ({ page, context }) => {
  await context.grantPermissions(['geolocation'])
  await context.setGeolocation({ latitude: 36.9719, longitude: -122.0263 })
  await at(page, '2026-11-04T08:00:00-08:00')
  await page.addInitScript(() =>
    localStorage.setItem('classmap.schedule.v1', JSON.stringify({ meetings: [{ course: 'CSE 130', title: '', section: '01', component: 'Lecture', class_nbr: '', days: [2], start: '09:20', end: '10:25', location: 'J Baskin Engr 152', start_date: '2026-09-24', end_date: '2026-12-04' }] })),
  )
  await ready(page, '')
  await expect(page).toHaveURL(/#\/today/)
  await page.getByRole('button', { name: 'Show my location' }).click()
  await page.getByRole('button', { name: 'Get me to CSE 130 Lecture' }).click()
  const trips = page.getByRole('region', { name: 'Trips by bus' })
  await expect(trips).toBeVisible({ timeout: 20_000 })
  const first = await trips.getByRole('radio').first().innerText()
  const arrive = /Arrive around (\d{1,2}):(\d{2}) AM/.exec(first)!
  expect(+arrive[1] * 60 + +arrive[2]).toBeLessThanOrEqual(9 * 60 + 20)
})

test('a starting point can be picked on the map', async ({ page }) => {
  await ready(page, '#/r//baskin-engineering-152')
  await page.getByRole('combobox', { name: 'From' }).click()
  await page.getByRole('button', { name: 'Pick on the map' }).click()
  await expect(page.getByText('Tap where the trip starts.')).toBeVisible()
  const pt = await page.evaluate(() => {
    const m = (window as any).__map
    const p = m.project([-122.0555, 36.9972])
    const r = m.getCanvas().getBoundingClientRect()
    return { x: r.left + p.x, y: r.top + p.y }
  })
  await page.mouse.click(pt.x, pt.y)
  await expect(page).toHaveURL(/#\/r\/%4036\.99\d+%2C-122\.05\d+\/baskin-engineering-152|#\/r\/@36\.99\d+,-122\.05\d+\/baskin-engineering-152/)
  await expect(page.getByRole('combobox', { name: 'From' })).toHaveValue('Dropped pin')
})
