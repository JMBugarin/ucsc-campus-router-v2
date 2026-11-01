import 'geo_point.dart';
import 'sequence_matcher.dart';

const _online = {
  'online',
  'remote',
  'remote instruction',
  'zoom',
  'asynchronous',
  'async',
  'web',
  'online asynchronous',
  'online synchronous',
};
const _tba = {'', 'tba', 'tbd', 'to be announced', 'no room', 'none'};
const _roomWords = {'room', 'rm'};
const _minSearchScore = 0.5;

String normalize(String text) => text
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(RegExp('[^a-z0-9]+'), ' ')
    .trim();

List<String> _words(String normalized) =>
    normalized.isEmpty ? const [] : normalized.split(' ');

bool _hasDigit(String s) => RegExp('[0-9]').hasMatch(s);

/// A door into a building. `kind` is `main` for the one OpenStreetMap marks as the main entrance.
class Entrance {
  const Entrance(this.point, this.kind);

  final GeoPoint point;
  final String kind;
}

class RoomPoint {
  const RoomPoint(this.lat, this.lon, this.level);

  final double lat;
  final double lon;
  final String? level;

  GeoPoint get point => GeoPoint(lat, lon);
}

class Building {
  Building({
    required this.id,
    required this.name,
    this.osmName,
    this.aliases = const [],
    this.exactNames = const {},
    this.knownRooms = const [],
    this.roomPoints = const {},
    this.centroid,
    this.entrances = const [],
  });

  final String id;
  final String name;
  final String? osmName;
  final List<String> aliases;

  /// Official names the classroom directory prints with no room, mapped to the room.
  final Map<String, String> exactNames;
  final List<String> knownRooms;
  final Map<String, RoomPoint> roomPoints;
  final GeoPoint? centroid;
  final List<Entrance> entrances;

  factory Building.fromJson(Map<String, dynamic> json) {
    GeoPoint? point(Object? v) => v is Map
        ? GeoPoint((v['lat'] as num).toDouble(), (v['lon'] as num).toDouble())
        : null;
    return Building(
      id: json['id'] as String,
      name: json['name'] as String,
      osmName: json['osm_name'] as String?,
      aliases: [
        for (final a in (json['aliases'] as List? ?? const [])) a as String,
      ],
      exactNames: {
        for (final e in ((json['exact_names'] as Map?) ?? const {}).entries)
          e.key as String: e.value as String,
      },
      knownRooms: [
        for (final r in (json['known_rooms'] as List? ?? const [])) r as String,
      ],
      roomPoints: {
        for (final e in ((json['room_points'] as Map?) ?? const {}).entries)
          e.key as String: RoomPoint(
            ((e.value as Map)['lat'] as num).toDouble(),
            ((e.value as Map)['lon'] as num).toDouble(),
            (e.value as Map)['level'] as String?,
          ),
      },
      centroid: point(json['centroid']),
      entrances: [
        for (final e in (json['entrances'] as List? ?? const []))
          Entrance(point(e)!, ((e as Map)['kind'] as String?) ?? ''),
      ],
    );
  }
}

/// What a schedule-style location string turned out to be.
class Resolution {
  const Resolution(
    this.raw,
    this.kind, {
    this.buildingId,
    this.room,
    this.entrances = const [],
    this.floor,
    this.note,
    this.roomKnown,
    this.roomPoint,
  });

  final String raw;

  /// `building`, `online`, `tba` or `unknown`.
  final String kind;
  final String? buildingId;
  final String? room;
  final List<Entrance> entrances;
  final String? floor;
  final String? note;

  /// True or false if the building's room list is known, else null.
  final bool? roomKnown;
  final RoomPoint? roomPoint;
}

/// One answer to a typed search: a building, or a room inside one.
class SearchHit {
  const SearchHit({
    required this.buildingId,
    required this.buildingName,
    required this.label,
    required this.query,
    required this.score,
    this.room,
    this.roomKnown,
    this.floor,
    this.point,
  });

  final String buildingId;
  final String buildingName;
  final String label;

  /// A schedule-style string that [Campus.resolve] maps back to this hit.
  final String query;
  final double score;
  final String? room;
  final bool? roomKnown;
  final String? floor;
  final GeoPoint? point;
}

bool _oneEditApart(String a, String b) {
  if (a == b || (a.length - b.length).abs() > 1) return false;
  if (a.length == b.length) {
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) diff++;
    }
    return diff == 1;
  }
  final short = a.length < b.length ? a : b;
  final long = a.length < b.length ? b : a;
  for (var i = 0; i < long.length; i++) {
    if (long.substring(0, i) + long.substring(i + 1) == short) return true;
  }
  return false;
}

/// The campus: building and room names, and where each one is.
class Campus {
  Campus(
    List<Building> buildings, {
    this.overrides = const {},
    Map<String, List<String>> searchAliases = const {},
  }) {
    for (final b in buildings) {
      if (this.buildings.containsKey(b.id)) {
        throw StateError('duplicate building id ${b.id}');
      }
      this.buildings[b.id] = b;
    }
    for (final b in buildings) {
      final names = <String>{};
      for (final a in [
        b.name,
        b.osmName ?? '',
        ...b.aliases,
        ...(searchAliases[b.id] ?? const <String>[]),
      ]) {
        final n = normalize(a);
        if (n.isNotEmpty) names.add(n);
      }
      _searchNames[b.id] = [for (final n in names) _words(n)];
      b.exactNames.forEach(
        (name, room) => _exact[normalize(name)] = (b.id, room),
      );
      for (final alias in [b.name, b.osmName ?? '', ...b.aliases]) {
        final key = normalize(alias);
        if (key.isEmpty) continue;
        final owner = _index.putIfAbsent(key, () => b.id);
        if (owner != b.id) {
          throw StateError('alias "$alias" belongs to both $owner and ${b.id}');
        }
      }
    }
  }

  final Map<String, Building> buildings = {};
  final Map<String, dynamic> overrides;
  final Map<String, List<List<String>>> _searchNames = {};
  final Map<String, String> _index = {};
  final Map<String, (String, String)> _exact = {};

  /// Splits a location followed by other words (a schedule row's room and instructor).
  (String, String) splitLocation(String text) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final norm = [for (final w in words) normalize(w)];

    String phrase(int k) => norm.take(k).where((n) => n.isNotEmpty).join(' ');
    (String, String) cut(int k) =>
        (words.take(k).join(' '), words.skip(k).join(' '));

    for (var k = 1; k <= (words.length < 3 ? words.length : 3); k++) {
      final p = phrase(k);
      if (_online.contains(p) || (_tba.contains(p) && p.isNotEmpty)) {
        return cut(k);
      }
    }
    for (var k = words.length; k > 0; k--) {
      if (_exact.containsKey(phrase(k))) return cut(k);
    }
    var aliasLen = 0;
    for (var k = words.length; k > 0; k--) {
      if (_index.containsKey(phrase(k))) {
        aliasLen = k;
        break;
      }
    }
    for (var j = aliasLen; j < words.length; j++) {
      if (_hasDigit(words[j])) return cut(j + 1);
    }
    return (text, '');
  }

  Resolution resolve(String? location) {
    final text = normalize(location ?? '');
    final raw = location ?? '';
    if (_tba.contains(text)) return Resolution(raw, 'tba');
    if (_online.contains(text) ||
        text.startsWith('online ') ||
        text.startsWith('remote ')) {
      return Resolution(raw, 'online');
    }
    final exact = _exact[text];
    if (exact != null) {
      return _building(raw, exact.$1, [exact.$2.toLowerCase()]);
    }

    final tokens = _words(text);
    for (var k = tokens.length; k > 0; k--) {
      final id = _index[tokens.take(k).join(' ')];
      if (id != null) return _building(raw, id, tokens.skip(k).toList());
    }
    return Resolution(raw, 'unknown');
  }

  Resolution _building(String raw, String buildingId, List<String> rest) {
    final words = rest.isNotEmpty && _roomWords.contains(rest.first)
        ? rest.skip(1).toList()
        : rest;
    final joined = words.join(' ').toUpperCase();
    final room = joined.isEmpty ? null : joined;
    final building = buildings[buildingId]!;
    var entrances = List<Entrance>.of(building.entrances);
    String? floor, note;
    final override = room == null
        ? null
        : (overrides['$buildingId:$room'] as Map?);
    if (override != null) {
      final e = override['entrance'];
      if (e is Map) {
        entrances = [
          Entrance(
            GeoPoint(
              (e['lat'] as num).toDouble(),
              (e['lon'] as num).toDouble(),
            ),
            'override',
          ),
        ];
      }
      floor = override['floor'] as String?;
      note = override['note'] as String?;
    }
    final known = building.knownRooms;
    final roomKnown = known.isNotEmpty && room != null
        ? known.contains(room)
        : null;
    final roomPoint = room == null ? null : building.roomPoints[room];
    floor ??= roomPoint?.level;
    return Resolution(
      raw,
      'building',
      buildingId: buildingId,
      room: room,
      entrances: entrances,
      floor: floor,
      note: note,
      roomKnown: roomKnown,
      roomPoint: roomPoint,
    );
  }

  /// Ranks buildings and rooms for a typed query such as "BE 152", "kresge 3201" or "Thimann 101".
  List<SearchHit> search(String? query, [int limit = 5]) {
    var tokens = _words(normalize(query ?? ''));
    if (tokens.length > 1 && _roomWords.contains(tokens.first)) {
      tokens = tokens.skip(1).toList();
    }
    if (tokens.isEmpty) return const [];
    final found = <(String, String?), (double, String?)>{};

    void offer(String buildingId, String? room, double score) {
      final key = (buildingId, room);
      final have = found[key]?.$1 ?? 0;
      if (score >= _minSearchScore && have < score) found[key] = (score, null);
    }

    for (var k = 1; k <= tokens.length; k++) {
      final roomTokens = tokens.skip(k).toList();
      if (roomTokens.length > 1 ||
          (roomTokens.isNotEmpty && !_hasDigit(roomTokens.first))) {
        continue;
      }
      final room = roomTokens.isEmpty ? null : roomTokens.first.toUpperCase();
      _matchNames(tokens.take(k).toList()).forEach((buildingId, nameScore) {
        final known = buildings[buildingId]!.knownRooms;
        if (room == null) {
          offer(buildingId, null, nameScore);
        } else if (known.contains(room)) {
          offer(buildingId, room, nameScore + 0.1 > 1 ? 1 : nameScore + 0.1);
        } else {
          offer(buildingId, room, nameScore * (known.isNotEmpty ? 0.9 : 0.95));
          for (final fixed in known.where((r) => _oneEditApart(r, room))) {
            offer(buildingId, fixed, nameScore * 0.95);
          }
        }
      });
    }
    if (found.isEmpty && tokens.length == 1 && _hasDigit(tokens.first)) {
      final room = tokens.first.toUpperCase();
      buildings.forEach((id, b) {
        if (b.knownRooms.contains(room)) offer(id, room, 0.6);
      });
    }

    // A room the directory lists beats guesses at the same number in buildings with no room list.
    bool listed(String b, String? r) =>
        r != null && buildings[b]!.knownRooms.contains(r);
    if (found.keys.any((k) => listed(k.$1, k.$2))) {
      found.removeWhere(
        (k, _) =>
            k.$2 != null &&
            !listed(k.$1, k.$2) &&
            buildings[k.$1]!.knownRooms.isEmpty,
      );
    }

    final ranked = found.entries.toList()
      ..sort((x, y) {
        final byScore = y.value.$1.compareTo(x.value.$1);
        if (byScore != 0) return byScore;
        final byName = buildings[x.key.$1]!.name.compareTo(
          buildings[y.key.$1]!.name,
        );
        return byName != 0
            ? byName
            : (x.key.$2 ?? '').compareTo(y.key.$2 ?? '');
      });
    return [
      for (final e in ranked.take(limit)) _hit(e.key.$1, e.key.$2, e.value.$1),
    ];
  }

  Map<String, double> _matchNames(List<String> nameTokens) {
    final scores = <String, double>{};
    final n = nameTokens.length;
    final joined = nameTokens.join(' ');
    _searchNames.forEach((buildingId, names) {
      for (final alias in names) {
        var score = 0.0;
        if (alias.length == n && _sameTokens(alias, nameTokens)) {
          score = 1;
        } else if (n < alias.length && _prefixTokens(nameTokens, alias)) {
          score = 0.9 - 0.03 * (alias.length - n);
        } else if (alias.length >= n) {
          final head = alias.take(n).toList();
          var digitsAgree = true;
          for (var i = 0; i < n; i++) {
            if (_hasDigit(nameTokens[i] + head[i]) &&
                nameTokens[i] != head[i]) {
              digitsAgree = false;
            }
          }
          if (digitsAgree) {
            final ratio = similarity(joined, head.join(' '));
            if (ratio >= 0.8) score = 0.8 * ratio;
          }
        }
        if (score > (scores[buildingId] ?? 0)) scores[buildingId] = score;
      }
    });
    return scores;
  }

  bool _sameTokens(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _prefixTokens(List<String> typed, List<String> alias) {
    for (var i = 0; i < typed.length; i++) {
      if (typed[i] != alias[i] &&
          !(typed[i].length >= 3 && alias[i].startsWith(typed[i]))) {
        return false;
      }
    }
    return true;
  }

  SearchHit _hit(String buildingId, String? room, double score) {
    final building = buildings[buildingId]!;
    final known = building.knownRooms;
    final point = room == null ? null : building.roomPoints[room];
    final spot = point?.point ?? building.centroid;
    String? query = room == null ? building.name : null;
    if (room != null) {
      for (final alias in [building.name, ...building.aliases]) {
        final text = '$alias $room';
        final resolved = resolve(text);
        if (resolved.buildingId == buildingId && resolved.room == room) {
          query = text;
          break;
        }
      }
    }
    return SearchHit(
      buildingId: buildingId,
      buildingName: building.name,
      room: room,
      roomKnown: known.isNotEmpty && room != null ? known.contains(room) : null,
      floor: point?.level,
      point: spot,
      query: query ?? building.name,
      label: room == null ? building.name : '${building.name} $room',
      score: score,
    );
  }
}
