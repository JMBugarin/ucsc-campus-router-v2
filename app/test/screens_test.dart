import 'package:classmap/app.dart';
import 'package:classmap/features/directions/directions.dart';
import 'package:classmap/features/schedule/import/clean.dart';
import 'package:classmap/features/schedule/meeting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> open(WidgetTester tester, TestRig rig) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
}

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Meeting everyDay({
  String course = 'XYZ 10',
  String start = '14:40',
  String end = '15:45',
  String location = 'Kresge Acad 3201',
}) => Meeting(
  course: course,
  component: 'Lecture',
  days: const [0, 1, 2, 3, 4, 5, 6],
  start: start,
  end: end,
  location: location,
  startDate: '2000-01-01',
  endDate: '2100-01-01',
);

void main() {
  group('Today', () {
    testWidgets('with no classes it points to the schedule', (tester) async {
      await open(tester, TestRig(now: mondayNoon));
      expect(find.text('Add your classes'), findsOneWidget);

      await tester.tap(find.text('Go to Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('My schedule'), findsOneWidget);
    });

    testWidgets('with no classes it still offers the map', (tester) async {
      await open(tester, TestRig(now: mondayNoon));
      await tester.tap(find.text('Find a room on the map'));
      await tester.pumpAndSettle();
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: 'the map search is showing',
      );
    });

    testWidgets(
      'shows what is on today: the headline, each class, its room, and the break between them',
      (tester) async {
        final rig = TestRig(
          stored: [
            meeting(start: '09:00', end: '09:50', days: const [0]),
            meeting(
              course: 'ABC 20',
              start: '14:40',
              end: '15:45',
              days: const [0],
              location: 'Cowell Acad 113',
            ),
          ],
          now: mondayNoon,
        );
        await open(tester, rig);

        expect(
          find.text('Next: ABC 20 Lecture at 2:40 PM in 2 h 40 min.'),
          findsOneWidget,
        );
        expect(find.text("Today's classes"), findsOneWidget);
        expect(find.text('XYZ 10 Lecture'), findsOneWidget);
        expect(find.text('ABC 20 Lecture'), findsOneWidget);
        expect(
          find.textContaining('Cowell Acad 113 · '),
          findsOneWidget,
          reason: 'the room, then the building it is in',
        );
        expect(find.textContaining('after your last class'), findsOneWidget);
        expect(
          find.text('Next'),
          findsOneWidget,
          reason: 'the next class is marked',
        );
      },
    );

    testWidgets(
      'Walk there opens walking directions in Apple Maps on an iPhone',
      (tester) async {
        final rig = TestRig(stored: [meeting()], now: mondayNoon);
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await open(tester, rig);
          await tester.tap(find.text('Walk there'));
          await tester.pumpAndSettle();
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
        final target = walkTarget(testCampus, 'Kresge Acad 3201')!;
        expect(rig.urls.opened, [walkingDirectionsUri(target, android: false)]);
        expect(rig.urls.opened.single.host, 'maps.apple.com');
        expect(rig.urls.opened.single.queryParameters['dirflg'], 'w');
      },
    );

    testWidgets('and in Google Maps on Android', (tester) async {
      final rig = TestRig(stored: [meeting()], now: mondayNoon);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await open(tester, rig);
        await tester.tap(find.text('Walk there'));
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      expect(rig.urls.opened.single.host, 'www.google.com');
      expect(rig.urls.opened.single.queryParameters['travelmode'], 'walking');
    });

    testWidgets('when the maps app cannot be opened it says so', (
      tester,
    ) async {
      final rig = TestRig(stored: [meeting()], now: mondayNoon)
        ..urls.succeeds = false;
      await open(tester, rig);
      await tester.tap(find.text('Walk there'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't open your maps app."), findsOneWidget);
    });

    testWidgets('an online class has nothing to walk to', (tester) async {
      final rig = TestRig(
        stored: [meeting(location: 'Online')],
        now: mondayNoon,
      );
      await open(tester, rig);
      expect(find.text('XYZ 10 Lecture'), findsOneWidget);
      expect(find.text('Walk there'), findsNothing);
      expect(find.byTooltip('Show XYZ 10 Lecture on the map'), findsNothing);
    });

    testWidgets(
      'a room that is not on the campus map is flagged and sends you to the search',
      (tester) async {
        final rig = TestRig(
          stored: [meeting(location: 'Mystery Hall 9')],
          now: mondayNoon,
        );
        await open(tester, rig);
        expect(
          find.text("We can't find this room on the campus map."),
          findsOneWidget,
        );
        expect(find.text('Walk there'), findsNothing);

        await tester.tap(find.text('Search the map'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
      },
    );

    testWidgets(
      'a class can be shown on the map, with its own Walk there button',
      (tester) async {
        final rig = TestRig(stored: [meeting()], now: mondayNoon);
        await open(tester, rig);

        await tester.tap(find.byTooltip('Show XYZ 10 Lecture on the map'));
        await tester.pumpAndSettle();
        expect(
          find.text('Kresge College Academic Building 3201'),
          findsNWidgets(2),
          reason: 'the search box and the place card',
        );
        expect(find.text('Walk there'), findsOneWidget);
      },
    );

    testWidgets('the day picker shows another day and goes back to today', (
      tester,
    ) async {
      await open(tester, TestRig(stored: [everyDay()], now: mondayNoon));
      expect(find.textContaining('Today, '), findsOneWidget);
      expect(find.text('Walk there'), findsOneWidget);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Today, '), findsNothing);
      expect(
        find.text('Walk there'),
        findsNothing,
        reason: 'there is no "next" class on another day',
      );
      expect(find.text('1 class, 2:40 PM to 3:45 PM.'), findsOneWidget);
      expect(find.text('Classes on Tue, Oct 13'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Today'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Today, '), findsOneWidget);
      expect(find.text("Today's classes"), findsOneWidget);
    });

    testWidgets('after the last class it says so and names the next one', (
      tester,
    ) async {
      final rig = TestRig(
        stored: [
          meeting(days: const [0]),
        ],
        now: DateTime.utc(2026, 10, 13, 2),
      ); // Monday 7 PM
      await open(tester, rig);
      expect(
        find.text('Done for today. Next class: Mon 2:40 PM, XYZ 10 Lecture.'),
        findsOneWidget,
      );
    });

    testWidgets('on a day with no class it says so and names the next one', (
      tester,
    ) async {
      final rig = TestRig(
        stored: [
          meeting(days: const [0]),
        ],
        now: DateTime.utc(2026, 10, 13, 19),
      ); // Tuesday noon
      await open(tester, rig);
      expect(
        find.text('No classes today. Next class: Mon 2:40 PM, XYZ 10 Lecture.'),
        findsOneWidget,
      );
    });
  });

  group('Schedule', () {
    testWidgets('lists the classes and flags a room it cannot place', (
      tester,
    ) async {
      final rig = TestRig(
        stored: [
          meeting(),
          meeting(course: 'NEW 1', location: 'Nowhere Hall 9'),
        ],
      );
      rig.schedule.nextImport = const ImportResult(
        meetings: [],
        notes: [],
        locations: [
          LocationInfo(
            kind: 'building',
            buildingName: 'Kresge College Academic Building',
          ),
          LocationInfo(kind: 'unknown'),
        ],
      );
      await open(tester, rig);
      await goToTab(tester, 'Schedule');

      expect(find.text('XYZ 10 Lecture'), findsOneWidget);
      expect(find.textContaining('MoWeFr  2:40 PM–3:45 PM'), findsNWidgets(2));
      expect(
        find.textContaining(
          'Kresge Acad 3201 (Kresge College Academic Building)',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining("Not recognised, so it can't be shown on the map"),
        findsOneWidget,
      );
    });

    testWidgets('pasting a schedule imports it and says what happened', (
      tester,
    ) async {
      final rig = TestRig();
      rig.schedule.nextImport = ImportResult(
        meetings: [meeting()],
        notes: const ['Skipped DEF 30 (dropped).'],
        locations: const [
          LocationInfo(
            kind: 'building',
            buildingName: 'Kresge College Academic Building',
          ),
        ],
      );
      await open(tester, rig);
      await goToTab(tester, 'Schedule');

      await tester.tap(find.text('Paste from MyUCSC'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'my schedule text');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(rig.schedule.calls, contains('text:my schedule text'));
      expect(
        find.textContaining('Added 1 class. Skipped DEF 30 (dropped).'),
        findsOneWidget,
      );
      expect(find.text('XYZ 10 Lecture'), findsOneWidget);
    });

    testWidgets('the message after an import floats above the tab bar, so the tabs stay tappable', (tester) async {
      final rig = TestRig();
      rig.schedule.nextImport = ImportResult(meetings: [meeting()], notes: const [], locations: const []);
      await open(tester, rig);
      await goToTab(tester, 'Schedule');
      await tester.tap(find.text('Paste from MyUCSC'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'my schedule text');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        tester.getRect(find.textContaining('Added 1 class')).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
      );
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Today')));
      await tester.pumpAndSettle();
      expect(find.text("Today's classes"), findsNothing, reason: 'Monday noon is before the default class, so Today shows it as the next');
    });

    testWidgets('a calendar file is read and cancelling does nothing', (
      tester,
    ) async {
      final rig = TestRig();
      rig.schedule.nextImport = ImportResult(
        meetings: [meeting()],
        notes: const [],
        locations: const [],
      );
      await open(tester, rig);
      await goToTab(tester, 'Schedule');

      rig.pickedCalendarText = null; // the person backs out of the file picker
      await tester.tap(find.text('Calendar file'));
      await tester.pumpAndSettle();
      expect(rig.schedule.calls.where((c) => c.startsWith('ics')), isEmpty);

      rig.pickedCalendarText = 'BEGIN:VCALENDAR\nEND:VCALENDAR';
      await tester.tap(find.text('Calendar file'));
      await tester.pumpAndSettle();
      expect(
        rig.schedule.calls,
        contains('ics:BEGIN:VCALENDAR\nEND:VCALENDAR'),
      );
      expect(find.textContaining('Added 1 class'), findsOneWidget);
    });

    testWidgets('an import that is refused shows the reason', (tester) async {
      final rig = TestRig();
      rig.schedule.failWith = const ScheduleError(
        "That doesn't look like a calendar (.ics) file.",
      );
      await open(tester, rig);
      await goToTab(tester, 'Schedule');

      await tester.tap(find.text('Paste from MyUCSC'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining("doesn't look like a calendar"),
        findsOneWidget,
      );
    });

    testWidgets('a class can be removed, and all of them after confirming', (
      tester,
    ) async {
      final rig = TestRig(
        stored: [
          meeting(),
          meeting(course: 'ABC 20'),
        ],
      );
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

    testWidgets(
      'the add-a-class form checks its fields before saving anything',
      (tester) async {
        final rig = TestRig();
        await open(tester, rig);
        await goToTab(tester, 'Schedule');

        await tester.tap(find.text('Add a class'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        expect(find.text('Enter the course, like CSE 130.'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'Course'),
          'cse 130',
        );
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Pick the days it meets'), findsOneWidget);

        await tester.tap(find.text('Mo'));
        await tester.tap(find.text('We'));
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        expect(find.text('Pick a start and end time.'), findsOneWidget);
        expect(
          rig.schedule.calls,
          isEmpty,
          reason: 'nothing is saved until the form is complete',
        );
      },
    );
  });

  group('Settings', () {
    testWidgets(
      'has no server or location settings, and says the data stays on the phone',
      (tester) async {
        await open(tester, TestRig(startTab: tabSettings));
        expect(
          find.textContaining('server address', findRichText: true),
          findsNothing,
        );
        expect(find.text('Use my location'), findsNothing);
        expect(
          find.textContaining('There is no account and no server'),
          findsOneWidget,
        );
        expect(
          find.textContaining('never asks for your location'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Not affiliated with or endorsed by UC Santa Cruz',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('reminders turn on only once notifications are allowed', (
      tester,
    ) async {
      final rig = TestRig(startTab: tabSettings);
      await open(tester, rig);
      final reminders = find.widgetWithText(SwitchListTile, 'Class reminders');

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

    testWidgets('a test notification can be sent once reminders are on', (
      tester,
    ) async {
      final rig = TestRig(startTab: tabSettings);
      await open(tester, rig);
      expect(find.text('Send a test notification'), findsNothing);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Class reminders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send a test notification'));
      await tester.pumpAndSettle();
      expect(rig.scheduler.shown, ['test']);
    });

    testWidgets('the lead time is chosen from a list and remembered', (
      tester,
    ) async {
      final rig = TestRig(startTab: tabSettings);
      await open(tester, rig);
      await tester.tap(find.text('10 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min').last);
      await tester.pumpAndSettle();
      expect(find.text('30 min'), findsOneWidget);
    });
  });
}
