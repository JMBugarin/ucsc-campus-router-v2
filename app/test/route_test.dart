import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/features/location/location_service.dart';
import 'package:ucsc_router/features/route/route_plan.dart';
import 'package:ucsc_router/features/today/today_models.dart';

import 'helpers.dart';

const here = GeoPoint(36.9998, -122.0628);

Future<void> open(WidgetTester tester, TestRig rig) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
}

void main() {
  group('RoutePlan', () {
    test('is read from a real server answer', () {
      final plan = RoutePlan.fromJson(fixture('route_to_room'), start: here);
      expect(plan.path.length, greaterThan(5));
      expect(plan.buildingName, 'Kresge College Academic Building');
      expect(plan.room, '3201');
      expect(plan.walkM, closeTo(887.4, 15));
      expect(plan.minutes, ((plan.walkM + plan.indoorM) / 1.3 / 60).ceil());
      expect(plan.door.lat, closeTo(37.0, 0.01));
    });

    test('matches the walk time the server gives on the Today screen', () {
      // The Today fixture was made from the same start and room.
      final plan = RoutePlan.fromJson(fixture('route_to_room'), start: here);
      final walk = Analysis.fromJson(fixture('today_before_class')).walk!;
      expect(plan.minutes, walk.minutes);
    });

    test('a missing route is an error, not a blank map', () {
      final json = fixture('route_to_room');
      (json['astar'] as Map<String, dynamic>)['found'] = false;
      expect(() => RoutePlan.fromJson(json, start: here), throwsFormatException);
    });
  });

  group('route screen', () {
    testWidgets('the walk card opens a map with the walk summarised', (tester) async {
      final rig = TestRig(stored: [meeting()]);
      await open(tester, rig);

      await tester.tap(find.text('Show route'));
      await tester.pumpAndSettle();

      expect(rig.route.requests.single.room, 'Kresge Acad 3201');
      expect(rig.route.requests.single.from, const GeoPoint(36.9998, -122.0628));
      expect(find.textContaining('min on foot'), findsOneWidget);
      expect(find.textContaining('Kresge College Academic Building'), findsOneWidget);
      expect(find.textContaining('to the door'), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsNothing, reason: 'attribution is behind a button');
    });

    testWidgets('any class on the timeline can be routed to', (tester) async {
      final rig = TestRig(stored: [meeting()]);
      await open(tester, rig);

      await tester.tap(find.byTooltip('Route to XYZ 10 Lecture').first);
      await tester.pumpAndSettle();
      expect(rig.route.requests.single.room, 'Kresge Acad 3201');
    });

    testWidgets("the server's reason is shown when there is no walk (online class)", (tester) async {
      final rig = TestRig(stored: [meeting()]);
      rig.route.answer = const ApiException('that class is online, so there is nowhere to walk',
          kind: ApiErrorKind.rejected);
      await open(tester, rig);

      await tester.tap(find.text('Show route'));
      await tester.pumpAndSettle();
      expect(find.textContaining('online'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('without location it says why and does not call the server', (tester) async {
      final rig = TestRig(stored: [meeting()]);
      await open(tester, rig);
      rig.location.result = const LocationResult.unavailable('Location is turned off on this phone.');

      await tester.tap(find.text('Show route'));
      await tester.pumpAndSettle();
      expect(find.text('Location is turned off on this phone.'), findsOneWidget);
      expect(rig.route.requests, isEmpty);

      rig.location.result = const LocationResult.found(here);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('min on foot'), findsOneWidget);
    });
  });
}
