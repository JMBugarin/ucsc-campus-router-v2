import 'dart:convert';
import 'dart:io';

import 'package:classmap/core/pacific.dart';
import 'package:classmap/features/schedule/meeting.dart';
import 'package:classmap/features/today/day_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// The day logic against `fixtures/schedule_cases.json`, recorded from the Python the app replaced.
void main() {
  final data =
      jsonDecode(File('test/fixtures/schedule_cases.json').readAsStringSync())
          as Map<String, dynamic>;
  final holidays = {for (final h in data['holidays'] as List) h as String};
  final named = {
    for (final e in (data['meetings'] as Map<String, dynamic>).entries)
      e.key: Meeting.fromJson(e.value as Map<String, dynamic>),
  };
  const states = {
    'in_class': DayState.inClass,
    'before_classes': DayState.beforeClasses,
    'between_classes': DayState.betweenClasses,
    'done_for_today': DayState.doneForToday,
    'no_classes_today': DayState.noClasses,
  };

  test('every shared case', () {
    final cases = data['cases'] as List;
    expect(cases.length, greaterThanOrEqualTo(15));
    for (final c in cases) {
      final name = c['name'] as String;
      final want = c['expect'] as Map<String, dynamic>;
      final now = DateTime.parse(c['now'] as String);
      final plan = planDay(
        meetings: [for (final n in c['meetings'] as List) named[n]!],
        now: now,
        holidays: holidays,
      );
      expect(plan.state, states[want['state']], reason: name);
      expect(plan.reason, want['reason'], reason: name);
      expect(
        plan.current == null ? null : isoWithOffset(plan.current!.start),
        want['current_start'],
        reason: name,
      );
      expect(
        plan.next == null ? null : isoWithOffset(plan.next!.start),
        want['next_start'],
        reason: name,
      );
      expect(
        [for (final o in plan.classes) isoWithOffset(o.start)],
        want['today_starts'],
        reason: name,
      );
      final next = plan.next;
      if (next != null) {
        expect(
          isoDate(next.start) == isoDate(pacificTime(now)),
          want['next_is_today'],
          reason: name,
        );
        expect(
          next.start.difference(pacificTime(now)).inSeconds / 60,
          closeTo(want['starts_in_min'] as num, 0.06),
          reason: name,
        );
      }
    }
  });

  group('around a clock change', () {
    final early = Meeting(
      course: 'XYZ 10',
      days: const [0, 1, 2, 3, 4, 5, 6],
      start: '08:00',
      end: '09:00',
      startDate: '2026-09-24',
      endDate: '2027-06-04',
    );

    test(
      'a class at 8 AM is still at 8 AM after the clocks go back (2026-11-01)',
      () {
        final plan = planDay(
          meetings: [early],
          now: DateTime.utc(2026, 11, 1, 12),
          holidays: const {},
        );
        expect(
          isoWithOffset(plan.classes.single.start),
          '2026-11-01T08:00:00-08:00',
        );
        expect(plan.state, DayState.beforeClasses);
      },
    );

    test('and after they go forward (2027-03-14)', () {
      final plan = planDay(
        meetings: [early],
        now: DateTime.utc(2027, 3, 14, 12),
        holidays: const {},
      );
      expect(
        isoWithOffset(plan.classes.single.start),
        '2027-03-14T08:00:00-07:00',
      );
    });

    test(
      'the next class across the change is the right number of minutes away',
      () {
        // 11 PM Pacific on Oct 31 (PDT) to 8 AM Nov 1 (PST) is nine hours on the wall clock and ten really.
        final plan = planDay(
          meetings: [early],
          now: DateTime.utc(2026, 11, 1, 6),
          holidays: const {},
        );
        expect(
          plan.next!.start
              .difference(pacificTime(DateTime.utc(2026, 11, 1, 6)))
              .inMinutes,
          10 * 60,
        );
      },
    );
  });

  group('the summary line', () {
    final lecture = Meeting(
      course: 'XYZ 10',
      component: 'Lecture',
      days: const [0],
      start: '14:40',
      end: '15:45',
      location: 'Kresge Acad 3201',
      startDate: '2026-09-24',
      endDate: '2026-12-04',
    );
    String summary(DateTime now, {DateTime? viewDay}) => daySummary(
      planDay(
        meetings: [lecture],
        now: now,
        holidays: const {},
        viewDay: viewDay,
      ),
      now,
    );

    test(
      'before class',
      () => expect(
        summary(DateTime.utc(2026, 10, 12, 19)),
        'Next: XYZ 10 Lecture at 2:40 PM in 2 h 40 min.',
      ),
    );
    test(
      'in class',
      () => expect(
        summary(DateTime.utc(2026, 10, 12, 22)),
        'In XYZ 10 Lecture until 3:45 PM (45 min left). Next: Mon 2:40 PM, XYZ 10 Lecture.',
      ),
    );
    test('after the last class', () {
      expect(
        summary(DateTime.utc(2026, 10, 13, 2)),
        startsWith('Done for today. Next class: Mon 2:40 PM'),
      );
    });
    test(
      'a day with no class',
      () => expect(
        summary(DateTime.utc(2026, 10, 13, 19)),
        'No classes today. Next class: Mon 2:40 PM, XYZ 10 Lecture.',
      ),
    );
    test('another day', () {
      expect(
        summary(
          DateTime.utc(2026, 10, 12, 19),
          viewDay: DateTime.utc(2026, 10, 19),
        ),
        '1 class, 2:40 PM to 3:45 PM.',
      );
      expect(
        summary(
          DateTime.utc(2026, 10, 12, 19),
          viewDay: DateTime.utc(2026, 10, 17),
        ),
        'No classes: weekend.',
      );
    });
  });
}
