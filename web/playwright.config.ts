import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: 'e2e',
  timeout: 60_000,
  retries: 1,
  workers: 2,
  reporter: [['list']],
  use: {
    baseURL: 'http://localhost:4173',
    channel: 'chrome',
    launchOptions: { args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] },
  },
  webServer: [
    { command: 'npm run build && npx vite preview --port 4173 --strictPort', url: 'http://localhost:4173', reuseExistingServer: true, timeout: 120_000 },
    { command: 'node scripts/copy-worker.mjs && VITE_TRANSIT_API=/svc VITE_ACTIVITY_URL=/svc/v1/activity VITE_FEEDBACK_URL=/svc/v1/room-feedback npx vite build --outDir dist-service && npx vite preview --outDir dist-service --port 4174 --strictPort', url: 'http://localhost:4174', reuseExistingServer: true, timeout: 120_000 },
  ],
})
