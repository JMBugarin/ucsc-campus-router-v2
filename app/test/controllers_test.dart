import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/core/pacific.dart';
import 'package:ucsc_router/features/location/location_service.dart';
import 'package:ucsc_router/features/schedule/meeting.dart';
import 'package:ucsc_router/features/schedule/schedule_controller.dart';
import 'package:ucsc_router/features/settings/settings.dart';
import 'package:ucsc_router/features/today/today_controller.dart';

import 'helpers.dart';

/// Monday 2026-10-12, noon on the campus clock, before the default class at 2:40 PM.
final mondayNoon = DateTime.utc(2026, 10, 12, 19);

void main() {
  group('schedule', () {
    test('importing merges, skips classes already there, and reports the notes', () async {
      final rig = TestRig(stored: [meeting()]);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(scheduleProvider.future);

      rig.schedule.nextImport = ImportResult(
        meetings: [meeting(), meeting(course: 'ABC 20', start: '16:00', end: '17:05')],
        notes: ['Skipped DEF 30 (dropped).'],
        locations: const [],
      );
      final summary = await container.read(scheduleProvider.notifier).importText('pasted');

      expect(summary.added, 1);
      expect(summary.alreadyThere, 1);
      expect(summary.message, 'Added 1 class (1 already there). Skipped DEF 30 (dropped).');
      expect(container.read(scheduleProvider).value!.map((m) => m.course), ['XYZ 10', 'ABC 20']);
      expect(rig.schedule.stored.length, 2, reason: 'it is saved to the phone');
    });

    test('a calendar file goes to the calendar reader', () async {
      final rig = TestRig();
      final container = await rig.container();
      addTearDown(container.dispose);
      rig.schedule.nextImport = ImportResult(meetings: [meeting()], notes: const [], locations: const []);
      await container.read(scheduleProvider.future);

      await container.read(scheduleProvider.notifier).importCalendar('BEGIN:VCALENDAR');
      expect(rig.schedule.calls, ['ics:BEGIN:VCALENDAR']);
    });

    test('a class typed by hand is checked by the server, then saved', () async {
      final rig = TestRig();
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(scheduleProvider.future);

      await container.read(scheduleProvider.notifier).add(meeting(location: 'Thim Lecture 003'));
      expect(rig.schedule.calls, ['clean:1']);
      expect(container.read(scheduleProvider).value!.single.location, 'Thim Lecture 003');
    });

    test('a rejected class is not saved, and the error reaches the caller', () async {
      final rig = TestRig();
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(scheduleProvider.future);
      rig.schedule.failWith = const ApiException('Bad: the end time must be after the start time',
          kind: ApiErrorKind.rejected);

      await expectLater(
        container.read(scheduleProvider.notifier).add(meeting()),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('end time'))),
      );
      expect(container.read(scheduleProvider).value, isEmpty);
    });

    test('removing and clearing', () async {
      final rig = TestRig(stored: [meeting(), meeting(course: 'ABC 20')]);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(scheduleProvider.future);

      await container.read(scheduleProvider.notifier).removeAt(0);
      expect(container.read(scheduleProvider).value!.map((m) => m.course), ['ABC 20']);
      await container.read(scheduleProvider.notifier).clear();
      expect(container.read(scheduleProvider).value, isEmpty);
      expect(rig.schedule.stored, isEmpty);
    });

    test('rooms the server cannot place are reported, and a dead server flags nothing', () async {
      final rig = TestRig(stored: [meeting()]);
      final container = await rig.container();
      addTearDown(container.dispose);
      rig.schedule.nextImport = const ImportResult(
        meetings: [],
        notes: [],
        locations: [LocationInfo(kind: 'unknown')],
      );
      expect((await container.read(locationInfoProvider.future)).single.isUnknown, isTrue);

      rig.schedule.failWith = const ApiException('offline', kind: ApiErrorKind.offline);
      container.invalidate(locationInfoProvider);
      expect(await container.read(locationInfoProvider.future), isEmpty);
    });
  });

  group('today', () {
    test('with no classes there is nothing to ask the server', () async {
      final rig = TestRig();
      final container = await rig.container();
      addTearDown(container.dispose);

      final data = await container.read(todayProvider.future);
      expect(data.hasSchedule, isFalse);
      expect(rig.today.requests, isEmpty);
      expect(rig.location.calls, 0);
    });

    test('asks the server with the classes and where the phone is', () async {
      final rig = TestRig(stored: [meeting()], now: mondayNoon);
      final container = await rig.container();
      addTearDown(container.dispose);

      final data = await container.read(todayProvider.future);
      expect(data.analysis!.next!.label, 'XYZ 10 Lecture');
      expect(rig.today.requests.single.here, const GeoPoint(36.9998, -122.0628));
      expect(rig.today.requests.single.lead, 5);
      expect(data.locationProblem, isNull);
    });

    test('without location permission it still works and says why there is no location', () async {
      final rig = TestRig(stored: [meeting()], now: mondayNoon);
      rig.location.result = const LocationResult.unavailable('Location permission was not given.');
      final container = await rig.container();
      addTearDown(container.dispose);

      final data = await container.read(todayProvider.future);
      expect(rig.today.requests.single.here, isNull);
      expect(data.locationProblem, 'Location permission was not given.');
      expect(data.analysis, isNotNull);
    });

    test('the location setting off means the phone is never asked', () async {
      final rig = TestRig(stored: [meeting()], useLocation: false);
      final container = await rig.container();
      addTearDown(container.dispose);

      await container.read(todayProvider.future);
      expect(rig.location.calls, 0);
      expect(rig.today.requests.single.here, isNull);
    });

    test('a recent location is reused instead of asking the phone again', () async {
      final rig = TestRig(stored: [meeting()], now: mondayNoon);
      final container = await rig.container();
      addTearDown(container.dispose);

      await container.read(todayProvider.future);
      await container.read(todayProvider.notifier).refresh();
      await container.read(todayProvider.notifier).refresh();
      expect(rig.location.calls, 1);
      expect(rig.today.requests.length, 3, reason: 'the day is still recomputed each time');
    });

    group('the phone is asked where it is only when a walk from there could matter', () {
      final later = meeting(course: 'ABC 20', start: '16:00', end: '17:05');
      final cases = [
        (when: 'before the first class', now: DateTime.utc(2026, 10, 12, 19), asks: true),
        (when: 'between two classes', now: DateTime.utc(2026, 10, 12, 22, 50), asks: true),
        (when: 'in a class, which the walk starts from', now: DateTime.utc(2026, 10, 12, 22), asks: false),
        (when: 'after the last class', now: DateTime.utc(2026, 10, 13, 1), asks: false),
        (when: 'on a weekend', now: DateTime.utc(2026, 10, 10, 19), asks: false),
        (when: 'on a day with no classes', now: DateTime.utc(2026, 10, 13, 19), asks: false),
      ];
      for (final c in cases) {
        test(c.when, () async {
          final rig = TestRig(stored: [meeting(), later], now: c.now);
          final container = await rig.container();
          addTearDown(container.dispose);
          await container.read(todayProvider.future);
          expect(rig.location.calls, c.asks ? 1 : 0);
          expect(rig.today.requests.single.here, c.asks ? const GeoPoint(36.9998, -122.0628) : isNull);
        });
      }

      test('on a holiday', () async {
        final rig = TestRig(stored: [meeting()], now: mondayNoon, prefs: {
          'walk_cache_v1': jsonEncode({'walks': <String, int>{}, 'any': <String, int>{}, 'holidays': ['2026-10-12']}),
        });
        final container = await rig.container();
        addTearDown(container.dispose);
        await container.read(todayProvider.future);
        expect(rig.location.calls, 0);
      });

      test('and no location problem is shown when it was not needed', () async {
        final rig = TestRig(stored: [meeting()], now: DateTime.utc(2026, 10, 13, 1));
        rig.location.result = const LocationResult.unavailable('Location permission was not given.');
        final container = await rig.container();
        addTearDown(container.dispose);
        final data = await container.read(todayProvider.future);
        expect(data.locationProblem, isNull);
      });
    });

    test('a failed manual refresh shows the error; a failed quiet one keeps the last answer', () async {
      final rig = TestRig(stored: [meeting()]);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(todayProvider.future);

      rig.today.answer = const ApiException('The server said no.', kind: ApiErrorKind.rejected);
      await container.read(todayProvider.notifier).refresh(quiet: true);
      expect(container.read(todayProvider).hasValue, isTrue);
      expect(container.read(todayProvider).hasError, isFalse);

      await container.read(todayProvider.notifier).refresh();
      expect(container.read(todayProvider).hasError, isTrue);
    });

    test('with the server unreachable the day is worked out on the phone from saved walk times', () async {
      final rig = TestRig(stored: [meeting()]);
      final container = await rig.container();
      addTearDown(container.dispose);
      final online = await container.read(todayProvider.future);
      expect(online.offline, isFalse);

      for (final kind in [ApiErrorKind.offline, ApiErrorKind.timeout, ApiErrorKind.server]) {
        rig.today.answer = ApiException('down', kind: kind);
        await container.read(todayProvider.notifier).refresh();
        final data = container.read(todayProvider).requireValue;
        expect(data.offline, isTrue, reason: '$kind');
        expect(data.analysis, isNotNull);
        expect(data.analysis!.reminders, isEmpty);
      }
    });

    test('rate limiting and a bad address are still errors, not offline mode', () async {
      final rig = TestRig(stored: [meeting()]);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(todayProvider.future);
      for (final kind in [ApiErrorKind.rateLimited, ApiErrorKind.notConfigured, ApiErrorKind.rejected]) {
        rig.today.answer = ApiException('no', kind: kind);
        await container.read(todayProvider.notifier).refresh();
        expect(container.read(todayProvider).hasError, isTrue, reason: '$kind');
      }
    });

    test('another day is asked for by its date, and leaves location and reminders alone', () async {
      final rig = TestRig(stored: [meeting()], remindersOn: true);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(todayProvider.future);
      final plannedBefore = rig.scheduler.scheduled.length;
      final locationsBefore = rig.location.calls;

      final soon = DateTime.now().add(const Duration(days: 3));
      container.read(viewedDayProvider.notifier).show(soon);
      final data = await container.read(todayProvider.future);

      expect(data.viewDay, isNotNull);
      final request = rig.today.requests.last;
      expect(request.at, isNotNull);
      expect(request.here, isNull);
      expect(rig.location.calls, locationsBefore);
      expect(rig.scheduler.scheduled.length, plannedBefore);
      expect(rig.scheduler.cancelled, isEmpty);

      container.read(viewedDayProvider.notifier).backToToday();
      expect((await container.read(todayProvider.future)).viewDay, isNull);
    });

    test('picking today goes back to today rather than a fixed date', () async {
      final rig = TestRig(stored: [meeting()]);
      final container = await rig.container();
      addTearDown(container.dispose);
      final today = pacificTime(DateTime.now());
      container.read(viewedDayProvider.notifier).show(DateTime(today.year, today.month, today.day));
      expect(container.read(viewedDayProvider), isNull);
    });

    test('changing the schedule recomputes the day', () async {
      final rig = TestRig(stored: [meeting()]);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(todayProvider.future);

      rig.schedule.nextImport = ImportResult(meetings: [meeting(course: 'ABC 20')], notes: const [], locations: const []);
      await container.read(scheduleProvider.notifier).importText('x');
      await container.read(todayProvider.future);
      expect(rig.today.requests.last.meetings.map((m) => m.course), ['XYZ 10', 'ABC 20']);
    });
  });

  group('settings', () {
    test('are remembered', () async {
      final rig = TestRig(serverUrl: '');
      final container = await rig.container();
      addTearDown(container.dispose);

      final controller = container.read(settingsProvider.notifier);
      await controller.setServerUrl('https://router.example');
      await controller.setUseLocation(false);
      await controller.setRemindLead(10);

      final s = container.read(settingsProvider);
      expect((s.serverUrl, s.useLocation, s.remindLeadMinutes), ('https://router.example', false, 10));
      final again = await rig.container();
      addTearDown(again.dispose);
      expect(again.read(settingsProvider).remindLeadMinutes, 10);
    });
  });
}
