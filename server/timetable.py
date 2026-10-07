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
from datetime import date, datetime, time, timedelta
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


def meetings_from_extraction(data, term=None):
    """Turn a schedule transcribed from an image into validated meetings.

    `data` is {"classes": [...], "notes": [...]} as produced by photo.py. Anything that
    is not a plain enrolled class, or fails validation, is reported in notes and left out,
    so a misread row never silently becomes a wrong class. `term` ({"start", "end"}) fills in
    dates the image did not show.
    """
    notes = [f"From the photo: {n}" for n in data.get("notes", []) if isinstance(n, str) and n.strip()]
    meetings, used_term = [], False
    for row in data.get("classes", [])[:MAX_MEETINGS]:
        if not isinstance(row, dict):
            continue
        name = " ".join(str(row.get("course") or "A class").split())
        status = " ".join(str(row.get("status") or "enrolled").split()).lower()
        if status != "enrolled":
            notes.append(f"Skipped {name} ({status}).")
            continue
        try:
            days = [DAY_CODES.index(d) for d in row.get("days") or []]
        except ValueError:
            notes.append(f"Couldn't read the days for {name}.")
            continue
        start_date, end_date = row.get("start_date") or "", row.get("end_date") or ""
        if (not start_date or not end_date) and term:
            start_date, end_date, used_term = term["start"], term["end"], True
        try:
            meetings.append(clean_meeting({
                "course": name, "title": row.get("title"), "section": row.get("section"),
                "component": row.get("component"), "class_nbr": row.get("class_nbr"),
                "days": days, "start": row.get("start"), "end": row.get("end"),
                "location": row.get("location"), "start_date": start_date, "end_date": end_date}))
        except ScheduleError as e:
            notes.append(f"Couldn't use {name} {row.get('component') or ''}".rstrip() + f": {e}.")
    if used_term:
        notes.append("Some classes showed no dates, so I used the term dates.")
    if not meetings and not notes:
        notes.append("I couldn't find any classes in that image.")
    return meetings, notes


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

def _minutes(delta):
    return delta.total_seconds() / 60.0


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
        d["starts_in_min"] = round(_minutes(start - now), 1)
        d["minutes_left"] = round(_minutes(end - now), 1)
    return d


def _walk_info(walker, origin, destination):
    """Ask the walker for a walk; returns the result plus whole minutes, or None."""
    if walker is None or origin is None:
        return None
    result = walker(origin, destination)
    if result is None:
        return None
    meters = result["meters"] + result.get("indoor_m", 0.0)
    return {**result, "total_m": round(meters, 1),
            "minutes": math.ceil(meters / WALK_SPEED_M_PER_S / 60.0)}


def _clock12(moment):
    return f"{moment.hour % 12 or 12}:{moment.minute:02d} {'AM' if moment.hour < 12 else 'PM'}"


def plan_reminders(out, now, lead_min, sent=()):
    """When to tell the student to leave for their next class, from an analysis made by analyze().

    Returns (reminders, banner). `reminders` are notifications still to come, each with the
    seconds from now to show it; `banner` is a message for the page itself, or None.

    A heads-up (lead_min minutes before leaving; none if lead_min is 0) whose time has passed is
    dropped. A "leave now" whose time has passed while the class has not started is returned
    once, as "late", to be shown straight away. `sent` holds keys already shown, so nothing
    repeats. Needs a walk to time, so there is nothing for a class tomorrow or an unknown room.
    """
    nxt, walk = out["next"], out["walk"]
    if not nxt or not nxt["is_today"] or not walk or not out["leave_by"]:
        return [], None
    start = datetime.fromisoformat(nxt["start"])
    leave = datetime.fromisoformat(out["leave_by"])
    if now >= start:
        return [], None

    name = " ".join(x for x in (nxt["course"], nxt["component"]) if x)
    details = f"{nxt['location']}: about {walk['minutes']} min on foot. Class starts at {_clock12(start)}."
    titles = {"heads-up": f"Leave in {lead_min} min for {name}", "leave": f"Time to leave for {name}",
              "late": f"Leave now, you're running late for {name}"}
    stages = [("heads-up", leave - timedelta(minutes=lead_min))] if lead_min > 0 else []
    stages.append(("leave", leave))

    reminders = []
    for stage, at in stages:
        key = f"{nxt['start']}|{stage}"
        if key in sent:
            continue
        seconds = (at - now).total_seconds()
        if seconds >= 0:
            reminders.append({"stage": stage, "key": key, "in_seconds": round(seconds, 1),
                              "title": titles[stage], "body": details})
        elif stage == "leave":
            reminders.append({"stage": "late", "key": key, "in_seconds": 0.0,
                              "title": titles["late"], "body": details})

    banner = None
    if now >= leave - timedelta(minutes=max(lead_min, 5)):
        if now >= leave:
            text = f"Leave now for {name}: it is a {walk['minutes']} min walk and class starts at {_clock12(start)}."
        else:
            minutes_left = math.ceil((leave - now).total_seconds() / 60)
            text = (f"Leave in {minutes_left} min for {name} "
                    f"({walk['minutes']} min walk, class at {_clock12(start)}).")
        banner = {"text": text, "late": now >= leave and out["status"] == "late"}
    return reminders, banner


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

    if current:
        state = "in_class"
    elif upcoming:
        state = "between_classes" if previous else "before_classes"
    elif today:
        state = "done_for_today"
    else:
        state = "no_classes_today"

    out = {"now": now.isoformat(), "state": state,
           "reason": None if today else _why_no_classes(meetings, now.date(), holidays),
           "current": _occ_dict(current, now) if current else None,
           "next": None, "walk": None, "free_min": None, "status": "unknown",
           "leave_by": None, "today": [], "notes": []}

    if nxt:
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
            free = _minutes(nxt[0] - spare_from) - walk["minutes"]
            out["walk"] = {"minutes": walk["minutes"], "meters": walk["total_m"],
                           "from": "current_class" if current else ("here" if here else "previous_class")}
            out["free_min"] = round(free, 1)
            out["status"] = _spare_status(free)
            out["leave_by"] = (nxt[0] - timedelta(minutes=walk["minutes"])).isoformat()
        elif out["next"]["is_today"] and nxt[2]["location"]:
            out["notes"].append("I can't work out the walk to that class (online, TBA, or an unknown room).")

    if remind is not None:
        out["reminders"], out["banner"] = plan_reminders(out, now, remind["lead_min"], set(remind["sent"]))

    for i, occ in enumerate(today):
        item = _occ_dict(occ)
        if i > 0:
            prev = today[i - 1]
            gap = _minutes(occ[0] - prev[1])
            walk = _walk_info(walker, ("room", prev[2]["location"]), occ[2]["location"])
            item["gap_min"] = round(gap, 1)
            if walk:
                item["walk_min"] = walk["minutes"]
                item["free_min"] = round(gap - walk["minutes"], 1)
            item["status"] = _spare_status(item.get("free_min"))
        out["today"].append(item)
    return out
