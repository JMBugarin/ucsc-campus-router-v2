import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../location/location_service.dart';
import 'route_plan.dart';
import 'route_repository.dart';

/// Whether to draw OpenStreetMap tiles. Tests turn this off so nothing touches the network.
final showMapTilesProvider = Provider<bool>((ref) => true);

LatLng _latLng(GeoPoint p) => LatLng(p.lat, p.lon);

/// Opens the map for the walk to [room].
void openRoute(BuildContext context, {required String room, required String title}) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RouteScreen(room: room, title: title)));
}

class RouteScreen extends ConsumerWidget {
  const RouteScreen({super.key, required this.room, required this.title});

  final String room;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeProvider(room));
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Find the route again',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(routeProvider(room)),
          ),
        ],
      ),
      body: route.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Finding your route…')],
          ),
        ),
        error: (error, _) => _Problem(
          message: switch (error) {
            ApiException(:final message) => message,
            RouteProblem(:final message) => message,
            _ => 'Something went wrong. Try again.',
          },
          onRetry: () => ref.invalidate(routeProvider(room)),
        ),
        data: (plan) => _RouteView(plan: plan),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wrong_location_outlined, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _RouteView extends ConsumerWidget {
  const _RouteView({required this.plan});

  final RoutePlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final points = [for (final p in plan.path) _latLng(p)];
    final bounds = LatLngBounds.fromPoints([_latLng(plan.start), ...points, _latLng(plan.door)]);
    final tiny = bounds.north == bounds.south && bounds.east == bounds.west;

    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: bounds.center,
              initialZoom: 17,
              initialCameraFit: tiny ? null : CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
            ),
            children: [
              if (ref.watch(showMapTilesProvider))
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'io.github.jmbugarin.ucsc_router',
                ),
              PolylineLayer(
                polylines: [
                  // The two short joins between the real start/door and the nearest path points.
                  if (points.isNotEmpty) ...[
                    Polyline(
                      points: [_latLng(plan.start), points.first],
                      strokeWidth: 3,
                      color: scheme.outline,
                      pattern: const StrokePattern.dotted(),
                    ),
                    Polyline(
                      points: [points.last, _latLng(plan.door)],
                      strokeWidth: 3,
                      color: scheme.outline,
                      pattern: const StrokePattern.dotted(),
                    ),
                  ],
                  Polyline(points: points, strokeWidth: 5, color: scheme.primary),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _latLng(plan.start),
                    child: Icon(Icons.my_location, color: Colors.blue.shade800, semanticLabel: 'You are here'),
                  ),
                  Marker(
                    point: _latLng(plan.door),
                    alignment: Alignment.topCenter,
                    child: Icon(Icons.location_on, size: 36, color: Colors.red.shade700, semanticLabel: 'Door'),
                  ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
              ),
            ],
          ),
        ),
        _Summary(plan: plan),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.plan});

  final RoutePlan plan;

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
            Text('About ${plan.minutes} min on foot', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${plan.walkM.round()} m to the door$inside.'),
            if (where.isNotEmpty) Text(where),
            if (plan.note != null) Text(plan.note!),
            const SizedBox(height: 6),
            Text(
              'Dotted lines join you and the door to the nearest path points.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
