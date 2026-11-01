import 'package:timezone/timezone.dart' as tz;

import '../../../campus/terms.dart';
import '../../../core/pacific.dart';
import '../meeting.dart';
import 'clean.dart';

const maxIcsChars = 1000000;
const maxEvents = 500;
const defaultWeeks = 16;
const _maxExpansionDays = 3 * 366;

const _zoneAliases = {
  'Pacific Standard Time': 'America/Los_Angeles',
  'Pacific Daylight Time': 'America/Los_Angeles',
  'US/Pacific': 'America/Los_Angeles',
  'PST8PDT': 'America/Los_Angeles',
};
const _dayCodes = {
  'MO': 0,
  'TU': 1,
  'WE': 2,
  'TH': 3,
  'FR': 4,
  'SA': 5,
  'SU': 6,
};
final _component = RegExp(
  r'^(?<course>.*?)[\s:\-\u2013\u2014]+(?<component>Lecture|Discussion|Laboratory|Lab|Seminar|Section|Studio)\b',
  caseSensitive: false,
);
final _duration = RegExp(
  r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
);

class _Prop {
  const _Prop(this.name, this.params, this.value);

  final String name;
  final Map<String, String> params;
  final String value;
}

_Prop? _splitProperty(String line) {
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (ch == ':' && !inQuotes) {
      final parts = line.substring(0, i).split(';');
      final params = <String, String>{};
      for (final part in parts.skip(1)) {
        final eq = part.indexOf('=');
        final key = (eq < 0 ? part : part.substring(0, eq)).toUpperCase();
        final value = eq < 0 ? '' : part.substring(eq + 1);
        params[key] = value.replaceAll(RegExp(r'^"+|"+$'), '');
      }
      return _Prop(parts.first.toUpperCase(), params, line.substring(i + 1));
    }
  }
  return null;
}

String _unescape(String text) => text.replaceAllMapped(
  RegExp(r'\\(.)'),
  (m) => 'nN'.contains(m[1]!) ? '\n' : m[1]!,
);

List<List<_Prop>> _readEvents(String text) {
  final lines = text
      .replaceAll(RegExp(r'\r?\n[ \t]'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final events = <List<_Prop>>[];
  List<_Prop>? current;
  var nested = 0;
  for (final line in lines) {
    final prop = _splitProperty(line.trim());
    if (prop == null) continue;
    if (prop.name == 'BEGIN' && prop.value.toUpperCase() == 'VEVENT') {
      current = [];
      nested = 0;
    } else if (current == null) {
      continue;
    } else if (prop.name == 'BEGIN') {
      nested++;
    } else if (prop.name == 'END' && prop.value.toUpperCase() == 'VEVENT') {
      events.add(current);
      current = null;
    } else if (prop.name == 'END') {
      nested--;
    } else if (nested == 0) {
      current.add(prop);
    }
  }
  return events;
}

/// A calendar time in Pacific time, or a plain date for an all-day value.
class _When {
  const _When.at(tz.TZDateTime this.at) : day = null;
  const _When.date(DateTime this.day) : at = null;

  final tz.TZDateTime? at;
  final DateTime? day;
}

DateTime _utcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _ymd(String s) {
  final y = int.parse(s.substring(0, 4)),
      m = int.parse(s.substring(4, 6)),
      d = int.parse(s.substring(6, 8));
  final date = DateTime.utc(y, m, d);
  return date.year == y && date.month == m && date.day == d ? date : null;
}

class _Reader {
  final notes = <String>[];

  tz.Location zone(String name) {
    final home = pacific; // also loads the time zone database
    try {
      return tz.getLocation(_zoneAliases[name] ?? name);
    } on Object {
      final note =
          "The calendar uses a time zone I don't know ($name), so I treated those times as Pacific time.";
      if (!notes.contains(note)) notes.add(note);
      return home;
    }
  }

  _When? moment(
    String raw,
    Map<String, String> params, [
    tz.Location? defaultZone,
  ]) {
    final value = raw.trim();
    if (params['VALUE'] == 'DATE' || RegExp(r'^\d{8}$').hasMatch(value)) {
      if (!RegExp(r'^\d{8}$').hasMatch(value)) return null;
      final d = _ymd(value);
      return d == null ? null : _When.date(d);
    }
    final m = RegExp(r'^(\d{8})T(\d{2})(\d{2})(\d{2})(Z?)$').firstMatch(value);
    if (m == null) return null;
    final date = _ymd(m[1]!);
    final h = int.parse(m[2]!), mi = int.parse(m[3]!), s = int.parse(m[4]!);
    if (date == null || h > 23 || mi > 59 || s > 60) return null;
    if (m[5]!.isNotEmpty) {
      return _When.at(
        tz.TZDateTime.from(
          DateTime.utc(date.year, date.month, date.day, h, mi, s),
          pacific,
        ),
      );
    }
    final loc = params.containsKey('TZID')
        ? zone(params['TZID']!)
        : (defaultZone ?? pacific);
    return _When.at(
      tz.TZDateTime.from(
        tz.TZDateTime(loc, date.year, date.month, date.day, h, mi, s),
        pacific,
      ),
    );
  }
}

Duration? _parseDuration(String value) {
  final m = _duration.firstMatch(value.trim());
  if (m == null ||
      [for (var i = 2; i <= 6; i++) m[i]].every((g) => g == null)) {
    return null;
  }
  int g(int i) => int.parse(m[i] ?? '0');
  final span = Duration(
    days: g(2) * 7 + g(3),
    hours: g(4),
    minutes: g(5),
    seconds: g(6),
  );
  return m[1] == '-' ? -span : span;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _title(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

Meeting? _eventToMeeting(List<_Prop> props, Term? term, _Reader reader) {
  final notes = reader.notes;
  _Prop? first(String name) {
    for (final p in props) {
      if (p.name == name) return p;
    }
    return null;
  }

  final summaryRaw = first('SUMMARY');
  final summary = _unescape(
    summaryRaw?.value ?? '',
  ).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  final name = summary.isEmpty ? 'Event' : summary;
  if (first('STATUS')?.value.trim().toUpperCase() == 'CANCELLED') {
    notes.add('Skipped "$name" (cancelled).');
    return null;
  }
  if (first('RECURRENCE-ID') != null) {
    notes.add(
      'Skipped a changed single day of "$name"; edit that day by hand if you need it.',
    );
    return null;
  }

  final startProp = first('DTSTART');
  final startWhen = startProp == null
      ? null
      : reader.moment(startProp.value, startProp.params);
  if (startWhen == null) {
    notes.add('Skipped "$name" (couldn\'t read when it starts).');
    return null;
  }
  final start = startWhen.at;
  if (start == null) {
    notes.add('Skipped "$name" (an all-day event, not a class).');
    return null;
  }
  final startZone = startProp!.params['TZID'] != null
      ? reader.zone(startProp.params['TZID']!)
      : null;

  tz.TZDateTime? end;
  final endProp = first('DTEND');
  final durationProp = first('DURATION');
  if (endProp != null) {
    end = reader.moment(endProp.value, endProp.params, startZone)?.at;
  } else if (durationProp != null &&
      _parseDuration(durationProp.value) != null) {
    end = start.add(_parseDuration(durationProp.value)!);
  }
  if (end == null || !end.isAfter(start)) {
    notes.add('Skipped "$name" (couldn\'t read when it ends).');
    return null;
  }
  if (_iso(end) != _iso(start)) {
    notes.add('Skipped "$name" (it runs past midnight, so it isn\'t a class).');
    return null;
  }

  var days = <int>[];
  final startDay = _utcDay(start);
  var startDate = startDay;
  var endDate = startDay;
  var skip = <String>[];
  final rrule = first('RRULE');
  if (rrule != null) {
    final rule = <String, String>{};
    for (final part in rrule.value.split(';')) {
      final eq = part.indexOf('=');
      rule[(eq < 0 ? part : part.substring(0, eq)).toUpperCase()] = eq < 0
          ? ''
          : part.substring(eq + 1);
    }
    final interval = rule['INTERVAL'] ?? '1';
    if (rule['FREQ'] != 'WEEKLY' || interval != '1') {
      notes.add(
        'Skipped "$name" (it repeats ${(rule['FREQ'] ?? 'oddly').toLowerCase()}'
        '${interval == '1' ? '' : ' every $interval'}, and I only handle every week).',
      );
      return null;
    }
    final byday = (rule['BYDAY'] ?? '')
        .split(',')
        .where((d) => d.isNotEmpty)
        .toList();
    if (byday.any((d) => !_dayCodes.containsKey(d))) {
      notes.add(
        'Skipped "$name" (it repeats on days like \'the first Monday\', which I can\'t handle).',
      );
      return null;
    }
    days = ({for (final d in byday) _dayCodes[d]!}).toList()..sort();
    if (days.isEmpty) days = [start.weekday - 1];

    DateTime? until;
    final untilRaw = rule['UNTIL'];
    if (untilRaw != null && untilRaw.isNotEmpty) {
      final when = reader.moment(untilRaw, const {}, startZone);
      until = when == null
          ? null
          : (when.at != null ? _utcDay(when.at!) : when.day);
    }
    final count = int.tryParse(rule['COUNT'] ?? '');
    if (count != null && count > 0) {
      var seen = 0;
      var day = startDay;
      for (var i = 0; i < _maxExpansionDays; i++) {
        if (days.contains(day.weekday - 1)) {
          seen++;
          until = day;
          if (seen >= count) break;
        }
        day = day.add(const Duration(days: 1));
      }
    }
    if (until == null) {
      if (term != null) {
        final termEnd = _ymd(term.end.replaceAll('-', ''))!;
        until = termEnd.isAfter(startDay) ? termEnd : startDay;
        notes.add(
          '"$name" repeats with no end date, so I ended it with the term.',
        );
      } else {
        until = startDay.add(const Duration(days: defaultWeeks * 7));
        notes.add(
          '"$name" repeats with no end date, so I stopped it after $defaultWeeks weeks.',
        );
      }
    }
    endDate = until;

    for (final p in props) {
      if (p.name != 'EXDATE') continue;
      for (final item in p.value.split(',')) {
        final when = reader.moment(item, p.params, startZone);
        if (when != null) skip.add(_iso(when.at ?? when.day!));
      }
    }
    skip = [
      for (final d in skip)
        if (_iso(startDate).compareTo(d) <= 0 &&
            d.compareTo(_iso(endDate)) <= 0)
          d,
    ];
  }

  var location = _unescape(
    first('LOCATION')?.value ?? '',
  ).split('\n').first.split(',').first.trim();
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(location)) {
    location = 'Online';
  }
  final match = _component.firstMatch(name);
  final course = match != null ? match.namedGroup('course')!.trim() : name;
  final component = match != null ? _title(match.namedGroup('component')!) : '';

  try {
    final label = course.isEmpty ? name : course;
    return cleanMeetingJson({
      'course': label.length > 40 ? label.substring(0, 40) : label,
      'title': '',
      'section': '',
      'component': component,
      'class_nbr': '',
      'days': days,
      'start': '${_two(start.hour)}:${_two(start.minute)}',
      'end': '${_two(end.hour)}:${_two(end.minute)}',
      'location': location,
      'start_date': _iso(startDate),
      'end_date': _iso(endDate),
      'skip_dates': skip,
    });
  } on ScheduleError catch (e) {
    notes.add('Skipped "$name": ${e.message}.');
    return null;
  }
}

/// Reads the text of an `.ics` calendar file. Anything that cannot be represented faithfully (daily or
/// every-other-week repeats, a changed single day, all-day or overnight events, cancelled events) is left out
/// and named in the notes, never guessed.
({List<Meeting> meetings, List<String> notes}) parseIcs(
  String text, {
  Term? term,
}) {
  if (text.trim().isEmpty) {
    throw const ScheduleError('choose a calendar (.ics) file first');
  }
  if (text.length > maxIcsChars) {
    throw const ScheduleError('that calendar file is too large');
  }
  if (!text.toUpperCase().contains('BEGIN:VCALENDAR')) {
    throw const ScheduleError("that doesn't look like a calendar (.ics) file");
  }
  final reader = _Reader();
  final events = _readEvents(text);
  final meetings = <Meeting>[];
  final seen = <String>{};
  for (final props in events.take(maxEvents)) {
    final meeting = _eventToMeeting(props, term, reader);
    if (meeting == null) continue;
    final key = [
      meeting.course,
      meeting.component,
      meeting.days.join(','),
      meeting.start,
      meeting.end,
      meeting.location,
      meeting.startDate,
    ].join('|');
    if (seen.add(key)) meetings.add(meeting);
  }
  final notes = reader.notes.toSet().toList();
  if (events.length > maxEvents) {
    notes.add(
      'The calendar has ${events.length} events; I only read the first $maxEvents.',
    );
  }
  var kept = meetings;
  if (meetings.length > maxMeetings) {
    notes.add('Only the first $maxMeetings classes were kept.');
    kept = meetings.take(maxMeetings).toList();
  }
  if (kept.isEmpty && notes.isEmpty) {
    notes.add("I couldn't find any classes in that calendar.");
  }
  return (meetings: kept, notes: notes);
}
