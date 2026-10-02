import 'package:flutter/material.dart';

/// 移动端四空间环境的精确配色（逐值取自 OmniNest Mobile Redesign 原型）。
///
/// 该调色板为环境设计基准：移动壳层与四空间表面固定使用，不随系统
/// 明暗主题翻转；可读性由环境遮罩与半透明表面保证。
abstract final class MobileEnvColors {
  /// 环境舞台底（无壁纸时的底色）。
  static const Color stage = Color(0xFF0B1110);

  /// 主文字色。
  static const Color ink = Color(0xFFF6F6F2);

  /// 主文字 62% 透明度（次级说明）。
  static const Color inkMuted = Color(0xBFF6F6F2);

  /// eyebrow 辅助文字。
  static const Color inkFaint = Color(0x94F6F6F2);

  /// 通知行时间戳（40% 墨色）。
  static const Color ink40 = Color(0x66F6F6F2);

  /// 通用弱化前景。
  static const Color white52 = Color(0x85FFFFFF);
  static const Color white46 = Color(0x75FFFFFF);
  static const Color white43 = Color(0x6EFFFFFF);
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white78 = Color(0xC7FFFFFF);

  /// 发丝线。
  static const Color line13 = Color(0x21FFFFFF);
  static const Color line10 = Color(0x1AFFFFFF);
  static const Color line07 = Color(0x12FFFFFF);
  static const Color line09 = Color(0x17FFFFFF);
  static const Color line15 = Color(0x26FFFFFF);
  static const Color line12 = Color(0x1FFFFFFF);

  /// 强调色（lime）。
  static const Color accent = Color(0xFFD5F17D);

  /// 强调色上的前景。
  static const Color onAccent = Color(0xFF172014);

  /// 强调色上的深文字（分段选中态）。
  static const Color onAccentDeep = Color(0xFF151C13);

  /// 分段条底（rgba(20,28,26,.72)）。
  static const Color segmentBg = Color(0xB8141C1A);

  /// 圆形玻璃动作钮底（样例 .icon-button 的 rgba(18,24,23,.32)）。
  static const Color iconButtonGlass = Color(0x52121817);

  /// 海报播放浮钮底（rgba(249,249,244,.9)）。
  static const Color posterPlayBg = Color(0xE6F9F9F4);
  static const Color posterPlayFg = Color(0xFF101513);

  /// 搜索覆盖层底。
  static const Color searchOverlayBg = Color(0xE60A0F0E);

  /// 玻璃表面族。
  static const Color surfaceGlass = Color(0xB8121918);
  static const Color surfaceRaised = Color(0x8F111816);
  static const Color navGlass = Color(0xC70E1413);
  static const Color sheetSolid = Color(0xFF171E1C);

  /// 焦点续接卡渐变。
  static const Color focusGradientStart = Color(0xC2101615);
  static const Color focusGradientEnd = Color(0x7D1B2421);

  /// 头像底色（米色圆）与前景。
  static const Color avatarBg = Color(0xFFD6C0A9);
  static const Color avatarFg = Color(0xFF2C211A);

  /// 书脊小卡。
  static const Color bookMiniBg = Color(0xFFD8CFB5);
  static const Color bookMiniFg = Color(0xFF27261F);
  static const Color bookMiniSpine = Color(0xFF948F7D);

  /// 文件夹图形。
  static const Color folderGlyph = Color(0xFF91BAF2);
  static const Color folderGlyphBg = Color(0x2B4C84D2);

  /// 存储条进度填充（样例 #8fb6ec，比图标色更深一档）。
  static const Color storageProgressFill = Color(0xFF8FB6EC);

  /// 存储条云图标。
  static const Color storageCloud = Color(0xFFB9D2FF);
  static const Color storageCloudBg = Color(0x295D8EE0);

  /// 书封占位系（阅读续读特写）。
  static const Color readerCoverBg = Color(0xFFD5CCAD);
  static const Color readerCoverSpine = Color(0xFF827D6C);
  static const Color readerCoverFg = Color(0xFF2C2C26);

  /// 多选贴底批量条（lime 实底）。
  static const Color selectionBar = Color(0xFFD9EF91);
  static const Color onSelectionBar = Color(0xFF162014);

  /// 主按钮（横幅内白底按钮）。
  static const Color buttonInk = Color(0xFFF6F6F2);
  static const Color onButtonInk = Color(0xFF141A18);
}
