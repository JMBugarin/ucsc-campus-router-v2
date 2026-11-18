import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/clock.dart';
import '../../core/pacific.dart';
import '../settings/settings.dart';

/// Where weekly pings go. Empty in builds that don't count usage, which hides the setting.
const activityUrl = String.fromEnvironment('ACTIVITY_URL');

const weeksBack = 5;

/// The Monday that starts the America/Los_Angeles week holding [moment].
String pacificWeek(DateTime moment) {
  final p = pacificTime(moment);
  final day = DateTime.utc(p.year, p.month, p.day);
  return isoDate(day.subtract(Duration(days: day.weekday - DateTime.monday)));
}

String randomInstallId([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = b[6] & 0x0f | 0x40;
  b[8] = b[8] & 0x3f | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

enum Sent { ok, rejected, failed }

abstract class ActivitySender {
  Future<Sent> record(String install, String week);
  Future<Sent> withdraw(String install);
}

class HttpActivitySender implements ActivitySender {
  HttpActivitySender(this.url);

  final String url;

  Future<Sent> _send(String method, Uri uri, [String? body]) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(method, uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'classmap');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      await response.drain<void>();
      if (response.statusCode == 204) return Sent.ok;
      if (response.statusCode == 400) return Sent.rejected;
      return Sent.failed;
    } catch (_) {
      return Sent.failed;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<Sent> record(String install, String week) => _send(
    'POST',
    Uri.parse(url),
    jsonEncode({'install': install, 'week': week}),
  );

  @override
  Future<Sent> withdraw(String install) => _send(
    'DELETE',
    Uri.parse(url).replace(queryParameters: {'install': install}),
  );
}

final activitySenderProvider = Provider<ActivitySender?>(
  (ref) => activityUrl.isEmpty ? null : HttpActivitySender(activityUrl),
);

class ActivityState {
  const ActivityState({this.install});

  /// The random id made when counting was turned on; null while it is off.
  final String? install;

  bool get on => install != null;

  /// What a student reads out so the consent record can name their install without their name.
  String? get participantCode => install?.substring(0, 8);
}

const _kInstall = 'activity_install';
const _kSent = 'activity_sent_week';
const _kPending = 'activity_pending_weeks';
const _kWithdraw = 'activity_withdraw';

class ActivityController extends Notifier<ActivityState> {
  late SharedPreferences _prefs;
  Future<void>? _flushing;

  ActivitySender? get _sender => ref.read(activitySenderProvider);

  @override
  ActivityState build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    final install = _sender == null ? null : _prefs.getString(_kInstall);
    if (_sender != null) scheduleMicrotask(flush);
    return ActivityState(install: install);
  }

  Future<void> setOn(bool on) async {
    if (_sender == null || on == state.on) return;
    if (on) {
      final id = randomInstallId();
      await _prefs.setString(_kInstall, id);
      state = ActivityState(install: id);
      return;
    }
    final id = state.install!;
    await _prefs.remove(_kInstall);
    await _prefs.remove(_kSent);
    await _prefs.remove(_kPending);
    final waiting = _prefs.getStringList(_kWithdraw) ?? const [];
    await _prefs.setStringList(_kWithdraw, [...waiting, id]);
    state = const ActivityState();
    await _flushing;
    await flush();
  }

  /// A meaningful action happened: a room was found, or a saved class was opened on the map.
  Future<void> meaningfulAction() async {
    if (!state.on) return;
    final week = pacificWeek(ref.read(clockProvider)());
    final pending = _prefs.getStringList(_kPending) ?? const [];
    if (_prefs.getString(_kSent) == week || pending.contains(week)) return;
    await _prefs.setStringList(_kPending, [...pending, week]);
    await flush();
  }

  Future<void> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<void> _flush() async {
    final sender = _sender;
    if (sender == null) return;
    for (final id in _prefs.getStringList(_kWithdraw) ?? const <String>[]) {
      if (await sender.withdraw(id) == Sent.failed) continue;
      final rest = [...?_prefs.getStringList(_kWithdraw)]..remove(id);
      await _prefs.setStringList(_kWithdraw, rest);
    }
    final install = state.install;
    if (install == null) return;
    final oldest = DateTime.parse(
      pacificWeek(ref.read(clockProvider)()),
    ).subtract(const Duration(days: 7 * weeksBack));
    for (final week in _prefs.getStringList(_kPending) ?? const <String>[]) {
      final keep = !DateTime.parse(week).isBefore(oldest);
      final result = keep ? await sender.record(install, week) : Sent.rejected;
      if (result == Sent.failed) continue;
      if (state.install != install) return;
      final rest = [...?_prefs.getStringList(_kPending)]..remove(week);
      await _prefs.setStringList(_kPending, rest);
      if (result == Sent.ok) await _prefs.setString(_kSent, week);
    }
  }
}

final activityProvider = NotifierProvider<ActivityController, ActivityState>(
  ActivityController.new,
);
