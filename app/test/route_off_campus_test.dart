import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/features/arrive/entry_walks.dart';
import 'package:ucsc_router/features/location/location_service.dart';
import 'package:ucsc_router/features/route/destination.dart';
import 'package:ucsc_router/features/route/route_repository.dart';

import 'arrive_test.dart' show downtown, sanFrancisco;
import 'controllers_test.dart' show mondayNoon;
import 'helpers.dart';

const kerr = GeoPoint(36.9968651, -122.0635781);

Future<TestRig> openRoute(
  WidgetTester tester, {
  LocationResult? location,
  Object? entryWalks,
}) async {
  final rig = TestRig(stored: [meeting()], now: mondayNoon, prefs: {'entry_point_choice': 'kerr-hall-bus-stop'});
  rig.location.result = location ?? const LocationResult.found(downtown);
  if (entryWalks != null) rig.entryWalks.answer = entryWalks;
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Route to XYZ 10 Lecture'));
  await tester.pumpAndSettle();
  return rig;
}

void main() {
  testWidgets('off campus the route starts at the entry point and the student\'s position is never sent', (tester) async {
    final rig = await openRoute(tester);
    expect(find.text("You're not on campus yet"), findsWidgets);
    expect(find.text('This walk starts at Kerr Hall bus stop.'), findsOneWidget);
    expect(find.text('Get to campus with Transit'), findsWidgets);
    expect(rig.route.requests.single.from, kerr);
    expect(rig.route.requests.single.from, isNot(downtown));
    expect(rig.route.requests.single.destination, const RoomDestination('Kresge Acad 3201'));
  });

  testWidgets('picking another entry point redraws the route from there', (tester) async {
    final rig = await openRoute(tester);
    await tester.tap(find.text('Change entry point').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Core West parking structure'));
    await tester.pumpAndSettle();
    expect(find.text('This walk starts at Core West parking structure.'), findsOneWidget);
    expect(rig.route.requests.last.from.lat, closeTo(36.9991152, 1e-6));
  });

  testWidgets('with location denied the entry points are still offered, shortest walk first', (tester) async {
    final rig = await openRoute(
      tester,
      location: const LocationResult.unavailable('Location permission was not given.'),
    );
    expect(find.text("Your location isn't available"), findsOneWidget);
    expect(find.text('Location permission was not given.'), findsOneWidget);
    expect(find.text('This walk starts at Kerr Hall bus stop.'), findsOneWidget);
    expect(rig.route.requests.single.from, kerr);
  });

  testWidgets('far away it says so and does not offer Transit', (tester) async {
    await openRoute(tester, location: const LocationResult.found(sanFrancisco));
    expect(find.text("You're far from campus"), findsWidgets);
    expect(find.text('Get to campus with Transit'), findsNothing);
  });

  testWidgets('an older server gets a plain message, not a crash', (tester) async {
    final rig = await openRoute(tester, entryWalks: const EntryWalksUnavailable());
    expect(find.text(const EntryWalksUnavailable().message), findsOneWidget);
    expect(rig.route.requests, isEmpty);
  });

  test('a dropped pin cannot be planned from off campus', () async {
    final rig = TestRig();
    rig.location.result = const LocationResult.found(downtown);
    final container = await rig.container();
    addTearDown(container.dispose);
    await expectLater(
      container.read(routeProvider(const PointDestination(GeoPoint(36.99, -122.06))).future),
      throwsA(isA<RouteProblem>().having((e) => e.message, 'message', contains("You're not on campus"))),
    );
    expect(rig.route.requests, isEmpty);
  });
}
