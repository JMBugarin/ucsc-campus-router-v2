import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:ucsc_router/core/pacific.dart';
import 'package:ucsc_router/features/reminders/reminder_planner.dart';
import 'package:ucsc_router/features/schedule/meeting.dart';
import 'package:ucsc_router/features/today/today_models.dart';
import 'package:ucsc_router/features/today/walk_cache.dart';

const kresge = 'Kresge Acad 3201';
const socSci = 'Soc Sci 2 075';

/// A moment on the campus clock.
tz.TZDateTime at(int y, int m, int d, [int h = 0, int min = 0]) => tz.TZDateTime(pacific, y, m, d, h, min);

Meeting cls({
  String course = 'XYZ 10',
  List<int> days = const [1],
  String start = '09:00',
  String end = '09:50',
  String location = kresge,
  String from = '2026-09-24',
  String to = '2026-12-04',
}) =>
    Meeting(
      course: course,
      component: 'Lecture',
      days: days,
      start: start,
      end: end,
      location: location,
      startDate: from,
      endDate: to,
    );

/// Walk times as the server's answers would have left them; `any` mirrors every destination, so a
/// planner that fell back to it would show.
Future<WalkCache> cache(Map<String, int> walks) async {
  SharedPreferences.setMockInitialValues({
    'walk_cache_v1': jsonEncode({
      'walks': walks,
      'any': {for (final e in walks.entries) e.key.split('>').last: e.value},
      'holidays': <String>[],
    }),
  });
  return WalkCache(await SharedPreferences.getInstance());
}

DateTime due(Reminder r, DateTime now) => now.add(Duration(milliseconds: (r.inSeconds * 1000).round()));

List<Reminder> plan(
  List<Meeting> meetings,
  DateTime now,
  WalkCache walks, {
  int lead = 0,
  Set<String> holidays = const {},
  Set<String> sent = const {},
}) =>
    planAhead(meetings: meetings, now: now, holidays: holidays, walks: walks, leadMinutes: lead, sent: sent);

Reminder reminder(String key, double inSeconds) =>
    Reminder(stage: key.split('|').last, key: key, inSeconds: inSeconds, title: key, body: '');

void main() {
  group('tomorrow, and the day boundary', () {
    test('a morning class is planned the evening before, with a heads-up and a leave', () async {
      final walks = await cache({'*>$kresge': 12});
      final evening = at(2026, 10, 19, 23, 30); // Monday night; the class is Tuesday 9:00
      final p = plan([cls()], evening, walks, lead: 5);

      expect([for (final r in p) r.key], ['2026-10-20T09:00:00-07:00|heads-up', '2026-10-20T09:00:00-07:00|leave']);
      expect(p[0].inSeconds, 33180); // 8:43 AM, 9 h 13 min away
      expect(p[1].inSeconds, 33480); // 8:48 AM
      expect(p[0].title, 'Leave in 5 min for XYZ 10 Lecture');
      expect(p[1].title, 'Time to leave for XYZ 10 Lecture');
      expect(p[1].body, '$kresge: about 12 min on foot. Class starts at 9:00 AM.');
    });

    test('the same moments hold on either side of midnight', () async {
      final walks = await cache({'*>$kresge': 12});
      final before = plan([cls()], at(2026, 10, 19, 23, 59), walks, lead: 5);
      final after = plan([cls()], at(2026, 10, 20, 0, 1), walks, lead: 5);

      expect([for (final r in after) r.key], [for (final r in before) r.key]);
      for (var i = 0; i < before.length; i++) {
        expect(due(after[i], at(2026, 10, 20, 0, 1)), due(before[i], at(2026, 10, 19, 23, 59)));
      }
    });

    test('once the moment to leave has passed there is nothing left to plan for that class', () async {
      final walks = await cache({'*>$kresge': 12});
      expect(plan([cls()], at(2026, 10, 20, 8, 50), walks), isEmpty);
      expect(plan([cls()], at(2026, 10, 20, 9, 30), walks), isEmpty, reason: 'the class has started');
    });

    test('a class that is still to come today is planned as well', () async {
      final walks = await cache({'*>$kresge': 12});
      final p = plan([cls(days: [0, 1, 2, 3, 4], start: '14:40', end: '15:45')], at(2026, 10, 20, 9), walks);
      expect([for (final r in p.take(2)) r.key], ['2026-10-20T14:40:00-07:00|leave', '2026-10-21T14:40:00-07:00|leave']);
      expect(p.first.inSeconds, (5 * 60 + 28) * 60);
    });
  });

  group('which classes get a reminder', () {
    test('a later class is walked to from the one before it, and never reminded before that one ends', () async {
      final walks = await cache({'*>$kresge': 12, '$kresge>$socSci': 15});
      final classes = [
        cls(),
        cls(course: 'ABC 20', start: '10:00', end: '10:50', location: socSci),
      ];
      final leaves = plan(classes, at(2026, 10, 19, 20), walks).where((r) => r.stage == 'leave').toList();

      expect([for (final r in leaves) r.key], ['2026-10-20T09:00:00-07:00|leave', '2026-10-20T10:00:00-07:00|leave']);
      expect(due(leaves[0], at(2026, 10, 19, 20)), at(2026, 10, 20, 8, 48));
      expect(due(leaves[1], at(2026, 10, 19, 20)), at(2026, 10, 20, 9, 50), reason: '10:00 minus 15 min is before 9:50');
    });

    test('a class with no saved walk gets nothing, whatever other walks to its room are saved', () async {
      final walks = await cache({'$socSci>$kresge': 8});
      final classes = [
        cls(location: socSci),
        cls(course: 'ABC 20', start: '10:00', end: '10:50'),
        cls(course: 'ONL 1', start: '11:00', end: '11:50', location: 'Online'),
        cls(course: 'TBA 1', start: '12:00', end: '12:50', location: ''),
      ];
      final p = plan(classes, at(2026, 10, 19, 20), walks);
      // the first class has no walk from the student's position; only the walk Soc Sci to Kresge is known
      expect([for (final r in p) r.key], ['2026-10-20T10:00:00-07:00|leave']);
    });

    test('with no heads-up there is only the leave, and the lead moves the heads-up', () async {
      final walks = await cache({'*>$kresge': 12});
      expect([for (final r in plan([cls()], at(2026, 10, 19, 20), walks)) r.stage], ['leave']);
      final ten = plan([cls()], at(2026, 10, 19, 20), walks, lead: 10);
      expect([for (final r in ten) r.stage], ['heads-up', 'leave']);
      expect(ten[1].inSeconds - ten[0].inSeconds, 600);
    });

    test('reminders already shown are not planned again', () async {
      final walks = await cache({'*>$kresge': 12});
      final p = plan([cls()], at(2026, 10, 19, 20), walks, lead: 5, sent: {'2026-10-20T09:00:00-07:00|heads-up'});
      expect([for (final r in p) r.stage], ['leave']);
    });

    test('a holiday has no reminder, and the days around it do', () async {
      final walks = await cache({'*>$kresge': 12});
      final p = plan([cls(days: [1, 3])], at(2026, 11, 23, 20), walks, holidays: {'2026-11-26'}); // Thanksgiving
      expect([for (final r in p) r.key], ['2026-11-24T09:00:00-08:00|leave']);
    });

    test('a class skipped for a date is left out', () async {
      final walks = await cache({'*>$kresge': 12});
      final skipped = Meeting(
        course: 'XYZ 10',
        component: 'Lecture',
        days: const [1],
        start: '09:00',
        end: '09:50',
        location: kresge,
        startDate: '2026-09-24',
        endDate: '2026-12-04',
        skipDates: const ['2026-10-20'],
      );
      expect(plan([skipped], at(2026, 10, 19, 20), walks), isEmpty);
    });
  });

  group('across a term boundary', () {
    final fall = cls(days: [0, 2, 4], to: '2026-12-04');
    final winter = cls(course: 'ABC 20', days: [0, 2, 4], from: '2027-01-04', to: '2027-03-12');
    late WalkCache walks;

    setUp(() async => walks = await cache({'*>$kresge': 12}));

    List<String> keys(DateTime now, {Set<String> holidays = const {}}) => [
          for (final r in plan([fall, winter], now, walks, holidays: holidays)) r.key,
        ];

    test('the last day of fall is planned the evening before, and nothing after it', () {
      expect(keys(at(2026, 12, 3, 18)), ['2026-12-04T09:00:00-08:00|leave']);
    });

    test('after the last fall class there is nothing to plan over the break', () {
      expect(keys(at(2026, 12, 4, 18)), isEmpty);
      expect(keys(at(2026, 12, 20, 12)), isEmpty);
    });

    test('the first winter day is planned the evening before', () {
      expect(keys(at(2027, 1, 3, 20)), [
        '2027-01-04T09:00:00-08:00|leave',
        '2027-01-06T09:00:00-08:00|leave',
        '2027-01-08T09:00:00-08:00|leave',
      ]);
    });

    test('a holiday inside the new term is skipped', () {
      expect(keys(at(2027, 1, 15, 18), holidays: {'2027-01-18'}), ['2027-01-20T09:00:00-08:00|leave']);
    });

    test('a fall reminder is not in the plan once winter starts', () {
      final fallKey = '2026-12-04T09:00:00-08:00|leave';
      expect(keys(at(2026, 12, 3, 18)), [fallKey]);
      expect(keys(at(2027, 1, 3, 20)), isNot(contains(fallKey)));
    });
  });

  test('clocks changing do not shift a reminder: the spring-forward weekend', () async {
    final walks = await cache({'*>$kresge': 12});
    final springMonday = Meeting(
      course: 'XYZ 10',
      component: 'Lecture',
      days: const [0],
      start: '08:00',
      end: '08:50',
      location: kresge,
      startDate: '2027-01-04',
      endDate: '2027-06-04',
    );

    final saturdayEvening = at(2027, 3, 13, 20); // 4:00 AM UTC on Sunday, still standard time
    final p = plan([springMonday], saturdayEvening, walks);
    expect(p.single.key, '2027-03-15T08:00:00-07:00|leave');
    final expected = DateTime.utc(2027, 3, 15, 14, 48).difference(DateTime.utc(2027, 3, 14, 4)); // 7:48 AM PDT
    expect(p.single.inSeconds, expected.inSeconds);
    expect(expected, const Duration(hours: 34, minutes: 48), reason: 'the weekend is 23 hours long');
  });

  group('merging with the server', () {
    test('the server decides for the classes it timed, the phone plan fills in the rest', () {
      final server = [reminder('A|leave', 100), reminder('A|heads-up', 50)];
      final ahead = [reminder('A|leave', 90), reminder('B|leave', 70), reminder('C|heads-up', 20)];
      final merged = mergeReminderPlans(server: server, ahead: ahead);
      expect([for (final r in merged) r.key], ['C|heads-up', 'A|heads-up', 'B|leave', 'A|leave']);
      expect(merged.last.inSeconds, 100, reason: "the server's time for a class wins");
    });

    test('with no server reminders the phone plan stands alone', () {
      final ahead = [reminder('B|leave', 70), reminder('A|leave', 30)];
      expect([for (final r in mergeReminderPlans(server: const [], ahead: ahead)) r.key], ['A|leave', 'B|leave']);
    });
  });

  group('days whose walks have not been saved', () {
    test('only upcoming days with two classes and no saved walk between them', () async {
      final classes = [
        cls(days: [0, 1]), // Monday (today) and Tuesday, 9:00
        cls(course: 'ABC 20', days: [0, 1], start: '10:00', end: '10:50', location: socSci),
        cls(course: 'DEF 30', days: [3], start: '13:00', end: '13:50'), // Thursday alone
      ];
      final empty = await cache({});
      final missing = daysMissingWalks(meetings: classes, now: at(2026, 10, 19, 8), holidays: {}, walks: empty);
      expect(missing, [DateTime.utc(2026, 10, 20)], reason: 'today is covered by the server, a lone class needs no pair');

      final known = await cache({'$kresge>$socSci': 15});
      expect(daysMissingWalks(meetings: classes, now: at(2026, 10, 19, 8), holidays: {}, walks: known), isEmpty);
    });

    test('a class with no room is not asked about', () async {
      final classes = [cls(), cls(course: 'ONL 1', start: '10:00', end: '10:50', location: '')];
      final walks = await cache({});
      expect(daysMissingWalks(meetings: classes, now: at(2026, 10, 19, 8), holidays: {}, walks: walks), isEmpty);
    });
  });
}
