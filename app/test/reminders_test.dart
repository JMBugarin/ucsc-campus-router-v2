import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:ucsc_router/core/pacific.dart';
import 'package:ucsc_router/features/reminders/reminder_scheduler.dart';
import 'package:ucsc_router/features/reminders/reminder_sync.dart';
import 'package:ucsc_router/features/schedule/meeting.dart';
import 'package:ucsc_router/features/settings/settings.dart';
import 'package:ucsc_router/features/today/today_controller.dart';
import 'package:ucsc_router/features/today/today_models.dart';

import 'helpers.dart';

List<Reminder> remindersIn(String fixtureName) => Analysis.fromJson(fixture(fixtureName)).reminders;

Reminder soon(String key, double inSeconds) =>
    Reminder(stage: 'leave', key: key, inSeconds: inSeconds, title: 'Time to leave', body: '');

/// Monday 2026-10-12, noon on the campus clock: the moment the fixtures were captured.
final mondayNoon = DateTime.utc(2026, 10, 12, 19);

tz.TZDateTime campus(int y, int m, int d, [int h = 0, int min = 0]) => tz.TZDateTime(pacific, y, m, d, h, min);

/// The same instant, whatever zone either side is written in.
Matcher sameMoment(DateTime moment) => predicate<DateTime>((t) => t.isAtSameMomentAs(moment), 'the moment $moment');

String savedWalks(Map<String, int> walks) => jsonEncode({
      'walks': walks,
      'any': {for (final e in walks.entries) e.key.split('>').last: e.value},
      'holidays': <String>[],
    });

/// What the server says about a day asked for by date: two classes with a walk between them.
Map<String, dynamic> tuesdayWithTwoClasses() => {
      'now': '2026-10-20T00:01:00-07:00',
      'state': 'before_classes',
      'reason': null,
      'current': null,
      'next': null,
      'walk': null,
      'free_min': null,
      'status': 'unknown',
      'leave_by': null,
      'today': [
        {
          'course': 'XYZ 10',
          'component': 'Lecture',
          'location': 'Kresge Acad 3201',
          'start': '2026-10-20T09:00:00-07:00',
          'end': '2026-10-20T09:50:00-07:00',
        },
        {
          'course': 'ABC 20',
          'component': 'Lecture',
          'location': 'Soc Sci 2 075',
          'start': '2026-10-20T10:00:00-07:00',
          'end': '2026-10-20T10:50:00-07:00',
          'gap_min': 10.0,
          'walk_min': 9,
          'free_min': 1.0,
          'status': 'tight',
        },
      ],
      'notes': <String>[],
      'reminders': <Object>[],
      'banner': null,
    };

void main() {
  final now = DateTime.utc(2026, 10, 12, 19, 0);

  group('notification ids', () {
    test('are the same every time and fit in 31 bits', () {
      expect(notificationId('2026-10-12T14:40:00-07:00|leave'), notificationId('2026-10-12T14:40:00-07:00|leave'));
      expect(notificationId('a'), isNot(notificationId('b')));
      for (final key in ['a', '2026-10-12T14:40:00-07:00|heads-up', 'x' * 500]) {
        expect(notificationId(key), inInclusiveRange(0, 0x7fffffff));
      }
    });
  });

  group('ReminderSync', () {
    late FakeReminderScheduler scheduler;
    late ReminderSync sync;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      scheduler = FakeReminderScheduler();
      sync = ReminderSync(scheduler, await SharedPreferences.getInstance());
    });

    test('schedules what is still to come at the right moment', () async {
      final plan = remindersIn('today_before_class');
      await sync.apply(plan, now);

      expect(scheduler.scheduled.keys, plan.map((r) => r.key));
      expect(scheduler.scheduled[plan[0].key], now.add(const Duration(seconds: 8580)));
      expect(scheduler.scheduled[plan[1].key], now.add(const Duration(seconds: 8880)));
      expect(scheduler.shown, isEmpty);
    });

    test('a whole day of reminders is scheduled, and dropping one class cancels only its own', () async {
      final plan = remindersIn('today_reminders_all_day');
      expect(plan.length, 6);
      await sync.apply(plan, now);
      expect(scheduler.scheduled.keys, plan.map((r) => r.key));

      final withoutMiddle = plan.where((r) => !r.key.contains('T11:00')).toList();
      await sync.apply(withoutMiddle, now);
      expect(scheduler.cancelled, plan.where((r) => r.key.contains('T11:00')).map((r) => r.key));
      expect(scheduler.scheduled.keys, withoutMiddle.map((r) => r.key));
    });

    test('a late reminder is shown straight away, once', () async {
      final plan = remindersIn('today_late');
      await sync.apply(plan, now);
      await sync.apply(plan, now.add(const Duration(minutes: 1)));
      expect(scheduler.shown, [plan.single.key]);
      expect(scheduler.scheduled, isEmpty);
    });

    test('a reminder is only reported as fired once its time has passed', () async {
      final plan = remindersIn('today_heads_up_soon'); // due in 2 s and 302 s
      await sync.apply(plan, now);

      expect(sync.firedKeys(now), isEmpty);
      expect(sync.firedKeys(now.add(const Duration(seconds: 10))), [plan[0].key]);
      expect(sync.firedKeys(now.add(const Duration(minutes: 6))), plan.map((r) => r.key));
    });

    test('planning again replaces rather than duplicates', () async {
      final plan = remindersIn('today_before_class');
      await sync.apply(plan, now);
      await sync.apply(plan, now.add(const Duration(minutes: 1)));
      expect(scheduler.scheduled.length, 2);
      expect(scheduler.cancelled, isEmpty);
    });

    test('a pending reminder the server dropped is cancelled', () async {
      final plan = remindersIn('today_before_class');
      await sync.apply(plan, now);
      await sync.apply([plan[1]], now.add(const Duration(minutes: 1)));
      expect(scheduler.cancelled, [plan[0].key]);
      expect(scheduler.scheduled.keys, [plan[1].key]);
    });

    test('one that already fired is not cancelled when it drops out of the plan', () async {
      final plan = remindersIn('today_heads_up_soon');
      await sync.apply(plan, now);
      await sync.apply([plan[1]], now.add(const Duration(seconds: 30)));
      expect(scheduler.cancelled, isEmpty);
    });

    test('clear cancels what is pending and forgets everything', () async {
      final plan = remindersIn('today_before_class');
      await sync.apply(plan, now);
      expect(sync.hasAny, isTrue);

      await sync.clear(now.add(const Duration(minutes: 1)));
      expect(scheduler.cancelled, plan.map((r) => r.key));
      expect(sync.hasAny, isFalse);
    });

    test('old entries are dropped after a day', () async {
      await sync.apply(remindersIn('today_heads_up_soon'), now);
      await sync.apply(const [], now.add(const Duration(days: 2)));
      expect(sync.hasAny, isFalse);
    });

    test('only the soonest reminders stay scheduled, within the platform limit', () async {
      final plan = [for (var i = 1; i <= 100; i++) soon('k$i', i * 60.0)];
      await sync.apply(plan, now);
      expect(scheduler.scheduled.length, maxPendingReminders);
      expect(scheduler.scheduled.keys, [for (var i = 1; i <= maxPendingReminders; i++) 'k$i']);

      await sync.apply([soon('near', 30), ...plan], now);
      expect(scheduler.scheduled.length, maxPendingReminders);
      expect(scheduler.scheduled.keys, containsAll(['near', 'k1', 'k${maxPendingReminders - 1}']));
      expect(scheduler.scheduled.keys, isNot(contains('k$maxPendingReminders')));
      expect(scheduler.cancelled, ['k$maxPendingReminders'], reason: 'the one pushed out is cancelled, not left pending');
    });

    test('one already set for the same moment is not set again, one that moved is', () async {
      final plan = [for (var i = 1; i <= 5; i++) soon('k$i', i * 600.0)];
      await sync.apply(plan, now);
      expect(scheduler.scheduleCalls, 5);

      await sync.apply(plan, now);
      await sync.apply(plan, now.add(const Duration(seconds: 1)));
      expect(scheduler.scheduleCalls, 5, reason: 'a second of drift is not a change');

      await sync.apply([soon('k1', 700), ...plan.skip(1)], now);
      expect(scheduler.scheduleCalls, 6);
      expect(scheduler.scheduled['k1'], now.add(const Duration(seconds: 700)));
    });

    test('a reminder planned for a day that turns out to be a holiday is cancelled', () async {
      final plan = [soon('2026-11-25T09:00:00-08:00|leave', 3600), soon('2026-11-26T09:00:00-08:00|leave', 90000)];
      await sync.apply(plan, now);
      await sync.apply([plan.first], now.add(const Duration(minutes: 5)));
      expect(scheduler.cancelled, ['2026-11-26T09:00:00-08:00|leave']);
      expect(scheduler.scheduled.keys, ['2026-11-25T09:00:00-08:00|leave']);
    });

    test('a broken store is treated as empty', () async {
      SharedPreferences.setMockInitialValues({'reminders_v1': 'not json'});
      final broken = ReminderSync(scheduler, await SharedPreferences.getInstance());
      expect(broken.firedKeys(now), isEmpty);
      await broken.apply(remindersIn('today_before_class'), now);
      expect(scheduler.scheduled.length, 2);
    });
  });

  group('Today with reminders', () {
    test('plans reminders from the server answer, and tells the server which already fired', () async {
      const oneOff = Meeting(
        course: 'XYZ 10',
        component: 'Lecture',
        days: [],
        start: '14:40',
        end: '15:45',
        location: 'Kresge Acad 3201',
        startDate: '2026-10-12',
        endDate: '2026-10-12',
      );
      final rig = TestRig(stored: [oneOff], remindersOn: true, now: mondayNoon);
      final container = await rig.container();
      addTearDown(container.dispose);

      await container.read(todayProvider.future);
      expect(rig.scheduler.scheduled.length, 2);
      expect(rig.today.requests.single.reminded, isEmpty);

      await container.read(todayProvider.notifier).refresh();
      expect(rig.today.requests.last.reminded, isEmpty, reason: 'nothing is due yet');
    });

    test('plans the days ahead from the saved walks, and the server decides for today', () async {
      final rig = TestRig(
        stored: [meeting()],
        remindersOn: true,
        now: mondayNoon,
        prefs: {'walk_cache_v1': savedWalks({'*>Kresge Acad 3201': 12})},
      );
      final container = await rig.container();
      addTearDown(container.dispose);

      await container.read(todayProvider.future);
      expect(rig.scheduler.scheduled.keys.toSet(), {
        for (final day in ['2026-10-12', '2026-10-14', '2026-10-16'])
          for (final stage in ['heads-up', 'leave']) '${day}T14:40:00-07:00|$stage',
      });
      expect(rig.scheduler.scheduled['2026-10-12T14:40:00-07:00|heads-up'], mondayNoon.add(const Duration(seconds: 8580)));
      expect(rig.scheduler.scheduled['2026-10-14T14:40:00-07:00|leave'], sameMoment(campus(2026, 10, 14, 14, 28)));
      expect(rig.scheduler.scheduled['2026-10-16T14:40:00-07:00|heads-up'], sameMoment(campus(2026, 10, 16, 14, 23)));
    });

    test('opening the app with no starting point does not drop the reminder planned the night before', () async {
      final rig = TestRig(
        stored: [meeting(days: const [1], start: '09:00', end: '09:50')],
        analysis: Analysis.fromJson(fixture('today_weekend')),
        remindersOn: true,
        now: DateTime.utc(2026, 10, 20, 14, 30), // Tuesday 7:30 AM
        prefs: {'walk_cache_v1': savedWalks({'*>Kresge Acad 3201': 12})},
      );
      final container = await rig.container();
      addTearDown(container.dispose);

      await container.read(todayProvider.future);
      expect(rig.scheduler.scheduled.keys, ['2026-10-20T09:00:00-07:00|heads-up', '2026-10-20T09:00:00-07:00|leave']);
      await container.read(todayProvider.notifier).refresh();
      expect(rig.scheduler.scheduled.length, 2);
      expect(rig.scheduler.cancelled, isEmpty);
    });

    test('learns the walks for days ahead in the background, once, and plans the classes it learns', () async {
      final rig = TestRig(
        stored: [
          meeting(days: const [1], start: '09:00', end: '09:50'),
          meeting(course: 'ABC 20', days: const [1], start: '10:00', end: '10:50', location: 'Soc Sci 2 075'),
        ],
        remindersOn: true,
        now: DateTime.utc(2026, 10, 19, 20), // Monday 1:00 PM
        prefs: {'walk_cache_v1': savedWalks({'*>Kresge Acad 3201': 12})},
      );
      rig.today.respond = (at) => Analysis.fromJson(at == null ? fixture('today_weekend') : tuesdayWithTwoClasses());
      final container = await rig.container();
      addTearDown(container.dispose);

      await container.read(todayProvider.future);
      await pumpEventQueue();
      final asked = rig.today.requests.where((r) => r.at != null).toList();
      expect(asked.map((r) => r.at!.millisecondsSinceEpoch), [campus(2026, 10, 20, 0, 1).millisecondsSinceEpoch]);
      expect(rig.scheduler.scheduled['2026-10-20T10:00:00-07:00|leave'], sameMoment(campus(2026, 10, 20, 9, 51)));
      expect(rig.scheduler.scheduled['2026-10-20T09:00:00-07:00|leave'], sameMoment(campus(2026, 10, 20, 8, 48)));

      await container.read(todayProvider.notifier).refresh();
      await pumpEventQueue();
      expect(rig.today.requests.where((r) => r.at != null), hasLength(1), reason: 'a day is only asked about once per run');
    });

    test('with reminders off nothing is scheduled', () async {
      final rig = TestRig(stored: [meeting()]);
      final container = await rig.container();
      addTearDown(container.dispose);

      await container.read(todayProvider.future);
      expect(rig.scheduler.scheduled, isEmpty);
      expect(rig.scheduler.shown, isEmpty);
    });

    test('switching reminders off cancels the ones planned', () async {
      final rig = TestRig(stored: [meeting()], remindersOn: true);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(todayProvider.future);
      expect(rig.scheduler.scheduled, isNotEmpty);

      await container.read(settingsProvider.notifier).setRemindersOn(false);
      await container.read(todayProvider.future);
      expect(rig.scheduler.scheduled, isEmpty);
    });

    test('a notification failure does not hide the schedule', () async {
      final rig = TestRig(stored: [meeting()], remindersOn: true);
      rig.scheduler.failing = true;
      final container = await rig.container();
      addTearDown(container.dispose);

      final data = await container.read(todayProvider.future);
      expect(data.analysis, isNotNull);
      expect(data.reminderProblem, contains('reminders'));
    });
  });
}
