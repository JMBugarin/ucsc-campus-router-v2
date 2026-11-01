import 'package:classmap/features/reminders/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final classes = [
    meeting(days: const [0, 2, 4]),
    meeting(
      course: 'ABC 20',
      days: const [1],
      start: '09:00',
      end: '09:50',
      location: '',
    ),
  ];

  test(
    'a reminder a lead time before each class over the next week, soonest first',
    () {
      final plan = planReminders(
        meetings: classes,
        now: mondayNoon,
        holidays: const {},
        leadMinutes: 10,
      );
      expect(plan.map((r) => r.key), [
        '2026-10-12T14:40:00-07:00|class',
        '2026-10-13T09:00:00-07:00|class',
        '2026-10-14T14:40:00-07:00|class',
        '2026-10-16T14:40:00-07:00|class',
      ]);
      expect(plan.first.inSeconds, 150 * 60, reason: 'noon to 2:30 PM');
      expect(plan.first.title, 'XYZ 10 Lecture in 10 min');
      expect(plan.first.body, 'Kresge Acad 3201 at 2:40 PM.');
    },
  );

  test('a class without a room says only when it starts', () {
    final plan = planReminders(
      meetings: classes,
      now: mondayNoon,
      holidays: const {},
      leadMinutes: 5,
    );
    final tuesday = plan.firstWhere((r) => r.key.startsWith('2026-10-13'));
    expect(tuesday.body, 'Starts at 9:00 AM.');
  });

  test('a lead of zero reminds at the start', () {
    final plan = planReminders(
      meetings: classes,
      now: mondayNoon,
      holidays: const {},
      leadMinutes: 0,
    );
    expect(plan.first.inSeconds, 160 * 60);
    expect(plan.first.title, 'XYZ 10 Lecture is starting');
  });

  test(
    'a class whose reminder time has passed gets none, and a sent one is not repeated',
    () {
      final late = DateTime.utc(2026, 10, 12, 21, 35); // 2:35 PM, five minutes before class
      expect(
        planReminders(
          meetings: classes,
          now: late,
          holidays: const {},
          leadMinutes: 10,
        ).first.key,
        startsWith('2026-10-13'),
      );
      final sent = planReminders(
        meetings: classes,
        now: mondayNoon,
        holidays: const {},
        leadMinutes: 10,
        sent: {'2026-10-12T14:40:00-07:00|class'},
      );
      expect(sent.first.key, startsWith('2026-10-13'));
    },
  );

  test('holidays and skipped days are left out', () {
    final skipped = meeting(days: const [0, 1, 2, 3, 4, 5, 6]);
    final withSkip = skipped.skipping('2026-10-13', today: '2026-10-12')!;
    final plan = planReminders(
      meetings: [withSkip],
      now: mondayNoon,
      holidays: {'2026-10-14'},
      leadMinutes: 10,
    );
    final days = plan.map((r) => r.key.substring(0, 10)).toList();
    expect(days, isNot(contains('2026-10-13')));
    expect(days, isNot(contains('2026-10-14')));
    expect(days.toSet(), {
      '2026-10-12',
      '2026-10-15',
      '2026-10-16',
      '2026-10-17',
      '2026-10-18',
    });
  });

  test('nothing is planned beyond the week', () {
    final plan = planReminders(
      meetings: classes,
      now: mondayNoon,
      holidays: const {},
      leadMinutes: 10,
    );
    expect(plan.every((r) => r.key.compareTo('2026-10-19') < 0), isTrue);
  });
}
