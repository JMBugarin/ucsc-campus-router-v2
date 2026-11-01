import '../../../campus/campus.dart';
import '../../../core/format.dart';
import '../meeting.dart';
import 'clean.dart';

final _course = RegExp(r'(?<course>[A-Z][A-Z&]{1,5} \d{1,3}[A-Z]{0,2}) - (?<title>.+?) Status Units');
final _status = RegExp(r'Status Units Grading Grade Deadlines (?<status>Enrolled|Dropped|Waiting|Wait Listed)');
final _row = RegExp(
  r'(?<nbr>\d{4,5}) (?<section>\d{2}[A-Z]?) (?<component>[A-Za-z]+) '
  r'(?<days>(?:Mo|Tu|We|Th|Fr|Sa|Su)+) '
  r'(?<t1>\d{1,2}:\d{2}\s?[AP]M) ?[-–—]? ?(?<t2>\d{1,2}:\d{2}\s?[AP]M) '
  r'(?<rest>.*?)\s*(?<d1>\d{2}/\d{2}/\d{4}) ?- ?(?<d2>\d{2}/\d{2}/\d{4})',
);
final _rowStart = RegExp(r'\b\d{4,5} \d{2}[A-Z]? (?:Lecture|Discussion|Laboratory|Lab|Seminar|Studio|Section)\b');

String _to24h(String text) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})([AP]M)$').firstMatch(text.replaceAll(' ', ''));
  final hour = m == null ? 0 : int.parse(m[1]!);
  final minute = m == null ? 99 : int.parse(m[2]!);
  if (m == null || hour < 1 || hour > 12 || minute > 59) throw FormatException("'$text' isn't a time");
  final h24 = hour % 12 + (m[3] == 'PM' ? 12 : 0);
  return '${h24.toString().padLeft(2, '0')}:${m[2]}';
}

String _usDate(String text) {
  final p = text.split('/');
  final month = int.parse(p[0]), day = int.parse(p[1]), year = int.parse(p[2]);
  final d = DateTime.utc(year, month, day);
  if (d.year != year || d.month != month || d.day != day) throw FormatException("'$text' isn't a date");
  return '${p[2]}-${p[0]}-${p[1]}';
}

/// Reads a schedule copied from MyUCSC's Class Schedule page. Line breaks do not matter. Dropped and
/// waitlisted courses are left out, and a row that looks like a class but cannot be read is named in the notes.
({List<Meeting> meetings, List<String> notes}) parsePasted(String text, Campus campus) {
  if (text.trim().isEmpty) throw const ScheduleError('paste your schedule first');
  if (text.length > maxPastedChars) throw const ScheduleError('that text is too long to be a schedule');
  final flat = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

  final headers = _course.allMatches(flat).toList();
  final statuses = _status.allMatches(flat).toList();
  final meetings = <Meeting>[];
  final notes = <String>[];
  final claimed = <(int, int)>[];

  for (final m in _row.allMatches(flat)) {
    claimed.add((m.start, m.end));
    final before = headers.where((h) => h.start < m.start).toList();
    final course = before.isEmpty ? 'Class ${m.namedGroup('nbr')}' : before.last.namedGroup('course')!;
    final title = before.isEmpty ? '' : before.last.namedGroup('title')!;
    var status = 'Enrolled';
    if (before.isNotEmpty) {
      final after = statuses.where((s) => s.start > before.last.start && s.start < m.start).toList();
      if (after.isNotEmpty) status = after.last.namedGroup('status')!;
    }
    if (status != 'Enrolled') {
      notes.add('Skipped $course (${status.toLowerCase()}).');
      continue;
    }
    final days = m.namedGroup('days')!;
    final (location, _) = campus.splitLocation(m.namedGroup('rest')!);
    try {
      meetings.add(cleanMeetingJson({
        'course': course,
        'title': title,
        'section': m.namedGroup('section'),
        'component': m.namedGroup('component'),
        'class_nbr': m.namedGroup('nbr'),
        'days': [for (var i = 0; i < days.length; i += 2) dayCodes.indexOf(days.substring(i, i + 2))],
        'start': _to24h(m.namedGroup('t1')!),
        'end': _to24h(m.namedGroup('t2')!),
        'location': location,
        'start_date': _usDate(m.namedGroup('d1')!),
        'end_date': _usDate(m.namedGroup('d2')!),
      }));
    } on ScheduleError catch (e) {
      notes.add("Couldn't read $course ${m.namedGroup('component')}: ${e.message}.");
    } on FormatException {
      notes.add("Couldn't read $course ${m.namedGroup('component')}: a time or date isn't valid.");
    }
  }

  for (final m in _rowStart.allMatches(flat)) {
    if (!claimed.any((c) => c.$1 <= m.start && m.start < c.$2)) {
      final end = m.start + 50 > flat.length ? flat.length : m.start + 50;
      notes.add('Couldn\'t read a row starting "${flat.substring(m.start, end)}".');
    }
  }
  if (meetings.isEmpty && notes.isEmpty) {
    notes.add("I couldn't find any classes in that text. Copy the whole Class Schedule page, or add classes by hand.");
  }
  return (meetings: meetings, notes: notes);
}
