import { expect, test, type Page } from '@playwright/test'

const PASTE = `CSE 130 - Principles of Computer Systems Design Status Units Grading Grade Deadlines Enrolled 5.00 Graded 21402 01 Lecture MoWeFr 9:20AM - 10:25AM J Baskin Engr 152 Staff 09/24/2026 - 12/04/2026 21403 01A Discussion Tu 4:00PM - 5:05PM McHenry Lib 1350 Staff 09/24/2026 - 12/04/2026
MATH 19A - Calculus Status Units Grading Grade Deadlines Enrolled 5.00 Graded 10811 01 Lecture MoWeFr 10:40AM - 11:45AM Mystery Hall 9 Staff 09/24/2026 - 12/04/2026
PHYS 5A - Mechanics Status Units Grading Grade Deadlines Dropped 5.00 Graded 30100 01 Lecture TuTh 1:30PM - 3:05PM Thimann Lecture 003 Staff 09/24/2026 - 12/04/2026`

test.use({ geolocation: { latitude: 36.99715, longitude: -122.05529 }, permissions: ['geolocation'] })

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
const ready = async (page: Page, hash = '') => {
  await page.goto(`/?e2e${hash}`)
  await page.waitForFunction(() => (window as unknown as { __map?: { loaded(): boolean } }).__map?.loaded(), null, { timeout: 45_000 })
}

test('paste a MyUCSC schedule, check it, and see today with when to leave', async ({ page }) => {
  await at(page, '2026-11-18T08:50:00-08:00')
  await ready(page, '#/schedule')
  await page.getByRole('button', { name: 'Paste from MyUCSC' }).click()
  await page.getByLabel('Schedule text').fill(PASTE)
  await page.getByRole('button', { name: 'Read my classes' }).click()
  const review = page.getByRole('dialog', { name: 'Check 3 classes' })
  await expect(review).toBeVisible()
  await expect(review).toContainText('Skipped PHYS 5A (dropped).')
  await expect(review).toContainText('On the map: Jack Baskin Engineering 152')
  await expect(review).toContainText('1 to look at')
  await expect(review).toContainText("Not a campus room the map knows")

  await review.getByRole('button', { name: 'Edit MATH 19A Lecture' }).click()
  await page.getByRole('button', { name: 'Find the room' }).click()
  await page.getByLabel('Find the room').fill('thimann lecture 003')
  await page.getByRole('option', { name: 'Thimann Lecture Hall 003' }).click()
  await expect(page.getByText('On the map: Thimann Lecture Hall 003')).toBeVisible()
  await page.getByRole('button', { name: 'Done' }).click()
  await expect(page.getByRole('dialog', { name: 'Check 3 classes' })).not.toContainText('to look at')
  await page.getByRole('button', { name: 'Save 3 classes' }).click()

  await expect(page).toHaveURL(/#\/today/)
  await expect(page.getByText('Next: CSE 130 Lecture at 9:20 AM in 30 min.')).toBeVisible()
  await page.getByRole('button', { name: 'Show my location' }).click()
  await expect(page.getByText(/^Leave by \d{1,2}:\d{2} AM$/)).toBeVisible()
  await expect(page.getByText(/min walk from here/)).toBeVisible()
  await expect(page.getByText(/break · \d+ min walk/)).toBeVisible()

  await page.getByRole('button', { name: 'Get me there' }).click()
  await expect(page).toHaveURL(/#\/r\/me\/baskin-engineering-152\?arrive=/)
  const plan = page.getByRole('region', { name: 'When to leave' })
  await expect(plan.getByRole('radio', { name: 'Arrive by 9:20 AM' })).toHaveAttribute('aria-checked', 'true')
  await expect(plan).toContainText(/Leave by \d{1,2}:\d{2} AM · Arrive around 9:20 AM/)
  await plan.getByRole('radio', { name: 'Leave now' }).click()
  await expect(plan).toContainText('Leave now · Arrive around')

  await page.reload()
  await page.goto('/?e2e')
  await expect(page).toHaveURL(/#\/today/)
  await expect(page.getByText('Next: CSE 130 Lecture at 9:20 AM in 30 min.')).toBeVisible()
})

test('add a class by hand, skip a day, and remove it', async ({ page }) => {
  await at(page, '2026-11-17T12:00:00-08:00')
  await ready(page, '#/schedule')
  await page.getByRole('button', { name: 'Add a class' }).click()
  const dialog = page.getByRole('dialog', { name: 'Add a class' })
  await expect(dialog.getByLabel('First day')).toHaveValue('2026-09-24')
  await expect(dialog.getByRole('button', { name: 'Save' })).toBeDisabled()
  await dialog.getByLabel('Course').fill('cse 101')
  await dialog.getByRole('button', { name: 'Wednesday' }).click()
  await dialog.getByLabel('Starts').fill('14:40')
  await dialog.getByLabel('Ends').fill('15:45')
  await dialog.getByLabel('Room').fill('BE 152')
  await expect(dialog.getByText('On the map: Jack Baskin Engineering 152')).toBeVisible()
  await dialog.getByRole('button', { name: 'Save' }).click()
  await expect(page.getByRole('button', { name: 'Edit CSE 101 on Wednesday' })).toBeVisible()

  await page.getByRole('button', { name: 'Edit CSE 101 on Wednesday' }).click()
  const edit = page.getByRole('dialog', { name: 'Edit class' })
  await edit.getByLabel('Day to skip').fill('2026-11-18')
  await edit.getByRole('button', { name: 'Skip that day' }).click()
  await edit.getByRole('button', { name: 'Save' }).click()
  await expect(page.getByText('Skipping Wed, Nov 18')).toBeVisible()

  await page.getByRole('radio', { name: 'Today' }).click()
  await page.getByRole('button', { name: 'Next day' }).click()
  await expect(page.getByText('No classes.')).toBeVisible()
  for (let i = 0; i < 7; i++) await page.getByRole('button', { name: 'Next day' }).click()
  await expect(page.getByRole('heading', { name: 'Wed, Nov 25' })).toBeVisible()
  await expect(page.getByRole('article', { name: 'CSE 101 at 2:40 PM' })).toBeVisible()

  await page.getByRole('radio', { name: 'Schedule' }).click()
  await page.getByRole('button', { name: 'Edit CSE 101 on Wednesday' }).click()
  await page.getByRole('button', { name: 'Delete class' }).click()
  await page.getByRole('button', { name: 'Tap again to delete' }).click()
  await expect(page.getByText('No classes yet.')).toBeVisible()
})

test('the map tab still searches rooms without a schedule', async ({ page }) => {
  await ready(page, '#/')
  await expect(page.getByRole('radio', { name: 'Map' })).toHaveAttribute('aria-checked', 'true')
  await page.getByRole('combobox', { name: 'Search UCSC' }).fill('mchenry 1340')
  await expect(page.getByRole('option').first()).toContainText('McHenry Library 1340')
})
