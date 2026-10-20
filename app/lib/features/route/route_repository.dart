import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../arrive/arrival.dart';
import '../arrive/entry_walks.dart';
import '../campus/campus_area.dart';
import '../location/location_service.dart';
import '../settings/settings.dart';
import 'destination.dart';
import 'route_plan.dart';

abstract class RouteRepository {
  Future<RoutePlan> to({required GeoPoint from, required Destination destination});
}

class ApiRouteRepository implements RouteRepository {
  ApiRouteRepository(this._api);

  final ApiClient _api;

  @override
  Future<RoutePlan> to({required GeoPoint from, required Destination destination}) async {
    // One path, no list of explored nodes: the phone only draws the route.
    final json = await _api.getJson('/api/route_to', query: {
      'start': '${from.lat},${from.lon}',
      ...destination.query,
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

/// The walk to show for a [Destination]. A student who is not on campus gets the walk from the entry
/// point they will arrive at ([entry]), with the other choices in [options] (the best guess first).
class RouteOutcome {
  const RouteOutcome(this.plan, {this.entry, this.options = const [], this.place, this.locationProblem});

  final RoutePlan plan;
  final EntryPoint? entry;
  final List<EntryWalk> options;
  final Whereabouts? place;

  /// Why the phone's location could not be used, when the walk starts at an entry point for that reason.
  final String? locationProblem;

  bool get offCampus => entry != null;
}

/// The walk to a [Destination]: from the phone's location when it is on campus, otherwise from the entry
/// point the student will arrive at. Where the student is never goes to the server unless it is on campus.
final routeProvider = FutureProvider.autoDispose.family<RouteOutcome, Destination>((ref, destination) async {
  // The student asked for this route, so the phone is asked for its location even if the
  // "use my location" setting (for Today) is off.
  final here = await ref.read(locationServiceProvider).current();
  final point = here.point;
  final place = point == null ? null : whereIs(point);
  if (point != null && place == Whereabouts.onCampus) {
    return RouteOutcome(await ref.read(routeRepositoryProvider).to(from: point, destination: destination), place: place);
  }
  if (destination is! RoomDestination) {
    throw RouteProblem(
      point == null
          ? (here.problem ?? 'Could not find where you are.')
          : "You're not on campus. Search for a room or building to plan how to get there.",
    );
  }

  final walks = await ref.read(entryWalksServiceProvider).forRoom(destination.location);
  final options = orderEntries(walks.walks, point);
  final entry = chooseEntry(options, ref.watch(entryChoiceProvider)).entry;
  final plan = await ref.read(routeRepositoryProvider).to(from: entry.point, destination: destination);
  return RouteOutcome(plan, entry: entry, options: options, place: place, locationProblem: here.problem);
});
