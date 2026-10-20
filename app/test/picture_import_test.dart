import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/app.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/features/schedule/meeting.dart';
import 'package:ucsc_router/features/schedule/ocr/recognized_text.dart';
import 'package:ucsc_router/features/schedule/ocr/text_recognizer.dart';
import 'package:ucsc_router/features/search/place.dart';
import 'package:ucsc_router/features/search/search_repository.dart';

import 'helpers.dart';
import 'ocr_pages.dart';

const term = (start: '2026-09-24', end: '2026-12-04');

RecognizedText myUcsc([List<Course>? courses]) => myUcscPage(courses ?? sampleCourses).build();

/// Two cards of the kind phone apps draw, which show no dates.
RecognizedText cards({String days = 'MWF', String room = 'Baskin Engineering 152'}) =>
    (OcrPage()
          ..line(60, 100, 'BME 160 Lecture')
          ..line(60, 150, 'Cell Biology')
          ..line(60, 200, '$days 1:20 PM - 2:25 PM')
          ..line(60, 250, room)
          ..line(60, 400, 'ART 20 Discussion')
          ..line(60, 450, 'Th 8:30 AM - 9:35 AM')
          ..line(60, 500, 'Thimann 101'))
        .build();

TestRig rigFor(RecognizedText reading, {({String start, String end})? term, bool pictureImport = true}) {
  final rig = TestRig(startTab: tabSchedule, term: term, stubTerm: true, pictureImport: pictureImport);
  rig.picker.path = '/fake/schedule.png';
  rig.recognizer.reading = reading;
  return rig;
}

Future<void> open(WidgetTester tester, TestRig rig, {double textScale = 1}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
}

Future<void> readPicture(WidgetTester tester) async {
  await tester.tap(find.text('Read a photo'));
  await tester.pumpAndSettle();
}

Finder card(String label) => find.widgetWithText(Card, label);

void main() {
  group('the button', () {
    testWidgets('is not offered where the phone cannot read pictures, and the other ways in stay', (tester) async {
      await open(tester, rigFor(myUcsc(), pictureImport: false));
      expect(find.text('Read a photo'), findsNothing);
      expect(find.text('Paste from MyUCSC'), findsOneWidget);
      expect(find.text('Calendar file'), findsOneWidget);
      expect(find.text('Add a class'), findsOneWidget);
    });

    testWidgets('choosing nothing does nothing', (tester) async {
      final rig = rigFor(myUcsc())..picker.path = null;
      await open(tester, rig);
      await readPicture(tester);
      expect(rig.picker.picks, 1);
      expect(rig.recognizer.paths, isEmpty);
      expect(find.text('Check your classes'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('while the picture is read the buttons wait and the screen says so', (tester) async {
      final release = Completer<void>();
      final rig = rigFor(myUcsc())..recognizer.hold = release.future;
      await open(tester, rig);
      await tester.tap(find.text('Read a photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Reading your picture…'), findsOneWidget);
      final button = find.ancestor(of: find.text('Read a photo'), matching: find.bySubtype<ButtonStyleButton>());
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
      release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Reading your picture…'), findsNothing);
      expect(find.text('Check your classes'), findsOneWidget);
    });
  });

  group('what goes wrong before there is anything to check', () {
    testWidgets('a photo library that cannot be opened is said so', (tester) async {
      final rig = rigFor(myUcsc())..picker.failWith = const PictureException("Couldn't open your photos. Try again.");
      await open(tester, rig);
      await readPicture(tester);
      expect(find.text("Couldn't open your photos. Try again."), findsOneWidget);
      expect(rig.recognizer.paths, isEmpty);
    });

    testWidgets('a picture that cannot be read is explained, and the copy the picker made is removed', (tester) async {
      final rig = rigFor(myUcsc())
        ..recognizer.reading = const PictureException("That file isn't a picture I can read.");
      await open(tester, rig);
      await readPicture(tester);
      expect(find.text("That file isn't a picture I can read."), findsOneWidget);
      expect(rig.picker.released, 1);
      expect(find.text('Reading your picture…'), findsNothing);
    });

    testWidgets('a failure nobody planned for is said, and does not leave the screen waiting', (tester) async {
      final rig = rigFor(myUcsc())..recognizer.reading = StateError('boom');
      await open(tester, rig);
      await readPicture(tester);
      expect(find.text('Something went wrong reading that picture. Try a different one.'), findsOneWidget);
      expect(find.text('Reading your picture…'), findsNothing);
      expect(rig.picker.released, 1);
      final button = find.ancestor(of: find.text('Read a photo'), matching: find.bySubtype<ButtonStyleButton>());
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
    });

    testWidgets('a picture with no text in it says so', (tester) async {
      final rig = rigFor(const RecognizedText(width: 100, height: 100, lines: []));
      await open(tester, rig);
      await readPicture(tester);
      expect(find.textContaining("couldn't find any text in that picture"), findsOneWidget);
      expect(find.text('Check your classes'), findsNothing);
      expect(rig.picker.released, 1);
    });

    testWidgets('text that is not a schedule says so, and offers the other ways in', (tester) async {
      final page = OcrPage()
        ..line(40, 40, 'Corner Cafe - Lunch Menu')
        ..cells(100, {40: 'Margherita Pizza', 700: '\$12.50'});
      await open(tester, rigFor(page.build()));
      await readPicture(tester);
      expect(find.textContaining("couldn't find any classes in that picture"), findsOneWidget);
      expect(find.textContaining('paste the text instead'), findsOneWidget);
      expect(find.text('Check your classes'), findsNothing);
    });

    testWidgets('a course that was dropped is mentioned even when nothing else was found', (tester) async {
      final dropped = Course('DEF 30', 'Sample Dropped', [
        const ClassRow('20009', '01', 'Lecture', 'Tu', '9:00AM', '9:55AM', 'Soc Sci 2 075', 'Pat Example'),
      ], status: 'Dropped');
      await open(tester, rigFor(myUcsc([dropped])));
      await readPicture(tester);
      expect(find.textContaining('Skipped DEF 30 (dropped).'), findsOneWidget);
    });
  });

  group('checking what was found', () {
    testWidgets('the classes are listed with what was read, and nothing is saved yet', (tester) async {
      final rig = rigFor(myUcsc());
      await open(tester, rig);
      await readPicture(tester);

      expect(find.text('Check your classes'), findsOneWidget);
      expect(find.textContaining('Found 4 classes.'), findsOneWidget);
      expect(find.textContaining('the picture was never sent anywhere'), findsOneWidget);
      expect(card('XYZ 10 Lecture'), findsOneWidget);
      expect(find.textContaining('MoWeFr  2:40 PM–3:45 PM'), findsOneWidget);
      expect(find.text('Kresge Acad 3201'), findsOneWidget);
      expect(find.text('Save 4 classes'), findsOneWidget);
      expect(rig.recognizer.paths, ['/fake/schedule.png']);
      expect(rig.picker.released, 1);
      expect(rig.schedule.stored, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Save adds the classes, with the dates the picture showed, and says how many', (tester) async {
      final rig = rigFor(myUcsc());
      await open(tester, rig);
      await readPicture(tester);
      await tester.tap(find.text('Save 4 classes'));
      await tester.pumpAndSettle();

      expect(find.text('Check your classes'), findsNothing);
      expect(find.textContaining('Added 4 classes.'), findsOneWidget);
      expect(rig.schedule.stored, hasLength(4));
      final lecture = rig.schedule.stored.firstWhere((m) => m.component == 'Lecture' && m.course == 'XYZ 10');
      expect(lecture.days, [0, 2, 4]);
      expect((lecture.start, lecture.end), ('14:40', '15:45'));
      expect((lecture.startDate, lecture.endDate), ('2026-09-24', '2026-12-04'));
      expect(lecture.location, 'Kresge Acad 3201');
      expect(find.text('XYZ 10 Lecture'), findsOneWidget, reason: 'now in the schedule list');
    });

    testWidgets('a save that fails keeps everything on screen, and the student can try again', (tester) async {
      final rig = rigFor(myUcsc());
      await open(tester, rig);
      await readPicture(tester);
      rig.schedule.saveFails = StateError('disk');
      await tester.tap(find.text('Save 4 classes'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't save your classes. Try again."), findsOneWidget);
      expect(find.text('Check your classes'), findsOneWidget);
      expect(rig.schedule.stored, isEmpty);
      rig.schedule.saveFails = null;
      await tester.tap(find.text('Save 4 classes'));
      await tester.pumpAndSettle();
      expect(find.text('Check your classes'), findsNothing);
      expect(rig.schedule.stored, hasLength(4));
    });

    testWidgets('while the classes are being saved the import cannot be cancelled', (tester) async {
      final release = Completer<void>();
      final rig = rigFor(myUcsc());
      await open(tester, rig);
      await readPicture(tester);
      rig.schedule.saveHold = release.future;
      await tester.tap(find.text('Save 4 classes'));
      await tester.pump();
      await tester.tap(find.byTooltip('Cancel import'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Discard this import?'), findsNothing);
      release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Check your classes'), findsNothing);
      expect(rig.schedule.stored, hasLength(4));
    });

    testWidgets('classes that are already saved are not added twice', (tester) async {
      final saved = Meeting(
        course: 'XYZ 10',
        title: 'Sample Calculus',
        section: '01',
        component: 'Lecture',
        days: const [0, 2, 4],
        start: '14:40',
        end: '15:45',
        location: 'Kresge Acad 3201',
        startDate: '2026-09-24',
        endDate: '2026-12-04',
      );
      final rig = TestRig(startTab: tabSchedule, stored: [saved], stubTerm: true);
      rig.picker.path = '/fake/schedule.png';
      rig.recognizer.reading = myUcsc();
      await open(tester, rig);
      await readPicture(tester);
      await tester.tap(find.text('Save 4 classes'));
      await tester.pumpAndSettle();
      expect(rig.schedule.stored, hasLength(4));
      expect(find.textContaining('(1 already there)'), findsOneWidget);
    });

    testWidgets('notes about the reading are shown with the classes and again after saving', (tester) async {
      final dropped = Course('DEF 30', 'Sample Dropped', [
        const ClassRow('20009', '01', 'Lecture', 'Tu', '9:00AM', '9:55AM', 'Soc Sci 2 075', 'Pat Example'),
      ], status: 'Dropped');
      await open(tester, rigFor(myUcsc([sampleCourses[0], dropped])));
      await readPicture(tester);
      expect(find.text('Skipped DEF 30 (dropped).'), findsOneWidget);
      await tester.tap(find.text('Save 2 classes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Skipped DEF 30 (dropped).'), findsOneWidget);
    });

    testWidgets('Cancel, the close button and going back each ask first, and nothing is saved', (tester) async {
      final rig = rigFor(myUcsc());
      await open(tester, rig);
      for (final leave in [
        () async {
          await tester.ensureVisible(find.text('Cancel'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cancel'));
        },
        () => tester.tap(find.byTooltip('Cancel import')),
        () async {
          await tester.binding.handlePopRoute();
        },
      ]) {
        await readPicture(tester);
        await leave();
        await tester.pumpAndSettle();
        expect(find.text('Discard this import?'), findsOneWidget);
        expect(find.text('Nothing has been saved.'), findsOneWidget);
        await tester.tap(find.text('Keep checking'));
        await tester.pumpAndSettle();
        expect(find.text('Check your classes'), findsOneWidget, reason: 'still there');
        await leave();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.text('Check your classes'), findsNothing);
        expect(rig.schedule.stored, isEmpty);
      }
    });
  });

  group('rows that need a look', () {
    testWidgets('a class the reading was not sure of is marked, with why', (tester) async {
      final rig = rigFor(cards(days: 'MoWer'), term: term);
      await open(tester, rig);
      await readPicture(tester);
      expect(find.textContaining('Found 2 classes, 1 needs a look.'), findsOneWidget);
      expect(find.text('The days may be wrong.'), findsOneWidget);
      expect(find.text('Save 2 classes'), findsOneWidget);
    });

    testWidgets('editing a class clears what the reading was unsure of', (tester) async {
      final rig = rigFor(cards(days: 'MoWer'), term: term);
      await open(tester, rig);
      await readPicture(tester);
      await tester.tap(card('BME 160 Lecture'));
      await tester.pumpAndSettle();
      expect(find.text('Edit class'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'Fr'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('The days may be wrong.'), findsNothing);
      expect(find.textContaining('Found 2 classes.'), findsOneWidget);
      await tester.tap(find.text('Save 2 classes'));
      await tester.pumpAndSettle();
      expect(rig.schedule.stored.first.days, [0, 2], reason: 'the guessed Friday was taken off');
    });

    testWidgets('a class with a time that was not read cannot be saved until it is fixed or removed', (tester) async {
      final page = OcrPage()
        ..line(60, 100, 'BME 160 Lecture')
        ..line(60, 150, 'MWF 1:20 PM -')
        ..line(60, 175, ':25 PM')
        ..line(60, 230, 'Thimann 101')
        ..line(60, 400, 'ART 20 Discussion')
        ..line(60, 450, 'Th 8:30 AM - 9:35 AM')
        ..line(60, 500, 'Thimann 101');
      final rig = rigFor(page.build(), term: term);
      await open(tester, rig);
      await readPicture(tester);

      expect(find.text('Pick a start and end time.'), findsOneWidget);
      expect(find.textContaining('1:20 PM–?'), findsOneWidget, reason: 'what was read is still shown');
      expect(find.text('Fix or remove the classes marked in red to save.'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Save 2 classes');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.tap(find.byTooltip('Remove BME 160 Lecture'));
      await tester.pumpAndSettle();
      expect(find.text('Fix or remove the classes marked in red to save.'), findsNothing);
      await tester.tap(find.text('Save 1 class'));
      await tester.pumpAndSettle();
      expect(rig.schedule.stored.map((m) => m.course), ['ART 20']);
    });

    testWidgets('removing a class can be undone', (tester) async {
      final rig = rigFor(myUcsc());
      await open(tester, rig);
      await readPicture(tester);
      await tester.tap(find.byTooltip('Remove XYZ 10 Lecture'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Found 3 classes.'), findsOneWidget);
      expect(card('XYZ 10 Lecture'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Found 4 classes.'), findsOneWidget);
      expect(card('XYZ 10 Lecture'), findsOneWidget);
    });

    testWidgets('removing every class leaves nothing to save, and leaving needs no question', (tester) async {
      final rig = rigFor(cards(), term: term);
      await open(tester, rig);
      await readPicture(tester);
      await tester.tap(find.byTooltip('Remove BME 160 Lecture'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove ART 20 Discussion'));
      await tester.pumpAndSettle();
      expect(find.text('No classes left.'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Save 0 classes');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(find.byTooltip('Cancel import'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this import?'), findsNothing);
      expect(find.text('Check your classes'), findsNothing);
    });

    testWidgets('the editor says what is wrong before it lets go of a class', (tester) async {
      final rig = rigFor(cards(), term: term);
      await open(tester, rig);
      await readPicture(tester);
      await tester.tap(card('BME 160 Lecture'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'BME 160'), '');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the course, like CSE 130.'), findsOneWidget);
      await tester.tap(find.text('Remove class'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Found 1 class.'), findsOneWidget);
    });
  });

  group('rooms', () {
    testWidgets('a room the server does not know is marked, and the room search finds the right one', (tester) async {
      final rig = rigFor(cards(room: 'Baskin Engr 15Z'), term: term);
      rig.search.resolutions['Baskin Engr 15Z'] = const RoomResolution(kind: 'unknown');
      rig.search.answer = [
        const Place(
          buildingId: 'baskin-engineering',
          buildingName: 'Jack Baskin Engineering',
          label: 'Jack Baskin Engineering 152',
          query: 'Jack Baskin Engineering 152',
          room: '152',
          roomKnown: true,
        ),
      ];
      await open(tester, rig);
      await readPicture(tester);

      expect(find.textContaining('Found 2 classes, 1 needs a look.'), findsOneWidget);
      expect(find.text("I don't recognise this room."), findsOneWidget);
      await tester.tap(find.text('Find the room'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Baskin Engr 15Z'), findsOneWidget, reason: 'starts from what was read');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(rig.search.queries, ['Baskin Engr 15Z']);
      await tester.tap(find.text('Jack Baskin Engineering 152'));
      await tester.pumpAndSettle();

      expect(find.text("I don't recognise this room."), findsNothing);
      expect(find.text('Jack Baskin Engineering 152'), findsOneWidget);
      expect(find.textContaining('Found 2 classes.'), findsOneWidget);
      await tester.tap(find.text('Save 2 classes'));
      await tester.pumpAndSettle();
      expect(rig.schedule.stored.first.location, 'Jack Baskin Engineering 152');
    });

    testWidgets('a building the server knows with a room number it does not list says so', (tester) async {
      final rig = rigFor(cards(), term: term);
      rig.search.resolutions['Baskin Engineering 152'] = const RoomResolution(kind: 'building', roomKnown: false);
      await open(tester, rig);
      await readPicture(tester);
      expect(find.text("That room number isn't one I know in this building."), findsOneWidget);
      expect(find.text('Find the room'), findsOneWidget);
    });

    testWidgets('online and to-be-announced rooms are not looked for', (tester) async {
      final rig = rigFor(cards(room: 'Online'), term: term);
      rig.search.resolutions['Online'] = const RoomResolution(kind: 'online');
      await open(tester, rig);
      await readPicture(tester);
      expect(find.textContaining('Found 2 classes.'), findsOneWidget);
      expect(find.text('Find the room'), findsNothing);
    });

    testWidgets('each distinct room is asked about once, and again when it is changed', (tester) async {
      final rig = rigFor(myUcsc());
      await open(tester, rig);
      await readPicture(tester);
      expect(rig.search.resolved.toSet(), hasLength(4));
      expect(rig.search.resolved, hasLength(4));
      await tester.tap(card('XYZ 10 Lecture'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Kresge Acad 3201'), 'Kresge Acad 3105');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(rig.search.resolved.last, 'Kresge Acad 3105');
      expect(rig.search.resolved, hasLength(5));
    });

    testWidgets('when the server cannot be reached the rooms are saved as read, and that is said', (tester) async {
      final rig = rigFor(myUcsc());
      for (final room in ['Cowell Acad 113', 'Kresge Acad 3201', 'J Baskin Engr 156', 'Earth&Marine B206']) {
        rig.search.resolutions[room] = const ApiException("Can't reach the server.", kind: ApiErrorKind.offline);
      }
      await open(tester, rig);
      await readPicture(tester);
      expect(find.textContaining("Couldn't check the rooms with the server"), findsOneWidget);
      expect(find.textContaining('Found 4 classes.'), findsOneWidget);
      await tester.tap(find.text('Save 4 classes'));
      await tester.pumpAndSettle();
      expect(rig.schedule.stored, hasLength(4));
    });
  });

  group('dates', () {
    testWidgets('a class with no dates in the picture takes the term the server reports, and says so', (tester) async {
      final rig = rigFor(cards(), term: term);
      await open(tester, rig);
      await readPicture(tester);
      expect(find.textContaining('run 2026-09-24 to 2026-12-04'), findsOneWidget);
      await tester.tap(find.text('Save 2 classes'));
      await tester.pumpAndSettle();
      expect({for (final m in rig.schedule.stored) (m.startDate, m.endDate)}, {('2026-09-24', '2026-12-04')});
    });

    testWidgets('a class given its own dates keeps them when the shared dates change', (tester) async {
      final rig = rigFor(cards(), term: term);
      await open(tester, rig);
      await readPicture(tester);
      await tester.tap(card('BME 160 Lecture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-09-24'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('28'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change dates'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '10/05/2026');
      await tester.enterText(fields.at(1), '12/11/2026');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save 2 classes'));
      await tester.pumpAndSettle();
      final byCourse = {for (final m in rig.schedule.stored) m.course: (m.startDate, m.endDate)};
      expect(byCourse['BME 160'], ('2026-09-28', '2026-12-04'), reason: 'its own start date stays');
      expect(byCourse['ART 20'], ('2026-10-05', '2026-12-11'), reason: 'the other takes the new shared dates');
    });

    testWidgets('with no term to use, the dates must be chosen before the classes can be saved', (tester) async {
      final rig = rigFor(cards());
      await open(tester, rig);
      await readPicture(tester);
      expect(find.textContaining('Choose when they run.'), findsOneWidget);
      expect(find.text('Choose dates'), findsOneWidget);
      expect(find.text('Pick the first and last dates.'), findsNWidgets(2));
      final save = find.widgetWithText(FilledButton, 'Save 2 classes');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
    });

    testWidgets('a page that shows its dates needs no term', (tester) async {
      await open(tester, rigFor(myUcsc()));
      await readPicture(tester);
      expect(find.textContaining('The picture shows no dates'), findsNothing);
    });
  });

  group('looks', () {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('the review and the editor at ${scale}x text', (tester) async {
        final rig = rigFor(
          cards(days: 'MoWer', room: 'Baskin Engineering 152'),
          term: term,
        );
        rig.search.resolutions['Baskin Engineering 152'] = const RoomResolution(kind: 'unknown');
        await open(tester, rig, textScale: scale);
        await readPicture(tester);
        expect(tester.takeException(), isNull, reason: 'review');
        await tester.tap(find.text('Edit').first);
        await tester.pumpAndSettle();
        expect(find.text('Edit class'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'editor');
      });
    }
  });
}
