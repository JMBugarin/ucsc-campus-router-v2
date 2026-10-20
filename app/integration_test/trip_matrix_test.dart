import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'where_test.dart' show twoClassesAhead;

/// Which server the app talks to: `online` (the local server), `old` (the code from before entry points,
/// standing in for the deployed server, on port 8001) or `offline` (nothing listens).
const mode = String.fromEnvironment('MODE', defaultValue: 'online');

const _savedEntryWalks = r'''{"Kresge Acad 3201":{"room":{"building_name":"Kresge College Academic Building"},"entry_points":[{"id":"kerr-hall-bus-stop","name":"Kerr Hall bus stop","type":"bus_stop","lat":36.9968651,"lon":-122.0635781,"minutes":10,"walk_m":739.6},{"id":"kresge-college-bus-stop","name":"Kresge College bus stop","type":"bus_stop","lat":36.9991748,"lon":-122.0645533,"minutes":11,"walk_m":769.2},{"id":"core-west-parking","name":"Core West parking structure","type":"parking","lat":36.9991152,"lon":-122.063643,"minutes":12,"walk_m":852.5},{"id":"science-hill-bus-stop","name":"Science Hill bus stop","type":"bus_stop","lat":36.9999131,"lon":-122.0623883,"minutes":13,"walk_m":973.3},{"id":"porter-college-bus-stop","name":"Porter College bus stop","type":"bus_stop","lat":36.9929959,"lon":-122.0652316,"minutes":14,"walk_m":988.3},{"id":"rachel-carson-bus-stop","name":"Rachel Carson College bus stop","type":"bus_stop","lat":36.9927855,"lon":-122.064816,"minutes":14,"walk_m":1017.3}]},"Thim Lecture 003":{"room":{"building_name":"Thimann Lecture Hall"},"entry_points":[{"id":"kerr-hall-bus-stop","name":"Kerr Hall bus stop","type":"bus_stop","lat":36.9968651,"lon":-122.0635781,"minutes":5,"walk_m":272.0},{"id":"science-hill-bus-stop","name":"Science Hill bus stop","type":"bus_stop","lat":36.9999131,"lon":-122.0623883,"minutes":6,"walk_m":382.5},{"id":"colleges-9-10-bus-stop","name":"Colleges 9 and 10 bus stop","type":"bus_stop","lat":36.9997701,"lon":-122.0582429,"minutes":7,"walk_m":424.3},{"id":"kresge-college-bus-stop","name":"Kresge College bus stop","type":"bus_stop","lat":36.9991748,"lon":-122.0645533,"minutes":8,"walk_m":509.6},{"id":"core-west-parking","name":"Core West parking structure","type":"parking","lat":36.9991152,"lon":-122.063643,"minutes":9,"walk_m":592.9},{"id":"crown-merrill-bus-stop","name":"Crown and Merrill bus stop","type":"bus_stop","lat":36.9990234,"lon":-122.0552341,"minutes":11,"walk_m":680.8}]}}''';

final _wanted = RegExp(r"Be at|not on campus|far from campus|Walk to|This walk starts|min on foot|Try again|Offline|can't plan|Can't reach|Couldn't|isn't available|Get to campus|Show route");

void report(WidgetTester tester, String label) {
  final seen = <String>{};
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final text = w.data;
    if (text != null && _wanted.hasMatch(text) && seen.add(text)) debugPrint('RESULT $label: $text');
  }
}

void main() {
  final binding = bindEnvironment();

  testWidgets('Today and the route to the next class ($mode)', (tester) async {
    final server = switch (mode) {
      'old' => 'http://127.0.0.1:8001',
      'offline' => deadServer,
      _ => localServer,
    };
    await startApp(tester, prefs: {
      'server_url': server,
      'schedule_v1': twoClassesAhead(),
      if (mode == 'offline') 'entry_walks_v1': _savedEntryWalks,
      if (mode == 'offline')
        'walk_cache_v1': '{"walks":{"*>Kresge Acad 3201":13},"any":{"Kresge Acad 3201":13},"holidays":[]}',
    });
    await tester.tap(tab('Today'));
    await waitFor(tester, find.text("Today's classes"), timeout: const Duration(seconds: 90));
    await tester.pump(const Duration(seconds: 4));
    report(tester, 'today');
    await shot(binding, tester, 'today');

    final byTooltip = find.byTooltip('Route to CSE 12 Lecture');
    await tester.drag(find.text("Today's classes"), const Offset(0, -420));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(byTooltip);
    await tester.pump(const Duration(seconds: 3));
    final done = find.byWidgetPredicate(
      (w) => w is Text && w.data != null && (w.data!.contains('min on foot') || w.data == 'Try again'),
    );
    await waitFor(tester, done, timeout: const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 6));
    report(tester, 'route');
    await shot(binding, tester, 'route');
  });
}
