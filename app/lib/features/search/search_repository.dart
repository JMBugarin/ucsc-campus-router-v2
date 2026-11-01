import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../campus/campus.dart';
import '../../campus/campus_data.dart';
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
  LocalSearchRepository(this._campus);

  final Future<Campus> Function() _campus;

  @override
  Future<List<Place>> search(String query) async => [
    for (final hit in (await _campus()).search(query, 6)) Place.fromHit(hit),
  ];

  @override
  Future<RoomResolution> resolve(String location) async {
    final r = (await _campus()).resolve(location);
    return RoomResolution(kind: r.kind, roomKnown: r.roomKnown);
  }
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => LocalSearchRepository(() => ref.read(campusProvider.future)),
);

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<Place>, String>(
      (ref, query) => ref.read(searchRepositoryProvider).search(query),
    );
