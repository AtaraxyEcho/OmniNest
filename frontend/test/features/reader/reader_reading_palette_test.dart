import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  test('legacy theme index migrates to a stable palette id', () {
    final settings = ReaderViewSettings.fromJson(const {
      'version': 3,
      'themeIndex': 0,
    });

    expect(settings.paletteId, ReaderReadingPalette.light.id);
    expect(settings.themeIndex, 0);
    expect(settings.toJson()['version'], 7);
    expect(settings.toJson()['paletteId'], 'light');
  });

  test('unknown palette falls back to dark', () {
    final settings = ReaderViewSettings.fromJson(const {
      'version': 4,
      'paletteId': 'missing',
    });

    expect(settings.paletteId, ReaderReadingPalette.dark.id);
    expect(settings.isDark, isTrue);
  });

  test('control surface is opaque in every palette', () {
    // 面板框、顶/底栏和弹出菜单直接压在正文上：半透明的控制层会让正文从控件
    // 底下透出来，而 .withValues(alpha: .97) 覆盖的是 alpha 本身，会把 8% 白
    // 变成 97% 白。
    for (final palette in ReaderReadingPalette.values) {
      expect(palette.controlSurface.a, 1.0, reason: '${palette.id} 的控制层必须是实底');
    }
  });

  test('章序标签在四档纸底上都是可读的微型文本', () {
    // 稿子的 --accent 压在米黄与葱绿纸底上只有 4.1–4.2:1；标签按稿子的
    // 8–11px 密度不放大字号，只能靠把强调色往墨色折算来补齐正文 AA。
    for (final palette in ReaderReadingPalette.values) {
      final settings = ReaderViewSettings(paletteId: palette.id);
      final style = settings.chapterKickerStyle();
      expect(
        _contrast(style.color!, palette.surface),
        greaterThanOrEqualTo(4.5),
        reason: '${palette.id} 的标签字色',
      );
      expect(style.fontSize, 11.0);
      expect(style.fontWeight, FontWeight.w700);
      expect(
        style.letterSpacing,
        closeTo(11.0 * 0.24, 0.001),
        reason: '稿子 .chapter-kicker 的 letter-spacing: .24em',
      );
    }
  });
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
