"""Build data/buildings.json from data/building_sources.json plus OpenStreetMap.

Usage (from data-pipeline/):
    python build_buildings.py

building_sources.json is the hand-edited input: each building's id, display
name, the OSM name to look up, and the aliases that appear in UCSC schedules.
This script adds the geometry: a centroid and the entrance points. It also
reads data/classrooms.json (from fetch_classrooms.py) and, for each building's
`facility_ids`, adds the official schedule names as aliases plus the list of
known rooms. The directory data also carries a map point per room (from the
campus map's classroom layer); those are saved as `room_points`.

A building whose `osm_name` is null is located from its rooms' map points
instead: if the points fall on an OSM footprint (within LOCATE_MAX_M) that
footprint is used, otherwise the building gets one approximate `approach`
entrance at the rooms' centroid. With no room points either, it is written
with `needs_location: true` and no entrances.

Entrances come from OSM `entrance=yes|main` nodes lying within ENTRANCE_MAX_M of
the building footprint. If OSM has none, the entrance falls back to the point
on the footprint closest to the nearest walkway node, so routing still ends
at the edge of the building rather than inside it.
"""

import argparse
import csv
import difflib
import json
import math
import sys
from pathlib import Path

import geopandas as gpd
import osmnx as ox
from shapely.geometry import Point
from shapely.ops import nearest_points

from build_graph import DEFAULT_BBOX

ROOT = Path(__file__).resolve().parents[1]
LOCATE_MAX_M = 5.0  # how close room points must be to a footprint to claim it
CROSS_CHECK_M = 100.0  # warn if a building's centroid is farther than this from its room points
ENTRANCE_MAX_M = 3.0  # how far an entrance node may sit from its footprint
SNAP_WARN_M = 30.0  # warn if an entrance is farther than this from a walkway
GOOD_ENTRANCES = {"yes", "main"}


def fetch(bbox):
    ox.settings.cache_folder = str(Path(__file__).parent / "cache")
    buildings = ox.features_from_bbox(bbox, tags={"building": True})
    buildings = buildings[buildings.geom_type.isin(["Polygon", "MultiPolygon"])]
    entrances = ox.features_from_bbox(bbox, tags={"entrance": True})
    entrances = entrances[entrances.geom_type == "Point"]
    entrances = entrances[entrances["entrance"].isin(GOOD_ENTRANCES)]
    if "access" in entrances:
        entrances = entrances[~entrances["access"].isin(["private", "no"])]
    return buildings, entrances


def official_names(classrooms, facility_ids):
    """Aliases, exact names and room numbers the classroom directory gives for these facilities.

    "Kresge Acad 3201" gives alias "Kresge Acad" and room 3201. A name with no room
    number ("Humn Lecture Hall") is kept whole and its room comes from the facility id.
    """
    aliases, exact, rooms, points = [], {}, set(), {}
    for r in classrooms:
        fid, _, facility_room = (r["facility_id"] or "").partition(" ")
        if fid not in facility_ids:
            continue
        name = r["ais_display_name"]
        head, _, last = name.rpartition(" ")
        if head and any(ch.isdigit() for ch in last):
            aliases.append(head)
            room = last.upper()
        else:
            aliases.append(name)
            room = facility_room.upper()
            exact[name] = room
        rooms.add(room)
        if "lat" in r:
            points[room] = {"lat": r["lat"], "lon": r["lon"],
                            "level": (r.get("level_id") or "").rsplit(".", 1)[-1] or None}
    return list(dict.fromkeys(aliases)), exact, sorted(rooms), points


def footprint_at_points(footprints, fp, utm, points):
    """The (non-roof) OSM footprint under these room points, or None."""
    pts = gpd.GeoSeries([Point(p["lon"], p["lat"]) for p in points.values()], crs=4326).to_crs(utm)
    centroid = pts.union_all().centroid
    candidates = fp[footprints["building"] != "roof"]
    dists = candidates.geometry.distance(centroid)
    best = dists.idxmin()
    return candidates.loc[[best]] if dists[best] <= LOCATE_MAX_M else None


def load_graph_nodes(graph_dir):
    with open(graph_dir / "nodes.csv", newline="") as f:
        return [(float(r["lat"]), float(r["lon"])) for r in csv.DictReader(f)]


def haversine_m(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = (math.sin((p2 - p1) / 2) ** 2
         + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2)
    return 2 * 6371009.0 * math.asin(math.sqrt(a))


def nearest_node(nodes, lat, lon):
    return min(nodes, key=lambda n: haversine_m(lat, lon, n[0], n[1]))


def to_latlon(point_utm, utm_crs):
    p = gpd.GeoSeries([point_utm], crs=utm_crs).to_crs(4326).iloc[0]
    return round(p.y, 7), round(p.x, 7)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sources", type=Path, default=ROOT / "data" / "building_sources.json")
    ap.add_argument("--graph", type=Path, default=ROOT / "graph" / "ucsc")
    ap.add_argument("--classrooms", type=Path, default=ROOT / "data" / "classrooms.json")
    ap.add_argument("--out", type=Path, default=ROOT / "data" / "buildings.json")
    args = ap.parse_args()

    sources = json.loads(args.sources.read_text(encoding="utf-8"))["buildings"]
    classrooms = json.loads(args.classrooms.read_text(encoding="utf-8"))["rooms"]
    nodes = load_graph_nodes(args.graph)
    footprints, entrance_pts = fetch(DEFAULT_BBOX)

    utm = footprints.estimate_utm_crs()
    fp = footprints.to_crs(utm)
    ent = entrance_pts.to_crs(utm)

    # Give each entrance to the nearest footprint (of ALL buildings, not just
    # ours, so a neighbour's door is not claimed by a building 2 m away).
    owner = {}
    for idx, pt in ent.geometry.items():
        dists = fp.geometry.distance(pt)
        nearest = dists.idxmin()
        if dists[nearest] <= ENTRANCE_MAX_M:
            owner.setdefault(nearest, []).append((idx, pt))

    out, problems = [], 0
    for src in sources:
        official, exact, known_rooms, room_points = official_names(
            classrooms, src.get("facility_ids", []))
        record = {
            "id": src["id"],
            "name": src["name"],
            "aliases": list(dict.fromkeys(src["aliases"] + official)),
            "osm_name": src["osm_name"],
            "facility_ids": src.get("facility_ids", []),
            "known_rooms": known_rooms,
            "exact_names": exact,
            "room_points": room_points,
            "located_by": "osm-name",
        }
        rows = None
        if src["osm_name"] is None:
            if not room_points:
                print(f"{src['id']:30s} no location yet (needs_location)")
                out.append({**record, "located_by": None, "needs_location": True,
                            "centroid": None, "entrances": []})
                continue
            record["located_by"] = "room-points"
            rows = footprint_at_points(footprints, fp, utm, room_points)
            if rows is None:  # no footprint under the rooms: approximate with the rooms' centroid
                c = gpd.GeoSeries([Point(p["lon"], p["lat"]) for p in room_points.values()],
                                  crs=4326).to_crs(utm).union_all().centroid
                lat, lon = to_latlon(c, utm)
                print(f"{src['id']:30s}  1 entrance(s) ['room-points'] (approximate: no footprint found)")
                out.append({**record, "centroid": {"lat": lat, "lon": lon}, "entrances": [
                    {"lat": lat, "lon": lon, "kind": "approach", "source": "room-points"}]})
                continue
        else:
            rows = fp[footprints["name"] == src["osm_name"]]
        if rows.empty:
            names = footprints["name"].dropna().unique()
            close = difflib.get_close_matches(src["osm_name"], names, n=3)
            print(f"ERROR {src['id']}: no OSM building named {src['osm_name']!r}; close: {close}")
            problems += 1
            continue
        shape = rows.geometry.union_all()
        c_lat, c_lon = to_latlon(shape.centroid, utm)

        entrances = []
        for idx in rows.index:
            for e_idx, pt in owner.get(idx, []):
                lat, lon = to_latlon(pt, utm)
                kind = "main" if ent.loc[e_idx, "entrance"] == "main" else "door"
                entrances.append({"lat": lat, "lon": lon, "kind": kind, "source": "osm"})
        entrances.sort(key=lambda e: (e["kind"] != "main", e["lat"], e["lon"]))

        if not entrances:
            n_lat, n_lon = nearest_node(nodes, c_lat, c_lon)
            edge_pt = nearest_points(shape.boundary, gpd.GeoSeries(
                [Point(n_lon, n_lat)], crs=4326).to_crs(utm).iloc[0])[0]
            lat, lon = to_latlon(edge_pt, utm)
            entrances.append({"lat": lat, "lon": lon, "kind": "door", "source": "footprint-edge"})

        worst = max(haversine_m(e["lat"], e["lon"], *nearest_node(nodes, e["lat"], e["lon"]))
                    for e in entrances)
        flag = "  <-- check: far from any walkway" if worst > SNAP_WARN_M else ""
        if room_points:
            rc = sum(p["lat"] for p in room_points.values()) / len(room_points)
            rl = sum(p["lon"] for p in room_points.values()) / len(room_points)
            gap = haversine_m(c_lat, c_lon, rc, rl)
            if gap > CROSS_CHECK_M:
                flag += f"  <-- check: footprint is {gap:.0f} m from its classroom points"
        sources_used = sorted({e["source"] for e in entrances})
        print(f"{src['id']:30s} {len(entrances):2d} entrance(s) {sources_used}{flag}")

        out.append({**record, "centroid": {"lat": c_lat, "lon": c_lon}, "entrances": entrances})

    if problems:
        sys.exit(f"{problems} building(s) not found; fix building_sources.json")
    args.out.write_text(json.dumps({"buildings": out}, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8")
    print(f"Wrote {len(out)} buildings to {args.out}")


if __name__ == "__main__":
    main()
