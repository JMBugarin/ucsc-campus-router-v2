"""Tests for check_photo.py: no key and no network are used (run: python3 -m unittest discover -s server)."""

import contextlib
import io
import os
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

import check_photo
import photo
import server as srv

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "engine" / "route"
GRAPH = ROOT / "graph" / "ucsc"
NO_LIMITS = {"general": (100_000, 60), "heavy": (100_000, 60)}
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32

TERM = {"start_date": "2026-09-24", "end_date": "2026-12-04"}


def row(course, section, component, days, start, end, location, status="Enrolled"):
    return {"course": course, "title": "", "section": section, "component": component, "class_nbr": "",
            "days": days, "start": start, "end": end, "location": location, "status": status, **TERM}


# What the model should return for the sample picture, in the shape photo.SCHEMA asks for.
RIGHT = {
    "classes": [
        row("XYZ 10", "01A", "Discussion", ["Tu"], "09:00", "09:55", "Soc Sci 2 075"),
        row("XYZ 10", "01", "Lecture", ["Mo", "We", "Fr"], "13:20", "14:25", "Kresge Acad 3201"),
        row("ABC 20", "01", "Lecture", ["Tu", "Th"], "11:40", "13:15", "Earth&Marine B206"),
        row("ABC 20", "01A", "Discussion", ["Th"], "16:00", "17:05", "Humn Lecture Hall"),
        row("DEF 30", "01", "Lecture", ["Mo", "We"], "08:00", "09:05", "J Baskin Engr 156", status="Dropped"),
    ],
    "notes": [],
}


def meetings_like(expected):
    return [dict(m) for m in expected]


class TestCompare(unittest.TestCase):
    def test_the_right_answer_has_no_differences(self):
        self.assertEqual(check_photo.compare(check_photo.EXPECTED, meetings_like(check_photo.EXPECTED)), [])

    def test_a_room_compares_loosely(self):
        got = meetings_like(check_photo.EXPECTED)
        got[2]["location"] = "earth & marine b-206"
        self.assertEqual(check_photo.compare(check_photo.EXPECTED, got), [])

    def test_each_kind_of_difference_is_named(self):
        got = meetings_like(check_photo.EXPECTED)
        by = {(m["course"], m["section"]): m for m in got}
        got.remove(by[("XYZ 10", "01A")])               # a class the picture shows is missing
        by[("XYZ 10", "01")]["start"] = "13:25"         # a wrong time
        by[("ABC 20", "01")]["days"] = [0, 2]           # wrong days
        by[("ABC 20", "01A")]["location"] = "Humn 1"    # a wrong room
        got.append({"course": "DEF 30", "section": "01", "days": [0], "start": "08:00", "end": "09:05",
                    "location": "J Baskin Engr 156"})   # the dropped course came back
        problems = check_photo.compare(check_photo.EXPECTED, got)
        text = "\n".join(problems)
        self.assertIn("missing: XYZ 10 01A", text)
        self.assertIn("XYZ 10 01: start is 13:25, should be 13:20", text)
        self.assertIn("ABC 20 01: days is [0, 2], should be [1, 3]", text)
        self.assertIn("ABC 20 01A: room is 'Humn 1', should be 'Humn Lecture Hall'", text)
        self.assertIn("DEF 30 01", text)
        self.assertEqual(len(problems), 5, text)

    def test_the_sample_in_the_checker_is_what_the_server_makes_of_a_correct_reading(self):
        import timetable
        meetings, _ = timetable.meetings_from_extraction(RIGHT, TERM | {"name": "Fall 2026"})
        self.assertEqual(check_photo.compare(check_photo.EXPECTED, meetings), [])


@unittest.skipUnless(ENGINE.exists(), "engine not built: make -C engine route")
class TestAgainstAServer(unittest.TestCase):
    def serve(self, reader):
        httpd = srv.make_server("127.0.0.1", 0, ENGINE, GRAPH, ROOT / "web", photo_reader=reader, limits=NO_LIMITS)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        self.addCleanup(httpd.server_close)
        self.addCleanup(httpd.shutdown)
        return f"http://127.0.0.1:{httpd.server_address[1]}"

    def run_check(self, base, *extra):
        def draw(path):
            Path(path).write_bytes(PNG)

        out = io.StringIO()
        with mock.patch.object(check_photo, "draw_sample", draw), contextlib.redirect_stdout(out):
            status = check_photo.main(["--server", base, *extra])
        return status, out.getvalue()

    def test_a_correct_reading_passes(self):
        status, text = self.run_check(self.serve(lambda image, media_type: RIGHT))
        self.assertEqual(status, 0, text)
        self.assertIn("OK: all 4 classes match", text)
        self.assertIn("XYZ 10", text)

    def test_a_wrong_reading_is_reported(self):
        wrong = {"classes": [dict(c) for c in RIGHT["classes"]], "notes": []}
        wrong["classes"][1]["start"] = "14:20"
        status, text = self.run_check(self.serve(lambda image, media_type: wrong))
        self.assertEqual(status, 1, text)
        self.assertIn("start is 14:20, should be 13:20", text)

    def test_a_picture_of_your_own_is_listed_for_you_to_check(self):
        base = self.serve(lambda image, media_type: RIGHT)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "mine.png"
            path.write_bytes(PNG)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                status = check_photo.main(["--server", base, str(path)])
        self.assertEqual(status, 0)
        self.assertIn("Compare the list above with your picture", out.getvalue())

    def test_a_server_that_cannot_read_photos_says_why(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            for name in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"):
                os.environ.pop(name, None)
            base = self.serve(None)
            status, text = self.run_check(base)
        self.assertEqual(status, 2, text)
        self.assertIn("can't read photos", text)

    def test_a_failure_while_reading_is_shown(self):
        def broken(image, media_type):
            raise photo.PhotoError(503, "The photo reader is unavailable: out of credit.")

        status, text = self.run_check(self.serve(broken))
        self.assertEqual(status, 3, text)
        self.assertIn("503", text)
        self.assertIn("out of credit", text)

    def test_no_server_at_all(self):
        status, text = self.run_check("http://127.0.0.1:1")
        self.assertEqual(status, 3, text)
        self.assertIn("Couldn't reach", text)


if __name__ == "__main__":
    unittest.main()
