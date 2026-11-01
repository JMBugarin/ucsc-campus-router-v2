import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../campus/campus.dart';
import '../../campus/campus_data.dart';
import '../../campus/terms.dart';
import '../../core/clock.dart';
import '../../core/pacific.dart';
import '../settings/settings.dart';
import 'import/clean.dart';
import 'import/ics.dart';
import 'import/paste.dart';
import 'meeting.dart';

/// Where the student's classes are stored (on the phone) and how pasted text, calendar files and hand-typed
/// classes are read and checked (also on the phone).
abstract class ScheduleRepository {
  Future<List<Meeting>> load();
  Future<void> save(List<Meeting> meetings);

  /// Reads a schedule pasted from MyUCSC, or calendar text if that is what was pasted.
  /// Throws [ScheduleError] with a message to show when the text cannot be used.
  Future<ImportResult> importText(String text);

  /// Reads the text of an `.ics` calendar file.
  Future<ImportResult> importCalendar(String text);

  /// Validates these meetings and says what each location is.
  Future<ImportResult> clean(List<Meeting> meetings);
}

const _kSchedule = 'schedule_v1';

class LocalScheduleRepository implements ScheduleRepository {
  LocalScheduleRepository(this._prefs, this._campus, this._terms, this._now);

  final SharedPreferences _prefs;
  final Future<Campus> Function() _campus;
  final Future<List<Term>> Function() _terms;
  final DateTime Function() _now;

  @override
  Future<List<Meeting>> load() async {
    final stored = _prefs.getString(_kSchedule);
    if (stored == null) return [];
    try {
      return [
        for (final m in jsonDecode(stored) as List)
          Meeting.fromJson(m as Map<String, dynamic>),
      ];
    } on Object {
      return []; // an unreadable saved schedule is dropped rather than crashing the app
    }
  }

  @override
  Future<void> save(List<Meeting> meetings) => _prefs.setString(
    _kSchedule,
    jsonEncode([for (final m in meetings) m.toJson()]),
  );

  @override
  Future<ImportResult> importText(String text) async {
    if (RegExp('BEGIN:VCALENDAR', caseSensitive: false).hasMatch(text)) {
      return importCalendar(text);
    }
    final campus = await _campus();
    final read = parsePasted(text, campus);
    return _result(campus, read.meetings, read.notes);
  }

  @override
  Future<ImportResult> importCalendar(String text) async {
    final campus = await _campus();
    final terms = await _terms();
    final read = parseIcs(
      text,
      term: termFor(terms, isoDate(pacificTime(_now()))),
    );
    return _result(campus, read.meetings, read.notes);
  }

  @override
  Future<ImportResult> clean(List<Meeting> meetings) async =>
      _result(await _campus(), cleanSchedule(meetings), const []);

  ImportResult _result(
    Campus campus,
    List<Meeting> meetings,
    List<String> notes,
  ) => ImportResult(
    meetings: meetings,
    notes: notes,
    locations: [
      for (final m in meetings)
        () {
          final r = campus.resolve(m.location);
          return LocationInfo(
            kind: r.kind,
            buildingName: r.buildingId == null
                ? null
                : campus.buildings[r.buildingId]!.name,
            roomKnown: r.roomKnown,
          );
        }(),
    ],
  );
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return LocalScheduleRepository(
    ref.watch(sharedPreferencesProvider),
    () => ref.read(campusProvider.future),
    () => ref.read(termsProvider.future),
    ref.read(clockProvider),
  );
});
