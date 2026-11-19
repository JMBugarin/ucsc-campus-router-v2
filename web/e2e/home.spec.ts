import { expect, test, type Page } from '@playwright/test'

const ready = async (page: Page, hash = '') => {
  await page.goto(`/?e2e${hash}`)
  await page.waitForFunction(() => (window as unknown as { __map?: { loaded(): boolean } }).__map?.loaded(), null, { timeout: 45_000 })
}
const search = (page: Page) => page.getByRole('combobox', { name: 'Search UCSC' })
const routeDrawn = (page: Page) =>
  page.waitForFunction(() => (window as any).__map.querySourceFeatures('route').some((f: any) => f.properties.kind === 'walk'), null, { timeout: 15_000 })

test('find a dorm by the name students use, set it as home, and route back in one tap', async ({ page }) => {
  await ready(page)
  await search(page).fill('c9 apt 2')
  await expect(page.getByRole('option').first()).toContainText('College Nine Apartment Building 2')
  await search(page).press('Enter')
  await expect(page.getByRole('heading', { name: 'College Nine Apartment Building 2' })).toBeVisible()
  await page.getByRole('button', { name: 'Set as home' }).click()
  await expect(page.getByText('Your home', { exact: true })).toBeVisible()
  await expect(page.getByRole('status').filter({ hasText: 'Saved as your home' })).toBeVisible()

  await page.getByRole('button', { name: 'Back to search' }).click()
  await page.getByRole('option', { name: /Get me home/ }).click()
  await expect(page).toHaveURL(/#\/r\/.*\/college-nine-apartment-building-2/)
  await expect(page.getByRole('combobox', { name: 'To' })).toHaveValue('College Nine Apartment Building 2')
  await page.getByRole('combobox', { name: 'From' }).click()
  await page.getByRole('combobox', { name: 'From' }).fill('baskin engineering')
  await page.getByRole('option', { name: /^Jack Baskin Engineering/ }).first().click()
  await expect(page.getByText(/^\d+ min$/)).toBeVisible()
  await routeDrawn(page)

  // and from the dorm's own page, the home can be removed again
  await ready(page, '#/p/college-nine-apartment-building-2')
  await page.getByRole('button', { name: 'Remove home' }).click()
  await expect(page.getByRole('button', { name: 'Set as home' })).toBeVisible()
})

test('the Housing list groups every dorm and apartment by college, and nicknames find them', async ({ page }) => {
  await ready(page)
  await page.getByRole('button', { name: 'Housing' }).click()
  await expect(page.getByRole('region', { name: 'College Nine' })).toContainText('College Nine Apartment Building 2')
  await expect(page.getByRole('region', { name: 'Stevenson College' })).toContainText('Casa Primera')
  await page.getByRole('button', { name: 'Housing' }).click()
  for (const [q, name] of [
    ['casa primera', 'Stevenson College House 1'],
    ['merrill dubois', 'Merrill College House D'],
    ['galileo', 'Crown College Galileo House'],
    ['rcc a building', 'Rachel Carson College Dorm A-L-Building'],
  ]) {
    await search(page).fill(q)
    await expect(page.getByRole('option').first()).toContainText(name)
  }
  // a college's own name still comes before its dorms
  await search(page).fill('crown')
  await expect(page.getByRole('option').first()).toContainText('Crown College')
})

test('home is offered first when choosing a place, and Today shows the walk home after the last class', async ({ page }) => {
  await page.addInitScript(() => {
    const R = Date
    const fixed = new R('2026-11-18T08:50:00-08:00').getTime()
    globalThis.Date = class extends R {
      constructor(...a: unknown[]) {
        if (a.length) super(...(a as [string]))
        else super(fixed)
      }
      static now() {
        return fixed
      }
    } as DateConstructor
    localStorage.setItem('homePlace', JSON.stringify('crown-college-galileo-house'))
    localStorage.setItem(
      'classmap.schedule.v1',
      JSON.stringify({
        meetings: [
          { course: 'CSE 130', title: 'Principles of Computer Systems Design', section: '01', component: 'Lecture', class_nbr: '21402', days: [0, 2, 4], start: '09:20', end: '10:25', location: 'J Baskin Engr 152', start_date: '2026-09-24', end_date: '2026-12-04' },
        ],
      }),
    )
  })
  await ready(page, '#/r//mchenry-library')
  const homeRow = page.getByRole('option', { name: /^Home/ })
  await expect(homeRow).toContainText('Crown College Galileo House')
  await homeRow.click()
  await expect(page.getByRole('combobox', { name: 'From' })).toHaveValue('Crown College Galileo House')
  await routeDrawn(page)

  await ready(page, '#/today')
  const after = page.getByRole('option', { name: /Head home after CSE 130/ })
  await expect(after).toContainText(/\d+ min walk to Galileo House/)
  await after.click()
  await expect(page).toHaveURL(/#\/r\/baskin-engineering-152\/crown-college-galileo-house/)
})
