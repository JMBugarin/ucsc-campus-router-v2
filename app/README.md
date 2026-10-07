# UCSC Router (Android app)

Your classes, the walk to each, and when to leave. It is a thin client for the project's server: the phone keeps your schedule, the server works out walking times and forgets everything straight away.

## What it does
- **Today**: what is happening now, the next class, the walk from where you are, free time, and a verdict on each gap between classes.
- **Schedule**: paste from MyUCSC, import a calendar (.ics) file, or add a class by hand. Saved on the phone only; instructor names are never kept.
- **Settings**: server address (with a connection test), whether to use your location, and how early the "leave soon" banner appears.

- **Route map**: "Show route" on the walk card (or the map button on any class) draws the walk from where you are to the best door, with distance and minutes. Dotted lines join you and the door to the nearest path points.
- **Leave-now reminders** (Settings): the phone schedules Android notifications from the server's reminder plan, so they appear even when the app is closed.

### How reminders work, and their limits
The server decides when to remind (`plan_reminders`); the app schedules those times with Android and remembers which have fired. The plan is made when the app opens or refreshes, for your **next class today**, using the walk from where you were then. So: open the app once in the morning and the reminders for the next class are set; later classes are planned after the next refresh. If you never open the app, nothing new is planned. Turning on exact alarms makes them arrive on time; without that permission Android may delay them a few minutes.

### Map tiles
Tiles come from OpenStreetMap's public tile server, which is fine for a personal or demo app but not for heavy use (see their tile usage policy). Swap the `urlTemplate` in `route_screen.dart` for your own tile provider before wide release.

## Run it
Start the server first (see the main README), then:

```bash
flutter pub get
flutter run          # on an emulator the dev machine is http://10.0.2.2:8000
```

Plain `http` is allowed only in debug builds (for the dev machine). A release build needs an `https` server address, such as the hosted deployment in `docs/hosting.md`.

## Code layout
`lib/core` (API client, address cleanup, time formatting) and `lib/features/{today,schedule,settings,location}`. State uses Riverpod notifiers with a repository per feature, so screens and controllers are tested against fakes, and models are tested against JSON captured from the real server (`test/fixtures`, built from an invented schedule).

```bash
flutter analyze
flutter test
```
