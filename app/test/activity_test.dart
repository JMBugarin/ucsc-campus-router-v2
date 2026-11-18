import 'package:classmap/app.dart';
import 'package:classmap/core/clock.dart';
import 'package:classmap/features/activity/activity.dart';
import 'package:classmap/features/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

Future<(ProviderContainer, FakeActivitySender, void Function(DateTime))> rig({
  Map<String, Object> prefs = const {},
  bool counting = true,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final stored = await SharedPreferences.getInstance();
  final sender = FakeActivitySender();
  var now = DateTime.utc(2026, 11, 18, 19);
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(stored),
      clockProvider.overrideWithValue(() => now),
      activitySenderProvider.overrideWithValue(counting ? sender : null),
    ],
  );
  addTearDown(c.dispose);
  return (c, sender, (DateTime t) => now = t);
}

Future<void> open(WidgetTester tester, TestRig rig) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
}

void main() {
  test('weeks start on Monday, Pacific time, across both clock changes', () {
    expect(pacificWeek(DateTime.utc(2026, 11, 23, 7, 30)), '2026-11-16');
    expect(pacificWeek(DateTime.utc(2026, 11, 23, 8, 10)), '2026-11-23');
    expect(pacificWeek(DateTime.utc(2026, 11, 2, 7, 59)), '2026-10-26');
    expect(pacificWeek(DateTime.utc(2026, 11, 2, 8)), '2026-11-02');
    expect(pacificWeek(DateTime.utc(2027, 3, 15, 6, 30)), '2027-03-08');
    expect(pacificWeek(DateTime.utc(2027, 3, 15, 7)), '2027-03-15');
  });

  test('install ids are random version 4 uuids', () {
    final ids = {for (var i = 0; i < 50; i++) randomInstallId()};
    expect(ids, hasLength(50));
    expect(ids.every(_uuid.hasMatch), isTrue);
  });

  test('nothing is sent until counting is turned on', () async {
    final (c, sender, _) = await rig();
    expect(c.read(activityProvider).on, isFalse);
    await c.read(activityProvider.notifier).meaningfulAction();
    expect(sender.recorded, isEmpty);
  });

  test('one ping per week, however many rooms are found', () async {
    final (c, sender, setNow) = await rig();
    final activity = c.read(activityProvider.notifier);
    await activity.setOn(true);
    final id = c.read(activityProvider).install!;
    expect(_uuid.hasMatch(id), isTrue);
    expect(c.read(activityProvider).participantCode, id.substring(0, 8));

    for (var i = 0; i < 4; i++) {
      await activity.meaningfulAction();
    }
    setNow(DateTime.utc(2026, 11, 23, 7, 59));
    await activity.meaningfulAction();
    setNow(DateTime.utc(2026, 11, 23, 8));
    await activity.meaningfulAction();
    await activity.meaningfulAction();
    expect(sender.recorded, [(id, '2026-11-16'), (id, '2026-11-23')]);
  });

  test(
    'a ping made offline is sent later, and one too old is dropped',
    () async {
      final (c, sender, setNow) = await rig();
      final activity = c.read(activityProvider.notifier);
      await activity.setOn(true);
      final id = c.read(activityProvider).install!;
      sender.next = Sent.failed;
      await activity.meaningfulAction();
      expect(sender.recorded, isEmpty);

      sender.next = Sent.ok;
      setNow(DateTime.utc(2026, 11, 30, 19));
      await activity.meaningfulAction();
      expect(sender.recorded, [(id, '2026-11-16'), (id, '2026-11-30')]);

      sender.next = Sent.failed;
      setNow(DateTime.utc(2026, 12, 9, 19));
      await activity.meaningfulAction();
      sender.next = Sent.ok;
      setNow(DateTime.utc(2027, 1, 20, 19));
      await activity.flush();
      expect(sender.recorded, hasLength(2));
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getStringList('activity_pending_weeks'), isEmpty);
    },
  );

  test(
    'turning counting off forgets the id and deletes what was sent',
    () async {
      final (c, sender, _) = await rig();
      final activity = c.read(activityProvider.notifier);
      await activity.setOn(true);
      final id = c.read(activityProvider).install!;
      await activity.meaningfulAction();

      sender.next = Sent.failed;
      await activity.setOn(false);
      expect(c.read(activityProvider).on, isFalse);
      expect(sender.withdrawn, isEmpty);
      await activity.meaningfulAction();

      sender.next = Sent.ok;
      await activity.flush();
      expect(sender.withdrawn, [id]);
      expect(sender.recorded, hasLength(1));

      await activity.setOn(true);
      expect(c.read(activityProvider).install, isNot(id));
    },
  );

  test('a build without a server never counts', () async {
    final (c, sender, _) = await rig(
      counting: false,
      prefs: {'activity_install': randomInstallId()},
    );
    final activity = c.read(activityProvider.notifier);
    expect(c.read(activityProvider).on, isFalse);
    await activity.setOn(true);
    await activity.meaningfulAction();
    expect(c.read(activityProvider).on, isFalse);
    expect(sender.recorded, isEmpty);
  });

  group('Settings', () {
    testWidgets('a build without a server has no counting switch', (
      tester,
    ) async {
      await open(tester, TestRig(startTab: tabSettings));
      expect(find.text('Count my weekly use'), findsNothing);
      expect(find.textContaining('no account and no server'), findsOneWidget);
    });

    testWidgets(
      'the switch starts off, shows a participant code once on, and finding a room counts the week',
      (tester) async {
        final sender = FakeActivitySender();
        final rig = TestRig(startTab: tabSettings, activity: sender);
        await open(tester, rig);
        final toggle = find.widgetWithText(
          SwitchListTile,
          'Count my weekly use',
        );
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(find.textContaining('Participant code'), findsNothing);

        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        expect(find.textContaining('Participant code: '), findsOneWidget);

        await tester.tap(find.byIcon(Icons.map_outlined).first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'kresge 3201');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kresge College Academic Building 3201'));
        await tester.pumpAndSettle();
        expect(sender.recorded, hasLength(1));
      },
    );
  });
}
