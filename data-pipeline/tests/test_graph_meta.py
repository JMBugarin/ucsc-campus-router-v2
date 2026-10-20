"""graph_meta records content hashes in meta.json (no network is used)."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import graph_meta  # noqa: E402


class TestGraphMeta(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        (self.dir / "nodes.csv").write_text("id,osm_id,lat,lon,elev_m\n0,1,36.9,-122.0,100.0\n")
        (self.dir / "edges.csv").write_text("from,to,length_m,is_stairs,highway\n0,0,1.00,0,path\n")
        (self.dir / "meta.json").write_text(json.dumps({"nodes": 1, "edges": 1, "source": "test"}))

    def meta(self):
        return json.loads((self.dir / "meta.json").read_text())

    def test_recording_adds_hashes_and_keeps_the_other_fields(self):
        graph_meta.record(self.dir, elevation_source="somewhere")
        meta = self.meta()
        self.assertEqual((meta["nodes"], meta["edges"], meta["source"]), (1, 1, "test"))
        self.assertEqual(meta["elevation_source"], "somewhere")
        self.assertEqual(set(meta["sha256"]), {"nodes.csv", "edges.csv"})
        self.assertTrue(all(len(h) == 64 for h in meta["sha256"].values()))

    def test_recording_twice_changes_nothing(self):
        graph_meta.record(self.dir)
        first = (self.dir / "meta.json").read_text()
        graph_meta.record(self.dir)
        self.assertEqual((self.dir / "meta.json").read_text(), first)

    def test_a_changed_file_changes_its_hash_only(self):
        before = graph_meta.fingerprint(self.dir)
        (self.dir / "nodes.csv").write_text("id,osm_id,lat,lon,elev_m\n0,1,36.9,-122.0,100.1\n")
        after = graph_meta.fingerprint(self.dir)
        self.assertNotEqual(before["nodes.csv"], after["nodes.csv"])
        self.assertEqual(before["edges.csv"], after["edges.csv"])


if __name__ == "__main__":
    unittest.main()
