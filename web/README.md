# UCSC Map (web)

An installable web map of UC Santa Cruz: search buildings, colleges, dining, libraries, parking and transit stops, open a place, and get a walking route over the campus path network. The interface is a glass design system ported from TileLens.

Free to build, host and run: React, TypeScript, Vite and MapLibre GL JS, with OpenFreeMap vector tiles and OpenStreetMap data. No API key, account, server or database.

## Run it

```bash
cd web
npm install
npm run dev        # http://localhost:5173
```

| Command | What it does |
|---|---|
| `npm run build` | Type-check and build to `dist/` (static files) |
| `npm run preview` | Serve `dist/` on :4173 |
| `npm test` | Unit tests (search, routing, URLs) |
| `npm run e2e` | Browser tests in Chrome with Playwright (builds and serves first) |
| `npm run gallery` | Render every component state over real map backdrops to `../docs/gallery` (needs `npm run preview` running) |
| `node scripts/screenshots.mjs` | Screenshots of the real app at real campus locations |
| `npm run transit` | Rebuild `public/data/transit.json` from METRO's GTFS (needs network and `unzip`) |
| `npm run data` | Rebuild `public/data/*.json` from `../graph`, `../data` and `data-src/` |

Playwright drives your installed Google Chrome, so no browser download is needed.

## Deploy for free

`dist/` is plain static files with relative paths, so any static host works, including a sub-path.

- **GitHub Pages**: build, then publish `web/dist` (for example with the `actions/upload-pages-artifact` and `actions/deploy-pages` actions).
- **Cloudflare Pages / Netlify**: build command `npm run build`, root `web`, output `dist`.

All routes use the URL hash (`#/p/<place>`, `#/r/<from>/<to>`), so no rewrite rules are needed.

### Hosted beta

`.github/workflows/pages.yml` builds `web/` and publishes it to GitHub Pages at https://jmbugarin.github.io/ucsc-campus-router-v2/ on every push to main that touches `web/`. Two repository variables feed the build:

- `TRANSIT_API`: the classmap-transit public ingress (`https://32-188-109-110.sslip.io`), for live departures.
- `ACTIVITY_URL`: the same host plus `/v1/activity`, for opt-in weekly counting.

If either is unset, that feature is off: departures fall back to the bundled schedule, and the counting switch is hidden.

Weekly counting is off until someone turns on "Count my weekly use" in Settings and about. The browser then makes a random id (`crypto.randomUUID`) and keeps it in localStorage. The first place opened in each Pacific week (a building, a room or a stop's departures) sends `{install, week}` and nothing else. Pings made offline are retried for up to 5 weeks. Turning the switch off deletes the server rows for that id, retrying until it succeeds. Settings shows the first 8 characters as a participant code for the private consent record. A different browser, a private window or clearing site data makes a new id.

## Layout

```
web/
  src/design/      glass design system: tokens.css, glass.css, components.tsx, icons, adaptive, motion
  src/map/         MapLibre style (built in code), markers, MapView
  src/data/        place types, loading, typo-tolerant search
  src/routing/     walking graph, Dijkstra with Tobler time, route planner
  src/features/    search results, place details, directions, modals
  src/gallery/     the component gallery page (#/gallery)
  data-src/        OpenStreetMap snapshots (ODbL) the dataset is built from
  scripts/         data build, gallery, screenshots, perf
  e2e/ tests/      Playwright and Vitest tests
```

More: [docs/web-app.md](../docs/web-app.md).
