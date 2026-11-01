import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

/// The whole app on a simulator or phone, with nothing running beside it:
/// `flutter test integration_test/app_test.dart -d <simulator>`.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets(
    'a fresh install opens on the map and finds a room that Apple and Google Maps do not know',
    (tester) async {
      await startApp(tester);
      expect(find.text('Add your classes'), findsNothing);
      await tester.enterText(find.byType(TextField), 'BE 152');
      await waitFor(tester, find.text('Jack Baskin Engineering 152'));
      await shot(binding, tester, 'map-search');
      await tester.tap(find.text('Jack Baskin Engineering 152'));
      await tester.pumpAndSettle();
      expect(find.text('Walk there'), findsOneWidget);
      await shot(binding, tester, 'map-place');
    },
  );

  testWidgets('a pasted schedule shows up on Today and on the map', (
    tester,
  ) async {
    await startApp(tester);
    await tester.tap(tab('Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste from MyUCSC'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), pastedSchedule);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Added 1 class'), findsOneWidget);
    await shot(binding, tester, 'schedule');

    await tester.tap(tab('Today'));
    await tester.pumpAndSettle();
    expect(find.text("Today's classes"), findsOneWidget);
    expect(find.text('XYZ 10 Lecture'), findsOneWidget);
    expect(
      find.textContaining(
        'Kresge Acad 3201 · Kresge College Academic Building',
      ),
      findsOneWidget,
    );
    await shot(binding, tester, 'today');

    await tester.tap(find.byTooltip('Show XYZ 10 Lecture on the map'));
    await tester.pumpAndSettle();
    expect(find.text('Kresge College Academic Building 3201'), findsWidgets);
    expect(find.text('Walk there'), findsOneWidget);
    await shot(binding, tester, 'map-class');

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('never asks for your location'), findsOneWidget);
    await shot(binding, tester, 'settings');
  });
}
