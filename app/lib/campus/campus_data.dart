import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'campus.dart';
import 'housing.dart';
import 'terms.dart';

Campus campusFromJson({
  required String buildings,
  String? rooms,
  String? aliases,
  String? floors,
}) {
  final list =
      (jsonDecode(buildings) as Map<String, dynamic>)['buildings'] as List;
  final overrides = rooms == null
      ? const <String, dynamic>{}
      : (jsonDecode(rooms) as Map)['overrides'] as Map<String, dynamic>? ??
            const {};
  final searchAliases = <String, List<String>>{
    if (aliases != null)
      for (final e in (jsonDecode(aliases) as Map<String, dynamic>).entries)
        e.key: [for (final a in (e.value as List)) a as String],
  };
  return Campus(
    [for (final b in list) Building.fromJson(b as Map<String, dynamic>)],
    overrides: overrides,
    floors: floors == null ? const {} : floorsFromJson(floors),
    searchAliases: searchAliases,
  );
}

/// `data/floors.json`: each confirmed floor with the published source it came from.
Map<String, RoomFloor> floorsFromJson(String text) {
  final json = jsonDecode(text) as Map<String, dynamic>;
  final sources = json['sources'] as Map<String, dynamic>? ?? const {};
  return {
    for (final e
        in (json['rooms'] as Map<String, dynamic>? ?? const {}).entries)
      e.key: RoomFloor(
        (e.value as Map)['floor'] as String,
        where: (e.value as Map)['where'] as String?,
        sourceName:
            (sources[(e.value as Map)['source']] as Map?)?['name'] as String?,
        sourceUrl:
            (sources[(e.value as Map)['source']] as Map?)?['url'] as String?,
      ),
  };
}

/// The campus data bundled with the app (`assets/data`). Nothing is fetched at run time.
final campusProvider = FutureProvider<Campus>((ref) async {
  final texts = await Future.wait([
    rootBundle.loadString('assets/data/buildings.json'),
    rootBundle.loadString('assets/data/rooms.json'),
    rootBundle.loadString('assets/data/search_aliases.json'),
    rootBundle.loadString('assets/data/floors.json'),
  ]);
  return campusFromJson(
    buildings: texts[0],
    rooms: texts[1],
    aliases: texts[2],
    floors: texts[3],
  );
});

/// Every residence hall and apartment building (`assets/data/housing.json`), for finding and walking home.
final housingProvider = FutureProvider<HousingIndex>((ref) async {
  final text = await rootBundle.loadString('assets/data/housing.json');
  return HousingIndex(housingFromJson(text));
});

final termsProvider = FutureProvider<List<Term>>((ref) async {
  final text = await rootBundle.loadString('assets/data/holidays.json');
  return termsFromJson(jsonDecode(text) as Map<String, dynamic>);
});
