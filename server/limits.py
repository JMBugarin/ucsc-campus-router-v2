"""A small per-client rate limiter, so a public copy of the server can't be run into the ground.

Sliding window: a client may make `limit` requests in any `window_s` seconds. In memory only
(each server process counts for itself) and standard library only.
"""

import math
import threading
import time
from collections import deque

MAX_TRACKED_CLIENTS = 5000


class RateLimiter:
    def __init__(self, limit, window_s, clock=time.monotonic):
        if limit < 1 or window_s <= 0:
            raise ValueError("limit must be at least 1 and window_s positive")
        self.limit, self.window, self._clock = limit, window_s, clock
        self._hits = {}
        self._lock = threading.Lock()

    def allow(self, client):
        """Returns (True, 0) and counts the request, or (False, seconds_until_it_would_be_allowed)."""
        now = self._clock()
        with self._lock:
            hits = self._hits.setdefault(client, deque())
            while hits and hits[0] <= now - self.window:
                hits.popleft()
            if len(hits) >= self.limit:
                return False, max(1, math.ceil(hits[0] + self.window - now))
            hits.append(now)
            if len(self._hits) > MAX_TRACKED_CLIENTS:  # forget clients with nothing recent
                for key in [k for k, q in self._hits.items() if not q or q[-1] <= now - self.window]:
                    del self._hits[key]
            return True, 0
