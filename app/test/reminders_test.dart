import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ucsc_router/features/reminders/reminder_scheduler.dart';
import 'package:ucsc_router/features/reminders/reminder_sync.dart';
import 'package:ucsc_router/features/settings/settings.dart';
import 'package:ucsc_router/features/today/today_controller.dart';
import 'package:ucsc_router/features/today/today_models.dart';

import 'helpers.dart';

List<Reminder> remindersIn(String fixtureName) => Analysis.fromJson(fixture(fixtureName)).reminders;

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
      final rig = TestRig(stored: [meeting()], remindersOn: true);
      final container = await rig.container();
      addTearDown(container.dispose);

      await container.read(todayProvider.future);
      expect(rig.scheduler.scheduled.length, 2);
      expect(rig.today.requests.single.reminded, isEmpty);

      await container.read(todayProvider.notifier).refresh();
      expect(rig.today.requests.last.reminded, isEmpty, reason: 'nothing is due yet');
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
