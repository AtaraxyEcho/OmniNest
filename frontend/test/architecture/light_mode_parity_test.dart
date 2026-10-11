// 浅态配色与样例事实表的对账闸门。
//
// 值只允许存在两份：样例事实表 `tool/light_mode_sample_values.txt`（由设计稿级联
// 最终值导出）与 `MobileEnvPalette`。本测试判两者一致，测试里不再手抄字面量——
// 上一轮反复的根因就是同一批值被抄了第二遍，改样例时测试反而把旧值钉成"正确"。
//
// 只判浅态：暗态实例由 `mobile_env_palette_test` 的「暗实例与 MobileEnvColors
// 逐值相同」钉住不动，事实表的暗列另有语义（组件级值多于调色板角色），不并入。
import 'dart:io';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';

/// 事实表角色 -> 浅态调色板字段。画布档读 `light`，`home` 前缀读摄影档实例。
/// 表里没有对应字段的角色（环境层强度、组件尺寸、非调色板的组件级值）不在
/// 本闸门范围内，由各自的专项测试判。
final Map<String, Color Function(MobileEnvPalette)> _lightRoles = {
  'accent': (p) => p.accent,
  'accentInk': (p) => p.accentInk,
  'ink': (p) => p.ink,
  'inkMuted': (p) => p.inkMuted,
  'notifGroupInk': (p) => p.groupLabelInk,
  'notifGroupLabelInk': (p) => p.groupLabelInk,
  'eyebrowInk': (p) => p.eyebrowInk,
  'homeEyebrowInk': (p) => p.eyebrowInk,
  'platformNoteInk': (p) => p.inkMuted,
  'weatherEnvironmentInk': (p) => p.inkMuted,
  'line13': (p) => p.line13,
  'borderSubtle': (p) => p.line13,
  'stageSolid': (p) => p.stageSolid,
  'surfaceGlass': (p) => p.surfaceGlass,
  'sheetSolid': (p) => p.sheetSolid,
  'navGlass': (p) => p.navGlass,
  'miniPlayer': (p) => p.miniPlayer,
  'segmentBg': (p) => p.segmentBg,
  'segmentActiveBg': (p) => p.segmentActiveBg,
  'appearanceOptionBg': (p) => p.appearanceOptionBg,
  'appearanceOptionBorder': (p) => p.appearanceOptionBorder,
  'appearanceOptionInk': (p) => p.appearanceOptionInk,
  'settingIconBg': (p) => p.settingIconBg,
  'appearanceActive': (p) => p.actionFill,
  'appearanceActiveInk': (p) => p.actionFillInk,
  'settingIconInk': (p) => p.accentInk,
  'segmentActiveInk': (p) => p.segmentActiveInk,
  'segmentBorder': (p) => p.segmentBorder,
  'actionFill': (p) => p.actionFill,
  'actionFillInk': (p) => p.actionFillInk,
  'switchOn': (p) => p.switchOn,
  'selectionBar': (p) => p.selectionBar,
  'onSelectionBar': (p) => p.onSelectionBar,
  'modalScrim': (p) => p.modalScrim,
  'metricCell': (p) => p.metricCell,
  'searchOverlayBg': (p) => p.searchOverlayBg,
  'iconButtonGlass': (p) => p.iconButtonGlass,
  'avatarBg': (p) => p.avatarBg,
  'buttonInk': (p) => p.buttonInk,
  'onButtonInk': (p) => p.onButtonInk,
  'heroGlow': (p) => p.heroGlow,
  'featureHeroStart': (p) => p.featureHeroStart,
  'featureHeroEnd': (p) => p.featureHeroEnd,
  'featureHeroLine': (p) => p.featureHeroLine,
  'featureHeroIconBg': (p) => p.featureHeroIconBg,
  'cardGlow': (p) => p.cardGlow,
  'sheetGlow': (p) => p.sheetGlow,
  'weatherSceneVeil': (p) => p.sceneVeilTop,
  'homeInk': (p) => p.ink,
  'homeCardMutedInk': (p) => p.inkMuted,
  // 摄影档的卡片族：样例第 4 层把首页所有卡片压成同一块深玻璃与白 12% 描边，
  // 这三处上一轮只进了事实表、没进判据，于是浅态首页卡片塌成近白无人报红。
  'homeCardGlass': (p) => p.surfaceGlass,
  'homeCardBorder': (p) => p.line15,
  'homeCardRaised': (p) => p.surfaceRaised,
  'homeCardLine': (p) => p.line10,
  'homeQuickLineBorder': (p) => p.line09,
  'homeFocusStart': (p) => p.focusGradientStart,
  'homeFocusEnd': (p) => p.focusGradientEnd,
  'homeIconButtonGlass': (p) => p.iconButtonGlass,
  'homeIconButtonBorder': (p) => p.line13,
  'homePlayFill': (p) => p.actionFill,
  'homePlayInk': (p) => p.actionFillInk,
};

String _hex(Color color) {
  return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
}

/// 把 `#rrggbb` / `rgba(r,g,b,a)` 解析成与调色板同口径的十六进制串；
/// 渐变、url()、尺寸一类的值返回 null 表示不由本闸门判。
String? _cssToHex(String value) {
  final text = value.trim();
  if (text.startsWith('#')) {
    final hex = text.substring(1);
    if (hex.length == 6) {
      return '#$hex';
    }
    if (hex.length == 3) {
      return '#${hex.split('').map((c) => c + c).join()}';
    }
    return null;
  }
  if (!text.startsWith('rgba(')) {
    return null;
  }
  final parts =
      text
          .replaceFirst('rgba(', '')
          .replaceFirst(')', '')
          .split(',')
          .map((p) => p.trim())
          .toList();
  if (parts.length != 4) {
    return null;
  }
  return '#${_byte(int.parse(parts[0]))}${_byte(int.parse(parts[1]))}${_byte(int.parse(parts[2]))}';
}

String _byte(int v) => v.clamp(0, 255).toRadixString(16).padLeft(2, '0');

void main() {
  test('浅态调色板与样例事实表逐角色一致', () {
    final file = File('tool/light_mode_sample_values.txt');
    expect(
      file.existsSync(),
      isTrue,
      reason: '缺少 tool/light_mode_sample_values.txt（刷新方式见文件头）',
    );

    final mismatches = <String>[];
    var checked = 0;
    for (final raw in file.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final columns = line.split('\t');
      if (columns.length < 4) {
        continue;
      }
      final accessor = _lightRoles[columns[0]];
      if (accessor == null) {
        continue;
      }
      final expected = _cssToHex(columns[2]);
      if (expected == null) {
        continue;
      }
      final palette =
          columns[0].startsWith('home')
              ? MobileEnvPalette.lightPhotographic
              : MobileEnvPalette.light;
      final actual = _hex(accessor(palette));
      checked++;
      if (actual != expected) {
        mismatches.add(
          '${columns[0]} 期望 $expected 实得 $actual —— ${columns[3]}',
        );
      }
    }

    expect(checked, greaterThan(20), reason: '对账角色数过少，说明映射表或事实表被误删');
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });
}
