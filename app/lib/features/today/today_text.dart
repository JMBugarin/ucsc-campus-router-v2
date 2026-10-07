import '../../core/format.dart';
import 'today_models.dart';

const _noClassesReasons = {
  'weekend': 'No classes on weekends.',
  'holiday': 'No classes today (holiday).',
  'before_term': "The term hasn't started yet.",
  'after_term': 'The term is over.',
  'no_schedule': 'Add your classes to see what is next.',
  'no_classes': 'No classes today.',
};

/// `XYZ 10 Lecture at 2:40 PM in 40 min`, or for another day `Tue 9:50 AM, XYZ 10 Lecture`.
String nextClassText(ClassTime next) {
  if (next.isToday) {
    return '${next.label} at ${clockFromIso(next.start)} in ${durationText(next.startsInMin ?? 0)}';
  }
  return '${weekdayFromIso(next.start)} ${clockFromIso(next.start)}, ${next.label}';
}

/// The headline for the day.
String todaySummary(Analysis a) {
  final next = a.next;
  switch (a.state) {
    case 'in_class':
      final current = a.current!;
      final head = 'In ${current.label} until ${clockFromIso(current.end)} '
          '(${durationText(current.minutesLeft ?? 0)} left).';
      return next == null ? head : '$head Next: ${nextClassText(next)}.';
    case 'before_classes':
    case 'between_classes':
      return next == null ? 'No more classes today.' : 'Next: ${nextClassText(next)}.';
    case 'done_for_today':
      return next == null ? 'Done for today.' : 'Done for today. Next class: ${nextClassText(next)}.';
    default:
      final why = _noClassesReasons[a.reason] ?? _noClassesReasons['no_classes']!;
      return next == null ? why : '$why Next class: ${nextClassText(next)}.';
  }
}

/// How the spare time reads, and whether it is fine (`ok`), `tight` or `late`.
({String status, String text}) spareText(double freeMin, {String? leaveBy}) {
  final leave = leaveBy == null ? '' : ' Leave by ${clockFromIso(leaveBy)}.';
  if (freeMin < 0) {
    return (status: 'late', text: "Not enough time: you'd arrive about ${durationText(-freeMin)} late.");
  }
  if (freeMin < 5) {
    return (status: 'tight', text: 'Tight: only ${durationText(freeMin)} to spare.$leave');
  }
  return (status: 'ok', text: '${durationText(freeMin)} of free time.$leave');
}

/// Where the walk starts, in words.
String walkOrigin(String from) => switch (from) {
      'current_class' => 'your current class',
      'previous_class' => 'your last class',
      _ => 'your location',
    };

/// The walk to the next class and the time to spare, or null if there is no walk to talk about.
({String status, String text})? walkText(Analysis a) {
  final next = a.next;
  final walk = a.walk;
  if (next == null || walk == null || a.freeMin == null) return null;
  final spare = spareText(a.freeMin!, leaveBy: a.leaveBy);
  return (
    status: spare.status,
    text: 'Walk to ${next.location} is about ${walk.minutes} min from ${walkOrigin(walk.from)}. ${spare.text}',
  );
}

/// The gap and walk between a class and the one before it, or null for the first class.
({String status, String text})? transitionText(ClassTime t) {
  if (t.gapMin == null) return null;
  if (t.walkMin == null || t.freeMin == null) {
    return (status: 'unknown', text: "${durationText(t.gapMin!)} between classes (can't time the walk).");
  }
  final spare = spareText(t.freeMin!);
  return (
    status: spare.status,
    text: '${durationText(t.gapMin!)} between classes, ${t.walkMin} min walk. ${spare.text}',
  );
}
