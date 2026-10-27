# Status

As of October 2026. The routing engine, server, data pipeline and Android/iOS app code are working and tested (hundreds of automated tests across C, Python and Dart, run in CI). The app is covered by widget tests and by integration tests that run in the iOS Simulator ([how](developer-notes.md#simulator-checks)). It has **not been run on a physical device**, so real GPS accuracy and notification timing are unverified, and notifications were not exercised in the simulator either. Photo import (screenshot to schedule) reads the picture on the phone and has only been tried on invented schedules in the Simulator, see [Reading a schedule from a picture](photo-import.md).

| Area | State |
|---|---|
| Room and building search | Working: abbreviations, partial names, typos (`/api/search`) |
| Routing | Working: real walking paths from OpenStreetMap, elevation-aware effort, optional avoid-stairs. Straight-line distance inside buildings; floors are shown but not routed |
| Today, week view, schedule import (paste, calendar file, by hand), reminders, day picker | Working. Reminders cover every class over the next week and are planned when the app opens; delivery is not verified on a device |
| Photo import | iOS only. "Read a photo" on the Schedule tab reads a screenshot or photo on the phone with Apple's Vision framework, then lists the classes for you to check before anything is saved. The picture never leaves the phone, and no account or key is involved. Measured on invented schedules in the Simulator ([results](photo-import.md)); not tried on a real device, a real photo or a real schedule. Not available on Android |
| Getting to campus from off campus | Working against a local server in the iOS Simulator, with the simulator's location set to campus, downtown Santa Cruz, Westside, Capitola, Scotts Valley and San Francisco, and with the server unreachable or too old to have the new path. Transit itself is not installed in the Simulator, so only the fall-back to Apple Maps was seen opening; the Transit link is checked by tests. **The deployed server needs a redeploy** for this to work: until then the app says it can't plan a trip and Today and routes behave as before. See [Getting to campus](getting-to-campus.md) |
| Offline | Today works offline; search, map and routes need the server |
| Data | 32 buildings and the 87 general-assignment classrooms. Other rooms resolve to their building's nearest door |
| Not built | Saved places, live bus information (Transit has it; this app does not), a map overlay of buildings and doors |
