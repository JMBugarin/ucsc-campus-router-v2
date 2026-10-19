import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/tiles.dart';
import '../route/destination.dart';
import '../route/route_screen.dart';
import '../search/place.dart';
import '../search/search_repository.dart';

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
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: const MapOptions(initialCenter: _campusCenter, initialZoom: 15),
          children: [
            const BaseMapLayer(),
            if (point != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(point.lat, point.lon),
                    alignment: Alignment.topCenter,
                    child: Icon(Icons.location_on, size: 40, color: Colors.red.shade700, semanticLabel: selected!.label),
                  ),
                ],
              ),
            const MapAttribution(),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SearchField(controller: _controller, onChanged: _typed, onClear: _clear),
              if (_query.isNotEmpty) _Results(query: _query, onChoose: _choose),
            ],
          ),
        ),
        if (selected != null) Align(alignment: Alignment.bottomCenter, child: _PlaceCard(place: selected)),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged, required this.onClear});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(28),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search a room or building, like BE 152',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close), onPressed: onClear),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
    final results = ref.watch(searchResultsProvider(query));
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: results.when(
        loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        error: (error, _) => _Note(error is ApiException ? error.message : 'Search failed. Try again.'),
        data: (places) => places.isEmpty
            ? const _Note('No match. Try the building name and room, like "Kresge 3201".')
            : Column(mainAxisSize: MainAxisSize.min, children: [for (final p in places) _ResultTile(place: p, onTap: onChoose)]),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(16), child: Text(text));
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.place, required this.onTap});

  final Place place;
  final ValueChanged<Place> onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(place.isRoom ? Icons.meeting_room_outlined : Icons.apartment_outlined),
      title: Text(place.label),
      subtitle: place.roomKnown == false ? const Text('Not on the building\'s room list') : null,
      onTap: () => onTap(place),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(place.label, style: theme.textTheme.titleMedium),
            if (place.floor != null) Text('Floor ${place.floor}'),
            if (place.roomKnown == false)
              const Text('This room is not on the building\'s list, so the route goes to the building\'s nearest door.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => openRoute(context, destination: RoomDestination(place.query)),
              icon: const Icon(Icons.directions_walk),
              label: const Text('Route here'),
            ),
          ],
        ),
      ),
    );
  }
}
