import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ucsc_router/app.dart';
import 'package:ucsc_router/features/location/location_service.dart';
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

  ImportResult _result() {
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
  final requests = <({List<Meeting> meetings, GeoPoint? here, int lead})>[];

  @override
  Future<Analysis> today({
    required List<Meeting> meetings,
    GeoPoint? here,
    int remindLeadMinutes = 5,
    List<String> reminded = const [],
  }) async {
    requests.add((meetings: meetings, here: here, lead: remindLeadMinutes));
    final a = answer;
    if (a is Analysis) return a;
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

/// Everything a screen test needs, with the fakes exposed so tests can look at them.
class TestRig {
  TestRig({
    List<Meeting> stored = const [],
    Object? analysis,
    String serverUrl = 'https://router.example',
    bool useLocation = true,
  })  : schedule = FakeScheduleRepository(stored: stored),
        today = FakeTodayRepository(analysis ?? Analysis.fromJson(fixture('today_before_class'))),
        location = FakeLocationService() {
    SharedPreferences.setMockInitialValues({'server_url': serverUrl, 'use_location': useLocation});
  }

  final FakeScheduleRepository schedule;
  final FakeTodayRepository today;
  final FakeLocationService location;
  String? pickedCalendarText;

  Future<List<Override>> overrides() async {
    final prefs = await SharedPreferences.getInstance();
    return [
      sharedPreferencesProvider.overrideWithValue(prefs),
      scheduleRepositoryProvider.overrideWithValue(schedule),
      todayRepositoryProvider.overrideWithValue(today),
      locationServiceProvider.overrideWithValue(location),
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
