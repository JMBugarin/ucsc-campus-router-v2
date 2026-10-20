import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/core/pacific.dart';

import 'support.dart';

/// Needs the local server and the simulator's location set (`xcrun simctl location <id> set <lat>,<lon>`),
/// so the same run can be repeated from campus, from town and from far away.
String twoClassesAhead() {
  final now = pacificTime(DateTime.now());
  String clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return jsonEncode([
    for (final (course, room, minutes) in [('CSE 12', 'Kresge Acad 3201', 90), ('MATH 19B', 'Thim Lecture 003', 180)])
      {
        'course': course,
        'title': 'Sample',
        'section': '01',
        'component': 'Lecture',
        'class_nbr': '10002',
        'days': [0, 1, 2, 3, 4, 5, 6],
        'start': clock(now.add(Duration(minutes: minutes))),
        'end': clock(now.add(Duration(minutes: minutes + 60))),
        'location': room,
        'start_date': '2025-01-01',
        'end_date': '2030-12-31',
      },
  ]);
}

void main() {
  final binding = bindEnvironment();

  testWidgets('Today from wherever the phone is', (tester) async {
    await startApp(tester, prefs: {'server_url': localServer, 'schedule_v1': twoClassesAhead()});
    await tester.tap(tab('Today'));
    await waitFor(tester, find.text("Today's classes"), timeout: const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 4));
    await shot(binding, tester, 'today');
  });
}
