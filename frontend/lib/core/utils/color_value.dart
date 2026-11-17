import 'package:flutter/material.dart';

/// 将 RGB 整数（0xRRGGBB）组装为不透明 [Color]。
///
/// 用于用户自定义主题色解析，避免业务代码散落 `0xFF000000 | value` 位运算。
Color colorFromRgbInt(int rgb) {
  return Color(0xFF000000 | (rgb & 0x00FFFFFF));
}

/// 解析 `#RRGGBB` / `RRGGBB` 十六进制颜色；失败时返回 [fallback]。
Color parseHexColor(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) {
    return fallback;
  }
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) {
    return fallback;
  }
  return colorFromRgbInt(value);
}
