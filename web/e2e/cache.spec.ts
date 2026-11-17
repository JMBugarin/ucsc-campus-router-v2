import { expect, test } from '@playwright/test'

test('returning visitors get fresh campus data and can use it offline', async ({ page, request, context }) => {
  const path = '/data/places.json'
  const currentData = await (await request.get(path)).text()
  await page.goto('/?e2e')
  await page.waitForFunction(() => !!navigator.serviceWorker.controller)
  await page.evaluate(async path => {
    const cache = await caches.open('ucsc-map-v2')
    await cache.put(path, new Response('previous release'))
  }, path)

  const readData = () => page.evaluate(async path => (await fetch(path)).text(), path)
  expect(await readData()).toBe(currentData)
  await expect.poll(() => page.evaluate(async path =>
    (await (await caches.match(path))?.text()) !== 'previous release', path)).toBe(true)
  await context.setOffline(true)
  expect(await readData()).toBe(currentData)
})

test('fingerprinted assets stay cache-first', async ({ page }) => {
  await page.goto('/?e2e')
  await page.waitForFunction(() => !!navigator.serviceWorker.controller)
  const contents = await page.evaluate(async () => {
    const asset = document.querySelector<HTMLScriptElement>('script[src*="/assets/"]')!.src
    const cache = await caches.open('ucsc-map-v2')
    await cache.put(asset, new Response('cached build asset'))
    return (await fetch(asset)).text()
  })
  expect(contents).toBe('cached build asset')
})
