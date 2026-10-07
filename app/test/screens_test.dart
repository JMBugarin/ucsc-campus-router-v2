import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/features/location/location_service.dart';
import 'package:ucsc_router/features/schedule/meeting.dart';
import 'package:ucsc_router/features/settings/settings.dart';
import 'package:ucsc_router/features/settings/settings_screen.dart';
import 'package:ucsc_router/features/today/today_models.dart';

import 'helpers.dart';

Future<void> open(WidgetTester tester, TestRig rig) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
}

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  group('Today', () {
    testWidgets('asks for a server address first', (tester) async {
      await open(tester, TestRig(serverUrl: ''));
      expect(find.text('Connect to the server'), findsOneWidget);

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Server address'), findsOneWidget);
    });

    testWidgets('with no classes it points to the schedule', (tester) async {
      await open(tester, TestRig());
      expect(find.text('Add your classes'), findsOneWidget);

      await tester.tap(find.text('Go to Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('My schedule'), findsOneWidget);
    });

    testWidgets('shows the day: headline, walk, banner and a verdict on each gap', (tester) async {
      final rig = TestRig(stored: [meeting()], analysis: Analysis.fromJson(fixture('today_late')));
      await open(tester, rig);

      expect(find.text('Next: XYZ 10 Lecture at 2:40 PM in 10 min.'), findsOneWidget);
      expect(find.textContaining('Leave now for XYZ 10 Lecture'), findsOneWidget); // the banner
      expect(find.textContaining("you'd arrive about 2 min late"), findsOneWidget);
      expect(find.text('Late'), findsWidgets, reason: 'status is a word, not just a colour');
      expect(find.text("Today's classes"), findsOneWidget);
      expect(find.text('XYZ 10 Discussion'), findsOneWidget);
      expect(find.textContaining('2:40 PM–3:45 PM'), findsOneWidget);
      expect(find.textContaining('·  next'), findsOneWidget);
    });

    testWidgets('a failure says what happened and offers to retry', (tester) async {
      final rig = TestRig(stored: [meeting()]);
      rig.today.answer = const ApiException(
        "Can't reach the server. Check your connection and the server address in Settings.",
        kind: ApiErrorKind.offline,
      );
      await open(tester, rig);

      expect(find.text("Couldn't work out your day"), findsOneWidget);
      expect(find.textContaining("Can't reach the server"), findsOneWidget);

      rig.today.answer = Analysis.fromJson(fixture('today_before_class'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Next: XYZ 10 Lecture at 2:40 PM'), findsOneWidget);
    });

    testWidgets('a location problem is shown beside the answer', (tester) async {
      final rig = TestRig(stored: [meeting()]);
      rig.location.result = const LocationResult.unavailable('Location permission was not given.');
      await open(tester, rig);
      expect(find.text('Location permission was not given.'), findsOneWidget);
      expect(find.textContaining('Next: XYZ 10 Lecture'), findsOneWidget);
    });
  });

  group('Schedule', () {
    testWidgets('lists the classes and flags a room it cannot place', (tester) async {
      final rig = TestRig(stored: [meeting(), meeting(course: 'NEW 1', location: 'Nowhere Hall 9')]);
      rig.schedule.nextImport = const ImportResult(
        meetings: [],
        notes: [],
        locations: [
          LocationInfo(kind: 'building', buildingName: 'Kresge College Academic Building'),
          LocationInfo(kind: 'unknown'),
        ],
      );
      await open(tester, rig);
      await goToTab(tester, 'Schedule');

      expect(find.text('XYZ 10 Lecture'), findsOneWidget);
      expect(find.textContaining('MoWeFr  2:40 PM–3:45 PM'), findsNWidgets(2));
      expect(find.textContaining('Kresge Acad 3201 (Kresge College Academic Building)'), findsOneWidget);
      expect(find.textContaining("Not recognised, so the walk can't be timed"), findsOneWidget);
    });

    testWidgets('pasting a schedule imports it and says what happened', (tester) async {
      final rig = TestRig();
      rig.schedule.nextImport = ImportResult(
        meetings: [meeting()],
        notes: const ['Skipped DEF 30 (dropped).'],
        locations: const [LocationInfo(kind: 'building', buildingName: 'Kresge College Academic Building')],
      );
      await open(tester, rig);
      await goToTab(tester, 'Schedule');

      await tester.tap(find.text('Paste from MyUCSC'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'my schedule text');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(rig.schedule.calls, contains('text:my schedule text'));
      expect(find.textContaining('Added 1 class. Skipped DEF 30 (dropped).'), findsOneWidget);
      expect(find.text('XYZ 10 Lecture'), findsOneWidget);
    });

    testWidgets('a calendar file is read and cancelling does nothing', (tester) async {
      final rig = TestRig();
      rig.schedule.nextImport = ImportResult(meetings: [meeting()], notes: const [], locations: const []);
      await open(tester, rig);
      await goToTab(tester, 'Schedule');

      rig.pickedCalendarText = null; // the person backs out of the file picker
      await tester.tap(find.text('Calendar file'));
      await tester.pumpAndSettle();
      expect(rig.schedule.calls.where((c) => c.startsWith('ics')), isEmpty);

      rig.pickedCalendarText = 'BEGIN:VCALENDAR\nEND:VCALENDAR';
      await tester.tap(find.text('Calendar file'));
      await tester.pumpAndSettle();
      expect(rig.schedule.calls, contains('ics:BEGIN:VCALENDAR\nEND:VCALENDAR'));
      expect(find.textContaining('Added 1 class'), findsOneWidget);
    });

    testWidgets("an import the server rejects shows the server's reason", (tester) async {
      final rig = TestRig();
      rig.schedule.failWith = const ApiException("That doesn't look like a calendar (.ics) file.",
          kind: ApiErrorKind.rejected);
      await open(tester, rig);
      await goToTab(tester, 'Schedule');

      await tester.tap(find.text('Paste from MyUCSC'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(find.textContaining("doesn't look like a calendar"), findsOneWidget);
    });

    testWidgets('a class can be removed, and all of them after confirming', (tester) async {
      final rig = TestRig(stored: [meeting(), meeting(course: 'ABC 20')]);
      await open(tester, rig);
      await goToTab(tester, 'Schedule');

      await tester.tap(find.byTooltip('Remove XYZ 10 Lecture'));
      await tester.pumpAndSettle();
      expect(find.text('XYZ 10 Lecture'), findsNothing);
      expect(find.text('ABC 20 Lecture'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove all classes'));
      await tester.pumpAndSettle();
      expect(find.text('Remove all classes?'), findsOneWidget);
      await tester.tap(find.text('Remove all'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No classes yet'), findsOneWidget);
      expect(rig.schedule.stored, isEmpty);
    });

    testWidgets('the add-a-class form checks its fields before sending anything', (tester) async {
      final rig = TestRig();
      await open(tester, rig);
      await goToTab(tester, 'Schedule');

      await tester.tap(find.text('Add a class'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the course, like CSE 130.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Course'), 'cse 130');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pick the days it meets'), findsOneWidget);

      await tester.tap(find.text('Mo'));
      await tester.tap(find.text('We'));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a start and end time.'), findsOneWidget);
      expect(rig.schedule.calls, isEmpty, reason: 'nothing is sent until the form is complete');
    });
  });

  group('Settings', () {
    Future<TestRig> openSettings(WidgetTester tester, {Map<String, http.Response>? server, String url = ''}) async {
      final rig = TestRig(serverUrl: url);
      final overrides = await rig.overrides();
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        retry: (count, error) => null,
        overrides: [
          ...overrides,
          apiClientProvider.overrideWith((ref) => ApiClient(
                baseUrl: ref.watch(settingsProvider).serverUrl,
                client: MockClient((request) async =>
                    server?[request.url.path] ?? http.Response('{"error":"nope"}', 404)),
              )),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.pumpAndSettle();
      return rig;
    }

    testWidgets('a nonsense address is refused and not saved', (tester) async {
      await openSettings(tester);
      await tester.enterText(find.byType(TextField), 'not a url');
      await tester.tap(find.text('Save and test'));
      await tester.pumpAndSettle();
      expect(find.textContaining("doesn't look like a server address"), findsOneWidget);
    });

    testWidgets('a good address is tidied, saved and tested', (tester) async {
      await openSettings(tester, server: {'/api/meta': http.Response('{"nodes": 1960}', 200)});
      await tester.enterText(find.byType(TextField), 'router.example/');
      await tester.tap(find.text('Save and test'));
      await tester.pumpAndSettle();
      expect(find.text('https://router.example'), findsOneWidget);
      expect(find.textContaining('Connected. The server knows 1960 campus path points.'), findsOneWidget);
    });

    testWidgets('a server that does not answer properly is reported', (tester) async {
      await openSettings(tester);
      await tester.enterText(find.byType(TextField), 'https://router.example');
      await tester.tap(find.text('Save and test'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved, but'), findsOneWidget);
    });

    testWidgets('plain http to the internet gets a warning', (tester) async {
      await openSettings(tester, server: {'/api/meta': http.Response('{"nodes": 1}', 200)});
      await tester.enterText(find.byType(TextField), 'http://router.example');
      await tester.tap(find.text('Save and test'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not secure (http)'), findsOneWidget);
    });

    testWidgets('the location switch is remembered', (tester) async {
      await openSettings(tester);
      final location = find.widgetWithText(SwitchListTile, 'Use my location');
      await tester.tap(location);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(location).value, isFalse);
    });

    testWidgets('reminders turn on only once notifications are allowed', (tester) async {
      final rig = await openSettings(tester);
      final reminders = find.widgetWithText(SwitchListTile, 'Leave-now reminders');

      rig.scheduler.allowed = false;
      await tester.tap(reminders);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(reminders).value, isFalse);
      expect(find.textContaining('Notifications are blocked'), findsOneWidget);

      rig.scheduler.allowed = true;
      await tester.tap(reminders);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(reminders).value, isTrue);
      expect(find.textContaining('Notifications are blocked'), findsNothing);
    });

    testWidgets('a test notification can be sent once reminders are on', (tester) async {
      final rig = await openSettings(tester);
      expect(find.text('Send a test notification'), findsNothing);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Leave-now reminders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send a test notification'));
      await tester.pumpAndSettle();
      expect(rig.scheduler.shown, ['test']);
    });
  });
}
