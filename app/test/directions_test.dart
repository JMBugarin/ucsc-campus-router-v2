import 'package:classmap/campus/campus.dart';
import 'package:classmap/campus/geo_point.dart';
import 'package:classmap/features/directions/directions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('the door to walk to', () {
    test('a room in a building uses the building\'s main entrance', () {
      final target = walkTarget(testCampus, 'Kresge Acad 3201')!;
      final r = testCampus.resolve('Kresge Acad 3201');
      final main = r.entrances.firstWhere(
        (e) => e.kind == 'main',
        orElse: () => r.entrances.first,
      );
      expect(target.point, main.point);
      expect(target.label, 'Kresge College Academic Building 3201');
    });

    test('a building with no room still has a place', () {
      final target = walkTarget(testCampus, 'Baskin Engineering');
      expect(target, isNotNull);
      expect(target!.label, 'Jack Baskin Engineering');
    });

    test('online, to-be-announced and unknown places have none', () {
      for (final place in ['Online', 'TBA', '', 'Mystery Hall 9']) {
        expect(walkTarget(testCampus, place), isNull, reason: place);
      }
    });

    test('a door pinned for a room beats the main entrance', () {
      final campus = Campus(
        [
          Building(
            id: 'b',
            name: 'Test Hall',
            aliases: const ['Test Hall'],
            knownRooms: const ['101'],
            entrances: const [
              Entrance(GeoPoint(1, 1), 'main'),
              Entrance(GeoPoint(2, 2), 'osm'),
            ],
          ),
        ],
        overrides: {
          'b:101': {
            'entrance': {'lat': 3.0, 'lon': 3.0},
          },
        },
      );
      expect(walkTarget(campus, 'Test Hall 101')!.point, const GeoPoint(3, 3));
      expect(walkTarget(campus, 'Test Hall 102')!.point, const GeoPoint(1, 1));
    });

    test('with no door the room, then the middle of the building, is used', () {
      final campus = Campus([
        Building(
          id: 'b',
          name: 'Test Hall',
          aliases: const ['Test Hall'],
          roomPoints: const {'7': RoomPoint(5, 5, 'L1')},
          centroid: const GeoPoint(9, 9),
        ),
      ]);
      expect(walkTarget(campus, 'Test Hall 7')!.point, const GeoPoint(5, 5));
      expect(walkTarget(campus, 'Test Hall 8')!.point, const GeoPoint(9, 9));
    });

    test('a building with no position at all has no target', () {
      final campus = Campus([
        Building(id: 'b', name: 'Test Hall', aliases: const ['Test Hall']),
      ]);
      expect(walkTarget(campus, 'Test Hall 7'), isNull);
    });

    test('every classroom the university lists can be walked to', () {
      for (final b in testCampus.buildings.values) {
        for (final room in b.knownRooms) {
          expect(
            walkTarget(testCampus, '${b.name} $room'),
            isNotNull,
            reason: '${b.name} $room',
          );
        }
      }
    });
  });

  group('the link', () {
    const target = WalkTarget(
      label: 'Test Hall 7',
      point: GeoPoint(36.9998, -122.0628),
    );

    test('Apple Maps asks for walking directions to the point', () {
      final uri = walkingDirectionsUri(target, android: false);
      expect(
        uri.toString(),
        'https://maps.apple.com/?daddr=36.9998%2C-122.0628&dirflg=w',
      );
    });

    test('Google Maps asks for walking directions to the point', () {
      final uri = walkingDirectionsUri(target, android: true);
      expect(uri.host, 'www.google.com');
      expect(uri.queryParameters, {
        'api': '1',
        'destination': '36.9998,-122.0628',
        'travelmode': 'walking',
      });
    });

    test('the link never carries where the phone is', () {
      final uri = walkingDirectionsUri(target, android: false);
      expect(uri.queryParameters.keys, unorderedEquals(['daddr', 'dirflg']));
    });
  });
}
