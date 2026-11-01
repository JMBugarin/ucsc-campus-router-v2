"""Tests for the politeness rules of fetch_classrooms (run: python -m unittest discover -s data-pipeline/tests)."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fetch_classrooms import DEFAULT_DELAY_S, crawl_delay  # noqa: E402

ROBOTS = """User-agent: *
Disallow: /wp-admin/
Crawl-delay: 30  # seconds

User-agent: Yandex
Disallow: /
Crawl-delay: 5
"""


class TestCrawlDelay(unittest.TestCase):
    def test_reads_the_delay_for_every_crawler(self):
        self.assertEqual(crawl_delay(ROBOTS), 30.0)

    def test_ignores_the_delay_of_a_named_crawler(self):
        self.assertEqual(crawl_delay("User-agent: Yandex\nCrawl-delay: 5\n"), DEFAULT_DELAY_S)

    def test_no_robots_file_means_the_default(self):
        self.assertEqual(crawl_delay(""), DEFAULT_DELAY_S)

    def test_a_nonsense_delay_is_ignored(self):
        self.assertEqual(crawl_delay("User-agent: *\nCrawl-delay: soon\n"), DEFAULT_DELAY_S)


if __name__ == "__main__":
    unittest.main()
