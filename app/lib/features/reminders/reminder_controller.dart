import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../campus/campus_data.dart';
import '../../campus/terms.dart';
import '../../core/clock.dart';
import '../schedule/schedule_controller.dart';
import '../settings/settings.dart';
import 'reminder_planner.dart';
import 'reminder_sync.dart';

/// Keeps the phone's scheduled reminders in step with the saved schedule and the settings. Its state is a
/// message when reminders could not be set up, otherwise null. It replans when the schedule or settings
/// change; the app invalidates it when it comes back to the foreground.
class ReminderController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final meetings = await ref.watch(scheduleProvider.future);
    final settings = ref.watch(settingsProvider);
    final terms = await ref.watch(termsProvider.future);
    final sync = ref.read(reminderSyncProvider);
    final now = ref.read(clockProvider)();
    try {
      if (!settings.remindersOn || meetings.isEmpty) {
        if (sync.hasAny) await sync.clear(now);
        return null;
      }
      await sync.apply(
        planReminders(
          meetings: meetings,
          now: now,
          holidays: holidaysOf(terms),
          leadMinutes: settings.remindLeadMinutes,
          sent: sync.firedKeys(now).toSet(),
        ),
        now,
      );
      return null;
    } on Object {
      return "Couldn't set up reminders on this phone.";
    }
  }
}

final reminderControllerProvider =
    AsyncNotifierProvider<ReminderController, String?>(ReminderController.new);
