"""Download UCSC's walkable street network from OpenStreetMap and export it as CSV.

Usage (from data-pipeline/):
    python build_graph.py --out ../graph/ucsc

Outputs, in the --out directory:
    nodes.csv  id,osm_id,lat,lon,elev_m
    edges.csv  from,to,length_m,is_stairs,highway
    meta.json  bounding box and counts

Node ids are renumbered 0..N-1 (sorted by OSM id, so output is deterministic)
so the C engine can index plain arrays. Edges are directed; a walkable street
appears once in each direction. elev_m is left empty until the elevation phase.
"""

import argparse
import csv
import json
from pathlib import Path

import osmnx as ox

# Core UCSC campus plus a small margin: (west, south, east, north).
DEFAULT_BBOX = (-122.0700, 36.9860, -122.0460, 37.0030)


def fetch_graph(bbox):
    ox.settings.cache_folder = str(Path(__file__).parent / "cache")
    graph = ox.graph_from_bbox(bbox, network_type="walk", simplify=True)
    # Keep only the part of the network where every node can reach every other,
    # so routing never fails because a start/end landed on an isolated fragment.
    return ox.truncate.largest_component(graph, strongly=True)


def highway_tags(value):
    """osmnx stores 'highway' as a str, or a list when simplification merged ways."""
    return sorted(value) if isinstance(value, list) else [value]


def export(graph, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)

    osm_ids = sorted(graph.nodes)
    new_id = {osm: i for i, osm in enumerate(osm_ids)}

    with open(out_dir / "nodes.csv", "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["id", "osm_id", "lat", "lon", "elev_m"])
        for osm in osm_ids:
            data = graph.nodes[osm]
            w.writerow([new_id[osm], osm, f"{data['y']:.7f}", f"{data['x']:.7f}", ""])

    # osmnx can return parallel edges between the same pair of nodes. The
    # router only needs the shortest one, so keep a single edge per (u, v).
    best = {}
    for u, v, data in graph.edges(data=True):
        if u == v:
            continue
        key = (new_id[u], new_id[v])
        length = float(data["length"])
        if key not in best or length < best[key][0]:
            tags = highway_tags(data.get("highway", ""))
            best[key] = (length, "steps" in tags, "|".join(tags))

    with open(out_dir / "edges.csv", "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["from", "to", "length_m", "is_stairs", "highway"])
        for (u, v), (length, stairs, hw) in sorted(best.items()):
            w.writerow([u, v, f"{length:.2f}", int(stairs), hw])

    return len(osm_ids), len(best)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", type=Path, default=Path("../graph/ucsc"))
    ap.add_argument(
        "--bbox",
        type=float,
        nargs=4,
        metavar=("WEST", "SOUTH", "EAST", "NORTH"),
        default=DEFAULT_BBOX,
    )
    args = ap.parse_args()

    graph = fetch_graph(tuple(args.bbox))
    n_nodes, n_edges = export(graph, args.out)

    meta = {
        "bbox_west_south_east_north": list(args.bbox),
        "nodes": n_nodes,
        "edges": n_edges,
        "source": "OpenStreetMap via osmnx",
    }
    (args.out / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"Wrote {n_nodes} nodes and {n_edges} edges to {args.out}")


if __name__ == "__main__":
    main()
