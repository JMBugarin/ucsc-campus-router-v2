import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/features/schedule/meeting.dart';
import 'package:ucsc_router/features/today/today_models.dart';

/// These fixtures are real answers captured from the server for an invented schedule, so the
/// tests check the app against the server's actual contract, not against what I remember of it.
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('Meeting', () {
    final raw = {
      'course': 'XYZ 10',
      'title': 'Sample Calculus',
      'section': '01',
      'component': 'Lecture',
      'class_nbr': '',
      'days': [0, 2, 4],
      'start': '14:40',
      'end': '15:45',
      'location': 'Kresge Acad 3201',
      'start_date': '2026-09-24',
      'end_date': '2026-12-04',
    };

    test('round-trips through JSON', () {
      final meeting = Meeting.fromJson(raw);
      expect(meeting.toJson(), raw);
      expect(Meeting.fromJson(meeting.toJson()).toJson(), raw);
    });

    test('skip dates are kept only when there are some', () {
      expect(Meeting.fromJson(raw).toJson().containsKey('skip_dates'), isFalse);
      final skipping = Meeting.fromJson({...raw, 'skip_dates': ['2026-11-09']});
      expect(skipping.toJson()['skip_dates'], ['2026-11-09']);
    });

    test('labels', () {
      final meeting = Meeting.fromJson(raw);
      expect(meeting.label, 'XYZ 10 Lecture');
      expect(meeting.whenLabel, 'MoWeFr');
      expect(meeting.timeLabel, '2:40 PM–3:45 PM');
      final oneOff = Meeting.fromJson({...raw, 'days': <int>[], 'start_date': '2026-10-12', 'end_date': '2026-10-12'});
      expect(oneOff.whenLabel, '2026-10-12');
    });

    test('the same class is recognised, a different one is not', () {
      final a = Meeting.fromJson(raw);
      expect(a.sameClassAs(Meeting.fromJson(raw)), isTrue);
      expect(a.sameClassAs(Meeting.fromJson({...raw, 'start': '14:50'})), isFalse);
      expect(a.sameClassAs(Meeting.fromJson({...raw, 'days': [0, 2]})), isFalse);
      expect(a.sameClassAs(Meeting.fromJson({...raw, 'location': 'Soc Sci 2 075'})), isFalse);
    });

    test('missing fields do not crash', () {
      final bare = Meeting.fromJson({'days': [1], 'start': '09:00', 'end': '10:00'});
      expect(bare.course, '');
      expect(bare.label, '');
    });
  });

  group('server answers', () {
    test('/api/schedule/parse', () {
      final result = ImportResult.fromJson(fixture('parse'));
      expect(result.meetings.length, 2);
      expect(result.meetings.first.component, 'Discussion');
      expect(result.meetings.first.location, 'Cowell Acad 113');
      expect(result.locations.first.kind, 'building');
    });

    test('/api/schedule/clean flags a room it does not know', () {
      final result = ImportResult.fromJson(fixture('clean'));
      expect(result.meetings.length, 4);
      expect(result.locations.map((l) => l.kind), ['building', 'building', 'building', 'unknown']);
      expect(result.locations.first.buildingName, 'Kresge College Academic Building');
      expect(result.locations.last.isUnknown, isTrue);
    });

    test('before class, with the walk and free time', () {
      final a = Analysis.fromJson(fixture('today_before_class'));
      expect(a.state, 'between_classes');
      expect(a.next!.label, 'XYZ 10 Lecture');
      expect(a.next!.isToday, isTrue);
      expect(a.next!.startsInMin, 160.0);
      expect(a.walk!.minutes, 12);
      expect(a.walk!.from, 'here');
      expect(a.status, 'ok');
      expect(a.leaveBy, '2026-10-12T14:28:00-07:00');
      expect(a.banner, isNull);
      expect(a.today.map((t) => t.label), ['XYZ 10 Discussion', 'XYZ 10 Lecture', 'ABC 20 Lecture']);
      expect(a.today.first.gapMin, isNull); // nothing before the first class
      expect(a.today[1].gapMin, isNotNull);
      expect(a.today[2].status, isNotNull);
    });

    test('running late: a banner and one immediate reminder', () {
      final a = Analysis.fromJson(fixture('today_late'));
      expect(a.status, 'late');
      expect(a.freeMin, -2.0);
      expect(a.banner!.late, isTrue);
      expect(a.banner!.text, startsWith('Leave now for XYZ 10 Lecture'));
      expect(a.reminders.single.stage, 'late');
      expect(a.reminders.single.inSeconds, 0);
      expect(a.reminders.single.key, endsWith('|leave'));
    });

    test('a heads-up that is a couple of seconds away', () {
      final a = Analysis.fromJson(fixture('today_heads_up_soon'));
      expect(a.reminders.map((r) => r.stage), ['heads-up', 'leave']);
      expect(a.reminders.first.inSeconds, closeTo(2, 0.5));
      expect(a.reminders.first.title, 'Leave in 5 min for XYZ 10 Lecture');
    });

    test('in class: the current class and minutes left', () {
      final a = Analysis.fromJson(fixture('today_in_class'));
      expect(a.state, 'in_class');
      expect(a.current!.label, 'XYZ 10 Lecture');
      expect(a.current!.minutesLeft, 45.0);
      expect(a.next!.label, 'ABC 20 Lecture');
      expect(a.walk!.from, 'current_class');
    });

    test('a weekend has no classes and points at Monday', () {
      final a = Analysis.fromJson(fixture('today_weekend'));
      expect(a.state, 'no_classes_today');
      expect(a.reason, 'weekend');
      expect(a.today, isEmpty);
      expect(a.next!.isToday, isFalse);
      expect(a.walk, isNull);
      expect(a.reminders, isEmpty);
    });

    test('/api/meta', () {
      final meta = fixture('meta');
      expect(meta['nodes'], greaterThan(1000));
      expect((meta['term'] as Map)['start'], '2026-09-24');
    });
  });
}
