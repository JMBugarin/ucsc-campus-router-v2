import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/settings.dart';
import 'today_models.dart';

/// The walk times the server last gave, kept so Today still works with no network.
///
/// Keys read `origin>destination`, where the origin is a class's location or `*` for wherever the
/// student was. A walk to a place from anywhere is also kept as a fallback.
class WalkCache {
  WalkCache(this._prefs, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  static const _key = 'walk_cache_v1';

  Map<String, dynamic> _load() {
    try {
      final raw = _prefs.getString(_key);
      return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      return {};
    }
  }

  Map<String, int> _ints(Object? value) =>
      value is Map ? {for (final e in value.entries) e.key as String: (e.value as num).toInt()} : {};

  /// Whole minutes from [origin] (a class location, or null for the student's own position) to [destination].
  int? minutes(String? origin, String destination) {
    final data = _load();
    final exact = _ints(data['walks'])['${origin ?? '*'}>$destination'];
    if (exact != null || origin != null) return exact;
    return _ints(data['any'])[destination];
  }

  Set<String> get holidays {
    final value = _load()['holidays'];
    return value is List ? {for (final h in value) h as String} : {};
  }

  bool get hasAny => _ints(_load()['walks']).isNotEmpty;

  /// When the server last answered and its walk times were kept; null if never, or saved before this was recorded.
  DateTime? get savedAt {
    final value = _load()['at'];
    return value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
  }

  /// Learns from an answer the server just gave.
  Future<void> remember(Analysis analysis) async {
    final data = _load();
    final walks = _ints(data['walks']);
    final any = _ints(data['any']);

    void put(String? origin, String destination, int minutes) {
      walks['${origin ?? '*'}>$destination'] = minutes;
      any[destination] = minutes;
    }

    final next = analysis.next;
    final walk = analysis.walk;
    if (next != null && walk != null && next.location.isNotEmpty) {
      final origin = switch (walk.from) {
        'current_class' => analysis.current?.location,
        'previous_class' => _lastEndedBefore(analysis, next),
        _ => null,
      };
      if (walk.from == 'here' || (origin != null && origin.isNotEmpty)) put(origin, next.location, walk.minutes);
    }
    for (var i = 1; i < analysis.today.length; i++) {
      final t = analysis.today[i], prev = analysis.today[i - 1];
      if (t.walkMin != null && t.location.isNotEmpty && prev.location.isNotEmpty) {
        walks['${prev.location}>${t.location}'] = t.walkMin!;
        any[t.location] = t.walkMin!;
      }
    }

    final holidays = analysis.holidays.isNotEmpty ? analysis.holidays : this.holidays.toList();
    await _prefs.setString(
      _key,
      jsonEncode({'walks': walks, 'any': any, 'holidays': holidays, 'at': _clock().millisecondsSinceEpoch}),
    );
  }

  String? _lastEndedBefore(Analysis analysis, ClassTime next) {
    String? found;
    for (final t in analysis.today) {
      if (t.start.compareTo(next.start) < 0) found = t.location;
    }
    return found;
  }
}

final walkCacheProvider = Provider<WalkCache>((ref) => WalkCache(ref.watch(sharedPreferencesProvider)));
