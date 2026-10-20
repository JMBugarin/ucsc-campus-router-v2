import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/features/schedule/ocr/layout.dart';
import 'package:ucsc_router/features/schedule/ocr/parsed_row.dart';
import 'package:ucsc_router/features/schedule/ocr/recognized_text.dart';
import 'package:ucsc_router/features/schedule/ocr/schedule_parser.dart';

import 'ocr_pages.dart';

ParsedSchedule parse(Page page) => parseSchedule(page.build());

String brief(ParsedRow r) => '${r.course} | ${r.component} | ${r.days} | ${r.start}-${r.end} | ${r.location}';

List<String> briefs(ParsedSchedule s) => [for (final r in s.rows) brief(r)];

/// What a row needs the student to know, leaving out what is only information (that no dates were shown).
Set<RowIssue> issuesOf(ParsedRow r) => {...r.issues}..remove(RowIssue.noDates);

/// A header-less table row: course, days, times, room, each in its own cell.
Page oneRow(String days, String times, {String room = 'BE 152', String course = 'ART 20'}) =>
    Page().cells(100, {40: course, 250: days, 520: times, 900: room});

void main() {
  group('readings the phone really returned', () {
    for (final f in Fixture.all()) {
      test('${f.name}: ${f.about}', () {
        final result = parseSchedule(f.reading);
        final want = f.expected;
        expect(result.problem?.name, want['problem']);
        expect(result.notes, want['notes']);
        final rows = (want['rows'] as List).cast<Map<String, dynamic>>();
        expect(result.rows, hasLength(rows.length));
        for (var i = 0; i < rows.length; i++) {
          final got = result.rows[i];
          final w = rows[i];
          expect(
            {
              'course': got.course,
              'title': got.title,
              'section': got.section,
              'component': got.component,
              'days': got.days,
              'start': got.start,
              'end': got.end,
              'location': got.location,
              'startDate': got.startDate,
              'endDate': got.endDate,
            },
            {
              for (final k in [
                'course',
                'title',
                'section',
                'component',
                'days',
                'start',
                'end',
                'location',
                'startDate',
                'endDate',
              ])
                k: w[k],
            },
            reason: 'row $i',
          );
          expect([for (final issue in got.issues) issue.name]..sort(), w['issues'], reason: 'issues of row $i');
          expect(got.needsReview, w['needsReview'], reason: 'review of row $i');
          expect(got.confidence, inInclusiveRange(0, 1));
        }
      });
    }
  });

  group('a MyUCSC page laid out like the real one', () {
    const clean = [
      'XYZ 10 | Discussion | [0] | 08:00-09:05 | Cowell Acad 113',
      'XYZ 10 | Lecture | [0, 2, 4] | 14:40-15:45 | Kresge Acad 3201',
      'ABC 20 | Discussion | [3] | 08:30-09:35 | J Baskin Engr 156',
      'ABC 20 | Lecture | [1, 3] | 09:50-11:25 | Earth&Marine B206',
    ];

    test('is rebuilt row by row, with titles, sections and dates', () {
      final result = parse(myUcscPage(sampleCourses));
      expect(result.notes, isEmpty);
      expect(briefs(result), clean);
      expect([for (final r in result.rows) r.section], ['01A', '01', '01A', '01']);
      expect(
        [for (final r in result.rows) r.title],
        ['Sample Calculus', 'Sample Calculus', 'Sample Systems', 'Sample Systems'],
      );
      expect({for (final r in result.rows) (r.startDate, r.endDate)}, {('2026-09-24', '2026-12-04')});
      expect(result.rows.where((r) => r.needsReview), isEmpty);
    });

    test('is read the same when the phone read neighbouring cells as one line', () {
      final result = parse(myUcscPage(sampleCourses, merge: true));
      expect(briefs(result), clean);
      expect(result.rows.where((r) => r.needsReview), isEmpty);
    });

    test('is read the same at any size', () {
      for (final scale in [0.6, 1.0, 1.7, 2.5]) {
        expect(briefs(parse(myUcscPage(sampleCourses, scale: scale))), clean, reason: 'scale $scale');
      }
    });

    test('a menu down the side and a footer are ignored', () {
      final result = parse(myUcscPage(sampleCourses));
      expect(result.rows, hasLength(4));
      expect(result.notes, isEmpty);
    });

    test('letters read for digits and a misspelt component are repaired without asking the student', () {
      final result = parse(
        myUcscPage(
          sampleCourses,
          noise: {
            ('section', '20003'): 'O01A',
            ('days', '20002'): 'M0WeFr',
            ('t1', '20001'): '8:OOAM',
            ('d1', '20004'): 'O9/24/2O26',
            ('component', '20004'): 'Lectre',
            ('nbr', '20001'): '2000l',
          },
        ),
      );
      expect(briefs(result), clean);
      expect(result.rows[2].section, '01A');
      expect(result.rows[3].startDate, '2026-09-24');
      expect(result.rows.where((r) => r.needsReview), isEmpty);
    });

    test('a time with no hour is reported, not guessed, and the row is flagged', () {
      final result = parse(myUcscPage(sampleCourses, noise: {('t2', '20002'): ':45PM'}));
      expect(result.rows, hasLength(4));
      final lecture = result.rows[1];
      expect(lecture.start, isNull);
      expect(lecture.end, isNull);
      expect(lecture.issues, contains(RowIssue.noTime));
      expect(lecture.needsReview, isTrue);
      expect(lecture.reasons.first, 'No time was found.');
      expect(result.rows.where((r) => r.needsReview), [lecture]);
    });

    test('a class number and section read as one word are split, and the row says so', () {
      final result = parse(myUcscPage(sampleCourses, noise: {('nbr', '20004'): '2000401', ('section', '20004'): ''}));
      expect(result.rows[3].section, '01');
      expect(result.rows[3].issues, contains(RowIssue.splitText));
      expect(brief(result.rows[3]), clean[3]);
    });

    test('a dropped course is left out and said so', () {
      final dropped = Course('DEF 30', 'Sample Dropped', [
        const ClassRow('20009', '01', 'Lecture', 'Tu', '9:00AM', '9:55AM', 'Soc Sci 2 075', 'Pat Example'),
      ], status: 'Dropped');
      final result = parse(myUcscPage([sampleCourses[0], dropped]));
      expect({for (final r in result.rows) r.course}, {'XYZ 10'});
      expect(result.notes, ['Skipped DEF 30 (dropped).']);
    });

    test('one table, and three', () {
      expect(parse(myUcscPage(sampleCourses.take(1).toList())).rows, hasLength(2));
      const third = Course('GHI 30', 'Sample Third', [
        ClassRow('20005', '01', 'Lecture', 'MoWeFr', '4:00PM', '5:05PM', 'Thim Lecture 003', 'Pat Example'),
      ]);
      final result = parse(myUcscPage([...sampleCourses, third]));
      expect(result.rows, hasLength(5));
      expect(brief(result.rows.last), 'GHI 30 | Lecture | [0, 2, 4] | 16:00-17:05 | Thim Lecture 003');
    });

    test('a room number that fell into the instructor column goes back to its room', () {
      final page = myUcscPage(sampleCourses);
      expect(briefs(parse(page)).first, contains('Cowell Acad 113'));
      expect(parse(page).rows.every((r) => RegExp(r'\d').hasMatch(r.location)), isTrue);
    });
  });

  group('days, times and rooms in the forms schedules use', () {
    test('days', () {
      const cases = {
        'M': [0],
        'Tu': [1],
        'W': [2],
        'Th': [3],
        'F': [4],
        'MWF': [0, 2, 4],
        'MW': [0, 2],
        'TuTh': [1, 3],
        'TTh': [1, 3],
        'MoWeFr': [0, 2, 4],
        'M W F': [0, 2, 4],
        'Tu Th': [1, 3],
        'Mon, Wed, Fri': [0, 2, 4],
        'Tue/Thu': [1, 3],
        'Tuesday': [1],
        'TUTH': [1, 3],
      };
      for (final entry in cases.entries) {
        final result = parse(oneRow(entry.key, '1:20 PM - 2:25 PM'));
        expect(result.rows, hasLength(1), reason: entry.key);
        expect(result.rows.single.days, entry.value, reason: entry.key);
        expect(result.rows.single.needsReview, isFalse, reason: entry.key);
      }
    });

    test('12 and 24 hour times, with and without AM and PM, and any dash', () {
      const cases = {
        '8:00AM - 9:05AM': ('08:00', '09:05'),
        '1:20pm-2:25pm': ('13:20', '14:25'),
        '10:40 AM \u2013 11:45 AM': ('10:40', '11:45'),
        '9:50 a.m. \u2014 11:25 a.m.': ('09:50', '11:25'),
        '12:00 PM - 1:05 PM': ('12:00', '13:05'),
        '1:20 - 2:25 PM': ('13:20', '14:25'),
        '11:40 - 1:15 PM': ('11:40', '13:15'),
        '13:20 - 14:25': ('13:20', '14:25'),
        '08:00 \u2013 09:35': ('08:00', '09:35'),
        '17:20-18:55': ('17:20', '18:55'),
        '9am-10:30am': ('09:00', '10:30'),
        '1:20 to 2:25 PM': ('13:20', '14:25'),
      };
      for (final entry in cases.entries) {
        final result = parse(oneRow('MWF', entry.key));
        expect(result.rows, hasLength(1), reason: entry.key);
        expect((result.rows.single.start, result.rows.single.end), entry.value, reason: entry.key);
      }
    });

    test('rooms as the schedule or a student writes them', () {
      for (final room in [
        'Thimann 101',
        'Kresge 3201',
        'BE 152',
        'Baskin Engineering 152',
        'Kresge Acad 3201',
        'J Baskin Engr 156',
        'Earth&Marine B206',
        'Soc Sci 2 075',
        'Humanities Lecture Hall',
      ]) {
        final result = parse(oneRow('MWF', '1:20 PM - 2:25 PM', room: room));
        expect(result.rows.single.location, room, reason: room);
        expect(result.rows.single.issues, isNot(contains(RowIssue.noRoom)), reason: room);
      }
    });

    test('online and to-be-announced classes keep what the page says and need no room', () {
      for (final room in ['Online', 'TBA', 'Remote Instruction', 'Zoom']) {
        final result = parse(oneRow('TuTh', '9:50 AM - 11:25 AM', room: room));
        expect(result.rows.single.location, room);
        expect(result.rows.single.needsReview, isFalse, reason: room);
      }
    });

    test('a class with no room on the page is kept, with the note that it has none', () {
      final result = parse(Page().cells(100, {40: 'ART 20', 250: 'MWF', 520: '1:20 PM - 2:25 PM'}));
      expect(result.rows.single.location, '');
      expect(result.rows.single.issues, contains(RowIssue.noRoom));
      expect(result.rows.single.needsReview, isFalse);
    });
  });

  group('cards and rows of text', () {
    Page card(
      Page p,
      double y, {
      String head = 'BME 160 Lecture',
      String when = 'MWF 1:20 PM - 2:25 PM',
      String room = 'Baskin Engineering 152',
    }) => p
      ..line(60, y, head)
      ..line(60, y + 50, 'Cell Biology')
      ..line(60, y + 100, when)
      ..line(60, y + 150, room);

    test('a card: course and kind of class, the title, days and times, then the room', () {
      final result = parse(card(Page(), 100));
      expect(briefs(result), ['BME 160 | Lecture | [0, 2, 4] | 13:20-14:25 | Baskin Engineering 152']);
      expect(result.rows.single.needsReview, isFalse);
    });

    test('cards one after the other each get their own course, time and room', () {
      final p = Page();
      card(p, 100);
      card(p, 360, head: 'BME 160 Discussion', when: 'Th 8:30 AM - 9:35 AM', room: 'Thimann 101');
      card(p, 620, head: 'CSE 101 Lecture', when: 'TuTh 9:50 AM - 11:25 AM', room: 'BE 152');
      expect(briefs(parse(p)), [
        'BME 160 | Lecture | [0, 2, 4] | 13:20-14:25 | Baskin Engineering 152',
        'BME 160 | Discussion | [3] | 08:30-09:35 | Thimann 101',
        'CSE 101 | Lecture | [1, 3] | 09:50-11:25 | BE 152',
      ]);
    });

    test('a pin or bullet drawn before the room is not part of it', () {
      for (final glyph in ['\u2022', 'O', '|', '\u25cb']) {
        final result = parse(card(Page(), 100, room: '$glyph Kresge Acad 3201'));
        expect(result.rows.single.location, 'Kresge Acad 3201', reason: glyph);
      }
    });

    test('a time that wraps onto a second line is one time', () {
      final p = Page()
        ..line(60, 100, 'BME 160 Lecture')
        ..line(60, 150, 'MWF 1:20 PM -')
        ..line(60, 175, '2:25 PM')
        ..line(60, 230, 'Thimann 101');
      expect(briefs(parse(p)), ['BME 160 | Lecture | [0, 2, 4] | 13:20-14:25 | Thimann 101']);
    });

    test('a card that labels each field: the value is the line under the label', () {
      final p = Page()
        ..line(60, 100, 'MATH 30 - Seminar in Ethics')
        ..line(60, 150, 'Status')
        ..line(60, 190, 'Enrolled')
        ..line(60, 250, 'Section')
        ..line(60, 290, '01A-DIS')
        ..line(60, 350, 'Days & Times')
        ..line(60, 390, 'Fr 8:00am-9:05am')
        ..line(60, 450, 'Room')
        ..line(60, 490, 'Crown Classroom 104');
      final result = parse(p);
      expect(briefs(result), ['MATH 30 | Discussion | [4] | 08:00-09:05 | Crown Classroom 104']);
      expect(result.rows.single.section, '01A');
      expect(result.rows.single.title, 'Seminar in Ethics');
    });

    test('a course that is dropped or wait-listed is left out and said so', () {
      final p = Page()
        ..line(60, 100, 'MATH 30 - Seminar in Ethics')
        ..line(60, 150, 'Status')
        ..line(60, 190, 'Dropped')
        ..line(60, 350, 'Days & Times')
        ..line(60, 390, 'Fr 8:00am-9:05am')
        ..line(60, 450, 'Room')
        ..line(60, 490, 'Crown Classroom 104');
      final result = parse(p);
      expect(result.rows, isEmpty);
      expect(result.notes, ['Skipped MATH 30 (dropped).']);
      expect(result.problem, ReadProblem.noClasses);
    });

    test('a second time under the same course takes that course, and is flagged as a guess', () {
      final p = Page()
        ..line(60, 100, 'BME 160 Lecture')
        ..line(60, 150, 'MWF 1:20 PM - 2:25 PM')
        ..line(60, 200, 'Th 4:00 PM - 5:05 PM');
      final result = parse(p);
      expect(result.rows.map((r) => r.course), ['BME 160', 'BME 160']);
      expect(result.rows[0].needsReview, isFalse);
      expect(result.rows[1].issues, contains(RowIssue.guessedCourse));
      expect(result.rows[1].needsReview, isTrue);
    });

    test('the first line of a wrapped time is not mistaken for the course of the next class', () {
      final p = Page()
        ..line(60, 100, 'BME 160 Lecture')
        ..line(60, 150, 'MWF 1:20 PM -')
        ..line(60, 175, '2:25 PM')
        ..line(60, 230, 'Thimann 101')
        ..line(60, 600, 'Th 4:00 PM - 5:05 PM')
        ..line(60, 650, 'BE 152');
      final result = parse(p);
      expect(result.rows, hasLength(2));
      expect(result.rows[1].course, '');
      expect(result.rows[1].issues, contains(RowIssue.noCourse));
    });

    test('rows of a table with no headings: every cell on one line', () {
      final p = Page()
        ..cells(100, {40: 'ART 20', 250: 'MWF', 520: '1:20pm-2:25pm', 900: 'Thimann Lec 001'})
        ..cells(160, {40: 'ART 20', 250: 'M', 520: '1:20pm-2:25pm', 900: 'Social Sci 2 159'})
        ..cells(220, {40: 'ECON 1', 250: 'TuTh', 520: '5:20pm-6:55pm', 900: 'BE 165'});
      expect(briefs(parse(p)), [
        'ART 20 |  | [0, 2, 4] | 13:20-14:25 | Thimann Lec 001',
        'ART 20 |  | [0] | 13:20-14:25 | Social Sci 2 159',
        'ECON 1 |  | [1, 3] | 17:20-18:55 | BE 165',
      ]);
    });

    test('a class listed once for each day is one class on those days', () {
      final p = Page()
        ..cells(100, {40: 'HIS10', 250: 'Tue', 520: '09:50', 700: '11:25', 900: 'Oakes 222'})
        ..cells(160, {40: 'HIS10', 250: 'Thu', 520: '09:50', 700: '11:25', 900: 'Oakes 222'})
        ..cells(220, {40: 'HIS10', 250: 'Mon', 520: '13:20', 700: '14:25', 900: 'Crown 104'});
      final result = parse(p);
      expect(briefs(result), [
        'HIS 10 |  | [1, 3] | 09:50-11:25 | Oakes 222',
        'HIS 10 |  | [0] | 13:20-14:25 | Crown 104',
      ]);
    });
  });

  group('rows that need a look', () {
    test('a clean row is sure of itself', () {
      final row = parse(oneRow('MWF', '1:20 PM - 2:25 PM')).rows.single;
      expect(row.confidence, greaterThan(0.9));
      expect(row.needsReview, isFalse);
      expect(row.reasons, isEmpty);
    });

    test('days with a letter lost are guessed and flagged', () {
      final row = parse(oneRow('MoWer', '1:20 PM - 2:25 PM')).rows.single;
      expect(row.days, [0, 2, 4]);
      expect(issuesOf(row), {RowIssue.guessedDays});
      expect(row.needsReview, isTrue);
      expect(row.reasons, ['The days may be wrong.']);
    });

    test('AM and PM guessed from school hours is flagged', () {
      final row = parse(oneRow('MWF', '1:20 - 2:25')).rows.single;
      expect((row.start, row.end), ('13:20', '14:25'));
      expect(issuesOf(row), {RowIssue.guessedTime});
      expect(row.needsReview, isTrue);
    });

    test('a time with a digit read for a letter is repaired and only noted', () {
      final row = parse(oneRow('MWF', '1:2O PM - 2:25 PM')).rows.single;
      expect((row.start, row.end), ('13:20', '14:25'));
      expect(issuesOf(row), {RowIssue.correctedText});
      expect(row.needsReview, isFalse);
      expect(row.reasons, ['Some characters were corrected.']);
    });

    test('text the phone was unsure of is flagged', () {
      final p = Page().cells(100, {40: 'ART 20', 250: 'MWF', 520: '1:20 PM - 2:25 PM', 900: 'BE 152'}, confidence: 0.3);
      final row = parse(p).rows.single;
      expect(row.issues, contains(RowIssue.unsureText));
      expect(row.needsReview, isTrue);
    });

    test('a course read with a guess in it is flagged', () {
      final row = parse(oneRow('MWF', '1:20 PM - 2:25 PM', course: 'BIOLI')).rows.single;
      expect(row.course, 'BIOL 1');
      expect(row.issues, contains(RowIssue.guessedCourse));
      expect(row.needsReview, isTrue);
    });

    test('what is missing comes first in the reasons, and a row can be missing several things', () {
      final row = parse(Page().cells(100, {520: '1:20 PM - 2:25 PM'})).rows.single;
      expect(row.issues, containsAll([RowIssue.noCourse, RowIssue.noDays]));
      expect(row.reasons.take(2), unorderedEquals(['No course was found.', 'No days were found.']));
      expect(row.needsReview, isTrue);
      expect(row.confidence, lessThan(0.5));
    });
  });

  group('repeats and noise', () {
    test('a class that appears twice is kept once, and the repeat is mentioned', () {
      final p = Page()
        ..cells(100, {40: 'ART 20', 250: 'MWF', 520: '1:20 PM - 2:25 PM', 900: 'BE 152'})
        ..cells(160, {40: 'ECON 1', 250: 'TuTh', 520: '5:20 PM - 6:55 PM', 900: 'BE 165'})
        ..cells(220, {40: 'ART 20', 250: 'MWF', 520: '1:20 PM - 2:25 PM', 900: 'BE 152'});
      final result = parse(p);
      expect(result.rows, hasLength(2));
      expect(result.notes, ['Skipped a class that appeared more than once.']);
    });

    test('the same line read twice at the same place is one line', () {
      final p = oneRow('MWF', '1:20 PM - 2:25 PM');
      final twice = RecognizedText(width: 1200, height: 1600, lines: [...p.lines, ...p.lines]);
      expect(parseSchedule(twice).rows, hasLength(1));
    });

    test('lines that are not classes, between and around the rows, are ignored', () {
      final p = Page()
        ..line(40, 40, 'Fall 2026 - My Schedule')
        ..cells(100, {40: 'ART 20', 250: 'MWF', 520: '1:20 PM - 2:25 PM', 900: 'BE 152'})
        ..line(40, 140, '| | | ||')
        ..line(40, 180, '\u2022 \u2022 \u2022')
        ..line(40, 220, 'Updated just now')
        ..cells(260, {40: 'ECON 1', 250: 'TuTh', 520: '5:20 PM - 6:55 PM', 900: 'BE 165'})
        ..line(40, 320, 'Total units 10.00')
        ..line(800, 360, 'Printer Friendly Page');
      expect(briefs(parse(p)), [
        'ART 20 |  | [0, 2, 4] | 13:20-14:25 | BE 152',
        'ECON 1 |  | [1, 3] | 17:20-18:55 | BE 165',
      ]);
    });

    test('prices and other numbers that look a little like times are not classes', () {
      final p = Page()
        ..cells(100, {40: 'Soup', 600: '5.50 - 6.50'})
        ..cells(160, {40: 'Units', 600: '5.00'})
        ..cells(220, {40: 'Sale', 600: '10.00 - 12.00'});
      final result = parse(p);
      expect(result.rows, isEmpty);
      expect(result.problem, ReadProblem.noClasses);
    });
  });

  group('words and lines', () {
    test('a line given without its words is spread over its box by length', () {
      final reading = RecognizedText(
        width: 1000,
        height: 1000,
        lines: [const RecognizedLine(text: 'ART 20 MWF 1:20 PM - 2:25 PM BE 152', box: Box(0, 100, 700, 130))],
      );
      final tokens = tokensOf(reading);
      expect(tokens.map((t) => t.text), ['ART', '20', 'MWF', '1:20', 'PM', '-', '2:25', 'PM', 'BE', '152']);
      expect(tokens.first.left, 0);
      expect(tokens.last.right, closeTo(700, 1e-9));
      expect(parseSchedule(reading).rows, hasLength(1));
    });

    test('a word the phone placed wrongly, with a box twice as tall as the text, stays on its own line', () {
      const normal = 24.0;
      final tokens = [
        const Token('We', Box(964, 594, 1000, 638), 1), // read in a box around two lines
        const Token('12:00PM-', Box(1006, 590, 1100, 637), 1),
        const Token('1:05PM', Box(971, 622, 1050, 649), 1),
      ];
      final lines = visualLines(tokens, normal);
      expect(lines.map((l) => l.text), ['12:00PM- We'.split(' ').reversed.join(' '), '1:05PM']);
    });

    test('ordinary text height ignores boxes that are taller because two lines were read together', () {
      final tokens = [
        for (var i = 0; i < 20; i++) Token('word$i', Box(0, i * 30.0, 50, i * 30.0 + 20), 1),
        for (var i = 0; i < 6; i++) Token('tall$i', Box(0, 700 + i * 60.0, 50, 700 + i * 60.0 + 44), 1),
      ];
      expect(typicalHeight(tokens), 20);
    });

    test('words with impossible positions are dropped', () {
      final reading = RecognizedText(
        width: 1000,
        height: 1000,
        lines: [
          const RecognizedLine(text: 'ART 20', box: Box(double.nan, 100, 200, 130)),
          RecognizedLine(
            text: 'ECON 1 TuTh 9:50 AM - 11:25 AM BE 152',
            box: const Box(0, 200, 500, 230),
            words: [const RecognizedWord('ECON', Box(0, double.infinity, 50, 230))],
          ),
        ],
      );
      expect(() => parseSchedule(reading), returnsNormally);
    });
  });

  group('bad input', () {
    test('nothing in the picture', () {
      final result = parseSchedule(const RecognizedText(width: 100, height: 100, lines: []));
      expect(result.rows, isEmpty);
      expect(result.problem, ReadProblem.noText);
    });

    test('lines of only spaces count as nothing', () {
      final result = parseSchedule(
        const RecognizedText(
          width: 100,
          height: 100,
          lines: [RecognizedLine(text: '   ', box: Box(0, 0, 10, 10))],
        ),
      );
      expect(result.problem, ReadProblem.noText);
    });

    test('text that is not a schedule', () {
      final p = Page()
        ..line(40, 40, 'Corner Cafe - Lunch Menu')
        ..cells(100, {40: 'Margherita Pizza', 700: '\$12.50'})
        ..cells(160, {40: 'Caesar Salad', 700: '\$9.00'});
      final result = parse(p);
      expect(result.rows, isEmpty);
      expect(result.problem, ReadProblem.noClasses);
    });

    test('boxes with no size do not break the reading', () {
      final lines = [
        for (var i = 0; i < 5; i++)
          RecognizedLine(text: 'ART 20 MWF 1:20 PM - 2:25 PM BE 152', box: Box(0, i * 30.0, 0, i * 30.0)),
      ];
      expect(() => parseSchedule(RecognizedText(width: 100, height: 100, lines: lines)), returnsNormally);
    });

    test('a great many lines are read in good time', () {
      final random = math.Random(7);
      final p = Page(height: 90000);
      for (var i = 0; i < 4000; i++) {
        p.cells(i * 20.0, {
          40: 'ART ${random.nextInt(300)}',
          250: 'MWF',
          520: '1:20 PM - 2:25 PM',
          900: 'BE ${random.nextInt(999)}',
        });
      }
      final watch = Stopwatch()..start();
      final result = parse(p);
      watch.stop();
      expect(result.rows, isNotEmpty);
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
    });

    test('a very long line', () {
      final p = Page(width: 200000)..line(0, 0, List.filled(3000, 'MWF 1:20 PM - 2:25 PM').join(' '));
      expect(() => parse(p), returnsNormally);
    });

    test('random words and numbers never raise an error', () {
      final random = math.Random(42);
      const vocabulary = [
        'ART',
        '20',
        'MWF',
        'TuTh',
        '1:20',
        'PM',
        'AM',
        '-',
        '\u2013',
        'BE',
        '152',
        'Lecture',
        'Section',
        'Room',
        'Days',
        '&',
        'Times',
        'Class',
        'Nbr',
        'Status',
        'Enrolled',
        'Dropped',
        '09/24/2026',
        ':45PM',
        'O',
        'l',
        '|',
        '5.00',
        'Kresge',
        'TBA',
        'Online',
        'Instructor',
        'Component',
        'Start/End',
        'Date',
        '01A',
        '20001',
        '2918301',
        'Mo',
        'We',
        'Fr',
        '12:00PM-',
        '\u2022',
      ];
      for (var round = 0; round < 150; round++) {
        final p = Page(charWidth: 4 + random.nextInt(14).toDouble(), textHeight: 8 + random.nextInt(40).toDouble());
        for (var i = 0; i < 1 + random.nextInt(40); i++) {
          final cells = <double, String>{};
          for (var c = 0; c < 1 + random.nextInt(5); c++) {
            cells[random.nextInt(1000).toDouble()] = List.generate(
              1 + random.nextInt(5),
              (_) => vocabulary[random.nextInt(vocabulary.length)],
            ).join(' ');
          }
          p.cells(random.nextInt(1500).toDouble(), cells, confidence: random.nextDouble());
        }
        final result = parse(p);
        for (final row in result.rows) {
          expect(row.confidence, inInclusiveRange(0, 1));
          expect(row.days.every((d) => d >= 0 && d <= 6), isTrue);
          if (row.start != null && row.end != null) expect(row.end!.compareTo(row.start!), greaterThan(0));
        }
      }
    });
  });
}
