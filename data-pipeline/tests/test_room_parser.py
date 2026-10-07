"""Tests for room_parser and the generated data files (run: python -m unittest discover tests)."""

import csv
import json
import math
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from build_graph import DEFAULT_BBOX  # noqa: E402
from room_parser import Campus, load_campus, normalize  # noqa: E402

DATA = HERE.parents[1] / "data"
BBOX_WEST, BBOX_SOUTH, BBOX_EAST, BBOX_NORTH = DEFAULT_BBOX


class TestResolve(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.campus = load_campus()

    def test_shared_cases(self):
        cases = json.loads((HERE / "room_cases.json").read_text(encoding="utf-8"))
        for case in cases:
            with self.subTest(case["input"]):
                r = self.campus.resolve(case["input"])
                self.assertEqual(r.kind, case["kind"])
                if case["kind"] == "building":
                    self.assertEqual(r.building_id, case["building"])
                    self.assertEqual(r.room, case["room"])
                    if not self.campus.buildings[case["building"]].get("needs_location"):
                        self.assertGreaterEqual(len(r.entrances), 1)
                else:
                    self.assertEqual(r.entrances, [])

    def test_every_official_classroom_name_resolves(self):
        """All 87 display names from classrooms.ucsc.edu must map to a known building and room."""
        rooms = json.loads((DATA / "classrooms.json").read_text(encoding="utf-8"))["rooms"]
        self.assertGreater(len(rooms), 80)
        for room in rooms:
            with self.subTest(room["ais_display_name"]):
                r = self.campus.resolve(room["ais_display_name"])
                self.assertEqual(r.kind, "building")
                # facility ids like "6A 3201" end in the room number
                self.assertEqual(r.room, room["facility_id"].split()[-1].upper())
                self.assertTrue(r.room_known)
                self.assertIn(room["facility_id"].split()[0],
                              self.campus.buildings[r.building_id]["facility_ids"])

    def test_room_gets_its_own_point_and_level(self):
        r = self.campus.resolve("Kresge Acad 3201")
        self.assertEqual(r.kind, "building")
        self.assertGreaterEqual(len(r.entrances), 1)
        self.assertAlmostEqual(r.room_point["lat"], 36.99891, places=3)
        self.assertEqual(r.floor, r.room_point["level"])  # e.g. "L2"

    def test_building_without_any_location_still_resolves(self):
        door = {"lat": 37.0, "lon": -122.06, "kind": "door", "source": "osm"}
        campus = Campus([
            {"id": "x", "name": "X Hall", "aliases": ["X"], "needs_location": True, "entrances": []},
            {"id": "y", "name": "Y Hall", "aliases": ["Y"], "entrances": [door]},
        ])
        r = campus.resolve("X 101")
        self.assertEqual((r.kind, r.building_id, r.room, r.entrances), ("building", "x", "101", []))
        self.assertIsNone(r.room_point)

    def test_unknown_room_in_known_building_is_flagged(self):
        self.assertFalse(self.campus.resolve("J Baskin Engr 999").room_known)

    def test_split_location_from_trailing_words(self):
        cases = {
            "Cowell Acad 113 To be Announced": ("Cowell Acad 113", "To be Announced"),
            "Earth&Marine B206 Jane Q Public": ("Earth&Marine B206", "Jane Q Public"),
            "Soc Sci 2 075 Jane Doe": ("Soc Sci 2 075", "Jane Doe"),
            "J Baskin Engr 156 To be Announced": ("J Baskin Engr 156", "To be Announced"),
            "Humn Lecture Hall Some Name": ("Humn Lecture Hall", "Some Name"),
            "TBA To be Announced": ("TBA", "To be Announced"),
            "Online Jane Doe": ("Online", "Jane Doe"),
            "Mystery Hall 12 Bob Smith": ("Mystery Hall 12", "Bob Smith"),
            "McHenry Lib 1340": ("McHenry Lib 1340", ""),
        }
        for text, expected in cases.items():
            with self.subTest(text):
                self.assertEqual(self.campus.split_location(text), expected)

    def test_correct_room_repairs_a_single_character_misread(self):
        fixed, note = self.campus.correct_room("Cowell Acad 13")  # a dropped digit: 113
        self.assertEqual(fixed, "Cowell Acad 113")
        self.assertIn("113", note)
        self.assertEqual(self.campus.correct_room("Soc Sci 2 75")[0], "Soc Sci 2 075")  # 075
        self.assertEqual(self.campus.correct_room("Humn Lecture Hall"), ("Humn Lecture Hall", None))

    def test_correct_room_never_guesses(self):
        unchanged = [
            "Kresge Acad 3201",       # already a real room
            "Cowell Acad 999",        # nothing close
            "Earth&Marine B20",       # one edit from both B206 and B210: ambiguous
            "Mystery Hall 12",        # unknown building
            "Online", "TBA", "McHenry Library",
        ]
        for text in unchanged:
            with self.subTest(text):
                self.assertEqual(self.campus.correct_room(text), (text, None))

    def test_one_edit_apart(self):
        from room_parser import _one_edit_apart as close
        self.assertTrue(close("113", "13") and close("13", "113"))   # one dropped
        self.assertTrue(close("B206", "B208"))                          # one changed
        self.assertFalse(close("113", "113"))                           # the same
        self.assertFalse(close("113", "3"))                             # two apart
        self.assertFalse(close("113", "331"))

    def test_unknown_gets_suggestions(self):
        r = self.campus.resolve("Baskin Enginering 152")  # typo
        self.assertEqual(r.kind, "unknown")
        self.assertIn("baskin-engineering", r.candidates)

    def test_normalize(self):
        self.assertEqual(normalize("  Earth&Mar Sci  A108 "), "earth and mar sci a108")
        self.assertEqual(normalize("Hum. Lecture-Hall"), "hum lecture hall")


class TestOverridesAndAliases(unittest.TestCase):
    def setUp(self):
        door = {"lat": 37.0, "lon": -122.06, "kind": "door", "source": "osm"}
        self.buildings = [
            {"id": "a", "name": "Alpha Hall", "aliases": ["Alpha"], "entrances": [door, door]},
            {"id": "b", "name": "Beta Hall", "aliases": ["Beta"], "entrances": [door]},
        ]

    def test_room_override_pins_entrance(self):
        pinned = {"lat": 37.001, "lon": -122.061}
        campus = Campus(self.buildings, {"a:101": {"entrance": pinned, "floor": "1", "note": "north door"}})
        r = campus.resolve("Alpha 101")
        self.assertEqual(r.entrances, [pinned])
        self.assertEqual((r.floor, r.note), ("1", "north door"))
        self.assertEqual(len(campus.resolve("Alpha 102").entrances), 2)  # no override

    def test_alias_collision_is_rejected(self):
        self.buildings[1]["aliases"].append("alpha")
        with self.assertRaises(ValueError):
            Campus(self.buildings)


class TestDataFiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.buildings = json.loads((DATA / "buildings.json").read_text(encoding="utf-8"))["buildings"]
        cls.sources = json.loads((DATA / "building_sources.json").read_text(encoding="utf-8"))["buildings"]

    def test_generated_file_matches_sources(self):
        """Fails if building_sources.json was edited without re-running build_buildings.py."""
        self.assertEqual([b["id"] for b in self.buildings], [s["id"] for s in self.sources])
        for built, src in zip(self.buildings, self.sources):
            self.assertTrue(set(src["aliases"]) <= set(built["aliases"]), built["id"])

    def test_every_room_is_near_an_entrance_of_its_building(self):
        """Independent check on the OSM matching: the campus map's room points must sit
        close to the entrances we chose for that building (checked 53 m at most)."""
        def meters(a, b):
            dy = (a[0] - b[0]) * 111_195
            dx = (a[1] - b[1]) * 111_195 * math.cos(math.radians(a[0]))
            return math.hypot(dx, dy)

        checked = 0
        for b in self.buildings:
            for room, p in b.get("room_points", {}).items():
                nearest = min(meters((p["lat"], p["lon"]), (e["lat"], e["lon"])) for e in b["entrances"])
                self.assertLess(nearest, 80, f"{b['id']} {room}")
                checked += 1
        self.assertGreaterEqual(checked, 80)

    def test_all_directory_buildings_are_located(self):
        pending = [b["id"] for b in self.buildings if b.get("needs_location")]
        self.assertEqual(pending, [])

    def test_ids_unique_and_entrances_present(self):
        ids = [b["id"] for b in self.buildings]
        self.assertEqual(len(ids), len(set(ids)))
        for b in self.buildings:
            if b.get("needs_location"):
                self.assertEqual(b["entrances"], [], b["id"])
            else:
                self.assertGreaterEqual(len(b["entrances"]), 1, b["id"])

    def test_coordinates_inside_campus_area(self):
        for b in self.buildings:
            if b.get("needs_location"):
                continue
            for p in [b["centroid"], *b["entrances"]]:
                self.assertTrue(BBOX_SOUTH < p["lat"] < BBOX_NORTH, b["id"])
                self.assertTrue(BBOX_WEST < p["lon"] < BBOX_EAST, b["id"])

    def test_entrances_are_near_a_walkway(self):
        """Routing snaps an entrance to the nearest graph node, so it must not be far."""
        with open(DATA.parent / "graph" / "ucsc" / "nodes.csv", newline="") as f:
            nodes = [(float(r["lat"]), float(r["lon"])) for r in csv.DictReader(f)]

        def meters(a, b):
            dy = (a[0] - b[0]) * 111_195
            dx = (a[1] - b[1]) * 111_195 * math.cos(math.radians(a[0]))
            return math.hypot(dx, dy)

        for b in self.buildings:
            if b.get("needs_location"):
                continue
            # At least one entrance per building must be a short walk from a path.
            best = min(min(meters((e["lat"], e["lon"]), n) for n in nodes) for e in b["entrances"])
            self.assertLess(best, 30, b["id"])  # nodes are sparse; see the README known gaps

    def test_no_alias_collisions(self):
        load_campus()  # raises ValueError on a collision


if __name__ == "__main__":
    unittest.main()
