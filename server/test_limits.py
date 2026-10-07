"""Tests for limits.py (run: python3 -m unittest discover -s server)."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import limits  # noqa: E402


class FakeClock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


class TestRateLimiter(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.limiter = limits.RateLimiter(3, 60, self.clock)

    def test_allows_up_to_the_limit_then_refuses(self):
        self.assertEqual([self.limiter.allow("a")[0] for _ in range(3)], [True, True, True])
        allowed, retry = self.limiter.allow("a")
        self.assertFalse(allowed)
        self.assertEqual(retry, 60)

    def test_the_window_slides(self):
        for _ in range(3):
            self.limiter.allow("a")
        self.clock.now += 30
        self.assertEqual(self.limiter.allow("a"), (False, 30))     # the first hit leaves the window in 30 s
        self.clock.now += 30.5
        self.assertEqual(self.limiter.allow("a"), (True, 0))       # now the oldest has aged out
        self.assertTrue(self.limiter.allow("a")[0])
        self.assertTrue(self.limiter.allow("a")[0])
        self.assertFalse(self.limiter.allow("a")[0])

    def test_clients_are_counted_separately(self):
        for _ in range(3):
            self.limiter.allow("a")
        self.assertFalse(self.limiter.allow("a")[0])
        self.assertTrue(self.limiter.allow("b")[0])

    def test_a_refused_request_is_not_counted(self):
        for _ in range(3):
            self.limiter.allow("a")
        for _ in range(10):
            self.limiter.allow("a")                                 # hammering does not extend the ban
        self.clock.now += 61
        self.assertTrue(self.limiter.allow("a")[0])

    def test_idle_clients_are_forgotten(self):
        for i in range(limits.MAX_TRACKED_CLIENTS + 10):
            self.limiter.allow(f"client-{i}")
        self.clock.now += 120
        self.limiter.allow("fresh")
        self.assertLess(len(self.limiter._hits), 50)

    def test_bad_settings_are_rejected(self):
        for args in ((0, 60), (5, 0), (5, -1)):
            with self.subTest(args), self.assertRaises(ValueError):
                limits.RateLimiter(*args)


if __name__ == "__main__":
    unittest.main()
