import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'where_test.dart' show twoClassesAhead;

/// Needs the local server and a simulated location off campus. Transit is not installed in the
/// Simulator, so the button falls back to Apple Maps.
void main() {
  final binding = bindEnvironment();

  testWidgets('the route from an entry point and the trip handoff, from off campus', (tester) async {
    await startApp(tester, prefs: {'server_url': localServer, 'schedule_v1': twoClassesAhead()});
    await tester.tap(tab('Today'));
    await waitFor(tester, find.text("You're not on campus yet"), timeout: const Duration(seconds: 60));
    await shot(binding, tester, 'trip-today');

    await tester.tap(find.byTooltip('Route to CSE 12 Lecture'));
    await waitFor(tester, find.textContaining('This walk starts at'), timeout: const Duration(seconds: 60));
    await shot(binding, tester, 'trip-route', settle: const Duration(seconds: 12));

    await tester.tap(find.text('Get to campus with Transit'));
    await tester.pump(const Duration(seconds: 5));
    await shot(binding, tester, 'trip-handoff');
  });
}
