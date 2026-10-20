/// Readers for the fields of a class (days, times, course, room, dates) in text recognized from a picture.
/// Each repairs the mistakes recognition makes in that kind of field and says how sure it is of the result.
library;

/// How a value was got: read as it is, repaired (a letter read as a digit), or guessed.
enum Certainty {
  exact,
  repaired,
  guessed;

  Certainty orWorse(Certainty other) => index >= other.index ? this : other;
}

String normalizeText(String text) => text
    .replaceAll(RegExp('[\u2010-\u2015\u2212]'), '-')
    .replaceAll('\u00a0', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const _digitish = {
  'O': '0',
  'o': '0',
  'Q': '0',
  'D': '0',
  'l': '1',
  'I': '1',
  '|': '1',
  'i': '1',
  'S': '5',
  'B': '8',
  'Z': '2',
};

/// Letters recognition reads for digits, turned back into digits.
String fixDigits(String text) => text.split('').map((c) => _digitish[c] ?? c).join();

bool _hasConfusable(String text) => RegExp(r'[^0-9]').hasMatch(text);

// ---- times ----------------------------------------------------------------------------------------------------

/// A start and end time as `HH:mm`, and where in the text they were found.
class TimeRange {
  const TimeRange(this.start, this.end, this.certainty, this.from, this.to);

  final String start;
  final String end;
  final Certainty certainty;
  final int from;
  final int to;
}

const _hour = r'(?:[0-9][0-9OolI|]?|[OolI|][0-9]|[lI|])';
const _minute = r'[0-9OolI|SB]{2}';
final _clockWithColon = RegExp(
  '(?<![A-Za-z0-9])($_hour)\\s*([:.;])\\s*($_minute)(?![0-9])(?:\\s*([AaPp])\\.?\\s*[Mm]\\b\\.?)?',
);
final _clockWithoutColon = RegExp(r'(?<![A-Za-z0-9:.;])([0-9]{1,2})\s*([AaPp])\.?\s*[Mm]\b\.?');
final _rangeSeparator = RegExp(
  '^[\\s~_.|,;\u2016]*(?:[-\u2010-\u2015\u2212]+|to|until|thru|through)?[\\s~_.|,;\u2016]*\$',
  caseSensitive: false,
);

class _Clock {
  const _Clock(this.hour, this.minute, this.pm, this.padded, this.repaired, this.from, this.to);

  final int hour;
  final int minute;
  final bool? pm;
  final bool padded;
  final bool repaired;
  final int from;
  final int to;

  int minutes(bool isPm) => (hour % 12 + (isPm ? 12 : 0)) * 60 + minute;
}

List<_Clock> _clocks(String text) {
  final found = <_Clock>[];
  for (final m in _clockWithColon.allMatches(text)) {
    final hourText = m.group(1)!;
    final minuteText = m.group(3)!;
    final hour = int.tryParse(fixDigits(hourText));
    final minute = int.tryParse(fixDigits(minuteText));
    if (hour == null || minute == null || minute > 59 || hour > 24) continue;
    final meridiem = m.group(4);
    // a dot or semicolon for the colon is only believed beside AM or PM: `5.50` is a price or a mark, not a time
    if (m.group(2) != ':' && meridiem == null) continue;
    found.add(
      _Clock(
        hour,
        minute,
        meridiem == null ? null : meridiem.toLowerCase() == 'p',
        hourText.length == 2 && hourText.startsWith('0'),
        _hasConfusable(hourText) || _hasConfusable(minuteText),
        m.start,
        m.end,
      ),
    );
  }
  for (final m in _clockWithoutColon.allMatches(text)) {
    if (found.any((c) => m.start < c.to && c.from < m.end)) continue;
    final hour = int.parse(m.group(1)!);
    if (hour < 1 || hour > 12) continue;
    found.add(_Clock(hour, 0, m.group(2)!.toLowerCase() == 'p', false, false, m.start, m.end));
  }
  return found..sort((a, b) => a.from.compareTo(b.from));
}

String _hhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// The first start and end time in [text], such as `8:00AM - 9:05AM`, `1:20-2:25 PM` or `13:20 - 14:25`.
/// A meridiem that is missing is worked out from the other time, or guessed from school hours.
TimeRange? findTimeRange(String text) {
  final clocks = _clocks(text);
  for (var i = 0; i + 1 < clocks.length; i++) {
    final a = clocks[i];
    final b = clocks[i + 1];
    if (!_rangeSeparator.hasMatch(text.substring(a.to, b.from))) continue;
    final range = _resolve(a, b);
    if (range != null) return range;
  }
  return null;
}

TimeRange? _resolve(_Clock a, _Clock b) {
  var certainty = a.repaired || b.repaired ? Certainty.repaired : Certainty.exact;
  int start;
  int end;
  if (a.pm == null && b.pm == null) {
    final twentyFour = a.hour > 12 || b.hour > 12 || a.hour == 0 || b.hour == 0 || a.padded || b.padded;
    if (twentyFour) {
      start = a.hour * 60 + a.minute;
      end = b.hour * 60 + b.minute;
    } else {
      bool schoolDayPm(int hour) => hour == 12 || hour < 8;
      start = a.minutes(schoolDayPm(a.hour));
      end = b.minutes(schoolDayPm(b.hour));
      certainty = Certainty.guessed;
    }
  } else {
    var aPm = a.pm ?? b.pm!;
    var bPm = b.pm ?? a.pm!;
    if (a.hour < 1 || a.hour > 12 || b.hour < 1 || b.hour > 12) return null;
    if (a.pm == null && a.minutes(aPm) >= b.minutes(bPm)) aPm = !aPm;
    if (b.pm == null && b.minutes(bPm) <= a.minutes(aPm)) bPm = !bPm;
    if (a.pm == null || b.pm == null) certainty = certainty.orWorse(Certainty.repaired);
    start = a.minutes(aPm);
    end = b.minutes(bPm);
  }
  final length = end - start;
  if (start < 0 || end >= 24 * 60 || length < 10 || length > 14 * 60) return null;
  return TimeRange(_hhmm(start), _hhmm(end), certainty, a.from, b.to);
}

/// True if [text] has a time in it, even one with no partner.
bool hasClock(String text) => _clocks(text).isNotEmpty;

/// A time on its own, where its partner was not read (`MWF 1:20 PM -` with the end time lost).
class LoneTime {
  const LoneTime(this.time, this.from, this.to);

  final String time;
  final int from;
  final int to;
}

/// The only time in [text], as `HH:mm`, or null if there is none or more than one. With no AM or PM it is guessed
/// from school hours.
LoneTime? findLoneTime(String text) {
  final clocks = _clocks(text);
  if (clocks.length != 1) return null;
  final c = clocks.single;
  final twentyFour = c.hour > 12 || c.hour == 0 || c.padded;
  if (c.pm == null && !twentyFour) {
    final pm = c.hour == 12 || c.hour < 8;
    return LoneTime(_hhmm(c.minutes(pm)), c.from, c.to);
  }
  if (c.pm != null && (c.hour < 1 || c.hour > 12)) return null;
  final minutes = c.pm == null ? c.hour * 60 + c.minute : c.minutes(c.pm!);
  if (minutes >= 24 * 60) return null;
  return LoneTime(_hhmm(minutes), c.from, c.to);
}

// ---- days -----------------------------------------------------------------------------------------------------

/// Weekdays (0 = Monday) found in some text, and where.
class DaysMatch {
  const DaysMatch(this.days, this.certainty, this.from, this.to);

  final List<int> days;
  final Certainty certainty;
  final int from;
  final int to;
}

const _dayNames = {
  'monday': 0,
  'mon': 0,
  'tuesday': 1,
  'tues': 1,
  'tue': 1,
  'wednesday': 2,
  'wed': 2,
  'thursday': 3,
  'thurs': 3,
  'thur': 3,
  'thu': 3,
  'friday': 4,
  'fri': 4,
  'saturday': 5,
  'sat': 5,
  'sunday': 6,
  'sun': 6,
};
const _dayCodes = {'mo': 0, 'tu': 1, 'we': 2, 'th': 3, 'fr': 4, 'sa': 5, 'su': 6};
const _dayLetters = {'M': 0, 'T': 1, 'W': 2, 'R': 3, 'F': 4, 'S': 5, 'U': 6};
const _misreadCodes = {'m0': 0, 'tn': 3};
// a day code whose first letter was lost: the second letters that belong to only one day
const _lostFirstLetter = {'o': 0, 'e': 2, 'h': 3, 'r': 4, 'a': 5};

(List<int>, Certainty)? _dayWord(String raw) {
  final word = raw.replaceAll(RegExp(r'[.,;:]+$'), '');
  if (word.isEmpty || word.length > 14) return null;
  final named = _dayNames[word.toLowerCase()];
  if (named != null) return ([named], Certainty.exact);
  if (!RegExp(r'^[A-Za-z0]+$').hasMatch(word)) return null;
  final upper = word == word.toUpperCase();
  final days = <int>[];
  var certainty = Certainty.exact;
  var i = 0;
  while (i < word.length) {
    final pair = i + 1 < word.length ? word.substring(i, i + 2).toLowerCase() : '';
    final code = _dayCodes[pair];
    if (code != null) {
      days.add(code);
      if (!upper && word[i] != word[i].toUpperCase()) certainty = Certainty.guessed;
      i += 2;
    } else if (_misreadCodes[pair] != null) {
      days.add(_misreadCodes[pair]!);
      certainty = certainty.orWorse(Certainty.repaired);
      i += 2;
    } else if (_dayLetters.containsKey(word[i])) {
      days.add(_dayLetters[word[i]]!);
      i += 1;
    } else if (i == word.length - 1 && days.isNotEmpty && _lostFirstLetter.containsKey(word[i])) {
      days.add(_lostFirstLetter[word[i]]!);
      certainty = Certainty.guessed;
      i += 1;
    } else {
      return null;
    }
  }
  if (days.toSet().length != days.length) return null;
  return (days, certainty);
}

final _wordSpan = RegExp(r'[^\s,/&]+');
final _dayJoiner = RegExp(r'^(?:\s|,|/|&|and)*$', caseSensitive: false);

/// The group of weekdays in [text] that is nearest to character [near] (the first if [near] is null): `MWF`,
/// `TuTh`, `MoWeFr`, `M W F`, `Mon, Wed`, `Tuesday`.
DaysMatch? findDays(String text, {int? near}) {
  final groups = <DaysMatch>[];
  int? from;
  int? to;
  var days = <int>[];
  var certainty = Certainty.exact;
  void close() {
    if (from != null && days.isNotEmpty && days.toSet().length == days.length) {
      groups.add(DaysMatch(List.of(days)..sort(), certainty, from!, to!));
    }
    from = null;
    days = [];
    certainty = Certainty.exact;
  }

  for (final m in _wordSpan.allMatches(text)) {
    final word = m.group(0)!;
    if (from != null && word.toLowerCase() == 'and') continue;
    final parsed = _dayWord(word);
    if (parsed == null) {
      close();
      continue;
    }
    if (from != null && !_dayJoiner.hasMatch(text.substring(to!, m.start))) close();
    from ??= m.start;
    to = m.end;
    days.addAll(parsed.$1);
    certainty = certainty.orWorse(parsed.$2);
  }
  close();
  if (groups.isEmpty) return null;
  if (near == null) return groups.first;
  int gap(DaysMatch g) => near < g.from ? g.from - near : (near > g.to ? near - g.to : 0);
  return groups.reduce((best, g) => gap(g) < gap(best) ? g : best);
}

// ---- courses, sections, components ----------------------------------------------------------------------

class CourseMatch {
  const CourseMatch(this.code, this.certainty, this.from, this.to);

  final String code;
  final Certainty certainty;
  final int from;
  final int to;
}

final _courseCode = RegExp(r'(?<![A-Za-z0-9])([A-Z][A-Z&]{1,4})\s?([0-9]{1,3}[A-Z]{0,2})(?![A-Za-z0-9])');
final _numberEndingInO = RegExp(r'^([0-9]{1,2})(O{1,2})$');
final _courseCodeMisread = RegExp(r'^\s*([A-Z]{2,5}?)\s?([OIl]{1,3})(?![A-Za-z0-9])');

/// The first course code in [text] (`CSE 101`, `MATH 19A`, `BME 160L`).
CourseMatch? findCourse(String text) {
  final m = _courseCode.firstMatch(text);
  if (m != null) {
    // no course number ends in the letter O, so `2O` is `20`
    final zeros = _numberEndingInO.firstMatch(m.group(2)!);
    if (zeros != null) {
      return CourseMatch(
        '${m.group(1)} ${zeros.group(1)}${'0' * zeros.group(2)!.length}',
        Certainty.repaired,
        m.start,
        m.end,
      );
    }
    return CourseMatch('${m.group(1)} ${m.group(2)}', Certainty.exact, m.start, m.end);
  }
  // `BIOLI`: a capital I read at the end is really the digit 1, as in `BIOL 1`
  final misread = _courseCodeMisread.firstMatch(text);
  final number = misread == null ? null : int.tryParse(fixDigits(misread.group(2)!));
  if (misread == null || number == null || number < 1) return null;
  return CourseMatch('${misread.group(1)} $number', Certainty.guessed, misread.start, misread.end);
}

const _components = {
  'lecture': 'Lecture',
  'lec': 'Lecture',
  'lect': 'Lecture',
  'discussion': 'Discussion',
  'disc': 'Discussion',
  'dis': 'Discussion',
  'laboratory': 'Laboratory',
  'lab': 'Laboratory',
  'seminar': 'Seminar',
  'sem': 'Seminar',
  'studio': 'Studio',
  'tutorial': 'Tutorial',
  'recitation': 'Recitation',
};

/// The kind of meeting named in [text], in the words the schedule page uses (`Lecture`, `Discussion`).
String? findComponent(String text) {
  for (final m in RegExp(r'[A-Za-z]+').allMatches(text)) {
    final component = _components[m.group(0)!.toLowerCase()];
    if (component != null) return component;
  }
  return null;
}

/// How many single-character edits turn [a] into [b].
int editDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final row = [i, ...List<int>.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      final change = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      row[j] = [change, previous[j] + 1, row[j - 1] + 1].reduce((x, y) => x < y ? x : y);
    }
    previous = row;
  }
  return previous[b.length];
}

/// The component a table cell most likely holds, even if a letter was misread (`Lectre`), or null.
String? closestComponent(String cell) {
  final word = cell.trim().toLowerCase();
  if (word.length < 3) return null;
  final exact = _components[word];
  if (exact != null) return exact;
  String? best;
  var bestDistance = 3;
  for (final entry in _components.entries.where((e) => e.key.length >= 6)) {
    final distance = editDistance(word, entry.key);
    if (distance < bestDistance && distance <= entry.key.length ~/ 4) {
      best = entry.value;
      bestDistance = distance;
    }
  }
  return best;
}

/// `enrolled`, `dropped` or `waitlisted`, from the words near a course's title. A letter of the word may be misread.
String courseStatus(Iterable<String> words) {
  for (final raw in words) {
    final w = raw.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    if (w.length < 4) continue;
    if (w == 'wait' || w == 'waiting' || (w.length >= 8 && editDistance(w, 'waitlisted') <= 1)) return 'waitlisted';
    if (w.length >= 6 && editDistance(w, 'dropped') <= 1) return 'dropped';
    if (w.length >= 6 && editDistance(w, 'enrolled') <= 2) return 'enrolled';
  }
  return 'enrolled';
}

/// A section such as `01` or `01A` that is the whole of [cell], after repairing letters read as digits.
String? sectionOfCell(String cell) {
  // a stray O or 0 in front (`O01A`) is noise
  final m = RegExp(r'^(?:[Oo0](?=[0-9OoQDIl|]{2}[A-Za-z]$))?([0-9OoQDIl|]{2})([A-Za-z]?)$').firstMatch(cell.trim());
  if (m == null) return null;
  final digits = fixDigits(m.group(1)!);
  return int.tryParse(digits) == null ? null : '$digits${m.group(2)!.toUpperCase()}';
}

final _sectionThenComponent = RegExp(r'(?<![A-Za-z0-9])(\d{2}[A-Z]?)\s*[-/]\s*([A-Za-z]{3,10})\b');
final _componentThenSection = RegExp(r'\b([A-Za-z]{3,10})\s*[-/]?\s*(\d{2}[A-Z]?)(?![0-9:.])');

/// A section and the kind of meeting written together: `01-LEC`, `01A DIS`, `LEC 01`.
({String section, String component})? findSectionAndComponent(String text) {
  for (final m in _sectionThenComponent.allMatches(text)) {
    final component = _components[m.group(2)!.toLowerCase()];
    if (component != null) return (section: m.group(1)!, component: component);
  }
  for (final m in _componentThenSection.allMatches(text)) {
    final component = _components[m.group(1)!.toLowerCase()];
    if (component != null) return (section: m.group(2)!, component: component);
  }
  return null;
}

/// A section named in running text: `Section 01A`, `Sec 02`, `(01B)`.
String? findSection(String text) {
  final m = RegExp(r'(?:\bsec(?:tion)?\.?\s*|\()(\d{2}[A-Z]?)\b', caseSensitive: false).firstMatch(text);
  return m?.group(1)!.toUpperCase();
}

// ---- dates ---------------------------------------------------------------------------------------------------

final _usDate = RegExp(r'(?<![0-9])([0-9OolI|]{1,2})\s*[/\\]\s*([0-9OolI|]{1,2})\s*[/\\]\s*([0-9OolI|SB]{4})(?![0-9])');

/// Dates written `09/24/2026`, as `2026-09-24`.
List<String> findDates(String text) {
  final dates = <String>[];
  for (final m in _usDate.allMatches(text)) {
    final month = int.tryParse(fixDigits(m.group(1)!));
    final day = int.tryParse(fixDigits(m.group(2)!));
    final year = int.tryParse(fixDigits(m.group(3)!));
    if (month == null || day == null || year == null || month < 1 || month > 12 || day < 1 || day > 31) continue;
    if (year < 2000 || year > 2100) continue;
    final date = DateTime.utc(year, month, day);
    if (date.month != month) continue;
    dates.add(
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
  }
  return dates;
}

// ---- rooms ---------------------------------------------------------------------------------------------------

final _glyph = RegExp(r'^(?:[•·●○◦▪▫■□*@>▶►|]+|[OQ0@])\s+(?=[A-Za-z0-9])');
final _label = RegExp(r'^(?:room|rm|location|loc|where|building)\s*:\s*', caseSensitive: false);

final _lostL = RegExp(r'(?<=[A-Za-z])I(?=[a-z])');

/// A room as written on the page, without the pin or bullet drawn before it or a label such as `Room:`.
String cleanRoom(String text) {
  // a capital I between letters is an l the phone could not tell from it: `CIrm` is `Clrm`
  var room = normalizeText(text.replaceAll('\u2016', ' ')).replaceAll(_lostL, 'l');
  room = room.replaceFirst(_glyph, '').replaceFirst(_label, '');
  room = room.replaceAll(RegExp(r'[\s,;:|.\-]+$'), '').trim();
  return room.startsWith('(') && room.endsWith(')') ? room.substring(1, room.length - 1).trim() : room;
}

final _online = RegExp(r'^(?:(?:online|remote|zoom|asynchronous|async)\b|web$)', caseSensitive: false);
final _tba = RegExp(r'^(?:tba|tbd|to be announced|no room)$', caseSensitive: false);

/// True for `Online` and `TBA`, which are places to be but not rooms.
bool isNoRoom(String text) => _online.hasMatch(text.trim()) || _tba.hasMatch(text.trim());

final _placeWord = RegExp(
  r'\b(?:hall|auditorium|theat(?:er|re)|library|center|centre|commons|gym|gymnasium|annex|building|bldg)\b',
  caseSensitive: false,
);

/// True if [text] could be a room: a building and a number (`Kresge Acad 3201`, `BE 152`), a named place
/// (`Humanities Lecture Hall`), `Online` or `TBA`.
bool looksLikeRoom(String text) {
  final room = cleanRoom(text);
  if (room.isEmpty || room.length > 44) return false;
  if (isNoRoom(room)) return true;
  if (hasClock(room) || findDates(room).isNotEmpty) return false;
  if (!RegExp(r'[A-Za-z]{2}').hasMatch(room)) return false;
  return RegExp(r'[0-9]').hasMatch(room) || (room.contains(' ') && _placeWord.hasMatch(room));
}
