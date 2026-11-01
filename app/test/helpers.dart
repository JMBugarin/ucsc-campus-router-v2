import 'dart:convert';
import 'dart:io';

import 'package:classmap/app.dart';
import 'package:classmap/campus/campus_data.dart';
import 'package:classmap/campus/terms.dart';
import 'package:classmap/core/clock.dart';
import 'package:classmap/core/tiles.dart';
import 'package:classmap/features/directions/directions.dart';
import 'package:classmap/features/reminders/reminder.dart';
import 'package:classmap/features/reminders/reminder_scheduler.dart';
import 'package:classmap/features/schedule/meeting.dart';
import 'package:classmap/features/schedule/ocr/picture_picker.dart';
import 'package:classmap/features/schedule/ocr/recognized_text.dart';
import 'package:classmap/features/schedule/ocr/text_recognizer.dart';
import 'package:classmap/features/schedule/schedule_repository.dart';
import 'package:classmap/features/schedule/schedule_screen.dart';
import 'package:classmap/features/schedule/term.dart';
import 'package:classmap/features/search/place.dart';
import 'package:classmap/features/search/search_repository.dart';
import 'package:classmap/features/settings/settings.dart';
import 'package:classmap/features/today/today_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

Meeting meeting({
  String course = 'XYZ 10',
  String component = 'Lecture',
  List<int> days = const [0, 2, 4],
  String start = '14:40',
  String end = '15:45',
  String location = 'Kresge Acad 3201',
}) => Meeting(
  course: course,
  component: component,
  days: days,
  start: start,
  end: end,
  location: location,
  startDate: '2026-09-24',
  endDate: '2026-12-04',
);

/// Stands in for the phone's storage and the schedule reader.
class FakeScheduleRepository implements ScheduleRepository {
  FakeScheduleRepository({List<Meeting> stored = const []})
    : stored = [...stored];

  List<Meeting> stored;
  ImportResult? nextImport;
  Object? failWith;
  final calls = <String>[];

  /// When set, imports wait for it, like a slow reader.
  Future<void>? hold;

  Future<ImportResult> _result() async {
    await hold;
    if (failWith != null) throw failWith!;
    return nextImport ??
        const ImportResult(meetings: [], notes: [], locations: []);
  }

  @override
  Future<List<Meeting>> load() async => [...stored];

  /// When set, saving waits for it; [saveFails] makes saving throw.
  Future<void>? saveHold;
  Object? saveFails;

  @override
  Future<void> save(List<Meeting> meetings) async {
    await saveHold;
    if (saveFails != null) throw saveFails!;
    stored = [...meetings];
  }

  @override
  Future<ImportResult> importText(String text) async {
    calls.add('text:$text');
    return _result();
  }

  @override
  Future<ImportResult> importCalendar(String text) async {
    calls.add('ics:$text');
    return _result();
  }

  @override
  Future<ImportResult> clean(List<Meeting> meetings) async {
    calls.add('clean:${meetings.length}');
    await hold;
    if (failWith != null) throw failWith!;
    return nextImport ??
        ImportResult(
          meetings: meetings,
          notes: const [],
          locations: [
            for (final _ in meetings)
              const LocationInfo(kind: 'building', buildingName: 'Some Hall'),
          ],
        );
  }
}

/// Records what would have been shown or scheduled on the phone.
class FakeReminderScheduler implements ReminderScheduler {
  bool allowed = true;
  bool failing = false;
  final shown = <String>[];
  final scheduled = <String, DateTime>{};
  final cancelled = <String>[];
  int scheduleCalls = 0;

  void _check() {
    if (failing) throw StateError('notifications are broken');
  }

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  Future<void> show(Reminder reminder) async {
    _check();
    shown.add(reminder.key);
  }

  @override
  Future<void> schedule(Reminder reminder, DateTime at) async {
    _check();
    scheduleCalls++;
    scheduled[reminder.key] = at;
  }

  @override
  Future<void> cancel(String key) async {
    cancelled.add(key);
    scheduled.remove(key);
  }
}

class FakeSearchRepository implements SearchRepository {
  Object answer = <Place>[];
  final queries = <String>[];

  /// What the campus data makes of each room, by the text asked about; a room not listed is a building it knows.
  final resolutions = <String, Object>{};
  final resolved = <String>[];

  @override
  Future<RoomResolution> resolve(String location) async {
    resolved.add(location);
    final r =
        resolutions[location] ??
        const RoomResolution(kind: 'building', roomKnown: true);
    if (r is RoomResolution) return r;
    throw r;
  }

  @override
  Future<List<Place>> search(String query) async {
    queries.add(query);
    final a = answer;
    if (a is List<Place>) return a;
    throw a;
  }
}

/// Stands in for the system photo picker: [path] is what the student chooses, or null for nothing.
class FakePicturePicker implements PicturePicker {
  String? path;
  Object? failWith;
  int picks = 0;
  int released = 0;

  @override
  Future<String?> pick() async {
    picks++;
    if (failWith != null) throw failWith!;
    return path;
  }

  @override
  Future<void> release() async => released++;
}

/// Stands in for the phone's text recognition: [reading] is a [RecognizedText], or an exception to throw.
class FakeTextRecognizer implements TextRecognizer {
  Object reading = const RecognizedText(width: 1, height: 1, lines: []);
  final paths = <String>[];

  /// When set, reading waits for it, like a slow picture.
  Future<void>? hold;

  @override
  Future<RecognizedText> recognize(String path) async {
    paths.add(path);
    await hold;
    final r = reading;
    if (r is RecognizedText) return r;
    throw r;
  }
}

/// Records the links the app tried to open.
class FakeUrlOpener {
  final opened = <Uri>[];
  bool succeeds = true;

  Future<bool> call(Uri uri) async {
    opened.add(uri);
    return succeeds;
  }
}

/// The campus data and terms the app ships, read from the files so no test waits on the asset bundle.
final testCampus = campusFromJson(
  buildings: File('assets/data/buildings.json').readAsStringSync(),
  rooms: File('assets/data/rooms.json').readAsStringSync(),
  aliases: File('assets/data/search_aliases.json').readAsStringSync(),
);
final testTerms = termsFromJson(
  jsonDecode(File('assets/data/holidays.json').readAsStringSync())
      as Map<String, dynamic>,
);

/// Everything a screen test needs, with the fakes exposed so tests can look at them.
class TestRig {
  TestRig({
    List<Meeting> stored = const [],
    bool remindersOn = false,
    this.startTab = tabToday,
    this.now,
    this.pictureImport = true,
    this.term,
    this.stubTerm = false,
    this.fakeSearch = false,
    Map<String, Object> prefs = const {},
  }) : schedule = FakeScheduleRepository(stored: stored),
       scheduler = FakeReminderScheduler(),
       search = FakeSearchRepository(),
       urls = FakeUrlOpener(),
       picker = FakePicturePicker(),
       recognizer = FakeTextRecognizer() {
    SharedPreferences.setMockInitialValues({
      'reminders_on': remindersOn,
      ...prefs,
    });
  }

  final FakeScheduleRepository schedule;
  final FakeReminderScheduler scheduler;
  final FakeSearchRepository search;
  final FakeUrlOpener urls;
  final FakePicturePicker picker;
  final FakeTextRecognizer recognizer;
  final int startTab;

  /// Whether this phone can read a picture of a schedule.
  final bool pictureImport;

  /// The term reported to the add-a-class form, if any. Only used when [stubTerm] is set or a term is given.
  final ({String start, String end})? term;
  final bool stubTerm;

  /// Searches with [search] instead of the bundled campus data.
  final bool fakeSearch;

  /// Pins the app's clock when set (a UTC instant).
  final DateTime? now;

  String? pickedCalendarText;

  Future<List<Override>> overrides() async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = now;
    return [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (pinned != null) clockProvider.overrideWithValue(() => pinned),
      campusProvider.overrideWith((ref) => testCampus),
      termsProvider.overrideWith((ref) => testTerms),
      scheduleRepositoryProvider.overrideWithValue(schedule),
      reminderSchedulerProvider.overrideWithValue(scheduler),
      if (fakeSearch) searchRepositoryProvider.overrideWithValue(search),
      urlOpenerProvider.overrideWithValue(urls.call),
      selectedTabProvider.overrideWith(() => SelectedTab(startTab)),
      showMapTilesProvider.overrideWithValue(false),
      todayRefreshIntervalProvider.overrideWithValue(
        null,
      ), // no timers left running after a test
      calendarFilePickerProvider.overrideWithValue(
        () async => pickedCalendarText,
      ),
      picturePickerProvider.overrideWithValue(picker),
      textRecognizerProvider.overrideWithValue(recognizer),
      pictureImportAvailableProvider.overrideWithValue(pictureImport),
      if (stubTerm || term != null)
        termProvider.overrideWith((ref) async => term),
    ];
  }

  Future<ProviderContainer> container() async {
    final container = ProviderContainer(
      retry: (count, error) => null,
      overrides: await overrides(),
    );
    return container;
  }

  Future<Widget> app() async => ProviderScope(
    retry: (count, error) => null,
    overrides: await overrides(),
    child: const ClassmapApp(),
  );
}

/// Monday 2026-10-12, noon on the campus clock, before the default class at 2:40 PM.
final mondayNoon = DateTime.utc(2026, 10, 12, 19);
