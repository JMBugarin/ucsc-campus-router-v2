import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ucsc_router/core/pacific.dart';
import 'package:ucsc_router/main.dart' as app;

/// Where screenshots go. Pass `--dart-define=SHOT_DIR=/absolute/path` to keep them.
const shotDir = String.fromEnvironment('SHOT_DIR');

/// A local server for the tests that need one: `python3 server/server.py` on this machine.
const localServer = 'http://127.0.0.1:8000';

/// An address where nothing listens, so every request fails fast.
const deadServer = 'http://127.0.0.1:1';

Future<void> startApp(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  final store = await SharedPreferences.getInstance();
  await store.clear();
  for (final e in prefs.entries) {
    final v = e.value;
    if (v is String) await store.setString(e.key, v);
    if (v is bool) await store.setBool(e.key, v);
    if (v is int) await store.setInt(e.key, v);
  }
  await app.main();
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

/// Pumps until [finder] matches, or fails after [timeout]. Real network calls need real time.
Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets, reason: 'timed out waiting for it to appear');
}

/// Asks the host to take a screenshot of the simulator (`binding.takeScreenshot` returns blank
/// images after the first on iOS here). A watcher on the host, `scripts/sim_screenshots.sh`, sees
/// the request file, runs `xcrun simctl io booted screenshot`, and removes the request.
Future<void> shot(IntegrationTestWidgetsFlutterBinding binding, WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 800));
  if (shotDir.isEmpty) return;
  await Directory(shotDir).create(recursive: true);
  final request = File('$shotDir/.want-$name');
  await request.writeAsString('');
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (request.existsSync() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

/// A schedule in the layout MyUCSC prints, with a class every day so "today" is never empty.
const pastedSchedule = '''
XYZ 10 - Sample Calculus Status Units Grading Grade Deadlines Enrolled 5.00 Graded
Class Nbr Section Component Days & Times Room Instructor Start/End Date
10002 01 Lecture MoTuWeThFrSaSu 2:40PM - 3:45PM Kresge Acad 3201 To be Announced 01/01/2025 - 12/31/2030
''';

String savedSchedule() => jsonEncode([
      {
        'course': 'XYZ 10',
        'title': 'Sample Calculus',
        'section': '01',
        'component': 'Lecture',
        'class_nbr': '10002',
        'days': [0, 1, 2, 3, 4, 5, 6],
        'start': '14:40',
        'end': '15:45',
        'location': 'Kresge Acad 3201',
        'start_date': '2025-01-01',
        'end_date': '2030-12-31',
      }
    ]);

/// Two classes placed around now on the campus clock: one that ended 30 minutes ago in Soc Sci 2 075 and
/// XYZ 10, which starts in 30 minutes, so "next class" is later today at whatever time the test runs.
/// Within an hour and a half of midnight that is not possible, and [startsToday] is false.
({String json, bool startsToday}) savedScheduleAroundNow() {
  final now = pacificTime(DateTime.now());
  final classes = [
    (course: 'XYZ 5', room: 'Soc Sci 2 075', start: now.subtract(const Duration(minutes: 90))),
    (course: 'XYZ 10', room: 'Kresge Acad 3201', start: now.add(const Duration(minutes: 30))),
  ];
  String clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final meetings = [
    for (final c in classes)
      {
        'course': c.course,
        'title': 'Sample',
        'section': '01',
        'component': 'Lecture',
        'class_nbr': '10002',
        'days': [0, 1, 2, 3, 4, 5, 6],
        'start': clock(c.start),
        'end': clock(c.start.add(const Duration(minutes: 60))),
        'location': c.room,
        'start_date': '2025-01-01',
        'end_date': '2030-12-31',
      },
  ];
  final today = isoDate(now);
  final startsToday = classes.every((c) => isoDate(c.start) == today && isoDate(c.start.add(const Duration(minutes: 60))) == today);
  return (json: jsonEncode(meetings), startsToday: startsToday);
}

IntegrationTestWidgetsFlutterBinding bindEnvironment() => IntegrationTestWidgetsFlutterBinding.ensureInitialized();

Finder tab(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
