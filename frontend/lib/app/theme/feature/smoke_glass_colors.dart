import 'package:flutter/material.dart';

/// 深色烟熏玻璃 chrome 配色：Portal 视觉面板与 Music 沉浸播放器共用的
/// 「背后有亮壁纸」深色色板。
///
/// 该色组是设计稿 token，Portal 侧 `PortalVisualPalette` 与 Music 侧
/// `MusicImmersivePalette.digital` 取同一组值；业务组件不得再散落字面量。
abstract final class SmokeGlassColors {
  /// 近黑舞台底。
  static const Color background = Color(0xFF071016);

  /// 面板填充（半透明烟青）。
  static const Color surface = Color(0xA6121D25);

  /// 强调控件填充。
  static const Color surfaceStrong = Color(0xD9142029);

  /// 主文字。
  static const Color text = Color(0xFFF4F7F5);

  /// 次级文字（深色壁纸分支）。
  static const Color muted = Color(0xB8DDE8E7);

  /// 冷青强调色。
  static const Color accent = Color(0xFF9FDBE3);

  /// 暖金备用强调色。
  static const Color accentAlt = Color(0xFFD5C27A);

  /// 光晕。
  static const Color glow = Color(0x663D8EA0);
}

/// 浅色主题叠加动态背景时 Portal 视觉面板使用的烟青透明色。
abstract final class PortalBackdropGlassColors {
  /// 面板填充。
  static const Color surface = Color(0x4D0C1920);

  /// 强调控件填充。
  static const Color surfaceStrong = Color(0x7512242B);

  /// 次级文字。
  static const Color muted = Color(0xD1D6E3E1);

  /// 光晕。
  static const Color glow = Color(0x383D8EA0);
}

/// Portal 封面占位的纯色回退（禁渐变规范，按变体取单一纯色）。
abstract final class PortalCoverFallbackColors {
  static const Color deepBlue = Color(0xFF263A66);
  static const Color deepTeal = Color(0xFF244641);
  static const Color deepIndigo = Color(0xFF20233D);
}
