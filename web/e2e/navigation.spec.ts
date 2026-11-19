import { expect, test, type Page } from '@playwright/test'

const ready = async (page: Page, hash = '') => {
  await page.goto(`/?e2e${hash}`)
  await page.waitForFunction(() => (window as unknown as { __map?: { loaded(): boolean } }).__map?.loaded(), null, { timeout: 45_000 })
}
const routeEnd = (page: Page) =>
  page.evaluate(() => {
    const f = (window as any).__map.querySourceFeatures('endpoints').find((x: any) => x.properties.role === 'from')
    return f ? (f.geometry.coordinates as [number, number]) : null
  })

test.use({ geolocation: { latitude: 36.99715, longitude: -122.05529 }, permissions: ['geolocation'] })

test('directions follow you: the route is redrawn as you move, at once when you leave it, and you arrive', async ({ page, context }) => {
  await ready(page, '#/p/stevenson-academic')
  await page.getByRole('button', { name: 'Show my location' }).click()
  await page.getByRole('button', { name: 'Directions' }).click()
  await expect(page).toHaveURL(/#\/r\/me\/stevenson-academic/)
  await page.waitForFunction(() => (window as any).__map.querySourceFeatures('route').some((f: any) => f.properties.kind === 'walk'), null, { timeout: 15_000 })
  await expect(page.getByText(/Following your location/)).toHaveCount(0)
  const first = await routeEnd(page)

  // walk 40 m along the way: the route starts from the new spot
  await context.setGeolocation({ latitude: 36.99715, longitude: -122.05484 })
  await expect.poll(async () => JSON.stringify(await routeEnd(page)), { timeout: 15_000 }).not.toBe(JSON.stringify(first))

  // step well off the route: it is redrawn at once and says so briefly
  await context.setGeolocation({ latitude: 36.99795, longitude: -122.05529 })
  await expect(page.getByRole('status').filter({ hasText: 'Rerouted from where you are' })).toBeVisible({ timeout: 15_000 })

  // reach the door
  const door = await page.evaluate(() => {
    const f = (window as any).__map.querySourceFeatures('endpoints').find((x: any) => x.properties.role === 'to')
    return f.geometry.coordinates as [number, number]
  })
  await context.setGeolocation({ latitude: door[1], longitude: door[0] })
  await expect(page.getByText(/You've arrived at Stevenson Academic Building/)).toBeVisible({ timeout: 15_000 })
})

test('once location is on, directions and Get me there start from it; the setting turns that off', async ({ page }) => {
  await ready(page)
  await page.getByRole('button', { name: 'Show my location' }).click()
  await page.waitForTimeout(500)
  await ready(page, '#/p/mchenry-library')
  await page.getByRole('button', { name: 'Directions' }).click()
  await expect(page.getByRole('combobox', { name: 'From' })).toHaveValue('My location')

  await ready(page, '#/r//kresge-college')
  await expect(page).toHaveURL(/#\/r\/me\/kresge-college/)

  await page.getByRole('button', { name: 'Settings and about' }).click()
  await page.getByRole('switch', { name: 'Use my location' }).click()
  await page.keyboard.press('Escape')
  await ready(page, '#/p/mchenry-library')
  await page.getByRole('button', { name: 'Directions' }).click()
  await expect(page.getByRole('combobox', { name: 'From' })).toHaveValue('')
})

test('dragging the map stops following, and the follow button brings it back', async ({ page, context }) => {
  await ready(page, '#/p/stevenson-academic')
  await page.getByRole('button', { name: 'Show my location' }).click()
  await page.getByRole('button', { name: 'Directions' }).click()
  await page.waitForFunction(() => (window as any).__map.querySourceFeatures('route').some((f: any) => f.properties.kind === 'walk'), null, { timeout: 15_000 })
  const box = (await page.locator('.map-root').boundingBox())!
  await page.mouse.move(box.x + box.width * 0.7, box.y + box.height * 0.5)
  await page.mouse.down()
  await page.mouse.move(box.x + box.width * 0.5, box.y + box.height * 0.3, { steps: 8 })
  await page.mouse.up()
  const follow = page.getByRole('button', { name: 'Follow my location' })
  await expect(follow).toBeVisible()
  await follow.click()
  await expect(follow).toHaveCount(0)
  await context.setGeolocation({ latitude: 36.99715, longitude: -122.05470 })
  await page.waitForFunction(() => Math.abs((window as any).__map.getCenter().lng - -122.0547) < 0.0015, null, { timeout: 15_000 })
})
