"""Checks on the entry point builder and on the committed data/entry_points.json."""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import build_entry_points as bep  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
NODES = [(37.0000, -122.0600), (37.0010, -122.0600), (37.0010, -122.0590)]
BBOX = (-122.07, 36.99, -122.05, 37.01)


def element(kind, number, lat, lon, **extra):
    base = {"type": kind, "id": number, "tags": {}}
    if kind == "way":
        base["center"] = {"lat": lat, "lon": lon}
    else:
        base.update(lat=lat, lon=lon)
    return {**base, **extra}


def source(**fields):
    return {"id": "stop", "name": "Stop", "type": "bus_stop", "osm": "node/1", **fields}


class TestBuild(unittest.TestCase):
    def test_snaps_to_the_nearest_graph_node(self):
        out = bep.build([source()], [element("node", 1, 37.00095, -122.05995)], NODES, BBOX)
        self.assertEqual(out[0]["node"], 1)
        self.assertLess(out[0]["snap_m"], 10)
        self.assertEqual(out[0]["osm"], "node/1")

    def test_way_uses_its_centre(self):
        out = bep.build([source(osm="way/9", type="parking")], [element("way", 9, 37.0, -122.0599)], NODES, BBOX)
        self.assertEqual((out[0]["lat"], out[0]["lon"]), (37.0, -122.0599))

    def test_missing_element_is_an_error(self):
        with self.assertRaisesRegex(bep.EntryPointError, "was not in"):
            bep.build([source()], [], NODES, BBOX)

    def test_point_far_from_any_path_is_refused(self):
        with self.assertRaisesRegex(bep.EntryPointError, "from the nearest path"):
            bep.build([source()], [element("node", 1, 37.0050, -122.0550)], NODES, BBOX)

    def test_point_outside_the_graph_area_is_refused(self):
        with self.assertRaisesRegex(bep.EntryPointError, "outside"):
            bep.build([source()], [element("node", 1, 36.9, -122.06)], NODES, BBOX)

    def test_unknown_type_and_duplicate_id_are_refused(self):
        found = [element("node", 1, 37.0, -122.06)]
        with self.assertRaisesRegex(bep.EntryPointError, "type must be"):
            bep.build([source(type="helipad")], found, NODES, BBOX)
        with self.assertRaisesRegex(bep.EntryPointError, "twice"):
            bep.build([source(), source()], found, NODES, BBOX)

    def test_references_must_look_like_node_or_way(self):
        for bad in ("relation/1", "node/x", "7"):
            with self.assertRaises(bep.EntryPointError):
                bep.split_ref(bad)


class TestCommittedData(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads((ROOT / "data" / "entry_points.json").read_text(encoding="utf-8"))
        cls.sources = json.loads((ROOT / "data" / "entry_point_sources.json").read_text(encoding="utf-8"))
        cls.nodes, cls.bbox = bep.load_graph(ROOT / "graph" / "ucsc")
        cls.points = cls.data["entry_points"]

    def test_attribution_is_kept(self):
        self.assertIn("OpenStreetMap", self.data["attribution"])
        self.assertIn("ODbL", self.data["attribution"])

    def test_matches_the_reviewed_sources(self):
        reviewed = [(s["id"], s["name"], s["type"], s["osm"]) for s in self.sources["entry_points"]]
        built = [(p["id"], p["name"], p["type"], p["osm"]) for p in self.points]
        self.assertEqual(built, reviewed)

    def test_every_point_sits_on_the_graph(self):
        west, south, east, north = self.bbox
        for p in self.points:
            self.assertTrue(south <= p["lat"] <= north and west <= p["lon"] <= east, p["id"])
            self.assertLessEqual(p["snap_m"], bep.MAX_SNAP_M, p["id"])
            lat, lon = self.nodes[p["node"]]
            self.assertAlmostEqual(bep.haversine_m(p["lat"], p["lon"], lat, lon), p["snap_m"], delta=0.2)
            self.assertEqual(bep.nearest_node(self.nodes, p["lat"], p["lon"])[0], p["node"], p["id"])

    def test_ids_are_unique_and_types_known(self):
        ids = [p["id"] for p in self.points]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertGreater(len(ids), 5)
        self.assertTrue({p["type"] for p in self.points} <= set(bep.TYPES))

    def test_no_transit_schedule_data_is_bundled(self):
        allowed = {"id", "name", "type", "lat", "lon", "node", "snap_m", "osm"}
        for p in self.points:
            self.assertEqual(set(p), allowed)


if __name__ == "__main__":
    unittest.main()
