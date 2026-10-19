import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Run with `--dart-define=SERVER_URL=http://127.0.0.1:1`: nothing listens there, so the app is offline.
void main() {
  final binding = bindEnvironment();

  testWidgets('with the server unreachable Today lists the classes, says it is offline and uses the saved walk time', (tester) async {
    await startApp(tester, prefs: {
      'schedule_v1': savedSchedule(),
      'walk_cache_v1': '{"walks":{"*>Kresge Acad 3201":8},"any":{"Kresge Acad 3201":8},"holidays":[]}',
    });
    await tester.tap(tab('Today'));
    await waitFor(tester, find.textContaining("worked out on your phone"));
    expect(find.textContaining('XYZ 10'), findsWidgets);
    await waitFor(tester, find.textContaining('about 8 min'));
    expect(find.text("Couldn't work out your day"), findsNothing);
    await shot(binding, tester, '08-today-offline');
  });
}
