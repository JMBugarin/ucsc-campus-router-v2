import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'campus.dart';
import 'terms.dart';

Campus campusFromJson({
  required String buildings,
  String? rooms,
  String? aliases,
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
    searchAliases: searchAliases,
  );
}

/// The campus data bundled with the app (`assets/data`). Nothing is fetched at run time.
final campusProvider = FutureProvider<Campus>((ref) async {
  final texts = await Future.wait([
    rootBundle.loadString('assets/data/buildings.json'),
    rootBundle.loadString('assets/data/rooms.json'),
    rootBundle.loadString('assets/data/search_aliases.json'),
  ]);
  return campusFromJson(
    buildings: texts[0],
    rooms: texts[1],
    aliases: texts[2],
  );
});

final termsProvider = FutureProvider<List<Term>>((ref) async {
  final text = await rootBundle.loadString('assets/data/holidays.json');
  return termsFromJson(jsonDecode(text) as Map<String, dynamic>);
});
