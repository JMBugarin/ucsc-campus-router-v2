import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ucsc_router/app.dart';
import 'package:ucsc_router/features/schedule/ocr/picture_picker.dart';
import 'package:ucsc_router/features/settings/settings.dart';

import 'support.dart';

/// Reads pictures drawn here with the real Vision framework and checks their rooms against a local server:
/// `python3 server/server.py` on 127.0.0.1:8000, then `flutter test integration_test/picture_import_test.dart -d <simulator>`.
Future<void> openApp(WidgetTester tester, String picture) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await prefs.setString('server_url', localServer);
  await prefs.setBool('use_location', false);
  await tester.pumpWidget(
    ProviderScope(
      retry: (count, error) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        picturePickerProvider.overrideWithValue(SystemPicturePicker(choose: () async => picture)),
      ],
      child: const UcscRouterApp(),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await tester.tap(tab('Schedule'));
  await tester.pumpAndSettle();
}

Future<void> readPicture(WidgetTester tester) async {
  await tester.tap(find.text('Read a photo'));
  await tester.pump();
}

Future<void> waitUntilGone(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isNotEmpty && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(finder, findsNothing, reason: 'timed out waiting for it to go');
}

void main() {
  final binding = bindEnvironment();

  testWidgets('a picture of a schedule is read on the phone, checked, and saved', (tester) async {
    final picture = await drawPicture(tester, 'import_cards', [
      ('BME 160 Lecture', const Offset(60, 60)),
      ('Cell Biology', const Offset(60, 110)),
      ('MWF 1:20 PM - 2:25 PM', const Offset(60, 160)),
      ('Kresge Acad 3201', const Offset(60, 210)),
      ('ART 20 Discussion', const Offset(60, 400)),
      ('Th 8:30 AM - 9:35 AM', const Offset(60, 450)),
      ('Thim Lecture 003', const Offset(60, 500)),
    ], size: const Size(1200, 700));
    await openApp(tester, picture);

    await readPicture(tester);
    await waitFor(tester, find.text('Check your classes'), timeout: const Duration(seconds: 60));
    await waitUntilGone(tester, find.text('Checking the room…'));
    expect(find.textContaining('Found 2 classes'), findsOneWidget);
    expect(find.textContaining('BME 160'), findsOneWidget);
    expect(find.textContaining('ART 20'), findsOneWidget);
    expect(find.textContaining('2:25 PM'), findsOneWidget);
    expect(find.text("I don't recognise this room."), findsNothing);
    await shot(binding, tester, 'import-review');

    await tester.tap(find.textContaining('BME 160'));
    await tester.pumpAndSettle();
    expect(find.text('Edit class'), findsOneWidget);
    await shot(binding, tester, 'import-editor');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save 2 classes'));
    await waitFor(tester, find.textContaining('Added 2 classes'));
    await tester.pumpAndSettle();
    expect(find.text('BME 160 Lecture'), findsOneWidget);
    expect(find.text('ART 20 Discussion'), findsOneWidget);
    await shot(binding, tester, 'import-saved');
  });

  testWidgets('a room the server does not know is marked, and fixing it clears the mark', (tester) async {
    final picture = await drawPicture(tester, 'import_bad_room', [
      ('BME 160 Lecture', const Offset(60, 60)),
      ('MWF 1:20 PM - 2:25 PM', const Offset(60, 110)),
      ('Zzzz Hall 999', const Offset(60, 160)),
    ], size: const Size(1200, 400));
    await openApp(tester, picture);

    await readPicture(tester);
    await waitFor(tester, find.text("I don't recognise this room."), timeout: const Duration(seconds: 60));
    expect(find.textContaining('1 needs a look'), findsOneWidget);
    await shot(binding, tester, 'import-unknown-room');

    await tester.tap(find.text('Find the room'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Zzzz Hall 999'), 'Kresge 3201');
    await waitFor(tester, find.widgetWithText(ListTile, 'Kresge College Academic Building 3201'));
    await shot(binding, tester, 'import-room-finder');
    await tester.tap(find.widgetWithText(ListTile, 'Kresge College Academic Building 3201'));
    await tester.pumpAndSettle();
    await waitUntilGone(tester, find.text("I don't recognise this room."));
    expect(find.textContaining('Found 1 class.'), findsOneWidget);
  });

  testWidgets('pictures that are not a schedule are explained and nothing is added', (tester) async {
    final blank = await drawPicture(tester, 'import_blank', const []);
    await openApp(tester, blank);
    await readPicture(tester);
    await waitFor(
      tester,
      find.textContaining("couldn't find any text in that picture"),
      timeout: const Duration(seconds: 60),
    );
    await shot(binding, tester, 'import-nothing-found');

    final menu = await drawPicture(tester, 'import_menu', [
      ('Corner Cafe - Lunch Menu', const Offset(60, 60)),
      ('Margherita Pizza', const Offset(60, 160)),
      ('Garden Salad', const Offset(60, 210)),
    ]);
    await openApp(tester, menu);
    await readPicture(tester);
    await waitFor(
      tester,
      find.textContaining("couldn't find any classes in that picture"),
      timeout: const Duration(seconds: 60),
    );
    expect(find.text('Check your classes'), findsNothing);
  });
}
