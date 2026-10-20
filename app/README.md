# UCSC Router (Android app)

Your classes, the walk to each, and when to leave. It is a thin client for the project's server: the phone keeps your schedule, the server works out walking times and forgets everything straight away.

## What it does
- **Today**: what is happening now, the next class, the walk from where you are, free time, and a verdict on each gap between classes.
- **Day picker**: step through any day of your schedule (arrows, or tap the date for a calendar) to see its classes and the gaps between them; "Today" brings you back. Other days show no walk, reminders or GPS use. A week view is not built yet.
- **Works offline**: when the server can't be reached, Today lists your classes, says what is now and next, and gives the walk times saved from the last time it could be reached (`WalkCache`). A blue "Offline" card at the top says so and how long ago the walk times were last updated (a warning once they are a week old), and the walk is worded "Saved walk time" so it is not mistaken for a live one. "Try again" asks the server again. Reminders already set stay set. It uses a Dart copy of the server's timetable logic; both are tested against the same cases in `server/testdata/schedule_cases.json`. A class you have never seen a walk time for shows no walk until you are back online.
- **Saved view while the server answers**: when the phone already has walk times saved, Today shows them at once under an "Updating…" card instead of a bare spinner, and replaces them when the server answers (useful when a sleeping host takes a minute).
- **Schedule**: paste from MyUCSC, import a calendar (.ics) file, or add a class by hand. Saved on the phone only; instructor names are never kept.
- **Settings**: server address (with a connection test), whether to use your location, and how early the "leave soon" banner appears.

- **Route map**: "Show route" on the walk card (or the map button on any class) draws the walk from where you are to the best door, with distance and minutes. Dotted lines join you and the door to the nearest path points.
- **Leave-now reminders** (Settings): the phone schedules local notifications for every class over the next week, so they appear even when the app is closed.

### How reminders work, and their limits
For today the server decides when to remind (`plan_reminders`, which knows where you are). For every class over the next seven days the phone plans the reminders itself (`planAhead`, in `lib/features/reminders/reminder_planner.dart`) from the walk times it has saved, by the same rules: a heads-up and a "leave now", a class that follows another is walked to from it and never reminded before that one ends, holidays and skipped dates are left out. The phone schedules them with the system (Android alarms, iOS local notifications) and remembers which have fired, so they fire with the app closed, tomorrow and the day after, without opening it. The plan is replaced whenever the app opens, comes back to the foreground or refreshes, so open it about once a week and every day is covered. If a class has no reminder planned yet, the phone asks the server in the background about the days ahead whose walks between classes it has not saved (at most once per day of the week per run).

Limits:
- A class gets a reminder only when a walk time is saved for it. The first class of a day uses the walk from your own location as last timed (open Today with location on once, near that class); a later class uses the walk between the two rooms. Online classes, unknown rooms and classes never timed get none. A saved walk may not match where you start tomorrow, so a first-class reminder can be early or late.
- Holidays are learned from the server's answers, so the very first plan, before the server has answered once, does not know them.
- iOS keeps at most 64 pending notifications and silently drops the rest, so at most 60 are scheduled, the soonest first.
- Notification delivery has not been exercised on a device or in the simulator (iOS notification permission cannot be granted from the command line); the scheduling is covered by tests with a fake scheduler.
- Turning on exact alarms makes Android reminders arrive on time; without that permission Android may delay them a few minutes.

### Map tiles
Without configuration the map uses OpenStreetMap's public tile server, which is fine for development but not for wide release (see their tile usage policy). For a real build use a hosted provider with your own key: copy `dart_defines.example.json` to `dart_defines.json` (git-ignored), set `TILE_PROVIDER` (`maptiler` or `stadia`) and `TILE_KEY`, and run with `--dart-define-from-file=dart_defines.json`. The key is compiled into the app, so restrict it to this app's bundle id in the provider's dashboard. The provider URLs and attributions are in `lib/core/tiles.dart`; they have not been tried against a live account, so check them against the provider's current docs when you set a key.

### When the hosted server is asleep
The default server is on a free plan that sleeps when idle and needs up to a minute to wake. The app sends an empty `GET /healthz` when it opens and when it returns to the foreground, so the wake-up starts before you need an answer. Every screen that waits on the server (Today, Map search, routes, schedule import, Settings) says so after four seconds. Requests that can safely be repeated (all reads, the Today calculation and the schedule checks, never photo import) are tried again once after a timeout (45 s per try) or a refused connection, and up to twice after a 502, 503 or 504. Today shows the saved view instead (see "Works offline") if the server still does not answer.

## Run it
Run the app (the hosted server is used by default):

```bash
flutter pub get
flutter run          # (add --dart-define-from-file=dart_defines.json for hosted map tiles) on an emulator the dev machine is http://10.0.2.2:8000
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
