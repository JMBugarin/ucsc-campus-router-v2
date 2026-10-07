# UCSC Router (Android app)

Your classes, the walk to each, and when to leave. It is a thin client for the project's server: the phone keeps your schedule, the server works out walking times and forgets everything straight away.

## What it does
- **Today**: what is happening now, the next class, the walk from where you are, free time, and a verdict on each gap between classes.
- **Schedule**: paste from MyUCSC, import a calendar (.ics) file, or add a class by hand. Saved on the phone only; instructor names are never kept.
- **Settings**: server address (with a connection test), whether to use your location, and how early the "leave soon" banner appears.

Not built yet: the map route screen and notifications that fire with the app closed.

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
