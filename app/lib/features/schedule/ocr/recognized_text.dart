/// A rectangle in picture pixels, measured from the top left.
class Box {
  const Box(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  @override
  bool operator ==(Object other) =>
      other is Box && other.left == left && other.top == top && other.right == right && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'Box($left, $top, $right, $bottom)';
}

class RecognizedWord {
  const RecognizedWord(this.text, this.box);

  final String text;
  final Box box;
}

/// One line of text the phone found in a picture, where it is, and how sure it is of the reading (0 to 1).
class RecognizedLine {
  const RecognizedLine({required this.text, required this.box, this.confidence = 1, this.words = const []});

  final String text;
  final Box box;
  final double confidence;
  final List<RecognizedWord> words;
}

/// Everything the phone read from one picture.
class RecognizedText {
  const RecognizedText({required this.width, required this.height, required this.lines});

  final int width;
  final int height;
  final List<RecognizedLine> lines;

  /// From the platform channel's reply, or a saved copy of one: positions are fractions of the picture's
  /// width and height, measured from the top left. Throws a [FormatException] if the shape is wrong.
  factory RecognizedText.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('The reading is not a map.');
    final width = json['width'];
    final height = json['height'];
    if (width is! int || height is! int || width <= 0 || height <= 0) {
      throw const FormatException("The reading doesn't say how big the picture is.");
    }
    final raw = json['lines'];
    if (raw is! List) throw const FormatException('The reading has no lines.');
    final lines = <RecognizedLine>[];
    for (final item in raw) {
      if (item is! Map) throw const FormatException('A line is not a map.');
      final text = item['text'];
      if (text is! String) throw const FormatException('A line has no text.');
      final box = _box(item, width, height);
      if (text.trim().isEmpty) continue;
      final words = item['words'];
      lines.add(
        RecognizedLine(
          text: text,
          box: box,
          confidence: _number(item['confidence'] ?? 1).clamp(0.0, 1.0),
          words: [
            if (words is List)
              for (final w in words)
                if (w is Map && w['text'] is String && (w['text'] as String).trim().isNotEmpty)
                  RecognizedWord(w['text'] as String, _box(w, width, height)),
          ],
        ),
      );
    }
    return RecognizedText(width: width, height: height, lines: lines);
  }

  Map<String, Object> toJson() => {
    'width': width,
    'height': height,
    'lines': [
      for (final l in lines)
        {
          'text': l.text,
          'confidence': l.confidence,
          ..._fractions(l.box),
          'words': [
            for (final w in l.words) {'text': w.text, ..._fractions(w.box)},
          ],
        },
    ],
  };

  Map<String, double> _fractions(Box b) => {
    'x': b.left / width,
    'y': b.top / height,
    'w': b.width / width,
    'h': b.height / height,
  };
}

double _number(Object? value) {
  if (value is! num || !value.isFinite) throw const FormatException('A position or confidence is not a number.');
  return value.toDouble();
}

Box _box(Map item, int width, int height) {
  final x = _number(item['x']);
  final y = _number(item['y']);
  final w = _number(item['w']);
  final h = _number(item['h']);
  if (w < 0 || h < 0) throw const FormatException('A box has a negative size.');
  return Box(x * width, y * height, (x + w) * width, (y + h) * height);
}
