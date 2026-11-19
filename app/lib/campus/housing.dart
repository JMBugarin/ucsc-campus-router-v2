import 'dart:convert';

import 'campus.dart';
import 'geo_point.dart';

/// A residence hall or apartment building (`data/housing.json`, from the campus map's residential layer).
class Housing {
  const Housing({
    required this.id,
    required this.name,
    required this.area,
    required this.point,
    this.short,
    this.knownAs,
    this.aliases = const [],
  });

  final String id;

  /// The official name, such as `College Nine Apartment Building 2`.
  final String name;

  /// The college or housing area, such as `College Nine` or `The Village`.
  final String area;
  final GeoPoint point;

  /// A short label: `Galileo House`, `Casa Primera`, `Apartment Building 2`.
  final String? short;

  /// The name students know it by when it differs from the official one (`Casa Primera`, `Biko House`).
  final String? knownAs;
  final List<String> aliases;

  /// `Housing · College Nine` or `Housing · Stevenson College · Casa Primera`.
  String get subtitle => ['Housing', area, ?knownAs].join(' · ');

  factory Housing.fromJson(Map<String, dynamic> json) => Housing(
    id: json['id'] as String,
    name: json['name'] as String,
    area: json['area'] as String,
    point: GeoPoint(
      (json['lat'] as num).toDouble(),
      (json['lon'] as num).toDouble(),
    ),
    short: json['short'] as String?,
    knownAs: json['known_as'] as String?,
    aliases: [
      for (final a in json['aliases'] as List? ?? const []) a as String,
    ],
  );
}

List<Housing> housingFromJson(String text) => [
  for (final b
      in (jsonDecode(text) as Map<String, dynamic>)['buildings'] as List)
    Housing.fromJson(b as Map<String, dynamic>),
];

/// Finds where someone lives from how they say it: "c9 apt 2", "galileo", "casa primera".
class HousingIndex {
  HousingIndex(this.all)
    : _names = [
        for (final h in all)
          [
            for (final n in {h.name, ...h.aliases})
              if (normalize(n).isNotEmpty) normalize(n).split(' '),
          ],
      ] {
    _words = [
      for (final names in _names) {for (final n in names) ...n},
    ];
  }

  final List<Housing> all;
  final List<List<List<String>>> _names;

  /// Every word of every name a building goes by, so "merrill dubois" finds Merrill's DuBois building.
  late final List<Set<String>> _words;

  Housing? byId(String? id) {
    if (id == null) return null;
    for (final h in all) {
      if (h.id == id) return h;
    }
    return null;
  }

  /// Matches best first, each with a score on the same 0 to 1 scale as [Campus.search].
  List<(Housing, double)> search(String query, [int limit = 6]) {
    final q = normalize(query);
    if (q.isEmpty) return const [];
    final words = q.split(' ');
    final found = <(Housing, double)>[];
    for (var i = 0; i < all.length; i++) {
      var best = 0.0;
      for (final name in _names[i]) {
        final s = _score(words, name);
        if (s > best) best = s;
      }
      if (best < 0.65 &&
          words.every((w) => _words[i].any((n) => n == w || n.startsWith(w)))) {
        best = 0.65;
      }
      if (best >= 0.6) found.add((all[i], best));
    }
    found.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0
          ? byScore
          : a.$1.name.length.compareTo(b.$1.name.length);
    });
    return found.take(limit).toList();
  }

  static double _score(List<String> q, List<String> name) {
    if (q.length == name.length && _prefixOf(q, name, exact: true)) return 1;
    if (q.length <= name.length && _prefixOf(q, name, exact: false)) {
      return 0.9 - 0.03 * (name.length - q.length);
    }
    final every = q.every((w) => name.any((n) => n == w || n.startsWith(w)));
    return every ? 0.7 : 0;
  }

  /// Whether [q] starts [name] word by word, the last word possibly cut short.
  static bool _prefixOf(
    List<String> q,
    List<String> name, {
    required bool exact,
  }) {
    for (var i = 0; i < q.length; i++) {
      final last = i == q.length - 1;
      if (q[i] == name[i]) continue;
      if (!exact && last && name[i].startsWith(q[i])) continue;
      return false;
    }
    return true;
  }
}
