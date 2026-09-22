import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/feature/music_backdrop_theme.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';

/// 平台账号窗口的配色契约：窗口底与文字必须来自同一份已解析调色板，且对比达标。
///
/// 回归背景：浅色主题叠加深色壁纸时，音乐模块把 onSurface 反出为近白色，而窗口
/// 底曾保持浅色实体值，出现"浅色底 + 白字"的内容全不可见。这里对三种场景分别
/// 锁定窗口底 / 卡片底 / 输入框底与正文色的对比度下限。
void main() {
  // 动态壁纸经应用处理呈深色底，半透明表面按最不利（纯黑）合成计算。

  Color composite(Color foreground) {
    final alpha = foreground.a;
    if (alpha >= 1) {
      return foreground;
    }
    return Color.fromARGB(
      255,
      ((foreground.r * 255) * alpha + 0 * (1 - alpha)).round(),
      ((foreground.g * 255) * alpha + 0 * (1 - alpha)).round(),
      ((foreground.b * 255) * alpha + 0 * (1 - alpha)).round(),
    );
  }

  double relativeLuminance(Color color) {
    double channel(double value) {
      return value <= 0.03928
          ? value / 12.92
          : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  double contrastRatio(Color a, Color b) {
    final la = relativeLuminance(a);
    final lb = relativeLuminance(b);
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  void expectReadable(MusicColors colors) {
    // 4.5:1 是正文可读的通行下限；窗口内正文、次要文字与图标都取这两档色。
    expect(
      contrastRatio(composite(colors.windowSurface), colors.onSurface),
      greaterThanOrEqualTo(4.5),
      reason: '窗口底与正文对比不足',
    );
    expect(
      contrastRatio(composite(colors.windowCard), colors.onSurface),
      greaterThanOrEqualTo(4.5),
      reason: '卡片底与正文对比不足',
    );
    expect(
      contrastRatio(composite(colors.fieldFill), colors.onSurface),
      greaterThanOrEqualTo(4.5),
      reason: '输入框底与正文对比不足',
    );
    expect(
      contrastRatio(composite(colors.windowSurface), colors.onSurfaceVariant),
      greaterThanOrEqualTo(3),
      reason: '窗口底与次要文字对比不足',
    );
  }

  test('浅色实体主题下窗口内容可读', () {
    expectReadable(MusicColors.fromGlobal(AppThemePalette.light));
  });

  test('深色实体主题下窗口内容可读', () {
    expectReadable(MusicColors.fromGlobal(AppThemePalette.dark));
  });

  test('浅色主题叠加动态壁纸时窗口随之进入深色玻璃且内容可读', () {
    final lightTheme = ThemeData(
      brightness: Brightness.light,
      extensions: <ThemeExtension<dynamic>>[
        MusicColors.fromGlobal(AppThemePalette.light),
      ],
    );
    final resolved = MusicBackdropTheme.resolve(
      lightTheme,
      backdropActive: true,
    );
    final colors = resolved.extension<MusicColors>()!;

    // 回归断言：窗口底必须与文字同族。此前 windowSurface 保持浅色而 onSurface
    // 已反为近白，实际对比只有约 1.16:1。
    expect(colors.onSurface, isNot(colors.windowSurface));
    expectReadable(colors);
  });
}
