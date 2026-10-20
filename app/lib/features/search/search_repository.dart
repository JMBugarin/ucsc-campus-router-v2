import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../settings/settings.dart';
import 'place.dart';

/// What the server makes of a schedule-style location such as `Kresge Acad 3201`, as it does when it works out a walk.
class RoomResolution {
  const RoomResolution({required this.kind, this.roomKnown});

  /// `building`, `online`, `tba` or `unknown`.
  final String kind;

  /// False when the building lists its rooms and this one is not among them.
  final bool? roomKnown;

  factory RoomResolution.fromJson(Map<String, dynamic> json) =>
      RoomResolution(kind: (json['kind'] as String?) ?? 'unknown', roomKnown: json['room_known'] as bool?);
}

abstract class SearchRepository {
  /// Buildings and rooms matching something a person typed, best first.
  Future<List<Place>> search(String query);

  /// Whether the server can place this location, so that a walk to it can be timed.
  Future<RoomResolution> resolve(String location);
}

class ApiSearchRepository implements SearchRepository {
  ApiSearchRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Place>> search(String query) async {
    final json = await _api.getJson('/api/search', query: {'q': query, 'limit': '6'});
    return [for (final r in (json['results'] as List? ?? const [])) Place.fromJson(r as Map<String, dynamic>)];
  }

  @override
  Future<RoomResolution> resolve(String location) async =>
      RoomResolution.fromJson(await _api.getJson('/api/resolve', query: {'q': location}));
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) => ApiSearchRepository(ref.watch(apiClientProvider)));

final searchResultsProvider = FutureProvider.autoDispose.family<List<Place>, String>(
  (ref, query) => ref.read(searchRepositoryProvider).search(query),
);
