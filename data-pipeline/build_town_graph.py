"""Build the walking network of the Santa Cruz area off campus into web/public/data/town.json.

Usage (from data-pipeline/):
    python build_town_graph.py              # fetch from the Overpass API, then build
    python build_town_graph.py --osm f.json  # build from a saved Overpass reply

The campus graph (graph/ucsc) stops at the campus edge. Trips that start or end in town need the
walk to and from the bus on real streets, so this takes every OpenStreetMap way people can walk on
in the area where students live (Santa Cruz, Live Oak, Capitola, Soquel, Scotts Valley), joins them
at shared nodes, keeps only the junctions as graph nodes and the bends between them as shapes, and
keeps the largest connected part. Motorways and ways marked private or no-foot are left out. No
elevation: town walking times are flat-ground estimates. Standard library only.

Output: the web map's graph format with each street once ("undirected": true; the map adds the
other direction): {lat, lon, ele, edges: [from, to, length_m, kind] * n, shapes: {pairs, off, pts},
source, fetched}. kind is 0 path, 1 steps, 2 road. Coordinates are rounded to about a metre and bends
simplified to within 3 m.
"""

import argparse
import json
import math
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "web" / "public" / "data" / "town.json"
OVERPASS = ("https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter")
CACHE = Path(__file__).resolve().parent / "cache" / "town-overpass.json"
USER_AGENT = "classmap data tool (student project)"
# west, south, east, north
BBOX = (-122.075, 36.945, -121.93, 37.065)
WALKABLE = ("footway|path|pedestrian|steps|residential|living_street|service|unclassified|tertiary|tertiary_link|"
            "secondary|secondary_link|primary|primary_link|track|cycleway|corridor|road")
ROADS = {"residential", "service", "unclassified", "tertiary", "tertiary_link", "secondary", "secondary_link",
         "primary", "primary_link", "track", "road", "living_street"}


def metres(a, b):
    r = 6371008.8
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(h)))


def fetch():
    west, south, east, north = BBOX
    query = (f'[out:json][timeout:180];way["highway"~"^({WALKABLE})$"]'
             f'["access"!~"^(private|no)$"]["foot"!~"^(no)$"]["service"!~"^(parking_aisle|driveway|drive-through)$"]'
             f'({south},{west},{north},{east});out body;>;out skel qt;')
    data = urllib.parse.urlencode({"data": query}).encode()
    last = None
    for attempt in range(4):
        url = OVERPASS[attempt % len(OVERPASS)]
        try:
            req = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=300) as resp:
                raw = resp.read().decode("utf-8")
            CACHE.parent.mkdir(exist_ok=True)
            CACHE.write_text(raw)
            return json.loads(raw)
        except (urllib.error.URLError, TimeoutError) as e:
            last = e
            print(f"overpass {url}: {e}; retrying", file=sys.stderr)
            time.sleep(20 * (attempt + 1))
    raise last


def offset(p, a, b):
    kx, ky = math.cos(math.radians(p[0])) * 111320, 110540
    ax, ay, bx, by = (a[1] - p[1]) * kx, (a[0] - p[0]) * ky, (b[1] - p[1]) * kx, (b[0] - p[0]) * ky
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    u = 0 if l2 == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / l2))
    return math.hypot(ax + u * dx, ay + u * dy)


def simplify(points, tol=3.0):
    """Douglas-Peucker: the bends of a street to within tol metres."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        worst, at = -1.0, -1
        for i in range(a + 1, b):
            d = offset(points[i], points[a], points[b])
            if d > worst:
                worst, at = d, i
        if worst > tol:
            keep[at] = True
            stack += [(a, at), (at, b)]
    return [p for p, k in zip(points, keep) if k]


def build(osm):
    coords = {e["id"]: (e["lat"], e["lon"]) for e in osm["elements"] if e["type"] == "node"}
    ways = [w for w in osm["elements"] if w["type"] == "way" and len(w.get("nodes", [])) >= 2]
    uses = {}
    for w in ways:
        for i, n in enumerate(w["nodes"]):
            end = i in (0, len(w["nodes"]) - 1)
            uses[n] = uses.get(n, 0) + (2 if end else 1)
    junction = {n for n, c in uses.items() if c >= 2}
    edges = {}
    for w in ways:
        hw = w.get("tags", {}).get("highway", "")
        kind = 1 if hw == "steps" else 2 if hw in ROADS else 0
        ids = [n for n in w["nodes"] if n in coords]
        start = 0
        for i in range(1, len(ids)):
            if ids[i] in junction or i == len(ids) - 1:
                seg = ids[start:i + 1]
                a, b = seg[0], seg[-1]
                if a != b:
                    length = sum(metres(coords[x], coords[y]) for x, y in zip(seg, seg[1:]))
                    key = (a, b) if a < b else (b, a)
                    pts = seg[1:-1] if a < b else list(reversed(seg[1:-1]))
                    if key not in edges or length < edges[key][0]:
                        edges[key] = (length, kind, pts)
                start = i
    # the largest connected part
    adj = {}
    for a, b in edges:
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    seen, best = set(), set()
    for n in adj:
        if n in seen:
            continue
        comp, stack = {n}, [n]
        seen.add(n)
        while stack:
            for m in adj[stack.pop()]:
                if m not in seen:
                    seen.add(m)
                    comp.add(m)
                    stack.append(m)
        if len(comp) > len(best):
            best = comp
    ids = sorted(best)
    index = {n: i for i, n in enumerate(ids)}
    out_edges, pairs, off, pts = [], [], [0], []
    for (a, b), (length, kind, mid) in sorted(edges.items()):
        if a not in index or b not in index:
            continue
        ia, ib = index[a], index[b]
        out_edges += [ia, ib, round(length), kind]
        line = simplify([coords[a]] + [coords[n] for n in mid] + [coords[b]])[1:-1]
        if line:
            lo, hi = (ia, ib) if ia < ib else (ib, ia)
            seq = line if ia < ib else list(reversed(line))
            pairs += [lo, hi]
            for la, lo_ in seq:
                pts += [round(la, 5), round(lo_, 5)]
            off.append(len(pts) // 2)
    return {
        "source": "OpenStreetMap ways via the Overpass API (ODbL)",
        "fetched": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "bbox_west_south_east_north": list(BBOX),
        "undirected": True,
        "lat": [round(coords[n][0], 5) for n in ids],
        "lon": [round(coords[n][1], 5) for n in ids],
        "ele": [0] * len(ids),
        "edges": out_edges,
        "shapes": {"pairs": pairs, "off": off, "pts": pts},
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--osm", type=Path, help="a saved Overpass reply instead of fetching")
    args = ap.parse_args()
    osm = json.loads(args.osm.read_text()) if args.osm else fetch()
    graph = build(osm)
    OUT.write_text(json.dumps(graph, separators=(",", ":")))
    print(f"town: {len(graph['lat'])} nodes, {len(graph['edges']) // 4} streets, {len(graph['shapes']['pts']) // 2} bend points", file=sys.stderr)


if __name__ == "__main__":
    main()
