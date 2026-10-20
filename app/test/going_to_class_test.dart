import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/features/location/location_service.dart';
import 'package:ucsc_router/features/schedule/meeting.dart';

import 'arrive_test.dart' show downtown, sanFrancisco, campus;
import 'controllers_test.dart' show mondayNoon;
import 'helpers.dart';

const phones = {
  'an iPhone 17': (Size(1206, 2622), 3.0),
  'an iPhone SE': (Size(750, 1334), 2.0),
};

Future<TestRig> open(
  WidgetTester tester, {
  GeoPoint at = campus,
  bool schedule = true,
  Size size = const Size(1206, 2622),
  double ratio = 3.0,
  double textScale = 1.0,
  bool dark = false,
  void Function(TestRig)? setUp,
}) async {
  final rig = TestRig(
    stored: schedule ? [meeting()] : const [],
    now: mondayNoon,
    prefs: {'entry_point_choice': 'kerr-hall-bus-stop'},
  );
  rig.location.result = LocationResult.found(at);
  setUp?.call(rig);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  if (dark) tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
  return rig;
}

void unknownRoom(TestRig rig) => rig.schedule.nextImport = const ImportResult(
      meetings: [],
      notes: [],
      locations: [LocationInfo(kind: 'unknown')],
    );

void main() {
  group('the Going to class card', () {
    testWidgets('names the class, the time, the room and the building, with one clear button', (tester) async {
      await open(tester);
      expect(find.text('Going to class'), findsOneWidget);
      expect(find.text('XYZ 10 Lecture'), findsWidgets);
      expect(find.text('2:40 PM · Kresge Acad 3201 · Some Hall'), findsOneWidget);
      expect(find.text('Show route'), findsOneWidget);
    });

    testWidgets('is a header for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(tester.getSemantics(find.text('Going to class')), matchesSemantics(isHeader: true, label: 'Going to class'));
      handle.dispose();
    });

    testWidgets('off campus it says when to be at the entry point, and the button is Transit', (tester) async {
      await open(tester, at: downtown);
      expect(find.text('Going to class'), findsOneWidget);
      expect(find.text('2:40 PM · Kresge Acad 3201 · Some Hall'), findsOneWidget);
      expect(find.text("You're not on campus yet"), findsOneWidget);
      expect(find.text('Be at Kerr Hall bus stop by 2:20 PM'), findsWidgets);
      expect(find.text('Get to campus with Transit'), findsOneWidget);
      expect(find.text('Show route'), findsNothing);
    });

    for (final phone in phones.entries) {
      for (final scale in [1.0, 3.0]) {
        for (final dark in [false, true]) {
          testWidgets('fits on ${phone.key} at ${scale}x text${dark ? ' in dark mode' : ''}', (tester) async {
            final (size, ratio) = phone.value;
            for (final at in [campus, downtown, sanFrancisco]) {
              await open(tester, at: at, size: size, ratio: ratio, textScale: scale, dark: dark);
              expect(tester.takeException(), isNull, reason: '$at');
            }
            await open(tester, size: size, ratio: ratio, textScale: scale, dark: dark, setUp: unknownRoom);
            expect(tester.takeException(), isNull, reason: 'unknown room');
            await open(tester, schedule: false, size: size, ratio: ratio, textScale: scale, dark: dark);
            expect(tester.takeException(), isNull, reason: 'first run');
          });
        }
      }
    }
  });

  group('when a student has no schedule yet', () {
    testWidgets('they can still find a room on the map', (tester) async {
      await open(tester, schedule: false);
      expect(find.text('Add your classes'), findsOneWidget);
      expect(find.textContaining('You can still find any room on the map'), findsOneWidget);
      await tester.tap(find.text('Find a room on the map'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Search a room or building'), findsOneWidget);
    });
  });

  group('when a room is not recognised', () {
    testWidgets('Today says so and sends the student to the map search', (tester) async {
      await open(tester, setUp: unknownRoom);
      expect(find.text("We can't find this room on the campus map."), findsOneWidget);
      expect(find.byTooltip('Route to XYZ 10 Lecture'), findsNothing);
      await tester.ensureVisible(find.text('Search the map'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search the map'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Search a room or building'), findsOneWidget);
    });

    testWidgets('a route that cannot be found offers the map search', (tester) async {
      final rig = await open(tester);
      rig.route.answer = const ApiException("I don't recognise that location", kind: ApiErrorKind.rejected);
      await tester.tap(find.text('Show route'));
      await tester.pumpAndSettle();
      expect(find.text("I don't recognise that location"), findsOneWidget);
      await tester.tap(find.text('Search the map instead'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Search a room or building'), findsOneWidget);
    });

    testWidgets('a server that is simply down offers a retry and no search', (tester) async {
      final rig = await open(tester);
      rig.route.answer = const ApiException('The server is down.', kind: ApiErrorKind.offline);
      await tester.tap(find.text('Show route'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Search the map instead'), findsNothing);
    });
  });
}
