# UCSC Campus Router

Walking directions for UC Santa Cruz, built on my own routing engine instead of a maps API.

## Why this exists

Many UCSC classrooms (Baskin Engineering rooms, Thimann Labs, and more) don't show up in Google or Apple Maps, so "get me to my next class" doesn't work for them. This project keeps its own campus dataset and its own router, so it can eventually answer: *which building is "Thimann Lab 003" in, which entrance do I use, and do I have time to get there?*

The long-term plan is a student app that takes a class schedule, finds the next class, routes to it, and shows time until class, walk time, and the free time in between, with warnings when a transition is tight. See [Roadmap](#roadmap).

**Status: Phases 1-4 are done in the web demo.** The data pipeline, the C routing engine (Dijkstra and A*), a CLI, tests and CI work. A campus dataset covers 32 buildings and all 87 general-assignment classrooms, with a parser for schedule locations like `Kresge Acad 3201`. A web demo routes from **your current location to a class** (or between any two points) and shows Dijkstra and A* side by side. The web demo also has a schedule: paste your MyUCSC class schedule (or add classes by hand) and a Today card tells you what is next, how long the walk is and whether you have time. The mobile app is not built yet.

## How it works

```
OpenStreetMap ──► data-pipeline/ (Python, osmnx) ──► graph/ucsc/{nodes,edges}.csv
                                                          │
                                                          ▼
                                       engine/ (C11): CSR graph, min-heap,
                                       Dijkstra, A*, nearest-node, `route` CLI
                                                          │
                                                          ▼
                          server/ (Python, stdlib) ──► web/ (Leaflet map demo)
```

| Directory | What it is |
|---|---|
| `data-pipeline/` | Downloads the walkable network for the core campus from OpenStreetMap (footpaths, stairs, bridges included) and exports it as CSV. |
| `graph/ucsc/` | The exported graph (1,960 nodes, 5,188 directed edges), committed so nothing needs a live download. |
| `engine/` | The router, written in C11 with no dependencies beyond libc and libm. |
| `server/` | Small local HTTP server: serves the web demo and exposes the engine as a JSON API (`/api/route`, `/api/resolve`, `/api/meta`). |
| `web/` | The demo page: two linked maps (Dijkstra and A*), click-to-route, room lookup, and a replay of the search. |
| `data/` | Campus data: `building_sources.json` (hand-edited names and schedule aliases), `buildings.json` (generated: footprint centroid and entrances), `rooms.json` (optional per-room entrance overrides). |
| `data-pipeline/room_parser.py` | Resolves schedule location strings like "Baskin Engr 152" to a building, room and entrances. |

**Graph format.** `nodes.csv`: `id,osm_id,lat,lon,elev_m`. `edges.csv`: `from,to,length_m,is_stairs,highway`. Node ids are 0..N-1. Edges are directed, and a two-way path appears once per direction.

**Engine design.**
- The graph is stored as compressed sparse rows: one offsets array plus one contiguous edge array.
- Dijkstra and A* share a single search loop. A* orders the heap by `distance + straight-line distance to goal` (haversine), Dijkstra by `distance`.
- The A* heuristic is admissible and consistent. When loading, any edge shorter than the straight line between its endpoints is lengthened to it (this only happens for 0.01 m rounding in the CSV; anything bigger is rejected as corrupt data), so A* never needs to reopen a settled node.
- The min-heap uses lazy deletion rather than decrease-key. A better path to a node pushes a new entry, and stale entries are skipped when popped. That avoids tracking each node's heap position, keeps the heap small and easy to test, and costs only a few extra entries on a graph this size.

## Build and run

Requires a C11 compiler and `make` (Linux, macOS or WSL). Valgrind is optional.

```bash
make -C engine route
cd engine

# Route between two lat/lon points (snapped to the nearest graph nodes)
./route ../graph/ucsc 36.9995 -122.0630 36.9915 -122.0525
./route ../graph/ucsc 36.9995 -122.0630 36.9915 -122.0525 --algo dijkstra --json

# Compare the two algorithms on 1000 random queries
./route ../graph/ucsc --bench 1000
```

Example output:

```
algorithm:       astar
start snapped:   node 1383 (8.6 m from input)
end snapped:     node 1582 (15.1 m from input)
distance:        1754.2 m
path nodes:      37
nodes explored:  852
```

### Web demo

The router is a Linux program, so the server has to run on Linux or inside WSL (running it with Windows Python won't work). On Windows, start it from PowerShell with the launcher, which builds the engine if needed and starts the server in WSL:

```powershell
.\scripts\start-server.ps1
# if PowerShell blocks scripts:  powershell -ExecutionPolicy Bypass -File .\scripts\start-server.ps1
```

On Linux, or from a WSL terminal:

```bash
make -C engine route
python3 server/server.py        # then open http://127.0.0.1:8000
```

The main use is routing to a class: type a schedule location such as `Kresge Acad 3201` and leave **From** blank to start from where you are (the browser asks for your location). The server tries each door of the building and picks the one with the shortest walk plus the straight-line distance from that door to the room itself, so a class in a big building sends you to the nearest door, not just the front one. You can also type a starting room, or click a start and end point on the map. Both maps route the same trip, show the nodes each algorithm explored, and list distance, walk time, nodes explored and engine time. "Replay search" animates the two searches in lockstep.

The server binds to localhost only and needs just the standard library; run it wherever the engine was built (Linux or WSL). The map tiles are loaded from OpenStreetMap and Leaflet from unpkg, so the page needs internet access. Browsers only share your location with pages served over HTTPS or from `localhost`/`127.0.0.1`, so "my location" works on the machine running the server; opening the page from a phone over the local network would need HTTPS.

### Hosting it

For a phone away from your Wi-Fi the server has to run somewhere public. The repository has a `Dockerfile` (server plus the compiled router), a Render blueprint, per-address rate limits, a cap on simultaneous router runs, log lines that never include a location, and Claude photo reading switched off on public servers so nobody can spend your API key. See [docs/hosting.md](docs/hosting.md).

### Schedule and "Today"

Open **My schedule** and either paste your MyUCSC Class Schedule page (Enrollment, then Class Schedule: select the page, copy, paste) or add classes by hand, including one-time events. The **Today** card then shows:

- what you are in now and how long is left, or the next class and how long until it;
- the walk to the next class (from your location if you tick "Use my location", otherwise from the class you are in or just left), your free time, and when to leave;
- every class today with a verdict on each transition between them: **OK**, **Tight** (under 5 minutes to spare) or **Late** (the walk is longer than the gap);
- sensible messages for weekends, holidays, before and after the term, and when the next class is tomorrow.

"Route to next class" sends the next class to the map. The server is stateless: your schedule is saved only in your browser (`localStorage`), instructor names are dropped on import, and the server just checks it and times the walks. Walking time is distance at 1.3 m/s (plus the straight-line distance from the door to the room), rounded up to whole minutes. `data/holidays.json` lists the term dates and no-class days (Veterans Day and Thanksgiving for Fall 2026); it is a starting point, so check it against the official UCSC academic calendar.

### Leave-now reminders

Tick **Remind me when it's time to leave** on the Today card. The page asks your browser for permission to show notifications, then tells you:

- a **heads-up** 5 or 10 minutes before you need to leave (or none), and
- **"Time to leave"** at the moment you should set off for your next class, using the real walk from where you are (or from the class you're in).

If you're already late, you get one "Leave now, you're running late" straight away, and never a repeat. An on-page banner counts down the last few minutes too. The rules (`timetable.plan_reminders`) live on the server and are covered by tests; the page only arms timers and shows what the server planned, which keeps the logic in one place for the mobile app to reuse. Reminders are browser notifications, so **this page has to stay open** (a background tab is fine; a closed browser is not). They need a walking time, so there is nothing to remind about for an online class, an unknown room, or a class tomorrow. Reminders that work with the app closed need push notifications from a server, which is part of the mobile app.

### Calendar file (.ics)

If you keep your classes in a calendar, export it as an `.ics` file (Google Calendar: Settings, Import & export, Export; Apple Calendar: File, Export; Canvas and many others offer a calendar feed or download) and use **Calendar file (.ics)** under My schedule, or paste the calendar text into the paste box. `server/ics.py` reads the standard parts a class timetable needs: weekly events with `BYDAY`, an end date (`UNTIL`) or a count, skipped days (`EXDATE`, kept as `skip_dates` on the class), one-off events, and UTC, named-zone or floating times, converted to Pacific time. It leaves out, and tells you about, what it can't represent faithfully: daily or every-other-week repeats, "first Monday" style rules, a single changed day of a series, all-day or overnight events, and cancelled events. A video-call link as the location becomes "Online". The file is read in your browser; only its text goes to this app's own server, and nothing is stored there.

### Photo import

You can add your schedule from a screenshot or photo of the MyUCSC Class Schedule page. There are two ways to read it:

**On this device (the default; no account, nothing uploaded).** The browser reads the text itself with [Tesseract.js](https://github.com/naptha/tesseract.js), so the picture never leaves your computer. The first time it downloads the text reader (about 10 MB) from a public CDN; the file is checked against a fixed hash before it runs. Plain text recognition scrambles this table, because cells wrap onto two lines ("Mo 8:00AM -" over "9:05AM"), so the server rebuilds the rows and columns from the *positions* of the words: each class is anchored by its class number, and each word is assigned to the nearest row and the column heading above it (`server/ocr_table.py`). The picture is measured and enlarged to a size the reader handles well, and if some rows can't be read it tries again at a different size and combines the results. Common misreads are repaired where the kind of text is known (a letter O in a time, `O01A` for a section), and a room that is exactly one character away from exactly one real room in that building is corrected with a note (`Cowell Acad 13` becomes `113`). Anything it can't read is reported and the rebuilt text is put in the paste box for you to fix. It works best on a screenshot; a crooked or blurry photo of a screen will do worse. Always check the result against your picture.

**With Claude (optional; needs an API key).** More forgiving of photos, but it sends the image off your machine. When you press **Read it with Claude**, the image is sent to Anthropic's Claude API (model `claude-opus-5-5`) to read the text. It is not stored by this app, the browser shrinks it and re-encodes it as a JPEG first (which also drops metadata such as where a photo was taken), and nothing is sent until you press the button. It typically costs a few cents per photo on your own API account.

The reply is forced into a fixed JSON format and then checked like any other class: dropped courses are skipped, unreadable rows are reported instead of guessed, instructor names are not requested, and any text inside the image is treated as data, not instructions. Photos can still be misread, so check each class against your photo; wrong ones can be removed with ×. The request also asks the API to retry on a fallback model if a safety classifier declines it (`server-side-fallback-2026-07-01`).

To turn it on, the server needs the `anthropic` package and an API key in its environment. With the PowerShell launcher the key is the only thing to do: it asks for it (typing is hidden), passes it to WSL for that run only, and never saves it; press Enter to skip photo import. Or set it yourself:

```bash
pip install -r server/requirements.txt             # normal setups
export ANTHROPIC_API_KEY=...                        # your key; never commit it
python3 server/server.py
```

On a machine where the server's Python has no pip (such as a bare WSL Ubuntu), install the Linux build into `server/vendor/` from another Python instead; the server loads it from there:

```bash
python -m pip install --target server/vendor --platform manylinux2014_x86_64 --python-version 3.12 --implementation cp --only-binary=:all: -r server/requirements.txt
```

If the app says the key was rejected, run `python3 server/check_key.py` in WSL (the PowerShell launcher does this for you at start-up). It prints the key's first ten and last four characters, so you can compare them with the Console, and asks Anthropic directly whether the key is accepted. The usual causes are an incomplete copy, a revoked or deleted key, or a login that is not an API key: a Claude.ai or Claude Code sign-in is not one, and a Claude subscription does not include API access. The server already ignores spaces, quotes and an `export` prefix that come along with a pasted key.

Without the package or a key everything else still works, including reading a screenshot on your device; only the Claude option shows what is missing. The tests use a fake client, so they never call the API or need a key.

The engine's `--explored` flag (with `--json`) is what feeds the visualization: it lists the settled nodes in the order they were settled.

### Tests

```bash
(cd app && flutter test)    # Android app
make -C engine test       # unit tests under AddressSanitizer + UBSan
make -C engine valgrind   # same tests under valgrind (leak check)
python3 -m unittest discover -s server -v   # web server, against the real engine
python -m unittest discover -s data-pipeline/tests   # checks the exported CSVs
```

The engine tests cover the heap (including a randomized comparison against `qsort`), graph loading and rejection of malformed files, a hand-made graph with known shortest paths, directed edges, unreachable nodes, and random graphs plus the real UCSC graph where **A\* and Dijkstra must return the same cost on every query**.

### Campus data and room parsing

```bash
cd data-pipeline
python room_parser.py "Baskin Engr 152" "Soc Sci 2 075" "Online"   # try the parser
python build_buildings.py                                          # regenerate data/buildings.json
```

To add or fix a building, edit `data/building_sources.json` (its OpenStreetMap name and the aliases as they appear in schedules), then run `build_buildings.py`. It adds the footprint centroid and entrance points from OpenStreetMap. If a building has no entrance there, it uses the footprint point nearest a walkway and marks it `footprint-edge`. To pin the door for a particular room, add it to `data/rooms.json`.

The parser normalizes the text, treats online/TBA locations as non-physical, matches the longest building alias, and treats the rest as the room. The shared test cases are in `data-pipeline/tests/room_cases.json`.

**Where the data comes from.** `fetch_classrooms.py` reads two public UCSC sources: the [classroom directory](https://classrooms.ucsc.edu/) (87 general-assignment rooms, each with its "AIS Display Name", the exact string class schedules use, such as `Kresge Acad 3201`, `Earth&Marine B206`, `Thim Lecture 003`) and the [campus map](https://maps.ucsc.edu/)'s public classroom-points layer (maintained by UCSC Planning, Design & Construction), which gives each room a coordinate and level. `build_buildings.py` turns these into building aliases, known rooms and per-room points, and tests check that all 87 names resolve. Rooms outside that directory (departmental or non-general-assignment spaces) may still need aliases added by hand.

**How buildings are located.** Most come from an OpenStreetMap footprint matched by name. Four (Cowell Academic, Cowell Com, Crown Classroom, Kresge Academic) have no matching OSM name, so they are located from where their classrooms' map points fall: the footprint under those points is used. Cowell Academic and Cowell Com are two wings of one OSM footprint and share its doors. As an independent check, a test requires every room point to be within 80 m of an entrance of its building (the real maximum is 53 m). A building that cannot be located at all is marked `needs_location`; none currently are.

### Regenerating the graph

```bash
cd data-pipeline
python -m venv ../.venv && ../.venv/bin/pip install -r requirements.txt   # Windows: ..\.venv\Scripts\...
python build_graph.py --out ../graph/ucsc
```

This downloads from OpenStreetMap, so the result can change as the map is edited. The covered area is set by `DEFAULT_BBOX` in `build_graph.py`.

## Benchmark results

1000 random node-to-node queries on the full graph (1,960 nodes, 5,188 edges), seed 42, `make -C engine bench`, `-O2`, Ubuntu on WSL2. Timing varies by machine, but the node counts are deterministic.

| Algorithm | Avg nodes explored | Avg heap pushes | Avg query time | Avg path length |
|---|---:|---:|---:|---:|
| Dijkstra | 976.7 | 1128.4 | 131.6 µs | 1035.7 m |
| A* | 315.8 | 410.5 | 76.2 µs | 1035.7 m |

A* explored **68% fewer nodes** and was **42% faster**, with 0 cost mismatches against Dijkstra. Time falls by less than node count because each A* step also computes a haversine distance.

## Roadmap

1. **Foundation** — done.
2. **Campus data** — done: 32 buildings located, official schedule names for all 87 general-assignment rooms, per-room points and levels, and the room parser. Possible later work: non-general-assignment rooms, verified door positions for buildings that only have an estimated entrance.
3. **Map frontend** — done as a web demo: click two points (or type two rooms), see the route and the nodes each algorithm explored.
4. **Schedule and calendar** — done in the web demo: paste your MyUCSC schedule or add classes by hand; a Today card shows what is happening now, the next class, time until it, walk time, free time and a warning when a transition is tight or impossible. Photo and calendar-file import and leave-now reminders are built too (see below). The Android app (`app/`) reuses the same API: Today, schedule import and settings are done; the map screen and background notifications are next.
5. **Polish** — elevation-weighted routing (UCSC is hilly), stairs-avoiding accessibility mode, "leave now" notifications, a widget.

## Developer notes

A portfolio project: keep code small, readable and tested.

### Layout
- `data-pipeline/` Python. `build_graph.py` pulls the walkable OSM network (osmnx) and writes `graph/ucsc/{nodes,edges}.csv`.
- `engine/` C11. Graph (CSR), min-heap, Dijkstra, A*, nearest-node, `route` CLI + benchmark.
- `graph/ucsc/` exported graph, committed so CI and the engine never need a live OSM download.
- `data/` `building_sources.json` (hand-edited: ids, OSM names, schedule aliases) -> `build_buildings.py` -> `buildings.json` (generated; don't hand-edit, edit the sources file and regenerate). `rooms.json` holds optional per-room entrance overrides keyed `<building-id>:<ROOM>`.
- `data/classrooms.json` generated by `fetch_classrooms.py` from classrooms.ucsc.edu: 87 rooms with their "AIS Display Name" (the exact schedule string) and facility id. This is the authoritative source for schedule names; `build_buildings.py` merges it into aliases via each building's `facility_ids`.
- `data-pipeline/room_parser.py` resolves schedule location strings to building/room/entrances. Shared cases: `data-pipeline/tests/room_cases.json` (reuse them in the Dart port).
- `server/` stdlib Python HTTP server: serves `web/` and wraps the engine (`/api/route`, `/api/resolve`, `/api/meta`). Shells out to `engine/route --json --explored`; bind to localhost only.
- `server/timetable.py` schedule logic (named `timetable`, not `schedule`, to avoid the PyPI package). Tests: `server/test_timetable.py`. `data/holidays.json` has the term dates and no-class days (verify against the official calendar).
- `server/ics.py` reads an iCalendar (.ics) export into meetings (weekly BYDAY/UNTIL/COUNT, EXDATE -> `skip_dates`, one-offs, tz conversion); unsupported shapes are reported in notes, never guessed. `POST /api/schedule/ics`.
- Leave-now reminders: the rules are `timetable.plan_reminders` (pure, tested; returned by `/api/today` when the request has `remind_lead` and `reminded`); `web/schedule.js` only arms timers and shows browser Notifications, so they work only while the page is open. Closed-app reminders need push, i.e. the mobile app. Keep the logic server-side so the Flutter app reuses it.
- `server/photo.py` photo-to-schedule via the Claude API. `anthropic` is an optional dependency (`server/requirements.txt`; imported lazily; on WSL without pip it is installed into the gitignored `server/vendor/` from Windows pip with `--platform manylinux2014_x86_64`). Never commit an API key; never log image data.
- Hosting: `Dockerfile` (multi-stage: builds the engine, then a slim Python image; `.dockerignore` keeps local binaries out), `render.yaml` (untested template), `docs/hosting.md`. `server/limits.py` rate limiter; heavy (engine) endpoints have a tighter limit; `ENGINE_SLOTS` caps concurrent router runs; `log_request` never logs query strings (they hold locations); `/healthz`; `HOST`/`PORT`/`TRUST_PROXY` env; Claude photo is off unless the server is on loopback or `ALLOW_PUBLIC_CLAUDE_PHOTO=1`. CI builds and smoke-tests the image (`container` job); there is no Docker on the dev machine, so that job is the real test.
- `web/` static demo page (Leaflet via unpkg with SRI hashes): two linked maps, Dijkstra vs A*.
- `app/` Flutter Android app (Android first, hosted server, schedule stays on the phone). Riverpod notifiers + a repository per feature; tests use fakes and fixtures captured from the real server (`app/test/fixtures`, invented schedule). Done: Today, schedule import, settings. Next: map route screen (flutter_map), local notifications from the server's `reminders`. Run `flutter analyze && flutter test` from `app/`; Flutter is at `C:\Users\jbuga\OneDrive\Desktop\Launchers\flutter`.

### Commands
Engine (Linux/WSL; on this Windows machine run through `wsl -d Ubuntu --cd /mnt/c/Users/jbuga/src/ucsc-campus-router/engine -- make <target>`):
- `make route` build the CLI (`-std=c11 -Wall -Wextra -Werror`)
- `make test` unit tests under ASan + UBSan
- `make valgrind` same tests under valgrind
- `make smoke` one real route with both algorithms
- `make bench` 1000 random queries, Dijkstra vs A*
- CLI: `./route <graph_dir> <lat> <lon> <lat> <lon> [--algo dijkstra|astar] [--json [--explored]]`, `./route <graph_dir> --bench [N] [--seed S]`

Server (must run in WSL/Linux where the engine was built; stdlib only apart from the optional photo SDK). On Windows start it with `.\scripts\start-server.ps1` (it asks for the API key privately and passes it to WSL for that run only); plain Windows Python exits with an explanation:
- `python3 server/server.py` then open http://127.0.0.1:8000
- `python3 -m unittest discover -s server -v` server tests (need `make -C engine route` first; skipped if the engine isn't built)

Pipeline (Windows venv at `.venv/`; from `data-pipeline/`):
- `python build_graph.py --out ../graph/ucsc` regenerate the graph (needs network)
- `python fetch_classrooms.py` refresh the classroom directory (needs network)
- `python build_buildings.py` regenerate `data/buildings.json` (needs network)
- `python room_parser.py "Baskin Engr 152"` try the parser
- `python -m unittest discover tests` sanity-check graph files, building data and the parser

### Conventions
- Node ids are 0..N-1 in file order; the CSV format is the contract between pipeline and engine.
- `graph_build` lengthens any edge shorter than the straight line between its endpoints (CSV rounding is 0.01 m; more than 1 m is rejected as corrupt). This keeps the haversine heuristic admissible and consistent. Do not remove it.
- Heap uses lazy deletion, not decrease-key (simpler, no position index; stale entries are skipped when popped).
- Dijkstra and A* share one loop in `search.c`; A* only adds the heuristic. Any new search feature must keep A* cost == Dijkstra cost on all tests.
- Tests use `engine/tests/testutil.h` (CHECK / CHECK_NEAR). No test framework.
- Small, focused commits with clear messages.

### Phase plan
1. **Foundation** (done): scaffold, pipeline, engine, CLI, tests, CI, README.
2. **Campus data** (done): 32 buildings, all located; official schedule names, room points and levels for all 87 general-assignment rooms; room parser (all 87 names resolve; every room point is within 80 m of an entrance of its building). Sources: classrooms.ucsc.edu and the maps.ucsc.edu classroom-points ArcGIS layer (public, read-only, one query).
3. **Map frontend** (done, web demo): route from the user's location (blank From, browser geolocation) or a starting room to a class, or click two points. `/api/route_to_room` picks the best door (walk + straight-line door-to-room distance). Shows Dijkstra vs A* side by side with a replay. Possible follow-ups: snap to edges instead of nodes.
4. **Schedule + calendar** (done in the web demo): `server/timetable.py` (pure logic: parse a pasted MyUCSC schedule, validate manual entries, `analyze` = now/next/walk/free time/transition verdicts), exposed by `POST /api/schedule/parse`, `/api/schedule/clean`, `/api/today`. UI in `web/schedule.js`. The server is stateless; the schedule lives in the browser's localStorage and instructor names are never kept. Walking times come from a `walker` callable (the router), so the logic is testable without the engine. Photo import has two routes. DEFAULT, on-device: the browser runs Tesseract.js (lazy-loaded, SRI-pinned, PSM 11, enlarged to ~28 px text, retried at other sizes and combined) and sends only word boxes to `POST /api/schedule/ocr`; `server/ocr_table.py` rebuilds the MyUCSC table from word positions (class-number row anchors, column headings), repairs OCR confusions per cell type, and `Campus.correct_room` fixes a room only when exactly one real room is one edit away. Nothing is uploaded, no key needed. Test it with `server/ocr_fixtures.py` (synthetic layout measured from a real screenshot; never commit a real schedule or screenshot, `web/_dev/` is gitignored for local experiments). OPTIONAL, Claude: photo import is built (`server/photo.py`, Claude API via the official `anthropic` SDK, model `claude-opus-5-5`, strict JSON schema, needs ANTHROPIC_API_KEY on the server; the one feature that sends data off the machine, and only when the student presses the button). The live API call has not been exercised without a key: tests use a fake client. Still to do: `.ics` import, the Flutter app.
5. **Polish:** elevation-weighted edges (fill `elev_m`), stairs-avoidance mode (`EDGE_STAIRS` flag already exported), notifications, widget.

### Phase 2 notes
- A building with `osm_name: null` in `building_sources.json` is located from its rooms' map points (footprint under them, else one approximate `approach` entrance). With no room points it is `needs_location: true` with no entrances; the parser still resolves it (`entrances == []`).
- `buildings.json` also stores `room_points` (room -> lat/lon/level) used to pick the best door and to show the level.
- Graph bbox was extended south (36.9860) so Oakes Academic is covered; a test checks every building has an entrance within 30 m of a graph node.
- OSM already has ~446 buildings (290 named) and 581 entrance nodes in the bbox, so `buildings.json` can be generated from OSM footprints/entrances, then hand-curated (schedule aliases, which entrance is the real front door). Don't invent coordinates from memory.

### Known gaps
- Schedule input is paste or manual only. A pasted schedule must contain the `Days & Times` and date columns as MyUCSC prints them; rows it can't read are reported, not dropped silently.
- Holidays are only the ones listed in `data/holidays.json` (Fall 2026). Add the next term's file when it starts.
- The web demo needs internet (OSM tiles, Leaflet from unpkg). The `route` binary is Linux-only here, so the server runs in WSL; the browser on Windows reaches it via localhost.
- `elev_m` is empty in the exported nodes.
- Nearest-node is a linear scan; add a grid index if the graph grows.
- Snapping goes to the nearest graph *node*, not the nearest point on an edge. Nodes are sparse (intersections/bends), so an entrance can snap up to ~26 m away (Social Sciences 2). Snap to edges to fix.
- Graph covers a core-campus bounding box only (see `DEFAULT_BBOX` in `build_graph.py`).
- CI does not re-run the OSM download (network flake); it checks the committed graph instead.

## Data and license

Map data © OpenStreetMap contributors, available under the [ODbL](https://www.openstreetmap.org/copyright).
