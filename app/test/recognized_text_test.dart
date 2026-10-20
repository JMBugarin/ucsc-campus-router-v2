import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/features/schedule/ocr/recognized_text.dart';

Map<String, Object?> line(
  String text, {
  Object? confidence = 0.9,
  double x = 0.1,
  double y = 0.2,
  List<Object?>? words,
}) => {'text': text, 'confidence': confidence, 'x': x, 'y': y, 'w': 0.5, 'h': 0.05, 'words': words ?? []};

Map<String, Object?> reading(List<Object?> lines, {Object? width = 1000, Object? height = 2000}) => {
  'width': width,
  'height': height,
  'lines': lines,
};

void main() {
  group('RecognizedText.fromJson', () {
    test('turns fractions of the picture into pixels', () {
      final text = RecognizedText.fromJson(
        reading([
          line(
            'MoWeFr 2:40PM',
            words: [
              {'text': 'MoWeFr', 'x': 0.1, 'y': 0.2, 'w': 0.2, 'h': 0.05},
              {'text': '2:40PM', 'x': 0.35, 'y': 0.2, 'w': 0.25, 'h': 0.05},
            ],
          ),
        ]),
      );
      expect(text.width, 1000);
      expect(text.height, 2000);
      final first = text.lines.single;
      expect(first.text, 'MoWeFr 2:40PM');
      expect(first.confidence, 0.9);
      expect(first.box, const Box(100, 400, 600, 500));
      expect(first.words.map((w) => w.text), ['MoWeFr', '2:40PM']);
      expect(first.words[1].box.left, closeTo(350, 1e-9));
      expect(first.words[1].box.right, closeTo(600, 1e-9));
    });

    test('drops lines and words that are only spaces, and keeps the rest in order', () {
      final text = RecognizedText.fromJson(
        reading([
          line('first'),
          line('   '),
          line(
            'second',
            words: [
              {'text': ' ', 'x': 0.1, 'y': 0.2, 'w': 0.1, 'h': 0.05},
              {'text': 'second', 'x': 0.1, 'y': 0.2, 'w': 0.1, 'h': 0.05},
            ],
          ),
        ]),
      );
      expect(text.lines.map((l) => l.text), ['first', 'second']);
      expect(text.lines[1].words.map((w) => w.text), ['second']);
    });

    test('a missing confidence counts as sure, and one out of range is held to 0 to 1', () {
      final text = RecognizedText.fromJson(
        reading([
          {'text': 'a', 'x': 0.0, 'y': 0.0, 'w': 0.1, 'h': 0.1},
          line('b', confidence: 1.7),
          line('c', confidence: -3),
        ]),
      );
      expect(text.lines.map((l) => l.confidence), [1.0, 1.0, 0.0]);
    });

    test('a reading with no lines is valid: the picture had no text', () {
      expect(RecognizedText.fromJson(reading([])).lines, isEmpty);
    });

    test('survives a round trip through its saved form', () {
      final original = RecognizedText.fromJson(
        reading([
          line(
            'Kresge Acad 3201',
            confidence: 0.5,
            words: [
              {'text': 'Kresge', 'x': 0.1, 'y': 0.2, 'w': 0.2, 'h': 0.05},
            ],
          ),
        ]),
      );
      final again = RecognizedText.fromJson(original.toJson());
      expect(again.width, original.width);
      expect(again.lines.single.text, 'Kresge Acad 3201');
      expect(again.lines.single.confidence, 0.5);
      expect(again.lines.single.box.left, closeTo(original.lines.single.box.left, 1e-9));
      expect(again.lines.single.box.bottom, closeTo(original.lines.single.box.bottom, 1e-9));
      expect(again.lines.single.words.single.text, 'Kresge');
    });

    test('refuses a reading that is the wrong shape', () {
      final bad = <String, Object?>{
        'not a map': 'nope',
        'no size': {'lines': []},
        'zero height': reading([], height: 0),
        'size not a whole number': reading([], width: 10.5),
        'lines not a list': {'width': 10, 'height': 10, 'lines': 'x'},
        'a line that is not a map': reading(['x']),
        'a line with no text': reading([
          {'x': 0, 'y': 0, 'w': 1, 'h': 1},
        ]),
        'a position that is not a number': reading([line('a', x: double.nan)]),
        'an infinite position': reading([line('a', y: double.infinity)]),
        'a negative size': reading([
          {'text': 'a', 'x': 0, 'y': 0, 'w': -1, 'h': 1},
        ]),
        'a confidence that is text': reading([line('a', confidence: 'high')]),
      };
      for (final entry in bad.entries) {
        expect(() => RecognizedText.fromJson(entry.value), throwsFormatException, reason: entry.key);
      }
    });
  });
}
