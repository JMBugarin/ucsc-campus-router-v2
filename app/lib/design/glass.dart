import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'accessibility_environment.dart';
import 'tokens.dart';

class _GlassScope extends InheritedWidget {
  const _GlassScope({required super.child});

  static bool inside(BuildContext context) => context.getInheritedWidgetOfExactType<_GlassScope>() != null;

  @override
  bool updateShouldNotify(_GlassScope oldWidget) => false;
}

/// A glass-style surface for a control that floats above content: a blur of what is behind it, a tint, an
/// edge stroke and a soft shadow that falls only outside the shape. It is never stacked: inside another
/// glass surface it draws the tint without blurring again. When glass is off (an older iOS, Reduce
/// Transparency, Increase Contrast) it is an opaque surface with the same shape and size.
class GlassSurface extends ConsumerWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.level = GlassLevel.regular,
    this.strong = false,
    this.prominent = false,
    this.radius = Radii.glass,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final GlassLevel level;

  /// More opaque tint, for a surface that carries a paragraph or a time to act on.
  final bool strong;

  /// Accent-tinted, for the most important control. Its content uses `accentOnFill`.
  final bool prominent;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final shape = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);
    if (!glassOn(context, ref)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: prominent ? c.accentFill : c.surfaceGlassFallback,
          borderRadius: shape,
          border: prominent ? null : Border.all(color: c.separator),
          boxShadow: Elevation.raised,
        ),
        child: content,
      );
    }
    final tint = prominent ? c.glassProminentTint : (strong ? c.glassTintStrong : c.glassTint);
    final face = DecoratedBox(
      decoration: BoxDecoration(color: tint, borderRadius: shape, border: Border.all(color: c.glassStroke)),
      child: content,
    );
    if (_GlassScope.inside(context)) return face;
    return CustomPaint(
      painter: _OuterShadow(shape, level.shadow),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: level.sigma, sigmaY: level.sigma),
          child: _GlassScope(child: face),
        ),
      ),
    );
  }
}

class _OuterShadow extends CustomPainter {
  const _OuterShadow(this.shape, this.shadows);

  final BorderRadius shape;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = shape.toRRect(Offset.zero & size);
    final everything = Path()..addRect(Rect.fromLTWH(-80, -80, size.width + 160, size.height + 160));
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, everything, Path()..addRRect(rrect)));
    for (final s in shadows) {
      canvas.drawRRect(rrect.shift(s.offset), s.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadow old) => old.shape != shape || old.shadows != shadows;
}
