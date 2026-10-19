# UCSC Router (Android app)

Your classes, the walk to each, and when to leave. It is a thin client for the project's server: the phone keeps your schedule, the server works out walking times and forgets everything straight away.

## What it does
- **Today**: what is happening now, the next class, the walk from where you are, free time, and a verdict on each gap between classes.
- **Works offline**: when the server can't be reached, Today lists your classes, says what is now and next, and gives the walk times saved from the last time it could be reached (`WalkCache`). Reminders already set stay set. It uses a Dart copy of the server's timetable logic; both are tested against the same cases in `server/testdata/schedule_cases.json`. A class you have never seen a walk time for shows no walk until you are back online.
- **Schedule**: paste from MyUCSC, import a calendar (.ics) file, or add a class by hand. Saved on the phone only; instructor names are never kept.
- **Settings**: server address (with a connection test), whether to use your location, and how early the "leave soon" banner appears.

- **Route map**: "Show route" on the walk card (or the map button on any class) draws the walk from where you are to the best door, with distance and minutes. Dotted lines join you and the door to the nearest path points.
- **Leave-now reminders** (Settings): the phone schedules Android notifications from the server's reminder plan, so they appear even when the app is closed.

### How reminders work, and their limits
The server decides when to remind (`plan_reminders`); the app schedules those times with Android and remembers which have fired. The plan is made when the app opens, comes back to the foreground or refreshes, and covers **every class still to come today** (each walked to from the one before it, never earlier than that class ends). It is replaced whenever the schedule changes. So: open the app once in the morning and the whole day is set; open it again the next morning for the next day. If you never open the app, nothing new is planned. Turning on exact alarms makes them arrive on time; without that permission Android may delay them a few minutes.

### Map tiles
Tiles come from OpenStreetMap's public tile server, which is fine for a personal or demo app but not for heavy use (see their tile usage policy). Swap the `urlTemplate` in `route_screen.dart` for your own tile provider before wide release.

## Run it
Run the app (the hosted server is used by default):

```bash
flutter pub get
flutter run          # on an emulator the dev machine is http://10.0.2.2:8000
```

A fresh install talks to the hosted server (`https://ucsc-campus-router.onrender.com`). To point a build at another server, pass it at build time; the Settings screen can still override it at run time:

```bash
flutter run --dart-define=SERVER_URL=http://10.0.2.2:8000
```

Plain `http` is allowed only in debug builds (for the dev machine). A release build needs an `https` server address, such as the hosted deployment in `docs/hosting.md`.

## Code layout
`lib/core` (API client, address cleanup, time formatting) and `lib/features/{today,schedule,settings,location}`. State uses Riverpod notifiers with a repository per feature, so screens and controllers are tested against fakes, and models are tested against JSON captured from the real server (`test/fixtures`, built from an invented schedule).

```bash
flutter analyze
flutter test
```
