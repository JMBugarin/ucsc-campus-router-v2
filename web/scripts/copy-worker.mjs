// MapLibre 6 loads its worker next to its main bundle. We bundle the main file, so serve the worker files ourselves.
import { cpSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const dist = join(root, 'node_modules', 'maplibre-gl', 'dist')
const out = join(root, 'public', 'maplibre')
mkdirSync(out, { recursive: true })
for (const f of ['maplibre-gl-worker.mjs', 'maplibre-gl-shared.mjs']) cpSync(join(dist, f), join(out, f))
