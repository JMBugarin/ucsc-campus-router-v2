import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'meeting.dart';
import 'schedule_repository.dart';

/// What an import did, for the message shown afterwards.
class ImportSummary {
  const ImportSummary({required this.added, required this.alreadyThere, required this.notes});

  final int added;
  final int alreadyThere;
  final List<String> notes;

  String get message {
    final parts = <String>[
      'Added $added ${added == 1 ? 'class' : 'classes'}${alreadyThere > 0 ? ' ($alreadyThere already there)' : ''}.',
      ...notes,
    ];
    return parts.join(' ');
  }
}

class ScheduleController extends AsyncNotifier<List<Meeting>> {
  ScheduleRepository get _repo => ref.read(scheduleRepositoryProvider);

  @override
  Future<List<Meeting>> build() => ref.read(scheduleRepositoryProvider).load();

  List<Meeting> get _current => state.value ?? const [];

  Future<ImportSummary> importText(String text) async => _merge(await _repo.importText(text));

  Future<ImportSummary> importCalendar(String text) async => _merge(await _repo.importCalendar(text));

  /// Adds classes the student has checked one by one, after reading them from a picture. They were read on the
  /// phone, so no server has seen them yet.
  Future<ImportSummary> addChecked(List<Meeting> meetings, {List<String> notes = const []}) =>
      _merge(ImportResult(meetings: meetings, notes: notes, locations: const []));

  /// Adds one hand-typed class after the server has checked it.
  Future<ImportSummary> add(Meeting meeting) async => _merge(await _repo.clean([meeting]));

  /// Marks [iso] (`2026-10-21`) as a day [meeting] does not meet. Returns false if there is no room
  /// for another skipped date, or the class is no longer in the schedule.
  Future<bool> skipDay(Meeting meeting, String iso, {required String today}) async {
    final i = _current.indexWhere(meeting.sameClassAs);
    final updated = i < 0 ? null : _current[i].skipping(iso, today: today);
    if (updated == null) return false;
    await _replace([..._current]..[i] = updated);
    return true;
  }

  /// Undoes [skipDay]: the class meets on [iso] again.
  Future<void> restoreDay(Meeting meeting, String iso) async {
    final i = _current.indexWhere(meeting.sameClassAs);
    if (i < 0) return;
    await _replace([..._current]..[i] = _current[i].meetingOn(iso));
  }

  /// Every day skipped for [meeting] meets again.
  Future<void> restoreAllDays(Meeting meeting) async {
    final i = _current.indexWhere(meeting.sameClassAs);
    if (i < 0) return;
    var updated = _current[i];
    for (final d in updated.skipDates) {
      updated = updated.meetingOn(d);
    }
    await _replace([..._current]..[i] = updated);
  }

  Future<void> removeAt(int index) async {
    final updated = [..._current]..removeAt(index);
    await _replace(updated);
  }

  Future<void> clear() => _replace(const []);

  Future<ImportSummary> _merge(ImportResult result) async {
    final existing = _current;
    final fresh = [
      for (final m in result.meetings)
        if (!existing.any(m.sameClassAs)) m,
    ];
    await _replace([...existing, ...fresh]);
    return ImportSummary(
      added: fresh.length,
      alreadyThere: result.meetings.length - fresh.length,
      notes: result.notes,
    );
  }

  Future<void> _replace(List<Meeting> meetings) async {
    await _repo.save(meetings);
    state = AsyncData(meetings);
  }
}

final scheduleProvider = AsyncNotifierProvider<ScheduleController, List<Meeting>>(ScheduleController.new);

/// What the server made of each class's room, to flag the ones it can't place. Best effort:
/// if the server can't be reached the list is empty and nothing is flagged.
final locationInfoProvider = FutureProvider<List<LocationInfo>>((ref) async {
  final meetings = await ref.watch(scheduleProvider.future);
  if (meetings.isEmpty) return const [];
  try {
    return (await ref.read(scheduleRepositoryProvider).clean(meetings)).locations;
  } on Object {
    return const [];
  }
});
