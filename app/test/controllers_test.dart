import 'package:classmap/campus/campus_data.dart';
import 'package:classmap/core/clock.dart';
import 'package:classmap/features/schedule/import/clean.dart';
import 'package:classmap/features/schedule/meeting.dart';
import 'package:classmap/features/schedule/schedule_controller.dart';
import 'package:classmap/features/settings/settings.dart';
import 'package:classmap/features/today/day_plan.dart';
import 'package:classmap/features/today/today_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  group('schedule', () {
    test(
      'importing merges, skips classes already there, and reports the notes',
      () async {
        final rig = TestRig(stored: [meeting()]);
        final container = await rig.container();
        addTearDown(container.dispose);
        await container.read(scheduleProvider.future);

        rig.schedule.nextImport = ImportResult(
          meetings: [
            meeting(),
            meeting(course: 'ABC 20', start: '16:00', end: '17:05'),
          ],
          notes: ['Skipped DEF 30 (dropped).'],
          locations: const [],
        );
        final summary = await container
            .read(scheduleProvider.notifier)
            .importText('pasted');

        expect(summary.added, 1);
        expect(summary.alreadyThere, 1);
        expect(
          summary.message,
          'Added 1 class (1 already there). Skipped DEF 30 (dropped).',
        );
        expect(container.read(scheduleProvider).value!.map((m) => m.course), [
          'XYZ 10',
          'ABC 20',
        ]);
        expect(
          rig.schedule.stored.length,
          2,
          reason: 'it is saved to the phone',
        );
      },
    );

    test('a calendar file goes to the calendar reader', () async {
      final rig = TestRig();
      final container = await rig.container();
      addTearDown(container.dispose);
      rig.schedule.nextImport = ImportResult(
        meetings: [meeting()],
        notes: const [],
        locations: const [],
      );
      await container.read(scheduleProvider.future);

      await container
          .read(scheduleProvider.notifier)
          .importCalendar('BEGIN:VCALENDAR');
      expect(rig.schedule.calls, ['ics:BEGIN:VCALENDAR']);
    });

    test('a class typed by hand is checked, then saved', () async {
      final rig = TestRig();
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(scheduleProvider.future);

      await container
          .read(scheduleProvider.notifier)
          .add(meeting(location: 'Thim Lecture 003'));
      expect(rig.schedule.calls, ['clean:1']);
      expect(
        container.read(scheduleProvider).value!.single.location,
        'Thim Lecture 003',
      );
    });

    test(
      'a rejected class is not saved, and the error reaches the caller',
      () async {
        final rig = TestRig();
        final container = await rig.container();
        addTearDown(container.dispose);
        await container.read(scheduleProvider.future);
        rig.schedule.failWith = const ScheduleError(
          'Bad: the end time must be after the start time',
        );

        await expectLater(
          container.read(scheduleProvider.notifier).add(meeting()),
          throwsA(
            isA<ScheduleError>().having(
              (e) => e.message,
              'message',
              contains('end time'),
            ),
          ),
        );
        expect(container.read(scheduleProvider).value, isEmpty);
      },
    );

    test('removing and clearing', () async {
      final rig = TestRig(
        stored: [
          meeting(),
          meeting(course: 'ABC 20'),
        ],
      );
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(scheduleProvider.future);

      await container.read(scheduleProvider.notifier).removeAt(0);
      expect(container.read(scheduleProvider).value!.map((m) => m.course), [
        'ABC 20',
      ]);
      await container.read(scheduleProvider.notifier).clear();
      expect(container.read(scheduleProvider).value, isEmpty);
      expect(rig.schedule.stored, isEmpty);
    });

    test('rooms the campus data cannot place are reported', () async {
      final rig = TestRig(
        stored: [
          meeting(),
          meeting(location: 'Mystery Hall 9'),
          meeting(location: 'Online'),
        ],
      );
      final container = await rig.container();
      addTearDown(container.dispose);
      rig.schedule.nextImport = const ImportResult(
        meetings: [],
        notes: [],
        locations: [
          LocationInfo(kind: 'building'),
          LocationInfo(kind: 'unknown'),
          LocationInfo(kind: 'online'),
        ],
      );
      final infos = await container.read(locationInfoProvider.future);
      expect(infos.map((i) => i.isUnknown), [false, true, false]);
    });
  });

  group('the real schedule repository, on the phone alone', () {
    Future<ProviderContainer> real({DateTime? now}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        retry: (c, e) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          campusProvider.overrideWith((ref) => testCampus),
          termsProvider.overrideWith((ref) => testTerms),
          clockProvider.overrideWithValue(() => now ?? mondayNoon),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    const pasted =
        'XYZ 10 - Sample Calculus Status Units Grading Grade Deadlines Enrolled 5.00 Graded '
        '10002 01 Lecture MoWeFr 1:20PM - 2:25PM Kresge Acad 3201 A Instructor 09/24/2026 - 12/04/2026 '
        '10003 01 Lecture TuTh 11:40AM - 1:15PM Mystery Hall 9 B Instructor 09/24/2026 - 12/04/2026';

    test(
      'pasted text is read, saved, and still there after a restart',
      () async {
        final container = await real();
        await container.read(scheduleProvider.future);
        final summary = await container
            .read(scheduleProvider.notifier)
            .importText(pasted);
        expect(summary.added, 2);

        final restarted = ProviderContainer(
          retry: (c, e) => null,
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            campusProvider.overrideWith((ref) => testCampus),
            termsProvider.overrideWith((ref) => testTerms),
          ],
        );
        addTearDown(restarted.dispose);
        expect(
          (await restarted.read(
            scheduleProvider.future,
          )).map((m) => m.location),
          ['Kresge Acad 3201', 'Mystery Hall 9'],
        );
        final infos = await restarted.read(locationInfoProvider.future);
        expect(
          [infos[0].kind, infos[0].buildingName, infos[1].kind],
          ['building', 'Kresge College Academic Building', 'unknown'],
        );
      },
    );

    test('text that is not a schedule is refused with a message', () async {
      final container = await real();
      await container.read(scheduleProvider.future);
      await expectLater(
        container.read(scheduleProvider.notifier).importText('   '),
        throwsA(
          isA<ScheduleError>().having(
            (e) => e.message,
            'message',
            'paste your schedule first',
          ),
        ),
      );
    });

    test(
      'a calendar file with no end date is ended with the current term',
      () async {
        final container = await real();
        await container.read(scheduleProvider.future);
        const ics =
            'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:ABC 5 Lecture\r\nLOCATION:Cowell Acad 113\r\n'
            'DTSTART;TZID=America/Los_Angeles:20260928T150000\r\nDTEND;TZID=America/Los_Angeles:20260928T160000\r\n'
            'RRULE:FREQ=WEEKLY;BYDAY=MO\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';
        final summary = await container
            .read(scheduleProvider.notifier)
            .importText(ics);
        expect(summary.added, 1);
        final saved = container.read(scheduleProvider).value!.single;
        expect(
          (saved.course, saved.component, saved.endDate),
          ('ABC 5', 'Lecture', '2026-12-04'),
        );
      },
    );

    test(
      'a hand-typed class with an end before its start is refused',
      () async {
        final container = await real();
        await container.read(scheduleProvider.future);
        await expectLater(
          container
              .read(scheduleProvider.notifier)
              .add(meeting(start: '15:00', end: '14:00')),
          throwsA(isA<ScheduleError>()),
        );
      },
    );
  });

  group('today', () {
    test('the day follows the saved schedule and the clock', () async {
      final rig = TestRig(stored: [meeting()], now: mondayNoon);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(scheduleProvider.future);
      await container.read(termsProvider.future);
      final plan = container.read(dayPlanProvider).requireValue;
      expect(plan.isToday, isTrue);
      expect(plan.state, DayState.beforeClasses);
      expect(plan.classes.map((o) => o.label), ['XYZ 10 Lecture']);
      expect(plan.next!.label, 'XYZ 10 Lecture');
    });

    test(
      'with no classes there is no plan to show beyond the reason',
      () async {
        final rig = TestRig(now: mondayNoon);
        final container = await rig.container();
        addTearDown(container.dispose);
        await container.read(scheduleProvider.future);
        await container.read(termsProvider.future);
        final plan = container.read(dayPlanProvider).requireValue;
        expect(
          (plan.state, plan.reason, plan.next),
          (DayState.noClasses, 'no_schedule', null),
        );
      },
    );

    test('another day is shown by its date and has no now or next', () async {
      final rig = TestRig(stored: [meeting()], now: mondayNoon);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(scheduleProvider.future);
      await container.read(termsProvider.future);
      container
          .read(viewedDayProvider.notifier)
          .show(DateTime.utc(2026, 10, 14));
      final plan = container.read(dayPlanProvider).requireValue;
      expect(
        (plan.isToday, plan.day, plan.classes.length, plan.next),
        (false, DateTime.utc(2026, 10, 14), 1, null),
      );
    });

    test('picking today goes back to today rather than a fixed date', () async {
      final rig = TestRig(stored: [meeting()], now: mondayNoon);
      final container = await rig.container();
      addTearDown(container.dispose);
      container
          .read(viewedDayProvider.notifier)
          .show(DateTime.utc(2026, 10, 12));
      expect(container.read(viewedDayProvider), isNull);
    });

    test('changing the schedule recomputes the day', () async {
      final rig = TestRig(stored: [meeting()], now: mondayNoon);
      final container = await rig.container();
      addTearDown(container.dispose);
      await container.read(scheduleProvider.future);
      await container.read(termsProvider.future);
      expect(
        container.read(dayPlanProvider).requireValue.classes,
        hasLength(1),
      );
      await container.read(scheduleProvider.notifier).clear();
      expect(container.read(dayPlanProvider).requireValue.classes, isEmpty);
    });
  });

  group('settings', () {
    test('are remembered', () async {
      final rig = TestRig();
      final container = await rig.container();
      addTearDown(container.dispose);

      final controller = container.read(settingsProvider.notifier);
      await controller.setRemindLead(15);
      await controller.setRemindersOn(true);

      final s = container.read(settingsProvider);
      expect((s.remindersOn, s.remindLeadMinutes), (true, 15));
      final again = await rig.container();
      addTearDown(again.dispose);
      expect(again.read(settingsProvider).remindLeadMinutes, 15);
      expect(again.read(settingsProvider).remindersOn, isTrue);
    });

    test('the default is a 10 minute reminder, off', () async {
      final container = await TestRig().container();
      addTearDown(container.dispose);
      final s = container.read(settingsProvider);
      expect((s.remindersOn, s.remindLeadMinutes), (false, 10));
    });
  });
}
