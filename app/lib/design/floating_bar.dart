import 'package:flutter/material.dart';

import 'tokens.dart';

/// How far the floating tab bar reaches up from the bottom of the screen, so a list can scroll beneath
/// it and still end clear of it.
class FloatingBarInset extends InheritedWidget {
  const FloatingBarInset({super.key, required this.bottom, required super.child});

  final double bottom;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FloatingBarInset>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(FloatingBarInset oldWidget) => oldWidget.bottom != bottom;
}

/// The soft edge under the floating bar: list text fades out into the canvas colour instead of running
/// behind the tab labels. It is functional, so it is not a decorative gradient, and it takes no taps.
class ScrollEdgeFade extends StatelessWidget {
  const ScrollEdgeFade({super.key});

  @override
  Widget build(BuildContext context) {
    final canvas = context.colors.bgCanvas;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [canvas.withValues(alpha: 0), canvas.withValues(alpha: 0.94), canvas],
            stops: const [0, 0.6, 1],
          ),
        ),
      ),
    );
  }
}

/// A message that floats above the tab bar instead of covering it, so the tabs stay tappable while it shows.
/// [inset] is `FloatingBarInset.of(context)`, read before any `await`.
SnackBar floatingSnackBar({
  required double inset,
  required Widget content,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) => SnackBar(
  content: content,
  action: action,
  duration: duration,
  behavior: SnackBarBehavior.floating,
  margin: EdgeInsets.fromLTRB(Space.md, 0, Space.md, inset + Space.sm),
);
