"""Fetch the UCSC general-assignment classroom directory into data/classrooms.json.

Usage (from data-pipeline/):
    python fetch_classrooms.py

Sources:
  * https://classrooms.ucsc.edu/. Each room page lists an "AIS Display Name"
    (e.g. "Kresge Acad 3201"), which is how UCSC's student system prints the
    room in class schedules, plus a facility id. Requests are sequential with a
    delay to stay polite.
  * The campus map's public "General Assignment Classroom Points" layer
    (https://maps.ucsc.edu/, maintained by UCSC PPDO): one query returns a
    coordinate and level for every room, keyed by the same display name.
Uses only the standard library.
"""

import argparse
import html
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "https://classrooms.ucsc.edu"
LISTING = f"{BASE}/seating-capacity/150/"
ROOM_POINTS = ("https://services1.arcgis.com/stBH6xTKFN83oDku/arcgis/rest/services/"
               "GA_Classroom_Points_PPDO/FeatureServer/0/query")
USER_AGENT = "ucsc-campus-router (personal student project)"
DELAY_S = 0.5


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8", errors="replace")


def text_of(page):
    page = re.sub(r"<script.*?</script>|<style.*?</style>", "", page, flags=re.S)
    return html.unescape(re.sub(r"<[^>]+>", "\n", page))


def field(text, label):
    m = re.search(rf"^{re.escape(label)}:\s*(.+)$", text, flags=re.M)
    return m.group(1).strip() if m else None


def fetch_room_points():
    """AIS display name -> {lat, lon, level_id, map_building_name} from the campus map layer."""
    query = urllib.parse.urlencode({
        "where": "1=1", "outFields": "AIS_Formatted_Name,BUILDING_NAME,LEVEL_ID",
        "outSR": 4326, "returnGeometry": "true", "f": "json"})
    data = json.loads(get(f"{ROOM_POINTS}?{query}"))
    if "error" in data or data.get("exceededTransferLimit"):
        raise SystemExit(f"unexpected room-points response: {data.get('error', 'truncated')}")
    points = {}
    for f in data["features"]:
        a, g = f["attributes"], f.get("geometry")
        if g and a.get("AIS_Formatted_Name"):
            points[a["AIS_Formatted_Name"]] = {
                "lat": round(g["y"], 7), "lon": round(g["x"], 7),
                "level_id": a.get("LEVEL_ID"), "map_building_name": a.get("BUILDING_NAME")}
    return points


def candidate_slugs(listing_html):
    slugs = re.findall(r'href="(?:https?://classrooms\.ucsc\.edu)?/([a-z0-9-]+)/"', listing_html)
    return list(dict.fromkeys(slugs))  # unique, in page order


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", type=Path, default=ROOT / "data" / "classrooms.json")
    args = ap.parse_args()

    slugs = candidate_slugs(get(LISTING))
    print(f"{len(slugs)} candidate links on the listing page")

    points = fetch_room_points()
    print(f"{len(points)} room points from the campus map layer")

    rooms = []
    for slug in slugs:
        time.sleep(DELAY_S)
        t = text_of(get(f"{BASE}/{slug}/"))
        display = field(t, "AIS Display Name")
        if not display:  # navigation page, not a room
            continue
        rooms.append({
            "slug": slug,
            "ais_display_name": display,
            "facility_id": field(t, "Building/Facility ID"),
            "ppdo_code": field(t, "PPDO Code"),
            **points.get(display, {}),
        })
        print(f"  {slug:36s} {display}")

    rooms.sort(key=lambda r: r["slug"])
    missing = [r["ais_display_name"] for r in rooms if "lat" not in r]
    if missing:
        print(f"WARNING: {len(missing)} rooms have no map point: {missing}")
    args.out.write_text(
        json.dumps({"source": LISTING, "rooms": rooms}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8")
    print(f"Wrote {len(rooms)} rooms to {args.out}")


if __name__ == "__main__":
    main()
