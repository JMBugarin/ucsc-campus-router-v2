import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/features/arrive/entry_walks.dart';
import 'package:ucsc_router/features/handoff/handoff.dart';
import 'package:ucsc_router/features/location/location_service.dart';

import 'arrive_test.dart' show downtown, sanFrancisco;
import 'controllers_test.dart' show mondayNoon;
import 'helpers.dart';

const kerr = GeoPoint(36.9968651, -122.0635781);

/// Runs as the iPhone app does, where the maps app is Apple Maps.
void iosTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

void main() {
  group('links', () {
    test('Transit gets the entry point as the destination and no starting point', () {
      expect(transitUri(kerr).toString(), 'transit://directions?to=36.9968651,-122.0635781');
      expect(transitUri(kerr).queryParameters.keys, ['to']);
    });

    test('the phone\'s maps app gets the same destination for each way of getting there', () {
      for (final mode in TravelMode.values) {
        expect(
          mapsUri(kerr, mode, platform: TargetPlatform.iOS).toString(),
          'https://maps.apple.com/directions?destination=36.9968651,-122.0635781&mode=${mode.name}',
        );
      }
      expect(mapsUri(kerr, TravelMode.cycling, platform: TargetPlatform.android).toString(),
          'https://www.google.com/maps/dir/?api=1&destination=36.9968651,-122.0635781&travelmode=bicycling');
      expect(mapsUri(kerr, TravelMode.transit, platform: TargetPlatform.android).queryParameters['travelmode'], 'transit');
    });

    test('no link carries where the student is', () {
      for (final uri in [transitUri(kerr), for (final m in TravelMode.values) mapsUri(kerr, m, platform: TargetPlatform.iOS)]) {
        expect(uri.toString(), isNot(contains('from=')));
        expect(uri.toString(), isNot(contains('source=')));
        expect(uri.toString(), isNot(contains('saddr=')));
      }
    });
  });

  group('opening Transit', () {
    test('Transit opens when it is installed', () async {
      final links = FakeLinkLauncher();
      expect(await openTransit(links, kerr, platform: TargetPlatform.iOS), HandoffResult.transit);
      expect(links.opened, [transitUri(kerr)]);
      expect(handoffMessage(HandoffResult.transit), isNull);
    });

    test('without Transit, transit directions open in the maps app instead', () async {
      final links = FakeLinkLauncher()..installed.clear();
      expect(await openTransit(links, kerr, platform: TargetPlatform.iOS), HandoffResult.mapsInstead);
      expect(links.opened.single.toString(), 'https://maps.apple.com/directions?destination=36.9968651,-122.0635781&mode=transit');
      expect(handoffMessage(HandoffResult.mapsInstead, platform: TargetPlatform.iOS),
          "Transit isn't installed, so this opened in Apple Maps.");
    });

    test('a launch that fails says so', () async {
      final broken = FakeLinkLauncher()..failing.add('transit');
      expect(await openTransit(broken, kerr), HandoffResult.failed);
      final nothing = FakeLinkLauncher()
        ..installed.clear()
        ..failing.add('https');
      expect(await openTransit(nothing, kerr), HandoffResult.failed);
      expect(handoffMessage(HandoffResult.failed, platform: TargetPlatform.iOS), contains("Couldn't open Transit or Apple Maps"));
    });

    test('the App Store page is Transit\'s', () {
      expect(transitStoreUri.toString(), 'https://apps.apple.com/us/app/transit-app/id498151501');
    });
  });

  group('on the Today screen', () {
    Future<TestRig> open(WidgetTester tester, {GeoPoint at = downtown, void Function(TestRig)? setUp, Map<String, Object>? prefs}) async {
      final rig = TestRig(stored: [meeting()], now: mondayNoon, prefs: prefs ?? {'entry_point_choice': 'kerr-hall-bus-stop'});
      rig.location.result = LocationResult.found(at);
      setUp?.call(rig);
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await rig.app());
      await tester.pumpAndSettle();
      return rig;
    }

    iosTest('the Transit button opens a trip to the entry point', (tester) async {
      final rig = await open(tester);
      await tester.tap(find.text('Get to campus with Transit'));
      await tester.pumpAndSettle();
      expect(rig.links.opened.single.toString(), 'transit://directions?to=36.9968651,-122.0635781');
      expect(find.byType(SnackBar), findsNothing);
    });

    iosTest('without Transit it opens Apple Maps and offers the App Store', (tester) async {
      final rig = await open(tester, setUp: (r) => r.links.installed.clear());
      await tester.tap(find.text('Get to campus with Transit'));
      await tester.pumpAndSettle();
      expect(rig.links.opened.single.host, 'maps.apple.com');
      expect(rig.links.opened.single.queryParameters['mode'], 'transit');
      expect(find.text("Transit isn't installed, so this opened in Apple Maps."), findsOneWidget);
      await tester.tap(find.text('Get Transit'));
      await tester.pumpAndSettle();
      expect(rig.links.opened.last, transitStoreUri);
    });

    iosTest('a failed launch is explained', (tester) async {
      final rig = await open(tester, setUp: (r) => r.links.failing.add('transit'));
      await tester.tap(find.text('Get to campus with Transit'));
      await tester.pumpAndSettle();
      expect(rig.links.opened, hasLength(1));
      expect(find.textContaining("Couldn't open Transit"), findsOneWidget);
    });

    iosTest('walking, biking, driving and transit open in Apple Maps', (tester) async {
      final rig = await open(tester);
      for (final (label, mode) in [('Walk there', 'walking'), ('Bike there', 'cycling'), ('Drive there', 'driving'), ('Public transit', 'transit')]) {
        await tester.tap(find.text('Open in Apple Maps'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(rig.links.opened.last.host, 'maps.apple.com');
        expect(rig.links.opened.last.queryParameters['mode'], mode);
        expect(rig.links.opened.last.queryParameters['destination'], '36.9968651,-122.0635781');
      }
    });

    iosTest('a far-away student is not offered Transit but can still open the maps app', (tester) async {
      await open(tester, at: sanFrancisco);
      expect(find.text('Get to campus with Transit'), findsNothing);
      expect(find.text('Open in Apple Maps'), findsOneWidget);
    });

    iosTest('another entry point can be picked, and the pick is remembered', (tester) async {
      final rig = await open(tester);
      expect(find.text('Be at Kerr Hall bus stop by 2:20 PM'), findsWidgets);
      await tester.tap(find.text('Change entry point'));
      await tester.pumpAndSettle();
      expect(find.text('Where will you arrive on campus?'), findsOneWidget);
      expect(find.textContaining('min on foot to Kresge Acad 3201'), findsWidgets);
      await tester.tap(find.text('Core West parking structure'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Be at Core West parking structure by'), findsWidgets);
      await tester.tap(find.text('Get to campus with Transit'));
      await tester.pumpAndSettle();
      final core = EntryWalks.fromJson(fixture('entry_walks')).walks.firstWhere((w) => w.entry.id == 'core-west-parking').entry.point;
      expect(rig.links.opened.single, transitUri(core));
      final prefs = await rig.container();
      addTearDown(prefs.dispose);
      expect(prefs.read(entryChoiceProvider), 'core-west-parking');
    });

    iosTest('on campus there are no trip buttons', (tester) async {
      await open(tester, at: const GeoPoint(36.9998, -122.0628));
      expect(find.text('Get to campus with Transit'), findsNothing);
      expect(find.text('Change entry point'), findsNothing);
    });
  });
}
