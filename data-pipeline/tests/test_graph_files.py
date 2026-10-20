"""Sanity checks on the exported graph files (run: python -m unittest discover tests)."""

import csv
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import graph_meta  # noqa: E402

GRAPH_DIR = Path(__file__).resolve().parents[2] / "graph" / "ucsc"


def read(name):
    with open(GRAPH_DIR / name, newline="") as f:
        return list(csv.DictReader(f))


class TestGraphFiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.nodes = read("nodes.csv")
        cls.edges = read("edges.csv")

    def test_node_ids_are_contiguous(self):
        self.assertGreater(len(self.nodes), 0)
        self.assertEqual([int(n["id"]) for n in self.nodes], list(range(len(self.nodes))))

    def test_nodes_inside_campus_area(self):
        for n in self.nodes:
            self.assertTrue(36.98 < float(n["lat"]) < 37.01)
            self.assertTrue(-122.08 < float(n["lon"]) < -122.04)

    def test_edges_reference_valid_nodes(self):
        count = len(self.nodes)
        for e in self.edges:
            self.assertTrue(0 <= int(e["from"]) < count)
            self.assertTrue(0 <= int(e["to"]) < count)
            self.assertNotEqual(e["from"], e["to"])

    def test_edge_lengths_positive(self):
        for e in self.edges:
            self.assertGreater(float(e["length_m"]), 0)

    def test_every_node_has_a_plausible_elevation(self):
        for n in self.nodes:
            self.assertNotEqual(n["elev_m"], "", n["id"])
            self.assertTrue(50 < float(n["elev_m"]) < 400, n["id"])

    def test_grades_are_mostly_walkable(self):
        elev = [float(n["elev_m"]) for n in self.nodes]
        steep = sum(abs(elev[int(e["to"])] - elev[int(e["from"])]) / float(e["length_m"]) > 0.3 for e in self.edges)
        self.assertLess(steep / len(self.edges), 0.02)

    def test_stairs_flag_is_boolean(self):
        for e in self.edges:
            self.assertIn(e["is_stairs"], ("0", "1"))

    def test_the_recorded_hashes_match_the_files(self):
        meta = json.loads((GRAPH_DIR / "meta.json").read_text())
        self.assertEqual(
            meta["sha256"], graph_meta.fingerprint(GRAPH_DIR),
            "the graph changed without meta.json saying so; if that was on purpose, run "
            "`python graph_meta.py ../graph/ucsc` from data-pipeline/ and commit the new hashes",
        )
        self.assertTrue(meta["downloaded"])
        self.assertEqual((meta["nodes"], meta["edges"]), (len(self.nodes), len(self.edges)))

    def test_every_edge_has_a_reverse(self):
        pairs = {(e["from"], e["to"]) for e in self.edges}
        for u, v in pairs:
            self.assertIn((v, u), pairs)


if __name__ == "__main__":
    unittest.main()
