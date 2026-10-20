import 'package:flutter/material.dart';

/// The type ramp. Sizes and line heights are the design's; the system font (SF Pro on iOS) is used and
/// the platform's text size setting scales every style.
abstract final class AppText {
  static TextStyle _s(double size, double line, FontWeight weight) =>
      TextStyle(fontSize: size, height: line / size, fontWeight: weight, letterSpacing: 0);

  static final display = _s(48, 52, FontWeight.w700);
  static final largeTitle = _s(34, 41, FontWeight.w700);
  static final title1 = _s(28, 34, FontWeight.w700);
  static final title2 = _s(22, 28, FontWeight.w700);
  static final title3 = _s(20, 25, FontWeight.w600);
  static final headline = _s(17, 22, FontWeight.w600);
  static final body = _s(17, 22, FontWeight.w400);
  static final callout = _s(16, 21, FontWeight.w400);
  static final subhead = _s(15, 20, FontWeight.w400);
  static final footnote = _s(13, 18, FontWeight.w400);
  static final caption = _s(12, 16, FontWeight.w400);

  /// The ramp as Material roles, so widgets that read the theme pick it up.
  static TextTheme textTheme(Color primary, Color secondary) => TextTheme(
        displayLarge: display.copyWith(color: primary),
        displayMedium: largeTitle.copyWith(color: primary),
        displaySmall: title1.copyWith(color: primary),
        headlineLarge: title1.copyWith(color: primary),
        headlineMedium: title2.copyWith(color: primary),
        headlineSmall: title3.copyWith(color: primary),
        titleLarge: title3.copyWith(color: primary),
        titleMedium: headline.copyWith(color: primary),
        titleSmall: subhead.copyWith(color: primary, fontWeight: FontWeight.w600),
        bodyLarge: body.copyWith(color: primary),
        bodyMedium: callout.copyWith(color: primary),
        bodySmall: footnote.copyWith(color: secondary),
        labelLarge: subhead.copyWith(color: primary, fontWeight: FontWeight.w600),
        labelMedium: footnote.copyWith(color: secondary),
        labelSmall: caption.copyWith(color: secondary),
      );
}
