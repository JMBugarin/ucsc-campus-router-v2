import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'where_test.dart' show twoClassesAhead;

/// The Map, Today and Going to class screens with two classes still to come. Needs the local server and a
/// simulated location; the screenshots are taken by the host script.
void main() {
  final binding = bindEnvironment();

  testWidgets('Map, Today and Going to class', (tester) async {
    await startApp(tester, prefs: {'server_url': localServer, 'schedule_v1': twoClassesAhead()});
    await tester.pump(const Duration(seconds: 6));
    await shot(binding, tester, 'a-map', settle: const Duration(seconds: 8));

    await tester.enterText(find.byType(TextField), 'BE 15');
    await tester.pump(const Duration(seconds: 3));
    await shot(binding, tester, 'b-map-results');
    await tester.tap(find.textContaining('Baskin Engineering 152').first);
    await tester.pump(const Duration(seconds: 3));
    await shot(binding, tester, 'c-map-place', settle: const Duration(seconds: 6));

    await tester.tap(tab('Today'));
    await waitFor(tester, find.text("Today's classes"), timeout: const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 3));
    await shot(binding, tester, 'd-today');

    await tester.tap(find.text('CSE 12 Lecture').first);
    await tester.pump(const Duration(seconds: 4));
    await shot(binding, tester, 'e-going', settle: const Duration(seconds: 8));
  });
}
