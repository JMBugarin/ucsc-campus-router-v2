import '../meeting.dart';

/// A schedule or meeting that cannot be used. The message is safe to show.
class ScheduleError implements Exception {
  const ScheduleError(this.message);

  final String message;

  @override
  String toString() => message;
}

const maxMeetings = 60;
const maxSkipDates = 60;
const maxPastedChars = 100000;

String _text(Map<String, dynamic> raw, String key, int maxLen, {bool required = false}) {
  final value = raw[key] ?? '';
  if (value is! String && value is! int) throw ScheduleError('$key must be text');
  final text = value.toString().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  if (required && text.isEmpty) throw ScheduleError('$key is required');
  if (text.length > maxLen) throw ScheduleError('$key is too long');
  return text;
}

String _clock(Object? value, String key) {
  final m = value is String ? RegExp(r'^(\d{2}):(\d{2})(?::(\d{2}))?$').firstMatch(value) : null;
  if (m != null && int.parse(m[1]!) < 24 && int.parse(m[2]!) < 60 && int.parse(m[3] ?? '0') < 60) {
    return '${m[1]}:${m[2]}';
  }
  throw ScheduleError('$key must look like 14:40');
}

String _day(Object? value, String key) {
  final m = value is String ? RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value) : null;
  if (m != null) {
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    final date = DateTime.utc(y, mo, d);
    if (y > 0 && date.year == y && date.month == mo && date.day == d) return value as String;
  }
  throw ScheduleError('$key must look like 2026-09-24');
}

/// Checks one meeting and returns a tidy copy, or throws [ScheduleError].
Meeting cleanMeetingJson(Map<String, dynamic> raw) {
  final days = raw['days'] ?? const [];
  if (days is! List || !days.every((d) => d is int && d >= 0 && d <= 6)) {
    throw const ScheduleError('days must be a list of weekday numbers, 0 (Monday) to 6 (Sunday)');
  }
  final skip = raw['skip_dates'] ?? const [];
  if (skip is! List || skip.length > maxSkipDates) {
    throw const ScheduleError('skip_dates must be a list of at most $maxSkipDates dates');
  }
  final course = _text(raw, 'course', 40, required: true);
  final title = _text(raw, 'title', 80);
  final section = _text(raw, 'section', 10);
  final component = _text(raw, 'component', 30);
  final classNbr = _text(raw, 'class_nbr', 10);
  final sortedDays = (<int>{...days.cast<int>()}).toList()..sort();
  final start = _clock(raw['start'], 'start');
  final end = _clock(raw['end'], 'end');
  final location = _text(raw, 'location', 80);
  final startDate = _day(raw['start_date'], 'start_date');
  final endDate = _day(raw['end_date'], 'end_date');
  final skipDates = ({for (final d in skip) _day(d, 'skip_dates')}).toList()..sort();
  if (end.compareTo(start) <= 0) throw ScheduleError('$course: the end time must be after the start time');
  if (endDate.compareTo(startDate) < 0) throw ScheduleError('$course: the end date is before the start date');
  if (sortedDays.isEmpty && startDate != endDate) {
    throw ScheduleError('$course: pick the days it meets, or use one date for a one-off event');
  }
  return Meeting(
    course: course,
    title: title,
    section: section,
    component: component,
    classNbr: classNbr,
    days: sortedDays,
    start: start,
    end: end,
    location: location,
    startDate: startDate,
    endDate: endDate,
    skipDates: skipDates,
  );
}

Meeting cleanMeeting(Meeting meeting) => cleanMeetingJson(meeting.toJson());

List<Meeting> cleanSchedule(List<Meeting> meetings) {
  if (meetings.length > maxMeetings) throw const ScheduleError('too many meetings (the limit is $maxMeetings)');
  return [for (final m in meetings) cleanMeeting(m)];
}
