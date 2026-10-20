import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/two_up.dart';
import 'class_draft.dart';
import 'room_finder.dart';

/// What the student chose in the editor: the class as they changed it, or to remove it.
class ClassEdit {
  const ClassEdit.save(this.draft) : delete = false;
  const ClassEdit.delete(this.draft) : delete = true;

  final ClassDraft draft;
  final bool delete;
}

Future<ClassEdit?> showClassEditor(BuildContext context, ClassDraft draft) => showModalBottomSheet<ClassEdit>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => ClassEditor(draft: draft),
);

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? _timeOf(String? hhmm) {
  final parts = hhmm?.split(':');
  if (parts == null || parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Every field of a class read from a picture, for correcting it.
class ClassEditor extends StatefulWidget {
  const ClassEditor({super.key, required this.draft});

  final ClassDraft draft;

  @override
  State<ClassEditor> createState() => _ClassEditorState();
}

class _ClassEditorState extends State<ClassEditor> {
  static const _components = ['Lecture', 'Discussion', 'Laboratory', 'Seminar', 'Studio'];

  late final _course = TextEditingController(text: widget.draft.course);
  late final _location = TextEditingController(text: widget.draft.location);
  late String _component = widget.draft.component;
  late final Set<int> _days = {...widget.draft.days};
  late String? _start = widget.draft.start;
  late String? _end = widget.draft.end;
  late String? _from = widget.draft.startDate;
  late String? _to = widget.draft.endDate;
  String? _problem;

  @override
  void dispose() {
    _course.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOf(start ? _start : _end) ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => start ? _start = _hhmm(picked) : _end = _hhmm(picked));
  }

  Future<void> _pickDate(bool from) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse((from ? _from : _to) ?? '') ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => from ? _from = _isoDate(picked) : _to = _isoDate(picked));
  }

  Future<void> _findRoom() async {
    final place = await showRoomFinder(context, _location.text);
    if (place != null) setState(() => _location.text = place.query);
  }

  ClassDraft _edited() => widget.draft.copyWith(
    course: _course.text.trim(),
    component: _component,
    days: _days.toList()..sort(),
    start: _start,
    end: _end,
    location: _location.text.trim(),
    startDate: _from,
    endDate: _to,
    edited: true,
  );

  void _done() {
    final draft = _edited();
    final problem = draft.problem;
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(context, ClassEdit.save(draft));
  }

  @override
  Widget build(BuildContext context) {
    final components = {..._components, if (_component.isNotEmpty) _component};
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text('Edit class', style: Theme.of(context).textTheme.titleMedium)),
            TextField(
              controller: _course,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Course', hintText: 'CSE 130'),
            ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _component,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Not shown')),
                for (final c in components)
                  DropdownMenuItem(
                    value: c,
                    child: Text(c, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _component = value ?? _component),
            ),
            TextField(
              controller: _location,
              decoration: InputDecoration(
                labelText: 'Room',
                hintText: 'Thim Lecture 003',
                suffixIcon: IconButton(tooltip: 'Find the room', icon: const Icon(Icons.search), onPressed: _findRoom),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (var d = 0; d < 7; d++)
                  FilterChip(
                    label: Text(dayCodes[d]),
                    selected: _days.contains(d),
                    onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TwoUp(
              OutlinedButton(
                onPressed: () => _pickTime(true),
                child: Text(_start == null ? 'Starts' : clockFromHhmm(_start!)),
              ),
              OutlinedButton(
                onPressed: () => _pickTime(false),
                child: Text(_end == null ? 'Ends' : clockFromHhmm(_end!)),
              ),
            ),
            const SizedBox(height: 8),
            TwoUp(
              OutlinedButton(onPressed: () => _pickDate(true), child: Text(_from ?? 'From')),
              OutlinedButton(onPressed: () => _pickDate(false), child: Text(_to ?? 'Until')),
            ),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            TwoUp(
              TextButton.icon(
                onPressed: () => Navigator.pop(context, ClassEdit.delete(widget.draft)),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove class'),
              ),
              FilledButton(onPressed: _done, child: const Text('Done')),
            ),
          ],
        ),
      ),
    );
  }
}
