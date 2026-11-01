import '../../core/format.dart';
import '../../core/pacific.dart';
import '../schedule/meeting.dart';
import '../today/day_plan.dart';
import 'reminder.dart';

/// How many days ahead reminders are planned, counting today.
const planAheadDays = 7;

/// A reminder [leadMinutes] before each class over the next [days] days. A lead of 0 reminds at the start.
/// Keys in [sent] are skipped, and a class whose reminder time has already passed gets none.
List<Reminder> planReminders({
  required List<Meeting> meetings,
  required DateTime now,
  required Set<String> holidays,
  required int leadMinutes,
  Set<String> sent = const {},
  int days = planAheadDays,
}) {
  final here = pacificTime(now);
  final today = DateTime.utc(here.year, here.month, here.day);
  final plan = <Reminder>[];
  for (var offset = 0; offset < days; offset++) {
    for (final c in occurrences(
      meetings,
      today.add(Duration(days: offset)),
      holidays,
    )) {
      if (!c.start.isAfter(here)) {
        continue;
      }
      final key = '${isoWithOffset(c.start)}|class';
      final remindAt = c.start.subtract(Duration(minutes: leadMinutes));
      final seconds = remindAt.difference(here).inMilliseconds / 1000;
      if (seconds < 0 || sent.contains(key)) {
        continue;
      }
      final when = clock12(c.start.hour, c.start.minute);
      plan.add(
        Reminder(
          stage: 'class',
          key: key,
          inSeconds: seconds,
          title: leadMinutes > 0
              ? '${c.label} in $leadMinutes min'
              : '${c.label} is starting',
          body: c.meeting.location.isEmpty
              ? 'Starts at $when.'
              : '${c.meeting.location} at $when.',
        ),
      );
    }
  }
  plan.sort((a, b) => a.inSeconds.compareTo(b.inSeconds));
  return plan;
}
