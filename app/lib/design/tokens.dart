import 'package:flutter/material.dart';

/// Color tokens, named as the design's variables (`label/primary` is [labelPrimary]).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bgCanvas,
    required this.surfaceContent,
    required this.surfaceRaised,
    required this.surfaceGlassFallback,
    required this.labelPrimary,
    required this.labelSecondary,
    required this.labelTertiary,
    required this.separator,
    required this.accentFill,
    required this.accentOnFill,
    required this.accentText,
    required this.accentTint,
    required this.markerDestination,
    required this.markerOutline,
    required this.userDot,
    required this.statusOkFill,
    required this.statusOkOn,
    required this.statusTightFill,
    required this.statusTightOn,
    required this.statusLateFill,
    required this.statusLateOn,
    required this.bannerFill,
    required this.glassTint,
    required this.glassTintStrong,
    required this.glassProminentTint,
    required this.glassStroke,
  });

  final Color bgCanvas;
  final Color surfaceContent;
  final Color surfaceRaised;
  final Color surfaceGlassFallback;
  final Color labelPrimary;
  final Color labelSecondary;
  final Color labelTertiary;
  final Color separator;
  final Color accentFill;
  final Color accentOnFill;
  final Color accentText;
  final Color accentTint;
  final Color markerDestination;
  final Color markerOutline;
  final Color userDot;
  final Color statusOkFill;
  final Color statusOkOn;
  final Color statusTightFill;
  final Color statusTightOn;
  final Color statusLateFill;
  final Color statusLateOn;
  final Color bannerFill;
  final Color glassTint;
  final Color glassTintStrong;
  final Color glassProminentTint;
  final Color glassStroke;

  static const light = AppColors(
    bgCanvas: Color(0xFFF2F2F7),
    surfaceContent: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceGlassFallback: Color(0xFFF6F6F9),
    labelPrimary: Color(0xFF000000),
    labelSecondary: Color(0xFF515156),
    labelTertiary: Color(0xFF8A8A90),
    separator: Color(0xFFC6C6C8),
    accentFill: Color(0xFF003C6C),
    accentOnFill: Color(0xFFFFFFFF),
    accentText: Color(0xFF003C6C),
    accentTint: Color(0x24003C6C),
    markerDestination: Color(0xFFFDC700),
    markerOutline: Color(0xFF3A2E00),
    userDot: Color(0xFF007AFF),
    statusOkFill: Color(0xFF1F7A36),
    statusOkOn: Color(0xFFFFFFFF),
    statusTightFill: Color(0xFF9A4A00),
    statusTightOn: Color(0xFFFFFFFF),
    statusLateFill: Color(0xFFC4001A),
    statusLateOn: Color(0xFFFFFFFF),
    bannerFill: Color(0xFFE4EDF7),
    glassTint: Color(0xB8FFFFFF),
    glassTintStrong: Color(0xDBFFFFFF),
    glassProminentTint: Color(0xE6003C6C),
    glassStroke: Color(0xB3FFFFFF),
  );

  static const dark = AppColors(
    bgCanvas: Color(0xFF000000),
    surfaceContent: Color(0xFF1C1C1E),
    surfaceRaised: Color(0xFF2C2C2E),
    surfaceGlassFallback: Color(0xFF2C2C2E),
    labelPrimary: Color(0xFFFFFFFF),
    labelSecondary: Color(0xFFB4B4B9),
    labelTertiary: Color(0xFF8E8E93),
    separator: Color(0xFF38383A),
    accentFill: Color(0xFF78B7F2),
    accentOnFill: Color(0xFF00213B),
    accentText: Color(0xFF7DB9F4),
    accentTint: Color(0x3878B7F2),
    markerDestination: Color(0xFFFDC700),
    markerOutline: Color(0xFF000000),
    userDot: Color(0xFF0A84FF),
    statusOkFill: Color(0xFF30D158),
    statusOkOn: Color(0xFF002A10),
    statusTightFill: Color(0xFFFF9F0A),
    statusTightOn: Color(0xFF2B1700),
    statusLateFill: Color(0xFFFF6961),
    statusLateOn: Color(0xFF3A0006),
    bannerFill: Color(0xFF14283D),
    glassTint: Color(0xC71C1C1E),
    glassTintStrong: Color(0xE01C1C1E),
    glassProminentTint: Color(0xEB78B7F2),
    glassStroke: Color(0x38FFFFFF),
  );

  Color statusFill(String status) => switch (status) {
        'ok' => statusOkFill,
        'tight' => statusTightFill,
        'late' => statusLateFill,
        _ => labelSecondary,
      };

  Color statusOn(String status) => switch (status) {
        'ok' => statusOkOn,
        'tight' => statusTightOn,
        'late' => statusLateOn,
        _ => surfaceContent,
      };

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bgCanvas: mix(bgCanvas, other.bgCanvas),
      surfaceContent: mix(surfaceContent, other.surfaceContent),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceGlassFallback: mix(surfaceGlassFallback, other.surfaceGlassFallback),
      labelPrimary: mix(labelPrimary, other.labelPrimary),
      labelSecondary: mix(labelSecondary, other.labelSecondary),
      labelTertiary: mix(labelTertiary, other.labelTertiary),
      separator: mix(separator, other.separator),
      accentFill: mix(accentFill, other.accentFill),
      accentOnFill: mix(accentOnFill, other.accentOnFill),
      accentText: mix(accentText, other.accentText),
      accentTint: mix(accentTint, other.accentTint),
      markerDestination: mix(markerDestination, other.markerDestination),
      markerOutline: mix(markerOutline, other.markerOutline),
      userDot: mix(userDot, other.userDot),
      statusOkFill: mix(statusOkFill, other.statusOkFill),
      statusOkOn: mix(statusOkOn, other.statusOkOn),
      statusTightFill: mix(statusTightFill, other.statusTightFill),
      statusTightOn: mix(statusTightOn, other.statusTightOn),
      statusLateFill: mix(statusLateFill, other.statusLateFill),
      statusLateOn: mix(statusLateOn, other.statusLateOn),
      bannerFill: mix(bannerFill, other.bannerFill),
      glassTint: mix(glassTint, other.glassTint),
      glassTintStrong: mix(glassTintStrong, other.glassTintStrong),
      glassProminentTint: mix(glassProminentTint, other.glassProminentTint),
      glassStroke: mix(glassStroke, other.glassStroke),
    );
  }
}

extension AppColorsOf on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
}

/// Spacing on a 4 pt grid, and the smallest tap target.
abstract final class Space {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double tapMin = 44;
}

abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double glass = 28;
  static const double pill = 999;
}

/// How strongly a glass surface blurs what is behind it. [sigma] is the Gaussian blur Flutter takes;
/// the design states the blur as a radius, which is twice the sigma.
enum GlassLevel {
  small(16),
  regular(24),
  strong(32);

  const GlassLevel(this.radius);

  final double radius;

  double get sigma => radius / 2;

  List<BoxShadow> get shadow => switch (this) {
        GlassLevel.small => Elevation.glassSmall,
        GlassLevel.regular => Elevation.glassRegular,
        GlassLevel.strong => Elevation.glassStrong,
      };
}

abstract final class Elevation {
  static const raised = [BoxShadow(color: Color(0x14000000), offset: Offset(0, 1), blurRadius: 3)];
  static const glassSmall = [BoxShadow(color: Color(0x24000000), offset: Offset(0, 4), blurRadius: 12)];
  static const glassRegular = [BoxShadow(color: Color(0x29000000), offset: Offset(0, 8), blurRadius: 24)];
  static const glassStrong = [BoxShadow(color: Color(0x2E000000), offset: Offset(0, 12), blurRadius: 32)];
}
