import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/settings.dart';
import '../today/today_models.dart';
import 'reminder_scheduler.dart';

/// Keeps the phone's scheduled notifications in step with what the server says is still to come.
///
/// The server decides when to remind (see `plan_reminders`); this class only remembers what it has
/// scheduled, so each reminder fires once and a changed plan replaces the old one.
class ReminderSync {
  ReminderSync(this._scheduler, this._prefs);

  final ReminderScheduler _scheduler;
  final SharedPreferences _prefs;

  static const _prefsKey = 'reminders_v1';

  /// Reminders are forgotten this long after they were due.
  static const _keepFor = Duration(hours: 24);

  /// reminder key -> when it is (or was) due, in milliseconds since 1970.
  Map<String, int> _load() {
    try {
      final raw = _prefs.getString(_prefsKey);
      if (raw == null) return {};
      return {for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries) e.key: (e.value as num).toInt()};
    } on Object {
      return {};
    }
  }

  Future<void> _save(Map<String, int> due) => _prefs.setString(_prefsKey, jsonEncode(due));

  bool get hasAny => _load().isNotEmpty;

  /// Keys already shown (or due by now). Sent to the server so it does not plan them again.
  List<String> firedKeys(DateTime now) {
    final ms = now.millisecondsSinceEpoch;
    return [for (final e in _load().entries) if (e.value <= ms) e.key];
  }

  /// Makes the phone's notifications match [plan] (the reminders still to come).
  Future<void> apply(List<Reminder> plan, DateTime now) async {
    final nowMs = now.millisecondsSinceEpoch;
    final due = _load()..removeWhere((_, at) => at < nowMs - _keepFor.inMilliseconds);
    final planned = {for (final r in plan) r.key};

    // Pending reminders the server no longer wants (class removed, walk got shorter, ...).
    for (final key in [for (final e in due.entries) if (e.value > nowMs) e.key]) {
      if (!planned.contains(key)) {
        await _scheduler.cancel(key);
        due.remove(key);
      }
    }

    for (final r in plan) {
      if (r.inSeconds <= 0) {
        if (due.containsKey(r.key)) continue; // already shown
        await _scheduler.show(r);
        due[r.key] = nowMs;
      } else {
        final at = now.add(Duration(milliseconds: (r.inSeconds * 1000).round()));
        await _scheduler.schedule(r, at);
        due[r.key] = at.millisecondsSinceEpoch;
      }
    }
    await _save(due);
  }

  /// Cancels everything still pending (reminders were switched off).
  Future<void> clear(DateTime now) async {
    final nowMs = now.millisecondsSinceEpoch;
    final due = _load();
    for (final e in due.entries) {
      if (e.value > nowMs) await _scheduler.cancel(e.key);
    }
    await _prefs.remove(_prefsKey);
  }
}

final reminderSyncProvider = Provider<ReminderSync>(
  (ref) => ReminderSync(ref.watch(reminderSchedulerProvider), ref.watch(sharedPreferencesProvider)),
);
