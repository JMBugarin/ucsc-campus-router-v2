"""Fetch the UCSC campus map's building layer into data/facilities.json.

Usage (from data-pipeline/):
    python fetch_facilities.py

Source: the public "facilities" feature layer behind https://maps.ucsc.edu/ (UCSC Planning,
Design & Construction): one query returns every campus building with its official name, short
label, alternative names, departments, use, region and outline. Residential buildings, hidden
records and off-campus sites (coastal science campus, agroecology) are left out. Standard
library only.
"""

import json
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYER = ("https://services1.arcgis.com/stBH6xTKFN83oDku/arcgis/rest/services/"
         "facilities_view/FeatureServer/0/query")
USER_AGENT = "classmap data tool (personal student project; see github.com/JMBugarin/ucsc-campus-router-v2)"
OFF_CAMPUS = ("off-campus", "agroecology", "coastal", "delaware")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode("utf-8", errors="replace")


def ring_centroid(ring):
    """Area-weighted centroid of a lon/lat ring (planar, fine at building scale)."""
    a = cx = cy = 0.0
    for (x0, y0), (x1, y1) in zip(ring, ring[1:] + ring[:1]):
        cross = x0 * y1 - x1 * y0
        a += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    if abs(a) < 1e-18:
        xs, ys = [p[0] for p in ring], [p[1] for p in ring]
        return sum(xs) / len(xs), sum(ys) / len(ys)
    return cx / (3 * a), cy / (3 * a)


def split_names(text):
    seen = []
    for part in (text or "").split(","):
        part = part.strip()
        if part and part.lower() not in {s.lower() for s in seen}:
            seen.append(part)
    return seen


def keep(attrs):
    if attrs.get("HIDE"):
        return False
    if (attrs.get("CATEGORY") or "").startswith("R"):
        return False
    region = (attrs.get("REGION") or "").lower()
    return not any(word in region for word in OFF_CAMPUS)


def parse(features):
    out = []
    for f in features:
        a = f["attributes"]
        rings = (f.get("geometry") or {}).get("rings") or []
        if not keep(a) or not rings:
            continue
        biggest = max(rings, key=len)
        lon, lat = ring_centroid([tuple(p) for p in biggest])
        out.append({
            "asset": str(a["ASSETNUM"]),
            "name": a["BUILDINGNAME"],
            "label": a["LABELNAME"],
            "aliases": split_names(a["ALIAS"]),
            "departments": split_names(a["DEPARTMENTS"]),
            "category": a["CATEGORY"],
            "primary_use": a["PRIMARYUSE"],
            "region": a["REGION"],
            "floors": a["FLOORS"],
            "lat": round(lat, 7),
            "lon": round(lon, 7),
        })
    out.sort(key=lambda r: (r["region"] or "", r["name"] or ""))
    return out


def main():
    query = urllib.parse.urlencode({"where": "1=1", "outFields": "*", "outSR": 4326,
                                    "returnGeometry": "true", "f": "json"})
    data = json.loads(get(f"{LAYER}?{query}"))
    if "error" in data or data.get("exceededTransferLimit"):
        raise SystemExit(f"unexpected facilities response: {data.get('error', 'truncated')}")
    rows = parse(data["features"])
    out = ROOT / "data" / "facilities.json"
    out.write_text(json.dumps({"source": "https://maps.ucsc.edu/ (facilities layer, UCSC PPDO)",
                               "buildings": rows}, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {len(rows)} buildings to {out}")


if __name__ == "__main__":
    main()
