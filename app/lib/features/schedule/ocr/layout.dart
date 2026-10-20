import 'dart:math' as math;

import 'fields.dart';
import 'recognized_text.dart';

/// One word of recognized text with where it is and how sure the phone was of its line.
class Token {
  const Token(this.text, this.box, this.confidence);

  final String text;
  final Box box;
  final double confidence;

  double get left => box.left;
  double get right => box.right;
  double get top => box.top;
  double get bottom => box.bottom;
  double get centerY => box.centerY;
  double get height => box.height;
  double get width => box.width;

  @override
  String toString() => text;
}

double median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return 0;
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// The reading's words. A line the phone gave without its words is spread over its box by length.
List<Token> tokensOf(RecognizedText reading, {int limit = 6000}) {
  final tokens = <Token>[];
  for (final line in reading.lines) {
    final text = normalizeText(line.text);
    if (text.isEmpty || !_isFinite(line.box)) continue;
    final pieces = text.split(' ');
    final words = [
      for (final w in line.words)
        if (normalizeText(w.text).isNotEmpty) (normalizeText(w.text), w.box),
    ];
    if (words.length == pieces.length && words.map((w) => w.$1).join(' ') == text) {
      for (final (word, box) in words) {
        if (_isFinite(box)) tokens.add(Token(word, box, line.confidence));
      }
    } else {
      var at = 0;
      for (final piece in pieces) {
        final from = line.box.left + line.box.width * at / text.length;
        final to = line.box.left + line.box.width * (at + piece.length) / text.length;
        tokens.add(Token(piece, Box(from, line.box.top, to, line.box.bottom), line.confidence));
        at += piece.length + 1;
      }
    }
    if (tokens.length > limit) break;
  }
  return _withoutRepeats(tokens);
}

bool _isFinite(Box b) => b.left.isFinite && b.top.isFinite && b.right.isFinite && b.bottom.isFinite;

/// A picture of the same page taken twice over (a scroll that overlaps itself) reads the same words twice.
List<Token> _withoutRepeats(List<Token> tokens) {
  final kept = <Token>[];
  final byText = <String, List<Token>>{};
  for (final t in tokens) {
    final same = byText.putIfAbsent(t.text, () => []);
    if (same.any((o) => _overlap(o.box, t.box) > 0.6)) continue;
    same.add(t);
    kept.add(t);
  }
  return kept;
}

double _overlap(Box a, Box b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (w <= 0 || h <= 0) return 0;
  final smaller = math.min(a.width * a.height, b.width * b.height);
  return smaller <= 0 ? 0 : w * h / smaller;
}

/// How tall ordinary text is in this picture, for judging distances. A little under the middle of the heights,
/// because a box around two lines that were read together is taller than the text in it.
double typicalHeight(List<Token> tokens) {
  final heights = [
    for (final t in tokens)
      if (RegExp(r'[A-Za-z0-9]{2}').hasMatch(t.text)) t.height,
  ]..sort();
  return heights.isEmpty ? 10 : heights[(heights.length * 0.35).floor()];
}

/// Words that sit on one line of the picture, left to right.
class VisualLine {
  VisualLine(List<Token> tokens) : tokens = ([...tokens]..sort((a, b) => a.left.compareTo(b.left)));

  final List<Token> tokens;

  late final double top = tokens.map((t) => t.top).reduce(math.min);
  late final double bottom = tokens.map((t) => t.bottom).reduce(math.max);
  late final double centerY = tokens.map((t) => t.centerY).reduce((a, b) => a + b) / tokens.length;
  late final double left = tokens.first.left;
  late final double right = tokens.map((t) => t.right).reduce(math.max);
  late final double height = median(tokens.map((t) => t.height));

  String get text => tokens.map((t) => t.text).join(' ');

  /// The line's text with [cellBreak] where the gap between words is wider than [gap], a break between cells.
  String textWithBreaks(double gap) {
    final buffer = StringBuffer(tokens.first.text);
    for (var i = 1; i < tokens.length; i++) {
      buffer.write(tokens[i].left - tokens[i - 1].right > gap ? ' $cellBreak ' : ' ');
      buffer.write(tokens[i].text);
    }
    return buffer.toString();
  }
}

/// Marks the edge of a cell in a line's text; no field reader treats it as part of a value.
const cellBreak = '\u2016';

class _Group {
  _Group(Token first) : tokens = [first], sum = first.centerY;

  final List<Token> tokens;
  double sum;

  double get center => sum / tokens.length;
}

/// Groups words into the lines they sit on, top to bottom. [h] is how tall ordinary text is.
List<VisualLine> visualLines(List<Token> tokens, double h) {
  final sorted = [...tokens]..sort((a, b) => a.centerY.compareTo(b.centerY));
  final groups = <_Group>[];
  for (final t in sorted) {
    _Group? home;
    for (var i = groups.length - 1; i >= 0 && i >= groups.length - 3; i--) {
      final g = groups[i];
      if ((t.centerY - g.center).abs() <= 0.5 * math.min(math.max(t.height, h), 1.4 * h)) {
        home = g;
        break;
      }
    }
    if (home == null) {
      groups.add(_Group(t));
    } else {
      home.tokens.add(t);
      home.sum += t.centerY;
    }
  }
  return [for (final g in groups) VisualLine(g.tokens)]..sort((a, b) => a.centerY.compareTo(b.centerY));
}
