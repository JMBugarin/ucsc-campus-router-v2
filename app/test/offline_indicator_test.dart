import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/core/format.dart';
import 'package:ucsc_router/features/today/today_models.dart';
import 'package:ucsc_router/features/today/today_text.dart';
import 'package:ucsc_router/features/today/walk_cache.dart';

import 'helpers.dart';

/// Monday 2026-10-19, 1:00 PM Pacific. A class at 2:40 PM is later today.
final monday1pm = DateTime.utc(2026, 10, 19, 20);

String savedWalks({Duration? age, bool withTime = true}) => jsonEncode({
      'walks': {'*>Kresge Acad 3201': 8},
      'any': {'Kresge Acad 3201': 8},
      'holidays': <String>[],
      if (withTime) 'at': monday1pm.subtract(age ?? const Duration(hours: 3)).millisecondsSinceEpoch,
    });

const offline = ApiException("Can't reach the server.", kind: ApiErrorKind.offline);

Future<void> open(WidgetTester tester, TestRig rig) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
}

TestRig rigWith({String? walks, Object? answer = offline, bool useLocation = true}) => TestRig(
      stored: [meeting(days: const [0, 1, 2, 3, 4, 5, 6])],
      analysis: answer,
      useLocation: useLocation,
      now: monday1pm,
      prefs: {'walk_cache_v1': ?walks},
    );

void main() {
  group('how old the saved walk times are', () {
    test('ago reads in minutes, hours and days', () {
      expect(agoText(const Duration(seconds: 20)), 'just now');
      expect(agoText(const Duration(minutes: 5)), '5 min ago');
      expect(agoText(const Duration(minutes: 59)), '59 min ago');
      expect(agoText(const Duration(hours: 3, minutes: 30)), '3 h ago');
      expect(agoText(const Duration(hours: 23)), '23 h ago');
      expect(agoText(const Duration(days: 1, hours: 2)), '1 day ago');
      expect(agoText(const Duration(days: 4)), '4 days ago');
    });

    test('the cache records when the server last answered', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = WalkCache(await SharedPreferences.getInstance(), clock: () => monday1pm);
      expect(cache.savedAt, isNull);
      await cache.remember(Analysis.fromJson(fixture('today_before_class')));
      expect(cache.savedAt, DateTime.fromMillisecondsSinceEpoch(monday1pm.millisecondsSinceEpoch));
    });

    test('a cache saved before the time was kept, or a broken one, has no age', () async {
      SharedPreferences.setMockInitialValues({'walk_cache_v1': savedWalks(withTime: false)});
      expect(WalkCache(await SharedPreferences.getInstance()).savedAt, isNull);
      SharedPreferences.setMockInitialValues({'walk_cache_v1': 'not json'});
      expect(WalkCache(await SharedPreferences.getInstance()).savedAt, isNull);
    });

    test('the line says how old, warns when old, and covers the unknown cases', () {
      String line({bool hasWalks = true, DateTime? at, DateTime? now}) =>
          savedWalksText(hasWalks: hasWalks, savedAt: at, now: now ?? monday1pm);
      expect(line(at: monday1pm.subtract(const Duration(hours: 3))), 'Walk times were last updated 3 h ago.');
      expect(
        line(at: monday1pm.subtract(const Duration(days: 9))),
        'Walk times were last updated 9 days ago. They may be out of date.',
      );
      expect(line(), 'Walk times are from an earlier visit.');
      expect(line(hasWalks: false), "No walk times are saved yet, so walks can't be timed.");
    });

    test('a saved walk is worded as saved, with no starting point claimed', () {
      final analysis = Analysis.fromJson(fixture('today_before_class'));
      expect(walkText(analysis)!.text, startsWith('Walk to Kresge Acad 3201 is about 12 min from your location.'));
      expect(walkText(analysis, saved: true)!.text, startsWith('Saved walk time to Kresge Acad 3201: about 12 min.'));
    });
  });

  group('Today offline', () {
    testWidgets('says Offline, how old the walk times are, and words the walk as saved', (tester) async {
      await open(tester, rigWith(walks: savedWalks()));
      await tester.pumpAndSettle();

      expect(find.text('Offline'), findsOneWidget);
      expect(
        find.textContaining("Can't reach the server, so this is worked out on your phone. Walk times were last updated 3 h ago."),
        findsOneWidget,
      );
      expect(find.textContaining('Saved walk time to Kresge Acad 3201: about 8 min.'), findsOneWidget);
      expect(find.textContaining('from your location'), findsNothing);
    });

    testWidgets('warns when the saved walk times are a week old or more', (tester) async {
      await open(tester, rigWith(walks: savedWalks(age: const Duration(days: 10))));
      await tester.pumpAndSettle();
      expect(find.textContaining('last updated 10 days ago. They may be out of date.'), findsOneWidget);
    });

    testWidgets('with nothing saved it says walks cannot be timed', (tester) async {
      await open(tester, rigWith());
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      expect(find.textContaining("No walk times are saved yet, so walks can't be timed."), findsOneWidget);
      expect(find.textContaining('Saved walk time'), findsNothing);
    });

    testWidgets('Try again asks the server, and the banner goes when it answers', (tester) async {
      final rig = rigWith(walks: savedWalks());
      await open(tester, rig);
      await tester.pumpAndSettle();
      final asked = rig.today.requests.length;

      rig.today.answer = Analysis.fromJson(fixture('today_before_class'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(rig.today.requests.length, asked + 1);
      expect(find.text('Offline'), findsNothing);
      expect(find.textContaining('Walk to Kresge Acad 3201 is about 12 min from your location.'), findsOneWidget);
    });

    testWidgets('another day shows the banner too', (tester) async {
      final rig = rigWith(walks: savedWalks());
      await open(tester, rig);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      expect(find.textContaining('Walk times were last updated 3 h ago.'), findsOneWidget);
    });
  });

  group('Today while the server answers', () {
    testWidgets('shows what the phone has saved, marked as updating, then the real answer', (tester) async {
      final slow = Completer<Analysis>();
      final rig = rigWith(walks: savedWalks(), answer: slow.future);
      await open(tester, rig);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Updating…'), findsOneWidget);
      expect(find.textContaining('Showing what is saved on this phone while the server answers.'), findsOneWidget);
      expect(find.textContaining('Walk times were last updated 3 h ago.'), findsOneWidget);
      expect(find.text('Next: XYZ 10 Lecture at 2:40 PM in 1 h 40 min.'), findsOneWidget);
      expect(find.text('Working out your day…'), findsNothing);
      expect(find.textContaining('waking up'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('waking up'), findsOneWidget);

      slow.complete(Analysis.fromJson(fixture('today_before_class')));
      await tester.pumpAndSettle();
      expect(find.text('Updating…'), findsNothing);
      expect(find.textContaining('waking up'), findsNothing);
    });

    testWidgets('with nothing saved it is the plain loading card', (tester) async {
      final rig = rigWith(answer: Completer<Analysis>().future);
      await open(tester, rig);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Working out your day…'), findsOneWidget);
      expect(find.text('Updating…'), findsNothing);
    });
  });
}
