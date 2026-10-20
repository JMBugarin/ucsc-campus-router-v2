import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Needs `python3 server/server.py` running on 127.0.0.1:8000, location allowed for the app and a
/// simulated location on campus (see docs/developer-notes.md, "Simulator checks").
/// The map's tiles come over the network after the screen is up; a screenshot taken straight away has gaps.
const mapTiles = Duration(seconds: 15);

void main() {
  final binding = bindEnvironment();

  testWidgets('a fresh install lands on the Map tab with no schedule', (tester) async {
    await startApp(tester, prefs: {'server_url': localServer});
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Add your classes'), findsNothing);
    expect(find.textContaining('Search a room or building'), findsOneWidget);
    await shot(binding, tester, '01-map-fresh-install');
  });

  for (final (query, label, shotName) in [
    ('BE 152', 'Jack Baskin Engineering 152', '02-map-search-be-152'),
    ('Thimann 101', 'Thimann Labs 101', '03-map-search-thimann-101'),
    ('Kresge 3201', 'Kresge College Academic Building 3201', '04-map-search-kresge-3201'),
  ]) {
    testWidgets('searching "$query" shows a result and a route', (tester) async {
      await startApp(tester, prefs: {'server_url': localServer});
      await tester.enterText(find.byType(TextField), query);
      await waitFor(tester, find.widgetWithText(ListTile, label, skipOffstage: false), timeout: const Duration(seconds: 30));
      await shot(binding, tester, '$shotName-results');

      await tester.tap(find.widgetWithText(ListTile, label).first);
      await tester.pumpAndSettle();
      expect(find.text('Route here'), findsOneWidget);
      await shot(binding, tester, '$shotName-place', settle: mapTiles);

      await tester.tap(find.text('Route here'));
      await waitFor(tester, find.textContaining('min on foot'), timeout: const Duration(seconds: 60));
      await shot(binding, tester, '$shotName-route', settle: mapTiles);
    });
  }

  testWidgets('importing a pasted schedule fills Today', (tester) async {
    await startApp(tester, prefs: {'server_url': localServer, 'use_location': false});
    await tester.tap(tab('Schedule'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No classes yet'), findsOneWidget);

    await tester.tap(find.text('Paste from MyUCSC'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, pastedSchedule);
    await tester.tap(find.text('Import'));
    await waitFor(tester, find.textContaining('Added 1 class'));
    await shot(binding, tester, '05-schedule-imported');

    await tester.tap(tab('Today'));
    await waitFor(tester, find.text("Today's classes"));
    expect(find.textContaining('XYZ 10'), findsWidgets);
  });

  testWidgets('Today times the walk to the next class from where the phone is', (tester) async {
    final around = savedScheduleAroundNow();
    await startApp(tester, prefs: {'server_url': localServer, 'schedule_v1': around.json});
    await tester.tap(tab('Today'));
    if (around.startsToday) {
      await waitFor(tester, find.textContaining('Walk to Kresge Acad 3201 is about'), timeout: const Duration(seconds: 60));
      expect(find.textContaining('from your location'), findsOneWidget);
    } else {
      await waitFor(tester, find.textContaining('Today, '));
    }
    await shot(binding, tester, '06-today');
  });

  testWidgets('the day picker changes the displayed day', (tester) async {
    await startApp(tester, prefs: {
      'server_url': localServer,
      'use_location': false,
      'schedule_v1': savedSchedule(),
    });
    await tester.tap(tab('Today'));
    await waitFor(tester, find.textContaining('Today, '));
    final todayLabel = tester.widget<Text>(find.textContaining('Today, ')).data!;

    await tester.tap(find.byTooltip('Next day'));
    await waitFor(tester, find.textContaining('Classes on '));
    expect(find.textContaining('Today, '), findsNothing);
    final bar = find.descendant(of: find.byType(TextButton), matching: find.byType(Text));
    expect(bar, findsWidgets);
    expect(find.text(todayLabel.replaceFirst('Today, ', '')), findsNothing, reason: 'now showing a different date');
    await shot(binding, tester, '07-today-next-day');

    await tester.tap(find.widgetWithText(TextButton, 'Today'));
    await waitFor(tester, find.textContaining('Today, '));
  });

  testWidgets('the week view lists the next seven days', (tester) async {
    await startApp(tester, prefs: {
      'server_url': localServer,
      'use_location': false,
      'schedule_v1': savedSchedule(),
    });
    await tester.tap(tab('Today'));
    await waitFor(tester, find.textContaining('Today, '));
    await tester.tap(find.byTooltip('Week'));
    await tester.pumpAndSettle();
    expect(find.text('Week'), findsOneWidget);
    expect(find.textContaining('Today, '), findsOneWidget);
    expect(find.textContaining('2:40 PM'), findsWidgets);
    await shot(binding, tester, '09-week-view');
  });

  testWidgets('Settings says what leaves the phone and which server gets it', (tester) async {
    await startApp(tester, prefs: {'server_url': localServer, 'use_location': false});
    await tester.tap(tab('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('What leaves your phone'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Right now this goes to 127.0.0.1.'), findsOneWidget);
    expect(find.textContaining('Photos: if you read a schedule from a photo'), findsOneWidget);
    await shot(binding, tester, '10-settings-privacy');
  });
}
