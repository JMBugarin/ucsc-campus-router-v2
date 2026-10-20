import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../location/location_service.dart';
import '../settings/settings.dart';

/// A place a student can arrive at campus: a bus stop or a parking area.
class EntryPoint {
  const EntryPoint({
    required this.id,
    required this.name,
    required this.type,
    required this.point,
  });

  final String id;
  final String name;

  /// `bus_stop` or `parking`.
  final String type;
  final GeoPoint point;

  bool get isBusStop => type == 'bus_stop';
}

/// The walk from an [EntryPoint] to a room, on campus paths only.
class EntryWalk {
  const EntryWalk({
    required this.entry,
    required this.minutes,
    required this.meters,
  });

  final EntryPoint entry;
  final int minutes;
  final double meters;

  factory EntryWalk.fromJson(Map<String, dynamic> json) => EntryWalk(
    entry: EntryPoint(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      point: GeoPoint(
        (json['lat'] as num).toDouble(),
        (json['lon'] as num).toDouble(),
      ),
    ),
    minutes: (json['minutes'] as num).toInt(),
    meters: (json['walk_m'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'id': entry.id,
    'name': entry.name,
    'type': entry.type,
    'lat': entry.point.lat,
    'lon': entry.point.lon,
    'minutes': minutes,
    'walk_m': meters,
  };
}

/// Every entry point's walk to one room, shortest first.
class EntryWalks {
  const EntryWalks({required this.buildingName, required this.walks});

  final String buildingName;
  final List<EntryWalk> walks;

  static const none = EntryWalks(buildingName: '', walks: []);

  factory EntryWalks.fromJson(Map<String, dynamic> json) {
    final room = json['room'];
    return EntryWalks(
      buildingName: room is Map<String, dynamic>
          ? (room['building_name'] as String? ?? '')
          : '',
      walks: [
        for (final w in (json['entry_points'] as List))
          EntryWalk.fromJson(w as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'room': {'building_name': buildingName},
    'entry_points': [for (final w in walks) w.toJson()],
  };
}

/// The server cannot plan trips from entry points: it predates the feature, or has no entry points.
class EntryWalksUnavailable implements Exception {
  const EntryWalksUnavailable();

  String get message =>
      "This server can't plan a trip to campus yet. Walking directions on campus still work.";
}

abstract class EntryWalksRepository {
  Future<EntryWalks> to(String room);
}

class ApiEntryWalksRepository implements EntryWalksRepository {
  ApiEntryWalksRepository(this._api);

  final ApiClient _api;

  @override
  Future<EntryWalks> to(String room) async {
    final Map<String, dynamic> json;
    try {
      json = await _api.getJson('/api/entry_walks', query: {'room': room});
    } on ApiException catch (error) {
      if (error.statusCode == 404) throw const EntryWalksUnavailable();
      rethrow;
    }
    final EntryWalks walks;
    try {
      walks = EntryWalks.fromJson(json);
    } on Object {
      throw const EntryWalksUnavailable();
    }
    if (walks.walks.isEmpty) throw const EntryWalksUnavailable();
    return walks;
  }
}

final entryWalksRepositoryProvider = Provider<EntryWalksRepository>(
  (ref) => ApiEntryWalksRepository(ref.watch(apiClientProvider)),
);

/// The last answer for each room, kept on the phone so a trip can still be planned without a network.
class EntryWalksCache {
  EntryWalksCache(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'entry_walks_v1';
  static const _rooms = 40;

  Map<String, dynamic> _load() {
    try {
      final raw = _prefs.getString(_key);
      return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      return {};
    }
  }

  EntryWalks? of(String room) {
    try {
      final saved = _load()[room];
      return saved is Map<String, dynamic> ? EntryWalks.fromJson(saved) : null;
    } on Object {
      return null;
    }
  }

  Future<void> remember(String room, EntryWalks walks) {
    final all = _load()..remove(room);
    all[room] = walks.toJson();
    while (all.length > _rooms) {
      all.remove(all.keys.first);
    }
    return _prefs.setString(_key, jsonEncode(all));
  }
}

final entryWalksCacheProvider = Provider<EntryWalksCache>(
  (ref) => EntryWalksCache(ref.watch(sharedPreferencesProvider)),
);

/// Entry-point walks for a room: from the server, or from the phone's memory when the server cannot be reached.
class EntryWalksService {
  EntryWalksService(this._repository, this._cache, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final EntryWalksRepository _repository;
  final EntryWalksCache _cache;
  final DateTime Function() _clock;
  final _recent = <String, ({EntryWalks walks, DateTime at})>{};

  /// Walks from the campus entrances do not change while the app is open, so Today's minute-by-minute
  /// refresh does not ask the server again for a room it asked about a moment ago.
  static const recentFor = Duration(minutes: 30);

  Future<EntryWalks> forRoom(String room) async {
    final recent = _recent[room];
    if (recent != null && _clock().difference(recent.at) < recentFor) return recent.walks;
    try {
      final walks = await _repository.to(room);
      _recent[room] = (walks: walks, at: _clock());
      await _cache.remember(room, walks);
      return walks;
    } on ApiException catch (error) {
      final unreachable =
          error.kind == ApiErrorKind.offline ||
          error.kind == ApiErrorKind.timeout ||
          error.kind == ApiErrorKind.server;
      final saved = unreachable ? _cache.of(room) : null;
      if (saved == null) rethrow;
      return saved;
    }
  }
}

final entryWalksServiceProvider = Provider<EntryWalksService>(
  (ref) => EntryWalksService(
    ref.watch(entryWalksRepositoryProvider),
    ref.watch(entryWalksCacheProvider),
  ),
);

/// The entry point the student last picked, remembered on this phone only.
class EntryChoice extends Notifier<String?> {
  static const _key = 'entry_point_choice';

  @override
  String? build() => ref.watch(sharedPreferencesProvider).getString(_key);

  Future<void> choose(String id) async {
    state = id;
    await ref.read(sharedPreferencesProvider).setString(_key, id);
  }
}

final entryChoiceProvider = NotifierProvider<EntryChoice, String?>(
  EntryChoice.new,
);
