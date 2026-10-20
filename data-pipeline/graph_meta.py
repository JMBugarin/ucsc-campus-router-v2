"""Content hashes for the exported graph, kept in meta.json, so a regenerated or hand-edited graph
cannot change routes unnoticed.

Usage (from data-pipeline/), to record the hashes of the files as they are now:
    python graph_meta.py ../graph/ucsc

build_graph.py and fetch_elevation.py do this themselves. Uses only the standard library.
"""

import hashlib
import json
import sys
from pathlib import Path

FILES = ("nodes.csv", "edges.csv")


def fingerprint(graph_dir):
    return {name: hashlib.sha256((Path(graph_dir) / name).read_bytes()).hexdigest() for name in FILES}


def record(graph_dir, **fields):
    """Write the files' current hashes, and any other fields given, into meta.json."""
    path = Path(graph_dir) / "meta.json"
    meta = json.loads(path.read_text())
    meta.update(fields)
    meta["sha256"] = fingerprint(graph_dir)
    path.write_text(json.dumps(meta, indent=2) + "\n")
    return meta


if __name__ == "__main__":
    record(sys.argv[1] if len(sys.argv) > 1 else "../graph/ucsc")
