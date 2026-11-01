import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  base: './',
  plugins: [react()],
  optimizeDeps: { exclude: ['maplibre-gl'] },
  build: {
    target: 'es2022',
    chunkSizeWarningLimit: 1100,
    rollupOptions: { output: { manualChunks: (id: string) => (id.includes('maplibre-gl') ? 'maplibre' : undefined) } },
  },
  test: { include: ['tests/**/*.test.ts'], environment: 'node' },
})
