import 'package:classmap/features/reminders/reminder_controller.dart';
import 'package:classmap/features/schedule/meeting.dart';
import 'package:classmap/features/schedule/schedule_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

TestRig rigFor({bool remindersOn = false}) =>
    TestRig(stored: [meeting()], now: mondayNoon, remindersOn: remindersOn);

Future<void> open(WidgetTester tester, TestRig rig) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
}

Future<void> skipFromMenu(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More for $label'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Skip this day'));
  await tester.pumpAndSettle();
}

void main() {
  group('a class that skips days', () {
    final base = meeting();

    test('skipping adds the date, in order, once', () {
      final once = base.skipping('2026-10-21', today: '2026-10-12')!;
      final more = once
          .skipping('2026-10-14', today: '2026-10-12')!
          .skipping('2026-10-21', today: '2026-10-12')!;
      expect(more.skipDates, ['2026-10-14', '2026-10-21']);
      expect(more.toJson()['skip_dates'], ['2026-10-14', '2026-10-21']);
      expect(Meeting.fromJson(more.toJson()).skipDates, more.skipDates);
      expect(base.skipDates, isEmpty, reason: 'the original is not changed');
      expect(base.toJson().containsKey('skip_dates'), isFalse);
    });

    test('dates already past are forgotten, so the list stays short', () {
      final m = base
          .skipping('2026-10-05', today: '2026-10-05')!
          .skipping('2026-10-21', today: '2026-10-12')!;
      expect(m.skipDates, ['2026-10-21']);
    });

    test('there is a limit of sixty, and the sixty-first is refused', () {
      var m = base;
      for (var i = 0; i < Meeting.maxSkipDates; i++) {
        m = m.skipping(
          DateTime.utc(2027, 1, 1 + i).toIso8601String().substring(0, 10),
          today: '2026-10-12',
        )!;
      }
      expect(m.skipDates, hasLength(60));
      expect(m.skipping('2027-06-01', today: '2026-10-12'), isNull);
      expect(
        m.skipping('2027-01-01', today: '2026-10-12')!.skipDates,
        hasLength(60),
        reason: 'a date already there is not new',
      );
    });

    test('a day can be given back', () {
      final m = base
          .skipping('2026-10-14', today: '2026-10-12')!
          .skipping('2026-10-21', today: '2026-10-12')!;
      expect(m.meetingOn('2026-10-14').skipDates, ['2026-10-21']);
      expect(m.skips('2026-10-21'), isTrue);
      expect(m.meetingOn('2026-10-21').skips('2026-10-21'), isFalse);
    });
  });

  group('the schedule', () {
    test('skipping and restoring change the saved class', () async {
      final rig = TestRig(stored: [meeting()]);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(scheduleProvider.future);
      final notifier = container.read(scheduleProvider.notifier);

      expect(
        await notifier.skipDay(meeting(), '2026-10-14', today: '2026-10-12'),
        isTrue,
      );
      expect(rig.schedule.stored.single.skipDates, ['2026-10-14']);

      await notifier.restoreDay(meeting(), '2026-10-14');
      expect(rig.schedule.stored.single.skipDates, isEmpty);

      await notifier.skipDay(meeting(), '2026-10-14', today: '2026-10-12');
      await notifier.skipDay(meeting(), '2026-10-16', today: '2026-10-12');
      await notifier.restoreAllDays(meeting());
      expect(rig.schedule.stored.single.skipDates, isEmpty);
    });

    test('a class that is no longer there cannot be skipped', () async {
      final rig = TestRig(stored: [meeting(course: 'ABC 20')]);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(scheduleProvider.future);
      expect(
        await container
            .read(scheduleProvider.notifier)
            .skipDay(meeting(), '2026-10-14', today: '2026-10-12'),
        isFalse,
      );
      expect(rig.schedule.stored.single.skipDates, isEmpty);
    });
  });

  group('Today', () {
    testWidgets(
      'Skip this day takes the class off the day, and Undo puts it back',
      (tester) async {
        final rig = rigFor();
        await open(tester, rig);
        expect(find.byTooltip('More for XYZ 10 Lecture'), findsOneWidget);

        await skipFromMenu(tester, 'XYZ 10 Lecture');
        expect(
          find.text('Skipped XYZ 10 Lecture on Mon, Oct 12.'),
          findsOneWidget,
        );
        expect(rig.schedule.stored.single.skipDates, ['2026-10-12']);
        expect(
          find.byTooltip('More for XYZ 10 Lecture'),
          findsNothing,
          reason: 'the class is off the day',
        );
        expect(find.textContaining('No classes today.'), findsOneWidget);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(rig.schedule.stored.single.skipDates, isEmpty);
        expect(find.byTooltip('More for XYZ 10 Lecture'), findsOneWidget);
      },
    );

    testWidgets(
      'another day can be skipped too, with that day in the message',
      (tester) async {
        final rig = rigFor();
        await open(tester, rig);
        await tester.tap(find.byTooltip('Next day'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Next day'));
        await tester.pumpAndSettle(); // Wednesday, a class day

        await skipFromMenu(tester, 'XYZ 10 Lecture');
        expect(
          find.text('Skipped XYZ 10 Lecture on Wed, Oct 14.'),
          findsOneWidget,
        );
        expect(rig.schedule.stored.single.skipDates, ['2026-10-14']);
        expect(find.text('No classes.'), findsOneWidget);
      },
    );

    testWidgets('a class that is over has nothing to skip', (tester) async {
      final rig = TestRig(
        stored: [meeting(start: '08:00', end: '09:00')],
        now: mondayNoon,
      );
      await open(tester, rig);
      expect(find.text('XYZ 10 Lecture'), findsOneWidget);
      expect(find.byTooltip('More for XYZ 10 Lecture'), findsNothing);
    });

    testWidgets('skipping cancels the reminder already planned for that day', (
      tester,
    ) async {
      final rig = rigFor(remindersOn: true);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(reminderControllerProvider.future);
      expect(
        rig.scheduler.scheduled.keys,
        contains('2026-10-14T14:40:00-07:00|class'),
      );

      await container
          .read(scheduleProvider.notifier)
          .skipDay(meeting(), '2026-10-14', today: '2026-10-12');
      await container.read(reminderControllerProvider.future);
      expect(
        rig.scheduler.scheduled.keys,
        isNot(contains('2026-10-14T14:40:00-07:00|class')),
      );
      expect(rig.scheduler.cancelled, ['2026-10-14T14:40:00-07:00|class']);
      expect(
        rig.scheduler.scheduled.keys,
        contains('2026-10-12T14:40:00-07:00|class'),
        reason: 'the other days stay',
      );
    });
  });

  group('the Schedule', () {
    testWidgets(
      'lists the days a class is not meeting, and Restore gives them back',
      (tester) async {
        final skipped = meeting()
            .skipping('2026-10-14', today: '2026-10-12')!
            .skipping('2026-10-21', today: '2026-10-12')!;
        final rig = TestRig(stored: [skipped], now: mondayNoon);
        await open(tester, rig);
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Schedule'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Not meeting Oct 14, Oct 21'), findsOneWidget);
        await tester.tap(find.text('Restore'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Not meeting'), findsNothing);
        expect(rig.schedule.stored.single.skipDates, isEmpty);
      },
    );
  });
}
