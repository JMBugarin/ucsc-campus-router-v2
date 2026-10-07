"""Read class meetings from an iCalendar (.ics) file.

Calendars exported from Google Calendar, Apple Calendar, Canvas and the like describe a weekly
class as one event with a recurrence rule ("every Monday, Wednesday and Friday until Dec 4"),
possibly with skipped dates. This module turns those into the app's meetings (see timetable.py).

It supports what a class timetable needs: weekly rules with BYDAY, UNTIL or COUNT, skipped dates
(EXDATE), one-off events, UTC / named-zone / floating times, and DTEND or DURATION. Anything it
cannot represent faithfully (daily or every-other-week repeats, changed single occurrences, all-day
or overnight events, cancelled events) is left out and reported in the notes, never guessed.
Standard library only.
"""

import re
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import timetable

MAX_ICS_CHARS = 1_000_000
MAX_EVENTS = 500
DEFAULT_WEEKS = 16  # how long an open-ended weekly event runs when there is no term to end it
MAX_EXPANSION_DAYS = 3 * 366

# Names that calendar programs use for Pacific time besides the standard one.
ZONE_ALIASES = {"Pacific Standard Time": "America/Los_Angeles", "Pacific Daylight Time": "America/Los_Angeles",
                "US/Pacific": "America/Los_Angeles", "PST8PDT": "America/Los_Angeles"}
DAY_CODES = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}
COMPONENT = re.compile(r"^(?P<course>.*?)[\s:\-\u2013\u2014]+(?P<component>Lecture|Discussion|Laboratory|Lab|"
                       r"Seminar|Section|Studio)\b", re.IGNORECASE)
DURATION = re.compile(r"^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$")


# ---- reading the file --------------------------------------------------------

def split_property(line):
    """'DTSTART;TZID=X:2026...' -> ('DTSTART', {'TZID': 'X'}, '2026...'); None if there is no colon."""
    in_quotes = False
    for i, ch in enumerate(line):
        if ch == '"':
            in_quotes = not in_quotes
        elif ch == ":" and not in_quotes:
            head, value = line[:i], line[i + 1:]
            break
    else:
        return None
    parts = head.split(";")
    params = {}
    for part in parts[1:]:
        key, _, val = part.partition("=")
        params[key.upper()] = val.strip('"')
    return parts[0].upper(), params, value


def unescape(text):
    return re.sub(r"\\(.)", lambda m: "\n" if m.group(1) in "nN" else m.group(1), text)


def read_events(text):
    """The properties of each VEVENT, as lists of (name, params, value)."""
    lines = re.sub(r"\r?\n[ \t]", "", text).replace("\r\n", "\n").replace("\r", "\n").split("\n")
    events, current, nested = [], None, 0
    for line in lines:
        prop = split_property(line.strip())
        if prop is None:
            continue
        name, params, value = prop
        if name == "BEGIN" and value.upper() == "VEVENT":
            current, nested = [], 0
        elif current is None:
            continue
        elif name == "BEGIN":
            nested += 1  # an alarm or similar inside the event
        elif name == "END" and value.upper() == "VEVENT":
            events.append(current)
            current = None
        elif name == "END":
            nested -= 1
        elif nested == 0:
            current.append((name, params, value))
    return events


# ---- dates and times ------------------------------------------------------------

class _Reader:
    """Converts calendar times to Pacific time, remembering what it had to assume."""

    def __init__(self):
        self.notes = []

    def zone(self, name):
        try:
            return ZoneInfo(ZONE_ALIASES.get(name, name))
        except (ZoneInfoNotFoundError, ValueError):
            note = f"The calendar uses a time zone I don't know ({name}), so I treated those times as Pacific time."
            if note not in self.notes:
                self.notes.append(note)
            return timetable.TZ

    def moment(self, value, params, default_zone=None):
        """A datetime in Pacific time, or a date for an all-day value, or None if unreadable."""
        value = value.strip()
        if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
            try:
                return datetime.strptime(value, "%Y%m%d").date()
            except ValueError:
                return None
        m = re.fullmatch(r"(\d{8}T\d{6})(Z?)", value)
        if not m:
            return None
        try:
            naive = datetime.strptime(m.group(1), "%Y%m%dT%H%M%S")
        except ValueError:
            return None
        if m.group(2):
            return naive.replace(tzinfo=timezone.utc).astimezone(timetable.TZ)
        zone = self.zone(params["TZID"]) if "TZID" in params else (default_zone or timetable.TZ)
        return naive.replace(tzinfo=zone).astimezone(timetable.TZ)


def parse_duration(value):
    m = DURATION.match(value.strip())
    if not m or not any(m.groups()[1:]):
        return None
    sign = -1 if m.group(1) == "-" else 1
    weeks, days, hours, minutes, seconds = (int(g or 0) for g in m.groups()[1:])
    return sign * timedelta(weeks=weeks, days=days, hours=hours, minutes=minutes, seconds=seconds)


def parse_rrule(value):
    rule = {}
    for part in value.split(";"):
        key, _, val = part.partition("=")
        rule[key.upper()] = val
    return rule


# ---- one event -> one meeting ------------------------------------------------------

def event_to_meeting(props, term, reader):
    """Returns a meeting dict, or None after adding a note about why the event was left out."""
    notes = reader.notes

    def first(name):
        return next((p for p in props if p[0] == name), None)

    summary = " ".join(unescape(first("SUMMARY")[2] if first("SUMMARY") else "").split()) or "Event"
    if first("STATUS") and first("STATUS")[2].strip().upper() == "CANCELLED":
        notes.append(f"Skipped \"{summary}\" (cancelled).")
        return None
    if first("RECURRENCE-ID"):
        notes.append(f"Skipped a changed single day of \"{summary}\"; edit that day by hand if you need it.")
        return None

    start_prop = first("DTSTART")
    start = reader.moment(start_prop[2], start_prop[1]) if start_prop else None
    if start is None:
        notes.append(f"Skipped \"{summary}\" (couldn't read when it starts).")
        return None
    if not isinstance(start, datetime):
        notes.append(f"Skipped \"{summary}\" (an all-day event, not a class).")
        return None
    start_zone = reader.zone(start_prop[1]["TZID"]) if start_prop[1].get("TZID") else None

    end = None
    if first("DTEND"):
        end = reader.moment(first("DTEND")[2], first("DTEND")[1], start_zone)
    elif first("DURATION") and parse_duration(first("DURATION")[2]):
        end = start + parse_duration(first("DURATION")[2])
    if not isinstance(end, datetime) or end <= start:
        notes.append(f"Skipped \"{summary}\" (couldn't read when it ends).")
        return None
    if end.date() != start.date():
        notes.append(f"Skipped \"{summary}\" (it runs past midnight, so it isn't a class).")
        return None

    days, start_date, end_date, skip = [], start.date(), start.date(), []
    rrule = first("RRULE")
    if rrule:
        rule = parse_rrule(rrule[2])
        interval = rule.get("INTERVAL", "1")
        if rule.get("FREQ") != "WEEKLY" or interval != "1":
            notes.append(f"Skipped \"{summary}\" (it repeats {rule.get('FREQ', 'oddly').lower()}"
                         f"{'' if interval == '1' else ' every ' + interval}, and I only handle every week).")
            return None
        byday = [d for d in rule.get("BYDAY", "").split(",") if d]
        if any(d not in DAY_CODES for d in byday):
            notes.append(f"Skipped \"{summary}\" (it repeats on days like 'the first Monday', which I can't handle).")
            return None
        days = sorted({DAY_CODES[d] for d in byday}) or [start.weekday()]
        start_date = start.date()

        until = None
        if rule.get("UNTIL"):
            moment = reader.moment(rule["UNTIL"], {}, start_zone)
            until = moment.date() if moment is not None else None
        if rule.get("COUNT", "").isdigit() and int(rule["COUNT"]) > 0:
            seen, day = 0, start.date()
            for _ in range(MAX_EXPANSION_DAYS):
                if day.weekday() in days:
                    seen += 1
                    until = day
                    if seen >= int(rule["COUNT"]):
                        break
                day += timedelta(days=1)
        if until is None:
            if term:
                until = max(date.fromisoformat(term["end"]), start.date())
                notes.append(f"\"{summary}\" repeats with no end date, so I ended it with the term.")
            else:
                until = start.date() + timedelta(weeks=DEFAULT_WEEKS)
                notes.append(f"\"{summary}\" repeats with no end date, so I stopped it after {DEFAULT_WEEKS} weeks.")
        end_date = until

        for name, params, value in props:
            if name == "EXDATE":
                for item in value.split(","):
                    moment = reader.moment(item, params, start_zone)
                    if moment is not None:
                        skip.append((moment.date() if isinstance(moment, datetime) else moment).isoformat())
        skip = [d for d in skip if start_date.isoformat() <= d <= end_date.isoformat()]

    location = unescape(first("LOCATION")[2] if first("LOCATION") else "").split("\n")[0].split(",")[0].strip()
    if re.match(r"https?://", location, re.IGNORECASE):  # a video-call link
        location = "Online"
    match = COMPONENT.match(summary)
    course, component = (match.group("course").strip(), match.group("component").title()) if match else (summary, "")

    try:
        return timetable.clean_meeting({
            "course": (course or summary)[:40], "title": "", "section": "", "component": component,
            "class_nbr": "", "days": days, "start": start.strftime("%H:%M"), "end": end.strftime("%H:%M"),
            "location": location, "start_date": start_date.isoformat(), "end_date": end_date.isoformat(),
            "skip_dates": skip})
    except timetable.ScheduleError as e:
        notes.append(f"Skipped \"{summary}\": {e}.")
        return None


def parse_ics(text, term=None):
    """Read an .ics file. Returns (meetings, notes); raises ScheduleError if it is not a calendar."""
    if not isinstance(text, str) or not text.strip():
        raise timetable.ScheduleError("choose a calendar (.ics) file first")
    if len(text) > MAX_ICS_CHARS:
        raise timetable.ScheduleError("that calendar file is too large")
    if "BEGIN:VCALENDAR" not in text.upper():
        raise timetable.ScheduleError("that doesn't look like a calendar (.ics) file")

    reader = _Reader()
    events = read_events(text)
    meetings, seen = [], set()
    for props in events[:MAX_EVENTS]:
        meeting = event_to_meeting(props, term, reader)
        if meeting is None:
            continue
        key = (meeting["course"], meeting["component"], tuple(meeting["days"]), meeting["start"],
               meeting["end"], meeting["location"], meeting["start_date"])
        if key not in seen:
            seen.add(key)
            meetings.append(meeting)

    notes = list(dict.fromkeys(reader.notes))
    if len(events) > MAX_EVENTS:
        notes.append(f"The calendar has {len(events)} events; I only read the first {MAX_EVENTS}.")
    if len(meetings) > timetable.MAX_MEETINGS:
        notes.append(f"Only the first {timetable.MAX_MEETINGS} classes were kept.")
        meetings = meetings[:timetable.MAX_MEETINGS]
    if not meetings and not notes:
        notes.append("I couldn't find any classes in that calendar.")
    return meetings, notes
