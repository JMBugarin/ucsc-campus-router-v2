"""Recover the true shape of every walking-graph edge from OpenStreetMap into graph/ucsc/shapes.json.

Usage (from data-pipeline/):
    python build_edge_shapes.py            # fetch from the Overpass API, then build
    python build_edge_shapes.py --osm f.json  # build from a saved Overpass reply

The graph in graph/ucsc was simplified when it was built: an edge joins two intersections and its
length follows the path, but only its end points were kept, so a route drawn from it cuts corners.
This follows the OpenStreetMap ways between the two end nodes of each edge (by their OSM node ids,
through nodes that are not graph nodes) and keeps the path whose length matches the edge, within
max(3 m, 3 %). Edges with no match, because OpenStreetMap changed since the graph was downloaded,
keep a straight line and are listed in the report. Standard library only.

Output: {"source", "fetched", "matched", "unmatched", "shapes": {"<a>-<b>": [[lat, lon], ...]}},
keyed by graph node ids with a < b, holding the points strictly between a and b, from a to b.
"""

import argparse
import csv
import json
import math
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRAPH = ROOT / "graph" / "ucsc"
OVERPASS = "https://overpass-api.de/api/interpreter"
USER_AGENT = "classmap data tool (student project)"
MARGIN = 0.002
MAX_POINTS = 600


def metres(a, b):
    r = 6371008.8
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(h)))


def fetch(bbox):
    west, south, east, north = bbox
    box = f"{south - MARGIN},{west - MARGIN},{north + MARGIN},{east + MARGIN}"
    query = f'[out:json][timeout:120];way["highway"]({box});out body;>;out skel qt;'
    data = urllib.parse.urlencode({"data": query}).encode()
    req = urllib.request.Request(OVERPASS, data=data, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=180) as resp:
        return json.loads(resp.read().decode("utf-8"))


def build(osm, nodes, edges):
    coords = {e["id"]: (e["lat"], e["lon"]) for e in osm["elements"] if e["type"] == "node"}
    adjacent = {}
    for w in osm["elements"]:
        if w["type"] != "way":
            continue
        ids = w["nodes"]
        for a, b in zip(ids, ids[1:]):
            if a in coords and b in coords and a != b:
                adjacent.setdefault(a, set()).add(b)
                adjacent.setdefault(b, set()).add(a)
    graph_osm = {int(n["osm_id"]): int(n["id"]) for n in nodes}
    shapes = {}
    unmatched = []
    seen = set()
    for e in edges:
        a, b = int(e["from"]), int(e["to"])
        key = (min(a, b), max(a, b))
        if key in seen:
            continue
        seen.add(key)
        want = float(e["length_m"])
        start = int(nodes[key[0]]["osm_id"])
        goal = int(nodes[key[1]]["osm_id"])
        best = None
        # depth-first along ways, only through nodes that are not intersections of the graph
        stack = [(start, [start], 0.0)]
        while stack:
            node, path, length = stack.pop()
            if length > want * 1.03 + 3 or len(path) > MAX_POINTS:
                continue
            for nxt in adjacent.get(node, ()):
                if nxt in path:
                    continue
                step = length + metres(coords[node], coords[nxt])
                if nxt == goal:
                    err = abs(step - want)
                    if err <= max(3.0, 0.03 * want) and (best is None or err < best[0]):
                        best = (err, path + [nxt])
                elif nxt not in graph_osm:
                    stack.append((nxt, path + [nxt], step))
        if best is None:
            unmatched.append({"from": key[0], "to": key[1], "length_m": want})
        elif len(best[1]) > 2:
            shapes[f"{key[0]}-{key[1]}"] = [[round(coords[p][0], 6), round(coords[p][1], 6)] for p in best[1][1:-1]]
    return shapes, unmatched, len(seen)


def read(name):
    with open(GRAPH / name, newline="") as f:
        return list(csv.DictReader(f))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--osm", type=Path, help="a saved Overpass reply instead of fetching")
    args = ap.parse_args()
    meta = json.loads((GRAPH / "meta.json").read_text())
    osm = json.loads(args.osm.read_text()) if args.osm else fetch(meta["bbox_west_south_east_north"])
    nodes, edges = read("nodes.csv"), read("edges.csv")
    shapes, unmatched, pairs = build(osm, nodes, edges)
    out = {
        "source": "OpenStreetMap ways via the Overpass API (ODbL)",
        "fetched": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "pairs": pairs,
        "matched": pairs - len(unmatched),
        "unmatched": unmatched,
        "shapes": shapes,
    }
    (GRAPH / "shapes.json").write_text(json.dumps(out, separators=(",", ":")) + "\n")
    points = sum(len(s) for s in shapes.values())
    print(f"{pairs} edge pairs: {pairs - len(unmatched)} matched ({len(shapes)} with bends, {points} points), {len(unmatched)} straight", file=sys.stderr)


if __name__ == "__main__":
    main()
