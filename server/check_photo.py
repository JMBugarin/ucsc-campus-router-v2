"""Read a sample schedule picture through a running server and compare the answer with what it shows.

    python3 server/server.py &                    # with the API key in its environment
    python3 server/check_photo.py [--server http://127.0.0.1:8000] [picture.png]

Without a picture it draws one with scripts/make_sample_schedule.swift (macOS): an invented schedule,
never a real one. A reading costs a few cents. Exit status: 0 every class matched, 1 something
differed, 2 the server cannot read photos, 3 the request failed.
"""

import argparse
import base64
import json
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# What scripts/make_sample_schedule.swift draws. Days are 0 for Monday. The course it also draws as
# dropped is left out by the server, so it is not here: seeing it come back is a difference.
EXPECTED = [
    {"course": "XYZ 10", "section": "01A", "days": [1], "start": "09:00", "end": "09:55", "location": "Soc Sci 2 075"},
    {"course": "XYZ 10", "section": "01", "days": [0, 2, 4], "start": "13:20", "end": "14:25",
     "location": "Kresge Acad 3201"},
    {"course": "ABC 20", "section": "01", "days": [1, 3], "start": "11:40", "end": "13:15",
     "location": "Earth&Marine B206"},
    {"course": "ABC 20", "section": "01A", "days": [3], "start": "16:00", "end": "17:05",
     "location": "Humn Lecture Hall"},
]


def loose(text):
    """A room as it compares: case, spaces and punctuation do not matter."""
    return re.sub(r"[^a-z0-9]", "", str(text).lower())


def compare(expected, meetings):
    """What differs between the classes the picture should give and the ones the server returned."""
    problems = []
    seen = set()
    for want in expected:
        key = (want["course"], want["section"])
        found = [m for m in meetings if (m["course"], m["section"]) == key]
        if not found:
            problems.append(f"missing: {want['course']} {want['section']}")
            continue
        got = found[0]
        seen.add(key)
        for field in ("days", "start", "end"):
            if got[field] != want[field]:
                problems.append(f"{want['course']} {want['section']}: {field} is {got[field]}, should be {want[field]}")
        if loose(got["location"]) != loose(want["location"]):
            problems.append(f"{want['course']} {want['section']}: room is {got['location']!r}, "
                            f"should be {want['location']!r}")
    for m in meetings:
        if (m["course"], m["section"]) not in seen:
            problems.append(f"not in the picture, or should have been left out: {m['course']} {m['section']}")
    return problems


def ask(server, path, payload=None, timeout=30):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(server + path, data=data, method="GET" if data is None else "POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as e:
        with e:
            return e.code, json.loads(e.read())


def draw_sample(path):
    subprocess.run(["swift", str(ROOT / "scripts" / "make_sample_schedule.swift"), str(path)], check=True,
                   capture_output=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("picture", nargs="?", type=Path, help="a PNG, JPEG, WebP or GIF; default: the drawn sample")
    parser.add_argument("--server", default="http://127.0.0.1:8000")
    args = parser.parse_args(argv)
    server = args.server.rstrip("/")

    try:
        _, caps = ask(server, "/api/capabilities")
    except (urllib.error.URLError, OSError) as e:
        print(f"Couldn't reach {server}: {e}")
        return 3
    photo = caps.get("photo", {})
    if not photo.get("ready"):
        print(f"This server can't read photos: {photo.get('reason') or 'no reason given'}")
        return 2

    with tempfile.TemporaryDirectory() as tmp:
        picture = args.picture
        if picture is None:
            picture = Path(tmp) / "sample.png"
            try:
                draw_sample(picture)
            except (OSError, subprocess.CalledProcessError) as e:
                print(f"Couldn't draw the sample (it needs macOS with swift); pass a picture instead: {e}")
                return 3
        raw = picture.read_bytes()

    media = {b"\x89PNG": "image/png", b"\xff\xd8\xff": "image/jpeg", b"GIF8": "image/gif", b"RIFF": "image/webp"}
    media_type = next((t for sig, t in media.items() if raw.startswith(sig)), "image/png")
    print(f"Sending {len(raw):,} bytes of {media_type} to {server} ...")
    status, body = ask(server, "/api/schedule/photo",
                       {"image": base64.b64encode(raw).decode("ascii"), "media_type": media_type}, timeout=240)
    if status != 200:
        print(f"The server answered {status}: {body.get('error', body)}")
        return 3

    for m in body["meetings"]:
        days = "".join("MTWRFSU"[d] for d in m["days"])
        print(f"  {m['course']:7} {m['section']:4} {days:5} {m['start']}-{m['end']}  {m['location']}")
    for note in body.get("notes", []):
        print(f"  note: {note}")
    if args.picture is not None:
        print("Compare the list above with your picture; the built-in check only knows the sample.")
        return 0
    problems = compare(EXPECTED, body["meetings"])
    if problems:
        print(f"{len(problems)} difference(s) from what the sample shows:")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print(f"OK: all {len(EXPECTED)} classes match, and the dropped course was left out.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
