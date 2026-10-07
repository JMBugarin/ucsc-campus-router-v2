"""Tests for the demo server (run from the repo root: python3 -m unittest discover -s server)."""

import base64
import json
import os
import threading
import unittest
import urllib.error
import urllib.request
from unittest import mock
from pathlib import Path

import server as srv

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "engine" / "route"
GRAPH = ROOT / "graph" / "ucsc"
BBOX = (-122.0700, 36.9860, -122.0460, 37.0030)
# These suites send many requests from one address; the limits themselves are tested in test_hosting.py.
NO_LIMITS = {"general": (100_000, 60), "heavy": (100_000, 60)}

# Two real points on campus (near Baskin Engineering and McHenry Library area).
START, END = "36.9995,-122.0630", "36.9915,-122.0525"


class TestHelpers(unittest.TestCase):
    def test_parse_point_ok(self):
        self.assertEqual(srv.parse_point("36.99,-122.06", BBOX), (36.99, -122.06))

    def test_parse_point_rejects_garbage(self):
        for bad in ("", "abc", "1,2,3", "36.99", "nan,nan", "inf,-122.06"):
            with self.subTest(bad), self.assertRaises(srv.BadRequest):
                srv.parse_point(bad, BBOX)

    def test_parse_point_rejects_far_away(self):
        with self.assertRaises(srv.BadRequest):
            srv.parse_point("37.77,-122.41", BBOX)  # San Francisco

    def test_static_path_blocks_traversal(self):
        web = ROOT / "web"
        self.assertIsNone(srv.safe_static_path(web, "/../server/server.py"))
        self.assertIsNone(srv.safe_static_path(web, "/%2e%2e/README.md"))
        self.assertIsNone(srv.safe_static_path(web, "/does-not-exist.js"))


@unittest.skipUnless(ENGINE.exists(), "engine not built: make -C engine route")
class TestApi(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = srv.make_server("127.0.0.1", 0, ENGINE, GRAPH, ROOT / "web", limits=NO_LIMITS)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def get(self, path):
        try:
            with urllib.request.urlopen(self.base + path, timeout=15) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_meta(self):
        status, body = self.get("/api/meta")
        self.assertEqual(status, 200)
        self.assertGreater(body["nodes"], 1000)
        self.assertEqual(body["term"]["start"], "2026-09-24")

    def test_rooms_list_for_autocomplete(self):
        status, body = self.get("/api/rooms")
        self.assertEqual(status, 200)
        self.assertEqual(len(body["rooms"]), 87)
        self.assertIn("Kresge Acad 3201", body["rooms"])

    def test_route_returns_both_algorithms_with_same_distance(self):
        status, body = self.get(f"/api/route?start={START}&end={END}")
        self.assertEqual(status, 200)
        d, a = body["dijkstra"], body["astar"]
        self.assertTrue(d["found"] and a["found"])
        self.assertAlmostEqual(d["distance_m"], a["distance_m"], places=1)
        self.assertEqual(len(d["explored"]), d["nodes_explored"])
        self.assertEqual(len(a["explored"]), a["nodes_explored"])
        self.assertLess(a["nodes_explored"], d["nodes_explored"])
        self.assertGreater(len(a["path"]), 2)

    def test_route_validation(self):
        self.assertEqual(self.get(f"/api/route?start={START}")[0], 400)
        self.assertEqual(self.get("/api/route?start=1,2&end=3,4")[0], 400)
        self.assertEqual(self.get(f"/api/route?start=abc&end={END}")[0], 400)

    def test_resolve(self):
        status, body = self.get("/api/resolve?q=Baskin+Engr+152")
        self.assertEqual((status, body["kind"], body["building_id"], body["room"]),
                         (200, "building", "baskin-engineering", "152"))
        self.assertGreaterEqual(len(body["entrances"]), 1)
        self.assertEqual(self.get("/api/resolve?q=Online")[1]["kind"], "online")

    def test_route_to_room_from_a_location(self):
        # Start near the Science Hill bus stop area, go to a room in Kresge (a building
        # that has several doors), as a student walking to class would.
        status, body = self.get(f"/api/route_to_room?start={START}&room=Kresge+Acad+3201")
        self.assertEqual(status, 200)
        room = body["room"]
        self.assertEqual((room["building_id"], room["room"]), ("kresge-academic", "3201"))
        doors = [(e["lat"], e["lon"]) for e in
                 self.get("/api/resolve?q=Kresge+Acad+3201")[1]["entrances"]]
        self.assertIn((room["entrance"]["lat"], room["entrance"]["lon"]), doors)
        d, a = body["dijkstra"], body["astar"]
        self.assertTrue(d["found"] and a["found"])
        self.assertAlmostEqual(d["distance_m"], a["distance_m"], places=1)
        self.assertAlmostEqual(room["walk_m"], a["distance_m"], delta=1.0)
        self.assertGreaterEqual(room["indoor_m"], 0)
        self.assertEqual(room["floor"], room["room_point"]["level"])

    def test_route_to_room_can_return_one_light_path(self):
        status, body = self.get(f"/api/route_to_room?start={START}&room=Kresge+Acad+3201&algo=astar&explored=0")
        self.assertEqual(status, 200)
        self.assertEqual(set(body), {"astar", "room"})
        self.assertTrue(body["astar"]["found"])
        self.assertGreater(len(body["astar"]["path"]), 1)
        self.assertNotIn("explored", body["astar"])
        status, full = self.get(f"/api/route_to_room?start={START}&room=Kresge+Acad+3201")
        self.assertIn("explored", full["astar"])
        self.assertEqual(self.get(f"/api/route_to_room?start={START}&room=Kresge+Acad+3201&algo=bogus")[0], 400)

    def test_route_to_room_picks_the_shorter_door(self):
        """A building with many doors: moving the start changes which door is best, and
        the chosen door is never worse than any other door's walk + indoor distance."""
        room_q = "Earth%26Marine+B206"
        status, base = self.get(f"/api/resolve?q={room_q}")
        self.assertEqual(status, 200)
        point = base["room_point"]
        for start in (START, END):
            status, body = self.get(f"/api/route_to_room?start={start}&room={room_q}")
            self.assertEqual(status, 200)
            chosen = body["room"]
            chosen_total = chosen["walk_m"] + chosen["indoor_m"]
            for e in base["entrances"]:
                status, alt = self.get(
                    f"/api/route?start={start}&end={e['lat']},{e['lon']}")
                indoor = srv.distance_m((e["lat"], e["lon"]), (point["lat"], point["lon"]))
                self.assertLessEqual(chosen_total, alt["astar"]["distance_m"] + indoor + 1.0)

    def test_route_to_room_errors(self):
        status, body = self.get(f"/api/route_to_room?start={START}&room=Online")
        self.assertEqual((status, body["kind"]), (422, "online"))
        status, body = self.get(f"/api/route_to_room?start={START}&room=Baskin+Enginering+9")
        self.assertEqual((status, body["kind"]), (422, "unknown"))
        self.assertIn("baskin-engineering", body["candidates"])
        self.assertIn("Jack Baskin Engineering", body["candidate_names"])
        self.assertEqual(self.get(f"/api/route_to_room?start={START}&room=")[0], 400)
        self.assertEqual(self.get("/api/route_to_room?start=1,2&room=Soc+Sci+2+075")[0], 400)

    def post(self, path, payload, raw=None):
        data = raw if raw is not None else json.dumps(payload).encode()
        req = urllib.request.Request(self.base + path, data=data, method="POST",
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_schedule_parse(self):
        text = ("XYZ 10 - Sample Calculus Status Units Grading Grade Deadlines Enrolled 5.00 Graded "
                "10002 01 Lecture MoWeFr 1:20PM - 2:25PM Kresge Acad 3201 A Instructor 09/24/2026 - 12/04/2026 "
                "10003 01 Lecture TuTh 11:40AM - 1:15PM Mystery Hall 9 B Instructor 09/24/2026 - 12/04/2026")
        status, body = self.post("/api/schedule/parse", {"text": text})
        self.assertEqual(status, 200)
        self.assertEqual([m["location"] for m in body["meetings"]], ["Kresge Acad 3201", "Mystery Hall 9"])
        self.assertEqual([loc["kind"] for loc in body["locations"]], ["building", "unknown"])
        self.assertEqual(body["locations"][0]["building_name"], "Kresge College Academic Building")
        self.assertNotIn("Instructor", json.dumps(body))
        self.assertEqual(self.post("/api/schedule/parse", {"text": ""})[0], 400)

    def test_schedule_clean(self):
        good = {"course": "XYZ 10", "days": [0], "start": "08:00", "end": "09:05",
                "location": "Cowell Acad 113", "start_date": "2026-09-24", "end_date": "2026-12-04"}
        status, body = self.post("/api/schedule/clean", {"meetings": [good]})
        self.assertEqual((status, body["meetings"][0]["start"], body["locations"][0]["kind"]),
                         (200, "08:00", "building"))
        self.assertEqual(self.post("/api/schedule/clean", {"meetings": [{**good, "end": "07:00"}]})[0], 400)
        self.assertEqual(self.post("/api/schedule/clean", {"meetings": "nope"})[0], 400)

    def test_today_with_real_walking_times(self):
        meetings = [
            {"course": "A", "days": [0], "start": "14:40", "end": "15:45", "location": "Kresge Acad 3201",
             "start_date": "2026-09-24", "end_date": "2026-12-04"},
            {"course": "B", "days": [0], "start": "16:00", "end": "17:05", "location": "Thim Lecture 003",
             "start_date": "2026-09-24", "end_date": "2026-12-04"},
        ]
        # Monday 12:00 with the student at the Baskin end of campus
        status, r = self.post("/api/today", {"meetings": meetings, "here": [36.9998, -122.0628],
                                              "now": "2026-10-12T12:00:00-07:00"})
        self.assertEqual((status, r["state"], r["next"]["course"]), (200, "before_classes", "A"))
        self.assertGreater(r["walk"]["minutes"], 5)  # Kresge is most of a kilometre away
        self.assertEqual(r["status"], "ok")
        self.assertLess(r["leave_by"], r["next"]["start"])
        self.assertEqual([t["course"] for t in r["today"]], ["A", "B"])
        self.assertIn(r["today"][1]["status"], ("ok", "tight", "late"))
        self.assertEqual(r["today"][1]["gap_min"], 15.0)
        # During class A the walk to B starts from A's room
        status, r = self.post("/api/today", {"meetings": meetings, "now": "2026-10-12T15:00:00-07:00"})
        self.assertEqual((r["state"], r["walk"]["from"]), ("in_class", "current_class"))
        # A weekend has no classes today; the next one is on Monday
        status, r = self.post("/api/today", {"meetings": meetings, "now": "2026-10-10T12:00:00-07:00"})
        self.assertEqual((r["state"], r["reason"], r["next"]["start"][:10]),
                         ("no_classes_today", "weekend", "2026-10-12"))

    def test_today_ignores_a_location_off_campus(self):
        meetings = [{"course": "A", "days": [0], "start": "14:40", "end": "15:45",
                     "location": "Kresge Acad 3201", "start_date": "2026-09-24", "end_date": "2026-12-04"}]
        status, r = self.post("/api/today", {"meetings": meetings, "here": [37.77, -122.41],
                                              "now": "2026-10-12T12:00:00-07:00"})
        self.assertEqual(status, 200)
        self.assertIsNone(r["walk"])
        self.assertTrue(any("outside the mapped campus" in n for n in r["notes"]))

    def test_post_rejects_bad_bodies(self):
        self.assertEqual(self.post("/api/today", None, raw=b"{not json")[0], 400)
        self.assertEqual(self.post("/api/today", None, raw=b"[1, 2]")[0], 400)
        self.assertEqual(self.post("/api/today", {"meetings": [], "now": "tomorrow-ish"})[0], 400)
        self.assertEqual(self.post("/api/schedule/parse", {"text": "x" * 400_000})[0], 400)
        self.assertEqual(self.post("/api/nope", {})[0], 404)

    def test_today_plans_leave_reminders(self):
        meetings = [{"course": "XYZ 10", "days": [0, 2, 4], "start": "14:40", "end": "15:45",
                     "location": "Kresge Acad 3201", "start_date": "2026-09-24", "end_date": "2026-12-04"}]
        ask = {"meetings": meetings, "here": [36.9998, -122.0628], "now": "2026-10-12T14:00:00-07:00",
               "remind_lead": 5, "reminded": []}
        status, plan = self.post("/api/today", ask)
        self.assertEqual(status, 200)
        heads_up, leave = plan["reminders"]
        self.assertEqual((heads_up["stage"], leave["stage"]), ("heads-up", "leave"))
        self.assertEqual(leave["in_seconds"] - heads_up["in_seconds"], 300)       # the lead is 5 minutes
        self.assertIn("Kresge Acad 3201", leave["body"])
        self.assertIsNone(plan["banner"])
        # reminders already shown are not planned again
        _, again = self.post("/api/today", {**ask, "reminded": [heads_up["key"]]})
        self.assertEqual([r["stage"] for r in again["reminders"]], ["leave"])
        # without the setting, no reminder fields at all
        _, plain = self.post("/api/today", {k: v for k, v in ask.items() if k not in ("remind_lead", "reminded")})
        self.assertNotIn("reminders", plain)

    def test_reminder_settings_are_validated(self):
        base = {"meetings": [], "now": "2026-10-12T14:00:00-07:00"}
        for bad in ({"remind_lead": -1}, {"remind_lead": 61}, {"remind_lead": "5"}, {"remind_lead": True},
                    {"remind_lead": 5, "reminded": "no"}, {"remind_lead": 5, "reminded": [1]},
                    {"remind_lead": 5, "reminded": ["x" * 81]}, {"remind_lead": 5, "reminded": ["k"] * 101}):
            with self.subTest(str(bad)[:50]):
                self.assertEqual(self.post("/api/today", {**base, **bad})[0], 400)
        self.assertEqual(self.post("/api/today", {**base, "remind_lead": 0})[0], 200)

    def test_schedule_from_a_calendar_file(self):
        text = ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
                "BEGIN:VEVENT\r\nSUMMARY:XYZ 10 - Lecture\r\nLOCATION:Kresge Acad 3201\r\n"
                "DTSTART;TZID=America/Los_Angeles:20260925T144000\r\nDTEND;TZID=America/Los_Angeles:20260925T154500\r\n"
                "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261205T075959Z\r\nEXDATE;TZID=America/Los_Angeles:20261109T144000\r\nEND:VEVENT\r\n"
                "BEGIN:VEVENT\r\nSUMMARY:Daily thing\r\nDTSTART:20261012T100000Z\r\nDTEND:20261012T110000Z\r\nRRULE:FREQ=DAILY\r\nEND:VEVENT\r\n"
                "END:VCALENDAR\r\n")
        status, body = self.post("/api/schedule/ics", {"text": text})
        self.assertEqual(status, 200)
        self.assertEqual(body["source"], "ics")
        (m,) = body["meetings"]
        self.assertEqual((m["course"], m["component"], m["days"], m["skip_dates"]),
                         ("XYZ 10", "Lecture", [0, 2, 4], ["2026-11-09"]))
        self.assertEqual(body["locations"][0]["building_name"], "Kresge College Academic Building")
        self.assertTrue(any("Daily thing" in n for n in body["notes"]))  # the part it can't represent is reported
        # a skipped date survives the round trip through validation
        status, cleaned = self.post("/api/schedule/clean", {"meetings": body["meetings"]})
        self.assertEqual(cleaned["meetings"][0]["skip_dates"], ["2026-11-09"])

    def test_calendar_errors_are_clear(self):
        self.assertEqual(self.post("/api/schedule/ics", {"text": "hello"})[0], 400)
        self.assertEqual(self.post("/api/schedule/ics", {})[0], 400)

    def test_schedule_from_ocr_words(self):
        import ocr_fixtures as fx
        noise = {("room", "20001"): "Cowell Acad 13"}  # a dropped digit, as OCR really does
        words = fx.render(fx.SAMPLE, noise)
        status, body = self.post("/api/schedule/ocr", {"words": words})
        self.assertEqual(status, 200)
        self.assertEqual(body["source"], "ocr")
        self.assertEqual([m["location"] for m in body["meetings"]],
                         ["Cowell Acad 113", "Kresge Acad 3201", "J Baskin Engr 156", "Earth&Marine B206"])
        self.assertTrue(any("Read room 13 as 113" in n for n in body["notes"]))
        self.assertEqual({m["class_nbr"] for m in body["meetings"]}, {""})  # unreliable, so not kept
        self.assertEqual({loc["kind"] for loc in body["locations"]}, {"building"})
        self.assertIn("Cowell Acad 113", body["text"])
        self.assertNotIn("Instructor", json.dumps(body["meetings"]))

    def test_ocr_errors_are_clear(self):
        for payload in ({"words": []}, {"words": [{"text": "just words", "x0": 0, "y0": 0, "x1": 5, "y1": 5}]}):
            status, body = self.post("/api/schedule/ocr", payload)
            self.assertEqual(status, 400)
            self.assertIn("class table", body["error"])
        self.assertEqual(self.post("/api/schedule/ocr", {"words": "no"})[0], 400)
        self.assertEqual(self.post("/api/schedule/ocr", {})[0], 400)

    def test_unknown_api_and_static(self):
        self.assertEqual(self.get("/api/nope")[0], 404)
        with urllib.request.urlopen(self.base + "/", timeout=15) as r:
            self.assertEqual(r.status, 200)
            self.assertIn(b"<html", r.read().lower())
        self.assertEqual(self.get("/..%2fREADME.md")[0], 404)


PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
EXTRACTION = {
    "classes": [
        {"course": "XYZ 10", "title": "", "section": "01", "component": "Lecture", "class_nbr": "",
         "days": ["Mo", "We", "Fr"], "start": "14:40", "end": "15:45", "location": "Kresge Acad 3201",
         "start_date": "2026-09-24", "end_date": "2026-12-04", "status": "Enrolled"},
        {"course": "OLD 1", "title": "", "section": "01", "component": "Lecture", "class_nbr": "",
         "days": ["Tu"], "start": "09:00", "end": "10:00", "location": "Soc Sci 2 075",
         "start_date": "", "end_date": "", "status": "Dropped"},
        {"course": "NEW 2", "title": "", "section": "01", "component": "Lecture", "class_nbr": "",
         "days": ["Th"], "start": "11:00", "end": "12:15", "location": "Nowhere Hall 9",
         "start_date": "", "end_date": "", "status": "Enrolled"},
    ],
    "notes": ["The last row is blurry"],
}


@unittest.skipUnless(ENGINE.exists(), "engine not built: make -C engine route")
class TestPhotoApi(unittest.TestCase):
    """The photo endpoint with a fake reader standing in for the Claude API."""

    @classmethod
    def setUpClass(cls):
        cls.seen = []

        def fake_reader(image, media_type):
            cls.seen.append((image, media_type))
            return EXTRACTION

        cls.httpd = srv.make_server("127.0.0.1", 0, ENGINE, GRAPH, ROOT / "web", photo_reader=fake_reader,
                                    limits=NO_LIMITS)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def post(self, payload):
        req = urllib.request.Request(self.base + "/api/schedule/photo", data=json.dumps(payload).encode(),
                                     method="POST", headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_photo_becomes_validated_meetings(self):
        self.seen.clear()
        data = base64.b64encode(PNG).decode()
        status, body = self.post({"image": data, "media_type": "image/png"})
        self.assertEqual(status, 200)
        self.assertEqual(self.seen, [(PNG, "image/png")])
        self.assertEqual(body["source"], "photo")
        # the dropped course is left out; the room the app doesn't know is kept but flagged
        self.assertEqual([m["course"] for m in body["meetings"]], ["XYZ 10", "NEW 2"])
        self.assertEqual([loc["kind"] for loc in body["locations"]], ["building", "unknown"])
        # a row with no dates takes the term's dates
        self.assertEqual(body["meetings"][1]["start_date"], "2026-09-24")
        text = " ".join(body["notes"])
        self.assertIn("From the photo: The last row is blurry", text)
        self.assertIn("OLD 1 (dropped)", text)

    def test_bad_uploads_are_rejected_before_the_reader_runs(self):
        self.seen.clear()
        good = base64.b64encode(PNG).decode()
        self.assertEqual(self.post({"image": good, "media_type": "application/pdf"})[0], 400)
        self.assertEqual(self.post({"image": "###", "media_type": "image/png"})[0], 400)
        self.assertEqual(self.post({"media_type": "image/png"})[0], 400)
        self.assertEqual(self.post({"image": base64.b64encode(b"hello").decode(), "media_type": "image/png"})[0], 400)
        # An oversized body is refused from its Content-Length, before it is read; the client
        # either gets the 400 or sees the connection close while it is still sending.
        try:
            status = self.post({"image": "A" * (srv.PHOTO_MAX_BODY_BYTES + 10), "media_type": "image/png"})[0]
        except (urllib.error.URLError, ConnectionError):
            status = 400
        self.assertEqual(status, 400)
        self.assertEqual(self.seen, [])

    def test_capabilities_with_a_reader(self):
        with urllib.request.urlopen(self.base + "/api/capabilities", timeout=15) as r:
            caps = json.loads(r.read())
        self.assertTrue(caps["photo"]["ready"])


@unittest.skipUnless(ENGINE.exists(), "engine not built: make -C engine route")
class TestPhotoNotConfigured(unittest.TestCase):
    """With no API key the rest of the app works and the photo option says what is missing."""

    def test_clear_message_when_there_is_no_key(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            for name in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"):
                os.environ.pop(name, None)
            httpd = srv.make_server("127.0.0.1", 0, ENGINE, GRAPH, ROOT / "web", limits=NO_LIMITS)
            base = f"http://127.0.0.1:{httpd.server_address[1]}"
            threading.Thread(target=httpd.serve_forever, daemon=True).start()
            try:
                with urllib.request.urlopen(base + "/api/capabilities", timeout=15) as r:
                    photo_caps = json.loads(r.read())["photo"]
                self.assertFalse(photo_caps["ready"])
                self.assertTrue(photo_caps["reason"])
                req = urllib.request.Request(
                    base + "/api/schedule/photo", method="POST", headers={"Content-Type": "application/json"},
                    data=json.dumps({"image": base64.b64encode(PNG).decode(), "media_type": "image/png"}).encode())
                with self.assertRaises(urllib.error.HTTPError) as ctx:
                    urllib.request.urlopen(req, timeout=15)
                self.assertEqual(ctx.exception.code, 501)
                self.assertIn("error", json.loads(ctx.exception.read()))
            finally:
                httpd.shutdown()
                httpd.server_close()


if __name__ == "__main__":
    unittest.main()
