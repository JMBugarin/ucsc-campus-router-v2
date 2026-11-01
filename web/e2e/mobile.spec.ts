import { devices, expect, test } from '@playwright/test'

test.use({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, userAgent: devices['iPhone 13'].userAgent })

test('mobile: bottom sheet search to place to directions', async ({ page }) => {
  await page.goto('/?e2e')
  await page.waitForFunction(() => (window as any).__map?.loaded(), null, { timeout: 45_000 })
  const sheet = page.getByRole('region', { name: 'Search and details' })
  await expect(sheet).toBeVisible()
  await page.getByRole('combobox', { name: 'Search UCSC' }).fill('mchenry')
  await page.getByRole('option').first().click()
  await expect(page.getByRole('heading', { name: 'McHenry Library' })).toBeVisible()
  const box = await page.getByRole('button', { name: 'Directions' }).boundingBox()
  expect(box!.height).toBeGreaterThanOrEqual(44)
  await page.getByRole('button', { name: 'Directions' }).click()
  await expect(page.getByRole('heading', { name: 'Walking directions' })).toBeVisible()
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth)
  expect(overflow).toBe(false)
})

test('mobile: sheet resizes by tapping the grabber', async ({ page }) => {
  await page.goto('/?e2e')
  await page.waitForFunction(() => (window as any).__map?.loaded(), null, { timeout: 45_000 })
  const sheet = page.getByRole('region', { name: 'Search and details' })
  const before = (await sheet.boundingBox())!.height
  await page.getByRole('button', { name: 'Resize panel' }).click()
  await page.waitForTimeout(500)
  expect((await sheet.boundingBox())!.height).not.toBe(before)
})
