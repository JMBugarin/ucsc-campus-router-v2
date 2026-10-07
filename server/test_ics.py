"""Tests for ics.py (run: python3 -m unittest discover -s server)."""

import sys
import unittest
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "data-pipeline"))

import ics  # noqa: E402
import timetable  # noqa: E402

TERM = {"name": "Fall 2026", "start": "2026-09-24", "end": "2026-12-04"}


def calendar(*events):
    return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\n" + "".join(events) + "END:VCALENDAR\r\n"


def event(*lines):
    return "BEGIN:VEVENT\r\n" + "".join(line + "\r\n" for line in lines) + "END:VEVENT\r\n"


# Mondays, Wednesdays and Fridays, 2:40-3:45 pm Pacific, until the end of term (UTC end, as Google writes it)
WEEKLY = event(
    "UID:1@test", "SUMMARY:XYZ 10 - Lecture", "LOCATION:Kresge Acad 3201",
    "DTSTART;TZID=America/Los_Angeles:20260925T144000", "DTEND;TZID=America/Los_Angeles:20260925T154500",
    "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261205T075959Z")


class TestReading(unittest.TestCase):
    def one(self, *events, term=TERM):
        meetings, notes = ics.parse_ics(calendar(*events), term)
        return meetings, notes

    def test_weekly_class(self):
        (m,), notes = self.one(WEEKLY)
        self.assertEqual(notes, [])
        self.assertEqual((m["course"], m["component"], m["days"], m["start"], m["end"], m["location"]),
                         ("XYZ 10", "Lecture", [0, 2, 4], "14:40", "15:45", "Kresge Acad 3201"))
        self.assertEqual((m["start_date"], m["end_date"]), ("2026-09-25", "2026-12-04"))  # UNTIL is in UTC

    def test_the_meeting_really_meets_on_those_days(self):
        (m,), _ = self.one(WEEKLY)
        self.assertTrue(timetable.occurs_on(m, date(2026, 10, 12)))     # a Monday
        self.assertFalse(timetable.occurs_on(m, date(2026, 10, 13)))    # a Tuesday
        self.assertFalse(timetable.occurs_on(m, date(2026, 12, 7)))     # after the end

    def test_utc_and_floating_times(self):
        utc = event("SUMMARY:A", "DTSTART:20261012T214000Z", "DTEND:20261012T224500Z")  # 2:40-3:45 pm PDT
        floating = event("SUMMARY:B", "DTSTART:20261012T144000", "DTEND:20261012T154500")
        (a, b), _ = self.one(utc, floating)
        self.assertEqual((a["start"], a["end"]), ("14:40", "15:45"))
        self.assertEqual((b["start"], b["end"]), ("14:40", "15:45"))

    def test_winter_time_is_converted_correctly(self):
        e = event("SUMMARY:A", "DTSTART:20261201T224000Z", "DTEND:20261201T234500Z")  # PST, UTC-8
        (m,), _ = self.one(e)
        self.assertEqual(m["start"], "14:40")

    def test_one_off_event(self):
        e = event("SUMMARY:Office hours", "LOCATION:Soc Sci 2 075",
                  "DTSTART;TZID=America/Los_Angeles:20261012T123000", "DTEND;TZID=America/Los_Angeles:20261012T131500")
        (m,), _ = self.one(e)
        self.assertEqual((m["days"], m["start_date"], m["end_date"]), ([], "2026-10-12", "2026-10-12"))

    def test_duration_instead_of_end(self):
        e = event("SUMMARY:A", "DTSTART;TZID=America/Los_Angeles:20261012T144000", "DURATION:PT1H5M")
        (m,), _ = self.one(e)
        self.assertEqual(m["end"], "15:45")

    def test_skipped_dates(self):
        e = event("SUMMARY:A", "DTSTART;TZID=America/Los_Angeles:20260928T144000",
                  "DTEND;TZID=America/Los_Angeles:20260928T154500", "RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20261204T000000Z",
                  "EXDATE;TZID=America/Los_Angeles:20261012T144000,20261019T144000",
                  "EXDATE;VALUE=DATE:20261026", "EXDATE;TZID=America/Los_Angeles:20300101T144000")  # last: out of range
        (m,), _ = self.one(e)
        self.assertEqual(m["skip_dates"], ["2026-10-12", "2026-10-19", "2026-10-26"])
        self.assertFalse(timetable.occurs_on(m, date(2026, 10, 12)))
        self.assertTrue(timetable.occurs_on(m, date(2026, 10, 5)))

    def test_count_ends_the_series(self):
        e = event("SUMMARY:A", "DTSTART;TZID=America/Los_Angeles:20260928T144000",
                  "DTEND;TZID=America/Los_Angeles:20260928T154500", "RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=5")
        (m,), _ = self.one(e)
        # five meetings: Mon 9/28, Wed 9/30, Mon 10/5, Wed 10/7, Mon 10/12
        self.assertEqual(m["end_date"], "2026-10-12")
        self.assertTrue(timetable.occurs_on(m, date(2026, 10, 12)))
        self.assertFalse(timetable.occurs_on(m, date(2026, 10, 14)))

    def test_open_ended_series_stops_at_the_term_or_a_default(self):
        e = event("SUMMARY:A", "DTSTART;TZID=America/Los_Angeles:20260928T144000",
                  "DTEND;TZID=America/Los_Angeles:20260928T154500", "RRULE:FREQ=WEEKLY;BYDAY=MO")
        (m,), notes = self.one(e)
        self.assertEqual(m["end_date"], "2026-12-04")
        self.assertTrue(any("no end date" in n for n in notes))
        (m,), notes = ics.parse_ics(calendar(e), None)
        self.assertEqual(m["end_date"], "2027-01-18")  # 16 weeks on
        self.assertTrue(any("16 weeks" in n for n in notes))

    def test_no_byday_uses_the_start_day(self):
        e = event("SUMMARY:A", "DTSTART;TZID=America/Los_Angeles:20260929T144000",  # a Tuesday
                  "DTEND;TZID=America/Los_Angeles:20260929T154500", "RRULE:FREQ=WEEKLY;UNTIL=20261201T000000Z")
        (m,), _ = self.one(e)
        self.assertEqual(m["days"], [1])

    def test_windows_zone_names_and_unknown_zones(self):
        win = event("SUMMARY:A", "DTSTART;TZID=Pacific Standard Time:20261012T144000",
                    "DTEND;TZID=Pacific Standard Time:20261012T154500")
        (m,), notes = self.one(win)
        self.assertEqual((m["start"], notes), ("14:40", []))
        odd = event("SUMMARY:B", "DTSTART;TZID=Mars/Olympus:20261012T144000", "DTEND;TZID=Mars/Olympus:20261012T154500")
        (m,), notes = self.one(odd)
        self.assertEqual(m["start"], "14:40")
        self.assertTrue(any("Mars/Olympus" in n for n in notes))

    def test_folded_lines_and_escapes(self):
        e = event("SUMMARY:XYZ 10 - Disc", "ussion", "LOCATION:Kresge Acad 3201\\, Kresge College",
                  "DTSTART;TZID=America/Los_Angeles:20261012T144000", "DTEND;TZID=America/Los_Angeles:20261012T154500")
        e = e.replace("Disc\r\nussion", "Disc\r\n ussion")  # a folded line continues with a space
        (m,), _ = self.one(e)
        self.assertEqual((m["course"], m["component"], m["location"]), ("XYZ 10", "Discussion", "Kresge Acad 3201"))

    def test_video_link_becomes_online(self):
        e = event("SUMMARY:A", "LOCATION:https://zoom.us/j/123", "DTSTART:20261012T144000", "DTEND:20261012T154500")
        (m,), _ = self.one(e)
        self.assertEqual(m["location"], "Online")

    def test_events_that_are_left_out_are_explained(self):
        cases = {
            "all-day": event("SUMMARY:Holiday", "DTSTART;VALUE=DATE:20261111", "DTEND;VALUE=DATE:20261112"),
            "cancelled": event("SUMMARY:Gone", "STATUS:CANCELLED", "DTSTART:20261012T144000", "DTEND:20261012T154500"),
            "daily": event("SUMMARY:Daily", "DTSTART:20261012T144000", "DTEND:20261012T154500", "RRULE:FREQ=DAILY"),
            "every other week": event("SUMMARY:Biweekly", "DTSTART:20261012T144000", "DTEND:20261012T154500",
                                      "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO"),
            "first monday": event("SUMMARY:Monthly", "DTSTART:20261012T144000", "DTEND:20261012T154500",
                                  "RRULE:FREQ=MONTHLY;BYDAY=1MO"),
            "changed day": event("SUMMARY:Moved", "RECURRENCE-ID:20261012T144000", "DTSTART:20261012T154000",
                                 "DTEND:20261012T164500"),
            "overnight": event("SUMMARY:Late", "DTSTART:20261012T230000", "DTEND:20261013T010000"),
            "no end": event("SUMMARY:NoEnd", "DTSTART:20261012T144000"),
            "end before start": event("SUMMARY:Backwards", "DTSTART:20261012T154000", "DTEND:20261012T144500"),
            "garbage time": event("SUMMARY:Junk", "DTSTART:tomorrow", "DTEND:later"),
        }
        for label, e in cases.items():
            with self.subTest(label):
                meetings, notes = self.one(e)
                self.assertEqual(meetings, [])
                self.assertEqual(len(notes), 1, notes)

    def test_alarms_inside_events_are_ignored(self):
        e = event("SUMMARY:A", "DTSTART:20261012T144000", "DTEND:20261012T154500",
                  "BEGIN:VALARM", "TRIGGER:-PT10M", "SUMMARY:ignore me", "END:VALARM")
        (m,), _ = self.one(e)
        self.assertEqual(m["course"], "A")

    def test_duplicates_are_merged(self):
        meetings, _ = self.one(WEEKLY, WEEKLY)
        self.assertEqual(len(meetings), 1)

    def test_a_calendar_with_nothing_useful(self):
        meetings, notes = ics.parse_ics(calendar(), TERM)
        self.assertEqual((meetings, notes), ([], ["I couldn't find any classes in that calendar."]))

    def test_not_a_calendar(self):
        for bad in ("", "   ", None, "hello", "a" * (ics.MAX_ICS_CHARS + 1)):
            with self.subTest(str(bad)[:20]), self.assertRaises(timetable.ScheduleError):
                ics.parse_ics(bad, TERM)

    def test_too_many_events_are_capped(self):
        many = "".join(event(f"SUMMARY:C{i}", f"DTSTART:20261012T{8 + i % 10:02d}{i % 60:02d}00",
                             f"DTEND:20261012T{9 + i % 10:02d}{i % 60:02d}00") for i in range(timetable.MAX_MEETINGS + 30))
        meetings, notes = ics.parse_ics(calendar(many), TERM)
        self.assertEqual(len(meetings), timetable.MAX_MEETINGS)
        self.assertTrue(any("first" in n for n in notes))


class TestHelpers(unittest.TestCase):
    def test_split_property_handles_quotes(self):
        self.assertEqual(ics.split_property('DTSTART;TZID="A:B":20260101T000000'),
                         ("DTSTART", {"TZID": "A:B"}, "20260101T000000"))
        self.assertIsNone(ics.split_property("no colon here"))

    def test_durations(self):
        self.assertEqual(ics.parse_duration("PT1H5M").total_seconds(), 3900)
        self.assertEqual(ics.parse_duration("P1DT30M").total_seconds(), 88200)
        self.assertIsNone(ics.parse_duration("garbage"))
        self.assertIsNone(ics.parse_duration("P"))

    def test_unescape(self):
        self.assertEqual(ics.unescape("a\\, b\\; c\\nd\\\\e"), "a, b; c\nd\\e")


if __name__ == "__main__":
    unittest.main()
