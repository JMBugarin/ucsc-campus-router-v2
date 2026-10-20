import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/app.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/features/location/location_service.dart';
import 'package:ucsc_router/features/search/place.dart';
import 'package:ucsc_router/features/search/search_repository.dart';
import 'package:ucsc_router/features/today/today_models.dart';

import 'helpers.dart';
import 'ocr_pages.dart';

/// Monday 2026-10-12, noon on the campus clock.
final mondayNoon = DateTime.utc(2026, 10, 12, 19);

const phones = {
  'an iPhone 17': (Size(1206, 2622), 3.0),
  'an iPhone SE': (Size(750, 1334), 2.0),
};

const manyPlaces = [
  Place(
    buildingId: 'baskin-engineering',
    buildingName: 'Jack Baskin Engineering',
    label: 'Jack Baskin Engineering 152',
    query: 'Jack Baskin Engineering 152',
    room: '152',
    roomKnown: true,
    floor: 'L1',
    point: GeoPoint(37.0004, -122.0633),
  ),
  Place(
    buildingId: 'baskin-engineering',
    buildingName: 'Jack Baskin Engineering',
    label: 'Jack Baskin Engineering 156',
    query: 'Jack Baskin Engineering 156',
    room: '156',
    roomKnown: false,
  ),
  Place(
    buildingId: 'baskin-engineering',
    buildingName: 'Jack Baskin Engineering',
    label: 'Jack Baskin Engineering',
    query: 'Jack Baskin Engineering',
  ),
  Place(
    buildingId: 'earth-marine',
    buildingName: 'Earth and Marine Sciences Building',
    label: 'Earth and Marine Sciences Building B206',
    query: 'Earth and Marine Sciences Building B206',
    room: 'B206',
    roomKnown: true,
  ),
  Place(
    buildingId: 'thimann-lecture',
    buildingName: 'Thimann Lecture Hall',
    label: 'Thimann Lecture Hall 003',
    query: 'Thimann Lecture Hall 003',
    room: '003',
    roomKnown: true,
  ),
  Place(
    buildingId: 'kresge-academic',
    buildingName: 'Kresge College Academic Building',
    label: 'Kresge College Academic Building 3201',
    query: 'Kresge College Academic Building 3201',
    room: '3201',
    roomKnown: true,
  ),
];

TestRig rig({int startTab = tabMap, ({String start, String end})? term}) => TestRig(
      stored: [
        meeting(days: const [0, 1, 2, 3, 4, 5, 6]),
        meeting(course: 'ABC 20', start: '16:00', end: '17:05', location: 'Thim Lecture 003', days: const [0, 1, 2, 3, 4, 5, 6]),
      ],
      analysis: Analysis.fromJson(fixture('today_before_class')),
      now: mondayNoon,
      startTab: startTab,
      term: term,
    )..search.answer = manyPlaces;

void screen(WidgetTester tester, Size size, double ratio, double textScale) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> tab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  for (final phone in phones.entries) {
    for (final scale in [1.0, 2.0, 3.0]) {
      group('${phone.key} at text size ${scale}x', () {
        final (size, ratio) = phone.value;

        testWidgets('the Map with a long list of results and a place picked', (tester) async {
          screen(tester, size, ratio, scale);
          await tester.pumpWidget(await rig().app());
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'BE 15');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Jack Baskin Engineering 152'), findsOneWidget);

          await tester.tap(find.text('Jack Baskin Engineering 152'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Route here'), findsOneWidget);
        });

        testWidgets('a route, and a route that could not be found', (tester) async {
          screen(tester, size, ratio, scale);
          final r = rig(startTab: tabToday);
          await tester.pumpWidget(await r.app());
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Show route'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Show route'));
          await tester.pumpAndSettle();
          expect(find.textContaining('min on foot'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'route');

          await tester.tap(find.byTooltip('Back'));
          await tester.pumpAndSettle();
          r.route.answer = const ApiException('I could not find a walking route there, and this sentence is long.', kind: ApiErrorKind.rejected);
          await tester.ensureVisible(find.text('Show route'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Show route'));
          await tester.pumpAndSettle();
          expect(find.text('Try again'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'no route');
        });

        testWidgets('the paste and add-a-class dialogs', (tester) async {
          screen(tester, size, ratio, scale);
          await tester.pumpWidget(await rig(startTab: tabSchedule).app());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Paste from MyUCSC'));
          await tester.pumpAndSettle();
          expect(find.text('Paste your schedule'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'paste');
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Add a class'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'add a class');
        });

        testWidgets('the classes read from a picture, a class being edited, and the room finder', (tester) async {
          screen(tester, size, ratio, scale);
          final r = rig(startTab: tabSchedule, term: (start: '2026-09-24', end: '2026-12-04'))
            ..picker.path = '/fake/schedule.png'
            ..recognizer.reading = (OcrPage()
                  ..line(60, 100, 'BME 160 Lecture')
                  ..line(60, 150, 'MoWer 1:20 PM - 2:25 PM')
                  ..line(60, 200, 'Baskin Engineering 152')
                  ..line(60, 400, 'ART 20 Discussion')
                  ..line(60, 450, 'Th 8:30 AM - 9:35 AM')
                  ..line(60, 500, 'Thimann 101'))
                .build();
          r.search.resolutions['Baskin Engineering 152'] = const RoomResolution(kind: 'unknown');
          await tester.pumpWidget(await r.app());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Read a photo'));
          await tester.pumpAndSettle();
          expect(find.text('Check your classes'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'review');

          await tester.scrollUntilVisible(find.text('Find the room'), 200, scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Find the room'));
          await tester.pumpAndSettle();
          expect(find.text('Find the room'), findsWidgets);
          expect(tester.takeException(), isNull, reason: 'room finder');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'room finder results');
          await tester.tapAt(const Offset(5, 5));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Edit').first);
          await tester.pumpAndSettle();
          expect(find.text('Edit class'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'editor');
        });

        testWidgets('Today, the Schedule, the Settings and the Week', (tester) async {
          screen(tester, size, ratio, scale);
          await tester.pumpWidget(await rig(startTab: tabToday).app());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final label in ['Schedule', 'Settings', 'Today']) {
            await tab(tester, label);
            expect(tester.takeException(), isNull, reason: label);
          }
          await tester.tap(find.byTooltip('Week'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Week');
        });
      });
    }
  }

  group('the Map', () {
    testWidgets('shows the clear button only when there is something to clear', (tester) async {
      screen(tester, const Size(1206, 2622), 3.0, 1.0);
      await tester.pumpWidget(await rig().app());
      await tester.pumpAndSettle();
      expect(find.byTooltip('Clear search'), findsNothing);

      await tester.enterText(find.byType(TextField), 'BE');
      await tester.pump();
      expect(find.byTooltip('Clear search'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.byTooltip('Clear search'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('the place card spans the screen between its margins', (tester) async {
      screen(tester, const Size(1206, 2622), 3.0, 1.0);
      await tester.pumpWidget(await rig().app());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'BE 152');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jack Baskin Engineering 152'));
      await tester.pumpAndSettle();

      final card = tester.getRect(find.ancestor(of: find.text('Route here'), matching: find.byType(Card)).first);
      expect((card.left, card.right), (0, 402), reason: 'the iPhone 17 is 402 points wide, and the card brings its own 12 point margin');
      expect(tester.getSize(find.widgetWithText(FilledButton, 'Route here')).width, closeTo(402 - 2 * 12 - 2 * 16, 0.5));
    });

    testWidgets('the search bar sits below the status bar while the map fills the screen', (tester) async {
      screen(tester, const Size(1206, 2622), 3.0, 1.0);
      tester.view.padding = const FakeViewPadding(top: 141); // a 47 point status bar and island
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(await rig().app());
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byType(TextField)).dy, greaterThanOrEqualTo(47 + 12));
      expect(tester.getTopLeft(find.bySemanticsLabel('Campus map')).dy, 0, reason: 'the map runs under the status bar');
      expect(tester.getSize(find.byKey(const ValueKey('statusBarVeil'))).height, 47, reason: 'a veil keeps the clock readable');
    });

    testWidgets('the map and the places are named for a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      screen(tester, const Size(1206, 2622), 3.0, 1.0);
      await tester.pumpWidget(await rig().app());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'BE 152');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Campus map'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Jack Baskin Engineering 156[\s\S]*Not on the building')), findsOneWidget);

      await tester.tap(find.text('Jack Baskin Engineering 152'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Jack Baskin Engineering 152'), findsWidgets, reason: 'the pin on the map and the card');
      semantics.dispose();
    });
  });

  group('Today for a screen reader', () {
    testWidgets('a class status is a word, not only a colour', (tester) async {
      final semantics = tester.ensureSemantics();
      screen(tester, const Size(1206, 2622), 3.0, 1.0);
      await tester.pumpWidget(await rig(startTab: tabToday).app());
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsWidgets);
      expect(tester.getSemantics(find.byTooltip('Route to XYZ 10 Lecture')).tooltip, 'Route to XYZ 10 Lecture');
      semantics.dispose();
    });
  });
}
