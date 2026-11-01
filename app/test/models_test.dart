import 'dart:convert';
import 'dart:io';

import 'package:classmap/features/schedule/meeting.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

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
      final skipping = Meeting.fromJson({
        ...raw,
        'skip_dates': ['2026-11-09'],
      });
      expect(skipping.toJson()['skip_dates'], ['2026-11-09']);
    });

    test('labels', () {
      final meeting = Meeting.fromJson(raw);
      expect(meeting.label, 'XYZ 10 Lecture');
      expect(meeting.whenLabel, 'MoWeFr');
      expect(meeting.timeLabel, '2:40 PM–3:45 PM');
      final oneOff = Meeting.fromJson({
        ...raw,
        'days': <int>[],
        'start_date': '2026-10-12',
        'end_date': '2026-10-12',
      });
      expect(oneOff.whenLabel, '2026-10-12');
    });

    test('the same class is recognised, a different one is not', () {
      final a = Meeting.fromJson(raw);
      expect(a.sameClassAs(Meeting.fromJson(raw)), isTrue);
      expect(
        a.sameClassAs(Meeting.fromJson({...raw, 'start': '14:50'})),
        isFalse,
      );
      expect(
        a.sameClassAs(
          Meeting.fromJson({
            ...raw,
            'days': [0, 2],
          }),
        ),
        isFalse,
      );
      expect(
        a.sameClassAs(Meeting.fromJson({...raw, 'location': 'Soc Sci 2 075'})),
        isFalse,
      );
    });

    test('missing fields do not crash', () {
      final bare = Meeting.fromJson({
        'days': [1],
        'start': '09:00',
        'end': '10:00',
      });
      expect(bare.course, '');
      expect(bare.label, '');
    });
  });
}
