import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../location/location_service.dart';
import '../settings/settings.dart';
import 'route_plan.dart';

abstract class RouteRepository {
  Future<RoutePlan> toRoom({required GeoPoint from, required String room});
}

class ApiRouteRepository implements RouteRepository {
  ApiRouteRepository(this._api);

  final ApiClient _api;

  @override
  Future<RoutePlan> toRoom({required GeoPoint from, required String room}) async {
    // One path, no list of explored nodes: the phone only draws the route.
    final json = await _api.getJson('/api/route_to_room', query: {
      'start': '${from.lat},${from.lon}',
      'room': room,
      'algo': 'astar',
      'explored': '0',
    });
    try {
      return RoutePlan.fromJson(json, start: from);
    } on Object {
      throw const ApiException('The server could not find a walking route there.', kind: ApiErrorKind.rejected);
    }
  }
}

final routeRepositoryProvider = Provider<RouteRepository>((ref) => ApiRouteRepository(ref.watch(apiClientProvider)));

/// Why a route could not be drawn even before asking the server.
class RouteProblem implements Exception {
  const RouteProblem(this.message);

  final String message;
}

/// The walk from the phone's location to [room] (a schedule location such as "Kresge Acad 3201").
final routeProvider = FutureProvider.autoDispose.family<RoutePlan, String>((ref, room) async {
  // The student asked for this route, so the phone is asked for its location even if the
  // "use my location" setting (for Today) is off.
  final here = await ref.read(locationServiceProvider).current();
  final point = here.point;
  if (point == null) throw RouteProblem(here.problem ?? 'Could not find where you are.');
  return ref.read(routeRepositoryProvider).toRoom(from: point, room: room);
});
