import 'package:classmap/campus/campus.dart';
import 'package:classmap/campus/geo_point.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('floors', () {
    test('read the floor a room number implies', () {
      expect(floorFromRoomNumber('152'), '1');
      expect(floorFromRoomNumber('071'), '0');
      expect(floorFromRoomNumber('B206'), '2');
      expect(floorFromRoomNumber('3201'), '2');
      expect(floorFromRoomNumber('1340'), '3');
      expect(floorFromRoomNumber('Hall'), isNull);
    });
    test('say Floor N, and name the campus map when the number disagrees', () {
      expect(floorText('L1', room: '152'), 'Floor 1');
      expect(floorText('L3', room: '1340'), 'Floor 3');
      expect(floorText('L1', room: '001'), 'Floor 1 (campus map)');
      expect(floorText('L0', room: '071'), 'Lower level (floor 0)');
      expect(floorText('2', room: '152'), 'Floor 2');
      expect(floorText('Ground'), 'Ground');
      expect(floorText(null), isNull);
    });
    test('every listed classroom gets a floor', () {
      for (final b in testCampus.buildings.values) {
        for (final e in b.roomPoints.entries) {
          expect(
            floorText(e.value.level, room: e.key),
            matches(RegExp('^(Floor|Lower)')),
            reason: '${b.name} ${e.key}',
          );
        }
      }
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
