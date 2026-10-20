import 'fields.dart';
import 'layout.dart';
import 'raw_row.dart';

const _roomLabels = {'room', 'location', 'where', 'building', 'place'};

bool _isRoomLabel(String text) => _roomLabels.contains(text.toLowerCase().replaceAll(RegExp('[^a-z]'), ''));

/// True if [next] carries on from [line]: the line ends with a time and a dash, and the next one starts with
/// the other time, as a cell that wraps does.
bool _continues(VisualLine line, VisualLine next, double h) {
  if (next.top - line.bottom > 1.8 * h) return false;
  final text = line.text.trimRight();
  return text.endsWith('-') && hasClock(text) && hasClock(next.text);
}

/// The words of a course line without its title (`MATH 30 - Seminar in Ethics` is the course `MATH 30`), so
/// that a word in the title is not taken for the kind of meeting. A dash before just `Lecture` is not a title.
String _withoutTitle(String text) {
  final course = findCourse(text);
  if (course == null) return text;
  final rest = text.substring(course.to);
  if (!RegExp(r'^\s*-\s+\S').hasMatch(rest)) return text;
  final words = rest.replaceFirst(RegExp(r'^\s*-\s+'), '').trim().split(RegExp(r'\s+'));
  return words.length <= 2 && findComponent(words.join(' ')) != null ? text : text.substring(0, course.to);
}

/// The lines of a picture and what has been read from them so far.
class _Page {
  _Page(this.lines, this.h, this.notes) : gap = 2.2 * h;

  final List<VisualLine> lines;
  final double h;
  final double gap;
  final List<String> notes;

  /// Lines already taken as a room or as the time of a class, so that the next card does not take one for its course.
  final taken = <int>{};
  String? lastCourse;
  var lastTimeLine = -100;

  /// The course for the time on line [i]: written before the time, or on one of the lines above, or the one
  /// the class before had. `skipped` is true for a course that is dropped or wait-listed.
  ({String text, String between, bool inherited, bool skipped}) courseFor(int i, String before, List<VisualLine> used) {
    var text = before;
    var between = '';
    var skipped = false;
    var inherited = false;
    if (findCourse(before) == null) {
      for (var k = i - 1; k >= 0 && i - k <= 8; k--) {
        if (taken.contains(k) || findTimeRange(lines[k].text) != null) break;
        if (findCourse(lines[k].text) == null) continue;
        text = lines[k].textWithBreaks(gap);
        between = lines.sublist(k + 1, i).map((l) => l.text).join(' ');
        used.add(lines[k]);
        final status = courseStatus(lines.sublist(k + 1, i).expand((l) => l.tokens).map((t) => t.text));
        if (status != 'enrolled') {
          notes.add('Skipped ${findCourse(text)!.code} ($status).');
          skipped = true;
        }
        break;
      }
      // a second time under the same course (`MWF ...` then `Th ...`) has no course line of its own
      if (findCourse(text) == null &&
          lastCourse != null &&
          lastTimeLine >= 0 &&
          i - lastTimeLine <= 3 &&
          lines[i].top - lines[lastTimeLine].bottom <= 6 * h) {
        text = lastCourse!;
        inherited = true;
      }
    }
    if (findCourse(text) != null) lastCourse = text;
    return (text: text, between: between, inherited: inherited, skipped: skipped);
  }

  /// The room for a time that ends on line [last]: in the cells after the time, under a `Room` label, or on
  /// the line below.
  String roomFor(int last, String after, List<VisualLine> used) {
    for (final cell in after.split(cellBreak)) {
      if (looksLikeRoom(cell)) return cleanRoom(cell);
    }
    for (var j = last + 1; j < lines.length && j <= last + 6; j++) {
      final next = lines[j];
      if (next.top - lines[j - 1].bottom > 3 * h || findTimeRange(next.text) != null) break;
      if (_isRoomLabel(next.text)) {
        if (j + 1 < lines.length && !taken.contains(j + 1) && looksLikeRoom(lines[j + 1].text)) {
          taken.addAll([j, j + 1]);
          used.add(lines[j + 1]);
          return cleanRoom(lines[j + 1].text);
        }
        break;
      }
      if (j == last + 1 && !taken.contains(j) && next.top - lines[last].bottom <= 2.4 * h && looksLikeRoom(next.text)) {
        taken.add(j);
        used.add(next);
        return cleanRoom(next.text);
      }
    }
    return '';
  }
}

/// Reads a class from every line that has a time range in it, whatever the page looks like: a row of a table
/// with no headings (`ART 20  MWF  1:20pm-2:25pm  Thimann Lec 001`), a card whose course is a line or two above
/// its time and whose room is the line below, or a card that labels each field.
List<RawRow> readLines(List<VisualLine> lines, double h, List<String> notes) {
  final page = _Page(lines, h, notes);
  final rows = <RawRow>[];
  var skip = -1;
  for (var i = 0; i < lines.length; i++) {
    if (i == skip) continue;
    var text = lines[i].textWithBreaks(page.gap);
    final used = <VisualLine>[lines[i]];
    var last = i;
    var range = findTimeRange(text);
    if (range == null && i + 1 < lines.length && _continues(lines[i], lines[i + 1], h)) {
      text = '$text ${lines[i + 1].textWithBreaks(page.gap)}';
      range = findTimeRange(text);
      if (range != null) {
        used.add(lines[i + 1]);
        last = i + 1;
        skip = last;
      }
    }
    if (range == null) continue;

    final before = text.substring(0, range.from);
    final course = page.courseFor(i, before, used);
    page.lastTimeLine = last;
    page.taken.addAll([i, last]);
    if (course.skipped) continue;
    final room = page.roomFor(last, text.substring(range.to), used);

    final head = _withoutTitle(course.text.replaceAll(cellBreak, ' '));
    final hint = '$head ${course.between} $before'.replaceAll(cellBreak, ' ');
    final row = RawRow(Structure.lines)
      ..guessedCourse = course.inherited
      ..cells[ColumnKind.course] = course.text.replaceAll(cellBreak, ' ')
      ..cells[ColumnKind.component] = hint
      ..cells[ColumnKind.section] = hint
      ..cells[ColumnKind.daysTimes] = text
      ..cells[ColumnKind.room] = room;
    for (final l in used) {
      row.tokens.addAll(l.tokens);
    }
    rows.add(row);
  }
  return rows;
}
