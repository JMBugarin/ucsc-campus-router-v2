import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../settings/settings.dart';
import 'meeting.dart';

/// Whether the server can read a photo of a schedule, and when it can't, why, in words for the student.
class PhotoSupport {
  const PhotoSupport({required this.ready, this.reason = ''});

  final bool ready;
  final String reason;
}

/// How long a photo may take: the server allows its reader about three minutes at the very most, and
/// the usual wait for a reply is far shorter.
const photoTimeout = Duration(seconds: 200);

/// Where the student's classes are stored (on the phone) and how pasted text, calendar files, photos
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

  /// Asks the server whether it can read photos, without sending one.
  Future<PhotoSupport> photoSupport();

  /// Sends a photo of a schedule to the server, which reads it and keeps nothing. Never sent twice: each
  /// reading costs the server's owner money.
  Future<ImportResult> importPhoto(Uint8List bytes, String mediaType);
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
        await _api.postJson('/api/schedule/clean', {'meetings': [for (final m in meetings) m.toJson()]}, retry: true),
      );

  @override
  Future<PhotoSupport> photoSupport() async {
    try {
      final photo = (await _api.getJson('/api/capabilities'))['photo'];
      if (photo is Map) {
        if (photo['ready'] == true) return const PhotoSupport(ready: true);
        return PhotoSupport(ready: false, reason: _whyNotPhotos(photo['reason']));
      }
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
    }
    return PhotoSupport(ready: false, reason: _whyNotPhotos(null));
  }

  /// The server's reason in the app's words: its advice about "the on-device reader" is for the web demo,
  /// which has one, so that sentence is left out and the app's own advice added.
  static String _whyNotPhotos(Object? reason) {
    final kept = reason is String
        ? reason.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.isNotEmpty && !s.toLowerCase().contains('on-device')).join(' ')
        : '';
    return "${kept.isEmpty ? "This server can't read photos." : kept} You can paste your schedule instead.";
  }

  @override
  Future<ImportResult> importPhoto(Uint8List bytes, String mediaType) async => ImportResult.fromJson(
        await _api.postJson(
          '/api/schedule/photo',
          {'image': base64Encode(bytes), 'media_type': mediaType},
          timeout: photoTimeout,
        ),
      );

  Future<ImportResult> _post(String path, String text) async =>
      ImportResult.fromJson(await _api.postJson(path, {'text': text}, retry: true));
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ApiScheduleRepository(ref.watch(sharedPreferencesProvider), ref.watch(apiClientProvider));
});
