// 环境色板两极性的守卫：暗实例必须与既有基准逐值相同（迁移不得改变环境外观），
// 浅实例必须满足可读性下限，且"填充 + 其上的字"必须成对翻转。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';

double _channelL(double v) {
  return v <= 0.03928
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

double _luminanceOf(double r, double g, double b) {
  return 0.2126 * _channelL(r) + 0.7152 * _channelL(g) + 0.0722 * _channelL(b);
}

/// 前景叠到背景后的对比度（半透明墨色先合成，不把 α 当成独立色）。
/// 背景按不透明处理：其自身 α 由更底层的舞台决定，不在本断言范围内。
double _contrast(Color fg, Color bg) {
  final a = fg.a;
  final l1 = _luminanceOf(
    fg.r * a + bg.r * (1 - a),
    fg.g * a + bg.g * (1 - a),
    fg.b * a + bg.b * (1 - a),
  );
  final l2 = _luminanceOf(bg.r, bg.g, bg.b);
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('暗实例与 MobileEnvColors 逐值相同', () {
    const dark = MobileEnvPalette.dark;
    expect(dark.stage, MobileEnvColors.stage);
    expect(dark.ink, MobileEnvColors.ink);
    expect(dark.inkMuted, MobileEnvColors.inkMuted);
    expect(dark.inkFaint, MobileEnvColors.inkFaint);
    expect(dark.ink40, MobileEnvColors.ink40);
    expect(dark.white52, MobileEnvColors.white52);
    expect(dark.white46, MobileEnvColors.white46);
    expect(dark.white43, MobileEnvColors.white43);
    expect(dark.white70, MobileEnvColors.white70);
    expect(dark.white78, MobileEnvColors.white78);
    expect(dark.line13, MobileEnvColors.line13);
    expect(dark.line10, MobileEnvColors.line10);
    expect(dark.line07, MobileEnvColors.line07);
    expect(dark.line09, MobileEnvColors.line09);
    expect(dark.line15, MobileEnvColors.line15);
    expect(dark.line12, MobileEnvColors.line12);
    expect(dark.accent, MobileEnvColors.accent);
    expect(dark.accentInk, MobileEnvColors.accent);
    expect(dark.onAccent, MobileEnvColors.onAccent);
    expect(dark.onAccentDeep, MobileEnvColors.onAccentDeep);
    expect(dark.segmentBg, MobileEnvColors.segmentBg);
    expect(dark.iconButtonGlass, MobileEnvColors.iconButtonGlass);
    expect(dark.posterPlayBg, MobileEnvColors.posterPlayBg);
    expect(dark.posterPlayFg, MobileEnvColors.posterPlayFg);
    expect(dark.searchOverlayBg, MobileEnvColors.searchOverlayBg);
    expect(dark.surfaceGlass, MobileEnvColors.surfaceGlass);
    expect(dark.surfaceRaised, MobileEnvColors.surfaceRaised);
    expect(dark.navGlass, MobileEnvColors.navGlass);
    expect(dark.sheetSolid, MobileEnvColors.sheetSolid);
    expect(dark.focusGradientStart, MobileEnvColors.focusGradientStart);
    expect(dark.focusGradientEnd, MobileEnvColors.focusGradientEnd);
    expect(dark.avatarBg, MobileEnvColors.avatarBg);
    expect(dark.avatarFg, MobileEnvColors.avatarFg);
    expect(dark.bookMiniBg, MobileEnvColors.bookMiniBg);
    expect(dark.bookMiniFg, MobileEnvColors.bookMiniFg);
    expect(dark.bookMiniSpine, MobileEnvColors.bookMiniSpine);
    expect(dark.folderGlyph, MobileEnvColors.folderGlyph);
    expect(dark.folderGlyphBg, MobileEnvColors.folderGlyphBg);
    expect(dark.storageProgressFill, MobileEnvColors.storageProgressFill);
    expect(dark.storageCloud, MobileEnvColors.storageCloud);
    expect(dark.storageCloudBg, MobileEnvColors.storageCloudBg);
    expect(dark.readerCoverBg, MobileEnvColors.readerCoverBg);
    expect(dark.readerCoverSpine, MobileEnvColors.readerCoverSpine);
    expect(dark.readerCoverFg, MobileEnvColors.readerCoverFg);
    expect(dark.selectionBar, MobileEnvColors.selectionBar);
    expect(dark.onSelectionBar, MobileEnvColors.onSelectionBar);
    expect(dark.buttonInk, MobileEnvColors.buttonInk);
    expect(dark.onButtonInk, MobileEnvColors.onButtonInk);
  });

  test('浅实例的中性墨与表面换成纸面对应物', () {
    const light = MobileEnvPalette.light;
    expect(light.stage, const Color(0xFFF7F8F6));
    expect(light.ink, const Color(0xFF1A1D1B));
    expect(light.accent, MobileEnvColors.accent, reason: '酸绿仍是酸绿，只改用法');
    expect(light.accentInk, const Color(0xFF0B6B61));
    expect(
      light.elevShadow.a,
      lessThan(MobileEnvPalette.dark.elevShadow.a),
      reason: '浅态玻璃面半透明，投影透上来会把卡片染成灰板，必须比暗态淡',
    );
  });

  test('浅实例的墨色族按等对比上调 α，深于同名的暗值比例', () {
    const dark = MobileEnvPalette.dark;
    const light = MobileEnvPalette.light;
    for (final (name, d, l) in [
      ('inkMuted', dark.inkMuted, light.inkMuted),
      ('inkFaint', dark.inkFaint, light.inkFaint),
      ('ink40', dark.ink40, light.ink40),
      ('line25', dark.line25, light.line25),
      ('white43', dark.white43, light.white43),
      ('white70', dark.white70, light.white70),
      ('white78', dark.white78, light.white78),
    ]) {
      expect(l.a, greaterThan(d.a), reason: '$name 在纸面需要更高 α 才能等对比');
    }
  });

  test('两极性的正文墨色与各自舞台底都保持 AA 以上对比', () {
    for (final palette in [MobileEnvPalette.dark, MobileEnvPalette.light]) {
      expect(
        _contrast(palette.ink, palette.stage),
        greaterThan(12),
        reason: '主文字',
      );
      expect(
        _contrast(palette.inkMuted, palette.stage),
        greaterThan(7),
        reason: '次级说明',
      );
      expect(
        _contrast(palette.inkFaint, palette.stage),
        greaterThan(4.5),
        reason: '眉标',
      );
      expect(
        _contrast(palette.accentInk, palette.stage),
        greaterThan(4.5),
        reason: '强调色作文字/图标/细条',
      );
    }
  });

  test('填充与其上的字成对定义，两极性都不出现同色相叠', () {
    for (final palette in [MobileEnvPalette.dark, MobileEnvPalette.light]) {
      expect(
        _contrast(palette.onAccent, palette.accent),
        greaterThan(7),
        reason: '酸绿填充 + 深字',
      );
      expect(
        _contrast(palette.onButtonInk, palette.buttonInk),
        greaterThan(7),
        reason: '主按钮填充与标签',
      );
      expect(
        _contrast(palette.onSelectionBar, palette.selectionBar),
        greaterThan(7),
        reason: '多选条',
      );
      expect(
        _contrast(palette.posterPlayFg, palette.posterPlayBg),
        greaterThan(7),
        reason: '海报播放浮钮',
      );
      expect(_contrast(palette.avatarFg, palette.avatarBg), greaterThan(4.5));
      expect(
        _contrast(palette.ink, palette.sheetSolid),
        greaterThan(12),
        reason: '面板底与正文',
      );
    }
  });

  testWidgets('未注册扩展时一律取暗基准，注册后以注册实例为准', (tester) async {
    late MobileEnvPalette byBrightness;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Builder(
          builder: (context) {
            byBrightness = context.env;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(
      byBrightness,
      MobileEnvPalette.dark,
      reason: '浅色根主题不等于实底浅面：桌面与媒体页仍取暗基准',
    );

    late MobileEnvPalette registered;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: const [MobileEnvPalette.dark],
        ),
        home: Builder(
          builder: (context) {
            registered = context.env;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // MaterialApp 的 AnimatedTheme 会插值主题，未走完时取到的是上一棵树的主题。
    await tester.pumpAndSettle();
    expect(registered, MobileEnvPalette.dark, reason: 'AnimatedTheme 需要走完插值');
  });
}
