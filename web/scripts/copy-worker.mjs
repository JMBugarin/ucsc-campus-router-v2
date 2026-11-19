// MapLibre 6 loads its worker next to its main bundle, and Tesseract.js loads its worker, engine and English model
// at run time. We bundle the main files, so serve these ourselves (copied from node_modules, git-ignored).
import { cpSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const modules = join(root, 'node_modules')
const maplibre = join(root, 'public', 'maplibre')
mkdirSync(maplibre, { recursive: true })
for (const f of ['maplibre-gl-worker.mjs', 'maplibre-gl-shared.mjs']) cpSync(join(modules, 'maplibre-gl', 'dist', f), join(maplibre, f))

const tesseract = join(root, 'public', 'tesseract')
mkdirSync(tesseract, { recursive: true })
cpSync(join(modules, 'tesseract.js', 'dist', 'worker.min.js'), join(tesseract, 'worker.min.js'))
for (const f of ['tesseract-core-lstm.wasm.js', 'tesseract-core-simd-lstm.wasm.js', 'tesseract-core-relaxedsimd-lstm.wasm.js']) cpSync(join(modules, 'tesseract.js-core', f), join(tesseract, f))
cpSync(join(modules, '@tesseract.js-data', 'eng', '4.0.0_best_int', 'eng.traineddata.gz'), join(tesseract, 'eng.traineddata.gz'))
