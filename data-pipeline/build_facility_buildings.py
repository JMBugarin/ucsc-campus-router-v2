"""Add the campus map's other teaching buildings to data/buildings.json.

Usage (from data-pipeline/):
    python build_facility_buildings.py

build_buildings.py writes the hand-curated buildings (OpenStreetMap footprints and doors).
This step reads data/facilities.json (from fetch_facilities.py) and appends every classroom,
lab, library, general-use and special-use building that is not already there, so rooms the
classroom directory does not list (departmental classrooms, labs, studios) still resolve to a
building. It is idempotent: records it wrote earlier (`source` = "ucsc-facilities") are replaced.

These buildings are located by the campus map's building outline: one `approach` point at the
outline's centre, not a door. Aliases come from the map's names plus common schedule
abbreviations. Standard library only.
"""

import csv
import difflib
import json
import re
import unicodedata
from pathlib import Path

from room_parser import normalize

ROOT = Path(__file__).resolve().parents[1]
USES = ("CLS", "LAB", "LIB", "GEN", "SPC")
SAME_NAME_RATIO = 0.82
SAME_PLACE_M = 80.0
MAX_FROM_PATH_M = 150.0  # farther from the walking graph than this: not routable, left out
SKIP_NAME = re.compile(r"storage|restroom|trailer|shed\b|garage|parking|kitchen|greenhouse|dome \d|"
                       r"receiving|blacksmith|powder house|cooperage|hay barn|fire house|woodshop|"
                       r"shop [ab]\b|stores|rest ?rooms?", re.I)
GENERIC = {"library", "lib", "lounge", "studio", "auditorium", "aud", "annex", "classroom", "clrm",
           "classroom building", "clrm bldg", "classroom bldg", "clrm building", "commons", "common",
           "coffee shop", "faculty wing", "faculty common", "academic center", "acad center",
           "recreation room", "activities", "foundry", "costume", "learning center", "gym",
           "pickard smith gallery", "annex building b", "unit a", "unit b", "unit c", "unit d",
           "unit e", "unit h", "unit k", "unit l", "unit m", "main stage", "2nd stage", "woodshop",
           "student production", "e classroom", "b drama", "a main stage", "m media", "e clrm"}
ABBREVIATIONS = [
    (r"\bLaboratories\b", ["Labs", "Lab"]), (r"\bLaboratory\b", ["Lab"]),
    (r"\bBuilding\b", ["Bldg", ""]), (r"\bSciences\b", ["Sci"]), (r"\bScience\b", ["Sci"]),
    (r"\bNatural\b", ["Nat"]), (r"\bEngineering\b", ["Engr", "Eng"]), (r"\bHumanities\b", ["Hum"]),
    (r"\bSocial\b", ["Soc"]), (r"\bLibrary\b", ["Lib"]), (r"\bAcademic\b", ["Acad"]),
    (r"\bClassroom\b", ["Clrm"]), (r"\bLecture Hall\b", ["Lecture", "Lec Hall"]),
    (r"\bAuditorium\b", ["Aud"]), (r"\bCollege\b", [""]), (r"\bRachel Carson\b", ["R Carson", "Carson"]),
]


def haversine_m(lat1, lon1, lat2, lon2):
    import math
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = (math.sin((p2 - p1) / 2) ** 2
         + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2)
    return 2 * 6371009.0 * math.asin(math.sqrt(a))


def slug(text):
    return normalize(text).replace(" ", "-")


def variants(name):
    """The name with each schedule-style abbreviation applied one at a time and all together."""
    out = {name}
    for pattern, subs in ABBREVIATIONS:
        for sub in subs:
            out |= {re.sub(pattern, sub, v).strip() for v in list(out)}
    return {re.sub(r"\s+", " ", v).strip() for v in out if len(v.strip()) > 2}


def existing_match(fac, curated):
    """The curated building this facility is, or None."""
    names = {normalize(n) for n in [fac["name"], fac["label"], *fac["aliases"]] if n}
    names |= {normalize(v) for v in variants(fac["name"])}
    for b in curated:
        known = {normalize(b["name"]), *(normalize(a) for a in b["aliases"])}
        if names & known:
            return b
    for b in curated:
        c = b.get("centroid")
        if not c or haversine_m(fac["lat"], fac["lon"], c["lat"], c["lon"]) > SAME_PLACE_M:
            continue
        fn, bn = normalize(fac["name"]), normalize(b["name"])
        if bn in fn or difflib.SequenceMatcher(None, fn, bn).ratio() >= SAME_NAME_RATIO:
            return b
    return None


def clean(alias):
    """Drop aliases the campus map garbled (a lone combining accent) or that are not words."""
    alias = unicodedata.normalize("NFC", alias)
    if any(unicodedata.category(ch) == "Mn" for ch in alias) or "\ufffd" in alias:
        return None
    return alias


def lettered_unit(name):
    """"Theater Arts C Studio" is also "Theater Arts C" and "Theater Arts Unit C"."""
    m = re.match(r"^(Theater Arts|Elena Baskin Building) ([A-Z])\b", name)
    if not m:
        return []
    short = m.group(1).replace("Building", "Bldg")
    return [f"{m.group(1)} {m.group(2)}", f"{short} {m.group(2)}", f"{m.group(1).replace('Building', '').strip()} Unit {m.group(2)}"]


def record(fac, taken_ids):
    name = fac["name"]
    names = [name, fac["label"], *fac["aliases"]]
    aliases = []
    for n in names:
        if n:
            aliases += sorted(variants(n), key=lambda v: (v != n, v))
    aliases += lettered_unit(name)
    aliases = [a for a in (clean(a) for a in aliases) if a]
    aliases = [a for a in dict.fromkeys(aliases) if normalize(a) != normalize(name)
               and normalize(a) not in GENERIC and len(normalize(a)) > 2]
    bid = slug(name)
    if bid in taken_ids:
        bid = f"{bid}-{fac['asset']}"
    taken_ids.add(bid)
    return {
        "id": bid, "name": name, "aliases": aliases, "osm_name": None, "facility_ids": [],
        "known_rooms": [], "exact_names": {}, "room_points": {}, "located_by": "ucsc-facilities",
        "centroid": {"lat": fac["lat"], "lon": fac["lon"]},
        "entrances": [{"lat": fac["lat"], "lon": fac["lon"], "kind": "approach", "source": "ucsc-facilities"}],
        "source": "ucsc-facilities", "asset": fac["asset"], "primary_use": (fac["primary_use"] or "")[:3],
        "region": fac["region"], "departments": fac["departments"],
    }


def load_nodes():
    with open(ROOT / "graph" / "ucsc" / "nodes.csv", newline="") as f:
        return [(float(r["lat"]), float(r["lon"])) for r in csv.DictReader(f)]


def build(curated, facilities, nodes=None):
    """(new records, report lines). curated must not contain earlier facility records.

    With `nodes` (the walking graph), buildings farther than MAX_FROM_PATH_M from a path are left out.
    """
    taken = {b["id"] for b in curated}
    out, report = [], []
    for fac in facilities:
        if nodes and min(haversine_m(fac["lat"], fac["lon"], la, lo) for la, lo in nodes) > MAX_FROM_PATH_M:
            continue
        use = (fac["primary_use"] or "")[:3]
        if use not in USES or SKIP_NAME.search(fac["name"] or ""):
            continue
        match = existing_match(fac, curated)
        if match:
            report.append(f"= {fac['name']!r} is {match['id']}")
            continue
        out.append(record(fac, taken))
    return out, report


def drop_shared_aliases(curated, new):
    """An alias two buildings share would mis-resolve rooms: keep it only where it is already curated."""
    owners = {}
    for b in curated + new:
        for a in [b["name"], *b["aliases"]]:
            owners.setdefault(normalize(a), set()).add(b["id"])
    for b in new:
        b["aliases"] = [a for a in b["aliases"] if len(owners[normalize(a)]) == 1]


def main():
    path = ROOT / "data" / "buildings.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    facilities = json.loads((ROOT / "data" / "facilities.json").read_text(encoding="utf-8"))["buildings"]
    curated = [b for b in data["buildings"] if b.get("source") != "ucsc-facilities"]
    new, report = build(curated, facilities, load_nodes())
    print("\n".join(report))
    drop_shared_aliases(curated, new)
    data["buildings"] = curated + new
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(curated)} curated + {len(new)} from the campus map = {len(data['buildings'])} buildings")


if __name__ == "__main__":
    main()
