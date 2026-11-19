import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../campus/campus.dart';
import '../../campus/campus_data.dart';
import '../../campus/housing.dart';
import 'place.dart';

/// What the campus data makes of a schedule-style location such as `Kresge Acad 3201`.
class RoomResolution {
  const RoomResolution({required this.kind, this.roomKnown});

  /// `building`, `online`, `tba` or `unknown`.
  final String kind;

  /// False when the building lists its rooms and this one is not among them.
  final bool? roomKnown;
}

abstract class SearchRepository {
  /// Buildings and rooms matching something a person typed, best first.
  Future<List<Place>> search(String query);

  /// Whether this location can be placed on the campus map.
  Future<RoomResolution> resolve(String location);
}

/// Searches the campus data bundled with the app, so it works with no connection.
class LocalSearchRepository implements SearchRepository {
  LocalSearchRepository(this._campus, [this._housing]);

  final Future<Campus> Function() _campus;
  final Future<HousingIndex> Function()? _housing;

  /// Buildings, rooms, dorms and apartments, best first. A dorm counts for a little less, so "crown" opens
  /// Crown's classroom building and "crown galileo" or "c9 apt 2" opens the dorm.
  @override
  Future<List<Place>> search(String query) async {
    final ranked = <(Place, double)>[
      for (final hit in (await _campus()).search(query, 6))
        (Place.fromHit(hit), hit.score),
      if (_housing != null)
        for (final (h, score) in (await _housing()).search(query, 6))
          (Place.fromHousing(h), score * 0.9),
    ];
    final order = [for (var i = 0; i < ranked.length; i++) i]
      ..sort((a, b) {
        final byScore = ranked[b].$2.compareTo(ranked[a].$2);
        return byScore != 0 ? byScore : a.compareTo(b);
      });
    return [for (final i in order.take(6)) ranked[i].$1];
  }

  @override
  Future<RoomResolution> resolve(String location) async {
    final r = (await _campus()).resolve(location);
    return RoomResolution(kind: r.kind, roomKnown: r.roomKnown);
  }
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => LocalSearchRepository(
    () => ref.read(campusProvider.future),
    () => ref.read(housingProvider.future),
  ),
);

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<Place>, String>(
      (ref, query) => ref.read(searchRepositoryProvider).search(query),
    );
