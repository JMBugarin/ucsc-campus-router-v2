# Classmap (iOS and Android app)

Your UCSC class schedule on an interactive campus map. Everything runs on the phone: there is no server, no account and no location access.

## What it does

- **Today**: the day's classes with time, room, building and the break before each, what is on now and next. The day picker steps through any day of the schedule; the week icon shows seven days at a glance.
- **Skip a day**: the menu on a class has "Skip this day", with Undo; its reminder is cancelled and the Schedule list shows "Not meeting Oct 21" with a Restore button.
- **Map**: search a room or building; today's classes are pinned. A class on Today has a button that shows it on the map.
- **Walk there**: opens walking directions to the room's door in Apple Maps (iPhone) or Google Maps (Android). Only the destination is sent; the maps app finds where you are. The door is the room's override in `data/rooms.json`, else the building's main entrance, else any entrance, else the room, else the middle of the building.
- **Schedule**: paste from MyUCSC, import a calendar (`.ics`) file, read a picture of it (iOS), or add a class by hand. Saved on the phone only; instructor names are never kept.
- **Read a photo** (iOS): the phone reads a screenshot or photo with Apple's Vision framework, then Dart code (`lib/features/schedule/ocr/`) rebuilds the classes. A "Check your classes" screen lists what was found before anything is saved; classes the reading was not sure of are marked with why. The picture never leaves the phone. See [docs/photo-import.md](../docs/photo-import.md).
- **Class reminders** (Settings): the phone schedules local notifications a chosen number of minutes before each class over the next week, so they appear even when the app is closed.

### How reminders work, and their limits

`planReminders` (`lib/features/reminders/reminder_planner.dart`) lists a reminder before each class over the next seven days, leaving out holidays and skipped days. `ReminderController` replans whenever the schedule or the settings change and when the app returns to the foreground; `ReminderSync` remembers what is scheduled so each fires once and a changed plan replaces the old one.

- Open the app about once a week so every day stays covered.
- iOS keeps at most 64 pending notifications and drops the rest, so at most 60 are scheduled, the soonest first.
- Delivery has not been exercised on a device or in the simulator (notification permission cannot be granted from the command line); the scheduling is covered by tests with a fake scheduler.
- Exact alarms keep Android reminders on time; without that permission they can be a few minutes late.

### Map tiles

Without configuration the map uses OpenStreetMap's public tile server, which is fine for development but not for wide release (see their tile usage policy). For a real build use a hosted provider with your own key: copy `dart_defines.example.json` to `dart_defines.json` (git-ignored), set `TILE_PROVIDER` (`maptiler` or `stadia`) and `TILE_KEY`, and run with `--dart-define-from-file=dart_defines.json`. Both are needed; a key with no provider is ignored and never sent anywhere. The key is compiled into the app, so restrict it to the app's bundle id in the provider's dashboard. The tile provider sees the area the map shows and the phone's network address.

### App icon

The icon and launch image are drawn by `scripts/make_icon.swift` and written at every size by `scripts/make_icons.sh` (macOS; needs `swift` and `sips`).

## Run it

```bash
flutter pub get
flutter run
```

## Code layout

`lib/campus` (the campus, search, terms), `lib/core` (clock, time formatting, tiles), `lib/features/{today,schedule,map,search,directions,reminders,settings}`, `lib/design` (tokens and components). Screens and controllers are tested against fakes; the campus search and the schedule and calendar readers are tested against outputs recorded from the Python code they replaced (`test/fixtures/golden_port.json`).

```bash
flutter analyze
flutter test
flutter test integration_test/app_test.dart -d <simulator>
```
