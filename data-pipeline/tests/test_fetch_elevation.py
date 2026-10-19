"""fetch_elevation batches its requests and refuses incomplete answers (no network is used)."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import fetch_elevation as fe  # noqa: E402


def fake_post(calls):
    def post(url, form):
        calls.append(form["locations"].count("|") + 1)
        points = [tuple(float(x) for x in p.split(",")) for p in form["locations"].split("|")]
        return {"status": "OK", "results": [{"elevation": 100.04 + i, "location": {"lat": a, "lng": b}}
                                            for i, (a, b) in enumerate(points)]}
    return post


class TestFetchElevation(unittest.TestCase):
    def setUp(self):
        self.pause = fe.PAUSE_S
        fe.PAUSE_S = 0

    def tearDown(self):
        fe.PAUSE_S = self.pause

    def test_requests_are_batched_and_values_rounded(self):
        calls = []
        points = [(37.0 + i * 1e-5, -122.0) for i in range(250)]
        out = fe.fetch_elevations(points, post=fake_post(calls))
        self.assertEqual(calls, [100, 100, 50])
        self.assertEqual(len(out), 250)
        self.assertEqual(out[0], 100.0)

    def test_a_short_or_failed_answer_is_an_error(self):
        with self.assertRaises(RuntimeError):
            fe.fetch_elevations([(37.0, -122.0)], post=lambda u, f: {"status": "INVALID_REQUEST", "results": []})
        with self.assertRaises(RuntimeError):
            fe.fetch_elevations([(37.0, -122.0)], post=lambda u, f: {
                "status": "OK", "results": [{"elevation": None, "location": {"lat": 37.0, "lng": -122.0}}]})


if __name__ == "__main__":
    unittest.main()
