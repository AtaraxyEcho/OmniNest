import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/material.dart' show HSVColor;
import 'package:flutter_test/flutter_test.dart';

/// 禁紫色规范（2026-09-10 定夺）：主题层色值不得落在紫色域。
///
/// 判定：HSV 色相 250-320 且饱和度 > 0.25 视为紫。扫描 `lib/app/theme/`
/// 全部 `Color(0xAARRGGBB)` 字面量，未来 accent 调整同样受此约束。
void main() {
  test('主题色板不包含紫色域色值', () {
    final themeDir = Directory('lib/app/theme');
    expect(themeDir.existsSync(), isTrue, reason: '应在 frontend/ 下运行');

    final violations = <String>[];
    final colorLiteral = RegExp(r'Color\((0x[0-9A-Fa-f]{8})\)');
    for (final entity in themeDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      for (final match in colorLiteral.allMatches(source)) {
        final value = int.parse(match.group(1)!);
        final color = Color(value);
        final hsv = HSVColor.fromColor(color);
        final isPurple =
            hsv.hue >= 250 && hsv.hue <= 320 && hsv.saturation > 0.25;
        if (isPurple) {
          violations.add(
            '${entity.path}: 0x${value.toRadixString(16).toUpperCase()} '
            '(hue=${hsv.hue.toStringAsFixed(0)}, '
            'sat=${hsv.saturation.toStringAsFixed(2)})',
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '主题层发现紫色域色值（禁紫规范）:\n${violations.join('\n')}',
    );
  });
}
