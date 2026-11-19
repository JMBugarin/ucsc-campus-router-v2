import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fetch_housing import outline_points, parse  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SQUARE = [[-122.0601, 37.0001], [-122.0599, 37.0001], [-122.0599, 36.9999], [-122.0601, 36.9999], [-122.0601, 37.0001]]


def feature(name, region, use="RES - Residential", alias=None, label=None, category="R - Residential", hide=0):
    return {"attributes": {"BUILDINGNAME": name, "REGION": region, "PRIMARYUSE": use, "ALIAS": alias,
                           "LABELNAME": label, "CATEGORY": category, "HIDE": hide, "ASSETNUM": 7000},
            "geometry": {"rings": [SQUARE]}}


class ParseTest(unittest.TestCase):
    def test_keeps_where_students_live(self):
        rows = parse([
            feature("College Nine Apartment Building 2", "College Nine", label="A2"),
            feature("Crown College House", "Crown College", alias="Crown College Provost House"),
            feature("Cowell College Garage", "Cowell College", use="GEN - General Use"),
            feature("College Nine Residence Hall Lounge", "College Nine", use="SUP - Support"),
            feature("Farm Apprentice Cabin 1", "Agroecology"),
            feature("Kresge Residence Hall A", "Kresge College", use=None),
            feature("Hidden Hall", "Cowell College", hide=1),
        ])
        self.assertEqual([r["name"] for r in rows], ["College Nine Apartment Building 2", "Kresge Residence Hall A"])

    def test_names_students_type(self):
        rows = {r["name"]: r for r in parse([
            feature("College Nine Apartment Building 2", "College Nine", label="A2"),
            feature("Crown College Galileo House", "Crown College", label="Galileo"),
            feature("Stevenson College House 1", "Stevenson College", label="Primera"),
            feature("Merrill College House D", "Merrill College", label="D"),
            feature("Rachel Carson College Dorm A-L-Building", "Rachel Carson College", label="Dorm A"),
            feature("College Nine Residence Hall 1", "College Nine", alias="Res Hall 1, Hague House", label="R1"),
        ])}
        self.assertIn("C9 Apt 2", rows["College Nine Apartment Building 2"]["aliases"])
        self.assertIn("College 9 Apartment Building 2", rows["College Nine Apartment Building 2"]["aliases"])
        self.assertNotIn("Apartment Building 2", rows["College Nine Apartment Building 2"]["aliases"])
        self.assertTrue({"Galileo", "Crown Galileo"} <= set(rows["Crown College Galileo House"]["aliases"]))
        self.assertTrue({"Casa Primera", "Stevenson House 1"} <= set(rows["Stevenson College House 1"]["aliases"]))
        self.assertTrue({"DuBois", "Merrill D"} <= set(rows["Merrill College House D"]["aliases"]))
        self.assertIn("RCC A Building", rows["Rachel Carson College Dorm A-L-Building"]["aliases"])
        self.assertIn("Hague House", rows["College Nine Residence Hall 1"]["aliases"])
        self.assertNotIn("Res Hall 1", rows["College Nine Residence Hall 1"]["aliases"])
        self.assertEqual(rows["College Nine Apartment Building 2"]["area"], "College Nine")
        self.assertEqual(rows["College Nine Apartment Building 2"]["id"], "college-nine-apartment-building-2")

    def test_outline_points_are_the_building_extremes(self):
        pts = outline_points([tuple(p) for p in SQUARE])
        self.assertTrue(2 <= len(pts) <= 4)
        for lat, lon in pts:
            self.assertTrue(36.9999 <= lat <= 37.0001 and -122.0601 <= lon <= -122.0599)


class CommittedDataTest(unittest.TestCase):
    def test_housing_file_is_complete(self):
        data = json.loads((ROOT / "data" / "housing.json").read_text(encoding="utf-8"))
        rows = data["buildings"]
        self.assertGreater(len(rows), 150)
        self.assertEqual(len({r["id"] for r in rows}), len(rows))
        names = {r["name"] for r in rows}
        for must in ["College Nine Apartment Building 2", "Crown College Galileo House", "Stevenson College House 1",
                     "Rachel Carson College Dorm A-L-Building", "Kresge Residence Hall A", "Village Housing B1"]:
            self.assertIn(must, names)
        for r in rows:
            self.assertTrue(36.97 < r["lat"] < 37.01 and -122.075 < r["lon"] < -122.04, r["name"])
            self.assertTrue(1 <= len(r["approach"]) <= 4, r["name"])


if __name__ == "__main__":
    unittest.main()
