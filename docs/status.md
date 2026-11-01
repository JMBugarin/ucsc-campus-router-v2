# Status

As of October 2026. The app is feature-complete for its scope and covered by about 400 automated unit and widget tests, a test that replays outputs recorded from the Python code it replaced, and an integration test that runs the whole app on the iOS Simulator (iPhone 17). It has **not been run on a physical device**: notification delivery, opening Apple Maps from a real phone, and photo import on real photos are unverified.

| Area | State |
|---|---|
| Room and building search | Working, offline: abbreviations, partial names, typos. Checked against every official classroom name (87 of 87 resolve to a building, a room and a position) |
| Today, day picker, week view | Working, offline, from the saved schedule and the clock. Handles holidays, skipped days and clock changes |
| Walk there | Opens walking directions in Apple Maps (iOS) or Google Maps (Android) to the room's main door. The link format is checked by tests; opening Apple Maps from a simulator build was seen, a real phone was not |
| Schedule import | Paste, calendar file and by hand work and are checked by tests against the Python behaviour they replaced. Photo import is iOS only and measured on invented schedules ([results](photo-import.md)) |
| Reminders | Planned from the schedule when the app opens; delivery is not verified on a device |
| Data | 32 buildings and the 87 general-assignment classrooms. Any other room resolves to its building's main door. Term dates run through Spring 2027 and must be extended by hand each year in `data/holidays.json` |
| Map tiles | OpenStreetMap's public tile server until a hosted provider key is set (see [app/README.md](../app/README.md)); fine for development, not for a wide release |
| Not built | Saved places, indoor floor guidance, a map overlay of buildings, Android photo import |
