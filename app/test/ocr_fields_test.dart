import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/features/schedule/ocr/fields.dart';

(String, String)? range(String text) {
  final r = findTimeRange(text);
  return r == null ? null : (r.start, r.end);
}

String? lone(String text) => findLoneTime(text)?.time;

List<int>? days(String text) => findDays(text)?.days;

void main() {
  group('a time with no partner', () {
    test('is read when its end was lost, with the meridiem it has', () {
      expect(lone('MWF 1:20 PM -'), '13:20');
      expect(lone('Th 8:30 AM \u2013'), '08:30');
      expect(lone('12:05 PM'), '12:05');
      expect(lone('12:05 AM'), '00:05');
      expect(lone('9am'), '09:00');
    });

    test('is guessed from school hours when no meridiem was read, and 24 hour times are taken as they are', () {
      expect(lone('MWF 9:00'), '09:00');
      expect(lone('MWF 1:20'), '13:20');
      expect(lone('MWF 13:20'), '13:20');
      expect(lone('MWF 08:30'), '08:30');
    });

    test('is not read when there are two times, none, or an impossible one', () {
      expect(lone('1:20 PM - 2:25 PM'), isNull);
      expect(lone('MWF'), isNull);
      expect(lone(''), isNull);
      expect(lone('13:20 PM'), isNull);
      expect(lone('25:10'), isNull);
      expect(lone('price 5.50'), isNull);
    });

    test('says where it was found', () {
      final found = findLoneTime('MWF 1:20 PM -')!;
      expect('MWF 1:20 PM -'.substring(found.from, found.to), '1:20 PM');
    });
  });

  group('times', () {
    test('12 hour times with a meridiem on each, in the forms schedules use', () {
      expect(range('Mo 8:00AM - 9:05AM'), ('08:00', '09:05'));
      expect(range('1:20pm-2:25pm'), ('13:20', '14:25'));
      expect(range('10:40 AM \u2013 11:45 AM'), ('10:40', '11:45'));
      expect(range('9:50 a.m. - 11:25 a.m.'), ('09:50', '11:25'));
      expect(range('12:00pm-1:05pm'), ('12:00', '13:05'));
      expect(range('12:00 AM - 12:30 AM'), ('00:00', '00:30'));
      expect(range('9am-10:30am'), ('09:00', '10:30'));
    });

    test('different dashes and words between the times', () {
      for (final sep in ['-', '\u2013', '\u2014', '\u2212', ' - ', ' to ', ' until ', '--']) {
        expect(range('1:20PM${sep}2:25PM'), ('13:20', '14:25'), reason: 'separator "$sep"');
      }
    });

    test('a meridiem shown once covers both times, and an earlier start is put in the morning', () {
      expect(range('1:20 - 2:25 PM'), ('13:20', '14:25'));
      expect(range('9:50 - 11:25 AM'), ('09:50', '11:25'));
      expect(range('11:40 - 1:15 PM'), ('11:40', '13:15'));
      expect(findTimeRange('1:20 - 2:25 PM')?.certainty, Certainty.repaired);
    });

    test('24 hour times need no meridiem', () {
      expect(range('13:20 - 14:25'), ('13:20', '14:25'));
      expect(range('08:00 \u2013 09:35'), ('08:00', '09:35'));
      expect(range('17:20-18:55'), ('17:20', '18:55'));
      expect(findTimeRange('13:20 - 14:25')?.certainty, Certainty.exact);
    });

    test('times with no meridiem and no sign of a 24 hour clock are guessed from school hours', () {
      expect(range('1:20 - 2:25'), ('13:20', '14:25'));
      expect(range('8:00 - 9:05'), ('08:00', '09:05'));
      expect(range('11:40 - 12:35'), ('11:40', '12:35'));
      expect(findTimeRange('1:20 - 2:25')?.certainty, Certainty.guessed);
    });

    test('letters read for digits are repaired', () {
      expect(range('Mo 8:OOAM - 9:O5am'), ('08:00', '09:05'));
      expect(range('TuTh 1l:40AM - l:15PM'), ('11:40', '13:15'));
      expect(range('8.00AM - 9;05AM'), ('08:00', '09:05'));
      expect(findTimeRange('8:OOAM - 9:05AM')?.certainty, Certainty.repaired);
      expect(findTimeRange('8:00AM - 9:05AM')?.certainty, Certainty.exact);
    });

    test('a stray bar or comma between the times does not break the range', () {
      expect(range('Th 5:20PM - | 6:25PM'), ('17:20', '18:25'));
      expect(range('8:00AM , 9:05AM'), ('08:00', '09:05'));
    });

    test('two times with the dash lost still make a range', () {
      expect(range('09:50 11:25'), ('09:50', '11:25'));
      expect(range('9:50AM 11:25AM'), ('09:50', '11:25'));
    });

    test('what is not a time range is left alone', () {
      expect(range('8:00AM'), isNull);
      expect(range('Mo :05PM - 9:00AM'), isNull, reason: 'a time with no hour is not guessed');
      expect(range('13:00AM - 2:00PM'), isNull);
      expect(range('9:75AM - 10:00AM'), isNull);
      expect(range('2:25PM - 1:20PM'), isNull, reason: 'ends before it starts');
      expect(range('8:00AM - 8:05AM'), isNull, reason: 'too short to be a class');
      expect(range('8:00AM - 11:30PM'), isNull, reason: 'too long to be a class');
      expect(range('Enrolled 5.00 Graded'), isNull);
      expect(range('Soup 5.50 - 6.50'), isNull, reason: 'prices are not times');
      expect(range('8.00 - 9.05'), isNull, reason: 'a dot for the colon is only believed beside AM or PM');
      expect(range('09/24/2026 - 12/04/2026'), isNull);
      expect(range(''), isNull);
    });

    test('says where the range is in the text', () {
      const text = 'MWF 1:20 PM - 2:25 PM Kresge Acad 3201';
      final r = findTimeRange(text)!;
      expect(text.substring(r.from, r.to), '1:20 PM - 2:25 PM');
    });
  });

  group('days', () {
    test('the abbreviations schedules use', () {
      expect(days('MWF'), [0, 2, 4]);
      expect(days('TuTh'), [1, 3]);
      expect(days('MoWeFr'), [0, 2, 4]);
      expect(days('Mo'), [0]);
      expect(days('Th'), [3]);
      expect(days('M'), [0]);
      expect(days('W'), [2]);
      expect(days('F'), [4]);
      expect(days('TTh'), [1, 3]);
      expect(days('TR'), [1, 3]);
      expect(days('MTWRF'), [0, 1, 2, 3, 4]);
      expect(days('MoTuWeThFr'), [0, 1, 2, 3, 4]);
      expect(days('SaSu'), [5, 6]);
    });

    test('days written out or spaced apart', () {
      expect(days('M W F'), [0, 2, 4]);
      expect(days('Tu Th'), [1, 3]);
      expect(days('Mon, Wed, Fri'), [0, 2, 4]);
      expect(days('Mon/Wed/Fri'), [0, 2, 4]);
      expect(days('Tue & Thu'), [1, 3]);
      expect(days('Mon and Wed'), [0, 2]);
      expect(days('Tuesday'), [1]);
      expect(days('Thursday, Tuesday'), [1, 3]);
      expect(days('TUTH'), [1, 3]);
      expect(days('MON WED'), [0, 2]);
    });

    test('found among other words, and the group nearest a place is the one chosen', () {
      expect(days('ART 20 MWF 1:20pm-2:25pm Thimann Lec 001'), [0, 2, 4]);
      expect(days('Tue, Thu 9:50am-11:25am'), [1, 3]);
      const text = 'Th 8:30AM - 9:35AM then MWF';
      expect(findDays(text, near: 2)?.days, [3]);
      expect(findDays(text, near: text.length)?.days, [0, 2, 4]);
    });

    test('mistakes in the codes are repaired or guessed, and say so', () {
      expect(days('M0WeFr'), [0, 2, 4]);
      expect(findDays('M0WeFr')?.certainty, Certainty.repaired);
      expect(days('TuTn'), [1, 3]);
      expect(days('MoWer'), [0, 2, 4], reason: 'the F of Fr was lost');
      expect(findDays('MoWer')?.certainty, Certainty.guessed);
      expect(findDays('MoWeFr')?.certainty, Certainty.exact);
    });

    test('a code with a lower case letter is read but guessed', () {
      expect(days('Mowe'), [0, 2]);
      expect(findDays('Mowe')?.certainty, Certainty.guessed);
    });

    test('words that are not days', () {
      for (final text in ['Hello', 'MUSC', 'Lecture', 'BIOL', '8:00AM', 'MM', 'Kresge', '']) {
        expect(findDays(text), isNull, reason: text);
      }
    });

    test('says where the days are in the text', () {
      const text = 'ART 20 TuTh 9:50';
      final m = findDays(text)!;
      expect(text.substring(m.from, m.to), 'TuTh');
    });
  });

  group('courses, sections and components', () {
    test('course codes', () {
      expect(findCourse('ART 20')?.code, 'ART 20');
      expect(findCourse('BIOL 194')?.code, 'BIOL 194');
      expect(findCourse('MATH 19A')?.code, 'MATH 19A');
      expect(findCourse('BME 160L')?.code, 'BME 160L');
      expect(findCourse('HIS10')?.code, 'HIS 10');
      expect(findCourse('A&H 10')?.code, 'A&H 10');
      expect(findCourse('XYZ 10 - Sample Calculus III')?.code, 'XYZ 10');
      expect(findCourse('Lecture CSE 101 Algorithms')?.code, 'CSE 101');
      expect(findCourse('Introduction to Syntax'), isNull);
      expect(findCourse('1:20pm'), isNull);
    });

    test('a course number ending in the letter O is the number with a zero, as no course number ends in O', () {
      final m = findCourse('HIS 2O')!;
      expect(m.code, 'HIS 20');
      expect(m.certainty, Certainty.repaired);
      expect(findCourse('CSE 1OO')?.code, 'CSE 100');
      expect(findCourse('HIS2O Introduction')?.code, 'HIS 20');
      expect(findCourse('MATH 19A')?.certainty, Certainty.exact);
      expect(findCourse('ART 20')?.certainty, Certainty.exact);
      expect(findCourse('BME 160L')?.code, 'BME 160L');
    });

    test('a trailing capital I read for a 1 is guessed', () {
      final m = findCourse('BIOLI')!;
      expect(m.code, 'BIOL 1');
      expect(m.certainty, Certainty.guessed);
      expect(findCourse('Introduction I'), isNull);
    });

    test('components, in the words MyUCSC uses', () {
      expect(findComponent('Lecture'), 'Lecture');
      expect(findComponent('Lec'), 'Lecture');
      expect(findComponent('Disc'), 'Discussion');
      expect(findComponent('Lab'), 'Laboratory');
      expect(findComponent('Seminar'), 'Seminar');
      expect(findComponent('Lecture \u00b7 Section 01'), 'Lecture');
      expect(findComponent('Seminar in Ecology'), 'Seminar');
      expect(findComponent('Kresge'), isNull);
    });

    test('a component with a letter misread is still found for a table cell', () {
      expect(closestComponent('Lectre'), 'Lecture');
      expect(closestComponent('Discusion'), 'Discussion');
      expect(closestComponent('Laboratary'), 'Laboratory');
      expect(closestComponent('Lab'), 'Laboratory');
      expect(closestComponent('Xyzzy'), isNull);
      expect(closestComponent('Le'), isNull);
    });

    test('a section that is a whole cell', () {
      expect(sectionOfCell('01'), '01');
      expect(sectionOfCell('01A'), '01A');
      expect(sectionOfCell('O1A'), '01A');
      expect(sectionOfCell('0lb'), '01B');
      expect(sectionOfCell('Lecture'), isNull);
      expect(sectionOfCell('1'), isNull);
      expect(sectionOfCell('20002'), isNull);
    });

    test('a section named in running text', () {
      expect(findSection('Lecture \u00b7 Section 01A'), '01A');
      expect(findSection('Sec 02'), '02');
      expect(findSection('Discussion (01B)'), '01B');
      expect(findSection('Lecture 1:20 PM'), isNull);
    });
  });

  group('dates and rooms', () {
    test('dates as MyUCSC writes them', () {
      expect(findDates('09/24/2026 - 12/04/2026'), ['2026-09-24', '2026-12-04']);
      expect(findDates('O9/24/2O26 - l2/O4/2026'), ['2026-09-24', '2026-12-04']);
      expect(findDates('13/01/2026 02/30/2026 1/5/1999 nothing'), isEmpty, reason: 'not real dates');
      expect(findDates('5.00'), isEmpty);
    });

    test('a room without the pin or label drawn before it', () {
      expect(cleanRoom('\u2022 Stevenson Academic 151'), 'Stevenson Academic 151');
      expect(cleanRoom('O Jack Baskin Engr 372'), 'Jack Baskin Engr 372');
      expect(cleanRoom('Room: BE 152'), 'BE 152');
      expect(cleanRoom('| Kresge Acad 3201'), 'Kresge Acad 3201');
      expect(cleanRoom('(Thimann 101)'), 'Thimann 101');
      expect(cleanRoom('Location:   Kresge Acad 3201,'), 'Kresge Acad 3201');
      expect(cleanRoom('  Soc Sci 2    075 '), 'Soc Sci 2 075');
      expect(cleanRoom('Oakes Acad 222'), 'Oakes Acad 222', reason: 'a building that starts with O is not a pin');
    });

    test('a capital I between letters in a room is the lowercase l it was read for', () {
      expect(cleanRoom('Crown CIrm 105'), 'Crown Clrm 105');
      expect(cleanRoom('Cowell CIrm 131'), 'Cowell Clrm 131');
      for (final room in [
        'Crown Clrm 105',
        'Kresge Acad 3201',
        'McHenry Lib 1350',
        'Hum & Soc Sci 250',
        'Info Desk 1',
      ]) {
        expect(cleanRoom(room), room, reason: room);
      }
    });

    test('what could be a room', () {
      for (final room in ['BE 152', 'Kresge Acad 3201', 'Thimann 101', 'Baskin Engineering 152', 'Soc Sci 2 075']) {
        expect(looksLikeRoom(room), isTrue, reason: room);
      }
      expect(isNoRoom('Web Design 101'), isFalse);
      expect(isNoRoom('Web'), isTrue);
      for (final room in ['Online', 'TBA', 'Remote Instruction', 'To be Announced']) {
        expect(looksLikeRoom(room), isTrue, reason: room);
        expect(isNoRoom(room), isTrue, reason: room);
      }
      for (final text in ['Seminar in Ecology', '1:20 PM - 2:25 PM', '09/24/2026', '', 'x' * 60, '152']) {
        expect(looksLikeRoom(text), isFalse, reason: text);
      }
      expect(isNoRoom('BE 152'), isFalse);
    });
  });
}
