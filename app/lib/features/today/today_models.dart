/// A class on today's timeline, or the current/next class.
class ClassTime {
  const ClassTime({
    required this.course,
    required this.component,
    required this.location,
    required this.start,
    required this.end,
    this.startsInMin,
    this.minutesLeft,
    this.isToday = true,
    this.gapMin,
    this.walkMin,
    this.freeMin,
    this.status,
  });

  final String course;
  final String component;
  final String location;

  /// ISO times with the Pacific offset, like `2026-10-12T14:40:00-07:00`.
  final String start;
  final String end;
  final double? startsInMin;
  final double? minutesLeft;
  final bool isToday;

  /// For a class after another one today: the gap since the previous class ended, the walk
  /// between them, the spare time left (negative means late) and a verdict.
  final double? gapMin;
  final int? walkMin;
  final double? freeMin;

  /// `ok`, `tight`, `late` or `unknown`.
  final String? status;

  String get label => [course, component].where((s) => s.isNotEmpty).join(' ');

  factory ClassTime.fromJson(Map<String, dynamic> json) => ClassTime(
        course: (json['course'] as String?) ?? '',
        component: (json['component'] as String?) ?? '',
        location: (json['location'] as String?) ?? '',
        start: json['start'] as String,
        end: json['end'] as String,
        startsInMin: (json['starts_in_min'] as num?)?.toDouble(),
        minutesLeft: (json['minutes_left'] as num?)?.toDouble(),
        isToday: (json['is_today'] as bool?) ?? true,
        gapMin: (json['gap_min'] as num?)?.toDouble(),
        walkMin: (json['walk_min'] as num?)?.toInt(),
        freeMin: (json['free_min'] as num?)?.toDouble(),
        status: json['status'] as String?,
      );
}

/// The walk to the next class.
class Walk {
  const Walk({required this.minutes, required this.meters, required this.from});

  final int minutes;
  final double meters;

  /// Where it starts: `here`, `current_class` or `previous_class`.
  final String from;

  factory Walk.fromJson(Map<String, dynamic> json) => Walk(
        minutes: (json['minutes'] as num).toInt(),
        meters: (json['meters'] as num).toDouble(),
        from: (json['from'] as String?) ?? 'here',
      );
}

/// A "time to leave" notification the server wants shown.
class Reminder {
  const Reminder({
    required this.stage,
    required this.key,
    required this.inSeconds,
    required this.title,
    required this.body,
  });

  /// `heads-up`, `leave` or `late`.
  final String stage;

  /// Identifies this reminder so it is never shown twice.
  final String key;
  final double inSeconds;
  final String title;
  final String body;

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        stage: json['stage'] as String,
        key: json['key'] as String,
        inSeconds: (json['in_seconds'] as num).toDouble(),
        title: json['title'] as String,
        body: json['body'] as String,
      );
}

class LeaveBanner {
  const LeaveBanner({required this.text, required this.late});

  final String text;
  final bool late;

  factory LeaveBanner.fromJson(Map<String, dynamic> json) =>
      LeaveBanner(text: json['text'] as String, late: (json['late'] as bool?) ?? false);
}

/// The server's answer to "where am I in my day?" (`POST /api/today`).
class Analysis {
  const Analysis({
    required this.now,
    required this.state,
    this.reason,
    this.current,
    this.next,
    this.walk,
    this.freeMin,
    required this.status,
    this.leaveBy,
    required this.today,
    required this.notes,
    required this.reminders,
    this.banner,
  });

  final String now;

  /// `in_class`, `before_classes`, `between_classes`, `done_for_today` or `no_classes_today`.
  final String state;

  /// Why there are no classes today (`weekend`, `holiday`, `before_term`, ...).
  final String? reason;
  final ClassTime? current;
  final ClassTime? next;
  final Walk? walk;
  final double? freeMin;

  /// `ok`, `tight`, `late` or `unknown`.
  final String status;
  final String? leaveBy;
  final List<ClassTime> today;
  final List<String> notes;
  final List<Reminder> reminders;
  final LeaveBanner? banner;

  factory Analysis.fromJson(Map<String, dynamic> json) {
    ClassTime? classTime(String key) {
      final value = json[key];
      return value is Map<String, dynamic> ? ClassTime.fromJson(value) : null;
    }

    return Analysis(
      now: json['now'] as String,
      state: json['state'] as String,
      reason: json['reason'] as String?,
      current: classTime('current'),
      next: classTime('next'),
      walk: json['walk'] is Map<String, dynamic> ? Walk.fromJson(json['walk'] as Map<String, dynamic>) : null,
      freeMin: (json['free_min'] as num?)?.toDouble(),
      status: (json['status'] as String?) ?? 'unknown',
      leaveBy: json['leave_by'] as String?,
      today: [for (final t in (json['today'] as List? ?? const [])) ClassTime.fromJson(t as Map<String, dynamic>)],
      notes: [for (final n in (json['notes'] as List? ?? const [])) n as String],
      reminders: [
        for (final r in (json['reminders'] as List? ?? const [])) Reminder.fromJson(r as Map<String, dynamic>)
      ],
      banner: json['banner'] is Map<String, dynamic> ? LeaveBanner.fromJson(json['banner'] as Map<String, dynamic>) : null,
    );
  }
}
