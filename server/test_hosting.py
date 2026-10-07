"""Tests for what a publicly hosted copy of the server needs (run: python3 -m unittest discover -s server)."""

import contextlib
import io
import json
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock

import server as srv

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "engine" / "route"
GRAPH = ROOT / "graph" / "ucsc"


class Running:
    """A server on a free port for the length of a `with` block."""

    def __init__(self, **kwargs):
        self.httpd = srv.make_server("127.0.0.1", 0, ENGINE, GRAPH, ROOT / "web", **kwargs)
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def __enter__(self):
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        return self

    def __exit__(self, *exc):
        self.httpd.shutdown()
        self.httpd.server_close()

    def get(self, path, headers=None):
        req = urllib.request.Request(self.base + path, headers=headers or {})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                return r.status, json.loads(r.read()), r.headers
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read()), e.headers


class TestHealthAndLimits(unittest.TestCase):
    def test_health_check(self):
        with Running() as s:
            status, body, _ = s.get("/healthz")
        self.assertEqual((status, body), (200, {"ok": True}))

    def test_too_many_requests_get_a_429_with_retry_after(self):
        with Running(limits={"general": (3, 60), "heavy": (100, 60)}) as s:
            codes = [s.get("/api/meta")[0] for _ in range(3)]
            status, body, headers = s.get("/api/meta")
            self.assertEqual(codes, [200, 200, 200])
            self.assertEqual(status, 429)
            self.assertIn("slow down", body["error"])
            self.assertEqual(int(headers["Retry-After"]), body["retry_after"])
            self.assertGreaterEqual(body["retry_after"], 1)
            # the health check and the web page are never throttled
            self.assertEqual(s.get("/healthz")[0], 200)
            with urllib.request.urlopen(s.base + "/", timeout=15) as r:
                self.assertEqual(r.status, 200)

    def test_the_engine_endpoints_have_a_tighter_limit(self):
        with Running(limits={"general": (100, 60), "heavy": (2, 60)}) as s:
            # these are rejected as bad requests, but they still count against the limit
            codes = [s.get("/api/route?start=x&end=y")[0] for _ in range(3)]
            self.assertEqual(codes, [400, 400, 429])
            self.assertEqual(s.get("/api/meta")[0], 200)              # cheap endpoints are unaffected

    def test_a_forwarded_address_is_ignored_unless_the_proxy_is_trusted(self):
        spoof = lambda n: {"X-Forwarded-For": f"203.0.113.{n}"}      # noqa: E731
        with Running(limits={"general": (2, 60), "heavy": (100, 60)}) as s:       # not behind a proxy
            codes = [s.get("/api/meta", spoof(n))[0] for n in range(4)]
            self.assertEqual(codes, [200, 200, 429, 429])             # changing the header does not help
        with Running(limits={"general": (2, 60), "heavy": (100, 60)}, trust_proxy=True) as s:
            first = [s.get("/api/meta", spoof(1))[0] for _ in range(3)]
            other = s.get("/api/meta", spoof(2))[0]
            self.assertEqual((first, other), ([200, 200, 429], 200))  # each real client has its own count

    def test_claude_photo_can_be_switched_off_for_a_public_server(self):
        fake = lambda image, media_type: {"classes": [], "notes": []}  # noqa: E731
        with Running(photo_reader=fake, photo_enabled=False) as s:
            caps = s.get("/api/capabilities")[1]["photo"]
            self.assertFalse(caps["ready"])
            self.assertIn("public server", caps["reason"])
            req = urllib.request.Request(
                s.base + "/api/schedule/photo", method="POST", headers={"Content-Type": "application/json"},
                data=json.dumps({"image": "iVBORw0KGgo=", "media_type": "image/png"}).encode())
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req, timeout=15)
            self.assertEqual(ctx.exception.code, 403)
        with Running(photo_reader=fake) as s:                       # on by default, as on a laptop
            self.assertTrue(s.get("/api/capabilities")[1]["photo"]["ready"])

    def test_slow_connections_are_dropped(self):
        with Running() as s:
            self.assertEqual(s.httpd.RequestHandlerClass.timeout, srv.SLOW_CLIENT_TIMEOUT_S)


@unittest.skipUnless(ENGINE.exists(), "engine not built: make -C engine route")
class TestPrivacyAndLoad(unittest.TestCase):
    def test_logs_never_contain_the_query_string(self):
        captured = io.StringIO()
        with Running() as s, contextlib.redirect_stderr(captured):
            status, _, _ = s.get("/api/route_to_room?start=36.9998,-122.0628&room=Kresge+Acad+3201")
            self.assertEqual(status, 200)
            s.get("/api/resolve?q=Baskin+Engr+152")
            time.sleep(0.2)                                            # the server logs after replying
        log = captured.getvalue()
        self.assertIn("/api/route_to_room", log)
        self.assertIn("/api/resolve", log)
        for private in ("36.9998", "-122.0628", "Kresge", "Baskin"):
            self.assertNotIn(private, log)

    def test_only_a_few_engine_runs_happen_at_once(self):
        running, peak, lock = [0], [0], threading.Lock()

        def slow_run(cmd, **kwargs):
            with lock:
                running[0] += 1
                peak[0] = max(peak[0], running[0])
            time.sleep(0.05)
            with lock:
                running[0] -= 1
            return mock.Mock(returncode=0, stdout=json.dumps({"found": True, "distance_m": 1.0}), stderr="")

        with mock.patch.object(srv, "ENGINE_SLOTS", threading.BoundedSemaphore(2)), \
                mock.patch.object(srv.subprocess, "run", slow_run):
            threads = [threading.Thread(target=srv.run_engine, args=(ENGINE, GRAPH, "astar", (37, -122), (37, -122.01)))
                       for _ in range(10)]
            for t in threads:
                t.start()
            for t in threads:
                t.join()
        self.assertEqual(peak[0], 2)


if __name__ == "__main__":
    unittest.main()
