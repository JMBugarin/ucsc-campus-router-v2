import 'layout.dart';

/// What a column of a schedule table, or a part of a card, holds.
enum ColumnKind { nbr, course, title, section, component, days, times, daysTimes, start, end, room, instructor, dates }

/// Where a row's words were found: under the headings of a table, or among lines of text.
enum Structure {
  table(1.0),
  lines(0.92);

  const Structure(this.certainty);

  /// What a row's confidence starts from: reading under headings is surer than reading lines of text.
  final double certainty;
}

/// The words of one class, as text for each field, before the fields are read.
class RawRow {
  RawRow(this.structure);

  final Structure structure;
  final Map<ColumnKind, String> cells = {};
  final List<Token> tokens = [];

  /// The course was taken from the class before, because this one has no course of its own.
  bool guessedCourse = false;
}
