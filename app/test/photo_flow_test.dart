import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/app.dart';
import 'package:ucsc_router/core/api_client.dart';
import 'package:ucsc_router/features/schedule/meeting.dart';
import 'package:ucsc_router/features/schedule/photo_import.dart';
import 'package:ucsc_router/features/schedule/schedule_repository.dart';

import 'helpers.dart';

final photo = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);

const read = ImportResult(
  meetings: [],
  notes: ['From the photo: The last row is blurry.'],
  locations: [],
);

ImportResult readClass() => ImportResult(
      meetings: [meeting(course: 'NEW 1')],
      notes: const ['From the photo: The last row is blurry.'],
      locations: const [LocationInfo(kind: 'building', buildingName: 'Kresge College Academic Building')],
    );

Future<void> open(WidgetTester tester, TestRig rig) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await rig.app());
  await tester.pumpAndSettle();
}

Future<void> tapPhoto(WidgetTester tester) async {
  await tester.tap(find.text('Read a photo'));
  await tester.pumpAndSettle();
}

void main() {
  group('Read a photo', () {
    testWidgets('asks the server first, and if it cannot read photos says why and goes no further', (tester) async {
      var picked = 0;
      final rig = TestRig(startTab: tabSchedule, photoPicker: () async {
        picked++;
        return photo;
      });
      rig.schedule.photoSupportNow = const PhotoSupport(
        ready: false,
        reason: 'Reading photos with Claude is turned off on a public server.',
      );
      await open(tester, rig);
      await tapPhoto(tester);

      expect(find.text('Reading photos with Claude is turned off on a public server.'), findsOneWidget);
      expect(find.text('Read a photo of your schedule'), findsNothing, reason: 'no consent dialog for something that cannot happen');
      expect(picked, 0);
      expect(rig.schedule.calls.where((c) => c.startsWith('photo')), ['photo-support'], reason: 'asked, but no photo sent');
    });

    testWidgets('a server that cannot be reached is said so', (tester) async {
      final rig = TestRig(startTab: tabSchedule);
      rig.schedule.photoSupportFails = const ApiException("Can't reach the server.", kind: ApiErrorKind.offline);
      await open(tester, rig);
      await tapPhoto(tester);
      expect(find.text("Can't reach the server."), findsOneWidget);
      expect(find.text('Read a photo of your schedule'), findsNothing);
    });

    testWidgets('says where the photo goes before anything is chosen, and Cancel sends nothing', (tester) async {
      var picked = 0;
      final rig = TestRig(startTab: tabSchedule, serverUrl: 'https://router.example', photoPicker: () async {
        picked++;
        return photo;
      });
      await open(tester, rig);
      await tapPhoto(tester);

      expect(find.text('Read a photo of your schedule'), findsOneWidget);
      expect(find.textContaining('sent to router.example, which sends it on to Anthropic'), findsOneWidget);
      expect(find.textContaining('The server keeps nothing, Anthropic handles the picture under its own terms'), findsOneWidget);
      expect(find.textContaining('instructor names are dropped'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(picked, 0);
      expect(rig.schedule.calls.where((c) => c.startsWith('photo:')), isEmpty);
    });

    testWidgets('a chosen photo is read by the server and its classes added, with a reminder to check them', (tester) async {
      final rig = TestRig(startTab: tabSchedule, photoPicker: () async => photo);
      rig.schedule.nextImport = readClass();
      await open(tester, rig);
      await tapPhoto(tester);
      await tester.tap(find.text('Choose a photo'));
      await tester.pumpAndSettle();

      expect(rig.schedule.calls, contains('photo:image/png:8'));
      expect(rig.schedule.stored.map((m) => m.course), ['NEW 1']);
      expect(find.textContaining('Added 1 class.'), findsOneWidget);
      expect(find.textContaining('The last row is blurry'), findsOneWidget);
      expect(find.textContaining('Check each class against your photo, and remove any that are wrong.'), findsOneWidget);
    });

    testWidgets('a photo with no classes in it adds nothing and does not ask for a check', (tester) async {
      final rig = TestRig(startTab: tabSchedule, photoPicker: () async => photo);
      rig.schedule.nextImport = read;
      await open(tester, rig);
      await tapPhoto(tester);
      await tester.tap(find.text('Choose a photo'));
      await tester.pumpAndSettle();

      expect(rig.schedule.stored, isEmpty);
      expect(find.textContaining('Added 0 classes.'), findsOneWidget);
      expect(find.textContaining('Check each class against your photo'), findsNothing);
    });

    testWidgets('a class that is already saved is not added twice', (tester) async {
      final rig = TestRig(startTab: tabSchedule, stored: [meeting(course: 'NEW 1')], photoPicker: () async => photo);
      rig.schedule.nextImport = readClass();
      await open(tester, rig);
      await tapPhoto(tester);
      await tester.tap(find.text('Choose a photo'));
      await tester.pumpAndSettle();
      expect(rig.schedule.stored, hasLength(1));
      expect(find.textContaining('(1 already there)'), findsOneWidget);
    });

    testWidgets('choosing nothing sends nothing', (tester) async {
      final rig = TestRig(startTab: tabSchedule, photoPicker: () async => null);
      await open(tester, rig);
      await tapPhoto(tester);
      await tester.tap(find.text('Choose a photo'));
      await tester.pumpAndSettle();
      expect(rig.schedule.calls.where((c) => c.startsWith('photo:')), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a picker that fails is said so, and nothing is sent', (tester) async {
      final rig = TestRig(startTab: tabSchedule, photoPicker: () async => throw Exception('the picker broke'));
      await open(tester, rig);
      await tapPhoto(tester);
      await tester.tap(find.text('Choose a photo'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't open your photos. Try again."), findsOneWidget);
      expect(find.textContaining('picker broke'), findsNothing);
      expect(rig.schedule.calls.where((c) => c.startsWith('photo:')), isEmpty);
    });

    testWidgets('a file that cannot be used is explained, and nothing is sent', (tester) async {
      final rig = TestRig(
        startTab: tabSchedule,
        photoPicker: () async => photo,
        photoPreparer: (bytes) async {
          throw const FormatException('That photo is too large to send. Try a screenshot of just your schedule.');
        },
      );
      await open(tester, rig);
      await tapPhoto(tester);
      await tester.tap(find.text('Choose a photo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('too large to send'), findsOneWidget);
      expect(rig.schedule.calls.where((c) => c.startsWith('photo:')), isEmpty);
      final button = find.ancestor(of: find.text('Read a photo'), matching: find.bySubtype<ButtonStyleButton>());
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull, reason: 'the screen is not left waiting');
    });

    testWidgets('an unexpected failure while preparing is not left showing, or waiting', (tester) async {
      final rig = TestRig(
        startTab: tabSchedule,
        photoPicker: () async => photo,
        photoPreparer: (bytes) async => throw StateError('codec exploded'),
      );
      await open(tester, rig);
      await tapPhoto(tester);
      await tester.tap(find.text('Choose a photo'));
      await tester.pumpAndSettle();
      expect(find.text("That file isn't a photo I can read."), findsOneWidget);
      expect(find.text('Preparing your photo…'), findsNothing);
      expect(find.textContaining('codec exploded'), findsNothing);
    });

    testWidgets('what is sent is what the preparer made of the picked file', (tester) async {
      final rig = TestRig(
        startTab: tabSchedule,
        photoPicker: () async => Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9, 9, 9]),
        photoPreparer: (bytes) async => PickedPhoto(Uint8List.fromList([1, 2, 3]), 'image/png'),
      );
      await open(tester, rig);
      await tapPhoto(tester);
      await tester.tap(find.text('Choose a photo'));
      await tester.pumpAndSettle();
      expect(rig.schedule.calls, contains('photo:image/png:3'));
    });

    testWidgets('while the file is being prepared the screen says so, and the buttons wait', (tester) async {
      final release = Completer<PickedPhoto>();
      final rig = TestRig(startTab: tabSchedule, photoPicker: () async => photo, photoPreparer: (bytes) => release.future);
      await open(tester, rig);
      await tapPhoto(tester);
      await tester.tap(find.text('Choose a photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Preparing your photo…'), findsOneWidget);
      final button = find.ancestor(of: find.text('Read a photo'), matching: find.bySubtype<ButtonStyleButton>());
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);

      release.complete(PickedPhoto(photo, 'image/png'));
      await tester.pumpAndSettle();
      expect(find.text('Preparing your photo…'), findsNothing);
      expect(rig.schedule.calls, contains('photo:image/png:8'));
    });

    testWidgets("when the reading fails the server's reason is shown and nothing is added", (tester) async {
      final rig = TestRig(startTab: tabSchedule, photoPicker: () async => photo);
      rig.schedule.failWith = const ApiException(
        "The photo reader is unavailable: the server's Anthropic account has run out of credit or reached its usage limit. "
        'Its owner needs to fix that. Pasting your schedule works meanwhile.',
        statusCode: 503,
      );
      await open(tester, rig);
      await tapPhoto(tester);
      await tester.tap(find.text('Choose a photo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('run out of credit or reached its usage limit'), findsOneWidget);
      expect(rig.schedule.stored, isEmpty);
      expect(rig.schedule.calls.where((c) => c.startsWith('photo:')), hasLength(1), reason: 'never sent again on its own');
    });

    testWidgets('while it reads, the buttons wait and a note explains why it takes so long', (tester) async {
      final release = Completer<void>();
      final rig = TestRig(startTab: tabSchedule, photoPicker: () async => photo);
      rig.schedule.hold = release.future;
      rig.schedule.nextImport = readClass();
      await open(tester, rig);
      await tapPhoto(tester);
      await tester.tap(find.text('Choose a photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Reading your photo…'), findsOneWidget);
      final button = find.ancestor(of: find.text('Read a photo'), matching: find.bySubtype<ButtonStyleButton>());
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
      expect(find.textContaining('Reading a photo takes a while'), findsNothing, reason: 'only once the wait drags on');
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('Reading a photo takes a while, up to a minute or two'), findsOneWidget);
      expect(find.textContaining('waking up'), findsNothing, reason: 'the photo has its own explanation');

      release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Reading your photo…'), findsNothing);
      expect(rig.schedule.stored, hasLength(1));
    });

    testWidgets('the other imports keep their usual note about a sleeping server', (tester) async {
      final release = Completer<void>();
      final rig = TestRig(startTab: tabSchedule);
      rig.schedule.hold = release.future;
      await open(tester, rig);
      await tester.tap(find.text('Paste from MyUCSC'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'my schedule text');
      await tester.tap(find.text('Import'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('waking up'), findsOneWidget);
      release.complete();
      await tester.pumpAndSettle();
    });
  });
}
