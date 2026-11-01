import 'package:classmap/app.dart';
import 'package:classmap/design/map_markers.dart';
import 'package:classmap/features/directions/directions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> open(WidgetTester tester, TestRig rig) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

void main() {
  group('Map tab', () {
    testWidgets('is the first thing a fresh install shows, with no schedule', (
      tester,
    ) async {
      final rig = TestRig(startTab: tabMap);
      await open(tester, rig);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Add your classes'), findsNothing);
      expect(find.byType(DestinationPin), findsNothing);
    });

    testWidgets(
      'searches a room, shows it, and offers a walk there without a schedule',
      (tester) async {
        final rig = TestRig(startTab: tabMap);
        await open(tester, rig);

        await type(tester, 'kresge 3201');
        expect(
          find.text('Kresge College Academic Building 3201'),
          findsOneWidget,
        );
        await tester.tap(find.text('Kresge College Academic Building 3201'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Floor '), findsOneWidget);
        expect(find.byType(DestinationPin), findsOneWidget);

        await tester.tap(find.text('Walk there'));
        await tester.pumpAndSettle();
        final target = walkTarget(
          testCampus,
          'Kresge College Academic Building 3201',
        )!;
        expect(
          rig.urls.opened.single.queryParameters.values,
          contains('${target.point.lat},${target.point.lon}'),
        );
      },
    );

    testWidgets('abbreviations and typos find the room', (tester) async {
      final rig = TestRig(startTab: tabMap);
      await open(tester, rig);

      await type(tester, 'BE 152');
      expect(find.text('Jack Baskin Engineering 152'), findsOneWidget);
      await type(tester, 'thiman 101');
      expect(find.textContaining('Thimann'), findsWidgets);
    });

    testWidgets('says so when nothing matches', (tester) async {
      final rig = TestRig(startTab: tabMap);
      await open(tester, rig);
      await type(tester, 'zzzz');
      expect(find.textContaining('No match'), findsOneWidget);
    });

    testWidgets('a failing search says so and offers to try again', (
      tester,
    ) async {
      final rig = TestRig(startTab: tabMap, fakeSearch: true)
        ..search.answer = Exception('broken');
      await open(tester, rig);
      await type(tester, 'BE 152');
      expect(find.text('Search failed. Try again.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('warns when a room is not on the building list', (
      tester,
    ) async {
      final rig = TestRig(startTab: tabMap);
      await open(tester, rig);
      await type(tester, 'BE 15');
      expect(find.text("Not on the building's room list"), findsWidgets);
      await tester.tap(find.text("Not on the building's room list").first);
      await tester.pumpAndSettle();
      expect(find.textContaining('the pin marks the building'), findsOneWidget);
      expect(find.text('Walk there'), findsOneWidget);
    });

    testWidgets('clearing the search removes the place card', (tester) async {
      final rig = TestRig(startTab: tabMap);
      await open(tester, rig);
      await type(tester, 'BE 152');
      await tester.tap(find.text('Jack Baskin Engineering 152'));
      await tester.pumpAndSettle();
      expect(find.text('Walk there'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Walk there'), findsNothing);
    });

    testWidgets(
      "today's classes are pinned, once for each place, and a pin opens its card",
      (tester) async {
        final rig = TestRig(
          stored: [
            meeting(start: '09:00', end: '09:50', days: const [0]),
            meeting(
              course: 'ABC 20',
              start: '11:00',
              end: '11:50',
              days: const [0],
            ),
            meeting(
              course: 'DEF 30',
              start: '14:40',
              end: '15:45',
              days: const [0],
              location: 'Cowell Acad 113',
            ),
            meeting(
              course: 'GHI 40',
              start: '16:00',
              end: '16:50',
              days: const [0],
              location: 'Online',
            ),
          ],
          startTab: tabMap,
          now: mondayNoon,
        );
        await open(tester, rig);
        expect(
          find.byType(DestinationPin),
          findsNWidgets(2),
          reason: 'two places; online has none',
        );

        await tester.tap(find.byType(DestinationPin).first);
        await tester.pumpAndSettle();
        expect(find.byType(DestinationPin), findsOneWidget);
        expect(find.text('Walk there'), findsOneWidget);
      },
    );

    testWidgets(
      'coming back to the app keeps the reminders and adds no duplicates',
      (tester) async {
        final rig = TestRig(
          stored: [meeting()],
          startTab: tabMap,
          remindersOn: true,
          now: mondayNoon,
        );
        await open(tester, rig);
        expect(
          rig.scheduler.scheduleCalls,
          3,
          reason: 'Monday, Wednesday and Friday',
        );

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(rig.scheduler.scheduleCalls, 3);
        expect(rig.scheduler.cancelled, isEmpty);
        expect(find.byType(DestinationPin), findsOneWidget);
      },
    );
  });
}
