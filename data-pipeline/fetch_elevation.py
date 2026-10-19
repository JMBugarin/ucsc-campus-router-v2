"""Fill the elev_m column of graph/ucsc/nodes.csv from USGS 3DEP (10 m) elevation data.

Usage (from data-pipeline/):
    python fetch_elevation.py [--graph ../graph/ucsc]

Elevations come from the public OpenTopoData API (dataset ned10m, the USGS National
Elevation Dataset at about 10 m resolution; USGS data is in the public domain). Run it after
build_graph.py, which writes the column empty. Values are in meters, rounded to 0.1 m, and
committed with the graph, so nothing needs the network at serve time.
Uses only the standard library.
"""

import argparse
import csv
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.opentopodata.org/v1/ned10m"
BATCH = 100  # the API's per-request limit
PAUSE_S = 1.1  # and its public rate limit is one request per second
SOURCE = "USGS 3DEP 10 m (ned10m) via OpenTopoData"


def fetch_elevations(points, post=None):
    """Elevation in meters for each (lat, lon). `post` is for tests: post(url, form) -> parsed JSON."""
    post = post or _post
    out = []
    for i in range(0, len(points), BATCH):
        chunk = points[i:i + BATCH]
        locations = "|".join(f"{lat:.7f},{lon:.7f}" for lat, lon in chunk)
        data = post(API, {"locations": locations})
        if data.get("status") != "OK" or len(data["results"]) != len(chunk):
            raise RuntimeError(f"elevation API answered {data.get('status')!r} for batch {i // BATCH}")
        for r in data["results"]:
            if r["elevation"] is None:
                raise RuntimeError(f"no elevation for {r['location']}")
            out.append(round(float(r["elevation"]), 1))
        if i + BATCH < len(points):
            time.sleep(PAUSE_S)
    return out


def _post(url, form):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(form).encode(), method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--graph", type=Path, default=Path("../graph/ucsc"))
    args = ap.parse_args()

    nodes_path = args.graph / "nodes.csv"
    with open(nodes_path, newline="") as f:
        rows = list(csv.reader(f))
    header, body = rows[0], rows[1:]
    points = [(float(r[2]), float(r[3])) for r in body]
    elevations = fetch_elevations(points)
    for row, elev in zip(body, elevations):
        row[4] = f"{elev:.1f}"
    with open(nodes_path, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(body)

    meta_path = args.graph / "meta.json"
    meta = json.loads(meta_path.read_text())
    meta["elevation_source"] = SOURCE
    meta_path.write_text(json.dumps(meta, indent=2) + "\n")
    print(f"Filled {len(body)} nodes ({min(elevations):.1f} to {max(elevations):.1f} m)")


if __name__ == "__main__":
    main()
