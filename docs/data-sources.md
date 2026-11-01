# Data sources

| Data | Source | Status |
|---|---|---|
| Building outlines, doors and the walking graph used to place them | [OpenStreetMap](https://www.openstreetmap.org/copyright) via osmnx, in `data/buildings.json` and `graph/ucsc/` | © OpenStreetMap contributors, [ODbL](https://opendatacommons.org/licenses/odbl/). Derived data must keep this attribution (the app credits it in Settings and on the map). |
| Elevation of each graph node | [USGS 3DEP](https://www.usgs.gov/3d-elevation-program) through [OpenTopoData](https://www.opentopodata.org/), fetched once and committed in `graph/ucsc/nodes.csv` | USGS data is public domain. Not used by the app. |
| Classroom names ("AIS Display Name") and facility ids | The public [UCSC classroom directory](https://classrooms.ucsc.edu/), read by `data-pipeline/fetch_classrooms.py` into `data/classrooms.json` | Public pages. No license or reuse terms were found. Its `robots.txt` (read 2026-10-31) allows pages other than `/wp-admin/` and asks for a `Crawl-delay` of 30 seconds; the fetcher now waits that long and checks `robots.txt` on every run. The committed data was fetched earlier with a 0.5 second delay, before that was noticed. |
| Room coordinates and floor levels | The public "General Assignment Classroom Points" layer behind the [UCSC campus map](https://maps.ucsc.edu/) (UCSC Planning, Design & Construction), a public ArcGIS feature service, also in `data/classrooms.json` | Public, read-only. No terms found. The service host publishes no `robots.txt` of its own. |
| Names, aliases and term dates | `data/building_sources.json`, `data/search_aliases.json`, `data/holidays.json` | Written for this project. Term dates match the registrar's 2026-27 academic calendar as of 2026-10-19; check each new term against it. |

## Before a public release

Nobody at UCSC has been asked about this. Room names and positions are facts that the university publishes, and the app only ships the 87 general-assignment rooms, but "public" is not the same as "licensed". Before putting the app in a store, email the owners of the classroom directory (Academic Scheduling / the Registrar) and of the campus map (Planning, Design & Construction), say what the app does, and ask whether using the data is fine and whether they have a better feed. If the answer is no, replace the data with positions verified on foot, which is also the better source for doors.

If you are a UCSC data owner and want something changed or removed, open an issue.
