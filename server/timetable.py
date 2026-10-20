"""Class schedules: import, validate, and work out what is happening now and next.

A schedule is a list of meetings (plain dicts, so they travel as JSON):

    {"course": "XYZ 10", "title": "Sample Calculus", "section": "01", "component": "Lecture",
     "class_nbr": "20002", "days": [0, 2, 4], "start": "14:40", "end": "15:45",
     "location": "Kresge Acad 3201", "start_date": "2026-09-24", "end_date": "2026-12-04"}

`days` are Python weekdays (0 = Monday). A meeting with no days is a one-off event on
start_date. An optional `skip_dates` lists dates it does not meet. Instructor names are deliberately not kept.

The functions here are pure: walking times come in through a `walker` callable, so this
module has no idea about maps or the routing engine.
"""

import math
import re
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

try:
    TZ = ZoneInfo("America/Los_Angeles")
except ZoneInfoNotFoundError:  # Windows has no system time zone database
    raise RuntimeError("Time zone data is missing. Install it with: python -m pip install tzdata") from None
DAY_CODES = ("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su")
WALK_SPEED_M_PER_S = 1.3
TIGHT_MINUTES = 5  # less spare time than this counts as a tight transition
SEARCH_DAYS = 21  # how far ahead to look for the next class

MAX_MEETINGS = 60
MAX_SKIP_DATES = 60
MAX_TEXT = 100_000


class ScheduleError(ValueError):
    """A schedule or meeting that cannot be used (the message is safe to show a user)."""


# ---- validating meetings -------------------------------------------------

def _text(raw, key, max_len, required=False):
    value = raw.get(key, "")
    if value is None:
        value = ""
    if not isinstance(value, (str, int)):
        raise ScheduleError(f"{key} must be text")
    value = " ".join(str(value).split())
    if required and not value:
        raise ScheduleError(f"{key} is required")
    if len(value) > max_len:
        raise ScheduleError(f"{key} is too long")
    return value


def _clock(value, key):
    try:
        return time.fromisoformat(value).strftime("%H:%M")
    except (TypeError, ValueError):
        raise ScheduleError(f"{key} must look like 14:40") from None


def _day(value, key):
    try:
        return date.fromisoformat(value).isoformat()
    except (TypeError, ValueError):
        raise ScheduleError(f"{key} must look like 2026-09-24") from None


def clean_meeting(raw):
    """Validate one meeting from a client and return a normalized copy."""
    if not isinstance(raw, dict):
        raise ScheduleError("each meeting must be an object")
    days = raw.get("days", [])
    if not isinstance(days, list) or not all(isinstance(d, int) and 0 <= d <= 6 for d in days):
        raise ScheduleError("days must be a list of weekday numbers, 0 (Monday) to 6 (Sunday)")
    skip = raw.get("skip_dates", [])
    if not isinstance(skip, list) or len(skip) > MAX_SKIP_DATES:
        raise ScheduleError(f"skip_dates must be a list of at most {MAX_SKIP_DATES} dates")
    meeting = {
        "course": _text(raw, "course", 40, required=True),
        "title": _text(raw, "title", 80),
        "section": _text(raw, "section", 10),
        "component": _text(raw, "component", 30),
        "class_nbr": _text(raw, "class_nbr", 10),
        "days": sorted(set(days)),
        "start": _clock(raw.get("start"), "start"),
        "end": _clock(raw.get("end"), "end"),
        "location": _text(raw, "location", 80),
        "start_date": _day(raw.get("start_date"), "start_date"),
        "end_date": _day(raw.get("end_date"), "end_date"),
    }
    skip_dates = sorted({_day(d, "skip_dates") for d in skip})
    if skip_dates:  # dates this class does not meet (for example a cancelled day); left out when empty
        meeting["skip_dates"] = skip_dates
    if meeting["end"] <= meeting["start"]:
        raise ScheduleError(f"{meeting['course']}: the end time must be after the start time")
    if meeting["end_date"] < meeting["start_date"]:
        raise ScheduleError(f"{meeting['course']}: the end date is before the start date")
    if not meeting["days"] and meeting["start_date"] != meeting["end_date"]:
        raise ScheduleError(f"{meeting['course']}: pick the days it meets, or use one date for a one-off event")
    return meeting


def clean_schedule(raw_meetings):
    if not isinstance(raw_meetings, list):
        raise ScheduleError("meetings must be a list")
    if len(raw_meetings) > MAX_MEETINGS:
        raise ScheduleError(f"too many meetings (the limit is {MAX_MEETINGS})")
    return [clean_meeting(m) for m in raw_meetings]


# ---- importing pasted text -----------------------------------------------

_COURSE = re.compile(r"(?P<course>[A-Z][A-Z&]{1,5} \d{1,3}[A-Z]{0,2}) - (?P<title>.+?) Status Units")
_STATUS = re.compile(r"Status Units Grading Grade Deadlines (?P<status>Enrolled|Dropped|Waiting|Wait Listed)")
_ROW = re.compile(
    r"(?P<nbr>\d{4,5}) (?P<section>\d{2}[A-Z]?) (?P<component>[A-Za-z]+) "
    r"(?P<days>(?:Mo|Tu|We|Th|Fr|Sa|Su)+) "
    r"(?P<t1>\d{1,2}:\d{2}\s?[AP]M) ?[-–—]? ?(?P<t2>\d{1,2}:\d{2}\s?[AP]M) "
    r"(?P<rest>.*?)\s*(?P<d1>\d{2}/\d{2}/\d{4}) ?- ?(?P<d2>\d{2}/\d{2}/\d{4})")
_ROW_START = re.compile(r"\b\d{4,5} \d{2}[A-Z]? (?:Lecture|Discussion|Laboratory|Lab|Seminar|Studio|Section)\b")


def _to_24h(text):
    return datetime.strptime(text.replace(" ", ""), "%I:%M%p").strftime("%H:%M")


def _us_date(text):
    return datetime.strptime(text, "%m/%d/%Y").date().isoformat()


def parse_pasted(text, campus):
    """Read a schedule copied from MyUCSC's "Class Schedule" page.

    Returns (meetings, notes). Whitespace and line breaks do not matter, so it copes
    with however the browser flattens the table. Dropped and waitlisted courses are
    left out, and anything that looks like a class row but could not be read is
    reported in notes rather than silently ignored.
    """
    if not isinstance(text, str) or not text.strip():
        raise ScheduleError("paste your schedule first")
    if len(text) > MAX_TEXT:
        raise ScheduleError("that text is too long to be a schedule")
    flat = " ".join(text.split())

    headers = [(m.start(), m.group("course"), m.group("title")) for m in _COURSE.finditer(flat)]
    statuses = [(m.start(), m.group("status")) for m in _STATUS.finditer(flat)]

    meetings, notes, claimed = [], [], []
    for m in _ROW.finditer(flat):
        claimed.append((m.start(), m.end()))
        before = [h for h in headers if h[0] < m.start()]
        course, title = (before[-1][1], before[-1][2]) if before else (f"Class {m.group('nbr')}", "")
        status = "Enrolled"
        if before:
            after_header = [s for s in statuses if before[-1][0] < s[0] < m.start()]
            status = after_header[-1][1] if after_header else "Enrolled"
        if status != "Enrolled":
            notes.append(f"Skipped {course} ({status.lower()}).")
            continue
        days = m.group("days")
        location, _instructor = campus.split_location(m.group("rest"))
        try:
            meetings.append(clean_meeting({
                "course": course, "title": title, "section": m.group("section"),
                "component": m.group("component"), "class_nbr": m.group("nbr"),
                "days": [DAY_CODES.index(days[i:i + 2]) for i in range(0, len(days), 2)],
                "start": _to_24h(m.group("t1")), "end": _to_24h(m.group("t2")),
                "location": location,
                "start_date": _us_date(m.group("d1")), "end_date": _us_date(m.group("d2")),
            }))
        except (ScheduleError, ValueError) as e:
            notes.append(f"Couldn't read {course} {m.group('component')}: {e}.")

    for m in _ROW_START.finditer(flat):
        if not any(a <= m.start() < b for a, b in claimed):
            notes.append(f"Couldn't read a row starting \"{flat[m.start():m.start() + 50]}\".")
    if not meetings and not notes:
        notes.append("I couldn't find any classes in that text. Copy the whole Class Schedule page, or add classes by hand.")
    return meetings, notes


# ---- terms ---------------------------------------------------------------

def parse_terms(raw):
    """Validate the `terms` list from data/holidays.json: [{name, start, end, holidays}], sorted by start."""
    terms = []
    for t in raw or []:
        term = {"name": t.get("name", ""), "start": _day(t.get("start"), "start"), "end": _day(t.get("end"), "end"),
                "holidays": sorted({_day(d, "holidays") for d in t.get("holidays", [])})}
        if term["end"] < term["start"]:
            raise ScheduleError(f"term {term['name']!r} ends before it starts")
        terms.append(term)
    return sorted(terms, key=lambda t: t["start"])


def term_for(terms, day):
    """The term containing `day`; otherwise the next one to start, otherwise the last; None if there are none."""
    if not terms:
        return None
    iso = day.isoformat()
    for t in terms:
        if t["start"] <= iso <= t["end"]:
            return t
    return next((t for t in terms if t["start"] > iso), terms[-1])


def holidays_of(terms):
    return frozenset(date.fromisoformat(d) for t in terms for d in t["holidays"])


# ---- what happens on a given day ----------------------------------------

def occurs_on(meeting, day, holidays=frozenset()):
    if not date.fromisoformat(meeting["start_date"]) <= day <= date.fromisoformat(meeting["end_date"]):
        return False
    if day.isoformat() in meeting.get("skip_dates", ()):
        return False
    if not meeting["days"]:  # one-off event: runs even on a holiday
        return day == date.fromisoformat(meeting["start_date"])
    return day not in holidays and day.weekday() in meeting["days"]


def occurrences(meetings, day, holidays=frozenset()):
    """Meetings that happen on `day`, as (start, end, meeting) with aware datetimes, in time order."""
    found = []
    for m in meetings:
        if occurs_on(m, day, holidays):
            start = datetime.combine(day, time.fromisoformat(m["start"]), tzinfo=TZ)
            end = datetime.combine(day, time.fromisoformat(m["end"]), tzinfo=TZ)
            found.append((start, end, m))
    return sorted(found, key=lambda o: (o[0], o[1]))


def _why_no_classes(meetings, day, holidays):
    if not meetings:
        return "no_schedule"
    first = min(date.fromisoformat(m["start_date"]) for m in meetings)
    last = max(date.fromisoformat(m["end_date"]) for m in meetings)
    if day in holidays:
        return "holiday"
    if day < first:
        return "before_term"
    if day > last:
        return "after_term"
    if day.weekday() >= 5:
        return "weekend"
    return "no_classes"


def next_occurrence(meetings, now, holidays=frozenset()):
    """The first class that starts after `now`, today or within the next three weeks."""
    if not meetings:
        return None
    first = min(date.fromisoformat(m["start_date"]) for m in meetings)
    for offset in range(SEARCH_DAYS + 1):  # before the term starts, look from its first day
        day = max(now.date(), first) + timedelta(days=offset)
        for occ in occurrences(meetings, day, holidays):
            if occ[0] > now:
                return occ
    return None


# ---- the "today" analysis -------------------------------------------------

def _seconds(later, earlier):
    """Real seconds from earlier to later. Moments that share a time zone subtract their wall clocks,
    which is an hour out when the clocks change in between."""
    return (later.astimezone(timezone.utc) - earlier.astimezone(timezone.utc)).total_seconds()


def _minutes(later, earlier):
    return _seconds(later, earlier) / 60.0


def _spare_status(free_min):
    if free_min is None:
        return "unknown"
    if free_min < 0:
        return "late"
    if free_min < TIGHT_MINUTES:
        return "tight"
    return "ok"


def _occ_dict(occ, now=None):
    start, end, m = occ
    d = {k: m[k] for k in ("course", "title", "section", "component", "location")}
    d["start"], d["end"] = start.isoformat(), end.isoformat()
    if now is not None:
        d["starts_in_min"] = round(_minutes(start, now), 1)
        d["minutes_left"] = round(_minutes(end, now), 1)
    return d


def walk_minutes(effort_m):
    """Whole minutes to walk this much climb-adjusted distance."""
    return math.ceil(effort_m / WALK_SPEED_M_PER_S / 60.0)


def _walk_info(walker, origin, destination):
    """Ask the walker for a walk; returns the result plus whole minutes, or None."""
    if walker is None or origin is None:
        return None
    result = walker(origin, destination)
    if result is None:
        return None
    indoor = result.get("indoor_m", 0.0)
    meters = result["meters"] + indoor
    effort = result.get("effective_m", result["meters"]) + indoor  # climbs make a walk take longer
    return {**result, "total_m": round(meters, 1),
            "minutes": walk_minutes(effort)}


def _clock12(moment):
    return f"{moment.hour % 12 or 12}:{moment.minute:02d} {'AM' if moment.hour < 12 else 'PM'}"


def _stage_reminders(item, now, lead_min, sent, allow_late):
    """The heads-up and "leave now" reminders still to come for one class."""
    start, leave = item["start"], item["leave"]
    details = f"{item['location']}: about {item['minutes']} min on foot. Class starts at {_clock12(start)}."
    titles = {"heads-up": f"Leave in {lead_min} min for {item['name']}",
              "leave": f"Time to leave for {item['name']}",
              "late": f"Leave now, you're running late for {item['name']}"}
    stages = [("heads-up", leave - timedelta(minutes=lead_min))] if lead_min > 0 else []
    stages.append(("leave", leave))
    reminders = []
    for stage, at in stages:
        key = f"{start.isoformat()}|{stage}"
        if key in sent:
            continue
        seconds = _seconds(at, now)
        if seconds >= 0:
            reminders.append({"stage": stage, "key": key, "in_seconds": round(seconds, 1),
                              "title": titles[stage], "body": details})
        elif stage == "leave" and allow_late:
            reminders.append({"stage": "late", "key": key, "in_seconds": 0.0,
                              "title": titles["late"], "body": details})
    return reminders


def plan_reminders(out, now, lead_min, sent=()):
    """When to tell the student to leave for each class still to come today, from an analysis made by analyze().

    Returns (reminders, banner). `reminders` are notifications still to come, each with the
    seconds from now to show it, in time order; `banner` is a message for the page itself about
    the next class, or None.

    A heads-up (lead_min minutes before leaving; none if lead_min is 0) whose time has passed is
    dropped. For the next class, a "leave now" whose time has passed while the class has not
    started is returned once, as "late", to be shown straight away. A later class is walked to
    from the one before it, so it is never reminded before that one ends. `sent` holds keys
    already shown, so nothing repeats. Needs a walk to time, so there is nothing for a class
    tomorrow, an online class or an unknown room.
    """
    nxt, walk = out["next"], out["walk"]
    if not nxt or not nxt["is_today"]:
        return [], None
    first_start = datetime.fromisoformat(nxt["start"])
    if now >= first_start:
        return [], None

    def name_of(c):
        return " ".join(x for x in (c["course"], c["component"]) if x)

    items = []
    if walk and out["leave_by"]:
        items.append({"name": name_of(nxt), "location": nxt["location"], "start": first_start,
                      "leave": datetime.fromisoformat(out["leave_by"]), "minutes": walk["minutes"], "late_ok": True})
    later = [t for t in out["today"] if datetime.fromisoformat(t["start"]) > first_start]
    for t in later:
        if "walk_min" not in t:
            continue
        before = [p for p in out["today"] if datetime.fromisoformat(p["start"]) < datetime.fromisoformat(t["start"])]
        free_from = max(datetime.fromisoformat(p["end"]) for p in before)
        start = datetime.fromisoformat(t["start"])
        leave = max(start - timedelta(minutes=t["walk_min"]), free_from)
        items.append({"name": name_of(t), "location": t["location"], "start": start, "leave": leave,
                      "minutes": t["walk_min"], "late_ok": False})

    reminders = []
    for item in items:
        reminders += _stage_reminders(item, now, lead_min, sent, item["late_ok"])
    reminders.sort(key=lambda r: r["in_seconds"])

    banner = None
    if items and items[0]["late_ok"]:
        leave, minutes = items[0]["leave"], items[0]["minutes"]
        name = items[0]["name"]
        if now >= leave - timedelta(minutes=max(lead_min, 5)):
            if now >= leave:
                text = f"Leave now for {name}: it is a {minutes} min walk and class starts at {_clock12(first_start)}."
            else:
                minutes_left = math.ceil(_minutes(leave, now))
                text = (f"Leave in {minutes_left} min for {name} "
                        f"({minutes} min walk, class at {_clock12(first_start)}).")
            banner = {"text": text, "late": now >= leave and out["status"] == "late"}
    return reminders, banner


def _state_of(today, current, upcoming, previous):
    if current:
        return "in_class"
    if upcoming:
        return "between_classes" if previous else "before_classes"
    return "done_for_today" if today else "no_classes_today"


def _walk_to_next(out, nxt, now, current, previous, here, walker):
    """Fill in the next class and, when it is today, the walk to it, the time to spare and when to leave."""
    out["next"] = _occ_dict(nxt, now)
    out["next"]["is_today"] = nxt[0].date() == now.date()
    origin, spare_from = None, now
    if current:  # finish this class, then walk
        origin, spare_from = ("room", current[2]["location"]), current[1]
    elif here is not None:
        origin = ("point", here[0], here[1])
    elif previous:
        origin = ("room", previous[2]["location"])
    # A walk only matters when the class is today; "18 hours of free time" before a
    # class tomorrow would just be noise.
    walk = _walk_info(walker, origin, nxt[2]["location"]) if out["next"]["is_today"] else None
    if walk:
        free = _minutes(nxt[0], spare_from) - walk["minutes"]
        out["walk"] = {"minutes": walk["minutes"], "meters": walk["total_m"],
                       "from": "current_class" if current else ("here" if here else "previous_class")}
        out["free_min"] = round(free, 1)
        out["status"] = _spare_status(free)
        out["leave_by"] = (nxt[0] - timedelta(minutes=walk["minutes"])).isoformat()
    elif out["next"]["is_today"] and nxt[2]["location"]:
        out["notes"].append("I can't work out the walk to that class (online, TBA, or an unknown room).")


def _timeline(today, walker):
    """Today's classes as rows, each with the gap and the walk from the class before it."""
    rows = []
    for i, occ in enumerate(today):
        item = _occ_dict(occ)
        if i > 0:
            prev = today[i - 1]
            gap = _minutes(occ[0], prev[1])
            walk = _walk_info(walker, ("room", prev[2]["location"]), occ[2]["location"])
            item["gap_min"] = round(gap, 1)
            if walk:
                item["walk_min"] = walk["minutes"]
                item["free_min"] = round(gap - walk["minutes"], 1)
            item["status"] = _spare_status(item.get("free_min"))
        rows.append(item)
    return rows


def analyze(meetings, now, holidays=frozenset(), walker=None, here=None, remind=None):
    """Summarise where the student is in their day.

    now     aware datetime (America/Los_Angeles).
    walker  walker(origin, destination_text) -> {"meters", "indoor_m"} or None, where origin
            is ("point", lat, lon) or ("room", text).
    here    (lat, lon) of the student, if known.
    remind  {"lead_min": int, "sent": [keys]} to also plan "time to leave" reminders
            (see plan_reminders); leave None for no reminder fields.
    """
    now = now.astimezone(TZ)
    today = occurrences(meetings, now.date(), holidays)
    current = next((o for o in today if o[0] <= now < o[1]), None)
    previous = next((o for o in reversed(today) if o[1] <= now), None)
    upcoming = [o for o in today if o[0] > now]
    nxt = upcoming[0] if upcoming else next_occurrence(meetings, now, holidays)

    out = {"now": now.isoformat(), "state": _state_of(today, current, upcoming, previous),
           "reason": None if today else _why_no_classes(meetings, now.date(), holidays),
           "current": _occ_dict(current, now) if current else None,
           "next": None, "walk": None, "free_min": None, "status": "unknown",
           "leave_by": None, "today": [], "notes": []}
    if nxt:
        _walk_to_next(out, nxt, now, current, previous, here, walker)
    out["today"] = _timeline(today, walker)
    if remind is not None:
        out["reminders"], out["banner"] = plan_reminders(out, now, remind["lead_min"], set(remind["sent"]))
    return out
