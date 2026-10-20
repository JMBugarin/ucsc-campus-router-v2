import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../arrive/entry_walks.dart';
import 'handoff.dart';

/// What a student off campus can do about the trip to [entry]: open it in Transit, open it in the phone's
/// maps app for another way of travelling, or pick a different entry point.
class TripActions extends ConsumerWidget {
  const TripActions({
    super.key,
    required this.entry,
    required this.options,
    required this.roomLabel,
    this.far = false,
  });

  final EntryPoint entry;

  /// Every entry point to choose from, the best guess first.
  final List<EntryWalk> options;

  /// Where the walks from the entry points lead, for the picker.
  final String roomLabel;

  /// Too far from campus for a local bus trip: Transit is not offered.
  final bool far;

  Future<void> _transit(BuildContext context, WidgetRef ref) async {
    final launcher = ref.read(linkLauncherProvider);
    final messenger = ScaffoldMessenger.of(context);
    final result = await openTransit(launcher, entry.point);
    final text = handoffMessage(result);
    if (text == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        action: result == HandoffResult.mapsInstead
            ? SnackBarAction(label: 'Get Transit', onPressed: () => launcher.open(transitStoreUri))
            : null,
      ));
  }

  Future<void> _maps(BuildContext context, WidgetRef ref, TravelMode mode) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await ref.read(linkLauncherProvider).open(mapsUri(entry.point, mode));
    if (opened) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text("Couldn't open ${mapsAppName()}.")));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maps = mapsAppName();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!far)
          FilledButton.icon(
            onPressed: () => _transit(context, ref),
            icon: const Icon(Icons.directions_bus_outlined),
            label: const Text('Get to campus with Transit'),
          ),
        Wrap(
          alignment: WrapAlignment.start,
          children: [
            if (options.length > 1)
              TextButton.icon(
                onPressed: () => showEntryPicker(context, entry: entry, options: options, roomLabel: roomLabel),
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text('Change entry point'),
              ),
            MenuAnchor(
              menuChildren: [
                for (final (mode, label) in [
                  (TravelMode.walking, 'Walk there'),
                  (TravelMode.cycling, 'Bike there'),
                  (TravelMode.driving, 'Drive there'),
                  (TravelMode.transit, 'Public transit'),
                ])
                  MenuItemButton(onPressed: () => _maps(context, ref, mode), child: Text(label)),
              ],
              builder: (context, controller, _) => TextButton.icon(
                onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.map_outlined),
                label: Text('Open in $maps'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A sheet listing the entry points with their walk to [roomLabel]; picking one is remembered on this phone.
Future<void> showEntryPicker(
  BuildContext context, {
  required EntryPoint entry,
  required List<EntryWalk> options,
  required String roomLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EntryPicker(current: entry, options: options, roomLabel: roomLabel),
  );
}

class _EntryPicker extends ConsumerWidget {
  const _EntryPicker({required this.current, required this.options, required this.roomLabel});

  final EntryPoint current;
  final List<EntryWalk> options;
  final String roomLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Where will you arrive on campus?', style: theme.textTheme.titleMedium),
            ),
            for (final (index, walk) in options.indexed)
              ListTile(
                selected: walk.entry.id == current.id,
                leading: Icon(walk.entry.isBusStop ? Icons.directions_bus_outlined : Icons.local_parking_outlined),
                title: Text(walk.entry.name),
                subtitle: Text('${walk.minutes} min on foot to $roomLabel${index == 0 ? ' · suggested' : ''}'),
                trailing: walk.entry.id == current.id ? const Icon(Icons.check) : null,
                onTap: () {
                  ref.read(entryChoiceProvider.notifier).choose(walk.entry.id);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}
