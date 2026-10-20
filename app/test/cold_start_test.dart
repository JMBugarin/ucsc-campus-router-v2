import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/app.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/core/waking_note.dart';
import 'package:ucsc_router/features/schedule/meeting.dart';
import 'package:ucsc_router/features/schedule/term.dart';
import 'package:ucsc_router/features/search/place.dart';
import 'package:ucsc_router/features/today/today_controller.dart';
import 'package:ucsc_router/features/today/today_models.dart';

import 'helpers.dart';

const waking = 'waking up';

Future<void> open(WidgetTester tester, TestRig rig, {List<Override> extra = const []}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: (count, error) => null,
    overrides: [...await rig.overrides(), ...extra],
    child: const UcscRouterApp(),
  ));
}

bool enabled(WidgetTester tester, String label) =>
    tester
        .widget<ButtonStyleButton>(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()))
        .onPressed !=
    null;

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the waking note says nothing at first, then explains the wait', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: WakingNote())));
    expect(find.textContaining(waking), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining(waking), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining(waking), findsOneWidget);
  });

  group('while the server wakes up', () {
    testWidgets('Today explains a slow start, then shows the day when the answer arrives', (tester) async {
      final slow = Completer<Analysis>();
      final rig = TestRig(stored: [meeting()], analysis: slow.future);
      await open(tester, rig);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Working out your day…'), findsOneWidget);
      expect(find.textContaining(waking), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining(waking), findsOneWidget);

      slow.complete(Analysis.fromJson(fixture('today_before_class')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Next: XYZ 10 Lecture at 2:40 PM'), findsOneWidget);
      expect(find.textContaining(waking), findsNothing);
    });

    testWidgets('a failed search offers to try again', (tester) async {
      const place = Place(
        buildingId: 'baskin-engineering',
        buildingName: 'Jack Baskin Engineering',
        label: 'Jack Baskin Engineering 152',
        query: 'Jack Baskin Engineering 152',
        room: '152',
        roomKnown: true,
      );
      final rig = TestRig(startTab: tabMap)
        ..search.answer = const ApiException('The server is taking a long time to answer.', kind: ApiErrorKind.timeout);
      await open(tester, rig);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'BE 152');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.textContaining('taking a long time'), findsOneWidget);

      rig.search.answer = [place];
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text(place.label), findsOneWidget);
      expect(rig.search.queries, ['BE 152', 'BE 152']);
    });

    testWidgets('an import shows that it is working, and says why it is slow', (tester) async {
      final gate = Completer<void>();
      final rig = TestRig();
      rig.schedule
        ..hold = gate.future
        ..nextImport = ImportResult(meetings: [meeting()], notes: const [], locations: const []);
      await open(tester, rig);
      await tester.pumpAndSettle();
      await goToTab(tester, 'Schedule');
      await tester.tap(find.text('Paste from MyUCSC'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'my schedule text');
      await tester.tap(find.text('Import'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Reading your schedule…'), findsOneWidget);
      expect(find.textContaining(waking), findsNothing);
      expect(enabled(tester, 'Add a class'), isFalse);

      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining(waking), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Reading your schedule…'), findsNothing);
      expect(find.textContaining('Added 1 class'), findsOneWidget);
      expect(enabled(tester, 'Add a class'), isTrue);
    });

    testWidgets('the add-a-class form does not wait on a sleeping server for the term dates', (tester) async {
      final rig = TestRig();
      await open(tester, rig, extra: [
        termProvider.overrideWith((ref) => Completer<({String start, String end})?>().future),
      ]);
      await tester.pumpAndSettle();
      await goToTab(tester, 'Schedule');

      await tester.tap(find.text('Add a class'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Course'), findsOneWidget);
    });
  });

  testWidgets('a hidden tab that is still loading does not keep animating', (tester) async {
    final rig = TestRig(stored: [meeting()], analysis: Completer<Analysis>().future, startTab: tabMap);
    await open(tester, rig);
    await tester.pumpAndSettle();
  });

  group('app start', () {
    testWidgets('the server is pinged when the app opens and again when it comes back', (tester) async {
      final rig = TestRig(startTab: tabMap);
      await open(tester, rig);
      await tester.pumpAndSettle();
      expect(rig.warmUps, 1);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(rig.warmUps, 2);
    });

    test('a quiet refresh is skipped while another is still waiting', () async {
      final slow = Completer<Analysis>();
      final rig = TestRig(stored: [meeting()], analysis: slow.future);
      final container = await rig.container();
      addTearDown(container.dispose);

      final first = container.read(todayProvider.future);
      await pumpEventQueue();
      expect(rig.today.requests, hasLength(1));

      await container.read(todayProvider.notifier).refresh(quiet: true);
      expect(rig.today.requests, hasLength(1));

      slow.complete(Analysis.fromJson(fixture('today_before_class')));
      await first;
      await container.read(todayProvider.notifier).refresh(quiet: true);
      expect(rig.today.requests, hasLength(2));
    });
  });
}
