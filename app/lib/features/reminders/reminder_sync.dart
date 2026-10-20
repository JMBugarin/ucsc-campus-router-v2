import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/settings.dart';
import '../today/today_models.dart';
import 'reminder_scheduler.dart';

/// iOS keeps at most 64 pending notifications and silently drops the rest, so fewer are scheduled.
const maxPendingReminders = 60;

/// Keeps the phone's scheduled notifications in step with what is still to come.
///
/// The server decides when to remind today (see `plan_reminders`) and `planAhead` covers the days after;
/// this class only remembers what it has scheduled, so each reminder fires once and a changed plan
/// replaces the old one.
class ReminderSync {
  ReminderSync(this._scheduler, this._prefs);

  final ReminderScheduler _scheduler;
  final SharedPreferences _prefs;

  static const _prefsKey = 'reminders_v1';

  /// Reminders are forgotten this long after they were due.
  static const _keepFor = Duration(hours: 24);

  /// A reminder already set for a moment this close to the new one is not set again.
  static const _sameMoment = Duration(seconds: 2);

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

  /// Makes the phone's notifications match [plan] (the reminders still to come). Only the soonest
  /// [maxPendingReminders] stay scheduled; a reminder already set for the same moment is left alone.
  Future<void> apply(List<Reminder> plan, DateTime now) async {
    final nowMs = now.millisecondsSinceEpoch;
    final due = _load()..removeWhere((_, at) => at < nowMs - _keepFor.inMilliseconds);
    final kept = _soonest(plan);
    final planned = {for (final r in kept) r.key};

    // Pending reminders the plan no longer wants (class removed, walk got shorter, ...).
    for (final key in [for (final e in due.entries) if (e.value > nowMs) e.key]) {
      if (!planned.contains(key)) {
        await _scheduler.cancel(key);
        due.remove(key);
      }
    }

    for (final r in kept) {
      if (r.inSeconds <= 0) {
        if (due.containsKey(r.key)) continue; // already shown
        await _scheduler.show(r);
        due[r.key] = nowMs;
      } else {
        final at = now.add(Duration(milliseconds: (r.inSeconds * 1000).round()));
        final already = due[r.key];
        if (already != null && already > nowMs && (already - at.millisecondsSinceEpoch).abs() < _sameMoment.inMilliseconds) {
          continue;
        }
        await _scheduler.schedule(r, at);
        due[r.key] = at.millisecondsSinceEpoch;
      }
    }
    await _save(due);
  }

  /// [plan] without the reminders that would not fit under the platform's limit. iOS keeps the soonest
  /// 64 pending notifications and drops the rest without a word, so the later ones are left out here.
  List<Reminder> _soonest(List<Reminder> plan) {
    final pending = [for (final r in plan) if (r.inSeconds > 0) r]..sort((a, b) => a.inSeconds.compareTo(b.inSeconds));
    if (pending.length <= maxPendingReminders) return plan;
    final dropped = {for (final r in pending.skip(maxPendingReminders)) r.key};
    return [for (final r in plan) if (!dropped.contains(r.key)) r];
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
