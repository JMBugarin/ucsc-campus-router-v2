"""The app's test fixtures (app/test/fixtures) were captured from this server. These tests ask the real
server the same questions and check it still sends every field the fixtures hold, with the same kind of
value, so a server change cannot quietly leave the app's models and tests describing a server that no
longer exists. Fields the server has added since are fine; the deployed server may be older than this
code, which is why the app only ever relies on the fields in the fixtures."""

import json
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

import server as srv

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "engine" / "route"
GRAPH = ROOT / "graph" / "ucsc"
FIXTURES = ROOT / "app" / "test" / "fixtures"
NO_LIMITS = {"general": (100_000, 60), "heavy": (100_000, 60)}

PASTED = ("XYZ 10 - Sample Calculus Status Units Grading Grade Deadlines Enrolled 5.00 Graded "
          "10002 01 Lecture MoWeFr 1:20PM - 2:25PM Kresge Acad 3201 A Instructor 09/24/2026 - 12/04/2026 "
          "10003 01 Lecture TuTh 11:40AM - 1:15PM Mystery Hall 9 B Instructor 09/24/2026 - 12/04/2026")

DAY = {"title": "Sample Calculus", "days": [0], "start_date": "2026-09-24", "end_date": "2026-12-04"}
MONDAY_CLASSES = [
    {**DAY, "course": "XYZ 10", "section": "01A", "component": "Discussion", "start": "08:00", "end": "09:05",
     "location": "Cowell Acad 113"},
    {**DAY, "course": "XYZ 10", "section": "01", "component": "Lecture", "start": "14:40", "end": "15:45",
     "location": "Kresge Acad 3201"},
    {**DAY, "course": "ABC 20", "section": "01", "component": "Lecture", "start": "16:00", "end": "17:05",
     "location": "Thim Lecture 003"},
]


def fixture(name):
    return json.loads((FIXTURES / f"{name}.json").read_text(encoding="utf-8"))


def fetch(base, path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(base + path, data=data, method="GET" if data is None else "POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        with e:
            return e.code, json.loads(e.read())


def differences(want, got, path="$"):
    """Where `got` no longer has what the fixture `want` shows: a field gone, or another kind of value."""
    if want is None or got is None:  # a field that can be empty may be filled, or the other way round
        return []
    if isinstance(want, dict):
        if not isinstance(got, dict):
            return [f"{path} is no longer an object"]
        found = []
        for key, value in want.items():
            if key not in got:
                found.append(f"{path}.{key} is gone")
            else:
                found += differences(value, got[key], f"{path}.{key}")
        return found
    if isinstance(want, list):
        if not isinstance(got, list):
            return [f"{path} is no longer a list"]
        return differences(want[0], got[0], f"{path}[0]") if want and got else []
    if isinstance(want, bool):
        return [] if isinstance(got, bool) else [f"{path} is no longer true/false"]
    if isinstance(want, (int, float)):
        return [] if isinstance(got, (int, float)) and not isinstance(got, bool) else [f"{path} is no longer a number"]
    return [] if isinstance(got, type(want)) else [f"{path} is no longer {type(want).__name__}"]


@unittest.skipUnless(ENGINE.exists(), "engine not built: make -C engine route")
class TestAppFixturesStillMatchTheServer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = srv.make_server("127.0.0.1", 0, ENGINE, GRAPH, ROOT / "web", limits=NO_LIMITS)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def ask(self, path, payload=None):
        return fetch(self.base, path, payload)

    def assert_matches(self, name, live):
        self.assertEqual(differences(fixture(name), live), [], f"app/test/fixtures/{name}.json")

    def test_meta(self):
        self.assert_matches("meta", self.ask("/api/meta")[1])

    def test_reading_a_pasted_schedule(self):
        self.assert_matches("parse", self.ask("/api/schedule/parse", {"text": PASTED})[1])

    def test_checking_classes(self):
        self.assert_matches("clean", self.ask("/api/schedule/clean", {"meetings": MONDAY_CLASSES[1:2]})[1])

    def test_a_route_to_a_room(self):
        status, body = self.ask("/api/route_to?start=36.9998,-122.0628&room=Kresge+Acad+3201&algo=astar&explored=0")
        self.assertEqual(status, 200)
        self.assert_matches("route_to_room", body)

    def test_a_route_to_a_room_that_has_no_walk(self):
        status, body = self.ask("/api/route_to?start=36.9998,-122.0628&room=Online")
        self.assertEqual(status, 422)
        self.assert_matches("route_to_room_online", body)

    def test_the_day_before_a_class(self):
        ask = {"meetings": MONDAY_CLASSES, "here": [36.9998, -122.0628], "now": "2026-10-12T12:00:00-07:00",
               "remind_lead": 5, "reminded": []}
        status, body = self.ask("/api/today", ask)
        self.assertEqual(status, 200)
        self.assert_matches("today_before_class", body)

    def test_a_day_in_class(self):
        ask = {"meetings": MONDAY_CLASSES, "here": [36.9998, -122.0628], "now": "2026-10-12T15:00:00-07:00",
               "remind_lead": 5, "reminded": []}
        status, body = self.ask("/api/today", ask)
        self.assertEqual(status, 200)
        self.assertIsNotNone(body["current"])
        want = fixture("today_in_class")
        self.assertEqual(differences(want["current"], body["current"], "$.current"), [])

    def test_a_weekend(self):
        ask = {"meetings": MONDAY_CLASSES, "now": "2026-10-10T12:00:00-07:00", "remind_lead": 5, "reminded": []}
        status, body = self.ask("/api/today", ask)
        self.assertEqual(status, 200)
        self.assert_matches("today_weekend", body)

    def test_a_rate_limit(self):
        httpd = srv.make_server("127.0.0.1", 0, ENGINE, GRAPH, ROOT / "web", limits={"general": (1, 60), "heavy": (1, 60)})
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        try:
            base = f"http://127.0.0.1:{httpd.server_address[1]}"
            self.assertEqual(fetch(base, "/api/meta")[0], 200)
            status, body = fetch(base, "/api/meta")
            self.assertEqual(status, 429)
            self.assertEqual(differences(fixture("error_rate_limited"), body), [])
        finally:
            httpd.shutdown()
            httpd.server_close()


class TestTheComparison(unittest.TestCase):
    want = {"a": 1, "b": {"c": "x", "d": [{"e": True}]}, "f": None}

    def check(self, got):
        return differences(self.want, {"f": None, **got})

    def test_it_accepts_other_values_extra_fields_and_a_filled_in_empty_one(self):
        self.assertEqual(differences(self.want, {"a": 2.5, "b": {"c": "y", "d": [{"e": False, "extra": 1}]}, "f": 5, "g": 0}), [])
        self.assertEqual(self.check({"a": 1, "b": {"c": "y", "d": []}}), [])

    def test_it_notices_what_the_app_would_miss(self):
        self.assertEqual(self.check({"b": {"c": "y", "d": [{"e": False}]}}), ["$.a is gone"])
        self.assertEqual(self.check({"a": "1", "b": {"c": "y", "d": []}}), ["$.a is no longer a number"])
        self.assertEqual(self.check({"a": True, "b": {"c": "y", "d": []}}), ["$.a is no longer a number"])
        self.assertEqual(self.check({"a": 1, "b": {"c": 3, "d": [{"e": 1}]}}),
                         ["$.b.c is no longer str", "$.b.d[0].e is no longer true/false"])
        self.assertEqual(differences(self.want, [1]), ["$ is no longer an object"])
        self.assertEqual(self.check({"a": 1, "b": {"c": "y", "d": {}}}), ["$.b.d is no longer a list"])

    def test_a_field_the_fixture_shows_empty_must_still_be_sent(self):
        self.assertEqual(differences(self.want, {"a": 1, "b": {"c": "y", "d": []}}), ["$.f is gone"])


if __name__ == "__main__":
    unittest.main()
