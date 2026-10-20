import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A first look at every tab on a fresh install, for checking the wording and layout.
void main() {
  final binding = bindEnvironment();

  testWidgets('every tab of a fresh install', (tester) async {
    await startApp(tester, prefs: {'server_url': localServer});
    await shot(binding, tester, 'tour-map', settle: const Duration(seconds: 6));
    for (final name in ['Today', 'Schedule', 'Settings']) {
      await tester.tap(tab(name));
      await tester.pump(const Duration(seconds: 2));
      await shot(binding, tester, 'tour-${name.toLowerCase()}');
    }
  });
}
