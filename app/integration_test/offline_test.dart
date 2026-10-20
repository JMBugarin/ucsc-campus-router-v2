import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Run with `--dart-define=SERVER_URL=http://127.0.0.1:1`: nothing listens there, so the app is offline.
void main() {
  final binding = bindEnvironment();

  testWidgets('with the server unreachable Today lists the classes, says it is offline and uses the saved walk time', (tester) async {
    final around = savedScheduleAroundNow();
    await startApp(tester, prefs: {
      'schedule_v1': around.json,
      'use_location': false,
      'walk_cache_v1': '{"walks":{"Soc Sci 2 075>Kresge Acad 3201":8},"any":{"Kresge Acad 3201":8},"holidays":[]}',
    });
    await tester.tap(tab('Today'));
    await waitFor(tester, find.text('Offline'));
    expect(find.textContaining("worked out on your phone"), findsOneWidget);
    expect(find.textContaining('XYZ 10'), findsWidgets);
    if (around.startsToday) await waitFor(tester, find.textContaining('Saved walk time to Kresge Acad 3201: about 8 min'));
    expect(find.text("Couldn't work out your day"), findsNothing);
    await shot(binding, tester, '08-today-offline');

    await tester.tap(find.byTooltip('Week'));
    await tester.pumpAndSettle();
    expect(find.text('Week'), findsOneWidget);
    expect(find.textContaining('Today, '), findsOneWidget);
    expect(find.textContaining('No-class days are not saved yet'), findsOneWidget, reason: 'the saved walk times carry no holiday dates');
    await shot(binding, tester, '11-week-view-offline');
  });
}
