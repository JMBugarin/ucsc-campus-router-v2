import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/tiles.dart';
import '../../design/controls.dart';
import '../../design/floating_bar.dart';
import '../../design/glass.dart';
import '../../design/map_markers.dart';
import '../../design/surfaces.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../going/going_to_class_screen.dart';
import '../route/destination.dart';
import '../route/route_screen.dart';
import '../search/place.dart';
import '../search/search_repository.dart';
import '../today/today_controller.dart';

const _campusCenter = LatLng(36.9951, -122.0585);

/// Search for a building or room and see where it is; no schedule needed.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _controller = TextEditingController();
  final _map = MapController();
  Timer? _debounce;
  String _query = '';
  Place? _selected;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _map.dispose();
    super.dispose();
  }

  void _typed(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  void _choose(Place place) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selected = place;
      _query = '';
      _controller.text = place.label;
    });
    final point = place.point;
    if (point != null) _map.move(LatLng(point.lat, point.lon), 18);
  }

  void _clear() {
    _debounce?.cancel();
    setState(() {
      _selected = null;
      _query = '';
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final point = selected?.point;
    final inset = FloatingBarInset.of(context);
    final c = context.colors;
    final today = ref.watch(todayProvider).value;
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: 'Campus map',
          child: FlutterMap(
            mapController: _map,
            options: const MapOptions(initialCenter: _campusCenter, initialZoom: 15),
            children: [
              const BaseMapLayer(),
              if (point != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(point.lat, point.lon),
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: DestinationPin(label: selected!.label),
                    ),
                  ],
                ),
              const MapAttribution(),
            ],
          ),
        ),
        // The clock and battery are white in dark mode and the map is always light, so they get a veil.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.paddingOf(context).top,
          child: ColoredBox(
            key: const ValueKey('statusBarVeil'),
            color: c.bgCanvas.withValues(alpha: 0.85),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassSearchField(controller: _controller, onChanged: _typed, onClear: _clear),
                if (today != null && today.offline) ...[
                  const SizedBox(height: Space.xs),
                  StatusBanner(
                    kind: BannerKind.offline,
                    title: 'Offline',
                    body: "Can't reach the server. Searching and routes need it; Today still works from what is saved on your phone.",
                    actionLabel: 'Try again',
                    onAction: () => ref.read(todayProvider.notifier).refresh(),
                  ),
                ],
                if (_query.isNotEmpty) Flexible(child: _Results(query: _query, onChoose: _choose)),
              ],
            ),
          ),
        ),
        if (selected != null)
          Positioned(left: 0, right: 0, bottom: inset, child: _PlaceCard(place: selected))
        else if (_query.isEmpty && today != null)
          Positioned(left: 0, right: 0, bottom: inset, child: _NextClassCard(data: today)),
      ],
    );
  }
}

/// The next class over the map, one tap from Going to class.
class _NextClassCard extends StatelessWidget {
  const _NextClassCard({required this.data});

  final TodayData data;

  @override
  Widget build(BuildContext context) {
    final analysis = data.analysis;
    final next = analysis?.next;
    if (data.viewDay != null || analysis == null || next == null || !next.isToday) return const SizedBox.shrink();
    final c = context.colors;
    final trip = data.offCampus ? data.arrivals.where((a) => a.classTime.start == next.start).firstOrNull : null;
    final walk = analysis.walk;
    final detail = trip != null
        ? trip.headline
        : walk == null
            ? 'At ${clockFromIso(next.start)}'
            : data.fromSaved
                ? 'Saved walk time: about ${walk.minutes} min'
                : analysis.leaveBy == null
                    ? '${walk.minutes} min walk'
                    : 'Leave by ${clockFromIso(analysis.leaveBy!)} · ${walk.minutes} min walk';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
      child: Semantics(
        button: true,
        label: 'Next: ${next.label}. $detail. Opens Going to class.',
        excludeSemantics: true,
        child: GlassSurface(
          padding: EdgeInsets.zero,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => openGoingToClass(context),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: c.accentTint),
                        child: SizedBox.square(
                          dimension: 44,
                          child: Icon(trip != null ? Icons.directions_bus_outlined : Icons.directions_walk, color: c.accentText),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Next: ${next.label}', style: AppText.headline.copyWith(color: c.labelPrimary)),
                            Text(detail, style: AppText.subhead.copyWith(color: c.labelSecondary)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: c.labelSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.onChoose});

  final String query;
  final ValueChanged<Place> onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final results = ref.watch(searchResultsProvider(query));
    Widget solid(Widget child) => Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surfaceContent,
              borderRadius: BorderRadius.circular(Radii.xl),
              border: Border.all(color: c.separator),
              boxShadow: Elevation.raised,
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(Radii.xl), child: SingleChildScrollView(child: child)),
          ),
        );
    return results.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: Space.xs),
        child: WakingCard(glass: true, after: Duration(seconds: 4)),
      ),
      error: (error, _) => solid(
        Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(error is ApiException ? error.message : 'Search failed. Try again.', style: AppText.body.copyWith(color: c.labelPrimary)),
              TextButton(onPressed: () => ref.invalidate(searchResultsProvider(query)), child: const Text('Try again')),
            ],
          ),
        ),
      ),
      data: (places) => solid(
        places.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Text(
                  'No match. Try the building name and room, like "Kresge 3201".',
                  style: AppText.body.copyWith(color: c.labelPrimary),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, p) in places.indexed) ...[
                    if (i > 0) Divider(height: 1, color: c.separator),
                    ListRow(
                      title: p.label,
                      subtitle: p.roomKnown == false ? "Not on the building's room list" : null,
                      icon: p.isRoom ? Icons.meeting_room_outlined : Icons.apartment_outlined,
                      flagged: p.roomKnown == false,
                      onTap: () => onChoose(p),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Large text must not push the card off the screen: it takes at most 60% of the height, and the
    // words scroll while the button stays in reach.
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        child: GlassSurface(
          level: GlassLevel.strong,
          strong: true,
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.label, style: AppText.title3.copyWith(color: c.labelPrimary)),
                      if (place.floor != null) Text('Floor ${place.floor}', style: AppText.subhead.copyWith(color: c.labelSecondary)),
                      if (place.roomKnown == false)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded, color: c.statusTightFill),
                              const SizedBox(width: Space.xs),
                              Expanded(
                                child: Text(
                                  "This room is not on the building's list, so the route goes to the building's nearest door.",
                                  style: AppText.subhead.copyWith(color: c.labelPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => openRoute(context, destination: RoomDestination(place.query)),
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('Route here'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
