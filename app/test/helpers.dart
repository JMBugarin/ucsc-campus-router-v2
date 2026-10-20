import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ucsc_router/app.dart';
import 'package:ucsc_router/core/clock.dart';
import 'package:ucsc_router/core/tiles.dart';
import 'package:ucsc_router/features/location/location_service.dart';
import 'package:ucsc_router/features/reminders/reminder_scheduler.dart';
import 'package:ucsc_router/features/route/destination.dart';
import 'package:ucsc_router/features/search/place.dart';
import 'package:ucsc_router/features/search/search_repository.dart';
import 'package:ucsc_router/features/route/route_plan.dart';
import 'package:ucsc_router/features/route/route_repository.dart';
import 'package:ucsc_router/features/schedule/meeting.dart';
import 'package:ucsc_router/features/schedule/schedule_repository.dart';
import 'package:ucsc_router/features/schedule/schedule_screen.dart';
import 'package:ucsc_router/features/settings/settings.dart';
import 'package:ucsc_router/features/today/today_controller.dart';
import 'package:ucsc_router/features/today/today_models.dart';
import 'package:ucsc_router/features/today/today_repository.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

Meeting meeting({
  String course = 'XYZ 10',
  String component = 'Lecture',
  List<int> days = const [0, 2, 4],
  String start = '14:40',
  String end = '15:45',
  String location = 'Kresge Acad 3201',
}) =>
    Meeting(
      course: course,
      component: component,
      days: days,
      start: start,
      end: end,
      location: location,
      startDate: '2026-09-24',
      endDate: '2026-12-04',
    );

/// Stands in for the server and for the phone's storage.
class FakeScheduleRepository implements ScheduleRepository {
  FakeScheduleRepository({List<Meeting> stored = const []}) : stored = [...stored];

  List<Meeting> stored;
  ImportResult? nextImport;
  Object? failWith;
  final calls = <String>[];

  /// When set, imports wait for it, like a server that is slow to answer.
  Future<void>? hold;

  Future<ImportResult> _result() async {
    await hold;
    if (failWith != null) throw failWith!;
    return nextImport ?? const ImportResult(meetings: [], notes: [], locations: []);
  }

  @override
  Future<List<Meeting>> load() async => [...stored];

  @override
  Future<void> save(List<Meeting> meetings) async => stored = [...meetings];

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
          locations: [for (final _ in meetings) const LocationInfo(kind: 'building', buildingName: 'Some Hall')],
        );
  }
}

class FakeTodayRepository implements TodayRepository {
  FakeTodayRepository(this.answer);

  Object answer; // an Analysis, or an exception to throw
  final requests = <({List<Meeting> meetings, GeoPoint? here, int lead, List<String> reminded, DateTime? at})>[];

  @override
  Future<Analysis> today({
    required List<Meeting> meetings,
    GeoPoint? here,
    int remindLeadMinutes = 5,
    List<String> reminded = const [],
    DateTime? at,
  }) async {
    requests.add((meetings: meetings, here: here, lead: remindLeadMinutes, reminded: reminded, at: at));
    final a = answer;
    if (a is Analysis) return a;
    if (a is Future<Analysis>) return a;
    throw a;
  }
}

class FakeLocationService implements LocationService {
  FakeLocationService([this.result = const LocationResult.found(GeoPoint(36.9998, -122.0628))]);

  LocationResult result;
  int calls = 0;

  @override
  Future<LocationResult> current() async {
    calls++;
    return result;
  }
}

/// Records what would have been shown or scheduled on the phone.
class FakeReminderScheduler implements ReminderScheduler {
  bool allowed = true;
  bool failing = false;
  final shown = <String>[];
  final scheduled = <String, DateTime>{};
  final cancelled = <String>[];

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
    scheduled[reminder.key] = at;
  }

  @override
  Future<void> cancel(String key) async {
    cancelled.add(key);
    scheduled.remove(key);
  }
}

class FakeRouteRepository implements RouteRepository {
  Object answer = RoutePlan.fromJson(fixture('route_to_room'), start: const GeoPoint(36.9998, -122.0628));
  final requests = <({GeoPoint from, Destination destination})>[];

  @override
  Future<RoutePlan> to({required GeoPoint from, required Destination destination}) async {
    requests.add((from: from, destination: destination));
    final a = answer;
    if (a is RoutePlan) return a;
    throw a;
  }
}

class FakeSearchRepository implements SearchRepository {
  Object answer = <Place>[];
  final queries = <String>[];

  @override
  Future<List<Place>> search(String query) async {
    queries.add(query);
    final a = answer;
    if (a is List<Place>) return a;
    throw a;
  }
}

/// Everything a screen test needs, with the fakes exposed so tests can look at them.
class TestRig {
  TestRig({
    List<Meeting> stored = const [],
    Object? analysis,
    String serverUrl = 'https://router.example',
    bool useLocation = true,
    bool remindersOn = false,
    this.startTab = tabToday,
    this.now,
    Map<String, Object> prefs = const {},
  })  : schedule = FakeScheduleRepository(stored: stored),
        today = FakeTodayRepository(analysis ?? Analysis.fromJson(fixture('today_before_class'))),
        location = FakeLocationService(),
        scheduler = FakeReminderScheduler(),
        route = FakeRouteRepository(),
        search = FakeSearchRepository() {
    SharedPreferences.setMockInitialValues({
      'server_url': serverUrl,
      'use_location': useLocation,
      'reminders_on': remindersOn,
      ...prefs,
    });
  }

  final FakeScheduleRepository schedule;
  final FakeTodayRepository today;
  final FakeLocationService location;
  final FakeReminderScheduler scheduler;
  final FakeRouteRepository route;
  final FakeSearchRepository search;
  final int startTab;

  /// Pins the app's clock when set (a UTC instant).
  final DateTime? now;
  String? pickedCalendarText;
  int warmUps = 0;

  Future<List<Override>> overrides() async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = now;
    return [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (pinned != null) clockProvider.overrideWithValue(() => pinned),
      serverWarmUpProvider.overrideWithValue(() async => warmUps++),
      scheduleRepositoryProvider.overrideWithValue(schedule),
      todayRepositoryProvider.overrideWithValue(today),
      locationServiceProvider.overrideWithValue(location),
      reminderSchedulerProvider.overrideWithValue(scheduler),
      routeRepositoryProvider.overrideWithValue(route),
      searchRepositoryProvider.overrideWithValue(search),
      selectedTabProvider.overrideWith(() => SelectedTab(startTab)),
      showMapTilesProvider.overrideWithValue(false),
      todayRefreshIntervalProvider.overrideWithValue(null), // no timers left running after a test
      calendarFilePickerProvider.overrideWithValue(() async => pickedCalendarText),
    ];
  }

  Future<ProviderContainer> container() async {
    final container = ProviderContainer(retry: (count, error) => null, overrides: await overrides());
    return container;
  }

  Future<Widget> app() async => ProviderScope(
        retry: (count, error) => null,
        overrides: await overrides(),
        child: const UcscRouterApp(),
      );
}
