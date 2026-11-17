import 'package:flutter/material.dart';

/// 跨模块共享的语义严重度色阶。
///
/// 用于天气 AQI 分段、相册回收站/删除确认、分享失败提示等
/// 「状态刻度」场景；业务组件不得再散落十六进制字面量。
abstract final class SeverityColors {
  /// 良好 / 成功。
  static const Color good = Color(0xFF4ADE80);

  /// 良好的低透明度叠色（约 15%）。
  static const Color goodSoft = Color(0x264ADE80);

  /// 良好的中透明度叠色（约 30%）。
  static const Color goodMuted = Color(0x4D4ADE80);

  /// 良好的高透明度叠色（约 70%）。
  static const Color goodFaint = Color(0xB34ADE80);

  /// 注意 / 警告。
  static const Color warning = Color(0xFFFACC15);

  /// 偏高 / 警戒。
  static const Color caution = Color(0xFFFB923C);

  /// 危险 / 失败 / 删除。
  static const Color danger = Color(0xFFEF4444);

  /// 强调型失败提示（玫瑰红）。
  static const Color dangerSoft = Color(0xFFFB7185);
}
