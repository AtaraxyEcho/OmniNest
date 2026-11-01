import 'package:flutter/material.dart';

/// 跨功能模块共享的固定色值。
///
/// 只收纳「有明确设计出处、但不随主题扩展变化」的常量；主题语义色仍放在各
/// 模块的 ThemeExtension。此处的值只作为单一来源，调用方不得再抄写字面量。
abstract final class AppThemeColors {
  /// 阅读器底部面板遮罩：稿子 `.sheet-layer` 的 `rgb(15 18 16 / 42%)`。
  /// 稿子另带 `blur(3px)`，正文页为整屏翻页表面，只保留色相。
  static const Color readerScrim = Color(0x6B0F1210);
}
