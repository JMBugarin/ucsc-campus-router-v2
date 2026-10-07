"""Rebuild MyUCSC's "Class Schedule" table from OCR word positions.

Text recognition run on a screenshot of that page returns words with bounding boxes. Reading
them in line order scrambles the table, because cells wrap (a "Days & Times" cell is two lines,
"Mo 8:00AM -" over "9:05AM") and the lines of neighbouring cells interleave. This module uses
the positions instead:

  1. each table is found by its header row (Section, Component, Days & Times, Room, ...), which
     also gives the x position of every column;
  2. each class is a row anchored by the class number in the first column; every other word is
     given to the nearest anchor vertically and to a column horizontally;
  3. each cell is read top to bottom and the common OCR confusions in times, dates, sections and
     components are repaired, since we know what kind of text each cell holds.

The output is the same flat text a copy-paste from the page would give, so timetable.parse_pasted
reads it. All of it is best effort: the caller shows the result for the student to check.
"""

import difflib
import re
from statistics import median

MAX_WORDS = 4000
MAX_WORD_LEN = 60
COLUMN_TOLERANCE_LINES = 1.1  # a word is in a column if it starts within this many text heights of the heading
ROW_REACH_LINES = 2.5  # how many text heights a word may be from its row's class number
KNOWN_COMPONENTS = ["Lecture", "Discussion", "Laboratory", "Lab", "Seminar", "Studio", "Section"]
COLUMNS = ("nbr", "section", "component", "days", "room", "instructor", "dates")


class OcrLayoutError(ValueError):
    """The words do not look like a MyUCSC class schedule table."""


class Word:
    __slots__ = ("text", "x0", "y0", "x1", "y1")

    def __init__(self, text, x0, y0, x1, y1):
        self.text, self.x0, self.y0, self.x1, self.y1 = text, x0, y0, x1, y1

    @property
    def yc(self):
        return (self.y0 + self.y1) / 2.0

    @property
    def height(self):
        return max(1.0, self.y1 - self.y0)


def clean_words(raw):
    """Validate word boxes from a client; returns a list of Word."""
    if not isinstance(raw, list):
        raise OcrLayoutError("words must be a list")
    if len(raw) > MAX_WORDS:
        raise OcrLayoutError(f"too many words (the limit is {MAX_WORDS})")
    words = []
    for w in raw:
        try:
            text = str(w["text"]).strip()
            box = [float(w[k]) for k in ("x0", "y0", "x1", "y1")]
        except (KeyError, TypeError, ValueError):
            raise OcrLayoutError("each word needs text, x0, y0, x1 and y1") from None
        if any(v != v or abs(v) > 100_000 for v in box):  # NaN or absurd
            raise OcrLayoutError("word positions are not valid numbers")
        if text and len(text) <= MAX_WORD_LEN:
            words.append(Word(text, *box))
    return words


# ---- small text repairs ---------------------------------------------------

_DIGITISH = str.maketrans({"O": "0", "o": "0", "Q": "0", "D": "0", "l": "1", "I": "1", "|": "1", "i": "1",
                           "S": "5", "B": "8", "Z": "2"})
# The hour needs a real digit (or a lone l/I for 1): otherwise the "o" in "Mo :05PM" would read as 0.
_TIME = re.compile(r"(?<![A-Za-z0-9])([0-9][0-9OolI|]?|[OolI|][0-9]|[lI|])\s*[:.;]\s*([0-9OolI|SB]{2})\s*([AaPp])\.?\s*[Mm]")
_DATE = re.compile(r"([0-9OolI|]{2})\s*[/\\|]\s*([0-9OolI|]{2})\s*[/\\|]\s*([0-9OolI|SB]{4})")
_DAYS_TOKEN = re.compile(r"^(?:M[o0O]|T[uU]|W[eE]|T[hHn]|F[rR]|S[aA]|S[uU])+$")
_DAY_FIX = {"M0": "Mo", "MO": "Mo", "MU": "Mo", "TU": "Tu", "WE": "We", "TH": "Th", "TN": "Th",
            "FR": "Fr", "SA": "Sa", "SU": "Su"}


def fix_digits(text):
    return text.translate(_DIGITISH)


def fix_times(cell):
    """Repair and standardise times in text like 'Mo 8:OOAM - 9:O5AM' -> ['8:00AM', '9:05AM'].
    A time that cannot be read as a real clock time (hour 1-12, minutes 0-59) is left out."""
    times = []
    for m in _TIME.finditer(cell):
        hh, mm = fix_digits(m.group(1)), fix_digits(m.group(2))
        if hh.isdigit() and mm.isdigit() and 1 <= int(hh) <= 12 and int(mm) <= 59:
            times.append(f"{int(hh)}:{mm}{m.group(3).upper()}M")
    return times


def fix_days(token):
    """'M0WeFr' -> 'MoWeFr'; returns None if the token is not made of day codes."""
    if not _DAYS_TOKEN.match(token):
        return None
    pairs = [token[i:i + 2] for i in range(0, len(token), 2)]
    fixed = [_DAY_FIX.get(p.upper()) for p in pairs]
    return "".join(fixed) if all(fixed) else None


def fix_dates(cell):
    dates = []
    for m in _DATE.finditer(cell):
        mm, dd, yyyy = (fix_digits(g) for g in m.groups())
        if (mm + dd + yyyy).isdigit():
            dates.append(f"{mm}/{dd}/{yyyy}")
    return dates


def fix_section(text):
    """'O01A' -> '01A'."""
    s = text.upper().replace("O", "0")
    m = re.search(r"\d{2}[A-Z]?$", s)
    return m.group(0) if m else ""


def fix_component(text):
    close = difflib.get_close_matches(text.title(), KNOWN_COMPONENTS, n=1, cutoff=0.6)
    return close[0] if close else text


_COURSE_LINE = re.compile(r"^([A-Z][A-Za-z&]{1,5} \d{1,3}[A-Z]{0,2})\s+(?:[-–—]\s*)?(.+)$")
_ROMAN_ENDING = re.compile(r"(?<=\s)[lI]{2,4}$")


def _tidy_course(text):
    """'XYZ 10 Sample Calculus lll' -> 'XYZ 10 - Sample Calculus III' (the dash is not read as a word, and
    capital I looks like lowercase L)."""
    text = _ROMAN_ENDING.sub(lambda m: "I" * len(m.group(0)), " ".join(text.split()))
    m = _COURSE_LINE.match(text)
    return f"{m.group(1)} - {m.group(2)}" if m else text


def fix_class_number(text):
    digits = "".join(ch for ch in fix_digits(text) if ch.isdigit())
    return digits if 4 <= len(digits) <= 5 else ""


# ---- finding the tables -------------------------------------------------

def _like(word, target, cutoff=0.75):
    return difflib.SequenceMatcher(None, word.lower(), target).ratio() >= cutoff


def _lines(words, line_height):
    """Group words into lines (top to bottom, left to right) and return the text of each."""
    lines, line_y = [], None
    for w in sorted(words, key=lambda w: (w.yc, w.x0)):
        if line_y is None or w.yc - line_y > line_height * 0.6:
            lines.append([])
            line_y = w.yc  # a line is measured from its first word
        lines[-1].append(w)
    return [" ".join(x.text for x in sorted(line, key=lambda w: w.x0)) for line in lines]


def _anchors_for(band):
    """Left edge of each column, from the words of one header row."""
    def left(match):
        found = [w for w in band if match(w.text)]
        return min((w.x0 for w in found), default=None)

    return {
        "nbr": left(lambda t: _like(t, "class")),
        "section": left(lambda t: _like(t, "section")),
        "component": left(lambda t: _like(t, "component")),
        "days": left(lambda t: _like(t, "days") or t.lower() == "&"),
        "room": left(lambda t: _like(t, "room")),
        "instructor": left(lambda t: _like(t, "instructor")),
        "dates": left(lambda t: t.lower().startswith("start") or _like(t, "start/end")),
    }


def read_table(words):
    """Rebuild the schedule as flat text. Returns (text, notes). Raises OcrLayoutError if there is
    no class table in the words."""
    words = [w for w in words if any(ch.isalnum() for ch in w.text)]
    if not words:
        raise OcrLayoutError("no text was found in the image")
    line_height = median(w.height for w in words)

    headers = sorted((w for w in words if _like(w.text, "component", 0.8)), key=lambda w: w.yc)
    if not headers:
        raise OcrLayoutError("couldn't find the class table (the row with Section, Component and Days & Times)")

    # A header row is the words level with "Component" and near it: a window of about 14 text
    # heights to its left keeps the page's menu ("Edit a Class") from being mistaken for the table.
    bands = [[w for w in words if abs(w.yc - h.yc) <= line_height * 1.8
              and h.x0 - 14 * line_height <= w.x0 <= h.x0 + 70 * line_height] for h in headers]
    found = [_anchors_for(b) for b in bands]
    anchors = {}
    for col in COLUMNS:
        values = [a[col] for a in found if a[col] is not None]
        if not values:
            raise OcrLayoutError(f"couldn't find the {col} column heading in the table")
        anchors[col] = median(values)  # the columns line up across all the tables on the page
    order = sorted(COLUMNS, key=lambda c: anchors[c])
    tolerance = COLUMN_TOLERANCE_LINES * line_height  # in the image's own pixels, so it scales
    left_edge = anchors[order[0]] - tolerance * 4

    def column_of(w):
        col = None
        for c in order:
            if w.x0 >= anchors[c] - tolerance:
                col = c
        return col

    # the "Status" word above each header marks the start of that course's block
    statuses = [w for w in words if _like(w.text, "status", 0.8) and w.x0 >= left_edge]
    blocks = []
    for h, band in zip(headers, bands):
        above = [s for s in statuses if s.yc < h.yc - line_height]
        status_word = max(above, key=lambda s: s.yc) if above else None
        blocks.append({"header": h, "band_bottom": max(w.y1 for w in band),
                       "status": status_word, "top": (status_word.y0 - line_height * 5) if status_word else h.y0})

    notes, out = [], []
    for i, block in enumerate(blocks):
        h = block["header"]
        next_top = blocks[i + 1]["top"] if i + 1 < len(blocks) else float("inf")
        table_words = [w for w in words if block["band_bottom"] < w.yc < next_top and w.x0 >= left_edge]

        # course name and status sit above the header, to the left
        course = ""
        status_text = "Enrolled"
        if block["status"]:
            s = block["status"]
            title_words = [w for w in words if s.y0 - line_height * 5 <= w.yc < s.y0 - 1
                           and w.x0 >= left_edge and (i == 0 or w.yc > blocks[i - 1]["band_bottom"])]
            course = " ".join(_lines(title_words, line_height)[-1:])
            course = _tidy_course(course)
            status_words = [w for w in words if s.y1 < w.yc < h.y0 - line_height and w.x0 >= left_edge
                            and w.x0 < anchors["section"]]
            found_status = [w.text for w in status_words
                            if difflib.get_close_matches(w.text.title(), ["Enrolled", "Dropped", "Waiting", "Waitlisted"],
                                                         n=1, cutoff=0.7)]
            if found_status:
                status_text = difflib.get_close_matches(found_status[0].title(),
                                                        ["Enrolled", "Dropped", "Waiting", "Waitlisted"], n=1)[0]
        else:
            notes.append(f"Couldn't read the course name above table {i + 1}.")

        # rows: anchored by a class number in the first column
        anchors_y = sorted((w for w in table_words
                            if column_of(w) == "nbr" and re.fullmatch(r"[0-9OolI|]{3,6}", w.text)
                            and abs(w.x0 - anchors["nbr"]) <= 7 * line_height), key=lambda w: w.yc)
        if not anchors_y:
            notes.append(f"No classes found under {course or f'table {i + 1}'}.")
            continue
        reach = line_height * ROW_REACH_LINES
        rows = [[] for _ in anchors_y]
        for w in table_words:
            nearest = min(range(len(anchors_y)), key=lambda k: abs(anchors_y[k].yc - w.yc))
            if abs(anchors_y[nearest].yc - w.yc) <= reach and column_of(w):
                rows[nearest].append(w)

        row_texts = []
        for anchor, row in zip(anchors_y, rows):
            cells = {c: [w for w in row if column_of(w) == c] for c in COLUMNS}
            cell = {c: " ".join(_lines(cells[c], line_height)) for c in COLUMNS}
            nbr = fix_class_number(cell["nbr"]) or "0000"
            days = next((fix_days(t) for t in cell["days"].split() if fix_days(t)), None)
            times = fix_times(cell["days"])
            dates = fix_dates(cell["dates"])
            if len(times) == 2 and days:
                when = f"{days} {times[0]} - {times[1]}"
            else:  # leave it as read; the parser will report a row it cannot use
                when = cell["days"]
            row_texts.append(" ".join([
                nbr, fix_section(cell["section"]) or "00", fix_component(cell["component"]), when.strip(),
                cell["room"], cell["instructor"],
                f"{dates[0]} - {dates[1]}" if len(dates) == 2 else cell["dates"]]))

        prefix = f"{course} " if course else ""
        out.append(f"{prefix}Status Units Grading Grade Deadlines {status_text} 5.00 Graded " + " ".join(row_texts))
    return "\n".join(out), notes
