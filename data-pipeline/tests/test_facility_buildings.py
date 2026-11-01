import json
import unittest
from pathlib import Path

import build_facility_buildings as fb
from room_parser import load_campus, normalize

ROOT = Path(__file__).resolve().parents[2]


def fac(**kw):
    base = {"asset": "1", "name": "Test Hall", "label": "Test", "aliases": [], "departments": [],
            "category": "G - General", "primary_use": "CLS - Classroom", "region": "X",
            "floors": 2, "lat": 36.99, "lon": -122.06}
    return {**base, **kw}


class FacilityRecords(unittest.TestCase):
    def test_generic_labels_are_not_aliases(self):
        new, _ = fb.build([], [fac(name="Kresge College Library", label="Library")])
        self.assertNotIn("Library", new[0]["aliases"])
        self.assertIn("Kresge Lib", new[0]["aliases"])

    def test_lettered_units_get_short_names(self):
        new, _ = fb.build([], [fac(name="Theater Arts C Studio", label="Studio")])
        self.assertIn("Theater Arts C", new[0]["aliases"])

    def test_shared_aliases_are_dropped(self):
        new, _ = fb.build([], [fac(asset="1", name="Alpha Hall", aliases=["Coffee Cart"]),
                               fac(asset="2", name="Beta Hall", aliases=["Coffee Cart"])])
        fb.drop_shared_aliases([], new)
        self.assertTrue(all("Coffee Cart" not in b["aliases"] for b in new))

    def test_offices_and_storage_are_skipped(self):
        new, _ = fb.build([], [fac(primary_use="OFF - Office"), fac(name="Chemical Storage Unit")])
        self.assertEqual(new, [])

    def test_existing_building_is_not_duplicated(self):
        curated = [{"id": "x", "name": "Thimann Labs", "aliases": ["Thimann Laboratories"],
                    "centroid": {"lat": 36.99, "lon": -122.06}}]
        new, report = fb.build(curated, [fac(name="Thimann Laboratories")])
        self.assertEqual(new, [])
        self.assertTrue(report)


class ShippedData(unittest.TestCase):
    def setUp(self):
        self.buildings = json.loads((ROOT / "data" / "buildings.json").read_text())["buildings"]

    def test_ids_unique_and_every_building_is_located(self):
        ids = [b["id"] for b in self.buildings]
        self.assertEqual(len(ids), len(set(ids)))
        for b in self.buildings:
            self.assertTrue(b["centroid"] and b["entrances"], b["id"])

    def test_no_alias_belongs_to_two_buildings(self):
        owners = {}
        for b in self.buildings:
            for a in [b["name"], *b["aliases"]]:
                owners.setdefault(normalize(a), set()).add(b["id"])
        self.assertEqual({k: v for k, v in owners.items() if len(v) > 1}, {})

    def test_rooms_in_departmental_buildings_resolve(self):
        campus = load_campus()
        for text, building in [("Communications 150", "communications-building"),
                               ("Sinsheimer Labs 201", "sinsheimer-laboratories"),
                               ("Theater Arts C 101", "theater-arts-c-studio"),
                               ("Kresge Classroom 327", "kresge-college-classroom-building"),
                               ("Elena Baskin Bldg A 110", "elena-baskin-building-a")]:
            r = campus.resolve(text)
            self.assertEqual((r.kind, r.building_id), ("building", building), text)


if __name__ == "__main__":
    unittest.main()
