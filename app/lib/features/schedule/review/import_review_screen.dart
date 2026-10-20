import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../search/search_repository.dart';
import '../ocr/parsed_row.dart';
import '../schedule_controller.dart';
import '../term.dart';
import 'class_draft.dart';
import 'class_editor.dart';
import 'room_finder.dart';

RoomState roomStateOf(RoomResolution resolution) => switch (resolution.kind) {
  'building' => resolution.roomKnown == false ? RoomState.unlisted : RoomState.found,
  'online' || 'tba' => RoomState.none,
  _ => RoomState.notFound,
};

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The classes read from a picture, for the student to check before anything is saved. Pops with what was
/// added, or null if the student cancelled.
class ImportReviewScreen extends ConsumerStatefulWidget {
  const ImportReviewScreen({super.key, required this.parsed});

  final ParsedSchedule parsed;

  @override
  ConsumerState<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends ConsumerState<ImportReviewScreen> {
  late List<ClassDraft> _drafts = [
    for (var i = 0; i < widget.parsed.rows.length; i++) ClassDraft.fromRow(i, widget.parsed.rows[i]),
  ];

  /// The classes the picture showed no dates for: they take the term's, or the ones the student chooses.
  late final Set<int> _undated = {
    for (final d in _drafts)
      if (!d.hasDates) d.id,
  };
  final _rooms = <String, RoomState>{};
  ({String start, String end})? _datesForUndated;
  bool _datesChosen = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _useTerm(ref.read(termProvider).value);
    ref.listenManual(termProvider, (_, next) {
      if (_datesChosen || !mounted) return;
      setState(() => _useTerm(next.value));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRooms());
  }

  void _useTerm(({String start, String end})? term) {
    if (term == null || _datesChosen) return;
    _datesForUndated = term;
    _fillUndated(term);
  }

  void _fillUndated(({String start, String end}) dates) {
    _drafts = [
      for (final d in _drafts)
        if (_undated.contains(d.id)) d.copyWith(startDate: dates.start, endDate: dates.end) else d,
    ];
  }

  Future<void> _chooseDates() async {
    final current = _datesForUndated;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: current == null
          ? null
          : DateTimeRange(start: DateTime.parse(current.start), end: DateTime.parse(current.end)),
    );
    if (range == null || !mounted) return;
    final dates = (start: _isoDate(range.start), end: _isoDate(range.end));
    setState(() {
      _datesChosen = true;
      _datesForUndated = dates;
      _fillUndated(dates);
    });
  }

  Future<void> _checkRooms() async {
    final search = ref.read(searchRepositoryProvider);
    final pending = {
      for (final d in _drafts)
        if (d.location.trim().isNotEmpty && !_rooms.containsKey(d.location.trim())) d.location.trim(),
    };
    if (pending.isEmpty || !mounted) return;
    setState(() {
      for (final location in pending) {
        _rooms[location] = RoomState.checking;
      }
    });
    await Future.wait([
      for (final location in pending)
        () async {
          RoomState state;
          try {
            state = roomStateOf(await search.resolve(location));
          } on Object {
            state = RoomState.unchecked;
          }
          if (mounted) setState(() => _rooms[location] = state);
        }(),
    ]);
  }

  RoomState? _roomOf(ClassDraft d) => d.location.trim().isEmpty ? null : _rooms[d.location.trim()];

  bool _needsLook(ClassDraft d) => d.problem != null || d.flagged || (_roomOf(d)?.needsLook ?? false);

  void _replace(ClassDraft draft) {
    _drafts = [for (final d in _drafts) d.id == draft.id ? draft : d];
  }

  Future<void> _edit(ClassDraft draft) async {
    final edit = await showClassEditor(context, draft);
    if (edit == null || !mounted) return;
    if (edit.delete) {
      _remove(edit.draft);
      return;
    }
    final own = edit.draft;
    if (own.startDate != _datesForUndated?.start || own.endDate != _datesForUndated?.end) _undated.remove(own.id);
    setState(() => _replace(own));
    _checkRooms();
  }

  Future<void> _findRoom(ClassDraft draft) async {
    final place = await showRoomFinder(context, draft.location);
    if (place == null || !mounted) return;
    setState(() => _replace(draft.copyWith(location: place.query)));
    _checkRooms();
  }

  void _remove(ClassDraft draft) {
    final index = _drafts.indexWhere((d) => d.id == draft.id);
    if (index < 0) return;
    setState(() => _drafts = [..._drafts]..removeAt(index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${draft.label.isEmpty ? 'the class' : draft.label}.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (mounted) setState(() => _drafts = [..._drafts]..insert(index.clamp(0, _drafts.length), draft));
            },
          ),
        ),
      );
  }

  void _leave([ImportSummary? summary]) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Navigator.pop(context, summary);
  }

  Future<void> _cancel() async {
    if (_saving) return;
    if (_drafts.isEmpty) {
      _leave();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this import?'),
        content: const Text('Nothing has been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep checking')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (discard == true && mounted) _leave();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final summary = await ref.read(scheduleProvider.notifier).addChecked([
        for (final d in _drafts) d.toMeeting(),
      ], notes: widget.parsed.notes);
      if (mounted) _leave(summary);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't save your classes. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final looks = _drafts.where(_needsLook).length;
    final invalid = _drafts.any((d) => d.problem != null);
    final canSave = _drafts.isNotEmpty && !invalid && !_saving;
    final undated = _drafts.where((d) => _undated.contains(d.id)).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Check your classes'),
          leading: IconButton(
            tooltip: 'Cancel import',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : _cancel,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                _drafts.isEmpty
                    ? 'No classes left.'
                    : 'Found ${_drafts.length} ${_drafts.length == 1 ? 'class' : 'classes'}'
                          '${looks == 0 ? '.' : ', $looks ${looks == 1 ? 'needs' : 'need'} a look.'}',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Read on this phone: the picture was never sent anywhere. Nothing is saved until you tap Save.',
              style: theme.textTheme.bodySmall,
            ),
            if (invalid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Fix or remove the classes marked in red to save.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            for (final note in widget.parsed.notes) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note)),
            if (_rooms.values.contains(RoomState.unchecked))
              const _Banner("Couldn't check the rooms with the server, so they will be saved as read."),
            if (undated.isNotEmpty)
              _DatesCard(dates: undated.every((d) => d.hasDates) ? _datesForUndated : null, onChoose: _chooseDates),
            for (final draft in _drafts)
              _ClassCard(
                draft: draft,
                room: _roomOf(draft),
                onEdit: () => _edit(draft),
                onRemove: () => _remove(draft),
                onFindRoom: () => _findRoom(draft),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _saving ? null : _cancel, child: const Text('Cancel')),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canSave ? _save : null,
                child: Text(_drafts.length == 1 ? 'Save 1 class' : 'Save ${_drafts.length} classes'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

class _DatesCard extends StatelessWidget {
  const _DatesCard({required this.dates, required this.onChoose});

  /// When the classes with no dates in the picture run, or null if that is not known yet.
  final ({String start, String end})? dates;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final known = dates;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              known == null
                  ? 'The picture shows no dates for some classes. Choose when they run.'
                  : 'The picture shows no dates for some classes, so they run ${known.start} to ${known.end}.',
            ),
            TextButton(onPressed: onChoose, child: Text(known == null ? 'Choose dates' : 'Change dates')),
          ],
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({
    required this.draft,
    required this.room,
    required this.onEdit,
    required this.onRemove,
    required this.onFindRoom,
  });

  final ClassDraft draft;
  final RoomState? room;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onFindRoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = draft.problem;
    final attention = problem != null || draft.flagged || (room?.needsLook ?? false);
    final warning = Colors.orange.shade800;
    final when = [draft.daysLabel, draft.timeLabel].where((s) => s.isNotEmpty).join('  ');
    return Card(
      margin: const EdgeInsets.only(top: 12),
      shape: attention
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: problem != null ? theme.colorScheme.error : warning, width: 1.5),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(draft.label.isEmpty ? '(no course)' : draft.label, style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Remove ${draft.label.isEmpty ? 'this class' : draft.label}',
                    icon: const Icon(Icons.close),
                    onPressed: onRemove,
                  ),
                ],
              ),
              if (when.isNotEmpty) Text(when),
              Text(draft.location.isEmpty ? 'No room' : draft.location),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 12),
                  child: Text(problem, style: TextStyle(color: theme.colorScheme.error)),
                )
              else if (draft.flagged)
                for (final reason in draft.reasons)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 12),
                    child: _Note(Icons.warning_amber_rounded, warning, reason),
                  ),
              if (room == RoomState.checking)
                const Padding(
                  padding: EdgeInsets.only(top: 4, right: 12),
                  child: _Note(Icons.hourglass_empty, null, 'Checking the room…'),
                ),
              if (room == RoomState.notFound || room == RoomState.unlisted)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 12),
                  child: _Note(
                    Icons.location_off_outlined,
                    warning,
                    room == RoomState.notFound
                        ? "I don't recognise this room."
                        : "That room number isn't one I know in this building.",
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  children: [
                    if (room == RoomState.notFound || room == RoomState.unlisted)
                      TextButton.icon(
                        onPressed: onFindRoom,
                        icon: const Icon(Icons.search),
                        label: const Text('Find the room'),
                      ),
                    TextButton(onPressed: onEdit, child: const Text('Edit')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.icon, this.color, this.text);

  final IconData icon;
  final Color? color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(text)),
    ],
  );
}
