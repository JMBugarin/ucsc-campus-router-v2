import 'dart:convert';
import 'dart:io';

import 'package:ucsc_router/features/schedule/ocr/recognized_text.dart';

/// Builds what the phone returns for a picture: lines of text, and where each word of them is.
class Page {
  Page({this.width = 1200, this.height = 1600, this.charWidth = 12, this.textHeight = 24});

  final int width;
  final int height;
  final double charWidth;
  final double textHeight;
  final List<RecognizedLine> lines = [];

  /// A line of text with its first word at ([x], [y]).
  Page line(double x, double y, String text, {double confidence = 1}) => cells(y, {x: text}, confidence: confidence);

  /// Cells that the phone read as one line, as it does when they sit close together. The key is where a cell
  /// starts.
  Page cells(double y, Map<double, String> byX, {double confidence = 1}) {
    final words = <RecognizedWord>[];
    for (final entry in byX.entries) {
      var x = entry.key;
      for (final w in entry.value.split(' ').where((w) => w.isNotEmpty)) {
        words.add(RecognizedWord(w, Box(x, y, x + w.length * charWidth, y + textHeight)));
        x += (w.length + 1) * charWidth;
      }
    }
    if (words.isEmpty) return this;
    lines.add(
      RecognizedLine(
        text: words.map((w) => w.text).join(' '),
        box: Box(words.first.box.left, y, words.last.box.right, y + textHeight),
        confidence: confidence,
        words: words,
      ),
    );
    return this;
  }

  RecognizedText build() => RecognizedText(width: width, height: height, lines: lines);
}

/// One row of MyUCSC's class table, with the cells as the page shows them.
class ClassRow {
  const ClassRow(
    this.nbr,
    this.section,
    this.component,
    this.days,
    this.t1,
    this.t2,
    this.room,
    this.instructor, {
    this.d1 = '09/24/2026',
    this.d2 = '12/04/2026',
  });

  final String nbr;
  final String section;
  final String component;
  final String days;
  final String t1;
  final String t2;
  final String room;
  final String instructor;
  final String d1;
  final String d2;
}

class Course {
  const Course(this.code, this.title, this.rows, {this.status = 'Enrolled'});

  final String code;
  final String title;
  final List<ClassRow> rows;
  final String status;
}

const sampleCourses = [
  Course('XYZ 10', 'Sample Calculus', [
    ClassRow('20001', '01A', 'Discussion', 'Mo', '8:00AM', '9:05AM', 'Cowell Acad 113', 'To be Announced'),
    ClassRow('20002', '01', 'Lecture', 'MoWeFr', '2:40PM', '3:45PM', 'Kresge Acad 3201', 'Alex Example'),
  ]),
  Course('ABC 20', 'Sample Systems', [
    ClassRow('20003', '01A', 'Discussion', 'Th', '8:30AM', '9:35AM', 'J Baskin Engr 156', 'To be Announced'),
    ClassRow('20004', '01', 'Lecture', 'TuTh', '9:50AM', '11:25AM', 'Earth&Marine B206', 'Pat Example'),
  ]),
];

const _col = {
  'nbr': 323.0,
  'section': 373.0,
  'component': 411.0,
  'days': 486.0,
  'room': 596.0,
  'instructor': 689.0,
  'dates': 796.0,
};

/// A MyUCSC "Class Schedule" page as text recognition reads it: a menu down the left, a table for each course with
/// cells that wrap onto two lines, and a footer. The geometry follows a real page, with invented classes. [noise]
/// replaces the text of a cell, keyed by the field and the row's class number. [merge] gives the phone's way of
/// reading cells that sit close together as one line.
Page myUcscPage(
  List<Course> courses, {
  double scale = 1,
  Map<(String, String), String> noise = const {},
  bool merge = false,
}) {
  final pieces = <(double, double, String)>[];
  void put(double x, double y, String text) => pieces.add((x * scale, y * scale, text));
  String n(String field, ClassRow r, String text) => noise[(field, r.nbr)] ?? text;

  for (var i = 0; i < 4; i++) {
    final label = ['Enrollment', 'Class Search', 'Enrollment: Add Classes', 'Edit a Class'][i];
    final parts = label.split(' ');
    for (var j = 0; j < parts.length; j++) {
      put(35 + 45.0 * j, 260 + 50.0 * i, parts[j]);
    }
  }
  var y = 441.0;
  for (final c in courses) {
    final title = '${c.code} ${c.title}'.split(' ');
    for (var k = 0; k < title.length; k++) {
      put(317 + 38.0 * k, y, title[k]);
    }
    for (final (text, x) in [
      ('Status', 317.0),
      ('Units', 499.0),
      ('Grading', 530.0),
      ('Grade', 679.0),
      ('Deadlines', 774.0),
    ]) {
      put(x, y + 29, text);
    }
    put(316, y + 50, c.status);
    put(454, y + 50, '5.00');
    put(530, y + 50, 'Graded');
    final hy = y + 82;
    for (final (text, x, dy) in [
      ('Class', 321.0, -7.0),
      ('Nbr', 327.0, 6.0),
      ('Section', 364.0, 0.0),
      ('Component', 410.0, 0.0),
      ('Days', 485.0, 0.0),
      ('&', 514.0, 0.0),
      ('Times', 524.0, 0.0),
      ('Room', 595.0, 0.0),
      ('Instructor', 688.0, 0.0),
      ('Start/End', 796.0, 0.0),
      ('Date', 846.0, 0.0),
    ]) {
      put(x, hy + dy, text);
    }
    for (var k = 0; k < c.rows.length; k++) {
      final r = c.rows[k];
      final top = y + 107 + k * 34;
      put(_col['nbr']!, top + 7, n('nbr', r, r.nbr));
      put(_col['section']!, top + 7, n('section', r, r.section));
      put(_col['component']!, top + 7, n('component', r, r.component));
      put(_col['days']!, top, n('days', r, r.days));
      put(_col['days']! + 46, top, n('t1', r, r.t1));
      put(_col['days']! + 100, top + 5, '-');
      put(_col['days']!, top + 14, n('t2', r, r.t2));
      final room = n('room', r, r.room).split(' ');
      var x = _col['room']!;
      for (final part in room.take(room.length - 1)) {
        put(x, top, part);
        x += 6.0 * part.length + 4;
      }
      put(_col['room']!, top + 14, room.last);
      final instructor = r.instructor.split(' ');
      put(
        _col['instructor']!,
        top,
        instructor.length > 1 ? instructor.take(instructor.length - 1).join(' ') : instructor.first,
      );
      if (instructor.length > 1) put(_col['instructor']!, top + 14, instructor.last);
      put(_col['dates']! - 1, top, n('d1', r, r.d1));
      put(_col['dates']! + 62, top + 5, '-');
      put(_col['dates']!, top + 14, n('d2', r, r.d2));
    }
    y += 107 + c.rows.length * 34 + 20;
  }
  for (var k = 0; k < 3; k++) {
    put(810 + 45.0 * k, y + 20, ['Printer', 'Friendly', 'Page'][k]);
  }

  final page = Page(
    width: (1000 * scale).round(),
    height: (y * scale + 100).round(),
    charWidth: 6.2 * scale,
    textHeight: 9 * scale,
  );
  if (!merge) {
    for (final (x, py, text) in pieces) {
      page.line(x, py, text);
    }
    return page;
  }
  final sorted = [...pieces]..sort((a, b) => a.$2.compareTo(b.$2));
  var i = 0;
  while (i < sorted.length) {
    var j = i;
    final byX = <double, String>{};
    while (j < sorted.length && sorted[j].$2 - sorted[i].$2 <= 8 * scale) {
      byX[sorted[j].$1] = sorted[j].$3;
      j++;
    }
    page.cells(sorted[i].$2, byX);
    i = j;
  }
  return page;
}

/// A reading saved by `integration_test`-style recording: the picture's lines as the phone returned them, and the
/// rows the parser is expected to make of them.
class Fixture {
  Fixture(this.name, this.about, this.reading, this.expected);

  final String name;
  final String about;
  final RecognizedText reading;
  final Map<String, dynamic> expected;

  static List<Fixture> all() {
    final files =
        Directory('test/fixtures/ocr').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return [
      for (final f in files)
        () {
          final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
          return Fixture(
            f.uri.pathSegments.last.replaceAll('.json', ''),
            json['about'] as String,
            RecognizedText.fromJson(json['reading']),
            json['expected'] as Map<String, dynamic>,
          );
        }(),
    ];
  }
}
