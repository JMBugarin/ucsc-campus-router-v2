import 'package:timezone/timezone.dart' as tz;

import '../../core/format.dart';
import '../../core/pacific.dart';
import '../schedule/meeting.dart';

const searchDays = 21;

class Occurrence {
  const Occurrence(this.start, this.end, this.meeting);

  final tz.TZDateTime start;
  final tz.TZDateTime end;
  final Meeting meeting;

  String get label => meeting.label;
}

bool occursOn(Meeting m, DateTime day, Set<String> holidays) {
  final iso = isoDate(day);
  if (iso.compareTo(m.startDate) < 0 || iso.compareTo(m.endDate) > 0) {
    return false;
  }
  if (m.skipDates.contains(iso)) return false;
  if (m.days.isEmpty) return iso == m.startDate;
  return !holidays.contains(iso) && m.days.contains(day.weekday - 1);
}

tz.TZDateTime _at(DateTime day, String hhmm) {
  final parts = hhmm.split(':');
  return tz.TZDateTime(
    pacific,
    day.year,
    day.month,
    day.day,
    int.parse(parts[0]),
    int.parse(parts[1]),
  );
}

List<Occurrence> occurrences(
  List<Meeting> meetings,
  DateTime day,
  Set<String> holidays,
) {
  final found = [
    for (final m in meetings)
      if (occursOn(m, day, holidays))
        Occurrence(_at(day, m.start), _at(day, m.end), m),
  ];
  found.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.end.compareTo(b.end);
  });
  return found;
}

/// The first class that starts after [now], today or within the next three weeks.
Occurrence? nextOccurrence(
  List<Meeting> meetings,
  tz.TZDateTime now,
  Set<String> holidays,
) {
  if (meetings.isEmpty) return null;
  final first = meetings
      .map((m) => m.startDate)
      .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
  final today = isoDate(now);
  final base = today.compareTo(first) >= 0
      ? DateTime.utc(now.year, now.month, now.day)
      : DateTime.parse('${first}T00:00:00Z');
  for (var offset = 0; offset <= searchDays; offset++) {
    final day = base.add(Duration(days: offset));
    for (final occ in occurrences(meetings, day, holidays)) {
      if (occ.start.isAfter(now)) return occ;
    }
  }
  return null;
}

/// Why [day] has no class: `no_schedule`, `holiday`, `before_term`, `after_term`, `weekend` or `no_classes`.
String whyNoClasses(
  List<Meeting> meetings,
  DateTime day,
  Set<String> holidays,
) {
  if (meetings.isEmpty) return 'no_schedule';
  final iso = isoDate(day);
  final first = meetings
      .map((m) => m.startDate)
      .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
  final last = meetings
      .map((m) => m.endDate)
      .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
  if (holidays.contains(iso)) return 'holiday';
  if (iso.compareTo(first) < 0) return 'before_term';
  if (iso.compareTo(last) > 0) return 'after_term';
  if (day.weekday >= 6) return 'weekend';
  return 'no_classes';
}

enum DayState {
  inClass,
  beforeClasses,
  betweenClasses,
  doneForToday,
  noClasses,
}

/// Where a day stands. For today it knows what is on now and what is next; for another day it is just
/// the list of classes (or why there are none).
class DayPlan {
  const DayPlan({
    required this.day,
    required this.isToday,
    required this.state,
    required this.classes,
    this.reason,
    this.current,
    this.next,
  });

  /// The calendar date, as midnight UTC.
  final DateTime day;
  final bool isToday;
  final DayState state;
  final List<Occurrence> classes;

  /// Why there are no classes (see [whyNoClasses]).
  final String? reason;
  final Occurrence? current;

  /// For today, the next class to start, which may be on a later day. Null when another day is shown.
  final Occurrence? next;

  /// Minutes between the end of the class before [index] and its start, or null for the first class.
  double? breakBefore(int index) => index <= 0
      ? null
      : classes[index].start.difference(classes[index - 1].end).inSeconds / 60;
}

/// Works out the day from the saved schedule and the clock. [viewDay] picks another day, which has no
/// "now" or "next".
DayPlan planDay({
  required List<Meeting> meetings,
  required DateTime now,
  required Set<String> holidays,
  DateTime? viewDay,
}) {
  final here = pacificTime(now);
  if (viewDay != null) {
    final classes = occurrences(meetings, viewDay, holidays);
    return DayPlan(
      day: viewDay,
      isToday: false,
      state: classes.isEmpty ? DayState.noClasses : DayState.beforeClasses,
      classes: classes,
      reason: classes.isEmpty
          ? whyNoClasses(meetings, viewDay, holidays)
          : null,
    );
  }
  final day = DateTime.utc(here.year, here.month, here.day);
  final today = occurrences(meetings, day, holidays);
  Occurrence? current;
  for (final o in today) {
    if (!o.start.isAfter(here) && here.isBefore(o.end)) {
      current = o;
      break;
    }
  }
  final previousEnded = today.any((o) => !o.end.isAfter(here));
  final upcoming = [
    for (final o in today)
      if (o.start.isAfter(here)) o,
  ];
  final next = upcoming.isNotEmpty
      ? upcoming.first
      : nextOccurrence(meetings, here, holidays);
  final state = current != null
      ? DayState.inClass
      : upcoming.isNotEmpty
      ? (previousEnded ? DayState.betweenClasses : DayState.beforeClasses)
      : today.isNotEmpty
      ? DayState.doneForToday
      : DayState.noClasses;
  return DayPlan(
    day: day,
    isToday: true,
    state: state,
    classes: today,
    reason: today.isEmpty ? whyNoClasses(meetings, day, holidays) : null,
    current: current,
    next: next,
  );
}

const _noClassesReasons = {
  'weekend': 'No classes on weekends.',
  'holiday': 'No classes today (holiday).',
  'before_term': "The term hasn't started yet.",
  'after_term': 'The term is over.',
  'no_schedule': 'Add your classes to see what is next.',
  'no_classes': 'No classes today.',
};

const _noClassesOnOtherDays = {
  'weekend': 'No classes: weekend.',
  'holiday': 'No classes: holiday.',
  'before_term': 'The term has not started.',
  'after_term': 'The term is over.',
  'no_schedule': 'No classes yet.',
  'no_classes': 'No classes.',
};

String noClassesOnOtherDayText(String? reason) =>
    _noClassesOnOtherDays[reason] ?? _noClassesOnOtherDays['no_classes']!;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Mon, Oct 12`.
String dayLabel(DateTime day) =>
    '${_weekdays[day.weekday - 1]}, ${_months[day.month - 1]} ${day.day}';

/// `Oct 12`.
String shortDayLabel(DateTime day) => '${_months[day.month - 1]} ${day.day}';

String _clock(tz.TZDateTime t) => clock12(t.hour, t.minute);

/// `3 classes, 9:00 AM to 3:45 PM.`
String classCountText(int count, String firstStart, String lastEnd) =>
    '$count ${count == 1 ? 'class' : 'classes'}, $firstStart to $lastEnd.';

/// `XYZ 10 Lecture at 2:40 PM in 40 min`, or for a later day `Tue 9:50 AM, XYZ 10 Lecture`.
String nextClassText(Occurrence next, tz.TZDateTime now) {
  if (isoDate(next.start) == isoDate(now)) {
    return '${next.label} at ${_clock(next.start)} in ${durationText(next.start.difference(now).inSeconds / 60)}';
  }
  return '${_weekdays[next.start.weekday - 1]} ${_clock(next.start)}, ${next.label}';
}

/// The headline for the day.
String daySummary(DayPlan plan, DateTime nowUtcInstant) {
  final now = pacificTime(nowUtcInstant);
  if (!plan.isToday) {
    if (plan.classes.isEmpty) return noClassesOnOtherDayText(plan.reason);
    return classCountText(
      plan.classes.length,
      _clock(plan.classes.first.start),
      _clock(plan.classes.last.end),
    );
  }
  final next = plan.next;
  switch (plan.state) {
    case DayState.inClass:
      final current = plan.current!;
      final head =
          'In ${current.label} until ${_clock(current.end)} '
          '(${durationText(current.end.difference(now).inSeconds / 60)} left).';
      return next == null ? head : '$head Next: ${nextClassText(next, now)}.';
    case DayState.beforeClasses:
    case DayState.betweenClasses:
      return next == null
          ? 'No more classes today.'
          : 'Next: ${nextClassText(next, now)}.';
    case DayState.doneForToday:
      return next == null
          ? 'Done for today.'
          : 'Done for today. Next class: ${nextClassText(next, now)}.';
    case DayState.noClasses:
      final why =
          _noClassesReasons[plan.reason] ?? _noClassesReasons['no_classes']!;
      return next == null
          ? why
          : '$why Next class: ${nextClassText(next, now)}.';
  }
}
