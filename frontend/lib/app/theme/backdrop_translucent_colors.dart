import 'package:flutter/material.dart';

/// 浅色主题叠加动态背景时使用的烟熏透明色。
///
/// 该色组只负责动态背景上的可读性，不替代各功能模块的品牌色。
abstract final class BackdropTranslucentColors {
  static const Color canvas = Color(0x0010181C);
  static const Color surfaceLow = Color(0x5210181C);
  static const Color surface = Color(0x75131F24);
  static const Color surfaceHigh = Color(0x85172328);
  static const Color surfaceHighest = Color(0x941B292D);
  static const Color primary = Color(0xFF92D8D1);
  static const Color primaryContainer = Color(0xA6264A4A);
  static const Color onPrimary = Color(0xFF082522);
  static const Color onPrimaryContainer = Color(0xFFE8F5F2);
  static const Color tertiary = Color(0xFFE2BE8E);
  static const Color onSurface = Color(0xFFF4F7F5);
  static const Color onSurfaceVariant = Color(0xFFD3DEDA);
  static const Color outline = Color(0x73FFFFFF);
  static const Color outlineVariant = Color(0x2EFFFFFF);
  static const Color shadow = Color(0x8A000000);
}
