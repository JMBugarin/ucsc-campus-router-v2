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
- Routes are drawn along the real shape of each path: `graph/ucsc/shapes.json` (from `data-pipeline/build_edge_shapes.py`, OpenStreetMap via Overpass) holds the bends the simplified graph dropped. 2,592 of 2,594 edges matched by length; the old straight lines strayed more than 10 m from the path on 196 edges and up to 162 m. A start or destination joins the nearest point on a path rather than the nearest intersection (doors: median 3.8 m instead of 8.0 m), and that last unmapped stretch is drawn dotted and called approximate. `npm run network:audit` lists doors far from any path, edges OpenStreetMap changed, and paths that stop short of a door, in [walking-network-audit.md](walking-network-audit.md), for checking on foot.
- No indoor routes, closures or construction.
- Times are estimates. Elevation is 10 m data, so grades on short edges are noisy.
- Transit, METRO buses: the stops and schedule come from Santa Cruz METRO's open GTFS feed ([developer.scmetro.org](https://developer.scmetro.org), CC BY 4.0 plus the SCMTD Developer License, no key). `npm run transit` cuts it down to the 1,291 trips that serve UCSC (routes 11, 16, 18, 19, 20), 20 stops, in `public/data/transit.json`. A stop page shows the next scheduled buses. Directions puts Walk and Bus side by side, each with when to leave and when it gets there, and says how much sooner or later the bus arrives (or, arriving by a class, how much later you can leave), so anyone who would rather ride can, even when walking is quicker. The bundled schedule covers 2026-09-10 to 2026-12-16 and must be rebuilt for each term.
- Transit, live: with `VITE_TRANSIT_API` set (the hosted beta), stop pages and trips use the Classmap transit service: predicted departures from METRO's trip updates, bus positions from `/v1/vehicles` and service alerts from `/v1/alerts`. A trip's own bus is highlighted on the map with METRO's occupancy report ("few seats", "standing room"), trips by bus say "Live: 2 min late" or "Scheduled", and alerts that name the trip's routes or stops (or no route at all) are shown. Positions older than three minutes are hidden. METRO's GTFS-realtime servers send no CORS headers, so without the service the app can use a pass-through proxy (`VITE_RT_BASE`, source in `web/worker/rt-proxy.js`) for delays and alerts only.
- Transit, campus shuttles (Loop, Upper Campus, Night Upper Campus): UCSC tracks them only in the flexigo app behind a UCSC login. No public schedule, GTFS or location feed was found, so they are not on the map as bus data; the transit panel lists them with the official page and flexigo link.
- Bus trips come from a RAPTOR planner (`src/transit/raptor.ts`) over METRO's whole schedule (`public/data/metro.json`, 759 stops and 6,362 trips in 74 stop patterns, 89 KB compressed, built by `npm run metro` and loaded when Directions opens): up to two transfers with short walks between nearby stops, "leave now" or "arrive by" a class (one search per five minutes over the two hours before). Walking on campus uses the mapped paths to the door; walking in town uses the town street network (`public/data/town.json`, 26,698 junctions and 35,670 streets of Santa Cruz, Live Oak, Capitola, Soquel and Scotts Valley from OpenStreetMap, 457 KB compressed, built by `data-pipeline/build_town_graph.py`, loaded only when a trip starts or ends off campus, flat-ground times); only outside that area is it a straight line with a 25 % detour, labelled as an estimate. When the whole way can be walked, the planner looks for trips that ride at least one bus even if walking is faster, keeps those that walk less than the walk itself, and lists the same bus once, from the stop that lets you leave latest. Directions opens on Walk unless the walk takes more than half an hour or Bus was picked last time (kept in the browser as `travelMode`); trips that start or end off campus have no walking route and go by bus. Arrive-by never offers a bus that has already left: when nothing gets there in time it says so and lists the buses still to come with how late each arrives. A trip can start or end at your location, a point picked on the map, or an address found with [Photon](https://photon.komoot.io/) (komoot's OpenStreetMap geocoder; only what you type into address search is sent, and only when you press search). Bus legs are drawn along METRO's published route shapes (74 shapes, simplified to 4 m, in `metro.json`). Live predictions and the bus's position and occupancy are shown where the transit service has them.
- Parking lot names come from OpenStreetMap lot numbers; permit rules are not shown (link to TAPS).
- "Science Hill" is an OSM locality point, not a boundary. Quarry Plaza is the center of the OSM plaza way.
- Classes: Today, Schedule and Map tabs share the glass panel. The schedule logic is a TypeScript port of the phone app's (`web/src/schedule`): `tests/schedule.test.ts` runs it against the app's own fixtures (`app/test/fixtures/golden_port.json` and `schedule_cases.json`): meeting cleaning, location splitting, 107 room resolutions, MyUCSC paste reading and 21 day cases including leave-by times and the walk between back-to-back classes. Walking minutes come from the campus path graph. Classes are added by pasting MyUCSC's Class Schedule page or by hand, checked in a review sheet, and saved only in `localStorage` (`classmap.schedule.v1`, the app's JSON shape). The room field also accepts nicknames such as "BE 152", which the strict app rules don't. Reminders fire only while a tab is open; there is no push server yet. Calendar files are not offered because MyUCSC has no obvious export.
- Photo import: "Take or upload a picture" reads a screenshot or photo of the Class Schedule page in the browser with [Tesseract.js](https://github.com/naptha/tesseract.js) 7 (Apache-2.0, LSTM engine, the 2.8 MB `4.0.0_best_int` English model from `@tesseract.js-data/eng`). The worker, engine and model are served from this site (`public/tesseract`, copied by `scripts/copy-worker.mjs`) and load only when someone picks a picture, so the picture never leaves the device. The words and their positions go through a TypeScript port of the app's reader (`web/src/schedule/ocr`), which `tests/ocr.test.ts` checks against the app's 22 recorded readings (`app/test/fixtures/ocr`): rows, issues and review flags all match. A browser test renders a synthetic MyUCSC-style page, photographs it and imports it. Real MyUCSC screenshots and phone photos still need checking with students' permission.
- Live directions: once someone has used their location (or turned on "Use my location" in Settings), Directions and Get me there start from it, and the map follows them: the position is watched while the page is visible (paused when hidden) and every fresh fix is used (about one a second), the dot glides between fixes at the walker's pace (`src/map/glide.ts`) and the camera moves with it every frame instead of jumping every few metres, the route is planned again from where they are every 20 m or 30 s and at once when they are more than 35 m off it (allowing for a vague fix), "You've arrived" shows within 20 to 40 m of the door, and dragging the map stops following until "Follow my location" is pressed. The site never prompts for location just for opening; a live trip is something the person asked for. Location stays in the browser.
- Housing: the 174 on-campus residence halls and apartment buildings from the campus map's residential layer (`data/housing.json`, built by `data-pipeline/fetch_housing.py`) are places of their own (`kind: "housing"`), found by the names students use ("C9 Apt 2", "Casa Primera", "Merrill DuBois", "RCC A Building") and listed by college under the Housing chip. Their pins appear only when zoomed in close. A route to one ends at whichever of its outline corners is quickest to reach. "Set as home" on a dorm's page saves it in the browser: the map then offers "Get me home", choosing a place in Directions offers Home first, and Today shows the walk home after the last class. The phone app has the same search, a Home chip on the map, "Walk home" on Today and the home in Settings.
- Rooms: each of the 87 general-assignment classrooms is its own place (`kind: "room"`), built by `web/scripts/rooms.mjs` from the official room point, the building's OpenStreetMap doors and `data/rooms.json`. Directions to a room end at the one or two doors nearest the room point (never the building centre or simply the main entrance), and a dotted line marks the last stretch inside. A floor is shown only when a published UCSC source confirms it (42 rooms, from the library's floor plan, the college maps and UCSC News; see [floors](floors.md)) or someone walked the room, with where it is from the way in ("Floor 2 · upstairs"). Neither the room number nor the campus map level is used: the map puts McHenry 1340 on level L3, but it is on floor 1. A room page says "Not checked on foot yet" until someone walks it and adds a guide to `data/rooms.json` (see [data/README.md](../data/README.md)); the build rejects guides without a checked date.
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
