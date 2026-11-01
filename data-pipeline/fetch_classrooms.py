"""Fetch the UCSC general-assignment classroom directory into data/classrooms.json.

Usage (from data-pipeline/):
    python fetch_classrooms.py

Sources:
  * https://classrooms.ucsc.edu/. Each room page lists an "AIS Display Name"
    (e.g. "Kresge Acad 3201"), which is how UCSC's student system prints the
    room in class schedules, plus a facility id. Requests are sequential and wait
    as long as the site's robots.txt asks (a Crawl-delay of 30 seconds when
    checked on 2026-10-31), so a full run takes most of an hour. Run it rarely:
    the result is committed.
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
USER_AGENT = "classmap data tool (personal student project; see github.com/JMBugarin/ucsc-campus-router-v2)"
DEFAULT_DELAY_S = 30.0


def crawl_delay(robots_txt, default=DEFAULT_DELAY_S):
    """The Crawl-delay robots.txt asks of every crawler (the `*` group), or [default] if it names none."""
    in_star_group, delay = False, None
    for line in robots_txt.splitlines():
        line = line.split("#", 1)[0].strip()
        name, _, value = line.partition(":")
        name, value = name.strip().lower(), value.strip()
        if name == "user-agent":
            in_star_group = value == "*"
        elif name == "crawl-delay" and in_star_group:
            try:
                delay = float(value)
            except ValueError:
                pass
    return default if delay is None else max(delay, 0.0)


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
    ap.add_argument("--delay", type=float, default=None,
                    help="seconds between requests to classrooms.ucsc.edu; never less than its robots.txt Crawl-delay")
    args = ap.parse_args()

    try:
        asked = crawl_delay(get(f"{BASE}/robots.txt"))
    except OSError:
        asked = DEFAULT_DELAY_S
    delay = max(asked, args.delay or 0.0)
    print(f"waiting {delay:g} s between requests (robots.txt asks for {asked:g} s)")

    slugs = candidate_slugs(get(LISTING))
    print(f"{len(slugs)} candidate links on the listing page")

    points = fetch_room_points()
    print(f"{len(points)} room points from the campus map layer")

    rooms = []
    for slug in slugs:
        time.sleep(delay)
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
