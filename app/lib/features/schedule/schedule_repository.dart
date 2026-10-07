import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../settings/settings.dart';
import 'meeting.dart';

/// Where the student's classes are stored (on the phone) and how pasted text, calendar files
/// and hand-typed classes are checked (by the server, which keeps nothing).
abstract class ScheduleRepository {
  Future<List<Meeting>> load();
  Future<void> save(List<Meeting> meetings);

  /// Reads a schedule pasted from MyUCSC, or calendar text if that is what was pasted.
  Future<ImportResult> importText(String text);

  /// Reads the text of an `.ics` calendar file.
  Future<ImportResult> importCalendar(String text);

  /// Has the server validate these meetings and say what each location is.
  Future<ImportResult> clean(List<Meeting> meetings);
}

const _kSchedule = 'schedule_v1';

class ApiScheduleRepository implements ScheduleRepository {
  ApiScheduleRepository(this._prefs, this._api);

  final SharedPreferences _prefs;
  final ApiClient _api;

  @override
  Future<List<Meeting>> load() async {
    final stored = _prefs.getString(_kSchedule);
    if (stored == null) return [];
    try {
      return [for (final m in jsonDecode(stored) as List) Meeting.fromJson(m as Map<String, dynamic>)];
    } on Object {
      return []; // an unreadable saved schedule is dropped rather than crashing the app
    }
  }

  @override
  Future<void> save(List<Meeting> meetings) =>
      _prefs.setString(_kSchedule, jsonEncode([for (final m in meetings) m.toJson()]));

  @override
  Future<ImportResult> importText(String text) {
    final isCalendar = RegExp('BEGIN:VCALENDAR', caseSensitive: false).hasMatch(text);
    return isCalendar ? importCalendar(text) : _post('/api/schedule/parse', text);
  }

  @override
  Future<ImportResult> importCalendar(String text) => _post('/api/schedule/ics', text);

  @override
  Future<ImportResult> clean(List<Meeting> meetings) async => ImportResult.fromJson(
        await _api.postJson('/api/schedule/clean', {'meetings': [for (final m in meetings) m.toJson()]}),
      );

  Future<ImportResult> _post(String path, String text) async =>
      ImportResult.fromJson(await _api.postJson(path, {'text': text}));
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ApiScheduleRepository(ref.watch(sharedPreferencesProvider), ref.watch(apiClientProvider));
});
