import 'package:flutter/material.dart';

/// 跨功能模块共享的固定色值。
///
/// 只收纳「有明确设计出处、但不随主题扩展变化」的常量；主题语义色仍放在各
/// 模块的 ThemeExtension。此处的值只作为单一来源，调用方不得再抄写字面量。
abstract final class AppThemeColors {
  /// 阅读器底部面板遮罩：稿子 `.sheet-layer` 的 `rgb(15 18 16 / 42%)`。
  /// 稿子另带 `blur(3px)`，正文页为整屏翻页表面，只保留色相。
  static const Color readerScrim = Color(0x6B0F1210);

  // ---- Files 移动壳层：六组文件类型功能编码色（淡底 + 亮前景） ----

  static const Color filesEnvViolet = Color(0xFFB3A4EF);
  static const Color filesEnvVioletBg = Color(0x267B64D5);
  static const Color filesEnvBlue = Color(0xFF91BAF2);
  static const Color filesEnvBlueBg = Color(0x2B4C84D2);
  static const Color filesEnvRed = Color(0xFFE69696);
  static const Color filesEnvRedBg = Color(0x24DA5050);
  static const Color filesEnvAmber = Color(0xFFE9BD7C);
  static const Color filesEnvAmberBg = Color(0x24D18A34);
  static const Color filesEnvCyan = Color(0xFF7FD5CC);
  static const Color filesEnvCyanBg = Color(0x2436A499);
  static const Color filesEnvGreen = Color(0xFF9BD18D);
  static const Color filesEnvGreenBg = Color(0x244F9E41);

  /// 浅极性同位色：保持色相、压明度，落在浅色色舱底上 ≥4.5:1。
  static const Color filesEnvVioletOnPaper = Color(0xFF6345DE);
  static const Color filesEnvBlueOnPaper = Color(0xFF175EBF);
  static const Color filesEnvRedOnPaper = Color(0xFFBB2D2D);
  static const Color filesEnvAmberOnPaper = Color(0xFF8C5D17);
  static const Color filesEnvCyanOnPaper = Color(0xFF246E66);
  static const Color filesEnvGreenOnPaper = Color(0xFF3B6F2D);

  /// 视频分类信息条前景色（与六组类型舱解耦）。
  static const Color filesVideoCategory = Color(0xFF0EA5E9);

  // ---- Music 沉浸播放器：背景两团环境光晕 ----

  static const Color musicAmbienceRose = Color(0x597E4880);
  static const Color musicAmbienceTeal = Color(0x57396469);
}
