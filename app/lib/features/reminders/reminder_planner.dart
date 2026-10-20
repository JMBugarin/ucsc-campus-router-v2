import '../../core/format.dart';
import '../../core/pacific.dart';
import '../schedule/meeting.dart';
import '../today/offline_analysis.dart';
import '../today/today_models.dart';
import '../today/walk_cache.dart';

/// How many days ahead reminders are planned, counting today.
const planAheadDays = 7;

/// "Time to leave" reminders for the classes still to come over the next [days] days, worked out from
/// the walk times saved on the phone, so they can be set up days before the app is opened again.
///
/// The rules follow the server's `plan_reminders`: a heads-up [leadMinutes] before leaving (none when
/// 0) and a "leave" at the moment to go; a class that follows another is walked to from it and is
/// never reminded before that one ends. A class with no saved walk time (online, an unknown room, or
/// never timed) gets nothing. The first class of a day starts from wherever the student was when its
/// walk was last timed from their location. Keys in [sent] are skipped.
List<Reminder> planAhead({
  required List<Meeting> meetings,
  required DateTime now,
  required Set<String> holidays,
  required WalkCache walks,
  required int leadMinutes,
  Set<String> sent = const {},
  int days = planAheadDays,
}) {
  final here = pacificTime(now);
  final today = DateTime.utc(here.year, here.month, here.day);
  final plan = <Reminder>[];
  for (var offset = 0; offset < days; offset++) {
    final classes = occurrences(meetings, today.add(Duration(days: offset)), holidays);
    for (var i = 0; i < classes.length; i++) {
      final c = classes[i];
      final location = c.meeting.location;
      if (!c.start.isAfter(here) || location.isEmpty) continue;
      final previous = i == 0 ? null : classes[i - 1];
      final minutes = previous == null
          ? walks.fromHere(location)
          : (previous.meeting.location.isEmpty ? null : walks.minutes(previous.meeting.location, location));
      if (minutes == null) continue;

      var leave = c.start.subtract(Duration(minutes: minutes));
      if (previous != null && leave.isBefore(previous.end)) leave = previous.end;
      final name = [c.meeting.course, c.meeting.component].where((s) => s.isNotEmpty).join(' ');
      final body = '$location: about $minutes min on foot. Class starts at ${clock12(c.start.hour, c.start.minute)}.';
      final startIso = isoWithOffset(c.start);

      void add(String stage, DateTime at, String title) {
        final key = '$startIso|$stage';
        final seconds = at.difference(here).inMilliseconds / 1000;
        if (seconds >= 0 && !sent.contains(key)) {
          plan.add(Reminder(stage: stage, key: key, inSeconds: seconds, title: title, body: body));
        }
      }

      if (leadMinutes > 0) {
        add('heads-up', leave.subtract(Duration(minutes: leadMinutes)), 'Leave in $leadMinutes min for $name');
      }
      add('leave', leave, 'Time to leave for $name');
    }
  }
  plan.sort((a, b) => a.inSeconds.compareTo(b.inSeconds));
  return plan;
}

/// The server's reminders for the classes it timed, plus [ahead] for every class it did not. The server
/// needs a starting point it may not have, and a reminder planned earlier must not be dropped just
/// because the app was opened without one.
List<Reminder> mergeReminderPlans({required List<Reminder> server, required List<Reminder> ahead}) {
  String classOf(Reminder r) => r.key.split('|').first;
  final covered = {for (final r in server) classOf(r)};
  return [...server, for (final r in ahead) if (!covered.contains(classOf(r))) r]
    ..sort((a, b) => a.inSeconds.compareTo(b.inSeconds));
}

/// Upcoming days after today with a walk between two classes that the phone has not saved. The
/// server's answer for today already covers today's walks.
List<DateTime> daysMissingWalks({
  required List<Meeting> meetings,
  required DateTime now,
  required Set<String> holidays,
  required WalkCache walks,
  int days = planAheadDays,
}) {
  final here = pacificTime(now);
  final today = DateTime.utc(here.year, here.month, here.day);
  final missing = <DateTime>[];
  for (var offset = 1; offset < days; offset++) {
    final day = today.add(Duration(days: offset));
    final classes = occurrences(meetings, day, holidays);
    for (var i = 1; i < classes.length; i++) {
      final from = classes[i - 1].meeting.location, to = classes[i].meeting.location;
      if (from.isNotEmpty && to.isNotEmpty && walks.minutes(from, to) == null) {
        missing.add(day);
        break;
      }
    }
  }
  return missing;
}
