"""Tests for timetable.py (run from the repo root: python3 -m unittest discover -s server)."""

import sys
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "data-pipeline"))

import timetable as sch  # noqa: E402
from room_parser import load_campus  # noqa: E402

TZ = sch.TZ

# A made-up schedule in the layout of MyUCSC's "Class Schedule" page. Cells are tab
# separated and some wrap across lines, as a browser copy often does. (Deliberately not
# anyone's real schedule.)
PASTED = """\
XYZ 10 - Sample Calculus
Status\tUnits\tGrading\tGrade\tDeadlines
Enrolled\t5.00\tGraded
Class\nNbr\tSection\tComponent\tDays & Times\tRoom\tInstructor\tStart/End Date
10001\t01A\tDiscussion\tTu 9:00AM -\n9:55AM\tSoc Sci 2\n075\tTo be\nAnnounced\t09/24/2026 -\n12/04/2026
10002\t01\tLecture\tMoWeFr 1:20PM - 2:25PM\tKresge Acad 3201\tA Instructor\t09/24/2026 - 12/04/2026
ABC 20 - Sample Systems Design
Status\tUnits\tGrading\tGrade\tDeadlines
Enrolled\t5.00\tGraded
10003\t01\tLecture\tTuTh 11:40AM - 1:15PM\tEarth&Marine B206\tB Instructor\t09/24/2026 - 12/04/2026
10004\t01A\tDiscussion\tTh 4:00PM - 5:05PM\tHumn Lecture Hall\tTo be Announced\t09/24/2026 - 12/04/2026
DEF 30 - Dropped Course
Status\tUnits\tGrading\tGrade\tDeadlines
Dropped\t5.00\tGraded
10005\t01\tLecture\tMoWe 8:00AM - 9:05AM\tJ Baskin Engr 156\tC Instructor\t09/24/2026 - 12/04/2026
"""


def meeting(course, days, start, end, location, start_date="2026-09-24", end_date="2026-12-04"):
    return {"course": course, "title": "", "section": "01", "component": "Lecture",
            "class_nbr": "", "days": days, "start": start, "end": end, "location": location,
            "start_date": start_date, "end_date": end_date}


def at(y, mo, d, h, mi):
    return datetime(y, mo, d, h, mi, tzinfo=TZ)


class TestParsePasted(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.campus = load_campus(ROOT / "data")
        cls.meetings, cls.notes = sch.parse_pasted(PASTED, cls.campus)

    def test_reads_enrolled_rows_and_skips_dropped(self):
        self.assertEqual([m["class_nbr"] for m in self.meetings], ["10001", "10002", "10003", "10004"])
        self.assertTrue(any("DEF 30" in n and "dropped" in n for n in self.notes))

    def test_fields(self):
        by_nbr = {m["class_nbr"]: m for m in self.meetings}
        disc = by_nbr["10001"]
        self.assertEqual((disc["course"], disc["title"], disc["section"], disc["component"]),
                         ("XYZ 10", "Sample Calculus", "01A", "Discussion"))
        self.assertEqual((disc["days"], disc["start"], disc["end"]), ([1], "09:00", "09:55"))
        self.assertEqual(disc["location"], "Soc Sci 2 075")  # room and instructor separated
        self.assertEqual((disc["start_date"], disc["end_date"]), ("2026-09-24", "2026-12-04"))
        self.assertEqual(by_nbr["10002"]["days"], [0, 2, 4])
        self.assertEqual((by_nbr["10002"]["start"], by_nbr["10002"]["end"]), ("13:20", "14:25"))
        self.assertEqual(by_nbr["10003"]["days"], [1, 3])
        self.assertEqual(by_nbr["10003"]["location"], "Earth&Marine B206")
        self.assertEqual(by_nbr["10004"]["location"], "Humn Lecture Hall")
        self.assertEqual(by_nbr["10003"]["course"], "ABC 20")

    def test_instructors_are_not_kept(self):
        self.assertNotIn("Instructor", str(self.meetings))
        self.assertNotIn("Announced", str(self.meetings))

    def test_every_location_resolves_to_a_building(self):
        for m in self.meetings:
            self.assertEqual(self.campus.resolve(m["location"]).kind, "building", m["location"])

    def test_flattened_text_works_too(self):
        flat = " ".join(PASTED.split())
        meetings, _ = sch.parse_pasted(flat, self.campus)
        self.assertEqual(len(meetings), 4)

    def test_rows_without_course_headers(self):
        rows = "10002 01 Lecture MoWeFr 1:20PM - 2:25PM Kresge Acad 3201 A Instructor 09/24/2026 - 12/04/2026"
        meetings, _ = sch.parse_pasted(rows, self.campus)
        self.assertEqual(meetings[0]["course"], "Class 10002")

    def test_unreadable_rows_are_reported(self):
        text = "10009 01 Lecture TBA TBA To be Announced 09/24/2026 - 12/04/2026"
        meetings, notes = sch.parse_pasted(text, self.campus)
        self.assertEqual(meetings, [])
        self.assertTrue(any("10009" in n for n in notes))

    def test_empty_and_huge_input(self):
        for bad in ("", "   ", None, "x" * (sch.MAX_TEXT + 1)):
            with self.assertRaises(sch.ScheduleError):
                sch.parse_pasted(bad, self.campus)

    def test_text_with_no_classes_says_so(self):
        meetings, notes = sch.parse_pasted("hello world", self.campus)
        self.assertEqual(meetings, [])
        self.assertIn("couldn't find any classes", notes[0])


class TestValidation(unittest.TestCase):
    def good(self, **changes):
        return {**meeting("XYZ 10", [0], "08:00", "09:05", "Cowell Acad 113"), **changes}

    def test_accepts_a_good_meeting(self):
        self.assertEqual(sch.clean_meeting(self.good())["start"], "08:00")

    def test_rejects_bad_meetings(self):
        bad = [
            self.good(course=""), self.good(course="x" * 41), self.good(days=[7]),
            self.good(days="Mo"), self.good(start="8am"), self.good(end="07:00"),
            self.good(start_date="soon"), self.good(end_date="2026-09-01"),
            self.good(days=[]),  # several dates but no weekdays
            "not a dict",
        ]
        for raw in bad:
            with self.subTest(raw), self.assertRaises(sch.ScheduleError):
                sch.clean_meeting(raw)

    def test_one_off_event_is_allowed(self):
        event = self.good(days=[], start_date="2026-10-12", end_date="2026-10-12")
        self.assertEqual(sch.clean_meeting(event)["days"], [])

    def test_unknown_fields_are_dropped_and_text_tidied(self):
        cleaned = sch.clean_meeting(self.good(location="  Cowell   Acad 113 ", evil="<script>"))
        self.assertEqual(cleaned["location"], "Cowell Acad 113")
        self.assertNotIn("evil", cleaned)

    def test_schedule_size_limit(self):
        with self.assertRaises(sch.ScheduleError):
            sch.clean_schedule([self.good()] * (sch.MAX_MEETINGS + 1))


class TestExtraction(unittest.TestCase):
    TERM = {"name": "Fall 2026", "start": "2026-09-24", "end": "2026-12-04"}

    def row(self, **changes):
        base = {"course": "XYZ 10", "title": "Sample Calculus", "section": "01", "component": "Lecture",
                "class_nbr": "20002", "days": ["Mo", "We", "Fr"], "start": "14:40", "end": "15:45",
                "location": "Kresge Acad 3201", "start_date": "2026-09-24", "end_date": "2026-12-04",
                "status": "Enrolled"}
        return {**base, **changes}

    def test_good_rows_become_meetings(self):
        meetings, notes = sch.meetings_from_extraction({"classes": [self.row()], "notes": []}, self.TERM)
        self.assertEqual(notes, [])
        self.assertEqual((meetings[0]["days"], meetings[0]["start"], meetings[0]["location"]),
                         ([0, 2, 4], "14:40", "Kresge Acad 3201"))

    def test_dropped_and_unreadable_rows_are_reported_not_used(self):
        data = {"classes": [
            self.row(),
            self.row(course="DEF 30", status="Dropped"),
            self.row(course="BAD 1", end="13:00"),            # ends before it starts
            self.row(course="BAD 2", days=["Xx"]),            # not a day
            self.row(course="BAD 3", start="2pm"),            # not a time
            "not a row",
        ], "notes": []}
        meetings, notes = sch.meetings_from_extraction(data, self.TERM)
        self.assertEqual([m["course"] for m in meetings], ["XYZ 10"])
        text = " ".join(notes)
        for fragment in ("DEF 30 (dropped)", "BAD 1", "days for BAD 2", "BAD 3"):
            self.assertIn(fragment, text)

    def test_missing_dates_fall_back_to_the_term(self):
        meetings, notes = sch.meetings_from_extraction(
            {"classes": [self.row(start_date="", end_date="")], "notes": []}, self.TERM)
        self.assertEqual((meetings[0]["start_date"], meetings[0]["end_date"]), ("2026-09-24", "2026-12-04"))
        self.assertTrue(any("term dates" in n for n in notes))
        meetings, notes = sch.meetings_from_extraction({"classes": [self.row(start_date="")], "notes": []}, None)
        self.assertEqual(meetings, [])  # no term to fall back on, so the row is reported instead
        self.assertTrue(notes)

    def test_models_notes_are_passed_on_and_prefixed(self):
        _, notes = sch.meetings_from_extraction({"classes": [], "notes": ["Row 3 is blurry", " "]}, self.TERM)
        self.assertEqual(notes, ["From the photo: Row 3 is blurry"])

    def test_nothing_found_says_so(self):
        meetings, notes = sch.meetings_from_extraction({"classes": [], "notes": []}, self.TERM)
        self.assertEqual((meetings, notes), ([], ["I couldn't find any classes in that image."]))

    def test_numbers_and_stray_text_are_tidied_not_trusted(self):
        meetings, _ = sch.meetings_from_extraction(
            {"classes": [self.row(class_nbr=20002, location="  Kresge   Acad 3201  ")], "notes": []}, self.TERM)
        self.assertEqual((meetings[0]["class_nbr"], meetings[0]["location"]), ("20002", "Kresge Acad 3201"))

    def test_row_count_is_capped(self):
        rows = [self.row(class_nbr=str(i)) for i in range(sch.MAX_MEETINGS + 20)]
        meetings, _ = sch.meetings_from_extraction({"classes": rows, "notes": []}, self.TERM)
        self.assertEqual(len(meetings), sch.MAX_MEETINGS)


class TestReminders(unittest.TestCase):
    """One class at 2:40 PM and a 12 minute walk, so the student must leave at 2:28."""

    def setUp(self):
        self.schedule = [meeting("XYZ 10", [0, 2, 4], "14:40", "15:45", "Kresge Acad 3201")]

    def plan(self, when, lead=5, sent=(), schedule=None, walk_m=900):
        walker = (lambda origin, destination: {"meters": walk_m, "indoor_m": 0.0}) if walk_m else None
        result = sch.analyze(schedule or self.schedule, when, frozenset(), walker, (37.0, -122.06),
                             {"lead_min": lead, "sent": list(sent)})
        return result["reminders"], result["banner"], result

    def stages(self, reminders):
        return [(r["stage"], r["in_seconds"]) for r in reminders]

    def test_both_reminders_are_planned_ahead(self):
        reminders, banner, result = self.plan(at(2026, 10, 12, 14, 0))
        self.assertEqual(result["leave_by"], at(2026, 10, 12, 14, 28).isoformat())
        self.assertEqual(self.stages(reminders), [("heads-up", 23 * 60.0), ("leave", 28 * 60.0)])
        self.assertEqual(reminders[0]["title"], "Leave in 5 min for XYZ 10 Lecture")
        self.assertEqual(reminders[1]["title"], "Time to leave for XYZ 10 Lecture")
        self.assertEqual(reminders[0]["body"], "Kresge Acad 3201: about 12 min on foot. Class starts at 2:40 PM.")
        self.assertIsNone(banner)

    def test_a_reminder_is_not_early_or_immediate(self):
        reminders, _, _ = self.plan(at(2026, 10, 12, 14, 22) + timedelta(seconds=58))
        self.assertEqual(self.stages(reminders)[0], ("heads-up", 2.0))

    def test_a_missed_heads_up_is_dropped_and_the_banner_counts_down(self):
        reminders, banner, _ = self.plan(at(2026, 10, 12, 14, 25))
        self.assertEqual(self.stages(reminders), [("leave", 180.0)])
        self.assertEqual(banner, {"text": "Leave in 3 min for XYZ 10 Lecture (12 min walk, class at 2:40 PM).",
                                  "late": False})

    def test_already_late_gives_one_immediate_reminder_and_a_late_banner(self):
        reminders, banner, result = self.plan(at(2026, 10, 12, 14, 30))
        self.assertEqual(result["status"], "late")  # 10 minutes to class, 12 to walk
        self.assertEqual(self.stages(reminders), [("late", 0.0)])
        self.assertEqual(reminders[0]["title"], "Leave now, you're running late for XYZ 10 Lecture")
        self.assertEqual(reminders[0]["key"], f"{at(2026, 10, 12, 14, 40).isoformat()}|leave")
        self.assertEqual(banner["late"], True)
        self.assertTrue(banner["text"].startswith("Leave now for XYZ 10 Lecture"))

    def test_reminders_already_shown_are_not_repeated(self):
        start = at(2026, 10, 12, 14, 40).isoformat()
        reminders, banner, _ = self.plan(at(2026, 10, 12, 14, 0), sent=[f"{start}|heads-up"])
        self.assertEqual(self.stages(reminders), [("leave", 28 * 60.0)])
        reminders, _, _ = self.plan(at(2026, 10, 12, 14, 30), sent=[f"{start}|leave"])
        self.assertEqual(reminders, [])
        self.assertIsNotNone(self.plan(at(2026, 10, 12, 14, 30), sent=[f"{start}|leave"])[1])  # banner stays

    def test_no_heads_up_when_the_lead_is_zero(self):
        reminders, banner, _ = self.plan(at(2026, 10, 12, 14, 0), lead=0)
        self.assertEqual(self.stages(reminders), [("leave", 28 * 60.0)])
        self.assertIsNone(self.plan(at(2026, 10, 12, 14, 20), lead=0)[1])      # the banner still gives 5 minutes' notice
        self.assertIsNotNone(self.plan(at(2026, 10, 12, 14, 24), lead=0)[1])

    def test_nothing_once_the_class_has_started(self):
        self.assertEqual(self.plan(at(2026, 10, 12, 14, 41))[:2], ([], None))
        self.assertEqual(self.plan(at(2026, 10, 12, 14, 50))[:2], ([], None))

    def test_nothing_without_a_walk_to_time_or_for_a_class_tomorrow(self):
        self.assertEqual(self.plan(at(2026, 10, 12, 14, 0), walk_m=0)[:2], ([], None))       # no walker
        self.assertEqual(self.plan(at(2026, 10, 12, 18, 0))[:2], ([], None))                 # next class is Wednesday
        online = [meeting("XYZ 10", [0], "14:40", "15:45", "Online")]
        self.assertEqual(self.plan(at(2026, 10, 12, 14, 0), schedule=online, walk_m=0)[:2], ([], None))

    def test_reminder_fields_are_only_present_when_asked_for(self):
        plain = sch.analyze(self.schedule, at(2026, 10, 12, 14, 0))
        self.assertNotIn("reminders", plain)
        self.assertNotIn("banner", plain)


class TestSkipDates(unittest.TestCase):
    def base(self, **changes):
        return {**meeting("A", [0], "14:40", "15:45", "Kresge Acad 3201"), **changes}

    def test_skipped_dates_are_kept_sorted_and_deduplicated(self):
        m = sch.clean_meeting(self.base(skip_dates=["2026-10-19", "2026-10-12", "2026-10-12"]))
        self.assertEqual(m["skip_dates"], ["2026-10-12", "2026-10-19"])

    def test_no_skip_dates_means_no_key(self):
        self.assertNotIn("skip_dates", sch.clean_meeting(self.base()))
        self.assertNotIn("skip_dates", sch.clean_meeting(self.base(skip_dates=[])))

    def test_bad_skip_dates_are_rejected(self):
        for bad in ("2026-10-12", ["soon"], [1], ["2026-10-12"] * (sch.MAX_SKIP_DATES + 1)):
            with self.subTest(str(bad)[:30]), self.assertRaises(sch.ScheduleError):
                sch.clean_meeting(self.base(skip_dates=bad))

    def test_a_skipped_day_has_no_class_and_other_days_do(self):
        m = sch.clean_meeting(self.base(skip_dates=["2026-10-12"]))
        self.assertFalse(sch.occurs_on(m, date(2026, 10, 12)))
        self.assertTrue(sch.occurs_on(m, date(2026, 10, 19)))
        today = sch.analyze([m], at(2026, 10, 12, 8, 0))
        self.assertEqual(today["next"]["start"][:10], "2026-10-19")  # skips straight to the next week


class TestOccurrences(unittest.TestCase):
    def setUp(self):
        self.mwf = meeting("A", [0, 2, 4], "14:40", "15:45", "Kresge Acad 3201")
        self.holidays = {date(2026, 11, 11)}

    def test_weekdays_and_term_bounds(self):
        self.assertTrue(sch.occurs_on(self.mwf, date(2026, 10, 12)))        # Monday
        self.assertFalse(sch.occurs_on(self.mwf, date(2026, 10, 13)))       # Tuesday
        self.assertFalse(sch.occurs_on(self.mwf, date(2026, 9, 21)))        # before the term
        self.assertFalse(sch.occurs_on(self.mwf, date(2026, 12, 7)))        # after the term

    def test_holiday_cancels_recurring_but_not_one_off(self):
        self.assertFalse(sch.occurs_on(self.mwf, date(2026, 11, 11), self.holidays))  # Wednesday
        event = meeting("Event", [], "18:00", "19:00", "Online", "2026-11-11", "2026-11-11")
        self.assertTrue(sch.occurs_on(event, date(2026, 11, 11), self.holidays))

    def test_sorted_by_time(self):
        early = meeting("B", [0], "08:00", "09:00", "Cowell Acad 113")
        order = [o[2]["course"] for o in sch.occurrences([self.mwf, early], date(2026, 10, 12))]
        self.assertEqual(order, ["B", "A"])


class TestAnalyze(unittest.TestCase):
    def setUp(self):
        self.schedule = [
            meeting("EARLY", [0], "08:00", "09:05", "Cowell Acad 113"),
            meeting("MID", [0], "10:40", "11:45", "McHenry Lib 1340"),
            meeting("AFT", [0, 2, 4], "14:40", "15:45", "Kresge Acad 3201"),
            meeting("EVE", [0, 2, 4], "16:00", "17:05", "Thim Lecture 003"),
            meeting("TUE", [1, 3], "09:50", "11:25", "Earth&Marine B206"),
        ]
        self.holidays = {date(2026, 11, 11)}
        self.meters = {"Cowell Acad 113": 400, "McHenry Lib 1340": 500,
                       "Kresge Acad 3201": 300, "Thim Lecture 003": 1000, "Earth&Marine B206": 600}
        self.calls = []

    def walker(self, origin, destination):
        self.calls.append((origin, destination))
        if destination not in self.meters:
            return None
        return {"meters": self.meters[destination], "indoor_m": 0.0}

    def run_at(self, when, here=(37.0, -122.06)):
        return sch.analyze(self.schedule, when, self.holidays, self.walker, here)

    def test_before_the_first_class(self):
        r = self.run_at(at(2026, 10, 12, 7, 0))
        self.assertEqual(r["state"], "before_classes")
        self.assertEqual(r["next"]["course"], "EARLY")
        self.assertEqual(r["next"]["starts_in_min"], 60.0)
        self.assertEqual(r["walk"], {"minutes": 6, "meters": 400.0, "from": "here"})  # 400 m = 5.1 -> 6 min
        self.assertEqual(r["free_min"], 54.0)
        self.assertEqual(r["status"], "ok")
        self.assertEqual(r["leave_by"], at(2026, 10, 12, 7, 54).isoformat())

    def test_during_a_class_the_next_walk_starts_from_that_room(self):
        r = self.run_at(at(2026, 10, 12, 8, 30))
        self.assertEqual(r["state"], "in_class")
        self.assertEqual(r["current"]["course"], "EARLY")
        self.assertEqual(r["current"]["minutes_left"], 35.0)
        self.assertEqual(r["next"]["course"], "MID")
        self.assertEqual(r["walk"]["from"], "current_class")
        self.assertEqual(self.calls[0][0], ("room", "Cowell Acad 113"))
        # 09:05 class ends, 10:40 next starts: 95 min gap minus a 7 min walk
        self.assertEqual(r["free_min"], 95.0 - 7)

    def test_between_classes_uses_here(self):
        r = self.run_at(at(2026, 10, 12, 12, 0))
        self.assertEqual(r["state"], "between_classes")
        self.assertEqual(r["next"]["course"], "AFT")
        self.assertEqual(r["walk"]["from"], "here")

    def test_between_classes_without_location_falls_back_to_last_room(self):
        r = self.run_at(at(2026, 10, 12, 12, 0), here=None)
        self.assertEqual(r["walk"]["from"], "previous_class")
        self.assertEqual(self.calls[0][0], ("room", "McHenry Lib 1340"))

    def test_tight_and_late_transitions(self):
        # 15:45 -> 16:00 is a 15 minute gap; Thimann is 1000 m = 13 min, leaving 2 spare
        r = self.run_at(at(2026, 10, 12, 15, 10))
        self.assertEqual(r["current"]["course"], "AFT")
        self.assertEqual((r["next"]["course"], r["free_min"], r["status"]), ("EVE", 2.0, "tight"))
        self.meters["Thim Lecture 003"] = 1500  # 19.2 min, rounded up to 20
        r = self.run_at(at(2026, 10, 12, 15, 10))
        self.assertEqual((r["free_min"], r["status"]), (-5.0, "late"))

    def test_today_list_has_a_verdict_for_each_transition(self):
        r = self.run_at(at(2026, 10, 12, 7, 0))
        self.assertEqual([t["course"] for t in r["today"]], ["EARLY", "MID", "AFT", "EVE"])
        self.assertNotIn("status", r["today"][0])  # nothing before the first class
        mid = r["today"][1]
        self.assertEqual((mid["gap_min"], mid["walk_min"], mid["free_min"], mid["status"]),
                         (95.0, 7, 88.0, "ok"))
        self.assertEqual(r["today"][3]["status"], "tight")  # 15 min gap, 13 min walk

    def test_after_the_last_class_points_at_tomorrow(self):
        r = self.run_at(at(2026, 10, 12, 18, 0))
        self.assertEqual(r["state"], "done_for_today")
        self.assertEqual(r["next"]["course"], "TUE")
        self.assertFalse(r["next"]["is_today"])
        # no walk or "free time" overnight
        self.assertEqual((r["walk"], r["free_min"], r["status"], r["leave_by"], r["notes"]),
                         (None, None, "unknown", None, []))
        self.assertNotIn("Earth&Marine B206", [dest for _, dest in self.calls])  # tomorrow is not timed

    def test_weekend_holiday_and_term_edges(self):
        r = self.run_at(at(2026, 10, 10, 12, 0))  # Saturday
        self.assertEqual((r["state"], r["reason"], r["next"]["course"]),
                         ("no_classes_today", "weekend", "EARLY"))
        r = self.run_at(at(2026, 11, 11, 9, 0))  # Veterans Day, a Wednesday
        self.assertEqual((r["state"], r["reason"], r["next"]["course"]),
                         ("no_classes_today", "holiday", "TUE"))
        r = self.run_at(at(2026, 9, 1, 9, 0))
        self.assertEqual((r["reason"], r["next"]["course"]), ("before_term", "TUE"))
        self.assertEqual(r["next"]["start"][:10], "2026-09-24")
        r = self.run_at(at(2026, 12, 10, 9, 0))
        self.assertEqual((r["reason"], r["next"]), ("after_term", None))

    def test_no_schedule(self):
        r = sch.analyze([], at(2026, 10, 12, 9, 0), self.holidays, self.walker)
        self.assertEqual((r["state"], r["reason"], r["next"]), ("no_classes_today", "no_schedule", None))

    def test_one_off_event_shows_up(self):
        self.schedule.append(meeting("Office hours", [], "13:00", "13:30", "Soc Sci 2 075",
                                     "2026-10-12", "2026-10-12"))
        self.meters["Soc Sci 2 075"] = 200
        r = self.run_at(at(2026, 10, 12, 12, 0))
        self.assertEqual(r["next"]["course"], "Office hours")

    def test_unwalkable_class_is_noted_not_guessed(self):
        self.schedule[2]["location"] = "Online"
        r = self.run_at(at(2026, 10, 12, 12, 0))
        self.assertEqual((r["next"]["course"], r["walk"], r["free_min"], r["status"]),
                         ("AFT", None, None, "unknown"))
        self.assertTrue(r["notes"])

    def test_times_convert_from_utc(self):
        r = self.run_at(datetime(2026, 10, 12, 15, 30, tzinfo=timezone.utc))  # 08:30 PDT
        self.assertEqual((r["state"], r["current"]["course"]), ("in_class", "EARLY"))

    def test_walker_is_optional(self):
        r = sch.analyze(self.schedule, at(2026, 10, 12, 7, 0), self.holidays)
        self.assertEqual((r["next"]["course"], r["walk"], r["status"]), ("EARLY", None, "unknown"))


if __name__ == "__main__":
    unittest.main()
