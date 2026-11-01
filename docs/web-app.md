# UCSC Map (web): design, data and limits

## Stack

| Layer | Choice | Why |
|---|---|---|
| Map engine | MapLibre GL JS 6 | Open source vector renderer: smooth camera, hillshade, clustering, data-driven styling. Leaflet is raster-first and cannot restyle the cartography. |
| Tiles | OpenFreeMap (planet vector tiles) | Free, no key, no account, no quota or billing, OpenMapTiles schema. Attribution is shown on the map and in Settings. Tiles are not cached by the app, per provider policy. |
| Terrain | Mapzen terrain tiles on AWS Open Data | Free, no key. Used only for hillshade, which shows UCSC's hills. |
| Data | OpenStreetMap (ODbL) plus UCSC's public classroom data already in this repo | Names, doors, bus stops, parking, plazas. |
| Routing | Own Dijkstra in the browser over the campus graph in `graph/ucsc` (1,960 nodes, 5,188 edges) | The graph is small; no routing server. Valhalla/OSRM would need hosting. |
| Frontend | React 19, TypeScript, Vite | Small, static output. |
| Hosting | Any static host; installable PWA | No server, no database. |

## What was reused and what was dropped

Reused: `graph/ucsc` (walking graph with elevation), `data/buildings.json` (32 curated buildings with doors and room points, plus 53 more teaching buildings from the campus map), `data/search_aliases.json` and the building aliases, the data-pipeline scripts that produced them.

New: everything in `web/`. Added from OpenStreetMap (snapshot in `web/data-src`): colleges, dining, libraries, landmarks and plazas, bus stops, parking lots, and bridge ways (used to mark bridge edges in the graph).

Not touched: the Flutter app in `app/` (the schedule product "Classmap"). The web map is a separate product in `web/`; the Flutter app is unchanged. The pre-rebuild state is tagged `baseline/pre-web-rebuild`.

## The glass design system

Translated from TileLens (`ui/design/tokens.py`, `material.py`, `components.py`, `appearance.py`) to CSS and React, in `web/src/design`:

| TileLens | Web |
|---|---|
| `Space` 4 to 24, `Radius` 10 / 12 / 18 / 20, `Motion` 120 / 180 / 280 ms | `tokens.css` variables, mirrored in `tokens.ts` |
| DARK and LIGHT materials (tints 22 to 34 percent, rim, hairline, text levels, accent, status colors) | the same values as CSS variables for each theme |
| `paint_glass`: gradient body, upper sheen, diagonal 1.5 px rim, hairline | `.glass`: gradient plus `backdrop-filter`, a sheen layer over the top 42 percent, a masked `::before` gradient ring, a 1 px hairline shadow |
| `paint_shadow` two layers (wide ambient, tight contact) | `--elev-floating` and `--elev-raised`, two box shadows each; never animated |
| Native blur or solid fallback | `@supports not (backdrop-filter)`, `prefers-reduced-transparency`, and an "Opaque panels" setting use the solid body |
| `GlassWindow`, `GlassCard`, `GlassButton`, `Segmented`, `Switch`, `Banner` | `GlassPanel`, `GlassCard`, `GlassButton`/`GlassIconButton`, `GlassSegmentedControl`, `GlassSwitch`, `GlassBanner`, plus `GlassSearch`, `GlassList`, `GlassToolbar`, `GlassTooltip`, `GlassModal`, `GlassSheet` |
| Flat lists, selected row has a thin accent outline and wash | `.glist__row` |
| `LumaSwitch`/`strength_for`: fill strength follows backdrop brightness and detail, with hysteresis | `adaptive.ts` samples the map canvas under each panel when the map goes idle and applies a strength between 0.9 and 1.5 only when it moves by more than a dead band, so panels do not flicker |
| Motion at most 180 ms, reduce-motion | all UI transitions use `--m-*`; reduced motion or the setting sets them to 0 |
| 36 pt shadow bleed of native windows | not needed on the web; panels sit 16 px from the edges and the shadow is not clipped |

Differences, on purpose: the web blur is `blur(26px)` with a small brightness and saturation adjustment because the map behind is far more detailed than TileLens's window backdrops; the accent for light mode stays TileLens blue; touch devices get 44 px targets and a 1.14x type scale.

## Map

The style is written in code (`src/map/style.ts`) over the OpenMapTiles schema, with a light and a dark palette: forest and grass tones for redwoods and meadows, hillshade, roads by class, dashed paths, stairs as a heavier dash, bridges with a pale inner line, buildings from zoom 14.5 with outlines from 16. Campus places are a GeoJSON source drawn as category markers: colleges and libraries at every zoom, the rest from zoom 15.8, parking clustered. Labels appear from zoom 15.2.

## Navigation

- Routes are Dijkstra over mapped edges only, weighted by walking time (Tobler's hiking function on the graph's 10 m USGS elevation, stairs slowed).
- The start and end can be a building door (the quickest of up to six known doors is used) or a point. The short gap from a point to the nearest mapped path (up to 150 m) is drawn dotted and counted in the totals. Beyond 150 m no route is drawn; a message says so and gives the straight-line distance. Straight lines between building centers are never used as routes.
- Legs are labelled path, stairs, road or bridge. Bridge edges are edges within 3 m of an OSM `bridge` way (36 edges).
- "Avoid stairs" excludes stair edges. If every route needs stairs it shows the shortest one with a warning. It is not an accessibility route: see UCSC's [accessibility map](https://ada.ucsc.edu/accessibility-map/).
- "My location" uses the browser's permission prompt; denial and unavailability show explanations.

## Limits

- Walking graph covers the core campus (roughly 36.986 N to 37.003 N). Lower campus is not routable.
- No indoor routes, closures or construction.
- Times are estimates. Elevation is 10 m data, so grades on short edges are noisy.
- Transit, METRO buses: the stops and schedule come from Santa Cruz METRO's open GTFS feed ([developer.scmetro.org](https://developer.scmetro.org), CC BY 4.0 plus the SCMTD Developer License, no key). `npm run transit` cuts it down to the 1,291 trips that serve UCSC (routes 11, 16, 18, 19, 20), 20 stops, in `public/data/transit.json`. A stop page shows the next scheduled buses; Directions adds "By bus" when a direct bus gets there at least two minutes sooner than walking. The bundled schedule covers 2026-09-10 to 2026-12-16 and must be rebuilt for each term.
- Transit, live: METRO also publishes GTFS-realtime (`rt.scmetro.org/gtfsrt/trips|vehicles|alerts`, no key). Its servers send no CORS headers, so a browser cannot read them directly. The app has a decoder for the feeds (tested on recorded real feeds) and turns on delays and alerts when `VITE_RT_BASE` points at a pass-through proxy (a free Cloudflare Worker is enough; the source is `web/worker/rt-proxy.js`). No proxy is deployed, so live times are off and the page says so.
- Transit, campus shuttles (Loop, Upper Campus, Night Upper Campus): UCSC tracks them only in the flexigo app behind a UCSC login. No public schedule, GTFS or location feed was found, so they are not on the map as bus data; the transit panel lists them with the official page and flexigo link.
- The bus planner only compares direct trips between campus stops (no transfers, no trips from off campus), using walking time to and from the stops. It uses the schedule, not live delays.
- Parking lot names come from OpenStreetMap lot numbers; permit rules are not shown (link to TAPS).
- "Science Hill" is an OSM locality point, not a boundary. Quarry Plaza is the center of the OSM plaza way.
- Only the 32 curated buildings have doors, room counts and the classroom directory's schedule names. The 53 buildings added from the campus map (Communications, Sinsheimer, Theater Arts and Elena Baskin units, college libraries and classroom buildings and others) have names, nicknames and an outline centre, not doors or room lists.
- Place data is a snapshot (`web/data-src`, October 2026). Refresh with the Overpass queries noted in `web/scripts/build-data.mjs`.
- Not tested on physical phones or on Safari/Firefox; tested in desktop Chrome with a mobile viewport and touch emulation.

## Visual testing

`npm run gallery` renders each component and state (rest, hover, press, focus, selected, disabled, loading, empty, error) over four real map backdrops (dark forest, pale plazas and roads, dense paths and buildings, hillshade terrain), in light and dark, at desktop and mobile widths: 16 sets of 11 captures plus an overview each. `docs/gallery` keeps a few overviews; the rest is regenerated on demand.

## Measured results

Run on 2026-10-31 on a Mac, desktop Chrome, release build. `npm test`: 19 unit tests; `npm run e2e`: 16 browser tests (desktop and a 390 px touch viewport); all passed.

| Measure | Result |
|---|---|
| JS (gzip) | app 89 KB, MapLibre 287 KB; CSS 15 KB. Campus data: places 39 KB, graph 140 KB (uncompressed) |
| First load transferred | about 380 KB before tiles |
| Search | 0.22 ms per query over 178 places (budget 3 ms, enforced by a test) |
| Route planning | 1.8 ms per plan on average (budget 25 ms, enforced by a test) |
| Page weight | about 145 DOM nodes; 18 to 19 MB JS heap |
| Map ready | 2.1 s (phone viewport, warm network) to 8.5 s (first cold load) in headless Chrome |

Frame rate was **not** measured meaningfully: automated Chrome renders WebGL in software, where panning showed 83 to 217 ms per frame. That says nothing about real phones or GPUs. Glass blur cost on real mobile hardware is untested; the "Opaque panels" setting and `prefers-reduced-transparency` turn blur off.
