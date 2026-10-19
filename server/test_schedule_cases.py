"""Runs testdata/schedule_cases.json, which the Dart app's offline logic is tested against too."""

import json
import sys
import unittest
from datetime import date, datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "data-pipeline"))

import timetable as sch  # noqa: E402

DATA = json.loads((HERE / "testdata" / "schedule_cases.json").read_text(encoding="utf-8"))


class TestSharedScheduleCases(unittest.TestCase):
    def walker(self, origin, destination):
        key = ("*" if origin[0] == "point" else origin[1]) + ">" + destination
        minutes = DATA["walks"].get(key)
        return None if minutes is None else {"meters": (minutes - 0.5) * 78.0, "indoor_m": 0.0}

    def test_cases(self):
        holidays = frozenset(date.fromisoformat(h) for h in DATA["holidays"])
        self.assertGreaterEqual(len(DATA["cases"]), 15)
        for case in DATA["cases"]:
            with self.subTest(case["name"]):
                meetings = [DATA["meetings"][n] for n in case["meetings"]]
                here = tuple(DATA["here"]) if case["here"] else None
                r = sch.analyze(meetings, datetime.fromisoformat(case["now"]), holidays, self.walker, here)
                got = {
                    "state": r["state"], "reason": r["reason"],
                    "current_start": r["current"]["start"] if r["current"] else None,
                    "next_start": r["next"]["start"] if r["next"] else None,
                    "next_is_today": r["next"]["is_today"] if r["next"] else None,
                    "starts_in_min": r["next"]["starts_in_min"] if r["next"] else None,
                    "today_starts": [x["start"] for x in r["today"]],
                    "walk_minutes": r["walk"]["minutes"] if r["walk"] else None,
                    "walk_from": r["walk"]["from"] if r["walk"] else None,
                    "free_min": r["free_min"], "status": r["status"], "leave_by": r["leave_by"],
                    "transitions": [{"walk_min": x.get("walk_min"), "free_min": x.get("free_min"),
                                     "status": x.get("status")} for x in r["today"][1:]],
                }
                self.assertEqual(got, case["expect"])


if __name__ == "__main__":
    unittest.main()
