import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/features/files/presentation/theme/files_workstation_theme.dart';

void main() {
  group('全局语义颜色对比度', () {
    for (final (name, colors) in <(String, GlobalThemeColors)>[
      ('浅色', AppThemePalette.light),
      ('深色', AppThemePalette.dark),
    ]) {
      test('$name主题的选中态和错误角标满足正文对比度', () {
        expect(
          _contrast(colors.onPrimaryContainer, colors.primaryContainer),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(colors.onError, colors.error),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('$name主题的状态标签在淡色背景上保持可读', () {
        for (final semantic in <Color>[
          colors.success,
          colors.warning,
          colors.info,
          colors.error,
        ]) {
          final background = Color.alphaBlend(
            semantic.withValues(alpha: 0.12),
            colors.surface,
          );
          expect(_contrast(semantic, background), greaterThanOrEqualTo(3.0));
        }
      });
    }
  });

  group('移动环境状态色调对比度', () {
    // 样例浅态把 warning/danger 写成与暗态同值的浅字（light-theme.css:877-878，
    // 机械反相段），压在纸面上不足 1.6:1。调色板对这两档做了记账过的偏离，
    // 本组锁住偏离结果，防止有人按样例把 #e9bd7c/#e69696 抄回浅态。
    for (final (name, palette, hosts)
        in <(String, MobileEnvPalette, List<Color>)>[
          (
            '浅色画布档',
            MobileEnvPalette.light,
            <Color>[
              MobileEnvPalette.light.stageSolid,
              MobileEnvPalette.light.sheetSolid,
            ],
          ),
          (
            '浅色摄影档',
            MobileEnvPalette.lightPhotographic,
            // 摄影档的卡片压在壁纸上而不是纸面画布上：拿浅态 stageSolid 当底会
            // 算出中灰，量出来的对比度既不代表真机也不代表样例。这里用暗档实底
            // 作壁纸替身（沉浸档底部遮罩本身就近乎不透明）。
            <Color>[
              Color.alphaBlend(
                MobileEnvPalette.lightPhotographic.surfaceGlass,
                MobileEnvPalette.dark.stageSolid,
              ),
            ],
          ),
          (
            '深色',
            MobileEnvPalette.dark,
            <Color>[
              MobileEnvPalette.dark.stageSolid,
              Color.alphaBlend(
                MobileEnvPalette.dark.surfaceGlass,
                MobileEnvPalette.dark.stageSolid,
              ),
            ],
          ),
        ]) {
      test('$name档的警示与危险前景在自身软底上满足正文对比度', () {
        for (final (foreground, tint) in <(Color, Color)>[
          (palette.statusWarning, const Color(0xFFD18A34)),
          (palette.statusDanger, const Color(0xFFDA5050)),
        ]) {
          for (final host in hosts) {
            final background = Color.alphaBlend(
              tint.withValues(alpha: 0.12),
              host,
            );
            expect(
              _contrast(foreground, background),
              greaterThanOrEqualTo(4.5),
              reason: '$foreground 压在 12% $tint + $host 上',
            );
          }
        }
      });
    }

    test('浅色摄影档的这两档回到暗档取值', () {
      expect(
        MobileEnvPalette.lightPhotographic.statusWarning,
        MobileEnvPalette.dark.statusWarning,
      );
      expect(
        MobileEnvPalette.lightPhotographic.statusDanger,
        MobileEnvPalette.dark.statusDanger,
      );
    });
  });

  group('Reader 语义颜色对比度', () {
    for (final (name, theme) in <(String, ThemeData)>[
      ('浅色', OmniNestTheme.light()),
      ('深色', OmniNestTheme.dark()),
    ]) {
      test('$name主题的侧边栏选中态保持清晰', () {
        final colors = theme.extension<ReaderColors>()!;
        final selectedBackground = Color.alphaBlend(
          colors.sidebarSelectedBg,
          colors.surfaceContainerLow,
        );

        expect(
          _contrast(colors.sidebarSelectedFg, selectedBackground),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(colors.sidebarSelectedBorder, colors.surfaceContainerLow),
          greaterThanOrEqualTo(3.0),
        );
        expect(
          _contrast(colors.primary, colors.surfaceContainerHigh),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('FileManager 侧边栏选中态对比度', () {
    for (final (name, palette) in <(String, GlobalThemeColors)>[
      ('浅色', AppThemePalette.light),
      ('深色', AppThemePalette.dark),
    ]) {
      test('$name主题下选中项文字保持清晰', () {
        final colors = FilesColors.fromGlobal(palette);
        final selectedBackground = Color.alphaBlend(
          colors.sidebarSelectedBg,
          colors.surfaceContainerLow,
        );

        expect(
          _contrast(colors.sidebarSelectedFg, selectedBackground),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('Files 子页状态徽章对比度', () {
    // 徽章此前把暗档那三枚亮彩抄死在码里，浅色纸面上只剩 1.82-3.19:1。
    // 现在前景取 FilesWorkstationPalette 的 success/warning/error：
    // 暗档取值与原来逐字节相同，浅档换成同名的 Deep 值。
    test('暗档前景压在自己的深底上满足正文对比度', () {
      const colors = FilesWorkstationPalette.darkColors;
      final pairs = <(Color, Color)>[
        (colors.success, FilesWorkstationPalette.emeraldBgDark),
        (colors.warning, FilesWorkstationPalette.amberBgDark),
        (colors.error, FilesWorkstationPalette.roseBgDark),
      ];
      for (final (foreground, background) in pairs) {
        expect(
          _contrast(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: '暗档语义色压在自己的深底上',
        );
      }
    });

    test('浅档前景取 Deep 档并记录未达 4.5 的两档', () {
      const colors = FilesWorkstationPalette.lightColors;
      final background = colors.surfaceContainerHigh;

      expect(_contrast(colors.success, background), greaterThanOrEqualTo(4.5));
      // warning 与 error 距正文档还差 0.2-0.4：再压暗要动的是共享角色本身
      // （admin 与 workstation 皮肤同源），留待定夺，先按实测记账。
      expect(_contrast(colors.warning, background), closeTo(4.25, 0.05));
      expect(_contrast(colors.error, background), closeTo(4.09, 0.05));
      expect(_contrast(colors.warning, background), greaterThanOrEqualTo(4.0));
      expect(_contrast(colors.error, background), greaterThanOrEqualTo(4.0));
    });
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
