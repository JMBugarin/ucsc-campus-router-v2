import 'fields.dart';
import 'layout.dart';
import 'parsed_row.dart';
import 'raw_row.dart';

/// A recognition confidence below this is the phone saying it was not sure of the words.
const _unsureBelow = 0.45;

/// Reads the fields of one class from the text of its cells, or returns null if there is nothing in it that
/// looks like a class.
ParsedRow? buildRow(RawRow raw) {
  String cell(ColumnKind kind) =>
      (raw.cells[kind] ?? '').replaceAll(cellBreak, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final issues = <RowIssue>{};

  var timeText = raw.cells[ColumnKind.daysTimes] ?? '';
  if (timeText.isEmpty) timeText = raw.cells[ColumnKind.times] ?? '';
  if (timeText.isEmpty && (cell(ColumnKind.start).isNotEmpty || cell(ColumnKind.end).isNotEmpty)) {
    timeText = '${cell(ColumnKind.start)} - ${cell(ColumnKind.end)}';
  }
  final range = findTimeRange(timeText);
  if (range == null) {
    issues.add(RowIssue.noTime);
  } else if (range.certainty == Certainty.guessed) {
    issues.add(RowIssue.guessedTime);
  } else if (range.certainty == Certainty.repaired) {
    issues.add(RowIssue.correctedText);
  }

  final daysCell = cell(ColumnKind.days);
  final daysMatch = daysCell.isNotEmpty ? findDays(daysCell) : findDays(timeText, near: range?.from);
  if (daysMatch == null) {
    issues.add(RowIssue.noDays);
  } else if (daysMatch.certainty == Certainty.guessed) {
    issues.add(RowIssue.guessedDays);
  } else if (daysMatch.certainty == Certainty.repaired) {
    issues.add(RowIssue.correctedText);
  }

  final courseText = cell(ColumnKind.course);
  final course = findCourse(courseText);
  if (course == null) {
    issues.add(RowIssue.noCourse);
  } else if (course.certainty == Certainty.guessed || raw.guessedCourse) {
    issues.add(RowIssue.guessedCourse);
  }
  if (range == null && daysMatch == null && course == null) return null;

  var title = cell(ColumnKind.title);
  if (title.isEmpty && course != null) {
    // a table's course line has its title after the code, and the dash between them is often not read at all
    final after = courseText.substring(course.to);
    title = raw.structure == Structure.table
        ? after.replaceFirst(RegExp(r'^[\s-]+'), '').trim()
        : RegExp(r'^\s*-\s+(\S.*)$').firstMatch(after)?.group(1)?.trim() ?? '';
  }

  // a class number and its section the phone read as one word ("2918301"): the number is the first five digits
  var section = sectionOfCell(cell(ColumnKind.section)) ?? '';
  final fused = RegExp(r'^[0-9OolI|]{5}([0-9OolI|]{2}[A-Za-z]?)$').firstMatch(cell(ColumnKind.nbr));
  if (section.isEmpty && fused != null) {
    section = sectionOfCell(fused.group(1)!) ?? '';
    if (section.isNotEmpty) issues.add(RowIssue.splitText);
  }

  final componentCell = cell(ColumnKind.component);
  var component = '';
  if (raw.structure == Structure.table) {
    component = closestComponent(componentCell) ?? findComponent(componentCell) ?? '';
    if (section.isEmpty) section = findSection(courseText) ?? '';
  } else {
    final both = findSectionAndComponent(componentCell);
    component = both?.component ?? findComponent(componentCell) ?? '';
    section = both?.section ?? findSection(componentCell) ?? '';
  }
  if (section.isEmpty && course != null) {
    section = RegExp(r'^\s*-\s*(\d{2}[A-Z]?)(?![0-9:])').firstMatch(courseText.substring(course.to))?.group(1) ?? '';
  }

  final room = cleanRoom(cell(ColumnKind.room));
  if (room.isEmpty) issues.add(RowIssue.noRoom);

  final dates = findDates(cell(ColumnKind.dates));
  if (dates.length < 2) issues.add(RowIssue.noDates);

  var lowest = 1.0;
  for (final t in raw.tokens) {
    if (t.confidence < lowest) lowest = t.confidence;
  }
  if (lowest < _unsureBelow) issues.add(RowIssue.unsureText);

  var confidence = raw.structure.certainty;
  for (final issue in issues) {
    confidence *= issue.severity.factor;
  }
  return ParsedRow(
    course: course?.code ?? '',
    title: title,
    section: section,
    component: component,
    days: daysMatch?.days ?? const [],
    start: range?.start,
    end: range?.end,
    location: room,
    startDate: dates.length >= 2 ? dates[0] : null,
    endDate: dates.length >= 2 ? dates[1] : null,
    confidence: confidence,
    issues: issues,
  );
}
