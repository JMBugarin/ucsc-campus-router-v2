"""Tests for ocr_table.py (run: python3 -m unittest discover -s server)."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "data-pipeline"))

import ocr_fixtures as fx  # noqa: E402
import ocr_table as ocr  # noqa: E402
import timetable  # noqa: E402
from room_parser import load_campus  # noqa: E402


def read(words):
    return ocr.read_table(ocr.clean_words(words))


class TestRepairs(unittest.TestCase):
    def test_times(self):
        self.assertEqual(ocr.fix_times("Mo 8:00AM - 9:05AM"), ["8:00AM", "9:05AM"])
        self.assertEqual(ocr.fix_times("Mo 8:OOAM - 9:O5am"), ["8:00AM", "9:05AM"])  # letter O for zero
        self.assertEqual(ocr.fix_times("TuTh 1l:40AM - l:15PM"), ["11:40AM", "1:15PM"])  # lowercase L for one
        self.assertEqual(ocr.fix_times("Mo 8.00AM"), ["8:00AM"])
        self.assertEqual(ocr.fix_times("Mo :05PM"), [])  # no hour: not guessed, and the "o" of "Mo" is not a 0
        self.assertEqual(ocr.fix_times("MoWeFr :05PM"), [])
        self.assertEqual(ocr.fix_times("Mo 13:00AM 0:30PM 9:75AM"), [])  # not real clock times

    def test_days(self):
        self.assertEqual(ocr.fix_days("MoWeFr"), "MoWeFr")
        self.assertEqual(ocr.fix_days("M0WeFr"), "MoWeFr")
        self.assertEqual(ocr.fix_days("TuTn"), "TuTh")
        self.assertIsNone(ocr.fix_days("Hello"))
        self.assertIsNone(ocr.fix_days("8:00AM"))

    def test_dates_sections_components_numbers(self):
        self.assertEqual(ocr.fix_dates("O9/24/2O26 - l2/O4/2026"), ["09/24/2026", "12/04/2026"])
        self.assertEqual(ocr.fix_section("O01A"), "01A")
        self.assertEqual(ocr.fix_section("O1F"), "01F")
        self.assertEqual(ocr.fix_component("Lectre"), "Lecture")
        self.assertEqual(ocr.fix_component("Discussion"), "Discussion")
        self.assertEqual(ocr.fix_class_number("2l001"), "21001")
        self.assertEqual(ocr.fix_class_number("131"), "")  # too short to be a class number

    def test_course_lines(self):
        self.assertEqual(ocr._tidy_course("XYZ 10 Sample Calculus lll"), "XYZ 10 - Sample Calculus III")
        self.assertEqual(ocr._tidy_course("ABC 20M Sample Systems for Fun"), "ABC 20M - Sample Systems for Fun")
        self.assertEqual(ocr._tidy_course("XYZ 10 - Sample Calculus II"), "XYZ 10 - Sample Calculus II")


class TestWordValidation(unittest.TestCase):
    def test_rejects_bad_input(self):
        for bad in ("nope", [{"text": "a"}], [{"text": "a", "x0": "x", "y0": 0, "x1": 1, "y1": 1}],
                    [{"text": "a", "x0": float("nan"), "y0": 0, "x1": 1, "y1": 1}],
                    [{"text": "a", "x0": 1e9, "y0": 0, "x1": 1, "y1": 1}],
                    [{"text": "a", "x0": 0, "y0": 0, "x1": 1, "y1": 1}] * (ocr.MAX_WORDS + 1)):
            with self.subTest(str(bad)[:40]), self.assertRaises(ocr.OcrLayoutError):
                ocr.clean_words(bad)

    def test_drops_empty_and_oversized_words(self):
        good = {"text": "ok", "x0": 0, "y0": 0, "x1": 1, "y1": 1}
        words = ocr.clean_words([good, {**good, "text": "  "}, {**good, "text": "x" * 500}])
        self.assertEqual([w.text for w in words], ["ok"])


class TestReadTable(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.campus = load_campus(ROOT / "data")

    def meetings(self, words):
        text, notes = read(words)
        meetings, parse_notes = timetable.parse_pasted(text, self.campus)
        return meetings, notes + parse_notes

    def test_rebuilds_a_clean_table(self):
        meetings, notes = self.meetings(fx.render(fx.SAMPLE))
        self.assertEqual(notes, [])
        got = [(m["course"], m["title"], m["component"], m["days"], m["start"], m["end"], m["location"])
               for m in meetings]
        self.assertEqual(got, [
            ("XYZ 10", "Sample Calculus", "Discussion", [0], "08:00", "09:05", "Cowell Acad 113"),
            ("XYZ 10", "Sample Calculus", "Lecture", [0, 2, 4], "14:40", "15:45", "Kresge Acad 3201"),
            ("ABC 20", "Sample Systems", "Discussion", [3], "08:30", "09:35", "J Baskin Engr 156"),
            ("ABC 20", "Sample Systems", "Lecture", [1, 3], "09:50", "11:25", "Earth&Marine B206"),
        ])
        self.assertEqual({(m["start_date"], m["end_date"]) for m in meetings}, {("2026-09-24", "2026-12-04")})

    def test_wrapped_cells_do_not_scramble(self):
        """'Mo 8:00AM -' over '9:05AM', 'Cowell Acad' over '113': the failure of plain line-order text."""
        text, _ = read(fx.render(fx.SAMPLE))
        self.assertIn("Mo 8:00AM - 9:05AM Cowell Acad 113 To be Announced 09/24/2026 - 12/04/2026", text)

    def test_menu_and_footer_are_ignored(self):
        text, _ = read(fx.render(fx.SAMPLE))
        for stray in ("Enrollment", "Printer", "Friendly", "Edit a"):
            self.assertNotIn(stray, text)

    def test_ocr_mistakes_are_repaired(self):
        noise = {("section", "20003"): "O01A", ("days", "20002"): "M0WeFr", ("t1", "20001"): "8:OOAM",
                 ("d1", "20004"): "O9/24/2O26", ("component", "20004"): "Lectre", ("nbr", "20001"): "2000l"}
        meetings, notes = self.meetings(fx.render(fx.SAMPLE, noise))
        self.assertEqual(notes, [])
        by = {(m["course"], m["component"]): m for m in meetings}
        self.assertEqual(by[("XYZ 10", "Discussion")]["start"], "08:00")
        self.assertEqual(by[("XYZ 10", "Lecture")]["days"], [0, 2, 4])
        self.assertEqual(by[("ABC 20", "Discussion")]["section"], "01A")
        self.assertEqual(by[("ABC 20", "Lecture")]["start_date"], "2026-09-24")

    def test_a_time_missing_its_hour_is_reported_not_guessed(self):
        meetings, notes = self.meetings(fx.render(fx.SAMPLE, {("t2", "20002"): ":45PM"}))
        self.assertEqual(len(meetings), 3)
        self.assertTrue(any("20002" in n or "Kresge" in n for n in notes), notes)

    def test_works_at_any_image_size(self):
        base, _ = read(fx.render(fx.SAMPLE))
        for scale in (0.6, 1.0, 2.5):
            with self.subTest(scale):
                self.assertEqual(read(fx.render(fx.SAMPLE, scale=scale))[0], base)

    def test_dropped_course_is_left_out_by_the_parser(self):
        courses = [fx.SAMPLE[0], fx.course("DEF 30", "Sample Dropped", [
            fx.row("20009", "01", "Lecture", "Tu", "9:00AM", "9:55AM", "Soc Sci 2 075", "Pat Example")],
            status="Dropped")]
        meetings, notes = self.meetings(fx.render(courses))
        self.assertEqual({m["course"] for m in meetings}, {"XYZ 10"})
        self.assertTrue(any("DEF 30" in n and "dropped" in n for n in notes))

    def test_single_course_and_three_tables(self):
        self.assertEqual(len(self.meetings(fx.render(fx.SAMPLE[:1]))[0]), 2)
        third = fx.course("GHI 30", "Sample Third", [
            fx.row("20005", "01", "Lecture", "MoWeFr", "4:00PM", "5:05PM", "Thim Lecture 003", "Pat Example")])
        meetings, _ = self.meetings(fx.render(fx.SAMPLE + [third]))
        self.assertEqual(len(meetings), 5)
        self.assertEqual(meetings[-1]["location"], "Thim Lecture 003")

    def test_no_table_is_a_clear_error(self):
        words = [fx.word(t, 20 + 50 * i, 100) for i, t in enumerate("Just some unrelated words".split())]
        with self.assertRaises(ocr.OcrLayoutError) as ctx:
            read(words)
        self.assertIn("class table", str(ctx.exception))
        with self.assertRaises(ocr.OcrLayoutError):
            read([])


if __name__ == "__main__":
    unittest.main()
