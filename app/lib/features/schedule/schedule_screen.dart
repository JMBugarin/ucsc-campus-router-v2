import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/waking_note.dart';
import '../settings/settings.dart';
import '../today/today_text.dart';
import 'add_class_dialog.dart';
import 'meeting.dart';
import 'photo_import.dart';
import 'schedule_controller.dart';
import 'schedule_repository.dart';

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

/// What the screen is waiting on the server for, and what to say if the wait drags on, or null when it
/// is not waiting.
class _Busy extends Notifier<({String label, String? note})?> {
  @override
  ({String label, String? note})? build() => null;

  void set(String? label, {String? note}) => state = label == null ? null : (label: label, note: note);
}

final _busyProvider = NotifierProvider<_Busy, ({String label, String? note})?>(_Busy.new);

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(scheduleProvider);
    final locations = ref.watch(locationInfoProvider).value ?? const <LocationInfo>[];
    final busy = ref.watch(_busyProvider);

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
                onPressed: busy == null ? () => _paste(context, ref) : null,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.event),
                label: const Text('Calendar file'),
                onPressed: busy == null ? () => _calendar(context, ref) : null,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Read a photo'),
                onPressed: busy == null ? () => _photo(context, ref) : null,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: const Text('Add a class'),
                onPressed: busy == null ? () => _add(context, ref) : null,
              ),
            ],
          ),
          if (busy != null) _Working(busy.label, note: busy.note),
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
                          onRestore: () => ref.read(scheduleProvider.notifier).restoreAllDays(meetings[i]),
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
    await _run(context, ref, 'Reading your schedule…', () => ref.read(scheduleProvider.notifier).importText(text));
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
    await _run(context, ref, 'Reading your schedule…', () => ref.read(scheduleProvider.notifier).importCalendar(text!));
  }

  Future<void> _photo(BuildContext context, WidgetRef ref) async {
    final busy = ref.read(_busyProvider.notifier)..set('Checking the server…');
    final PhotoSupport support;
    try {
      support = await ref.read(scheduleRepositoryProvider).photoSupport();
    } on ApiException catch (e) {
      if (context.mounted) _say(context, e.message);
      return;
    } finally {
      busy.set(null);
    }
    if (!context.mounted) return;
    if (!support.ready) {
      _say(context, support.reason);
      return;
    }

    final host = Uri.tryParse(ref.read(settingsProvider).serverUrl)?.host ?? '';
    final agreed = await showDialog<bool>(context: context, builder: (_) => _PhotoDialog(host: host));
    if (agreed != true || !context.mounted) return;

    final Uint8List? chosen;
    try {
      chosen = await ref.read(photoPickerProvider)();
    } on Object {
      if (context.mounted) _say(context, "Couldn't open your photos. Try again.");
      return;
    }
    if (chosen == null || !context.mounted) return;

    busy.set('Preparing your photo…');
    final PickedPhoto photo;
    try {
      photo = await ref.read(photoPreparerProvider)(chosen);
    } on Object catch (e) {
      busy.set(null);
      if (context.mounted) _say(context, e is FormatException ? e.message : "That file isn't a photo I can read.");
      return;
    }
    if (!context.mounted) {
      busy.set(null);
      return;
    }
    await _run(
      context,
      ref,
      'Reading your photo…',
      () => ref.read(scheduleProvider.notifier).importPhoto(photo),
      note: 'Reading a photo takes a while, up to a minute or two. It goes to your server, which sends it to Claude.',
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    // A sleeping server must not hold the form back: without the term it just starts with empty dates.
    final term = await ref.read(termProvider.future).timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
    if (term == null) ref.invalidate(termProvider);
    if (!context.mounted) return;
    final meeting = await showDialog<Meeting>(context: context, builder: (_) => AddClassDialog(term: term));
    if (meeting == null) return;
    if (!context.mounted) return;
    await _run(context, ref, 'Checking the class…', () => ref.read(scheduleProvider.notifier).add(meeting));
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

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    String working,
    Future<ImportSummary> Function() action, {
    String? note,
  }) async {
    final busy = ref.read(_busyProvider.notifier)..set(working, note: note);
    String message;
    try {
      message = (await action()).message;
    } on ApiException catch (e) {
      message = e.message;
    } finally {
      busy.set(null);
    }
    if (context.mounted) _say(context, message);
  }

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 8)));
  }
}

class _Working extends StatelessWidget {
  const _Working(this.label, {this.note});

  final String label;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(label),
          WakingNote(after: note == null ? const Duration(seconds: 4) : const Duration(seconds: 2), message: note),
        ],
      ),
    );
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
  const _MeetingTile({required this.meeting, required this.location, required this.onDelete, required this.onRestore});

  final Meeting meeting;
  final LocationInfo? location;
  final VoidCallback onDelete;
  final VoidCallback onRestore;

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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${meeting.whenLabel}  ${meeting.timeLabel}\n${meeting.location}${place == null ? '' : ' ($place)'}'),
            if (meeting.skipDates.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Not meeting ${meeting.skipDates.map((d) => shortDayLabel(DateTime.parse(d))).join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(onPressed: onRestore, child: const Text('Restore')),
                ],
              ),
          ],
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

/// Says where a photo goes before the student picks one, since this is the one import that sends a picture
/// somewhere other than the server's own code.
class _PhotoDialog extends StatelessWidget {
  const _PhotoDialog({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) {
    final where = host.isEmpty ? 'your server' : host;
    return AlertDialog(
      scrollable: true,
      title: const Text('Read a photo of your schedule'),
      content: Text(
        'The photo you choose is sent to $where, which sends it on to Anthropic\'s Claude to read. '
        'The server keeps nothing, Anthropic handles the picture under its own terms, and instructor names are dropped.\n\n'
        'Choose a screenshot of your schedule, not a picture with other people or details in it. '
        'Check the classes it finds afterwards, since a reading can be wrong.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Choose a photo')),
      ],
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
      scrollable: true,
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
