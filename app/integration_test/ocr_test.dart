import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ucsc_router/features/schedule/ocr/recognized_text.dart';
import 'package:ucsc_router/features/schedule/ocr/text_recognizer.dart';

/// Runs the real Vision framework on pictures drawn here, in the iOS Simulator:
/// `flutter test integration_test/ocr_test.dart -d <simulator>`.
Future<String> drawPicture(
  WidgetTester tester,
  String name,
  List<(String, Offset)> texts, {
  Size size = const Size(1200, 800),
}) async {
  final path = '${Directory.systemTemp.path}/$name.png';
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (final (text, at) in texts) {
      TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(color: Colors.black, fontSize: 32),
          ),
          textDirection: TextDirection.ltr,
        )
        ..layout()
        ..paint(canvas, at);
    }
    final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(png!.buffer.asUint8List());
  });
  addTearDown(() => File(path).deleteSync());
  return path;
}

String squash(String text) => text.replaceAll(RegExp(r'\s+'), '').toLowerCase();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const recognizer = VisionTextRecognizer();

  testWidgets('Vision returns each line with its text, where it is and how sure it is', (tester) async {
    final path = await drawPicture(tester, 'ocr_lines', [
      ('XYZ 10 - Sample Calculus', const Offset(60, 80)),
      ('MoWeFr 2:40PM - 3:45PM', const Offset(60, 300)),
      ('Kresge Acad 3201', const Offset(700, 300)),
    ]);
    final RecognizedText text = (await tester.runAsync(() => recognizer.recognize(path)))!;

    expect(text.width, 1200);
    expect(text.height, 800);
    final course = text.lines.firstWhere((l) => squash(l.text).contains('samplecalculus'));
    final times = text.lines.firstWhere((l) => squash(l.text).contains('2:40pm'));
    final room = text.lines.firstWhere((l) => squash(l.text).contains('kresge'));

    expect(squash(room.text), contains('3201'));
    expect(course.box.centerY, lessThan(times.box.centerY), reason: 'positions are from the top left');
    expect(room.box.left, greaterThan(times.box.right - 50), reason: 'the room is to the right of the time');
    expect(course.box.top, inInclusiveRange(60, 100));
    expect(times.box.top, inInclusiveRange(280, 320));
    expect(room.box.left, inInclusiveRange(680, 720));
    expect(room.box.height, inInclusiveRange(25, 60));
    for (final line in [course, times, room]) {
      expect(line.confidence, inInclusiveRange(0.3, 1.0));
      expect(line.words, isNotEmpty);
      for (final w in line.words) {
        expect(w.box.left, greaterThanOrEqualTo(line.box.left - 6));
        expect(w.box.right, lessThanOrEqualTo(line.box.right + 6));
      }
    }
    expect(room.words.map((w) => w.text), contains('3201'));
  });

  testWidgets('a picture with no text gives no lines rather than an error', (tester) async {
    final path = await drawPicture(tester, 'ocr_blank', const []);
    final text = (await tester.runAsync(() => recognizer.recognize(path)))!;
    expect(text.lines, isEmpty);
    expect(text.width, 1200);
  });

  testWidgets('a file that is not a picture, and one that is missing, are explained', (tester) async {
    final notPicture = File('${Directory.systemTemp.path}/ocr_not_a_picture.png')
      ..writeAsStringSync('hello, not a png');
    for (final path in [notPicture.path, '${Directory.systemTemp.path}/ocr_does_not_exist.png']) {
      final error = await tester.runAsync(() async {
        try {
          await recognizer.recognize(path);
        } on PictureException catch (e) {
          return e;
        }
        return null;
      });
      expect(error?.message, contains("isn't a picture"), reason: path);
    }
  });
}
