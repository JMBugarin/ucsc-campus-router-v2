import 'block_reader.dart';
import 'layout.dart';
import 'parsed_row.dart';
import 'recognized_text.dart';
import 'row_builder.dart';
import 'table_reader.dart';

/// Turns text recognized in a picture of a class schedule into the classes it shows, each with how sure the
/// reading is. Nothing leaves the phone and nothing is saved: the student checks the result first.
ParsedSchedule parseSchedule(RecognizedText reading) {
  final tokens = tokensOf(reading);
  if (tokens.isEmpty) return const ParsedSchedule(rows: [], problem: ReadProblem.noText);
  final h = typicalHeight(tokens);
  final lines = visualLines(tokens, h);
  final notes = <String>[];

  var raw = readTables(lines, h, notes);
  if (raw.isEmpty) raw = readLines(lines, h, notes);
  final rows = [for (final r in raw) ?buildRow(r)];
  final merged = _mergeRepeats(rows, notes);
  return ParsedSchedule(rows: merged, notes: notes, problem: merged.isEmpty ? ReadProblem.noClasses : null);
}

String _loose(String text) => text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _sameClass(ParsedRow r) =>
    [r.course, r.section, r.component, r.start, r.end, _loose(r.location), r.startDate, r.endDate].join('|');

/// A class read twice is kept once, and a class listed with one row for each day is one class on several days.
List<ParsedRow> _mergeRepeats(List<ParsedRow> rows, List<String> notes) {
  final merged = <ParsedRow>[];
  var repeats = 0;
  for (final row in rows) {
    final i = merged.indexWhere((m) => _sameClass(m) == _sameClass(row));
    if (i < 0) {
      merged.add(row);
      continue;
    }
    final other = merged[i];
    if (row.days.every(other.days.contains)) {
      repeats++;
    } else if (row.days.every((d) => !other.days.contains(d))) {
      merged[i] = other.copyWith(
        days: [...other.days, ...row.days]..sort(),
        confidence: other.confidence < row.confidence ? other.confidence : row.confidence,
        issues: {...other.issues, ...row.issues},
      );
    } else {
      merged.add(row);
    }
  }
  if (repeats > 0) notes.add('Skipped ${repeats == 1 ? 'a class' : '$repeats classes'} that appeared more than once.');
  return merged;
}
