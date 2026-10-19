import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/app.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/features/location/location_service.dart';
import 'package:ucsc_router/features/route/destination.dart';
import 'package:ucsc_router/features/search/place.dart';

import 'helpers.dart';

const kresge = Place(
  buildingId: 'kresge-academic',
  buildingName: 'Kresge College Academic Building',
  label: 'Kresge College Academic Building 3201',
  query: 'Kresge College Academic Building 3201',
  room: '3201',
  roomKnown: true,
  floor: 'L3',
  point: GeoPoint(36.9998, -122.0655),
);

Future<void> open(WidgetTester tester, TestRig rig) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  group('Map tab', () {
    testWidgets('is the first thing a fresh install shows, with no schedule', (tester) async {
      final rig = TestRig(startTab: tabMap);
      await open(tester, rig);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Add your classes'), findsNothing);
    });

    testWidgets('searches a room, shows it, and routes to it without a schedule', (tester) async {
      final rig = TestRig(startTab: tabMap)..search.answer = [kresge];
      await open(tester, rig);

      await type(tester, 'kresge 3201');
      expect(rig.search.queries, ['kresge 3201']);
      await tester.tap(find.text(kresge.label));
      await tester.pumpAndSettle();
      expect(find.text('Floor L3'), findsOneWidget);

      await tester.tap(find.text('Route here'));
      await tester.pumpAndSettle();
      expect(rig.route.requests.single.destination, const RoomDestination('Kresge College Academic Building 3201'));
      expect(find.textContaining('min on foot'), findsOneWidget);
    });

    testWidgets('says so when nothing matches, and shows the server error when search fails', (tester) async {
      final rig = TestRig(startTab: tabMap);
      await open(tester, rig);

      await type(tester, 'zzzz');
      expect(find.textContaining('No match'), findsOneWidget);

      rig.search.answer = const ApiException("Can't reach the server.", kind: ApiErrorKind.offline);
      await type(tester, 'BE 152');
      expect(find.text("Can't reach the server."), findsOneWidget);
    });

    testWidgets('warns when a room is not on the building list', (tester) async {
      const unlisted = Place(
        buildingId: 'baskin-engineering',
        buildingName: 'Jack Baskin Engineering',
        label: 'Jack Baskin Engineering 15',
        query: 'Jack Baskin Engineering 15',
        room: '15',
        roomKnown: false,
      );
      final rig = TestRig(startTab: tabMap)..search.answer = [unlisted];
      await open(tester, rig);
      await type(tester, 'BE 15');
      expect(find.text("Not on the building's room list"), findsOneWidget);
      await tester.tap(find.text(unlisted.label));
      await tester.pumpAndSettle();
      expect(find.textContaining("nearest door"), findsOneWidget);
    });

    testWidgets('a class on Today still opens its route', (tester) async {
      final rig = TestRig(stored: [meeting()], startTab: tabMap);
      await open(tester, rig);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show route'));
      await tester.pumpAndSettle();
      expect(rig.route.requests.single.destination, const RoomDestination('Kresge Acad 3201'));
    });
  });
}
