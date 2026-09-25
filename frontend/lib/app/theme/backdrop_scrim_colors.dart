import 'package:flutter/material.dart';

/// 动态背景可读性遮罩色阶：按 [AppBackdropReadabilityMode] 取三段渐变停点。
///
/// 遮罩均为黑色叠透明度，业务组件不得再散落十六进制字面量。
abstract final class BackdropScrimColors {
  /// minimal 档：顶 / 中 / 底。
  static const Color minimalTop = Color(0x12000000);
  static const Color minimalMid = Color(0x05000000);
  static const Color minimalBottom = Color(0x18000000);

  /// content 档：顶 / 中 / 底。
  static const Color contentTop = Color(0x40000000);
  static const Color contentMid = Color(0x12000000);
  static const Color contentBottom = Color(0x4D000000);

  /// work 档：顶 / 中 / 底。
  static const Color workTop = Color(0xEB000000);
  static const Color workMid = Color(0xE0000000);
  static const Color workBottom = Color(0xF0000000);

  /// immersive 档：顶 / 中 / 底。
  static const Color immersiveTop = Color(0x26000000);
  static const Color immersiveMid = Color(0x08000000);
  static const Color immersiveBottom = Color(0x33000000);
}

/// 动态背景占位与渐变使用的深色底。
abstract final class BackdropStageColors {
  /// 图片加载占位底色。
  static const Color loading = Color(0xFF0A1821);

  /// 完全透明。
  static const Color transparent = Color(0x00000000);

  /// 表面渐变起止。
  static const Color surfaceStart = Color(0xFF0A1821);
  static const Color surfaceEnd = Color(0xFF111927);

  /// 设置面板渐变起止。
  static const Color panelStart = Color(0xFF0B1720);
  static const Color panelEnd = Color(0xFF162234);
}
