import 'package:classmap/campus/campus.dart';
import 'package:classmap/campus/geo_point.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('floors', () {
    test(
      'come from a walk or a published source, never the room number or map level',
      () {
        // The campus map puts McHenry 1340 on level L3; the library's floor plan says floor 1.
        expect(
          testCampus.roomFloor('mchenry-library', '1340')?.text,
          'Floor 1 · one floor below the main entrance',
        );
        expect(
          testCampus.roomFloor('merrill-academic', '102')?.text,
          'Floor 2 · upstairs',
        );
        expect(
          testCampus.roomFloor('merrill-academic', '002')?.text,
          'Floor 1 · entrance level',
        );
        expect(testCampus.roomFloor('engineering-2', '192')?.text, 'Floor 1');
        expect(testCampus.roomFloor('baskin-engineering', '372'), isNull);
        expect(testCampus.roomFloor('social-sciences-2', '071'), isNull);
        expect(testCampus.roomFloor('mchenry-library', null), isNull);
      },
    );
    test('every published floor names its source and a real room', () {
      expect(testCampus.floors, isNotEmpty);
      testCampus.floors.forEach((key, f) {
        final [b, room] = key.split(':');
        expect(
          testCampus.buildings[b]?.roomPoints,
          contains(room),
          reason: key,
        );
        expect(f.sourceUrl, startsWith('https://'), reason: key);
        expect(f.label, matches(RegExp(r'^(\d{1,2}|G)$')), reason: key);
      });
    });
    test('a walked floor wins over a published one', () {
      final campus = Campus(
        [
          Building(id: 'b', name: 'Test Hall', aliases: const ['Test Hall']),
        ],
        overrides: {
          'b:101': {'floor': '2', 'checked': '2026-11-20'},
        },
        floors: {
          'b:101': const RoomFloor(
            '1',
            where: 'entrance',
            sourceName: 'Map',
            sourceUrl: 'https://x',
          ),
        },
      );
      expect(campus.roomFloor('b', '101')?.text, 'Floor 2');
      expect(campus.roomFloor('b', '101')?.checked, isTrue);
    });
  });

  group('room guides', () {
    test('need a checked date', () {
      expect(RoomGuide.fromOverride({'note': 'x'}), isNull);
      expect(RoomGuide.fromOverride(null), isNull);
    });
    test('carry what was checked', () {
      final g = RoomGuide.fromOverride({
        'access': 'outside',
        'entrance': {'lat': 37.0, 'lon': -122.0, 'label': 'Courtyard door'},
        'wing': 'North wing',
        'note': 'Corner room facing the trees',
        'steps': ['Through the glass doors', 'Second door on the left'],
        'step_free': true,
        'elevator': 'By the main lobby',
        'checked': '2026-11-20',
        'source': 'student-tip',
      })!;
      expect(g.access, 'outside');
      expect(g.doorLabel, 'Courtyard door');
      expect(g.steps, hasLength(2));
      expect(g.stepFree, isTrue);
      expect(g.source, 'student-tip');
    });
    test('come through resolve for the room they name', () {
      final campus = Campus(
        [
          Building(
            id: 'b',
            name: 'Test Hall',
            aliases: const ['Test Hall'],
            knownRooms: const ['101'],
          ),
        ],
        overrides: {
          'b:101': {
            'access': 'library',
            'note': 'Past the help desk',
            'checked': '2026-11-20',
          },
        },
      );
      expect(campus.resolve('Test Hall 101').guide?.note, 'Past the help desk');
      expect(campus.resolve('Test Hall 102').guide, isNull);
    });
  });

  test('distances and directions between points', () {
    const a = GeoPoint(37.0, -122.06);
    const b = GeoPoint(37.0002, -122.06);
    expect(a.metresTo(b), closeTo(22.2, 0.5));
    expect(a.compassTo(b), 'north');
    expect(b.compassTo(a), 'south');
  });
}
