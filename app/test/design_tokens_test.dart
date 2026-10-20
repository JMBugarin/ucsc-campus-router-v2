import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/design/theme.dart';
import 'package:ucsc_router/design/tokens.dart';
import 'package:ucsc_router/design/type.dart';

double _lin(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _lum(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double ratio(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

Color over(Color tint, Color back) => Color.alphaBlend(tint, back);

void main() {
  group('colour tokens resolve for each brightness', () {
    test('the light theme carries the light tokens, the dark theme the dark ones', () {
      expect(AppTheme.light().extension<AppColors>(), AppColors.light);
      expect(AppTheme.dark().extension<AppColors>(), AppColors.dark);
      expect(AppTheme.light().brightness, Brightness.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
    });

    test('key values match the design', () {
      expect(AppColors.light.accentFill, const Color(0xFF003C6C));
      expect(AppColors.dark.accentFill, const Color(0xFF78B7F2));
      expect(AppColors.light.bgCanvas, const Color(0xFFF2F2F7));
      expect(AppColors.dark.bgCanvas, const Color(0xFF000000));
      expect(AppColors.dark.glassTint.a, closeTo(0.78, 0.01));
      expect(AppColors.dark.glassTintStrong.a, closeTo(0.88, 0.01));
      expect(AppColors.light.glassTint.a, closeTo(0.72, 0.01));
      expect(AppColors.light.glassTintStrong.a, closeTo(0.86, 0.01));
    });

    testWidgets('context.colors follows the ambient theme', (tester) async {
      late AppColors seen;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(builder: (context) {
          seen = context.colors;
          return const SizedBox();
        }),
      ));
      expect(seen, AppColors.dark);
    });

    test('colours blend between themes', () {
      final mid = AppColors.light.lerp(AppColors.dark, 0.5);
      expect(mid.bgCanvas, Color.lerp(AppColors.light.bgCanvas, AppColors.dark.bgCanvas, 0.5));
      expect(AppColors.light.lerp(null, 0.5), AppColors.light);
    });

    test('status colours are named by word', () {
      expect(AppColors.light.statusFill('late'), AppColors.light.statusLateFill);
      expect(AppColors.dark.statusOn('tight'), AppColors.dark.statusTightOn);
      expect(AppColors.light.statusFill('unknown'), AppColors.light.labelSecondary);
    });
  });

  group('contrast the design promises', () {
    const mapColours = [
      Color(0xFFF1EEE6), Color(0xFFCFE3B9), Color(0xFFAAD3DF), Color(0xFFD9D0C9), Color(0xFFFFFFFF), Color(0xFFF7E08A), Color(0xFFC9C3B6), Color(0xFF5F6B55), // light map
    ];
    const darkMapColours = [
      Color(0xFF20262B), Color(0xFF2B4033), Color(0xFF1E3A4A), Color(0xFF3A3F45), Color(0xFF4A5259), Color(0xFF8A7A3A), Color(0xFF12161A), Color(0xFFA9B4A2),
    ];

    for (final entry in {'light': AppColors.light, 'dark': AppColors.dark}.entries) {
      final c = entry.value;
      test('${entry.key}: text on solid surfaces is at least 4.5:1', () {
        for (final back in [c.surfaceContent, c.bgCanvas, c.surfaceGlassFallback]) {
          expect(ratio(c.labelPrimary, back), greaterThanOrEqualTo(4.5));
          expect(ratio(c.labelSecondary, back), greaterThanOrEqualTo(4.5));
          expect(ratio(c.accentText, back), greaterThanOrEqualTo(4.5));
        }
        expect(ratio(c.accentOnFill, c.accentFill), greaterThanOrEqualTo(4.5));
        for (final s in ['ok', 'tight', 'late']) {
          expect(ratio(c.statusOn(s), c.statusFill(s)), greaterThanOrEqualTo(4.5));
        }
        expect(ratio(c.labelPrimary, c.bannerFill), greaterThanOrEqualTo(4.5));
      });

      test('${entry.key}: text on glass is at least 4.5:1 over the worst map colour', () {
        final maps = entry.key == 'light' ? mapColours : darkMapColours;
        for (final tint in [c.glassTint, c.glassTintStrong]) {
          for (final fg in [c.labelPrimary, c.labelSecondary, c.accentText]) {
            for (final back in maps) {
              expect(ratio(fg, over(tint, back)), greaterThanOrEqualTo(4.5), reason: '$fg on $tint over $back');
            }
          }
        }
        for (final back in maps) {
          expect(ratio(c.accentOnFill, over(c.glassProminentTint, back)), greaterThanOrEqualTo(4.5));
        }
      });
    }
  });

  group('the type ramp', () {
    test('uses the design sizes and line heights', () {
      expect(AppText.display.fontSize, 48);
      expect(AppText.largeTitle.fontSize, 34);
      expect(AppText.body.fontSize, 17);
      expect(AppText.caption.fontSize, 12);
      expect(AppText.body.height, closeTo(22 / 17, 0.001));
      expect(AppText.headline.fontWeight, FontWeight.w600);
      expect(AppText.title1.fontWeight, FontWeight.w700);
    });

    test('feeds the Material roles and takes its colour from the theme', () {
      final t = AppTheme.dark().textTheme;
      expect(t.titleMedium!.fontSize, 17);
      expect(t.titleMedium!.color, AppColors.dark.labelPrimary);
      expect(t.bodySmall!.color, AppColors.dark.labelSecondary);
    });
  });

  group('spacing, radii and glass levels', () {
    test('sit on the 4 pt grid and the glass levels grow', () {
      for (final v in [Space.xxs, Space.xs, Space.sm, Space.md, Space.lg, Space.xl, Space.xxl]) {
        expect(v % 4, 0);
      }
      expect(Space.tapMin, 44);
      expect(Radii.glass, 28);
      expect(GlassLevel.small.sigma, lessThan(GlassLevel.regular.sigma));
      expect(GlassLevel.regular.sigma, lessThan(GlassLevel.strong.sigma));
      expect(GlassLevel.regular.shadow.single.blurRadius, 24);
    });

    test('buttons meet the tap target', () {
      final theme = AppTheme.light();
      expect(theme.textButtonTheme.style!.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(Space.tapMin));
      expect(theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(Space.tapMin));
    });
  });
}
