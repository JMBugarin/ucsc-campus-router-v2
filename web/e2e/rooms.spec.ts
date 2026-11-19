import { expect, test, type Page } from '@playwright/test'

const ready = async (page: Page, hash = '') => {
  await page.goto(`/?e2e${hash}`)
  await page.waitForFunction(() => (window as unknown as { __map?: { loaded(): boolean } }).__map?.loaded(), null, { timeout: 45_000 })
}
const search = (page: Page) => page.getByRole('combobox', { name: 'Search UCSC' })

test('a room search opens the room with its floor, door and building layout', async ({ page }) => {
  await ready(page)
  await search(page).fill('BE 152')
  await expect(page.getByRole('option').first()).toContainText('Jack Baskin Engineering 152')
  await search(page).press('Enter')
  await expect(page).toHaveURL(/#\/p\/baskin-engineering-152/)
  await expect(page.getByRole('heading', { name: 'Jack Baskin Engineering 152' })).toBeVisible()
  await expect(page.getByText('Not checked on foot yet')).toBeVisible()
  await expect(page.getByText('Closest mapped door')).toBeVisible()
  await expect(page.getByText('The room is about 30 m south-west of this door, on floor 1.')).toBeVisible()
  await page.waitForFunction(() => (window as any).__map.querySourceFeatures('rooms').length >= 4, null, { timeout: 15_000 })
  await page.waitForFunction(() => (window as any).__map.querySourceFeatures('doors').some((f: any) => f.properties.chosen === 1), null, { timeout: 15_000 })

  await page.getByText('More details').click()
  await page.getByRole('button', { name: 'Jack Baskin Engineering 372' }).click()
  await expect(page).toHaveURL(/#\/p\/baskin-engineering-372/)
  await expect(page.getByRole('heading', { name: 'Jack Baskin Engineering 372' })).toBeVisible()
  await expect(page.getByText('Jack Baskin Engineering · Floor 3')).toBeVisible()
})

test('the building lists its rooms by floor and remembers recent rooms', async ({ page }) => {
  await ready(page, '#/p/baskin-engineering-165')
  await expect(page.getByRole('heading', { name: 'Jack Baskin Engineering 165' })).toBeVisible()
  await ready(page, '#/p/baskin-engineering')
  const rooms = page.getByRole('region', { name: 'Classrooms' })
  await expect(rooms.getByText('Floor 1')).toBeVisible()
  await expect(rooms.getByText('Floor 3')).toBeVisible()
  await expect(rooms.getByRole('button', { name: 'Jack Baskin Engineering 152' })).toBeVisible()
  await page.getByRole('button', { name: 'Back to search' }).click()
  await expect(page.getByRole('list', { name: 'Recent places' }).or(page.getByLabel('Recent places'))).toContainText('Jack Baskin Engineering 165')
})

test('directions to a room end at its door and draw the last stretch inside', async ({ page }) => {
  await ready(page, '#/r/quarry-plaza/baskin-engineering-152')
  await expect(page.getByText(/^\d+ min$/)).toBeVisible()
  // from Quarry Plaza the quicker of the two doors near 152 is the main entrance, not the closest one
  await expect(page.getByRole('region', { name: 'Arriving at the room' })).toContainText('The route ends at a mapped door near the room.')
  await page.waitForFunction(() => (window as any).__map.querySourceFeatures('route').some((f: any) => f.properties.kind === 'indoor'), null, { timeout: 15_000 })
  const roles = await page.evaluate(() => (window as any).__map.querySourceFeatures('endpoints').map((f: any) => f.properties.role))
  expect(roles).toContain('room')
})

test('audit mode records a guide, places the door from a map tap and writes the rooms.json entry', async ({ page }) => {
  await ready(page, '#/p/baskin-engineering-152?audit')
  const panel = page.getByRole('region', { name: 'Audit this room' })
  await expect(panel).toBeVisible()
  await panel.getByRole('radio', { name: 'Outside' }).click()
  await panel.getByLabel('One-line tip').fill('Corner room facing the trees')
  await panel.getByRole('button', { name: 'Tap it on the map' }).click()
  await page.waitForTimeout(1200)
  const pt = await page.evaluate(() => {
    const m = (window as any).__map
    const p = m.project([-122.0634, 37.0003])
    const r = m.getCanvas().getBoundingClientRect()
    return { x: r.left + p.x, y: r.top + p.y }
  })
  await page.mouse.click(pt.x, pt.y)
  const json = panel.getByLabel('Entry for data/rooms.json')
  await expect(json).toHaveValue(/"baskin-engineering:152"/)
  await expect(json).toHaveValue(/"access": "outside"/)
  await expect(json).toHaveValue(/"entrance"/)
  await expect(json).toHaveValue(/"checked": "\d{4}-\d{2}-\d{2}"/)
  await expect(page).toHaveURL(/baskin-engineering-152/)
  await page.waitForFunction(() => (window as any).__map.querySourceFeatures('doors').some((f: any) => f.properties.chosen === 1 && Math.abs(f.geometry.coordinates[1] - 37.0003) < 0.00005), null, { timeout: 15_000 })
})

test('room pages show no audit tools without ?audit', async ({ page }) => {
  await ready(page, '#/p/baskin-engineering-152')
  await expect(page.getByRole('heading', { name: 'Jack Baskin Engineering 152' })).toBeVisible()
  await expect(page.getByRole('region', { name: 'Audit this room' })).toHaveCount(0)
})
