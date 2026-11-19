# Room guides

A room guide is what a student needs in the last 30 metres: which door, which side, which floor, and the one thing that would have saved them a minute. The map can place a room from UCSC's data, but only someone standing there can say "enter from the lower plaza, not the upper path". Guides live in `data/rooms.json` and every one carries the date someone checked it.

## What a room page shows

| State | What the student sees |
|---|---|
| Not walked yet (default) | Floor from the campus map, "Not checked on foot yet", the closest mapped door and where the room is from it ("about 30 m south-west of this door, on floor 1"). |
| Walked | An access badge (Outside access, Inside the building, Inside the library), the checked door with its name, the one-line tip, up to five steps from the door, step-free or stairs, the elevator, and "Checked on foot Nov 20, 2026". Directions end at the checked door. |
| From a student tip | The same, marked "From a student tip, checked ...". A tip is only added after someone confirms it on foot. |

Buildings whose rooms have access tags split their room list into Outside access, Inside the building, Inside the library and Not checked yet, so a hybrid building like Baskin Engineering or McHenry reads at a glance. Until then rooms are grouped by floor.

## Walking a room (field audit)

1. Open the worksheet, [room-audit.md](room-audit.md). It lists the 20 rooms most likely to send someone to the wrong side, floor or door, with each one's mapped doors and the campus map floor. Regenerate it with `npm run rooms:audit` in `web/`; rooms with a guide drop off.
2. On your phone, open a room's link from the worksheet. The `?audit` at the end turns on the audit panel for this browser session (it stays on as you move between rooms).
3. Walk to the room from the outside the way a student would arrive, then fill in only what you saw:
   - **How you get in**: Outside (patio, plaza, outdoor walkway), Lobby (inside the building) or Library (past the library doors).
   - **Door you would use**: tap it on the map, or stand at it and press "I'm at the door" (GPS is within about 5 to 15 m, so the map tap is usually closer). Give it a name a stranger would recognise: "East patio door by the bike racks".
   - **Floor as signed**, **wing or side**, a **one-line tip** (up to 160 characters), up to five **steps from the door** (one per line), **step-free** or not, and the **elevator**.
4. Drafts are saved in the browser as you go. "Copy this room" copies one entry; "Copy all audited rooms" copies every room you've drafted as one object.
5. Paste the entries into `"overrides"` in `data/rooms.json`, then run `npm run data` in `web/` (it rejects unknown fields, missing dates, overlong text and doors more than 120 m from the room), `scripts/sync_app_data.sh` for the phone app, and the tests. Open a pull request.

Write what you saw, not what should be true. Leave a field out rather than guess; an empty field shows nothing, a wrong one sends people the wrong way.

## Student feedback

When the web map is built with `VITE_FEEDBACK_URL` (the `FEEDBACK_URL` repository variable for the Pages build), every room page asks "Did this get you there?" with three buttons: Easy to find, Pin or route was off (optional note) and Add a tip. Searching for a room number the map doesn't have offers "Can't find your room? Tell us which one". Each sends only the place id, the kind and the note to the classmap-transit API, which keeps no address or install id and caps intake at 20 a minute and 500 a day.

Nothing a student sends appears on the map by itself. Review it on the server:

```bash
transit feedback-report          # unreviewed, oldest first
transit feedback-reviewed 12 13  # after acting on them
```

Rooms that collect "Pin or route was off" go to the top of the next walk. A tip that checks out on foot goes into `data/rooms.json` with `"source": "student-tip"`. Delete anything personal straight away.

## Rollout

Start with the 20 rooms in the worksheet, mostly in mixed-use buildings (McHenry Library, Science & Engineering Library, Baskin Engineering, Engineering 2, Earth & Marine Sciences, Thimann Labs), where the building outline doesn't match how you get in. Share links to those rooms in class chats, Discord servers and study groups in the first week of the quarter, when people are actually getting lost, and point them at the feedback buttons.
