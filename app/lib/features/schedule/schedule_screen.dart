import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../settings/settings.dart';
import 'add_class_dialog.dart';
import 'meeting.dart';
import 'schedule_controller.dart';

/// Picks a calendar file and returns its text, or null if nothing was chosen. Tests replace this.
final calendarFilePickerProvider = Provider<Future<String?> Function()>((ref) => pickCalendarFileText);

const _maxCalendarBytes = 1000000;

Future<String?> pickCalendarFileText() async {
  final file = await FilePicker.pickFile(type: FileType.any);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > _maxCalendarBytes) {
    throw const FormatException('That file is too large to be a class calendar.');
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// The term's first and last day, so the "add a class" form can start with them filled in.
final termProvider = FutureProvider<({String start, String end})?>((ref) async {
  try {
    final term = (await ref.read(apiClientProvider).getJson('/api/meta'))['term'];
    if (term is Map && term['start'] is String && term['end'] is String) {
      return (start: term['start'] as String, end: term['end'] as String);
    }
  } on Object {
    // no server yet, or it is asleep: the form just starts with empty dates
  }
  return null;
});

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(scheduleProvider);
    final locations = ref.watch(locationInfoProvider).value ?? const <LocationInfo>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('My schedule'),
        actions: [
          if (schedule.value?.isNotEmpty ?? false)
            IconButton(
              tooltip: 'Remove all classes',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.content_paste),
                label: const Text('Paste from MyUCSC'),
                onPressed: () => _paste(context, ref),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.event),
                label: const Text('Calendar file'),
                onPressed: () => _calendar(context, ref),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: const Text('Add a class'),
                onPressed: () => _add(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your classes are saved on this phone. Instructor names are never kept.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          schedule.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Could not read your saved classes: $e'),
            data: (meetings) => meetings.isEmpty
                ? const _Empty()
                : Column(
                    children: [
                      for (var i = 0; i < meetings.length; i++)
                        _MeetingTile(
                          meeting: meetings[i],
                          location: i < locations.length ? locations[i] : null,
                          onDelete: () => ref.read(scheduleProvider.notifier).removeAt(i),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _paste(BuildContext context, WidgetRef ref) async {
    final text = await showDialog<String>(context: context, builder: (_) => const _PasteDialog());
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    await _run(context, () => ref.read(scheduleProvider.notifier).importText(text));
  }

  Future<void> _calendar(BuildContext context, WidgetRef ref) async {
    final String? text;
    try {
      text = await ref.read(calendarFilePickerProvider)();
    } on FormatException catch (e) {
      if (context.mounted) _say(context, e.message);
      return;
    }
    if (text == null) return;
    if (!context.mounted) return;
    await _run(context, () => ref.read(scheduleProvider.notifier).importCalendar(text!));
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final term = await ref.read(termProvider.future);
    if (!context.mounted) return;
    final meeting = await showDialog<Meeting>(context: context, builder: (_) => AddClassDialog(term: term));
    if (meeting == null) return;
    if (!context.mounted) return;
    await _run(context, () => ref.read(scheduleProvider.notifier).add(meeting));
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove all classes?'),
        content: const Text('This clears the schedule saved on this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove all')),
        ],
      ),
    );
    if (ok == true) await ref.read(scheduleProvider.notifier).clear();
  }

  Future<void> _run(BuildContext context, Future<ImportSummary> Function() action) async {
    try {
      final summary = await action();
      if (context.mounted) _say(context, summary.message);
    } on ApiException catch (e) {
      if (context.mounted) _say(context, e.message);
    }
  }

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 8)));
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('No classes yet. Paste your schedule, import a calendar, or add one.')),
      );
}

class _MeetingTile extends StatelessWidget {
  const _MeetingTile({required this.meeting, required this.location, required this.onDelete});

  final Meeting meeting;
  final LocationInfo? location;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final info = location;
    final place = switch (info?.kind) {
      'building' => info!.buildingName ?? meeting.location,
      'online' => 'Online',
      'tba' => 'No room yet',
      'unknown' => "Not recognised, so the walk can't be timed",
      _ => null,
    };
    return Card(
      shape: info?.isUnknown == true
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.orange.shade800, width: 1.5),
            )
          : null,
      child: ListTile(
        title: Text(meeting.label.isEmpty ? '(untitled)' : meeting.label),
        subtitle: Text(
          '${meeting.whenLabel}  ${meeting.timeLabel}\n${meeting.location}${place == null ? '' : ' ($place)'}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Remove ${meeting.label}',
          icon: const Icon(Icons.close),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste your schedule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'In MyUCSC open Enrollment, then Class Schedule. Select the whole page, copy it, and paste it here.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Paste here'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Import')),
      ],
    );
  }
}
