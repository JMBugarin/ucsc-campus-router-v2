import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../settings/settings.dart';
import 'place.dart';

abstract class SearchRepository {
  /// Buildings and rooms matching something a person typed, best first.
  Future<List<Place>> search(String query);
}

class ApiSearchRepository implements SearchRepository {
  ApiSearchRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Place>> search(String query) async {
    final json = await _api.getJson('/api/search', query: {'q': query, 'limit': '6'});
    return [for (final r in (json['results'] as List? ?? const [])) Place.fromJson(r as Map<String, dynamic>)];
  }
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) => ApiSearchRepository(ref.watch(apiClientProvider)));

final searchResultsProvider = FutureProvider.autoDispose.family<List<Place>, String>(
  (ref, query) => ref.read(searchRepositoryProvider).search(query),
);
