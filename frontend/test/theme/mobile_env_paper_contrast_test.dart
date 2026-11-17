import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';

/// 浅极性功能前景的对比度闸门（纸面表 + 摄影表）。
///
/// 浅实例里有几个角色是把暗档粉彩逐字抄过来的（`storageCloud`、`folderGlyph`、
/// `storageProgressFill`），它们在深玻璃上没问题，压在纸面上只有 1.38-1.88:1，
/// 于是 Files 首页的存储卡云图标、四枚分区入口图标和存储进度条在浅色模式下
/// 几乎看不见。
///
/// 这张表钉的是"浅实例作为纸面表，其前景角色必须在纸面上过 AA"这一不变量。
/// `folderGlyph` 当前唯一的落点其实在首页摄影面（深玻璃），那里由
/// `lightPhotographic` 覆盖回粉彩；把它留在闸门里是为了这条不变量——
/// 若哪天去掉那条覆盖，纸面值本身必须是可读的。
///
/// 本闸门同时显式列出**已知的**低于阈值档位：那几档是样例刻意设的弱化层
///（见 `MobileEnvPalette` 类注释的取值规则②），改它们等于改视觉层级，
/// 属于待决的设计取舍而不是笔误，所以记在这里而不是悄悄放宽阈值。
void main() {
  const paper = Color(0xFFF1F4ED); // 样例浅态 sheet 面（.glass-sheet 最终值）

  // 前景角色 -> 取值器。函数字面量不能进 const，故用 final。
  final requiredOnPaper = <String, Color Function(MobileEnvPalette)>{
    'ink': (p) => p.ink,
    'inkMuted': (p) => p.inkMuted,
    'inkFaint': (p) => p.inkFaint,
    'microLabelInk': (p) => p.microLabelInk,
    'groupLabelInk': (p) => p.groupLabelInk,
    'eyebrowInk': (p) => p.eyebrowInk,
    'accentInk': (p) => p.accentInk,
    'statusWarning': (p) => p.statusWarning,
    'statusDanger': (p) => p.statusDanger,
    'folderGlyph': (p) => p.folderGlyph,
    'storageCloud': (p) => p.storageCloud,
    'storageProgressFill': (p) => p.storageProgressFill,
    'appearanceOptionInk': (p) => p.appearanceOptionInk,
    'segmentActiveInk': (p) => p.segmentActiveInk,
    'white52': (p) => p.white52,
    'white70': (p) => p.white70,
    'white78': (p) => p.white78,
  };

  for (final entry in requiredOnPaper.entries) {
    test('浅实例前景角色 ${entry.key} 在纸面上过 AA', () {
      final color = entry.value(MobileEnvPalette.light);
      expect(
        _contrast(color, paper),
        greaterThanOrEqualTo(4.5),
        reason:
            '${entry.key} 压在 $paper 上只有 '
            '${_contrast(color, paper).toStringAsFixed(2)}:1',
      );
    });
  }

  // 刻意弱化的三档：登记实测值，防止"顺手改深"破坏层级，也防止误以为已过线。
  test('弱化档的实测对比度被记录在案', () {
    final light = MobileEnvPalette.light;
    expect(_contrast(light.ink40, paper), closeTo(2.39, 0.05));
    expect(_contrast(light.white43, paper), closeTo(2.60, 0.05));
    expect(_contrast(light.white46, paper), closeTo(4.33, 0.05));
  });

  // 摄影档（`.home-space`）在浅态仍是深玻璃，因此浅实例往纸面推的任何前景
  // 都必须在这张表里被覆盖回去，否则就是暗字压暗底。
  // 这条闸门守的是"改了纸面值却漏改摄影表"这一类回归，不重复上面的纸面检查。
  test('摄影档前景在深玻璃色舱上仍可读', () {
    // 样例深玻璃 rgba(13,28,22,.74) 压在近黑壁纸上的有效底色。
    const glass = Color(0xFF0D1C16);
    final photographic = MobileEnvPalette.lightPhotographic;
    // 图标真正落的那层是它自己的色舱，不是玻璃本身。
    final chip = Color.alphaBlend(photographic.folderGlyphBg, glass);
    final ratio = _contrast(photographic.folderGlyph, chip);
    expect(
      ratio,
      greaterThanOrEqualTo(4.5),
      reason:
          'folderGlyph 在摄影档深玻璃色舱上只有 ${ratio.toStringAsFixed(2)}:1，'
          '说明浅实例往纸面推的值漏覆盖回这张表',
    );
  });

  // 壁纸带尾必须收进面板纸面。浅档原先两端同值 14%，图片一路铺到逐时轨上，
  // 暗档尾部本来就是全不透明 —— 两端同值不衰减这条形状不许回来。
  test('浅档壁纸带尾部收进面板纸面，与暗档同构', () {
    final light = MobileEnvPalette.light;
    expect(light.sceneVeilBottom.a, 1.0, reason: '尾值不透明才收得住图片，半透明尾部等于没有 veil');
    expect(
      light.sceneVeilBottom,
      light.sheetSolid,
      reason: '收进去的那层就是样例 .glass-sheet 的纸面',
    );
    expect(MobileEnvPalette.dark.sceneVeilBottom.a, 1.0);
    // 顶部仍要透光，否则整条壁纸带被糊成平涂。
    expect(light.sceneVeilTop.a, lessThan(0.3));
  });
}

double _contrast(Color foreground, Color background) {
  final blended = Color.alphaBlend(foreground, background);
  final lighter = math.max(
    blended.computeLuminance(),
    background.computeLuminance(),
  );
  final darker = math.min(
    blended.computeLuminance(),
    background.computeLuminance(),
  );
  return (lighter + 0.05) / (darker + 0.05);
}
