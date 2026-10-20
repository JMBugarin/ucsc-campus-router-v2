import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accentFill,
      onPrimary: c.accentOnFill,
      primaryContainer: c.bannerFill,
      onPrimaryContainer: c.labelPrimary,
      secondary: c.accentFill,
      onSecondary: c.accentOnFill,
      secondaryContainer: c.bannerFill,
      onSecondaryContainer: c.labelPrimary,
      tertiary: c.accentText,
      onTertiary: c.accentOnFill,
      error: c.statusLateFill,
      onError: c.statusLateOn,
      surface: c.surfaceContent,
      onSurface: c.labelPrimary,
      onSurfaceVariant: c.labelSecondary,
      surfaceContainerLowest: c.bgCanvas,
      surfaceContainerLow: c.bgCanvas,
      surfaceContainer: c.surfaceContent,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.surfaceRaised,
      outline: c.separator,
      outlineVariant: c.separator,
      inverseSurface: dark ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E),
      onInverseSurface: dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      inversePrimary: c.accentFill,
      scrim: const Color(0xFF000000),
      shadow: const Color(0xFF000000),
    );
    final text = AppText.textTheme(c.labelPrimary, c.labelSecondary);
    const pill = StadiumBorder();
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [c],
      scaffoldBackgroundColor: c.bgCanvas,
      canvasColor: c.bgCanvas,
      textTheme: text,
      primaryTextTheme: text,
      dividerColor: c.separator,
      dividerTheme: DividerThemeData(color: c.separator, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.labelPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bgCanvas,
        foregroundColor: c.labelPrimary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleTextStyle: AppText.headline.copyWith(color: c.labelPrimary),
      ),
      cardTheme: CardThemeData(
        color: c.surfaceContent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: Space.xxs),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
          side: BorderSide(color: c.separator),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accentFill,
          foregroundColor: c.accentOnFill,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          shape: pill,
          textStyle: AppText.headline,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentText,
          minimumSize: const Size(Space.tapMin, Space.tapMin),
          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
          textStyle: AppText.headline,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.accentText,
          minimumSize: const Size(0, 50),
          side: BorderSide(color: c.separator),
          shape: pill,
          textStyle: AppText.headline,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(Space.tapMin, Space.tapMin), foregroundColor: c.labelPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: c.separator)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: c.separator)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: c.accentFill, width: 2)),
        labelStyle: AppText.body.copyWith(color: c.labelSecondary),
        hintStyle: AppText.body.copyWith(color: c.labelSecondary),
      ),
      listTileTheme: ListTileThemeData(iconColor: c.labelSecondary, textColor: c.labelPrimary, minVerticalPadding: Space.xs),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentFill : c.separator),
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentOnFill : c.surfaceRaised),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accentFill,
        linearTrackColor: c.separator,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(3),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: AppText.subhead.copyWith(color: scheme.onInverseSurface),
        actionTextColor: dark ? AppColors.light.accentText : AppColors.dark.accentText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceContent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.glass)),
        titleTextStyle: AppText.title3.copyWith(color: c.labelPrimary),
        contentTextStyle: AppText.callout.copyWith(color: c.labelPrimary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceContent,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.glass))),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: c.accentTint,
        indicatorShape: pill,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => AppText.caption.copyWith(color: s.contains(WidgetState.selected) ? c.accentText : c.labelSecondary),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.accentText : c.labelSecondary),
        ),
      ),
    );
  }
}
