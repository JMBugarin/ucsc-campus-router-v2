import 'dart:math' as math;

import 'fields.dart';
import 'layout.dart';
import 'raw_row.dart';

class _Column {
  const _Column(this.kind, this.left, {this.weak = false, this.right});

  final ColumnKind kind;
  final double left;

  /// Where the heading's last word ends, when the heading is more than one word.
  final double? right;

  /// Named by a word that could mean something else (`Class`, which heads a course column or a class number).
  final bool weak;
}

class _Band {
  _Band(this.lines, this.columns);

  final List<VisualLine> lines;
  final List<_Column> columns;

  double get top => lines.map((l) => l.top).reduce(math.min);
  double get bottom => lines.map((l) => l.bottom).reduce(math.max);
}

const _keywords = <ColumnKind, List<String>>{
  ColumnKind.nbr: ['nbr', 'number'],
  ColumnKind.section: ['section', 'sec'],
  ColumnKind.component: ['component', 'type'],
  ColumnKind.days: ['days', 'day'],
  ColumnKind.times: ['times', 'time'],
  ColumnKind.room: ['room', 'location', 'building', 'where', 'place'],
  ColumnKind.instructor: ['instructor', 'professor', 'teacher', 'faculty'],
  ColumnKind.course: ['course', 'code', 'subject'],
  ColumnKind.title: ['title', 'name', 'description'],
  ColumnKind.dates: ['dates', 'date'],
};

String _word(Token t) => t.text.toLowerCase().replaceAll(RegExp(r'[^a-z/#&]'), '');

bool _is(String word, String key) =>
    word == key || (key.length >= 6 && word.length >= 5 && editDistance(word, key) <= 1);

ColumnKind? _kindOf(String word) {
  for (final entry in _keywords.entries) {
    if (entry.value.any((k) => _is(word, k))) return entry.key;
  }
  return null;
}

bool _isHeaderWord(String word) =>
    word == 'class' || word == 'end' || word.startsWith('start') || _kindOf(word) != null;

/// The columns a header row names, left to right, with the x position of each heading.
List<_Column> _columnsOf(List<Token> tokens, double h) {
  final sorted = [...tokens]..sort((a, b) => a.left.compareTo(b.left));
  final words = [for (final t in sorted) _word(t)];
  String? at(int j) => j < words.length ? words[j] : null;
  final hasNbr = words.contains('nbr');
  final columns = <_Column>[];
  for (var i = 0; i < sorted.length; i++) {
    final w = words[i];
    ColumnKind? kind;
    var consumed = 0;
    if (_is(w, 'days') || w == 'day') {
      var j = i + 1;
      if (at(j) == '&' || at(j) == 'and') j++;
      final next = at(j);
      if (next != null && (_is(next, 'times') || next == 'time')) {
        kind = ColumnKind.daysTimes;
        consumed = j - i;
      } else {
        kind = ColumnKind.days;
      }
    } else if (w == 'class') {
      if (const {'nbr', '#', 'no', 'num', 'number'}.contains(at(i + 1))) {
        kind = ColumnKind.nbr;
        consumed = 1;
      } else if (!hasNbr) {
        columns.add(_Column(ColumnKind.course, sorted[i].left, weak: true));
      }
    } else if (w.startsWith('start') && w.contains('/')) {
      kind = ColumnKind.dates;
      if (at(i + 1) == 'date' || at(i + 1) == 'dates') consumed = 1;
    } else if (w == 'start' && (at(i + 1) == '/' || at(i + 1) == '&') && at(i + 2) == 'end') {
      kind = ColumnKind.dates;
      consumed = at(i + 3) == 'date' ? 3 : 2;
    } else if (w == 'start') {
      kind = ColumnKind.start;
    } else if (w == 'end' && columns.any((c) => c.kind == ColumnKind.start)) {
      kind = ColumnKind.end;
    } else {
      kind = _kindOf(w);
    }
    if (kind != null) columns.add(_Column(kind, sorted[i].left, right: sorted[i + consumed].right));
    i += consumed;
  }
  // `Class` just before `Section` and `Component` heads the class numbers, as it does on MyUCSC
  final section = columns.where((c) => c.kind == ColumnKind.section).firstOrNull;
  final named = columns.map((c) => c.kind).toSet();
  final seen = <ColumnKind>{};
  final result = <_Column>[];
  for (final c in columns) {
    var column = c;
    if (c.weak) {
      final classNumbers = section != null && named.contains(ColumnKind.component) && section.left - c.left < 14 * h;
      if (section != null && section.left - c.left >= 14 * h) continue;
      if (classNumbers) column = _Column(ColumnKind.nbr, c.left);
    }
    if (seen.add(column.kind)) result.add(column);
  }
  _addMisreadRoom(result, sorted, h);
  return result;
}

/// A `Room` heading the phone misread (`Koom`) is still the one word between the times and the instructor.
void _addMisreadRoom(List<_Column> columns, List<Token> headings, double h) {
  if (columns.any((c) => c.kind == ColumnKind.room)) return;
  final timing = columns.where((c) => {ColumnKind.daysTimes, ColumnKind.times, ColumnKind.end}.contains(c.kind));
  final instructor = columns.where((c) => c.kind == ColumnKind.instructor).firstOrNull;
  if (timing.isEmpty || instructor == null) return;
  final after = timing.map((c) => c.right ?? c.left).reduce(math.max);
  final between = [
    for (final t in headings)
      if (t.left > after + 0.5 * h && t.right < instructor.left && _word(t).length >= 3) t,
  ];
  if (between.length == 1) {
    columns
      ..add(_Column(ColumnKind.room, between.single.left))
      ..sort((a, b) => a.left.compareTo(b.left));
  }
}

/// A heading the phone dropped or misread is where the same heading is in the page's other tables, which are laid
/// out alike (MyUCSC draws a table for each course).
void _borrowColumns(List<_Band> bands, double h) {
  final borrowed = List.generate(bands.length, (_) => <_Column>[]);
  for (var b = 0; b < bands.length; b++) {
    for (var o = 0; o < bands.length; o++) {
      if (o == b) continue;
      final same = bands[b].columns.where(
        (c) => bands[o].columns.any((x) => x.kind == c.kind && (x.left - c.left).abs() <= 1.5 * h),
      );
      if (same.length < 3) continue;
      for (final x in bands[o].columns) {
        final present = bands[b].columns.any((c) => c.kind == x.kind || (c.left - x.left).abs() <= 1.5 * h);
        if (!present && !borrowed[b].any((c) => c.kind == x.kind)) borrowed[b].add(x);
      }
    }
  }
  for (var b = 0; b < bands.length; b++) {
    bands[b].columns
      ..addAll(borrowed[b])
      ..sort((a, c) => a.left.compareTo(c.left));
  }
}

const _timingKinds = {ColumnKind.days, ColumnKind.times, ColumnKind.daysTimes, ColumnKind.start};

List<_Band> _findBands(List<VisualLine> lines, double h) {
  bool marked(VisualLine l) => l.tokens.any((t) => _isHeaderWord(_word(t)));
  final bands = <_Band>[];
  var i = 0;
  while (i < lines.length) {
    if (!marked(lines[i])) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < lines.length && marked(lines[j + 1]) && lines[j + 1].top - lines[j].bottom <= 0.6 * h) {
      j++;
    }
    final group = lines.sublist(i, j + 1);
    final columns = _columnsOf([for (final l in group) ...l.tokens], h);
    final kinds = columns.map((c) => c.kind).toSet();
    if (kinds.length >= 3 && kinds.any(_timingKinds.contains)) bands.add(_Band(group, columns));
    i = j + 1;
  }
  return bands;
}

final _titleStart = RegExp(r'^[A-Z][A-Z&]{1,4}\s?\d{1,3}[A-Z]{0,2}\b');

/// The line naming the course a table belongs to: the nearest line above its headings that starts with a
/// course code (`XYZ 10 - Sample Calculus`).
VisualLine? _titleAbove(List<VisualLine> lines, _Band band, double h) {
  for (final line in lines.reversed) {
    if (line.bottom > band.top + 0.2 * h) continue;
    if (band.top - line.bottom > 14 * h) return null;
    if (_titleStart.hasMatch(line.text)) return line;
  }
  return null;
}

final _dateWord = RegExp(r'^[0-9OolI|]{1,2}/[0-9OolI|]{1,2}/[0-9OolIsB]{4}-?$');
final _clockWord = RegExp(r'^-?[0-9OolI|]{0,2}[:.;][0-9OolI|SB]{2}([AaPp]\.?[Mm]\.?)?-?$');

/// The columns a word belongs in by what it says, whatever its position: a time or a day goes in the cell
/// with the other times, a date in the dates. Also how far from such a column, in text heights, it may be
/// moved. Null for words that could be anywhere, such as names and rooms.
({Set<ColumnKind> kinds, double reach})? _typedKinds(String text) {
  if (text == '-') {
    return (
      kinds: const {ColumnKind.daysTimes, ColumnKind.times, ColumnKind.start, ColumnKind.end, ColumnKind.dates},
      reach: 15,
    );
  }
  if (_dateWord.hasMatch(text)) return (kinds: const {ColumnKind.dates}, reach: 15);
  if (_clockWord.hasMatch(text)) {
    return (kinds: const {ColumnKind.daysTimes, ColumnKind.times, ColumnKind.start, ColumnKind.end}, reach: 15);
  }
  final days = findDays(text);
  if (days != null && days.from == 0 && days.to == text.length && days.certainty != Certainty.guessed) {
    // a lone `R` is Thursday, and also the first word of `R Carson Acad`: only believed beside the times
    return (kinds: const {ColumnKind.daysTimes, ColumnKind.days}, reach: text.length > 1 ? 15 : 3);
  }
  return null;
}

extension on RawRow {
  /// A room's number that the phone read together with the next cell, and that sits at the very edge of its own,
  /// goes back with the rest of the room.
  void _moveRoomNumber() {
    final room = cells[ColumnKind.room];
    final next = cells[ColumnKind.instructor];
    if (room == null || next == null || room.isEmpty || RegExp(r'[0-9]').hasMatch(room)) return;
    final m = RegExp(r'^([A-Za-z]?[0-9]{1,4}[A-Za-z]?)(?:\s+(.*))?$').firstMatch(next);
    if (m == null) return;
    cells[ColumnKind.room] = '$room ${m.group(1)}';
    cells[ColumnKind.instructor] = m.group(2) ?? '';
  }
}

final _idToken = RegExp(r'^[0-9OolI|]{4,9}[A-Za-z]?$');
final _sectionToken = RegExp(r'^[0-9OolI|]{2}[A-Za-z]?$');

/// The columns of one table, and which of them a word belongs to.
class _Table {
  _Table(this.columns, this.h);

  final List<_Column> columns;
  final double h;

  /// A word starts a little left of its heading as often as right of it (headings are centred, or placed a little
  /// off by the phone), so a column takes the words that start up to this far before its heading.
  double get tolerance => 1.5 * h;

  ColumnKind? kindOf(Token t) {
    final typed = _typedKinds(t.text);
    if (typed != null) {
      _Column? nearest;
      for (final c in columns) {
        final nearer = nearest == null || (c.left - t.left).abs() < (nearest.left - t.left).abs();
        if (typed.kinds.contains(c.kind) && nearer) nearest = c;
      }
      if (nearest != null && (nearest.left - t.left).abs() <= typed.reach * h) return nearest.kind;
    }
    ColumnKind? found;
    for (final c in columns) {
      if (t.left >= c.left - tolerance) found = c.kind;
    }
    return found;
  }
}

/// A heading the phone misread (`Class Nbr` as `ChEr`) leaves the class numbers without a column: they are the
/// numbers just left of Section.
void _addClassNumbers(List<_Column> columns, List<VisualLine> region, double h) {
  final section = columns.where((c) => c.kind == ColumnKind.section).firstOrNull;
  if (section == null || columns.any((c) => c.kind == ColumnKind.nbr)) return;
  final lefts = [
    for (final l in region)
      for (final t in l.tokens)
        if (_idToken.hasMatch(t.text) && t.left < section.left - 1.5 * h && t.left > section.left - 12 * h) t.left,
  ];
  if (lefts.isEmpty) return;
  columns
    ..add(_Column(ColumnKind.nbr, lefts.reduce(math.min)))
    ..sort((a, b) => a.left.compareTo(b.left));
}

/// One word for each class: where its class number or section is, or, for a table with a course column, where
/// its course is. A class number and its section are one row, even when the phone read them as a single word.
List<Token> _rowAnchors(List<VisualLine> region, _Table table) {
  final byCourse =
      table.columns.any((c) => c.kind == ColumnKind.course) && !table.columns.any((c) => c.kind == ColumnKind.nbr);
  final anchors = <Token>[];
  for (final line in region) {
    if (byCourse) {
      final cell = line.tokens.where((t) => table.kindOf(t) == ColumnKind.course).toList();
      if (cell.isNotEmpty && findCourse(cell.map((t) => t.text).join(' ')) != null) anchors.add(cell.first);
      continue;
    }
    for (final t in line.tokens) {
      final kind = table.kindOf(t);
      if (kind == ColumnKind.nbr && _idToken.hasMatch(t.text)) anchors.add(t);
      if (kind == ColumnKind.section && _sectionToken.hasMatch(t.text)) anchors.add(t);
    }
  }
  anchors.sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <Token>[];
  for (final a in anchors) {
    if (rows.isNotEmpty && (a.centerY - rows.last.centerY).abs() <= 0.9 * table.h) {
      if (table.kindOf(a) == ColumnKind.nbr) rows[rows.length - 1] = a;
      continue;
    }
    rows.add(a);
  }
  return rows;
}

List<RawRow> _readBand(
  List<VisualLine> lines,
  _Band band,
  VisualLine? title,
  double limit,
  double h,
  List<String> notes,
) {
  final hasRowKey = band.columns.any((c) => {ColumnKind.nbr, ColumnKind.section, ColumnKind.course}.contains(c.kind));
  if (!hasRowKey) return const [];
  if (title != null) {
    final status = courseStatus([
      for (final l in lines)
        if (l.top >= title.bottom - 1 && l.bottom <= band.top + 1) ...l.tokens.map((t) => t.text),
    ]);
    if (status != 'enrolled') {
      notes.add('Skipped ${findCourse(title.text)?.code ?? 'a course'} ($status).');
      return const [];
    }
  }
  final region = [
    for (final l in lines)
      if (l.centerY > band.lines.last.centerY + 0.6 * h && l.top < limit) l,
  ];
  final columns = [...band.columns];
  _addClassNumbers(columns, region, h);
  final table = _Table(columns, h);
  final anchors = _rowAnchors(region, table);
  if (anchors.isEmpty) return const [];

  // the words of a cell that wraps are on lines above and below the class number, so each word goes to the nearest
  // row, up to the height of a cell of three lines
  final reach = 2.6 * h;
  final cells = [for (final _ in anchors) <ColumnKind, List<Token>>{}];
  final used = [for (final _ in anchors) <Token>[]];
  for (final line in region) {
    for (final t in line.tokens) {
      final kind = table.kindOf(t);
      if (kind == null) continue;
      var nearest = 0;
      for (var k = 1; k < anchors.length; k++) {
        if ((anchors[k].centerY - t.centerY).abs() < (anchors[nearest].centerY - t.centerY).abs()) nearest = k;
      }
      if ((anchors[nearest].centerY - t.centerY).abs() > reach) continue;
      cells[nearest].putIfAbsent(kind, () => []).add(t);
      used[nearest].add(t);
    }
  }
  return [
    for (var k = 0; k < anchors.length; k++)
      RawRow(Structure.table)
        ..tokens.addAll(used[k])
        ..cells.addAll({for (final e in cells[k].entries) e.key: visualLines(e.value, h).map((l) => l.text).join(' ')})
        ..cells.addAll({if (title != null) ColumnKind.course: title.text})
        .._moveRoomNumber(),
  ];
}

/// Reads tables whose columns are named in a header row, with a row for each class. Words are given to the
/// column whose heading they sit under and to the nearest row, so cells that wrap onto two lines, or that the
/// phone read together with a neighbour, still land in the right place.
List<RawRow> readTables(List<VisualLine> lines, double h, List<String> notes) {
  final bands = _findBands(lines, h);
  _borrowColumns(bands, h);
  final titles = [
    for (final band in bands) band.columns.any((c) => c.kind == ColumnKind.course) ? null : _titleAbove(lines, band, h),
  ];
  return [
    for (var b = 0; b < bands.length; b++)
      ..._readBand(
        lines,
        bands[b],
        titles[b],
        b + 1 < bands.length ? (titles[b + 1]?.top ?? bands[b + 1].top) - 0.2 * h : double.infinity,
        h,
        notes,
      ),
  ];
}
