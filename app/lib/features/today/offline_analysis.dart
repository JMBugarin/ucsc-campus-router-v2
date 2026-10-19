import 'package:timezone/timezone.dart' as tz;

import '../../core/pacific.dart';
import '../schedule/meeting.dart';
import 'today_models.dart';
import 'walk_cache.dart';

/// The no-network twin of the server's `timetable.analyze`, apart from walk times (which come from
/// [WalkCache]) and reminders. Both are tested against `server/testdata/schedule_cases.json`.

const tightMinutes = 5;
const searchDays = 21;

class Occurrence {
  const Occurrence(this.start, this.end, this.meeting);

  final tz.TZDateTime start;
  final tz.TZDateTime end;
  final Meeting meeting;
}

bool occursOn(Meeting m, DateTime day, Set<String> holidays) {
  final iso = isoDate(day);
  if (iso.compareTo(m.startDate) < 0 || iso.compareTo(m.endDate) > 0) return false;
  if (m.skipDates.contains(iso)) return false;
  if (m.days.isEmpty) return iso == m.startDate;
  return !holidays.contains(iso) && m.days.contains(day.weekday - 1);
}

tz.TZDateTime _at(DateTime day, String hhmm) {
  final parts = hhmm.split(':');
  return tz.TZDateTime(pacific, day.year, day.month, day.day, int.parse(parts[0]), int.parse(parts[1]));
}

List<Occurrence> occurrences(List<Meeting> meetings, DateTime day, Set<String> holidays) {
  final found = [
    for (final m in meetings)
      if (occursOn(m, day, holidays)) Occurrence(_at(day, m.start), _at(day, m.end), m),
  ];
  found.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.end.compareTo(b.end);
  });
  return found;
}

/// The first class that starts after [now], today or within the next three weeks.
Occurrence? nextOccurrence(List<Meeting> meetings, tz.TZDateTime now, Set<String> holidays) {
  if (meetings.isEmpty) return null;
  final first = meetings.map((m) => m.startDate).reduce((a, b) => a.compareTo(b) < 0 ? a : b);
  final today = isoDate(now);
  final base = today.compareTo(first) >= 0 ? DateTime.utc(now.year, now.month, now.day) : DateTime.parse('${first}T00:00:00Z');
  for (var offset = 0; offset <= searchDays; offset++) {
    final day = base.add(Duration(days: offset));
    for (final occ in occurrences(meetings, day, holidays)) {
      if (occ.start.isAfter(now)) return occ;
    }
  }
  return null;
}

String _whyNoClasses(List<Meeting> meetings, DateTime day, Set<String> holidays) {
  if (meetings.isEmpty) return 'no_schedule';
  final iso = isoDate(day);
  final first = meetings.map((m) => m.startDate).reduce((a, b) => a.compareTo(b) < 0 ? a : b);
  final last = meetings.map((m) => m.endDate).reduce((a, b) => a.compareTo(b) > 0 ? a : b);
  if (holidays.contains(iso)) return 'holiday';
  if (iso.compareTo(first) < 0) return 'before_term';
  if (iso.compareTo(last) > 0) return 'after_term';
  if (day.weekday >= 6) return 'weekend';
  return 'no_classes';
}

double _minutes(Duration d) => d.inMicroseconds / Duration.microsecondsPerMinute;

double _round1(double x) => (x * 10).roundToDouble() / 10;

String _spareStatus(double? freeMin) {
  if (freeMin == null) return 'unknown';
  if (freeMin < 0) return 'late';
  if (freeMin < tightMinutes) return 'tight';
  return 'ok';
}

ClassTime _classTime(Occurrence o, {tz.TZDateTime? now, bool isToday = true, Map<String, Object?> extra = const {}}) {
  return ClassTime(
    course: o.meeting.course,
    component: o.meeting.component,
    location: o.meeting.location,
    start: isoWithOffset(o.start),
    end: isoWithOffset(o.end),
    startsInMin: now == null ? null : _round1(_minutes(o.start.difference(now))),
    minutesLeft: now == null ? null : _round1(_minutes(o.end.difference(now))),
    isToday: isToday,
    gapMin: extra['gap'] as double?,
    walkMin: extra['walk'] as int?,
    freeMin: extra['free'] as double?,
    status: extra['status'] as String?,
  );
}

/// What the server would say about [meetings] at [now], with walk times from [walks] (or none).
///
/// [hasLocation] says the phone knows where the student is, so a walk starts from there.
Analysis analyzeOffline({
  required List<Meeting> meetings,
  required DateTime now,
  required Set<String> holidays,
  required WalkCache walks,
  required bool hasLocation,
}) {
  final here = pacificTime(now);
  final today = occurrences(meetings, DateTime.utc(here.year, here.month, here.day), holidays);
  Occurrence? current;
  for (final o in today) {
    if (!o.start.isAfter(here) && here.isBefore(o.end)) {
      current = o;
      break;
    }
  }
  Occurrence? previous;
  for (final o in today.reversed) {
    if (!o.end.isAfter(here)) {
      previous = o;
      break;
    }
  }
  final upcoming = [for (final o in today) if (o.start.isAfter(here)) o];
  final next = upcoming.isNotEmpty ? upcoming.first : nextOccurrence(meetings, here, holidays);

  final state = current != null
      ? 'in_class'
      : upcoming.isNotEmpty
          ? (previous != null ? 'between_classes' : 'before_classes')
          : today.isNotEmpty
              ? 'done_for_today'
              : 'no_classes_today';

  ClassTime? nextTime;
  Walk? walk;
  double? freeMin;
  var status = 'unknown';
  String? leaveBy;
  final notes = <String>[];

  if (next != null) {
    final isToday = isoDate(next.start) == isoDate(here);
    nextTime = _classTime(next, now: here, isToday: isToday);
    if (isToday) {
      String? originRoom;
      var spareFrom = here;
      var from = 'here';
      if (current != null) {
        originRoom = current.meeting.location;
        spareFrom = current.end;
        from = 'current_class';
      } else if (hasLocation) {
        originRoom = null;
      } else if (previous != null) {
        originRoom = previous.meeting.location;
        from = 'previous_class';
      }
      final canWalk = current != null || hasLocation || previous != null;
      final minutes = canWalk ? walks.minutes(originRoom, next.meeting.location) : null;
      if (minutes != null) {
        final free = _minutes(next.start.difference(spareFrom)) - minutes;
        walk = Walk(minutes: minutes, meters: 0, from: from);
        freeMin = _round1(free);
        status = _spareStatus(free);
        leaveBy = isoWithOffset(next.start.subtract(Duration(minutes: minutes)));
      } else if (next.meeting.location.isNotEmpty) {
        notes.add("Offline: I don't have a saved walk time for that class yet.");
      }
    }
  }

  final timeline = <ClassTime>[];
  for (var i = 0; i < today.length; i++) {
    final occ = today[i];
    if (i == 0) {
      timeline.add(_classTime(occ));
      continue;
    }
    final prev = today[i - 1];
    final gap = _minutes(occ.start.difference(prev.end));
    final minutes = walks.minutes(prev.meeting.location, occ.meeting.location);
    final free = minutes == null ? null : gap - minutes;
    timeline.add(_classTime(occ, extra: {
      'gap': _round1(gap),
      'walk': minutes,
      'free': free == null ? null : _round1(free),
      'status': _spareStatus(free),
    }));
  }

  return Analysis(
    now: isoWithOffset(here),
    state: state,
    reason: today.isEmpty ? _whyNoClasses(meetings, DateTime.utc(here.year, here.month, here.day), holidays) : null,
    current: current == null ? null : _classTime(current, now: here),
    next: nextTime,
    walk: walk,
    freeMin: freeMin,
    status: status,
    leaveBy: leaveBy,
    today: timeline,
    notes: notes,
    reminders: const [],
    holidays: holidays.toList()..sort(),
  );
}
