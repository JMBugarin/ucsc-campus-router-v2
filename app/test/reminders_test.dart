import 'package:classmap/features/reminders/reminder.dart';
import 'package:classmap/features/reminders/reminder_controller.dart';
import 'package:classmap/features/reminders/reminder_planner.dart';
import 'package:classmap/features/reminders/reminder_scheduler.dart';
import 'package:classmap/features/reminders/reminder_sync.dart';
import 'package:classmap/features/schedule/schedule_controller.dart';
import 'package:classmap/features/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Reminder soon(String key, double inSeconds) => Reminder(
  stage: 'class',
  key: key,
  inSeconds: inSeconds,
  title: 'Class soon',
  body: '',
);

void main() {
  final now = mondayNoon;
  final day = [
    meeting(start: '09:00', end: '09:50', days: const [0]),
    meeting(course: 'ABC 20', start: '11:00', end: '11:50', days: const [0]),
    meeting(course: 'DEF 30', start: '14:40', end: '15:45', days: const [0]),
  ];
  List<Reminder> planFor(List<dynamic> meetings) => planReminders(
    meetings: [for (final m in meetings) m],
    now: DateTime.utc(2026, 10, 12, 15), // 8 AM on the campus clock
    holidays: const {},
    leadMinutes: 10,
  );

  group('notification ids', () {
    test('are the same every time and fit in 31 bits', () {
      expect(
        notificationId('2026-10-12T14:40:00-07:00|class'),
        notificationId('2026-10-12T14:40:00-07:00|class'),
      );
      expect(notificationId('a'), isNot(notificationId('b')));
      for (final key in ['a', '2026-10-12T14:40:00-07:00|class', 'x' * 500]) {
        expect(notificationId(key), inInclusiveRange(0, 0x7fffffff));
      }
    });
  });

  group('ReminderSync', () {
    late FakeReminderScheduler scheduler;
    late ReminderSync sync;
    final eight = DateTime.utc(2026, 10, 12, 15);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      scheduler = FakeReminderScheduler();
      sync = ReminderSync(scheduler, await SharedPreferences.getInstance());
    });

    test('schedules what is still to come at the right moment', () async {
      final plan = planFor(day);
      expect(plan.length, 3);
      await sync.apply(plan, eight);

      expect(scheduler.scheduled.keys, plan.map((r) => r.key));
      expect(
        scheduler.scheduled[plan[0].key],
        DateTime.utc(2026, 10, 12, 15, 50),
      ); // 8:50 AM
      expect(scheduler.shown, isEmpty);
    });

    test('dropping one class cancels only its own reminder', () async {
      final plan = planFor(day);
      await sync.apply(plan, eight);
      final withoutMiddle = planFor([day[0], day[2]]);
      await sync.apply(withoutMiddle, eight);
      expect(scheduler.cancelled, [plan[1].key]);
      expect(scheduler.scheduled.keys, withoutMiddle.map((r) => r.key));
    });

    test('a late reminder is shown straight away, once', () async {
      final late = soon('late', -30);
      await sync.apply([late], now);
      await sync.apply([late], now.add(const Duration(minutes: 1)));
      expect(scheduler.shown, ['late']);
      expect(scheduler.scheduled, isEmpty);
    });

    test(
      'a reminder is only reported as fired once its time has passed',
      () async {
        final plan = [soon('a', 2), soon('b', 302)];
        await sync.apply(plan, now);

        expect(sync.firedKeys(now), isEmpty);
        expect(sync.firedKeys(now.add(const Duration(seconds: 10))), ['a']);
        expect(sync.firedKeys(now.add(const Duration(minutes: 6))), ['a', 'b']);
      },
    );

    test('planning again replaces rather than duplicates', () async {
      final plan = planFor(day);
      await sync.apply(plan, eight);
      await sync.apply(plan, eight.add(const Duration(minutes: 1)));
      expect(scheduler.scheduled.length, 3);
      expect(scheduler.cancelled, isEmpty);
    });

    test(
      'a pending reminder that dropped out of the plan is cancelled',
      () async {
        final plan = planFor(day);
        await sync.apply(plan, eight);
        await sync.apply([
          plan[1],
          plan[2],
        ], eight.add(const Duration(minutes: 1)));
        expect(scheduler.cancelled, [plan[0].key]);
      },
    );

    test(
      'one that already fired is not cancelled when it drops out of the plan',
      () async {
        final plan = [soon('a', 2), soon('b', 302)];
        await sync.apply(plan, now);
        await sync.apply([plan[1]], now.add(const Duration(seconds: 30)));
        expect(scheduler.cancelled, isEmpty);
      },
    );

    test('clear cancels what is pending and forgets everything', () async {
      final plan = planFor(day);
      await sync.apply(plan, eight);
      expect(sync.hasAny, isTrue);

      await sync.clear(eight.add(const Duration(minutes: 1)));
      expect(scheduler.cancelled, plan.map((r) => r.key));
      expect(sync.hasAny, isFalse);
    });

    test('old entries are dropped after a day', () async {
      await sync.apply([soon('a', 2)], now);
      await sync.apply(const [], now.add(const Duration(days: 2)));
      expect(sync.hasAny, isFalse);
    });

    test(
      'only the soonest reminders stay scheduled, within the platform limit',
      () async {
        final plan = [for (var i = 1; i <= 100; i++) soon('k$i', i * 60.0)];
        await sync.apply(plan, now);
        expect(scheduler.scheduled.length, maxPendingReminders);
        expect(scheduler.scheduled.keys, [
          for (var i = 1; i <= maxPendingReminders; i++) 'k$i',
        ]);

        await sync.apply([soon('near', 30), ...plan], now);
        expect(scheduler.scheduled.length, maxPendingReminders);
        expect(
          scheduler.scheduled.keys,
          containsAll(['near', 'k1', 'k${maxPendingReminders - 1}']),
        );
        expect(
          scheduler.scheduled.keys,
          isNot(contains('k$maxPendingReminders')),
        );
        expect(scheduler.cancelled, [
          'k$maxPendingReminders',
        ], reason: 'the one pushed out is cancelled, not left pending');
      },
    );

    test(
      'one already set for the same moment is not set again, one that moved is',
      () async {
        final plan = [for (var i = 1; i <= 5; i++) soon('k$i', i * 600.0)];
        await sync.apply(plan, now);
        expect(scheduler.scheduleCalls, 5);

        await sync.apply(plan, now);
        await sync.apply(plan, now.add(const Duration(seconds: 1)));
        expect(
          scheduler.scheduleCalls,
          5,
          reason: 'a second of drift is not a change',
        );

        await sync.apply([soon('k1', 700), ...plan.skip(1)], now);
        expect(scheduler.scheduleCalls, 6);
        expect(
          scheduler.scheduled['k1'],
          now.add(const Duration(seconds: 700)),
        );
      },
    );

    test('a broken store is treated as empty', () async {
      SharedPreferences.setMockInitialValues({'reminders_v1': 'not json'});
      final broken = ReminderSync(
        scheduler,
        await SharedPreferences.getInstance(),
      );
      expect(broken.firedKeys(now), isEmpty);
      await broken.apply(planFor(day), eight);
      expect(scheduler.scheduled.length, 3);
    });
  });

  group('reminders kept in step with the schedule', () {
    test(
      'with reminders on, the next classes are scheduled ahead of time',
      () async {
        final rig = TestRig(
          stored: [meeting()],
          remindersOn: true,
          now: mondayNoon,
        );
        final container = await rig.container();
        addTearDown(container.dispose);
        final problem = await container.read(reminderControllerProvider.future);

        expect(problem, isNull);
        expect(
          rig.scheduler.scheduled.keys.first,
          '2026-10-12T14:40:00-07:00|class',
        );
        expect(
          rig.scheduler.scheduled['2026-10-12T14:40:00-07:00|class'],
          DateTime.utc(2026, 10, 12, 21, 30),
        );
      },
    );

    test('the lead time in the settings is used', () async {
      final rig = TestRig(
        stored: [meeting()],
        remindersOn: true,
        now: mondayNoon,
        prefs: {'remind_lead_v2': 30},
      );
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(reminderControllerProvider.future);
      expect(
        rig.scheduler.scheduled['2026-10-12T14:40:00-07:00|class'],
        DateTime.utc(2026, 10, 12, 21, 10),
      );
    });

    test('with reminders off nothing is scheduled', () async {
      final rig = TestRig(stored: [meeting()], now: mondayNoon);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(reminderControllerProvider.future);
      expect(rig.scheduler.scheduled, isEmpty);
      expect(rig.scheduler.scheduleCalls, 0);
    });

    test('switching reminders off cancels the ones planned', () async {
      final rig = TestRig(
        stored: [meeting()],
        remindersOn: true,
        now: mondayNoon,
      );
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(reminderControllerProvider.future);
      expect(rig.scheduler.scheduled, isNotEmpty);

      await container.read(settingsProvider.notifier).setRemindersOn(false);
      await container.read(reminderControllerProvider.future);
      expect(rig.scheduler.scheduled, isEmpty);
      expect(rig.scheduler.cancelled, isNotEmpty);
    });

    test('removing every class cancels the reminders', () async {
      final rig = TestRig(
        stored: [meeting()],
        remindersOn: true,
        now: mondayNoon,
      );
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(reminderControllerProvider.future);
      await container.read(scheduleProvider.notifier).clear();
      await container.read(reminderControllerProvider.future);
      expect(rig.scheduler.scheduled, isEmpty);
    });

    test(
      'a notification failure is reported and does not hide the schedule',
      () async {
        final rig = TestRig(
          stored: [meeting()],
          remindersOn: true,
          now: mondayNoon,
        );
        rig.scheduler.failing = true;
        final container = await rig.container();
        addTearDown(container.dispose);

        expect(
          await container.read(reminderControllerProvider.future),
          "Couldn't set up reminders on this phone.",
        );
        expect((await container.read(scheduleProvider.future)).length, 1);
      },
    );
  });
}
