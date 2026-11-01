import 'dart:convert';
import 'dart:io';

import 'package:classmap/campus/campus_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// The data the app ships must be the data in `data/`, which the tools in `data-pipeline/` write. After
/// changing `data/`, run `scripts/sync_app_data.sh`.
void main() {
  for (final name in ['buildings', 'rooms', 'search_aliases', 'holidays']) {
    test('$name.json in the app is the one in data/', () {
      expect(
        File('assets/data/$name.json').readAsStringSync(),
        File('../data/$name.json').readAsStringSync(),
        reason: 'run scripts/sync_app_data.sh',
      );
    });
  }

  test('every official classroom name resolves to its building and room', () {
    final rooms = (jsonDecode(File('../data/classrooms.json').readAsStringSync()) as Map)['rooms'] as List;
    expect(rooms.length, greaterThan(80));
    final campus = campusFromJson(
      buildings: File('assets/data/buildings.json').readAsStringSync(),
      rooms: File('assets/data/rooms.json').readAsStringSync(),
      aliases: File('assets/data/search_aliases.json').readAsStringSync(),
    );
    for (final room in rooms) {
      final name = room['ais_display_name'] as String;
      final facility = room['facility_id'] as String;
      final r = campus.resolve(name);
      expect(r.kind, 'building', reason: name);
      expect(r.room, facility.split(' ').last.toUpperCase(), reason: name);
      expect(r.roomKnown, isTrue, reason: name);
      expect(campus.buildings[r.buildingId]!.centroid, isNotNull, reason: name);
    }
  });

  test('the terms cover the next two years of classes', () {
    final terms = jsonDecode(File('assets/data/holidays.json').readAsStringSync())['terms'] as List;
    expect(terms.last['end'].compareTo('2027-06-01'), greaterThan(0));
  });
}
