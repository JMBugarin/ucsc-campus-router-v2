import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../campus/campus_data.dart';
import '../../core/tiles.dart';
import '../../design/controls.dart';
import '../../design/floating_bar.dart';
import '../../design/glass.dart';
import '../../design/map_markers.dart';
import '../../design/surfaces.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../directions/directions.dart';
import '../search/place.dart';
import '../search/search_repository.dart';
import '../today/today_controller.dart';
import 'focused_place.dart';

const _campusCenter = LatLng(36.9951, -122.0585);

/// Search for a building or room and see where it is, and see the day's classes on the campus map.
/// No schedule is needed. Directions are left to the phone's maps app.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _controller = TextEditingController();
  final _map = MapController();
  String _query = '';
  Place? _selected;

  @override
  void dispose() {
    _controller.dispose();
    _map.dispose();
    super.dispose();
  }

  void _typed(String text) => setState(() => _query = text.trim());

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

  void _clear() => setState(() {
    _selected = null;
    _query = '';
    _controller.clear();
  });

  @override
  Widget build(BuildContext context) {
    ref.listen(focusedPlaceProvider, (_, place) {
      if (place == null) return;
      ref.read(focusedPlaceProvider.notifier).clear();
      _choose(place);
    });
    final selected = _selected;
    final inset = FloatingBarInset.of(context);
    final c = context.colors;
    final campus = ref.watch(campusProvider).value;
    final classes = ref.watch(dayPlanProvider).value?.classes ?? const [];
    final classPlaces = <String, Place>{};
    if (campus != null) {
      for (final occ in classes) {
        final place = placeFor(campus, occ.meeting.location);
        if (place != null) classPlaces[place.label] = place;
      }
    }
    final pins = (selected == null ? classPlaces.values.toList() : [selected])
        .where((p) => p.point != null)
        .toList();
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: 'Campus map',
          child: FlutterMap(
            mapController: _map,
            options: const MapOptions(
              initialCenter: _campusCenter,
              initialZoom: 15,
            ),
            children: [
              const BaseMapLayer(),
              MarkerLayer(
                markers: [
                  for (final place in pins)
                    Marker(
                      point: LatLng(place.point!.lat, place.point!.lon),
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _choose(place),
                        child: DestinationPin(label: place.label),
                      ),
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
                GlassSearchField(
                  controller: _controller,
                  onChanged: _typed,
                  onClear: _clear,
                ),
                if (_query.isNotEmpty)
                  Flexible(
                    child: _Results(query: _query, onChoose: _choose),
                  ),
              ],
            ),
          ),
        ),
        if (selected != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: inset,
            child: _PlaceCard(place: selected),
          ),
      ],
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.xl),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );
    return results.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => solid(
        Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Search failed. Try again.',
                style: AppText.body.copyWith(color: c.labelPrimary),
              ),
              TextButton(
                onPressed: () => ref.invalidate(searchResultsProvider(query)),
                child: const Text('Try again'),
              ),
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
                      subtitle: p.roomKnown == false
                          ? "Not on the building's room list"
                          : null,
                      icon: p.isRoom
                          ? Icons.meeting_room_outlined
                          : Icons.apartment_outlined,
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

class _PlaceCard extends ConsumerWidget {
  const _PlaceCard({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final campus = ref.watch(campusProvider).value;
    final target = campus == null ? null : walkTarget(campus, place.query);
    // Large text must not push the card off the screen: it takes at most 60% of the height, and the
    // words scroll while the button stays in reach.
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
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
                      Text(
                        place.label,
                        style: AppText.title3.copyWith(color: c.labelPrimary),
                      ),
                      if (place.floor != null)
                        Text(
                          'Floor ${place.floor}',
                          style: AppText.subhead.copyWith(
                            color: c.labelSecondary,
                          ),
                        ),
                      if (place.roomKnown == false)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: c.statusTightFill,
                              ),
                              const SizedBox(width: Space.xs),
                              Expanded(
                                child: Text(
                                  "This room is not on the building's list, so the pin marks the building.",
                                  style: AppText.subhead.copyWith(
                                    color: c.labelPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (target != null) ...[
                const SizedBox(height: Space.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => walkThere(context, ref, target),
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Walk there'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
