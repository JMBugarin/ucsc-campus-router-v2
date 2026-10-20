import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/waking_note.dart';
import '../../search/place.dart';
import '../../search/search_repository.dart';

/// The room search of the Map tab, to find the room a class from a picture was meant to be in. Returns the
/// place the student chose, whose `query` is a location the server can place.
Future<Place?> showRoomFinder(BuildContext context, String initialQuery) => showModalBottomSheet<Place>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => RoomFinder(initialQuery: initialQuery),
);

class RoomFinder extends ConsumerStatefulWidget {
  const RoomFinder({super.key, required this.initialQuery});

  final String initialQuery;

  @override
  ConsumerState<RoomFinder> createState() => _RoomFinderState();
}

class _RoomFinderState extends ConsumerState<RoomFinder> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  late String _query = widget.initialQuery.trim();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _typed(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, keyboard + 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text('Find the room', style: Theme.of(context).textTheme.titleMedium)),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _typed,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Building and room',
                hintText: 'Kresge 3201',
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(child: _Results(query: _query)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.isEmpty) {
      return const Padding(padding: EdgeInsets.all(8), child: Text('Type a building and a room number.'));
    }
    return ref
        .watch(searchResultsProvider(query))
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [LinearProgressIndicator(), WakingNote()],
            ),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(error is ApiException ? error.message : 'The search failed. Try again.'),
                TextButton(
                  onPressed: () => ref.invalidate(searchResultsProvider(query)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
          data: (places) => places.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No match. Try the building name and room, like "Kresge 3201".'),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final place in places)
                      ListTile(
                        dense: true,
                        leading: Icon(place.isRoom ? Icons.meeting_room_outlined : Icons.apartment_outlined),
                        title: Text(place.label),
                        subtitle: place.roomKnown == false ? const Text("Not on the building's room list") : null,
                        onTap: () => Navigator.pop(context, place),
                      ),
                  ],
                ),
        );
  }
}
