import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/features/arrive/entry_walks.dart';
import 'package:ucsc_router/features/location/location_service.dart';

import 'arrive_test.dart' show downtown, sanFrancisco, campus;
import 'controllers_test.dart' show mondayNoon;
import 'helpers.dart';

Future<TestRig> open(WidgetTester tester, {GeoPoint at = downtown, Object? entryWalks}) async {
  final rig = TestRig(stored: [meeting()], now: mondayNoon, prefs: {'entry_point_choice': 'kerr-hall-bus-stop'});
  rig.location.result = LocationResult.found(at);
  if (entryWalks != null) rig.entryWalks.answer = entryWalks;
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
  return rig;
}

void main() {
  testWidgets('off campus, Today says when to be at an entry point instead of when to leave', (tester) async {
    await open(tester);
    expect(find.text("You're not on campus yet"), findsOneWidget);
    expect(find.text('Be at Kerr Hall bus stop by 2:20 PM'), findsWidgets);
    expect(find.textContaining('10 min on foot from there, plus 10 min to spare'), findsOneWidget);
    expect(find.text('Show route'), findsNothing);
  });

  testWidgets('far away, it says so and still gives the time', (tester) async {
    await open(tester, at: sanFrancisco);
    expect(find.text("You're far from campus"), findsOneWidget);
    expect(find.text('Be at Kerr Hall bus stop by 2:20 PM'), findsWidgets);
  });

  testWidgets('on campus, Today is what it was', (tester) async {
    await open(tester, at: campus);
    expect(find.text("You're not on campus yet"), findsNothing);
    expect(find.text('Show route'), findsOneWidget);
    expect(find.textContaining('Be at'), findsNothing);
  });

  testWidgets('an older server: the plain walk card stays and a note says why', (tester) async {
    await open(tester, entryWalks: const EntryWalksUnavailable());
    expect(find.text("You're not on campus yet"), findsNothing);
    expect(find.text('Show route'), findsOneWidget);
    expect(find.text(const EntryWalksUnavailable().message), findsOneWidget);
  });
}
