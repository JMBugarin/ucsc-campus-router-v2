import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/tiles.dart';
import '../../core/waking_note.dart';
import '../../design/map_markers.dart';
import '../../design/tokens.dart';
import '../arrive/entry_walks.dart';
import '../campus/campus_area.dart';
import '../handoff/trip_actions.dart';
import '../location/location_service.dart';
import 'destination.dart';
import 'route_plan.dart';
import 'route_repository.dart';

LatLng _latLng(GeoPoint p) => LatLng(p.lat, p.lon);

/// Opens the map for the walk to [destination].
void openRoute(BuildContext context, {required Destination destination}) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RouteScreen(destination: destination)));
}

class RouteScreen extends ConsumerWidget {
  const RouteScreen({super.key, required this.destination});

  final Destination destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeProvider(destination));
    return Scaffold(
      appBar: AppBar(
        title: Text(destination.label),
        actions: [
          IconButton(
            tooltip: 'Find the route again',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(routeProvider(destination)),
          ),
        ],
      ),
      body: route.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Finding your route…'),
              Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: WakingNote()),
            ],
          ),
        ),
        error: (error, _) => _Problem(
          message: switch (error) {
            ApiException(:final message) => message,
            EntryWalksUnavailable(:final message) => message,
            RouteProblem(:final message) => message,
            _ => 'Something went wrong. Try again.',
          },
          onRetry: () => ref.invalidate(routeProvider(destination)),
          onSearch: error is ApiException && error.kind == ApiErrorKind.rejected || error is RouteProblem
              ? () {
                  ref.read(selectedTabProvider.notifier).select(tabMap);
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              : null,
        ),
        data: (outcome) => _RouteView(outcome: outcome, destination: destination),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry, this.onSearch});

  final String message;
  final VoidCallback onRetry;

  /// Offered when a different search might help (the room is not recognised, or the place is not a room).
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wrong_location_outlined, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
            if (onSearch != null) TextButton(onPressed: onSearch, child: const Text('Search the map instead')),
          ],
        ),
      ),
    );
  }
}

/// The walk drawn on the map: the route on a casing so it reads on any tile, the start (you, or the entry
/// point) and the door.
class RouteMap extends StatelessWidget {
  const RouteMap({super.key, required this.plan, this.entry, this.fitPadding = const EdgeInsets.all(48)});

  final RoutePlan plan;
  final EntryPoint? entry;
  final EdgeInsets fitPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final points = [for (final p in plan.path) _latLng(p)];
    final bounds = LatLngBounds.fromPoints([_latLng(plan.start), ...points, _latLng(plan.door)]);
    final tiny = bounds.north == bounds.south && bounds.east == bounds.west;
    return FlutterMap(
      options: MapOptions(
        initialCenter: bounds.center,
        initialZoom: 17,
        initialCameraFit: tiny ? null : CameraFit.bounds(bounds: bounds, padding: fitPadding),
      ),
      children: [
        const BaseMapLayer(),
        PolylineLayer(
          polylines: [
            // The two short joins between the real start/door and the nearest path points.
            if (points.isNotEmpty) ...[
              Polyline(
                points: [_latLng(plan.start), points.first],
                strokeWidth: 3,
                color: c.labelSecondary,
                pattern: const StrokePattern.dotted(),
              ),
              Polyline(
                points: [points.last, _latLng(plan.door)],
                strokeWidth: 3,
                color: c.labelSecondary,
                pattern: const StrokePattern.dotted(),
              ),
            ],
            Polyline(points: points, strokeWidth: 10, color: c.surfaceContent),
            Polyline(points: points, strokeWidth: 5, color: c.accentFill),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _latLng(plan.start),
              width: entry == null ? 22 : 40,
              height: entry == null ? 22 : 40,
              child: entry == null ? const UserDot() : EntryMarker(name: entry!.name),
            ),
            Marker(
              point: _latLng(plan.door),
              width: 40,
              height: 40,
              alignment: Alignment.topCenter,
              child: const DestinationPin(label: 'Door'),
            ),
          ],
        ),
        const MapAttribution(),
      ],
    );
  }
}

class _RouteView extends ConsumerWidget {
  const _RouteView({required this.outcome, required this.destination});

  final RouteOutcome outcome;
  final Destination destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // At large text sizes the summary can outgrow the screen: it takes at most half the height and scrolls.
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          Expanded(child: RouteMap(plan: outcome.plan, entry: outcome.entry)),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * 0.5),
            child: SingleChildScrollView(child: _Summary(outcome: outcome, destination: destination)),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.outcome, required this.destination});

  final RouteOutcome outcome;
  final Destination destination;

  RoutePlan get plan => outcome.plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final where = [
      if (plan.buildingName.isNotEmpty) plan.buildingName,
      if (plan.room.isNotEmpty) 'room ${plan.room}',
      if (plan.floor != null) 'floor ${plan.floor}',
    ].join(', ');
    final inside = plan.indoorM >= 1 ? ' plus about ${plan.indoorM.round()} m from the door to the room' : '';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (outcome.entry != null) ...[
              Text(
                switch (outcome.place) {
                  Whereabouts.far => "You're far from campus",
                  Whereabouts.offCampus => "You're not on campus yet",
                  _ => "Your location isn't available",
                },
                style: theme.textTheme.labelLarge,
              ),
              Text('This walk starts at ${outcome.entry!.name}.', style: theme.textTheme.titleMedium),
              if (outcome.locationProblem != null) Text(outcome.locationProblem!, style: theme.textTheme.bodySmall),
              TripActions(
                entry: outcome.entry!,
                options: outcome.options,
                roomLabel: destination.label,
                far: outcome.place == Whereabouts.far,
              ),
              const Divider(),
            ],
            Text('About ${plan.minutes} min on foot', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${plan.walkM.round()} m to the door$inside.'),
            if (where.isNotEmpty) Text(where),
            if (plan.note != null) Text(plan.note!),
            const SizedBox(height: 6),
            Text(
              outcome.entry == null
                  ? 'Dotted lines join you and the door to the nearest path points.'
                  : 'Dotted lines join the entry point and the door to the nearest path points.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
