import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/features/today/today_models.dart';
import 'package:ucsc_router/features/today/today_text.dart';

import 'helpers.dart';

Analysis load(String name) => Analysis.fromJson(fixture(name));

void main() {
  group('the headline', () {
    test('before a class', () {
      expect(todaySummary(load('today_before_class')), 'Next: XYZ 10 Lecture at 2:40 PM in 2 h 40 min.');
    });

    test('during a class it says how long is left and what is next', () {
      expect(
        todaySummary(load('today_in_class')),
        'In XYZ 10 Lecture until 3:45 PM (45 min left). Next: ABC 20 Lecture at 4:00 PM in 1 h.',
      );
    });

    test('on a weekend it says so and points at the next class', () {
      expect(todaySummary(load('today_weekend')), 'No classes on weekends. Next class: Mon 8:00 AM, XYZ 10 Discussion.');
    });

    test('other reasons for no classes', () {
      Analysis reason(String r) => Analysis.fromJson({...fixture('today_weekend'), 'reason': r, 'next': null});
      expect(todaySummary(reason('holiday')), 'No classes today (holiday).');
      expect(todaySummary(reason('before_term')), "The term hasn't started yet.");
      expect(todaySummary(reason('after_term')), 'The term is over.');
      expect(todaySummary(reason('something_new')), 'No classes today.');
    });

    test('done for the day', () {
      final done = Analysis.fromJson({...fixture('today_weekend'), 'state': 'done_for_today'});
      expect(todaySummary(done), startsWith('Done for today. Next class: Mon'));
    });
  });

  group('the walk', () {
    test('has room to spare', () {
      final walk = walkText(load('today_before_class'))!;
      expect(walk.status, 'ok');
      expect(walk.text, startsWith('Walk to Kresge Acad 3201 is about 12 min from your location. '));
      expect(walk.text, endsWith('Leave by 2:28 PM.'));
    });

    test('too late', () {
      final walk = walkText(load('today_late'))!;
      expect(walk.status, 'late');
      expect(walk.text, endsWith("Not enough time: you'd arrive about 2 min late."));
    });

    test('from the class you are in', () {
      expect(walkText(load('today_in_class'))!.text, contains('from your current class'));
    });

    test('nothing to say without a walk', () {
      expect(walkText(load('today_weekend')), isNull);
    });
  });

  group('spare time', () {
    test('the three verdicts', () {
      expect(spareText(30, leaveBy: '2026-10-12T14:28:00-07:00').status, 'ok');
      expect(spareText(30, leaveBy: '2026-10-12T14:28:00-07:00').text, '30 min of free time. Leave by 2:28 PM.');
      expect(spareText(4).status, 'tight');
      expect(spareText(4).text, 'Tight: only 4 min to spare.');
      expect(spareText(0).status, 'tight');
      expect(spareText(-3).status, 'late');
      expect(spareText(5).status, 'ok', reason: 'five minutes to spare is fine');
    });
  });

  group('between classes', () {
    test('nothing before the first class', () {
      expect(transitionText(load('today_before_class').today.first), isNull);
    });

    test('a gap with a walk gets a verdict', () {
      const tight = ClassTime(
        course: 'XYZ 10',
        component: 'Lecture',
        location: 'Kresge Acad 3201',
        start: '2026-10-12T16:00:00-07:00',
        end: '2026-10-12T17:05:00-07:00',
        gapMin: 15,
        walkMin: 13,
        freeMin: 2,
        status: 'tight',
      );
      final t = transitionText(tight)!;
      expect(t.status, 'tight');
      expect(t.text, '15 min between classes, 13 min walk. Tight: only 2 min to spare.');
    });

    test("a gap where the walk can't be timed says so", () {
      const unknown = ClassTime(
        course: 'A',
        component: '',
        location: 'Online',
        start: '2026-10-12T16:00:00-07:00',
        end: '2026-10-12T17:05:00-07:00',
        gapMin: 90,
      );
      expect(transitionText(unknown)!.text, "1 h 30 min between classes (can't time the walk).");
    });
  });
}
