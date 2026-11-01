import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:classmap/campus/campus_data.dart';
import 'package:classmap/campus/terms.dart';
import 'package:classmap/features/schedule/import/clean.dart';
import 'package:classmap/features/schedule/import/ics.dart';
import 'package:classmap/features/schedule/import/paste.dart';

/// The Dart campus, schedule and calendar code against outputs recorded from the Python code it replaced
/// (`test/fixtures/golden_port.json`).
void main() {
  final golden =
      jsonDecode(File('test/fixtures/golden_port.json').readAsStringSync())
          as Map<String, dynamic>;
  final campus = campusFromJson(
    buildings: File('assets/data/buildings.json').readAsStringSync(),
    rooms: File('assets/data/rooms.json').readAsStringSync(),
    aliases: File('assets/data/search_aliases.json').readAsStringSync(),
  );
  final terms = termsFromJson(
    jsonDecode(File('assets/data/holidays.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  List cases(String key) => golden[key] as List;

  test('room resolution matches', () {
    for (final c in cases('resolve')) {
      final r = campus.resolve(c['input'] as String);
      final want = c['out'] as Map<String, dynamic>;
      final label = 'resolve "${c['input']}"';
      expect(r.kind, want['kind'], reason: label);
      expect(r.buildingId, want['building_id'], reason: label);
      expect(r.room, want['room'], reason: label);
      expect(r.roomKnown, want['room_known'], reason: label);
      expect(r.floor, want['floor'], reason: label);
      expect(r.entrances.length, want['entrances'], reason: label);
      final point = want['room_point'] as Map<String, dynamic>?;
      expect(r.roomPoint?.lat, point?['lat'], reason: label);
      expect(r.roomPoint?.lon, point?['lon'], reason: label);
    }
  });

  test('search matches', () {
    for (final c in cases('search')) {
      final hits = campus.search(c['input'] as String, 6);
      final want = c['out'] as List;
      final label = 'search "${c['input']}"';
      expect(
        [for (final h in hits) h.label],
        [for (final w in want) w['label']],
        reason: label,
      );
      for (var i = 0; i < want.length; i++) {
        final h = hits[i];
        final w = want[i] as Map<String, dynamic>;
        expect(h.buildingId, w['building_id'], reason: label);
        expect(h.room, w['room'], reason: label);
        expect(h.roomKnown, w['room_known'], reason: label);
        expect(h.floor, w['floor'], reason: label);
        expect(h.query, w['query'], reason: label);
        expect(h.point?.lat, (w['point'] as Map?)?['lat'], reason: label);
        expect(h.point?.lon, (w['point'] as Map?)?['lon'], reason: label);
      }
    }
  });

  test('location splitting matches', () {
    for (final c in cases('split')) {
      final (room, rest) = campus.splitLocation(c['input'] as String);
      expect([room, rest], c['out'], reason: '${c['input']}');
    }
  });

  test('cleaning matches', () {
    for (final c in cases('clean')) {
      final want = c['out'] as Map<String, dynamic>;
      final label = '${c['input']}';
      if (want.containsKey('error')) {
        expect(
          () => cleanMeetingJson(c['input'] as Map<String, dynamic>),
          throwsA(
            isA<ScheduleError>().having(
              (e) => e.message,
              'message',
              want['error'],
            ),
          ),
          reason: label,
        );
      } else {
        expect(
          cleanMeetingJson(c['input'] as Map<String, dynamic>).toJson(),
          want['meeting'],
          reason: label,
        );
      }
    }
  });

  test('pasted schedules match', () {
    for (final c in cases('paste')) {
      final want = c['out'] as Map<String, dynamic>;
      final got = parsePasted(c['input'] as String, campus);
      expect(
        [for (final m in got.meetings) m.toJson()],
        want['meetings'],
        reason: '${c['input']}',
      );
      expect(got.notes, want['notes'], reason: '${c['input']}');
    }
  });

  test('calendar files match, with and without a term', () {
    for (final c in cases('ics')) {
      final text = c['input'] as String;
      for (final withTerm in [true, false]) {
        final want =
            c[withTerm ? 'with_term' : 'no_term'] as Map<String, dynamic>;
        final label =
            '${withTerm ? 'term' : 'no term'}: ${text.substring(0, text.length > 80 ? 80 : text.length)}';
        if (want.containsKey('error')) {
          expect(
            () => parseIcs(text, term: withTerm ? terms.first : null),
            throwsA(
              isA<ScheduleError>().having(
                (e) => e.message,
                'message',
                want['error'],
              ),
            ),
            reason: label,
          );
          continue;
        }
        final got = parseIcs(text, term: withTerm ? terms.first : null);
        expect(
          [for (final m in got.meetings) m.toJson()],
          want['meetings'],
          reason: label,
        );
        expect(got.notes, want['notes'], reason: label);
      }
    }
  });

  test('terms pick the right term and holidays', () {
    final t = golden['term']['terms'] as List;
    expect(terms.map((x) => x.name), [for (final x in t) x['name']]);
    expect(termFor(terms, '2026-10-01')!.name, 'Fall 2026');
    expect(termFor(terms, '2026-12-20')!.name, 'Winter 2027');
    expect(termFor(terms, '2030-01-01')!.name, 'Spring 2027');
    expect(holidaysOf(terms), contains('2026-11-26'));
  });

  test('a pasted row with an impossible time is named, not dropped silently', () {
    final got = parsePasted(
      'XYZ 10 - Sample Status Units Grading Grade Deadlines Enrolled 5.00 Graded '
      '10008 03 Seminar Th 25:00AM - 8:00AM TBA Staff 09/24/2026 - 12/04/2026',
      campus,
    );
    expect(got.meetings, isEmpty);
    expect(got.notes.single, startsWith("Couldn't read XYZ 10 Seminar"));
  });
}
