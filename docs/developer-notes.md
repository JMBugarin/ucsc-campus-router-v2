# Developer notes

## Layout

`app/lib`:

- `campus/` — `Campus` (resolve a schedule-style room, rank search results), the bundled data loaders, terms and holidays. Plain Dart.
- `features/schedule/` — the saved schedule, the paste, calendar and by-hand readers (`import/`), photo import (`ocr/`, `review/`) and the Schedule screen.
- `features/today/` — `day_plan.dart` works out the day from the schedule and the clock; the Today screen and week view show it.
- `features/map/`, `features/search/` — the map, search and the place card.
- `features/directions/` — which door to walk to and the link that opens the phone's maps app.
- `features/reminders/` — plans a reminder before each class and keeps the phone's scheduled notifications in step.
- `design/` — tokens, glass and solid components.

State uses Riverpod notifiers; repositories sit behind small interfaces so tests use fakes.

## Commands

```bash
cd app
flutter pub get
flutter analyze
flutter test
TZ=Pacific/Kiritimati flutter test        # CI also runs the tests where the calendar date differs from Pacific
flutter test integration_test/app_test.dart -d <simulator>
```

## Simulator checks

```bash
xcrun simctl boot "iPhone 17"
cd app && flutter test integration_test/app_test.dart -d <simulator id>
flutter test integration_test/picture_import_test.dart -d <simulator id>   # real Vision framework
```

`scripts/sim_screenshots.sh` is a host-side watcher that takes screenshots when an integration test asks for one (`SHOT_DIR`).

## Where the logic came from

The room search, schedule reader and calendar reader were Python (`room_parser.py`, `timetable.py`, `ics.py`) behind a server. They are Dart now. `app/test/port_parity_test.dart` runs them against `app/test/fixtures/golden_port.json`, recorded from the Python, and `app/test/day_plan_test.dart` runs the day logic against `fixtures/schedule_cases.json`. `data-pipeline/room_parser.py` is kept as the reference the parity cases came from and for its tests.

## Campus data

See [data/README.md](../data/README.md). To add a term: edit `data/holidays.json`, run `scripts/sync_app_data.sh`, run the tests. To correct a door: add an entry in `data/rooms.json`.

## Conventions

Conventional commits, one logical change each; everything lands through a pull request.
