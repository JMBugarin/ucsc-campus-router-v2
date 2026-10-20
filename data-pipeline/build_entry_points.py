"""Build data/entry_points.json from data/entry_point_sources.json plus OpenStreetMap.

Usage (from data-pipeline/):
    python build_entry_points.py                       # asks the Overpass API for the listed elements
    python build_entry_points.py --elements saved.json # uses a saved Overpass answer instead

entry_point_sources.json is the hand-reviewed list of places a student can arrive at campus (bus
stops, parking): an id, a display name, a type and the OpenStreetMap element it comes from. This
script reads each element's position, snaps it to the nearest node of the walking graph and refuses
to write a point that is outside the graph's area or too far from a path.

Uses only the standard library. The data is (c) OpenStreetMap contributors, ODbL.
"""

import argparse
import csv
import json
import math
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
USER_AGENT = "ucsc-campus-router (student project; data/entry_points.json builder)"
MAX_SNAP_M = 40.0
TYPES = ("bus_stop", "parking", "entrance", "gate")
ATTRIBUTION = "(c) OpenStreetMap contributors, ODbL: https://www.openstreetmap.org/copyright"


class EntryPointError(Exception):
    pass


def haversine_m(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = (math.sin((p2 - p1) / 2) ** 2
         + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2)
    return 2 * 6371009.0 * math.asin(math.sqrt(min(1.0, a)))


def load_graph(graph_dir):
    """(nodes, bbox): nodes is a list of (lat, lon) indexed by node id; bbox is west, south, east, north."""
    with open(Path(graph_dir) / "nodes.csv", newline="") as f:
        nodes = [(float(r["lat"]), float(r["lon"])) for r in csv.DictReader(f)]
    bbox = json.loads((Path(graph_dir) / "meta.json").read_text())["bbox_west_south_east_north"]
    return nodes, bbox


def split_ref(ref):
    kind, _, number = ref.partition("/")
    if kind not in ("node", "way") or not number.isdigit():
        raise EntryPointError(f"{ref!r} should look like node/123 or way/123")
    return kind, int(number)


def fetch(refs):
    """The Overpass elements (with a centre for ways) for these node/way references."""
    ids = {"node": [], "way": []}
    for ref in refs:
        kind, number = split_ref(ref)
        ids[kind].append(str(number))
    parts = [f"{kind}(id:{','.join(numbers)});" for kind, numbers in ids.items() if numbers]
    query = f"[out:json][timeout:60];({''.join(parts)});out center tags;"
    request = urllib.request.Request(
        OVERPASS_URL, data=urllib.parse.urlencode({"data": query}).encode(),
        headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.load(response)["elements"]


def position(element):
    point = element if "lat" in element else element.get("center")
    if not point:
        raise EntryPointError(f"{element.get('type')}/{element.get('id')} has no position")
    return point["lat"], point["lon"]


def nearest_node(nodes, lat, lon):
    best = min(range(len(nodes)), key=lambda i: haversine_m(lat, lon, nodes[i][0], nodes[i][1]))
    return best, haversine_m(lat, lon, nodes[best][0], nodes[best][1])


def build(sources, elements, nodes, bbox):
    """The entry point records for the reviewed sources, or an EntryPointError saying what to fix."""
    found = {f"{e['type']}/{e['id']}": e for e in elements}
    west, south, east, north = bbox
    out, seen = [], set()
    for src in sources:
        if src["id"] in seen:
            raise EntryPointError(f"{src['id']} is listed twice")
        seen.add(src["id"])
        if src["type"] not in TYPES:
            raise EntryPointError(f"{src['id']}: type must be one of {', '.join(TYPES)}")
        element = found.get(src["osm"])
        if element is None:
            raise EntryPointError(f"{src['id']}: {src['osm']} was not in the OpenStreetMap answer")
        lat, lon = position(element)
        if not (south <= lat <= north and west <= lon <= east):
            raise EntryPointError(f"{src['id']}: {src['osm']} is outside the walking graph's area")
        node, snap_m = nearest_node(nodes, lat, lon)
        if snap_m > MAX_SNAP_M:
            raise EntryPointError(
                f"{src['id']}: {src['osm']} is {snap_m:.0f} m from the nearest path (limit {MAX_SNAP_M:.0f} m)")
        out.append({"id": src["id"], "name": src["name"], "type": src["type"],
                    "lat": round(lat, 7), "lon": round(lon, 7), "node": node,
                    "snap_m": round(snap_m, 1), "osm": src["osm"]})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sources", type=Path, default=ROOT / "data" / "entry_point_sources.json")
    ap.add_argument("--graph", type=Path, default=ROOT / "graph" / "ucsc")
    ap.add_argument("--elements", type=Path, help="a saved Overpass answer, instead of asking the API")
    ap.add_argument("--out", type=Path, default=ROOT / "data" / "entry_points.json")
    args = ap.parse_args()

    sources = json.loads(args.sources.read_text(encoding="utf-8"))["entry_points"]
    nodes, bbox = load_graph(args.graph)
    if args.elements:
        elements = json.loads(args.elements.read_text(encoding="utf-8"))["elements"]
    else:
        elements = fetch([s["osm"] for s in sources])
    try:
        points = build(sources, elements, nodes, bbox)
    except EntryPointError as e:
        sys.exit(f"ERROR {e}")
    record = {"attribution": ATTRIBUTION, "entry_points": points}
    args.out.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for p in points:
        print(f"{p['id']:34s} node {p['node']:5d}  {p['snap_m']:5.1f} m from the path")
    print(f"Wrote {len(points)} entry points to {args.out}")


if __name__ == "__main__":
    main()
