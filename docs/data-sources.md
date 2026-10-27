# Data sources

| Data | Source | Status |
|---|---|---|
| Elevation of each graph node | [USGS 3DEP](https://www.usgs.gov/3d-elevation-program) 10 m data (`ned10m`) through the [OpenTopoData](https://www.opentopodata.org/) API, fetched once by `data-pipeline/fetch_elevation.py` and committed in `graph/ucsc/nodes.csv` | USGS data is public domain. |
| Walking network and building footprints/entrances | [OpenStreetMap](https://www.openstreetmap.org/copyright) via osmnx, committed in `graph/ucsc/` and `data/buildings.json` | © OpenStreetMap contributors, [ODbL](https://opendatacommons.org/licenses/odbl/). Derived data must keep this attribution. |
| Campus bus stops and parking areas (entry points) | [OpenStreetMap](https://www.openstreetmap.org/copyright) through the Overpass API, chosen by hand in `data/entry_point_sources.json`, built by `data-pipeline/build_entry_points.py` into `data/entry_points.json`. Positions and names only: no routes, no timetable | © OpenStreetMap contributors, [ODbL](https://opendatacommons.org/licenses/odbl/). Derived data must keep this attribution. |
| Classroom names ("AIS Display Name") and facility ids | The public [UCSC classroom directory](https://classrooms.ucsc.edu/), read by `data-pipeline/fetch_classrooms.py` and committed as `data/classrooms.json` | Public web pages. No license or reuse terms were found or checked; this project is not affiliated with or endorsed by UCSC. |
| Room coordinates and floor levels | The public classroom-points layer behind the [UCSC campus map](https://maps.ucsc.edu/) (UCSC Planning, Design & Construction), also in `data/classrooms.json` | Same as above: public, read-only, terms not checked. |
| Hand-edited names, aliases and term dates | `data/building_sources.json`, `data/search_aliases.json`, `data/holidays.json` | Written for this project. Term dates match the registrar's 2026-27 calendar as of 2026-10-19; check each new term against it. |

If you are a UCSC data owner and want something changed or removed, open an issue.
