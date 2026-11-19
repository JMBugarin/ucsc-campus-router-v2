"""Fetch the on-campus residence halls and apartments into data/housing.json.

Usage (from data-pipeline/):
    python fetch_housing.py

Source: the same public "facilities" layer behind https://maps.ucsc.edu/ that fetch_facilities.py reads,
keeping the residential buildings people live in (residence halls, houses, apartments) and leaving out
provost houses, garages, lounges, dining and service buildings and off-campus sites. Each building gets
the names students use for it ("C9 Apt 2", "Casa Primera", "Merrill DuBois") so search finds it, and up to
four points on its outline so a route can end at whichever side of the building is quickest to reach.
Standard library only.
"""

import json
import re
import urllib.parse
from pathlib import Path

from fetch_facilities import LAYER, get, ring_centroid, split_names

ROOT = Path(__file__).resolve().parents[1]

# region in the layer -> (name shown, names students put in front of a building)
AREAS = {
    "College Nine": ("College Nine", ["C9", "College 9", "Nine"]),
    "John R. Lewis College Neighborhood": ("John R. Lewis College", ["JRL", "C10", "College 10", "College Ten", "Lewis"]),
    "Rachel Carson College": ("Rachel Carson College", ["RCC", "Carson", "Rachel Carson", "C8", "College 8", "College Eight"]),
    "Cowell College": ("Cowell College", ["Cowell"]),
    "Stevenson College": ("Stevenson College", ["Stevenson"]),
    "Crown College": ("Crown College", ["Crown"]),
    "Merrill College": ("Merrill College", ["Merrill"]),
    "Porter College": ("Porter College", ["Porter"]),
    "Kresge College": ("Kresge College", ["Kresge"]),
    "Oakes College": ("Oakes College", ["Oakes"]),
    "Crown-Merrill Housing": ("Crown/Merrill Apartments", ["Crown Merrill", "Crown-Merrill", "Crown Merrill Apartments", "CM"]),
    "Lower Quarry Village Housing": ("The Village", ["Village", "The Village", "Lower Quarry Village"]),
    "Graduate Student Housing": ("Graduate Student Housing", ["Grad Housing", "Graduate Housing", "Heller Housing"]),
    "Family Student Housing": ("Family Student Housing", ["FSH", "Family Housing"]),
}

# not where students live: the provost's and chancellor's houses, garages, lounges, service rooms
SKIP = re.compile(r"College House$|University House|Garage|Preceptor|Service Module|Lounge|Common Building|"
                  r"Multipurpose|Utility|Maintenance|Dining|Commons|Cafe|Affiliate|Child Care", re.I)

# wing names on the official Merrill College map (maps.ucsc.edu/printable-maps/Merrill_College010215.pdf)
MERRILL_WINGS = {
    "Merrill College House A": ["Lorde-Studds", "Kochiyama", "Buloson"],
    "Merrill College House B": ["Gandhi-Kahlo", "Ghandi-Kahlo"],
    "Merrill College House C": ["Chavez-Menchu", "Chávez-Menchú"],
    "Merrill College House D": ["DuBois", "Du Bois"],
}


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower().replace("&", "and")).strip("-")


def keep(attrs):
    if attrs.get("HIDE") or not (attrs.get("CATEGORY") or "").startswith("R"):
        return False
    if (attrs.get("REGION") or "") not in AREAS or SKIP.search(attrs.get("BUILDINGNAME") or ""):
        return False
    use = attrs.get("PRIMARYUSE") or ""
    return use.startswith("RES") or (not use and re.search(r"Residence Hall", attrs.get("BUILDINGNAME") or ""))


def short_names(name, area_prefixes):
    """The part of the official name that tells this building apart, in the forms students say it, and the
    names distinctive enough to stand alone ("Galileo", but not "Apartment Building 2")."""
    m = re.fullmatch(r"Redwood Grove Apartments Building (\d+)", name)
    if m:
        n = m.group(1)
        return [], [f"Redwood Grove {n}", f"Redwood Grove Building {n}", f"Redwood Grove Apartments {n}"]
    rest = name
    for p in sorted([*area_prefixes, "Cowell College", "Crown College", "Merrill College", "Porter College",
                     "Kresge College", "Oakes College", "Rachel Carson College", "Stevenson College",
                     "College Nine", "John R. Lewis College", "Crown-Merrill Housing", "Village Housing",
                     "Graduate Student Housing", "Family Student Housing", "Kresge"], key=len, reverse=True):
        if rest.startswith(p + " "):
            rest = rest[len(p) + 1:]
            break
    shorts, alone = [rest], []
    m = re.fullmatch(r"Apartment Building (\w+)", rest)
    if m:
        n = m.group(1)
        shorts += [f"Apt {n}", f"Apartments {n}", f"Apartment {n}", f"Apt Building {n}", f"Building {n}"]
    m = re.fullmatch(r"Residence Hall (\w+)", rest)
    if m:
        n = m.group(1)
        shorts += [f"Res Hall {n}", f"Hall {n}"] + ([n] if n.isalpha() else [])
    m = re.fullmatch(r"([A-Z][a-z]+) House", rest)
    if m:
        shorts.append(m.group(1))
        alone += [rest, m.group(1)]
    m = re.fullmatch(r"House (\w+)", rest)
    if m:
        n = m.group(1)
        shorts += [f"Building {n}", f"{n} Building", n] if n.isalpha() else [f"House {int(n)}"]
    m = re.fullmatch(r"Dorm (\w)-L-Building", rest)
    if m:
        shorts += [f"{m.group(1)} Building", f"Building {m.group(1)}", f"Dorm {m.group(1)}"]
    m = re.fullmatch(r"Dorm (\w)-Garden", rest)
    if m:
        shorts += [f"{m.group(1)} Garden", f"Garden {m.group(1)}"]
    m = re.fullmatch(r"Building (\w+)", rest)
    if m:
        shorts.append(m.group(1))
    return list(dict.fromkeys(shorts)), alone


def outline_points(ring):
    """The northmost, eastmost, southmost and westmost corners: where a route may meet the building."""
    pts = [(lat, lon) for lon, lat in ring]
    picks = [max(pts), max(pts, key=lambda p: p[1]), min(pts), min(pts, key=lambda p: p[1])]
    return [[round(a, 7), round(b, 7)] for a, b in dict.fromkeys(picks)]


def parse(features):
    out = []
    for f in features:
        a = f["attributes"]
        rings = (f.get("geometry") or {}).get("rings") or []
        if not keep(a) or not rings:
            continue
        name = a["BUILDINGNAME"].strip()
        area, prefixes = AREAS[a["REGION"]]
        biggest = max(rings, key=len)
        lon, lat = ring_centroid([tuple(p) for p in biggest])
        shorts, alone = short_names(name, prefixes)
        label = (a.get("LABELNAME") or "").strip()
        generic = re.compile(r"(Res Hall|Residence Hall|Hall|Building|Apartment|Apartments|House|Dorm) \w+", re.I)
        aliases = [*[x for x in split_names(a.get("ALIAS")) if not generic.fullmatch(x)], *MERRILL_WINGS.get(name, []), *alone]
        if a["REGION"] == "Stevenson College" and label:
            aliases += [f"Casa {label}", label, f"Stevenson {label}"]
        for p in prefixes:
            aliases += [f"{p} {s}" for s in shorts]
        seen = {name.lower()}
        unique = []
        for alias in aliases:
            if alias.lower() not in seen:
                seen.add(alias.lower())
                unique.append(alias)
        layer_names = [x for x in split_names(a.get("ALIAS"))
                       if not generic.fullmatch(x) and not x.startswith(area) and not re.search(r"laundry", x, re.I)]
        known_as = (f"Casa {label}" if a["REGION"] == "Stevenson College" and label
                    else ", ".join(MERRILL_WINGS[name][:1]) if name in MERRILL_WINGS else
                    (layer_names[0] if layer_names else None))
        short = known_as or (shorts or alone)[0]
        out.append({
            "id": slug(name),
            "asset": str(a["ASSETNUM"]),
            "name": name,
            "short": short,
            **({"known_as": known_as} if known_as else {}),
            "area": area,
            "aliases": unique,
            "lat": round(lat, 7),
            "lon": round(lon, 7),
            "approach": outline_points([tuple(p) for p in biggest]),
        })
    out.sort(key=lambda r: (r["area"], natural(r["name"])))
    return out


def natural(text):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", text)]


def main():
    query = urllib.parse.urlencode({"where": "CATEGORY LIKE 'R%'", "outFields": "*", "outSR": 4326,
                                    "returnGeometry": "true", "f": "json"})
    data = json.loads(get(f"{LAYER}?{query}"))
    if "error" in data or data.get("exceededTransferLimit"):
        raise SystemExit(f"unexpected facilities response: {data.get('error', 'truncated')}")
    rows = parse(data["features"])
    out = ROOT / "data" / "housing.json"
    out.write_text(json.dumps({"source": "https://maps.ucsc.edu/ (facilities layer, UCSC PPDO); wing names from the "
                                         "Merrill College map", "buildings": rows}, indent=1, ensure_ascii=False) + "\n",
                   encoding="utf-8")
    print(f"wrote {len(rows)} residential buildings to {out}")


if __name__ == "__main__":
    main()
