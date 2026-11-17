// 环境色板两极性的守卫：暗实例必须与字面快照逐值相同（迁移不得改变环境外观），
// 浅实例必须满足可读性下限，且"填充 + 其上的字"必须成对翻转。
import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  // 暗实例字面快照：环境基准不随系统明暗翻转，迁移与后续改动都不许动这些值。
  // 原先这份基准由 MobileEnvColors 承担，该类是极性表落地前的重复来源，已删。
  test('暗实例逐值等于环境基准快照', () {
    const dark = MobileEnvPalette.dark;
    expect(dark.stage, const Color(0xFF0B1110));
    expect(dark.ink, const Color(0xFFF6F6F2));
    expect(dark.inkMuted, const Color(0xBFF6F6F2));
    expect(dark.inkFaint, const Color(0x94F6F6F2));
    expect(dark.ink40, const Color(0x66F6F6F2));
    expect(dark.white52, const Color(0x85FFFFFF));
    expect(dark.white46, const Color(0x75FFFFFF));
    expect(dark.white43, const Color(0x6EFFFFFF));
    expect(dark.white70, const Color(0xB3FFFFFF));
    expect(dark.white78, const Color(0xC7FFFFFF));
    expect(dark.line13, const Color(0x21FFFFFF));
    expect(dark.line10, const Color(0x1AFFFFFF));
    expect(dark.line07, const Color(0x12FFFFFF));
    expect(dark.line09, const Color(0x17FFFFFF));
    expect(dark.line15, const Color(0x26FFFFFF));
    expect(dark.line12, const Color(0x1FFFFFFF));
    expect(dark.accent, const Color(0xFFD5F17D));
    expect(dark.accent, const Color(0xFFD5F17D));
    expect(dark.onAccent, const Color(0xFF172014));
    expect(dark.onAccentDeep, const Color(0xFF151C13));
    expect(dark.segmentBg, const Color(0xB8141C1A));
    expect(dark.accent, const Color(0xFFD5F17D));
    expect(dark.accent, const Color(0xFFD5F17D));
    expect(dark.onAccent, const Color(0xFF172014));
    expect(dark.accent, const Color(0xFFD5F17D));
    expect(dark.ink, const Color(0xFFF6F6F2));
    expect(dark.onAccentDeep, const Color(0xFF151C13));
    expect(dark.iconButtonGlass, const Color(0x52121817));
    expect(dark.posterPlayBg, const Color(0xE6F9F9F4));
    expect(dark.posterPlayFg, const Color(0xFF101513));
    expect(dark.searchOverlayBg, const Color(0xF00A0F0E));
    expect(dark.surfaceGlass, const Color(0xB8121918));
    expect(dark.surfaceRaised, const Color(0x8F111816));
    expect(dark.navGlass, const Color(0xC70E1413));
    expect(dark.sheetSolid, const Color(0xFF171E1C));
    expect(dark.focusGradientStart, const Color(0xC2101615));
    expect(dark.focusGradientEnd, const Color(0x7D1B2421));
    expect(dark.avatarBg, const Color(0xFFD6C0A9));
    expect(dark.avatarFg, const Color(0xFF2C211A));
    expect(dark.bookMiniBg, const Color(0xFFD8CFB5));
    expect(dark.bookMiniFg, const Color(0xFF27261F));
    expect(dark.bookMiniSpine, const Color(0xFF948F7D));
    expect(dark.folderGlyph, const Color(0xFF91BAF2));
    expect(dark.folderGlyphBg, const Color(0x2B4C84D2));
    expect(dark.storageProgressFill, const Color(0xFF8FB6EC));
    expect(dark.storageCloud, const Color(0xFFB9D2FF));
    expect(dark.storageCloudBg, const Color(0x295D8EE0));
    expect(dark.readerCoverBg, const Color(0xFFD5CCAD));
    expect(dark.readerCoverSpine, const Color(0xFF827D6C));
    expect(dark.readerCoverFg, const Color(0xFF2C2C26));
    expect(dark.selectionBar, const Color(0xFFD9EF91));
    expect(dark.onSelectionBar, const Color(0xFF162014));
    expect(dark.buttonInk, const Color(0xFFF6F6F2));
    expect(dark.onButtonInk, const Color(0xFF141A18));
  });

  test('两极性的各级文字墨色在每张实底承载面上都过 AA', () {
    // 次级说明与眉标不只落在 stage 上，实底面板、指标格、舞台实底都比 stage 更深，
    // 只判 stage 会漏掉真正最差的那张面。玻璃面按壁纸合成，不在本断言范围内。
    final surfaces = <MobileEnvPalette, Map<String, Color>>{
      MobileEnvPalette.dark: {
        'stage': MobileEnvPalette.dark.stage,
        'stageSolid': MobileEnvPalette.dark.stageSolid,
        'sheetSolid': MobileEnvPalette.dark.sheetSolid,
        'metricCell': MobileEnvPalette.dark.metricCell,
      },
      MobileEnvPalette.light: {
        'stage': MobileEnvPalette.light.stage,
        'stageSolid': MobileEnvPalette.light.stageSolid,
        'sheetSolid': MobileEnvPalette.light.sheetSolid,
        'metricCell': MobileEnvPalette.light.metricCell,
        'navGlass': MobileEnvPalette.light.navGlass,
        'canvas': MobileEnvPalette.light.searchOverlayBg,
      },
    };

    for (final polarity in surfaces.entries) {
      final palette = polarity.key;
      expect(
        _contrast(palette.ink, palette.stage),
        greaterThan(12),
        reason: '${palette.brightness} 主文字',
      );
      for (final surface in polarity.value.entries) {
        for (final role
            in {
              'inkMuted': palette.inkMuted,
              'inkFaint': palette.inkFaint,
              'groupLabelInk': palette.groupLabelInk,
              'appearanceOptionInk': palette.appearanceOptionInk,
              'accentInk': palette.accentInk,
            }.entries) {
          expect(
            _contrast(role.value, surface.value),
            greaterThan(4.5),
            reason:
                '${palette.brightness} ${role.key} 压在 ${surface.key} 上'
                '实测 ${_contrast(role.value, surface.value).toStringAsFixed(3)}',
          );
        }
      }
    }
  });

  test('三处 α 是对样例字面量的刻意偏离，闸门只判 RGB 所以必须在这里钉住', () {
    // light_mode_parity_test 把 `_cssToHex` 只取到 r/g/b，α 漂移它抓不到；
    // 样例这几档的 α 压在浅纸上过不了 AA，于是色相照抄、α 单独提档。
    expect(
      MobileEnvPalette.light.inkMuted.a,
      closeTo(0xA3 / 255, 0.001),
      reason: '样例 rgba(23,35,30,.62)=0x9E，为过 AA 提到 0xA3',
    );
    expect(
      MobileEnvPalette.light.groupLabelInk.a,
      closeTo(0x9F / 255, 0.001),
      reason: '样例 rgba(26,29,27,.58)=0x94，提到 0x9F',
    );
    expect(
      MobileEnvPalette.dark.groupLabelInk.a,
      closeTo(0x7C / 255, 0.001),
      reason: '样例 rgba(246,246,242,.43)=0x6E，提到 0x7C',
    );
    // 偏离只允许发生在 α：色相必须仍是样例那一支。
    expect(MobileEnvPalette.light.inkMuted.toARGB32() & 0xFFFFFF, 0x17231E);
    expect(
      MobileEnvPalette.light.groupLabelInk.toARGB32() & 0xFFFFFF,
      0x1A1D1B,
    );
    expect(MobileEnvPalette.dark.groupLabelInk.toARGB32() & 0xFFFFFF, 0xF6F6F2);

    // 天气抽屉那批 7-10px 小字：样例字面量是 --muted（浅 .62，实测压在指标格上
    // 只有 4.68），设备截图上整层发灰；改用样例自己的标签档 --text-secondary
    // .72（实测 6.06）。暗态 --muted 本来就够，不跟着提档。
    expect(
      MobileEnvPalette.light.microLabelInk.a,
      closeTo(0xB8 / 255, 0.001),
      reason: '样例 .weather-metrics small 是 rgba(23,35,30,.62)=0x9E，提到 0xB8',
    );
    expect(
      MobileEnvPalette.dark.microLabelInk.a,
      MobileEnvPalette.dark.inkMuted.a,
      reason: '暗态维持 --muted，避免把已经够强的那一档再推一遍',
    );
    expect(
      _contrast(
        MobileEnvPalette.light.microLabelInk,
        MobileEnvPalette.light.metricCell,
      ),
      greaterThan(5.5),
      reason: '微型标签档在指标格上要比 --muted 明显',
    );
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

  testWidgets('未传 barrierColor 的模态面板，遮罩随注册的极性走', (tester) async {
    // showModalBottomSheet 的遮罩解析链是「显式参数 → bottomSheetTheme
    // .modalBarrierColor → Colors.black54」，全仓 32 处调用里 29 处没传参数，
    // 所以判据必须走真实路由，而不是只看主题字段。
    for (final palette in const [
      MobileEnvPalette.dark,
      MobileEnvPalette.light,
    ]) {
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: palette.brightness,
          ).withEnvPalette(palette),
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        showModalBottomSheet<void>(
          context: hostContext,
          builder: (context) => const SizedBox(height: 80),
        ),
      );
      await tester.pumpAndSettle();

      final barrier = tester.widget<ModalBarrier>(
        find
            .byWidgetPredicate(
              (widget) => widget is ModalBarrier && widget.color != null,
            )
            .first,
      );
      expect(
        barrier.color,
        palette.modalScrim,
        reason: '${palette.brightness} 档的模态遮罩必须来自同一极性',
      );
      expect(barrier.color, isNot(Colors.black54));

      Navigator.of(hostContext, rootNavigator: true).pop();
      await tester.pumpAndSettle();
    }
  });

  test('浅态的强调色只能当填充，当文字或图标会直接看不见', () {
    const light = MobileEnvPalette.light;
    expect(
      _contrast(light.accent, light.stage),
      lessThan(1.6),
      reason: '这就是 accent 当字色必须换成 accentInk 的量依据',
    );
    expect(
      _contrast(light.accentInk, light.stage),
      greaterThan(4.5),
      reason: '同一位置换成墨用法后要过 AA',
    );
    // 暗态两者同值，所以这条换用不会动暗基线。
    expect(MobileEnvPalette.dark.accent, MobileEnvPalette.dark.accentInk);
  });
}
