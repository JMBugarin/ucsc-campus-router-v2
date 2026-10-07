import 'package:flutter/material.dart';

import '../../core/format.dart';
import 'meeting.dart';

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A form for a class typed in by hand. Returns the [Meeting], or null if cancelled.
/// The server checks it again when it is saved.
class AddClassDialog extends StatefulWidget {
  const AddClassDialog({super.key, this.term});

  /// The term's first and last day, used to fill in the dates.
  final ({String start, String end})? term;

  @override
  State<AddClassDialog> createState() => _AddClassDialogState();
}

class _AddClassDialogState extends State<AddClassDialog> {
  static const _components = ['Lecture', 'Discussion', 'Lab', 'Seminar', 'Event'];

  final _course = TextEditingController();
  final _location = TextEditingController();
  String _component = 'Lecture';
  final Set<int> _days = {};
  bool _oneTime = false;
  TimeOfDay? _start;
  TimeOfDay? _end;
  late String _from = widget.term?.start ?? '';
  late String _to = widget.term?.end ?? '';
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
      initialTime: (start ? _start : _end) ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _pickDate(bool from) async {
    final current = DateTime.tryParse(from ? _from : _to) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => from ? _from = _isoDate(picked) : _to = _isoDate(picked));
  }

  void _submit() {
    String? problem;
    if (_course.text.trim().isEmpty) {
      problem = 'Enter the course, like CSE 130.';
    } else if (!_oneTime && _days.isEmpty) {
      problem = 'Pick the days it meets, or turn on "One-time event".';
    } else if (_start == null || _end == null) {
      problem = 'Pick a start and end time.';
    } else if (_hhmm(_end!).compareTo(_hhmm(_start!)) <= 0) {
      problem = 'The end time must be after the start time.';
    } else if (_from.isEmpty || (!_oneTime && _to.isEmpty)) {
      problem = _oneTime ? 'Pick the date.' : 'Pick the first and last dates.';
    } else if (!_oneTime && _to.compareTo(_from) < 0) {
      problem = 'The last date is before the first.';
    }
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(
      context,
      Meeting(
        course: _course.text.trim(),
        component: _component,
        days: _oneTime ? const [] : (_days.toList()..sort()),
        start: _hhmm(_start!),
        end: _hhmm(_end!),
        location: _location.text.trim(),
        startDate: _from,
        endDate: _oneTime ? _from : _to,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a class'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _course,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Course', hintText: 'CSE 130'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _component,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [for (final c in _components) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (value) => setState(() => _component = value ?? _component),
            ),
            TextField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Room', hintText: 'Thim Lecture 003'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('One-time event'),
              value: _oneTime,
              onChanged: (value) => setState(() => _oneTime = value),
            ),
            if (!_oneTime)
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(true),
                    child: Text(_start == null ? 'Starts' : clock12(_start!.hour, _start!.minute)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(false),
                    child: Text(_end == null ? 'Ends' : clock12(_end!.hour, _end!.minute)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(true),
                    child: Text(_from.isEmpty ? (_oneTime ? 'Date' : 'From') : _from),
                  ),
                ),
                if (!_oneTime) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(false),
                      child: Text(_to.isEmpty ? 'Until' : _to),
                    ),
                  ),
                ],
              ],
            ),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
