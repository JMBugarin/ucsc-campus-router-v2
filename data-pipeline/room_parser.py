"""Resolve UCSC schedule location strings to a building, room and entrances.

    >>> campus = load_campus()
    >>> r = campus.resolve("Baskin Engr 152")
    >>> r.kind, r.building_id, r.room
    ('building', 'baskin-engineering', '152')

Rules (shared test cases live in tests/room_cases.json so a Dart port can reuse them):
  1. Normalize: lowercase, "&" -> "and", every run of non-alphanumerics -> one space.
  2. "online", "remote", "tba" and blank strings are not physical places.
  3. Names the classroom directory prints with no room ("Humn Lecture Hall") match whole.
     Otherwise the longest alias that is a whole-word prefix of the string
     names the building; whatever follows (minus a leading "room"/"rm") is the room.
  4. data/rooms.json may pin a specific entrance (and floor/note) for a room.
"""

import difflib
import json
import re
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ONLINE = {"online", "remote", "remote instruction", "zoom", "asynchronous", "async", "web",
          "online asynchronous", "online synchronous"}
TBA = {"", "tba", "tbd", "to be announced", "no room", "none"}
ROOM_WORDS = {"room", "rm"}


def normalize(text):
    text = text.lower().replace("&", " and ")
    return re.sub(r"[^a-z0-9]+", " ", text).strip()


def _one_edit_apart(a, b):
    """True if a and b differ by exactly one inserted, deleted or changed character."""
    if a == b or abs(len(a) - len(b)) > 1:
        return False
    if len(a) == len(b):
        return sum(x != y for x, y in zip(a, b)) == 1
    short, long_ = (a, b) if len(a) < len(b) else (b, a)
    return any(long_[:i] + long_[i + 1:] == short for i in range(len(long_)))


@dataclass
class Resolution:
    raw: str
    kind: str  # "building", "online", "tba" or "unknown"
    building_id: str = None
    room: str = None
    entrances: list = field(default_factory=list)
    floor: str = None
    note: str = None
    room_known: bool = None  # True/False if the building's room list is known, else None
    room_point: dict = None  # {"lat", "lon", "level"} of the room itself, when the map has it
    candidates: list = field(default_factory=list)  # best guesses when kind == "unknown"


class Campus:
    def __init__(self, buildings, overrides=None):
        self.buildings = {b["id"]: b for b in buildings}
        if len(self.buildings) != len(buildings):
            raise ValueError("duplicate building ids")
        self.overrides = overrides or {}
        self._index = {}
        self._exact = {}  # whole official names that carry no room number
        for b in buildings:
            for name, room in b.get("exact_names", {}).items():
                self._exact[normalize(name)] = (b["id"], room)
            for alias in [b["name"], b.get("osm_name") or "", *b.get("aliases", [])]:
                key = tuple(normalize(alias).split())
                if not key:
                    continue
                if self._index.setdefault(key, b["id"]) != b["id"]:
                    raise ValueError(
                        f"alias {alias!r} belongs to both {self._index[key]} and {b['id']}")

    def split_location(self, text):
        """Split a location followed by other words, e.g. a schedule row's room and instructor.

        "Cowell Acad 113 To be Announced" -> ("Cowell Acad 113", "To be Announced").
        Uses the known building names to find where the room ends; for an unknown
        building the room ends at the first word containing a digit.
        """
        words = text.split()
        norm = [normalize(w) for w in words]

        def phrase(k):
            return " ".join(n for n in norm[:k] if n)

        for k in range(1, min(3, len(words)) + 1):  # "TBA", "Online", "Remote Instruction"
            if phrase(k) in ONLINE or phrase(k) in TBA - {""}:
                return " ".join(words[:k]), " ".join(words[k:])
        for k in range(len(words), 0, -1):  # whole names with no room number
            if phrase(k) in self._exact:
                return " ".join(words[:k]), " ".join(words[k:])
        alias_len = 0
        for k in range(len(words), 0, -1):
            if tuple(phrase(k).split()) in self._index:
                alias_len = k
                break
        for j in range(alias_len, len(words)):
            if any(ch.isdigit() for ch in words[j]):
                return " ".join(words[:j + 1]), " ".join(words[j + 1:])
        return text, ""

    def correct_room(self, location):
        """Repair a room that text recognition misread by one character.

        If the room is not one the building has, but is exactly one edit (a dropped, extra or
        changed character) from exactly one that it does have, return the corrected location and
        a note saying so. Otherwise return the location unchanged with no note.
        """
        res = self.resolve(location)
        if res.kind != "building" or not res.room or res.room_known is not False:
            return location, None
        close = [r for r in self.buildings[res.building_id].get("known_rooms", [])
                 if _one_edit_apart(r, res.room)]
        tokens, n = location.split(), len(res.room.split())
        if len(close) != 1 or len(tokens) <= n:
            return location, None
        fixed = " ".join(tokens[:-n] + [close[0]])
        if self.resolve(fixed).building_id != res.building_id:
            return location, None
        return fixed, f"Read room {res.room} as {close[0]}, the only room in that building like it."

    def resolve(self, location):
        text = normalize(location or "")
        if text in TBA:
            return Resolution(location, "tba")
        if text in ONLINE or text.startswith(("online ", "remote ")):
            return Resolution(location, "online")

        if text in self._exact:
            building_id, room = self._exact[text]
            return self._building(location, building_id, [room.lower()])

        tokens = text.split()
        for k in range(len(tokens), 0, -1):
            building_id = self._index.get(tuple(tokens[:k]))
            if building_id:
                return self._building(location, building_id, tokens[k:])
        return Resolution(location, "unknown", candidates=self._suggest(tokens))

    def _building(self, raw, building_id, rest):
        if rest and rest[0] in ROOM_WORDS:
            rest = rest[1:]
        room = " ".join(rest).upper() or None
        building = self.buildings[building_id]
        entrances = list(building["entrances"])
        floor = note = None
        override = self.overrides.get(f"{building_id}:{room}") if room else None
        if override:
            if "entrance" in override:
                entrances = [override["entrance"]]
            floor, note = override.get("floor"), override.get("note")
        known = building.get("known_rooms")
        room_known = (room in known) if (known and room) else None
        room_point = building.get("room_points", {}).get(room) if room else None
        if floor is None and room_point:
            floor = room_point.get("level")
        return Resolution(raw, "building", building_id, room, entrances, floor, note, room_known,
                          room_point)

    def _suggest(self, tokens):
        scored = []
        for key, building_id in self._index.items():
            head = " ".join(tokens[:len(key)])
            score = difflib.SequenceMatcher(None, head, " ".join(key)).ratio()
            scored.append((score, building_id))
        best = []
        for score, building_id in sorted(scored, reverse=True):
            if score >= 0.6 and building_id not in best:
                best.append(building_id)
        return best[:3]


def load_campus(data_dir=ROOT / "data"):
    data_dir = Path(data_dir)
    buildings = json.loads((data_dir / "buildings.json").read_text(encoding="utf-8"))["buildings"]
    overrides = {}
    rooms = data_dir / "rooms.json"
    if rooms.exists():
        overrides = json.loads(rooms.read_text(encoding="utf-8")).get("overrides", {})
    return Campus(buildings, overrides)


if __name__ == "__main__":
    import sys

    campus = load_campus()
    for arg in sys.argv[1:] or ["Baskin Engr 152"]:
        print(campus.resolve(arg))
