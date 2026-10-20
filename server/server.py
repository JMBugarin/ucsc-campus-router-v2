"""Local web server for the campus router demo.

Serves web/ and exposes the C engine (engine/route) as a small JSON API.
Standard library only; run it where the engine binary was built (Linux/WSL):

    make -C engine route
    python3 server/server.py            # then open http://127.0.0.1:8000

API
    GET /api/meta                          graph size and the covered area
    GET /api/route?start=LAT,LON&end=LAT,LON
                                           Dijkstra and A* results for the same trip,
                                           including the nodes each one explored
    GET /api/resolve?q=Baskin+Engr+152     building, room and entrances for a schedule string
    GET /api/search?q=BE+152[&limit=5]     ranked buildings and rooms for something a person typed
                                           (abbreviations, partial names, typos); each result's "query"
                                           can be passed to /api/route_to as room=
    GET /api/route_to?start=LAT,LON&room=Kresge+Acad+3201[&algo=astar][&explored=0][&avoid_stairs=1]
    GET /api/route_to?start=LAT,LON&to=LAT,LON[&name=Library][&algo=astar][&explored=0]
                                           route from a point (e.g. your location) to a room or to
                                           a coordinate. For a room it picks the building door that
                                           gives the shortest total trip. Needs no schedule.
                                           /api/route_to_room is the same endpoint under its old name
    POST /api/schedule/parse   {"text": "..."}       read a schedule pasted from MyUCSC
    POST /api/schedule/clean   {"meetings": [...]}   validate meetings (manual entry, saved ones)
    GET  /healthz                            "ok" for a hosting platform's health check
    POST /api/schedule/ics     {"text": "BEGIN:VCALENDAR..."}   read classes from a calendar (.ics) file
    POST /api/schedule/ocr     {"words": [{"text", "x0", "y0", "x1", "y1"}, ...]}
                                           rebuild a schedule from word positions that the browser read
                                           from a photo on the student's own machine (nothing is sent out)
    POST /api/today  {"meetings": [...], "here": [lat, lon], "now": "ISO time",
                      "remind_lead": 5, "reminded": [keys already shown]}
                                           what is happening now and next, with walking times and
                                           warnings for tight or impossible transitions
"""

import argparse
import json
import math
import mimetypes
import os
import re
import subprocess
import sys
import threading
import time
from collections import OrderedDict
from datetime import date, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]

if __name__ == "__main__" and os.name == "nt":  # checked before the imports below can fail
    sys.exit("The router only runs on Linux, so the server has to start inside WSL.\n"
             "From PowerShell, run:  .\\scripts\\start-server.ps1")

sys.path.insert(0, str(ROOT / "data-pipeline"))
from limits import RateLimiter  # noqa: E402
from room_parser import load_campus  # noqa: E402
import ics  # noqa: E402
import ocr_table  # noqa: E402
import timetable  # noqa: E402

ALGORITHMS = ("dijkstra", "astar")
MAX_BODY_BYTES = 300_000
OCR_MAX_BODY_BYTES = 1_000_000  # a few thousand word boxes
ICS_MAX_BODY_BYTES = 1_200_000  # a calendar file (limited to 1M characters inside)
DRAIN_LIMIT_BYTES = 12_000_000  # a refused upload is read and dropped up to this size, so the client sees the refusal
DRAIN_SECONDS = 10
MARGIN_DEG = 0.002  # how far outside the graph's area a click may be
ENGINE_TIMEOUT_S = 10
ENGINE_SLOTS = threading.BoundedSemaphore(int(os.environ.get("ENGINE_CONCURRENCY", "4")))
SLOW_CLIENT_TIMEOUT_S = 30  # a connection that stalls this long is dropped
# Per client: (requests, seconds). Heavy endpoints run the routing engine, so they get a tighter limit.
DEFAULT_LIMITS = {"general": (120, 60), "heavy": (30, 60)}
HEAVY_PATHS = frozenset({"/api/route", "/api/route_to_room", "/api/today", "/api/schedule/ocr"})


class BadRequest(Exception):
    pass


def parse_point(text, bbox):
    """Parse "lat,lon" and check it lies on (or just beside) the campus graph."""
    try:
        lat_s, lon_s = (text or "").split(",")
        lat, lon = float(lat_s), float(lon_s)
    except ValueError:
        raise BadRequest(f"expected lat,lon but got {text!r}") from None
    if not (math.isfinite(lat) and math.isfinite(lon)):
        raise BadRequest("coordinates must be finite numbers")
    west, south, east, north = bbox
    if not (south - MARGIN_DEG <= lat <= north + MARGIN_DEG
            and west - MARGIN_DEG <= lon <= east + MARGIN_DEG):
        raise BadRequest("that point is outside the campus area")
    return lat, lon


def distance_m(a, b):
    """Great-circle distance in meters between (lat, lon) pairs."""
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    h = (math.sin((p2 - p1) / 2) ** 2
         + math.cos(p1) * math.cos(p2) * math.sin(math.radians(b[1] - a[1]) / 2) ** 2)
    return 2 * 6371009.0 * math.asin(math.sqrt(min(1.0, h)))


def run_engine(engine, graph_dir, algo, start, end, explored=True, avoid_stairs=False):
    """Run the C router once and return its JSON result (found may be false).

    distance_m is the physical length; effective_m is the same walk scaled for climbs (what
    walking time is based on); stairs_m is how much of it is stairs."""
    cmd = [str(engine), str(graph_dir), f"{start[0]:.7f}", f"{start[1]:.7f}",
           f"{end[0]:.7f}", f"{end[1]:.7f}", "--algo", algo, "--json"]
    if explored:
        cmd.append("--explored")
    if avoid_stairs:
        cmd.append("--avoid-stairs")
    with ENGINE_SLOTS:  # a busy server queues engine runs instead of starting dozens at once
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=ENGINE_TIMEOUT_S)
    if proc.returncode not in (0, 2):  # 2 means "no path", which still prints JSON
        raise RuntimeError(proc.stderr.strip() or f"engine exited with {proc.returncode}")
    return json.loads(proc.stdout)


class Remembered:
    """A small least-recently-used memory that request threads can share."""

    def __init__(self, size):
        self.size = size
        self._items = OrderedDict()
        self._lock = threading.Lock()

    def get(self, key):
        """The value kept for key, or None."""
        with self._lock:
            if key not in self._items:
                return None
            self._items.move_to_end(key)
            return self._items[key]

    def put(self, key, value):
        with self._lock:
            self._items[key] = value
            self._items.move_to_end(key)
            while len(self._items) > self.size:
                self._items.popitem(last=False)

    def clear(self):
        with self._lock:
            self._items.clear()


DOOR_WALKS = Remembered(20_000)


def door_walk(engine, graph_dir, start, door, avoid_stairs=False):
    """The A* walk from start to a door (see run_engine). The graph does not change while the server
    runs and a phone asks about the same places again and again, so a walk is remembered; starts
    within about a meter of each other share one."""
    key = (str(engine), str(graph_dir), round(start[0], 5), round(start[1], 5),
           round(door[0], 6), round(door[1], 6), avoid_stairs)
    walk = DOOR_WALKS.get(key)
    if walk is None:
        walk = run_engine(engine, graph_dir, "astar", start, door, explored=False, avoid_stairs=avoid_stairs)
        DOOR_WALKS.put(key, walk)
    return walk


def best_entrance(engine, graph_dir, start, entrances, room_point=None, avoid_stairs=False):
    """Pick the door with the least effort from start: the climb-adjusted walk plus, when the
    room's own point is known, the straight-line distance from that door to the room.

    The router snaps both ends to the nearest path node, so the walk also counts the straight legs
    from the start to its node and from the door's node to the door (a door can be 25 m from any).

    Returns (entrance, walk_m, indoor_m, effective_m, stairs_m), or None if no door can be reached.
    """
    best = None
    seen = set()
    for e in entrances:
        key = (round(e["lat"], 6), round(e["lon"], 6))
        if key in seen:
            continue
        seen.add(key)
        r = door_walk(engine, graph_dir, start, (e["lat"], e["lon"]), avoid_stairs)
        if not r["found"]:
            continue
        indoor = 0.0
        if room_point:
            indoor = distance_m((e["lat"], e["lon"]), (room_point["lat"], room_point["lon"]))
        legs = r.get("start_snap_m", 0.0) + r.get("end_snap_m", 0.0)
        effective = r["effective_m"] + legs
        total = effective + indoor
        if best is None or total < best[0]:
            best = (total, e, r["distance_m"] + legs, indoor, effective, r["stairs_m"])
    return None if best is None else best[1:]


def load_calendar(path):
    """The terms listed in data/holidays.json; a missing file means none."""
    if not path.exists():
        return []
    return timetable.parse_terms(json.loads(path.read_text(encoding="utf-8")).get("terms"))


def load_room_names(path):
    """Official schedule names of the general-assignment rooms, for autocomplete."""
    if not path.exists():
        return []
    rooms = json.loads(path.read_text(encoding="utf-8"))["rooms"]
    return sorted(r["ais_display_name"] for r in rooms)


def make_walker(engine, graph_dir, campus):
    """A walker(origin, destination_text) for timetable.analyze, backed by the router.

    origin is ("point", lat, lon) or ("room", text). Returns {"meters", "indoor_m", "effective_m"}
    for the walk to the best door of the destination building, or None if there is no walk to
    time (online, TBA, unknown room, or no route).
    """
    cache = {}

    def start_of(origin):
        if origin[0] == "point":
            return (origin[1], origin[2])
        res = campus.resolve(origin[1])
        if res.kind != "building" or not res.entrances:
            return None
        if res.room_point:
            return (res.room_point["lat"], res.room_point["lon"])
        door = next((e for e in res.entrances if e["kind"] == "main"), res.entrances[0])
        return (door["lat"], door["lon"])

    def walker(origin, destination):
        key = (origin, destination)
        if key not in cache:
            start = start_of(origin)
            res = campus.resolve(destination)
            result = None
            if start is not None and res.kind == "building" and res.entrances:
                chosen = best_entrance(engine, graph_dir, start, res.entrances, res.room_point)
                if chosen is not None:
                    result = {"meters": chosen[1], "indoor_m": chosen[2], "effective_m": chosen[3]}
            cache[key] = result
        return cache[key]

    return walker


def safe_static_path(web_dir, url_path):
    """Map a URL path to a file under web_dir, or None if it escapes or is missing."""
    rel = "index.html" if url_path in ("", "/") else url_path.lstrip("/")
    candidate = (web_dir / rel).resolve()
    if web_dir.resolve() not in candidate.parents or not candidate.is_file():
        return None
    return candidate


def make_handler(engine, graph_dir, web_dir, limits=None, trust_proxy=False):
    meta = json.loads((graph_dir / "meta.json").read_text(encoding="utf-8"))
    bbox = tuple(meta["bbox_west_south_east_north"])
    campus = load_campus(ROOT / "data")
    terms = load_calendar(ROOT / "data" / "holidays.json")
    holidays = timetable.holidays_of(terms)

    def current_term():
        return timetable.term_for(terms, datetime.now(timetable.TZ).date())
    room_names = load_room_names(ROOT / "data" / "classrooms.json")
    resolution_fields = ("raw", "kind", "building_id", "room", "entrances", "floor", "note",
                         "room_known", "room_point", "candidates")

    def resolution_dict(r):
        d = {k: getattr(r, k) for k in resolution_fields}
        d["candidate_names"] = [campus.buildings[c]["name"] for c in r.candidates]
        return d

    def describe_locations(meetings):
        """For each meeting, what its location string turned out to be (for the UI)."""
        out = []
        for m in meetings:
            r = campus.resolve(m["location"])
            out.append({"kind": r.kind,
                        "building_name": campus.buildings[r.building_id]["name"] if r.building_id else None,
                        "room_known": r.room_known})
        return out

    settings = {**DEFAULT_LIMITS, **(limits or {})}
    general_limit = RateLimiter(*settings["general"])
    heavy_limit = RateLimiter(*settings["heavy"])

    class Handler(BaseHTTPRequestHandler):
        timeout = SLOW_CLIENT_TIMEOUT_S

        def log_message(self, fmt, *args):
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

        def log_request(self, code="-", size="-"):
            # Log the path but never the query string: it holds where the student is.
            self.log_message('"%s %s" %s', self.command, urlparse(self.path).path, code)

        def client_id(self):
            """Who to count requests against. Behind a trusted proxy that is the address it forwards."""
            forwarded = self.headers.get("X-Forwarded-For", "")
            if trust_proxy and forwarded:
                return forwarded.split(",")[0].strip()
            return self.client_address[0]

        def throttled(self, path):
            """Send a 429 and return True if this client has made too many requests."""
            if not path.startswith("/api/"):
                return False
            client = self.client_id()
            checks = [general_limit] + ([heavy_limit] if path in HEAVY_PATHS else [])
            for limiter in checks:
                allowed, retry_after = limiter.allow(client)
                if not allowed:
                    body = json.dumps({"error": "Too many requests. Please slow down and try again shortly.",
                                       "retry_after": retry_after}).encode("utf-8")
                    self.send_response(429)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.send_header("Retry-After", str(retry_after))
                    self.end_headers()
                    self.wfile.write(body)
                    return True
            return False

        def send_json(self, status, payload):
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            url = urlparse(self.path)
            query = parse_qs(url.query)
            if self.throttled(url.path):
                return
            try:
                if url.path == "/healthz":  # for the host's health check; says nothing about students
                    self.send_json(200, {"ok": True})
                elif url.path == "/api/meta":
                    self.send_json(200, {"bbox": bbox, "nodes": meta["nodes"], "edges": meta["edges"],
                                         "term": current_term(), "terms": terms})
                elif url.path == "/api/rooms":
                    self.send_json(200, {"rooms": room_names})
                elif url.path == "/api/route":
                    start = parse_point(query.get("start", [""])[0], bbox)
                    end = parse_point(query.get("end", [""])[0], bbox)
                    stairs = query.get("avoid_stairs", ["0"])[0] == "1"
                    self.send_json(200, {a: run_engine(engine, graph_dir, a, start, end, avoid_stairs=stairs)
                                         for a in ALGORITHMS})
                elif url.path == "/api/search":
                    text = query.get("q", [""])[0]
                    if len(text) > 100:
                        raise BadRequest("q is too long")
                    try:
                        limit = int(query.get("limit", ["5"])[0])
                    except ValueError:
                        raise BadRequest("limit must be a whole number") from None
                    self.send_json(200, {"results": campus.search(text, max(1, min(limit, 10)))})
                elif url.path == "/api/resolve":
                    self.send_json(200, resolution_dict(campus.resolve(query.get("q", [""])[0])))
                elif url.path in ("/api/route_to", "/api/route_to_room"):
                    self.route_to(query, bbox)
                elif url.path.startswith("/api/"):
                    self.send_json(404, {"error": "unknown endpoint"})
                else:
                    self.send_static(url.path)
            except BadRequest as e:
                self.send_json(400, {"error": str(e)})
            except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as e:
                self.send_json(500, {"error": f"engine failed: {e}"})

        def read_json(self, limit=MAX_BODY_BYTES):
            try:
                length = int(self.headers.get("Content-Length", ""))
            except ValueError:
                raise BadRequest("send a JSON body") from None
            if length < 0 or length > limit:
                raise BadRequest("that request is too large")
            raw = self.rfile.read(length)
            self.body_read = True
            try:
                body = json.loads(raw)
            except (json.JSONDecodeError, UnicodeDecodeError):
                raise BadRequest("the body is not valid JSON") from None
            if not isinstance(body, dict):
                raise BadRequest("the body must be a JSON object")
            return body

        def drain_body(self):
            """Read and drop an upload that was refused unread. Closing with unread bytes resets the
            connection, and the client would see that instead of our answer."""
            if self.body_read:
                return
            deadline = time.monotonic() + DRAIN_SECONDS
            try:
                left = min(int(self.headers.get("Content-Length", "0")), DRAIN_LIMIT_BYTES)
                while left > 0 and time.monotonic() < deadline:
                    chunk = self.rfile.read(min(left, 65536))
                    if not chunk:
                        break
                    left -= len(chunk)
            except (ValueError, OSError):
                pass

        def do_POST(self):
            self.body_read = False
            try:
                self.handle_post()
            finally:
                self.drain_body()

        def handle_post(self):
            url = urlparse(self.path)
            if self.throttled(url.path):
                return
            try:
                if url.path == "/api/schedule/parse":
                    meetings, notes = timetable.parse_pasted(self.read_json().get("text"), campus)
                    self.send_json(200, {"meetings": meetings, "notes": notes,
                                         "locations": describe_locations(meetings)})
                elif url.path == "/api/schedule/clean":
                    meetings = timetable.clean_schedule(self.read_json().get("meetings"))
                    self.send_json(200, {"meetings": meetings, "locations": describe_locations(meetings)})
                elif url.path == "/api/schedule/ics":
                    self.schedule_ics(self.read_json(ICS_MAX_BODY_BYTES))
                elif url.path == "/api/schedule/ocr":
                    self.schedule_ocr(self.read_json(OCR_MAX_BODY_BYTES))
                elif url.path == "/api/today":
                    self.today(self.read_json())
                else:
                    self.send_json(404, {"error": "unknown endpoint"})
            except (BadRequest, timetable.ScheduleError) as e:
                self.send_json(400, {"error": str(e)})
            except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as e:
                self.send_json(500, {"error": f"engine failed: {e}"})

        def schedule_ics(self, body):
            meetings, notes = ics.parse_ics(body.get("text"), current_term())
            self.send_json(200, {"meetings": meetings, "notes": notes, "source": "ics",
                                 "locations": describe_locations(meetings)})

        def schedule_ocr(self, body):
            try:  # a bad payload and a picture with no table both get a clear 400, never a dropped connection
                words = ocr_table.clean_words(body.get("words"))
                text, notes = ocr_table.read_table(words)
            except ocr_table.OcrLayoutError as e:
                raise timetable.ScheduleError(
                    f"I couldn't read a class table from that image: {e}. Try a screenshot of the whole "
                    "Class Schedule page, or paste the text instead.") from None
            meetings, parse_notes = timetable.parse_pasted(text, campus)
            for m in meetings:
                original = m["location"]
                m["location"], fixed = campus.correct_room(original)
                if fixed:
                    notes.append(fixed)
                    # keep the text shown for hand-editing in step with what was imported
                    text = re.sub(re.escape(original) + r"(?![\w])", lambda _, loc=m["location"]: loc, text)
                m["class_nbr"] = ""  # recognition often drops a digit, and the number is not needed
            self.send_json(200, {"meetings": meetings, "notes": notes + parse_notes, "source": "ocr",
                                 "text": text, "locations": describe_locations(meetings)})

        def today(self, body):
            meetings = timetable.clean_schedule(body.get("meetings", []))
            now = datetime.now(timetable.TZ)
            if body.get("now") is not None:  # lets a demo or a test pick the moment
                try:
                    now = datetime.fromisoformat(body["now"])
                except (TypeError, ValueError):
                    raise BadRequest("now must look like 2026-10-12T08:30:00-07:00") from None
                if now.tzinfo is None:
                    now = now.replace(tzinfo=timetable.TZ)
            notes, here = [], None
            if body.get("here") is not None:
                try:
                    here = parse_point(",".join(str(x) for x in body["here"]), bbox)
                except (BadRequest, TypeError):
                    notes.append("Your location is outside the mapped campus area, so I ignored it.")
            remind = None
            if body.get("remind_lead") is not None:  # also plan "time to leave" reminders
                lead, sent = body["remind_lead"], body.get("reminded", [])
                if not isinstance(lead, int) or isinstance(lead, bool) or not 0 <= lead <= 60:
                    raise BadRequest("remind_lead must be a whole number of minutes from 0 to 60")
                if not isinstance(sent, list) or len(sent) > 100 or not all(
                        isinstance(k, str) and len(k) <= 80 for k in sent):
                    raise BadRequest("reminded must be a short list of reminder keys")
                remind = {"lead_min": lead, "sent": sent}
            result = timetable.analyze(meetings, now, holidays, make_walker(engine, graph_dir, campus), here, remind)
            result["notes"] = notes + result["notes"]
            result["holidays"] = sorted(d.isoformat() for d in holidays)  # so a phone can work offline
            self.send_json(200, result)

        def route_to(self, query, bbox):
            start = parse_point(query.get("start", [""])[0], bbox)
            if query.get("to"):
                target = parse_point(query["to"][0], bbox)
                name = " ".join(query.get("name", [""])[0].split())[:80]
                res = None
                entrances, room_point = [{"lat": target[0], "lon": target[1], "kind": "point"}], None
            else:
                text = query.get("room", [""])[0]
                if not text.strip() or len(text) > 100:
                    raise BadRequest("room must be a schedule location such as 'Kresge Acad 3201', or give to=LAT,LON")
                res = campus.resolve(text)
                if res.kind != "building":
                    reason = {"online": "that class is online, so there is nowhere to walk",
                              "tba": "that class has no room yet",
                              "unknown": "I don't recognise that location"}[res.kind]
                    self.send_json(422, {"error": reason, "kind": res.kind, "candidates": res.candidates,
                                         "candidate_names": resolution_dict(res)["candidate_names"]})
                    return
                entrances, room_point = res.entrances, res.room_point
            avoid_stairs = query.get("avoid_stairs", ["0"])[0] == "1"
            chosen = best_entrance(engine, graph_dir, start, entrances, room_point, avoid_stairs)
            if chosen is None:
                self.send_json(422, {"error": "no walkable route from there to that place",
                                     "kind": "unreachable", "candidates": []})
                return
            entrance, walk_m, indoor_m, effective_m, stairs_m = chosen
            end = (entrance["lat"], entrance["lon"])
            # The web demo wants both algorithms and the explored nodes; the phone app only
            # needs one path, so it can ask for less (?algo=astar&explored=0).
            algos = ALGORITHMS if "algo" not in query else [query["algo"][0]]
            if any(a not in ALGORITHMS for a in algos):
                raise BadRequest("algo must be one of: " + ", ".join(ALGORITHMS))
            with_explored = query.get("explored", ["1"])[0] != "0"
            payload = {a: run_engine(engine, graph_dir, a, start, end, explored=with_explored, avoid_stairs=avoid_stairs)
                       for a in algos}
            described = (resolution_dict(res) | {"building_name": campus.buildings[res.building_id]["name"]}
                         if res else {"kind": "point", "building_name": name})
            payload["room"] = {
                **described,
                "entrance": entrance,
                "walk_m": round(walk_m, 1),
                "effective_m": round(effective_m, 1),
                "stairs_m": round(stairs_m, 1),
                "indoor_m": round(indoor_m, 1),
            }
            self.send_json(200, payload)

        def send_static(self, url_path):
            path = safe_static_path(web_dir, url_path)
            if path is None:
                self.send_json(404, {"error": "not found"})
                return
            body = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", mimetypes.guess_type(path.name)[0] or "application/octet-stream")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return Handler


def make_server(host, port, engine, graph_dir, web_dir, limits=None, trust_proxy=False):
    handler = make_handler(engine, graph_dir, web_dir, limits, trust_proxy)
    return ThreadingHTTPServer((host, port), handler)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    # A host such as Render or Cloud Run sets PORT (and we set HOST in the container image).
    ap.add_argument("--host", default=os.environ.get("HOST", "127.0.0.1"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8000")))
    ap.add_argument("--trust-proxy", action="store_true",
                    default=os.environ.get("TRUST_PROXY", "") in ("1", "true", "yes"),
                    help="count clients by X-Forwarded-For (only behind a proxy you trust)")
    ap.add_argument("--engine", type=Path, default=ROOT / "engine" / "route")
    ap.add_argument("--graph", type=Path, default=ROOT / "graph" / "ucsc")
    ap.add_argument("--web", type=Path, default=ROOT / "web")
    args = ap.parse_args()
    if not args.engine.exists():
        sys.exit(f"engine not found at {args.engine}; build it with: make -C engine route")
    server = make_server(args.host, args.port, args.engine, args.graph, args.web, trust_proxy=args.trust_proxy)
    print(f"Serving on http://{args.host}:{args.port}  (Ctrl+C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
