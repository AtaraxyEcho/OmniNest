import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';

void main() {
  test('暗色相册媒体叠层文字使用浅白色', () {
    final colors = PhotosColors.fromGlobal(AppThemePalette.dark);

    expect(colors.mediaOverlayText, const Color(0xFFF6FAF7));
    expect(colors.badgeText, AppThemePalette.dark.badgeText);
    expect(
      ThemeData.estimateBrightnessForColor(colors.mediaOverlayText),
      Brightness.light,
    );
  });

  for (final (name, palette) in [
    ('浅色', AppThemePalette.light),
    ('深色', AppThemePalette.dark),
  ]) {
    test('$name主题的 Photos 强调色按钮满足正文对比度', () {
      final colors = PhotosColors.fromGlobal(palette);

      expect(
        _contrast(colors.onPrimaryContainer, colors.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}

double _contrast(Color foreground, Color background) {
  final lighter = math.max(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  final darker = math.min(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  return (lighter + 0.05) / (darker + 0.05);
}
