import 'package:classmap/design/controls.dart';
import 'package:classmap/features/schedule/meeting.dart';
import 'package:classmap/features/today/week_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Monday 2026-10-19, 1:00 PM Pacific.
final monday = DateTime.utc(2026, 10, 19, 20);

Meeting cls({
  String course = 'XYZ 10',
  List<int> days = const [0, 2, 4],
  String start = '09:00',
  String end = '09:50',
}) => meeting(course: course, days: days, start: start, end: end);

TestRig rigWith(List<Meeting> classes, {DateTime? now}) =>
    TestRig(stored: classes, now: now ?? monday);

Future<void> open(WidgetTester tester, TestRig rig) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
}

Future<void> openWeek(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Week'));
  await tester.pumpAndSettle();
}

void main() {
  group('a week from the saved schedule', () {
    final classes = [
      cls(),
      cls(course: 'ABC 20', days: [0, 2], start: '13:00', end: '13:50'),
    ];
    final start = DateTime.utc(2026, 10, 19);

    test('counts the classes of each day and says why a day has none', () {
      final week = weekFrom(
        meetings: classes,
        start: start,
        holidays: const {},
      );
      expect([for (final d in week) d.classes.length], [2, 0, 2, 0, 1, 0, 0]);
      expect(
        [for (final d in week) d.reason],
        [null, 'no_classes', null, 'no_classes', null, 'weekend', 'weekend'],
      );
      expect(weekDayText(week[0]), '2 classes, 9:00 AM to 1:50 PM.');
      expect(weekDayText(week[4]), '1 class, 9:00 AM to 9:50 AM.');
      expect(weekDayText(week[1]), 'No classes.');
      expect(weekDayText(week[5]), 'No classes: weekend.');
    });

    test('a holiday is marked, and the days either side are not', () {
      final week = weekFrom(
        meetings: classes,
        start: start,
        holidays: {'2026-10-21'},
      );
      expect(week[2].classes, isEmpty);
      expect(weekDayText(week[2]), 'No classes: holiday.');
      expect(week[0].classes, hasLength(2));
      expect(week[4].classes, hasLength(1));
    });

    test('over the end of the term the days say the term is over', () {
      final week = weekFrom(
        meetings: classes,
        start: DateTime.utc(2026, 12, 3),
        holidays: const {},
      );
      expect(
        [for (final d in week) weekDayText(d)],
        [
          'No classes.',
          '1 class, 9:00 AM to 9:50 AM.', // Friday Dec 4 is the last day of the term
          'The term is over.', // the weekend after it reads as over too
          'The term is over.',
          'The term is over.',
          'The term is over.',
          'The term is over.',
        ],
      );
    });

    test('before the term starts it says so', () {
      final week = weekFrom(
        meetings: classes,
        start: DateTime.utc(2026, 9, 14),
        holidays: const {},
      );
      expect({for (final d in week.take(5)) d.reason}, {'before_term'});
    });

    test('the span covers the schedule and today', () {
      final span = scheduleSpan(classes, DateTime.utc(2026, 10, 19));
      expect(
        (span.first, span.last),
        (DateTime.utc(2026, 9, 24), DateTime.utc(2026, 12, 4)),
      );
      final late = scheduleSpan(classes, DateTime.utc(2027, 1, 5));
      expect(late.last, DateTime.utc(2027, 1, 5));
    });
  });

  group('the Week screen', () {
    testWidgets('lists seven days from today, with the classes of each', (
      tester,
    ) async {
      await open(
        tester,
        rigWith([
          cls(),
          cls(course: 'ABC 20', days: [0, 2], start: '13:00', end: '13:50'),
        ]),
      );
      await openWeek(tester);

      expect(find.text('Mon, Oct 19 to Sun, Oct 25'), findsOneWidget);
      expect(find.text('Today, Mon, Oct 19'), findsOneWidget);
      expect(find.text('Wed, Oct 21'), findsOneWidget);
      expect(find.text('2 classes, 9:00 AM to 1:50 PM.'), findsNWidgets(2));
      expect(find.text('1 class, 9:00 AM to 9:50 AM.'), findsOneWidget);
      expect(find.text('No classes: weekend.'), findsNWidgets(2));
    });

    testWidgets(
      'marks the no-class days of the term (Veterans Day, Wednesday 2026-11-11)',
      (tester) async {
        await open(
          tester,
          rigWith([cls()], now: DateTime.utc(2026, 11, 9, 20)),
        );
        await openWeek(tester);
        expect(find.text('Wed, Nov 11'), findsOneWidget);
        expect(find.text('No classes: holiday.'), findsOneWidget);
      },
    );

    testWidgets(
      'moves a week at a time, and stops at the ends of the schedule',
      (tester) async {
        await open(tester, rigWith([cls()]));
        await openWeek(tester);
        await tester.tap(find.byTooltip('Next week'));
        await tester.pumpAndSettle();
        expect(find.text('Mon, Oct 26 to Sun, Nov 1'), findsOneWidget);
        await tester.tap(find.byTooltip('Previous week'));
        await tester.pumpAndSettle();
        expect(find.text('Mon, Oct 19 to Sun, Oct 25'), findsOneWidget);

        for (var i = 0; i < 9; i++) {
          final next = tester.widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right),
          );
          if (next.onPressed == null) break;
          await tester.tap(find.byTooltip('Next week'));
          await tester.pumpAndSettle();
        }
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_right),
              )
              .onPressed,
          isNull,
        );
        expect(find.text('Mon, Nov 30 to Sun, Dec 6'), findsOneWidget);
        expect(find.text('The term is over.'), findsNWidgets(2));
      },
    );

    testWidgets('tapping a day opens it in Today', (tester) async {
      final rig = rigWith([cls()]);
      await open(tester, rig);
      await openWeek(tester);
      await tester.tap(find.text('Wed, Oct 21'));
      await tester.pumpAndSettle();

      expect(find.text('Week'), findsNothing, reason: 'back on Today');
      expect(find.text('Classes on Wed, Oct 21'), findsOneWidget);
      expect(find.text("Today's classes"), findsNothing);

      await openWeek(tester);
      expect(
        find.text('Mon, Oct 19 to Sun, Oct 25'),
        findsOneWidget,
        reason: 'the week always opens at today',
      );
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Wed, Oct 21'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Thu, Oct 22'))
            .selected,
        isFalse,
      );
    });

    testWidgets('picking today in the week goes back to today', (tester) async {
      await open(tester, rigWith([cls()]));
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle(); // Wednesday, a class day
      expect(find.textContaining('Classes on'), findsOneWidget);

      await openWeek(tester);
      await tester.tap(find.text('Today, Mon, Oct 19'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Classes on'), findsNothing);
      expect(find.textContaining('Today, '), findsOneWidget);
    });

    testWidgets('with no schedule the button is off', (tester) async {
      await open(tester, rigWith(const []));
      expect(
        tester
            .widget<GlassIconButton>(
              find.widgetWithIcon(
                GlassIconButton,
                Icons.calendar_view_week_outlined,
              ),
            )
            .onPressed,
        isNull,
      );
    });
  });

  testWidgets('large text does not break the week', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(
      tester,
      rigWith([
        cls(),
        cls(course: 'ABC 20', days: [0, 2], start: '13:00', end: '13:50'),
      ]),
    );
    await openWeek(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('2 classes, 9:00 AM to 1:50 PM.'), findsWidgets);
  });
}
